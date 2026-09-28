// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'assistant_engine.dart';
import 'local_model/local_llm.dart';
import 'local_model/model_runtime.dart';

enum ChatRole { user, assistant }

enum ChatPhase { idle, thinking, loadingModel, streaming }

class ChatEntry {
  ChatEntry({
    required this.role,
    this.text = '',
    this.source,
    this.online = false,
    this.local = false,
    this.streaming = false,
    this.failed = false,
    this.question,
  });

  final ChatRole role;
  String text;
  AssistantSource? source;
  bool online;
  bool local;
  bool streaming;
  bool failed;
  final String? question;
}

typedef OfflineAnswer = Future<AssistantResponse?> Function(String message);
typedef OnlineAnswer = Future<AssistantResponse> Function(String message);
typedef SystemPromptBuilder = Future<String> Function();

class AssistantChat extends ChangeNotifier {
  AssistantChat.basic({required OnlineAnswer answer})
      : _answer = answer,
        _exact = null,
        runtime = null,
        _modelPath = null,
        _systemPrompt = null;

  AssistantChat.local({
    required ModelRuntime this.runtime,
    required String? Function() modelPath,
    required OfflineAnswer exact,
    required SystemPromptBuilder systemPrompt,
  })  : _answer = null,
        _exact = exact,
        _modelPath = modelPath,
        _systemPrompt = systemPrompt {
    runtime!.addListener(_runtimeChanged);
  }

  final ModelRuntime? runtime;
  final OnlineAnswer? _answer;
  final OfflineAnswer? _exact;
  final String? Function()? _modelPath;
  final SystemPromptBuilder? _systemPrompt;

  static const historyLimit = 16;

  final List<ChatEntry> entries = [];
  ChatPhase _phase = ChatPhase.idle;
  String? _system;
  _Ask? _ask;
  bool _disposed = false;

  ChatPhase get phase => _phase;

  bool get busy => _phase != ChatPhase.idle;

  bool get usesModel => runtime != null;

