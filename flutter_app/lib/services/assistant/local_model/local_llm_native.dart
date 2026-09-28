// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:llamadart/llamadart.dart';

import 'local_llm.dart';

bool runtimeAvailable() {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  return const {Abi.androidArm64, Abi.androidX64, Abi.iosArm64, Abi.iosX64}.contains(Abi.current());
}

bool prefersGpu() => Platform.isIOS;

LocalLlm createLocalLlm() => _LlamaLocalLlm();

class _LlamaLocalLlm implements LocalLlm {
  LlamaEngine? _engine;
  LlmSettings? _settings;

  static const _generation = GenerationParams(
    maxTokens: 640,
    temp: 0.7,
    topK: 64,
    topP: 0.95,
    minP: 0.05,
    penalty: 1.05,
    streamBatchTokenThreshold: 2,
    streamBatchByteThreshold: 96,
  );

  @override
  bool get isLoaded => _engine?.isReady ?? false;

  @override
  Future<void> load(String path, LlmSettings settings) async {
    if (isLoaded) return;
    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        path,
        modelParams: ModelParams(
          contextSize: settings.contextSize,
          gpuLayers: settings.gpu ? ModelParams.maxGpuLayers : 0,
          preferredBackend: settings.gpu ? GpuBackend.auto : GpuBackend.cpu,
          batchSize: settings.batchSize,
          microBatchSize: settings.microBatchSize,
        ),
      );
    } catch (_) {
      try {
        await engine.dispose();
      } catch (_) {}
      rethrow;
    }
    _engine = engine;
    _settings = settings;
  }

  @override
  Stream<String> reply({required String system, required List<LlmTurn> history, required String message}) async* {
    final engine = _engine;
    final settings = _settings;
    if (engine == null || settings == null || !engine.isReady) throw StateError('model not loaded');
    final session = ChatSession(engine, maxContextTokens: settings.contextSize, systemPrompt: system);
    for (final turn in history) {
      session.addMessage(LlamaChatMessage.fromText(
        role: turn.fromUser ? LlamaChatRole.user : LlamaChatRole.assistant,
        text: turn.text,
      ));
    }
    await for (final chunk in session.create(
      [LlamaTextContent(message)],
      params: _generation,
      enableThinking: false,
    )) {
      if (chunk.choices.isEmpty) continue;
      final text = chunk.choices.first.delta.content;
      if (text != null && text.isNotEmpty) yield text;
    }
  }

  @override
  void stop() => _engine?.cancelGeneration();

  @override
  Future<void> unload() async {
    final engine = _engine;
    _engine = null;
    _settings = null;
    if (engine == null) return;
    engine.cancelGeneration();
    await engine.dispose();
  }
}
