// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:app/services/assistant/local_model/model_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'assistant_model_fakes.dart';

void main() {
  late RuntimeHarness h;

  setUp(() => h = RuntimeHarness());

  Stream<String> ask(ModelRuntime model, [String message = 'Hi']) =>
      model.reply(path: '/models/a.gguf', system: 'sys', history: const [], message: message);

  group('runtime', () {
    test('marks the load while it runs and clears it afterwards', () async {
      final model = h.runtime();
      await model.load('/models/a.gguf');
      expect(model.isLoaded, isTrue);
      expect(model.activity, ModelActivity.ready);
      expect(h.store.inflightHistory, ['now', null]);
      expect(h.created.single.settings!.gpu, isTrue);
      model.dispose();
    });

    test('a crash during the last load or first answer moves to the careful settings', () async {
      h.store.storedInflight = 'earlier';
      final model = h.runtime();
      await model.load('/models/a.gguf');
      expect(h.store.storedLevel, 1);
      expect(h.created.single.settings!.gpu, isFalse);
      expect(h.created.single.settings!.contextSize, 2048);
      model.dispose();
    });

    test('after two crashes it waits for the user, and an explicit retry starts over normally', () async {
      h.store
        ..storedLevel = 1
        ..storedInflight = 'earlier';
      final model = h.runtime();
      await expectLater(
        model.load('/models/a.gguf'),
        throwsA(isA<ModelLoadException>().having((e) => e.gaveUp, 'gaveUp', isTrue)),
      );
      expect(h.created, isEmpty);

      await model.resetCrashGuard();
      expect(h.store.storedLevel, 0);
      await model.load('/models/a.gguf');
      expect(model.isLoaded, isTrue);
      expect(h.created.single.settings!.contextSize, 4096);
      expect(h.created.single.settings!.gpu, isTrue);
      model.dispose();
    });

    test('only the first answer after a load is watched, until its first token', () async {
      h.replyGate = Completer<void>();
      final model = h.runtime();
      final first = <String>[];
      final firstDone = ask(model).listen(first.add).asFuture<void>();
      await settle();
      expect(model.activity, ModelActivity.generating);
      expect(h.store.storedInflight, 'now');
      h.replyGate!.complete();
      await firstDone;
      expect(first.join(), 'Hallo zusammen!');
      expect(h.store.storedInflight, isNull);

      h.created.single.gate = Completer<void>();
      final second = ask(model, 'Noch was').listen((_) {});
      await settle();
      expect(model.activity, ModelActivity.generating);
      expect(h.store.storedInflight, isNull);
      h.created.single.gate!.complete();
      await second.asFuture<void>();
      model.dispose();
    });

    test('a kill later in an answer or while idle is not counted as a crash', () async {
      final model = h.runtime();
      await ask(model).join();
      expect(h.store.storedInflight, isNull);
      model.dispose();

      final next = h.runtime(session: 'later');
      await next.load('/models/a.gguf');
      expect(h.store.storedLevel, 0);
      next.dispose();
    });

    test('going to the background clears the marker and returning while loading sets it again', () async {
      h.loadGate = Completer<void>();
      final model = h.runtime();
      final loading = model.load('/models/a.gguf');
      await settle();
      expect(h.store.storedInflight, 'now');
      model.setBackground(true);
      await settle();
      expect(h.store.storedInflight, isNull);
      model.setBackground(false);
      await settle();
      expect(h.store.storedInflight, 'now');
      h.loadGate!.complete();
      await loading;
      expect(h.store.storedInflight, isNull);
      model.dispose();
    });

    test('a few clean starts bring the careful level back to normal', () async {
      h.store.storedLevel = 1;
      final model = h.runtime();
      for (var i = 0; i < ModelRuntime.cleanRunsToRecover; i++) {
        await ask(model).join();
        await model.unload();
      }
      expect(h.store.storedLevel, 0);
      expect(h.store.storedCleanRuns, 0);
      model.dispose();
    });

    test('a failed load is reported and leaves no marker', () async {
      final model = h.runtime(loadError: StateError('broken'));
      await expectLater(
        model.load('/models/a.gguf'),
        throwsA(isA<ModelLoadException>().having((e) => e.gaveUp, 'gaveUp', isFalse)),
      );
      expect(h.store.storedInflight, isNull);
      expect(model.activity, ModelActivity.idle);
      model.dispose();
    });

    test('a GPU start that fails is tried once more on the CPU', () async {
      var attempts = 0;
      final model = ModelRuntime(
        create: () {
          final llm = FakeLlm(h.log);
          if (attempts++ == 0) llm.loadError = StateError('metal');
          h.created.add(llm);
          return llm;
        },
        store: h.store,
        gpuPreferred: true,
        session: 'now',
      );
      await model.load('/models/a.gguf');
      expect(model.isLoaded, isTrue);
      expect(h.created.map((llm) => llm.settings!.gpu), [true, false]);
      expect(h.store.storedInflight, isNull);
      model.dispose();
    });

    test('loads lazily on the first answer and unloads when idle', () async {
      final model = h.runtime(idle: const Duration(milliseconds: 30));
      final text = await ask(model).join();
      expect(text, 'Hallo zusammen!');
      expect(h.log, ['load', 'reply:Hi']);
      expect(h.store.storedInflight, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(model.isLoaded, isFalse);
      expect(h.log.last, 'unload');
      model.dispose();
    });

    test('going to the background unloads once the answer is done', () async {
      final model = h.runtime();
      await model.load('/models/a.gguf');
      model.setBackground(true);
      await settle();
      expect(model.isLoaded, isFalse);
      model.dispose();
    });

    test('leaving the screen waits for the running answer before it unloads', () async {
      h.replyGate = Completer<void>();
      final model = h.runtime();
      final answer = ask(model).join();
      await settle();
      await model.releaseWhenIdle();
      expect(model.isLoaded, isTrue);
      h.replyGate!.complete();
      await answer;
      await settle();
      expect(model.isLoaded, isFalse);
      model.dispose();
    });

    test('an answer cancelled while the model loads never starts generating', () async {
      h.loadGate = Completer<void>();
      final model = h.runtime();
      final subscription = ask(model).listen((_) {});
      await settle();
      await subscription.cancel();
      h.loadGate!.complete();
      await settle();
      expect(h.log, ['load']);
      expect(model.activity, ModelActivity.ready);
      model.dispose();
    });
  });
}
