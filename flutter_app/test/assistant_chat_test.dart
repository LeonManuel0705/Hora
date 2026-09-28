// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:app/services/assistant/assistant_chat.dart';
import 'package:app/services/assistant/assistant_engine.dart';
import 'package:app/services/assistant/local_model/model_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'assistant_model_fakes.dart';

void main() {
  late RuntimeHarness h;

  setUp(() => h = RuntimeHarness());

  group('chat', () {
    late ModelRuntime model;
    late AssistantChat chat;
    var contextBuilds = 0;

    setUp(() {
      contextBuilds = 0;
      model = h.runtime();
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

    AssistantChat localChat(
      ModelRuntime runtime, {
      Future<AssistantResponse?> Function(String message)? exact,
      Future<String> Function()? prompt,
    }) {
      return AssistantChat.local(
        runtime: runtime,
        modelPath: () => '/models/a.gguf',
        exact: exact ?? (_) async => null,
        systemPrompt: prompt ?? () async => '',
      );
    }

    test('exact questions never wake the model', () async {
      await chat.ask('2+2');
      expect(chat.entries.last.text, '**4**');
      expect(chat.entries.last.source, AssistantSource.math);
      expect(h.log, isEmpty);
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
      final history = h.created.single.lastHistory!;
      expect(history.map((turn) => turn.text), ['2+2', '**4**']);
      expect(h.created.single.lastSystem, 'Kontext 1');

      await chat.ask('Und noch mal?');
      expect(h.created.single.lastHistory!.map((turn) => turn.text).toList(),
          ['2+2', '**4**', 'Erklär mir Vektoren', 'Hallo zusammen!']);
      expect(contextBuilds, 1);
    });

    test('stop keeps what was written so far', () async {
      final llm = FakeLlm(h.log)..gate = Completer<void>();
      final stoppable = ModelRuntime(create: () => llm, store: h.store, gpuPreferred: false, session: 'now');
      final stopChat = localChat(stoppable);
      final asking = stopChat.ask('Schreib eine lange Geschichte');
      await settle();
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

    test('stop during the exact lookup ends the question right away', () async {
      final lookup = Completer<AssistantResponse?>();
      final slowChat = localChat(model, exact: (_) => lookup.future);
      final asking = slowChat.ask('Wer war Ada Lovelace?');
      await settle();
      expect(slowChat.busy, isTrue);
      slowChat.stop();
      await asking;
      expect(slowChat.phase, ChatPhase.idle);
      expect(slowChat.entries.last.text, AssistantChat.stoppedText);
      lookup.complete(null);
      await settle();
      expect(h.log, isEmpty);
      slowChat.dispose();
    });

    test('a failing exact lookup still gets an answer and never leaves the chat busy', () async {
      final brokenChat = localChat(model, exact: (_) async => throw StateError('lookup'));
      await brokenChat.ask('Erklär mir Vektoren');
      expect(brokenChat.phase, ChatPhase.idle);
      expect(brokenChat.entries.last.text, 'Hallo zusammen!');
      brokenChat.dispose();
    });

    test('stop while the prompt is built starts no answer', () async {
      final prompt = Completer<String>();
      final slowChat = localChat(model, prompt: () => prompt.future);
      final asking = slowChat.ask('Was steht heute an?');
      await settle();
      slowChat.stop();
      await asking;
      expect(slowChat.phase, ChatPhase.idle);
      expect(slowChat.entries.last.text, AssistantChat.stoppedText);
      prompt.complete('Kontext');
      await settle();
      expect(h.log.where((line) => line.startsWith('reply:')), isEmpty);
      slowChat.dispose();
    });

    test('stop while the model loads frees the chat at once and skips the answer', () async {
      h.loadGate = Completer<void>();
      final loading = h.runtime();
      final loadingChat = localChat(loading);
      final asking = loadingChat.ask('Hallo');
      await settle();
      expect(loadingChat.phase, ChatPhase.loadingModel);
      loadingChat.stop();
      await asking;
      expect(loadingChat.phase, ChatPhase.idle);
      expect(loadingChat.entries.last.text, AssistantChat.stoppedText);
      h.loadGate!.complete();
      await settle();
      expect(h.log.where((line) => line.startsWith('reply:')), isEmpty);
      loadingChat.dispose();
      loading.dispose();
    });

    test('a model that fails to start shows a retry and the retry asks again', () async {
      final failing = h.runtime(loadError: StateError('oom'));
      final failingChat = localChat(failing);
      await failingChat.ask('Hilf mir beim Lernen');
      final entry = failingChat.entries.last;
      expect(entry.failed, isTrue);
      expect(entry.text, AssistantChat.loadFailedText);
      expect(entry.question, 'Hilf mir beim Lernen');

      h.failLoads = null;
      await failingChat.retry(entry);
      expect(failingChat.entries.where((e) => e.failed), isEmpty);
      expect(failingChat.entries, hasLength(2));
      failingChat.dispose();
      failing.dispose();
    });

    test('retrying after the memory warning resets the crash guard', () async {
      h.store
        ..storedLevel = 2
        ..storedCleanRuns = 1;
      final guarded = h.runtime();
      final guardedChat = localChat(guarded);
      await guardedChat.ask('Hallo');
      final entry = guardedChat.entries.last;
      expect(entry.text, AssistantChat.loadGaveUpText);
      expect(entry.text.contains('abgestürzt'), isFalse);
      await guardedChat.retry(entry);
      expect(h.store.storedLevel, 0);
      expect(guardedChat.entries.last.text, 'Hallo zusammen!');
      guardedChat.dispose();
      guarded.dispose();
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