  Future<void> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty || busy) return;
    final run = _Ask();
    _ask = run;
    entries.add(ChatEntry(role: ChatRole.user, text: question));
    _setPhase(ChatPhase.thinking);
    try {
      final answer = _answer;
      if (answer != null) {
        final response = await answer(question);
        if (_disposed || run.stopped) return;
        entries.add(ChatEntry(role: ChatRole.assistant, text: response.text, source: response.source, online: response.online));
        return;
      }
      AssistantResponse? exact;
      try {
        exact = await run.unlessStopped<AssistantResponse?>(_exact!(question));
      } catch (_) {
        exact = null;
      }
      if (_disposed) return;
      if (run.stopped) {
        entries.add(ChatEntry(role: ChatRole.assistant, text: stoppedText));
        return;
      }
      if (exact != null) {
        entries.add(ChatEntry(role: ChatRole.assistant, text: exact.text, source: exact.source, online: exact.online));
        return;
      }
      await _generate(question, run);
    } catch (_) {
      if (!_disposed) {
        entries.add(ChatEntry(role: ChatRole.assistant, text: replyFailedText, failed: true, question: question));
      }
    } finally {
      if (identical(_ask, run)) _ask = null;
      if (!_disposed) _setPhase(ChatPhase.idle, force: true);
    }
  }

  Future<void> retry(ChatEntry failed) async {
    if (busy || !failed.failed || failed.question == null) return;
    final index = entries.indexOf(failed);
    if (index < 0) return;
    entries.removeAt(index);
    if (index > 0 && entries[index - 1].role == ChatRole.user && entries[index - 1].text == failed.question) {
      entries.removeAt(index - 1);
    }
    final model = runtime;
    if (model != null && failed.text == loadGaveUpText) await model.resetCrashGuard();
    notifyListeners();
    await ask(failed.question!);
  }

  Future<void> _generate(String question, _Ask run) async {
    final model = runtime!;
    final path = _modelPath!();
    final history = _history();
    final reply = ChatEntry(
      role: ChatRole.assistant,
      local: true,
      streaming: true,
      question: question,
      source: AssistantSource.unknown,
    );
    entries.add(reply);
    if (!model.isLoaded) {
      _system = null;
      _setPhase(ChatPhase.loadingModel);
    } else {
      notifyListeners();
    }
    if (path == null) {
      _finish(reply, failure: loadFailedText);
      return;
    }
    try {
      _system ??= await run.unlessStopped<String>(_systemPrompt!());
    } catch (_) {
      _system = '';
    }
    if (_disposed) return;
    if (run.stopped) {
      _finish(reply);
      return;
    }

    final done = Completer<void>();
    String? failure;
    final subscription = model.reply(path: path, system: _system!, history: history, message: question).listen(
      (delta) {
        if (run.stopped) return;
        reply.text += delta;
        if (_phase != ChatPhase.streaming) {
          _setPhase(ChatPhase.streaming);
        } else {
          notifyListeners();
        }
      },
      onError: (Object error) {
        failure = error is ModelLoadException
            ? (error.gaveUp ? loadGaveUpText : loadFailedText)
            : replyFailedText;
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    run.onStop = () {
      unawaited(subscription.cancel());
      if (!done.isCompleted) done.complete();
    };
    await done.future;
    run.onStop = null;
    if (_disposed) {
      unawaited(subscription.cancel());
      return;
    }
    _finish(reply, failure: run.stopped ? null : failure);
  }

  void _finish(ChatEntry reply, {String? failure}) {
    reply.streaming = false;
    reply.text = reply.text.trim();
    if (failure != null && reply.text.isEmpty) {
      reply
        ..failed = true
        ..text = failure;
    } else if (reply.text.isEmpty) {
      reply.text = stoppedText;
    }
  }

  List<LlmTurn> _history() {
    final turns = <LlmTurn>[];
    for (final entry in entries.take(entries.length - 1)) {
      if (entry.failed || entry.text.isEmpty) continue;
      turns.add(LlmTurn(fromUser: entry.role == ChatRole.user, text: entry.text));
    }
    if (turns.length <= historyLimit) return turns;
    final trimmed = turns.sublist(turns.length - historyLimit);
    return trimmed.first.fromUser ? trimmed : trimmed.sublist(1);
  }

  void stop() {
    final run = _ask;
    if (run == null || run.stopped) return;
    run.stop();
  }

  void clear() {
    stop();
    entries.clear();
    _system = null;
    _setPhase(ChatPhase.idle, force: true);
  }

  void _runtimeChanged() {
    final activity = runtime?.activity;
    if (_phase == ChatPhase.loadingModel && activity == ModelActivity.generating) {
      _setPhase(ChatPhase.thinking);
    }
  }

  void _setPhase(ChatPhase phase, {bool force = false}) {
    if (_disposed) return;
    if (_phase == phase && !force) {
      notifyListeners();
      return;
    }
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    runtime?.removeListener(_runtimeChanged);
    _ask?.stop();
    super.dispose();
  }

  static const stoppedText = 'Abgebrochen.';
  static const loadFailedText =
      'Das Sprachmodell ließ sich gerade nicht starten. Schließ andere Apps und versuch es noch einmal.';
  static const loadGaveUpText =
      'Der Assistent hat gerade nicht genug Arbeitsspeicher, um das Sprachmodell zu starten. '
      'Schließ andere Apps und versuch es dann noch einmal.';
  static const replyFailedText = 'Bei der Antwort ist etwas schiefgegangen. Versuch es noch einmal.';
}

class _Ask {
  final _signal = Completer<void>();
  bool stopped = false;
  void Function()? onStop;

  void stop() {
    if (stopped) return;
    stopped = true;
    _signal.complete();
    onStop?.call();
  }

  Future<T?> unlessStopped<T>(Future<T> work) {
    if (stopped) {
      unawaited(work.then((_) {}, onError: (_) {}));
      return Future<T?>.value(null);
    }
    return Future.any<T?>([work, _signal.future.then((_) => null)]);
  }
}
