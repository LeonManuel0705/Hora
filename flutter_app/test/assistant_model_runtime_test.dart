// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:app/services/assistant/assistant_chat.dart';
import 'package:app/services/assistant/assistant_engine.dart';
import 'package:app/services/assistant/local_model/local_llm.dart';
import 'package:app/services/assistant/local_model/model_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements RuntimeStore {
  int storedLevel = 0;
  String? storedInflight;
  final inflightHistory = <String?>[];

  @override
  Future<int> level() async => storedLevel;

  @override
  Future<void> setLevel(int level) async => storedLevel = level;

  @override
  Future<String?> inflight() async => storedInflight;

  @override
  Future<void> setInflight(String? value) async {
    storedInflight = value;
    inflightHistory.add(value);
  }
}

class _Llm implements LocalLlm {
  _Llm(this.log);

  final List<String> log;
  bool loaded = false;
  Object? loadError;
  LlmSettings? settings;
  List<String> deltas = const ['Hallo', ' zusammen', '!'];
  Completer<void>? gate;
  bool stopped = false;
  List<LlmTurn>? lastHistory;
  String? lastSystem;

  @override
  bool get isLoaded => loaded;

  @override
  Future<void> load(String path, LlmSettings settings) async {
    log.add('load');
    this.settings = settings;
    final error = loadError;
    if (error != null) throw error;
    loaded = true;
  }

  @override
  Stream<String> reply({required String system, required List<LlmTurn> history, required String message}) async* {
    log.add('reply:$message');
    lastHistory = history;
    lastSystem = system;
    for (final delta in deltas) {
      final wait = gate;
      if (wait != null) await wait.future;
      if (stopped) return;
      yield delta;
    }
  }

  @override
  void stop() => stopped = true;

  @override
  Future<void> unload() async {
    log.add('unload');
    loaded = false;
  }
}

