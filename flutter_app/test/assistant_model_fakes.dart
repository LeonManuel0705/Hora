// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:app/services/assistant/local_model/local_llm.dart';
import 'package:app/services/assistant/local_model/model_runtime.dart';

class FakeRuntimeStore implements RuntimeStore {
  int storedLevel = 0;
  int storedCleanRuns = 0;
  String? storedInflight;
  final inflightHistory = <String?>[];

  @override
  Future<int> level() async => storedLevel;

  @override
  Future<void> setLevel(int level) async => storedLevel = level;

  @override
  Future<int> cleanRuns() async => storedCleanRuns;

  @override
  Future<void> setCleanRuns(int runs) async => storedCleanRuns = runs;

  @override
  Future<String?> inflight() async => storedInflight;

  @override
  Future<void> setInflight(String? value) async {
    storedInflight = value;
    inflightHistory.add(value);
  }
}

class FakeLlm implements LocalLlm {
  FakeLlm(this.log);

  final List<String> log;
  bool loaded = false;
  Object? loadError;
  Completer<void>? loadGate;
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
    final wait = loadGate;
    if (wait != null) await wait.future;
    final error = loadError;
    if (error != null) throw error;
    loaded = true;
  }

  @override
  Stream<String> reply({required String system, required List<LlmTurn> history, required String message}) async* {
    log.add('reply:$message');
    stopped = false;
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

class RuntimeHarness {
  final store = FakeRuntimeStore();
  final log = <String>[];
  final created = <FakeLlm>[];
  Object? failLoads;
  Completer<void>? loadGate;
  Completer<void>? replyGate;

  ModelRuntime runtime({Duration idle = const Duration(minutes: 3), String session = 'now', Object? loadError}) {
    failLoads = loadError;
    return ModelRuntime(
      create: () {
        final llm = FakeLlm(log)
          ..loadError = failLoads
          ..loadGate = loadGate
          ..gate = replyGate;
        created.add(llm);
        return llm;
      },
      store: store,
      gpuPreferred: true,
      idleTimeout: idle,
      session: session,
    );
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));
