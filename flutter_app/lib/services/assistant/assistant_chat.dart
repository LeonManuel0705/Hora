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
  StreamSubscription<String>? _subscription;
  Completer<void>? _done;
  bool _disposed = false;

  ChatPhase get phase => _phase;

  bool get busy => _phase != ChatPhase.idle;

  bool get usesModel => runtime != null;

  Future<void> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty || busy) return;
    entries.add(ChatEntry(role: ChatRole.user, text: question));
    _setPhase(ChatPhase.thinking);

    final answer = _answer;
    if (answer != null) {
      final response = await answer(question);
      if (_disposed) return;
      entries.add(ChatEntry(role: ChatRole.assistant, text: response.text, source: response.source, online: response.online));
      _setPhase(ChatPhase.idle);
      return;
    }

    final exact = await _exact!(question);
    if (_disposed) return;
    if (exact != null) {
      entries.add(ChatEntry(role: ChatRole.assistant, text: exact.text, source: exact.source, online: exact.online));
      _setPhase(ChatPhase.idle);
      return;
    }
    await _generate(question);
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

  Future<void> _generate(String question) async {
    final model = runtime!;
    final path = _modelPath!();
    final history = _history();
    final reply = ChatEntry(role: ChatRole.assistant, local: true, streaming: true, question: question, source: AssistantSource.unknown);
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
      _system ??= await _systemPrompt!();
    } catch (_) {
      _system = '';
    }
    if (_disposed) return;

    final done = Completer<void>();
    _done = done;
    String? failure;
    _subscription = model.reply(path: path, system: _system!, history: history, message: question).listen(
      (delta) {
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
    await done.future;
    _subscription = null;
    _done = null;
    if (_disposed) return;
    _finish(reply, failure: failure);
  }

  void _finish(ChatEntry reply, {String? failure}) {
    reply.streaming = false;
    reply.text = reply.text.trim();
    if (failure != null && reply.text.isEmpty) {
      reply
        ..failed = true
        ..text = failure;
    } else if (reply.text.isEmpty) {
      reply.text = 'Abgebrochen.';
    }
    _setPhase(ChatPhase.idle);
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
    if (_phase == ChatPhase.idle) return;
    runtime?.stop();
    if (_phase == ChatPhase.loadingModel || _phase == ChatPhase.thinking) {
      final subscription = _subscription;
      _subscription = null;
      unawaited(subscription?.cancel());
      final done = _done;
      if (done != null && !done.isCompleted) done.complete();
    }
  }

  void clear() {
    stop();
    unawaited(_subscription?.cancel());
    _subscription = null;
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
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  static const loadFailedText =
      'Das Sprachmodell ließ sich gerade nicht starten. Schließ andere Apps und versuch es noch einmal.';
  static const loadGaveUpText =
      'Das Sprachmodell ist auf diesem Handy schon zweimal beim Start abgestürzt, vermutlich weil der '
      'Arbeitsspeicher knapp war. Schließ andere Apps und versuch es noch einmal. Der Assistent startet dann '
      'in einem sparsameren Modus.';
  static const replyFailedText = 'Bei der Antwort ist etwas schiefgegangen. Versuch es noch einmal.';
}