void main() {
  late _Store store;
  late List<String> log;
  late List<_Llm> created;
  Object? failLoads;

  ModelRuntime runtime({Duration idle = const Duration(minutes: 3), String session = 'now', Object? loadError}) {
    failLoads = loadError;
    return ModelRuntime(
      create: () {
        final llm = _Llm(log)..loadError = failLoads;
        created.add(llm);
        return llm;
      },
      store: store,
      gpuPreferred: true,
      idleTimeout: idle,
      session: session,
    );
  }

  setUp(() {
    store = _Store();
    log = [];
    created = [];
    failLoads = null;
  });

  group('runtime', () {
    test('marks the load while it runs and clears it afterwards', () async {
      final model = runtime();
      await model.load('/models/a.gguf');
      expect(model.isLoaded, isTrue);
      expect(model.activity, ModelActivity.ready);
      expect(store.inflightHistory, ['now', null]);
      expect(created.single.settings!.gpu, isTrue);
      model.dispose();
    });

    test('a crash during the last load or answer moves to the careful settings', () async {
      store.storedInflight = 'earlier';
      final model = runtime();
      await model.load('/models/a.gguf');
      expect(store.storedLevel, 1);
      expect(created.single.settings!.gpu, isFalse);
      expect(created.single.settings!.contextSize, 2048);
      model.dispose();
    });

    test('after two crashes it gives up until the user asks again', () async {
      store
        ..storedLevel = 1
        ..storedInflight = 'earlier';
      final model = runtime();
      await expectLater(
        model.load('/models/a.gguf'),
        throwsA(isA<ModelLoadException>().having((e) => e.gaveUp, 'gaveUp', isTrue)),
      );
      expect(created, isEmpty);

      await model.resetCrashGuard();
      await model.load('/models/a.gguf');
      expect(model.isLoaded, isTrue);
      expect(created.single.settings!.contextSize, 2048);
      model.dispose();
    });

    test('a failed load is reported and leaves no marker', () async {
      final model = runtime(loadError: StateError('broken'));
      await expectLater(
        model.load('/models/a.gguf'),
        throwsA(isA<ModelLoadException>().having((e) => e.gaveUp, 'gaveUp', isFalse)),
      );
      expect(store.storedInflight, isNull);
      expect(model.activity, ModelActivity.idle);
      model.dispose();
    });

    test('a GPU start that fails is tried once more on the CPU', () async {
      var attempts = 0;
      final model = ModelRuntime(
        create: () {
          final llm = _Llm(log);
          if (attempts++ == 0) llm.loadError = StateError('metal');
          created.add(llm);
          return llm;
        },
        store: store,
        gpuPreferred: true,
        session: 'now',
      );
      await model.load('/models/a.gguf');
      expect(model.isLoaded, isTrue);
      expect(created.map((llm) => llm.settings!.gpu), [true, false]);
      expect(store.storedInflight, isNull);
      model.dispose();
    });

    test('loads lazily on the first answer and unloads when idle', () async {
      final model = runtime(idle: const Duration(milliseconds: 30));
      final text = await model
          .reply(path: '/models/a.gguf', system: 'sys', history: const [], message: 'Hi')
          .join();
      expect(text, 'Hallo zusammen!');
      expect(log, ['load', 'reply:Hi']);
      expect(store.storedInflight, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(model.isLoaded, isFalse);
      expect(log.last, 'unload');
      model.dispose();
    });

    test('going to the background unloads once the answer is done', () async {
      final model = runtime();
      await model.load('/models/a.gguf');
      model.setBackground(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(model.isLoaded, isFalse);
      model.dispose();
    });
  });

  group('chat', () {
    late ModelRuntime model;
    late AssistantChat chat;
    var contextBuilds = 0;

    setUp(() {
      contextBuilds = 0;
      model = runtime();
      chat = AssistantChat.local(
        runtime: model,
        modelPath: () => '/models/a.gguf',
        exact: (message) async => message == '2+2'
            ? const AssistantResponse(text: '**4**', source: AssistantSource.math)
            : null,
        systemPrompt: () async {
          contextBuilds++;
          return 'Kontext $contextBuilds';
        },
      );
    });

    tearDown(() {
      chat.dispose();
      model.dispose();
    });

    test('exact questions never wake the model', () async {
      await chat.ask('2+2');
      expect(chat.entries.last.text, '**4**');
      expect(chat.entries.last.source, AssistantSource.math);
      expect(log, isEmpty);
    });

    test('everything else streams from the model with the history of the chat', () async {
      final phases = <ChatPhase>[];
      chat.addListener(() => phases.add(chat.phase));
      await chat.ask('2+2');
      await chat.ask('Erklär mir Vektoren');
      final reply = chat.entries.last;
      expect(reply.text, 'Hallo zusammen!');
      expect(reply.local, isTrue);
      expect(reply.streaming, isFalse);
      expect(phases, containsAllInOrder([ChatPhase.loadingModel, ChatPhase.streaming, ChatPhase.idle]));
      final history = created.single.lastHistory!;
      expect(history.map((turn) => turn.text), ['2+2', '**4**']);
      expect(created.single.lastSystem, 'Kontext 1');

      await chat.ask('Und noch mal?');
      expect(created.single.lastHistory!.map((turn) => turn.text).toList(),
          ['2+2', '**4**', 'Erklär mir Vektoren', 'Hallo zusammen!']);
      expect(contextBuilds, 1);
    });

    test('stop keeps what was written so far', () async {
      final llm = _Llm(log)..gate = Completer<void>();
      final stoppable = ModelRuntime(create: () => llm, store: store, gpuPreferred: false, session: 'now');
      final stopChat = AssistantChat.local(
        runtime: stoppable,
        modelPath: () => '/models/a.gguf',
        exact: (_) async => null,
        systemPrompt: () async => '',
      );
      final asking = stopChat.ask('Schreib eine lange Geschichte');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      llm.gate!.complete();
      llm.gate = null;
      await Future<void>.delayed(Duration.zero);
      stopChat.stop();
      await asking;
      expect(stopChat.phase, ChatPhase.idle);
      expect(stopChat.entries.last.failed, isFalse);
      expect(stopChat.entries.last.text, isNotEmpty);
      stopChat.dispose();
      stoppable.dispose();
    });

    test('a model that fails to start shows a retry and the retry asks again', () async {
      final failing = runtime(loadError: StateError('oom'));
      final failingChat = AssistantChat.local(
        runtime: failing,
        modelPath: () => '/models/a.gguf',
        exact: (_) async => null,
        systemPrompt: () async => '',
      );
      await failingChat.ask('Hilf mir beim Lernen');
      final entry = failingChat.entries.last;
      expect(entry.failed, isTrue);
      expect(entry.text, AssistantChat.loadFailedText);
      expect(entry.question, 'Hilf mir beim Lernen');

      failLoads = null;
      await failingChat.retry(entry);
      expect(failingChat.entries.where((e) => e.failed), isEmpty);
      expect(failingChat.entries, hasLength(2));
      failingChat.dispose();
      failing.dispose();
    });

    test('clear starts a new chat with a fresh context', () async {
      await chat.ask('Hallo');
      chat.clear();
      expect(chat.entries, isEmpty);
      await chat.ask('Hallo');
      expect(contextBuilds, 2);
    });
  });
}
