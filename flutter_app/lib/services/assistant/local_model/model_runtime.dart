// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_llm.dart';

enum ModelActivity { idle, loading, ready, generating }

class ModelLoadException implements Exception {
  const ModelLoadException(this.gaveUp, [this.cause]);

  final bool gaveUp;
  final Object? cause;

  @override
  String toString() => 'ModelLoadException(gaveUp: $gaveUp, cause: $cause)';
}

abstract class RuntimeStore {
  Future<int> level();

  Future<void> setLevel(int level);

  Future<String?> inflight();

  Future<void> setInflight(String? value);
}

LlmSettings settingsFor({
  required int level,
  required bool gpuPreferred,
  required int modelBytes,
  int? availableMemory,
}) {
  final tight = availableMemory != null && availableMemory < modelBytes ~/ 2 + 900 * 1000 * 1000;
  if (level >= 1 || tight) {
    return const LlmSettings(contextSize: 2048, gpu: false, batchSize: 256, microBatchSize: 128);
  }
  final gpuFits = availableMemory == null || availableMemory >= modelBytes + 600 * 1000 * 1000;
  return LlmSettings(contextSize: 4096, gpu: gpuPreferred && gpuFits, batchSize: 512, microBatchSize: 256);
}

class ModelRuntime extends ChangeNotifier {
  ModelRuntime({
    required LocalLlm Function() create,
    required this.store,
    required this.gpuPreferred,
    this.availableMemory,
    this.idleTimeout = const Duration(minutes: 3),
    String? session,
  })  : _create = create,
        _session = session ?? '${DateTime.now().microsecondsSinceEpoch}';

  final LocalLlm Function() _create;
  final RuntimeStore store;
  final bool gpuPreferred;
  final Future<int?> Function()? availableMemory;
  final Duration idleTimeout;
  final String _session;

  static const maxLevel = 2;

  LocalLlm? _llm;
  String? _path;
  Future<void>? _loading;
  Future<void> _queue = Future<void>.value();
  Timer? _idle;
  ModelActivity _activity = ModelActivity.idle;
  bool _background = false;
  bool _disposed = false;

  ModelActivity get activity => _activity;

  bool get isLoaded => _llm?.isLoaded ?? false;

  bool get isGenerating => _activity == ModelActivity.generating;

  Future<void> load(String path) {
    if (isLoaded && _path == path) return Future<void>.value();
    return _loading ??= _load(path).whenComplete(() => _loading = null);
  }

  Future<void> _load(String path) async {
    _idle?.cancel();
    if (_llm != null) await _unloadNow();
    _set(ModelActivity.loading);
    var level = await store.level();
    final previous = await store.inflight();
    if (previous != null && previous != _session) {
      level = level + 1;
      await store.setLevel(level > maxLevel ? maxLevel : level);
      await store.setInflight(null);
    }
    if (level >= maxLevel) {
      _set(ModelActivity.idle);
      throw const ModelLoadException(true);
    }
    int? available;
    try {
      available = await availableMemory?.call();
    } catch (_) {
      available = null;
    }
    final settings = settingsFor(
      level: level,
      gpuPreferred: gpuPreferred,
      modelBytes: await _length(path),
      availableMemory: available,
    );
    final llm = _create();
    await store.setInflight(_session);
    try {
      await llm.load(path, settings);
    } catch (error) {
      await store.setInflight(null);
      try {
        await llm.unload();
      } catch (_) {}
      _set(ModelActivity.idle);
      throw ModelLoadException(false, error);
    }
    await store.setInflight(null);
    if (_disposed) {
      await llm.unload();
      return;
    }
    _llm = llm;
    _path = path;
    _set(ModelActivity.ready);
    _armIdle();
  }

  Future<void> resetCrashGuard() async {
    await store.setInflight(null);
    await store.setLevel(1);
  }

  Stream<String> reply({
    required String path,
    required String system,
    required List<LlmTurn> history,
    required String message,
  }) async* {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      await previous;
      await load(path);
      final llm = _llm;
      if (llm == null) throw const ModelLoadException(false);
      _idle?.cancel();
      _set(ModelActivity.generating);
      await store.setInflight(_session);
      try {
        yield* llm.reply(system: system, history: history, message: message);
      } finally {
        await store.setInflight(null);
        if (_llm != null) _set(ModelActivity.ready);
        _armIdle();
      }
    } finally {
      done.complete();
    }
  }

  void stop() => _llm?.stop();

  void setBackground(bool background) {
    _background = background;
    if (background) unawaited(releaseIfIdle());
  }

  Future<void> unload() async {
    _idle?.cancel();
    if (_loading != null) {
      try {
        await _loading;
      } catch (_) {}
    }
    await _unloadNow();
  }

  Future<void> releaseIfIdle() async {
    if (_activity == ModelActivity.generating || _activity == ModelActivity.loading) return;
    await unload();
  }

  Future<void> _unloadNow() async {
    final llm = _llm;
    _llm = null;
    _path = null;
    if (llm != null) {
      try {
        await llm.unload();
      } catch (_) {}
    }
    _set(ModelActivity.idle);
  }

  static Future<int> _length(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }

  void _armIdle() {
    _idle?.cancel();
    if (_disposed || _llm == null) return;
    _idle = Timer(_background ? Duration.zero : idleTimeout, () => unawaited(releaseIfIdle()));
  }

  void _set(ModelActivity activity) {
    if (_disposed || _activity == activity) return;
    _activity = activity;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idle?.cancel();
    final llm = _llm;
    _llm = null;
    if (llm != null) {
      llm.stop();
      unawaited(llm.unload().catchError((_) {}));
    }
    super.dispose();
  }
}
