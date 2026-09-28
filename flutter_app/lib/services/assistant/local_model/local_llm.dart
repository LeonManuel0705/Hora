// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'local_llm_stub.dart' if (dart.library.ffi) 'local_llm_native.dart' as platform;

class LlmTurn {
  const LlmTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

class LlmSettings {
  const LlmSettings({required this.contextSize, required this.gpu, this.batchSize = 0, this.microBatchSize = 0});

  final int contextSize;
  final bool gpu;
  final int batchSize;
  final int microBatchSize;
}

abstract class LocalLlm {
  bool get isLoaded;

  Future<void> load(String path, LlmSettings settings);

  Stream<String> reply({required String system, required List<LlmTurn> history, required String message});

  void stop();

  Future<void> unload();
}

bool localLlmAvailable() => platform.runtimeAvailable();

bool localLlmPrefersGpu() => platform.prefersGpu();

LocalLlm createLocalLlm() => platform.createLocalLlm();
