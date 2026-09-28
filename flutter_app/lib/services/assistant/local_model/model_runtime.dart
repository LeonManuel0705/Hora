// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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

  Future<int> cleanRuns();

  Future<void> setCleanRuns(int runs);

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

class _Request {
  bool cancelled = false;
  bool generating = false;
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
  static const cleanRunsToRecover = 3;

  LocalLlm? _llm;
  String? _path;
  Future<void>? _loading;
  Future<void> _queue = Future<void>.value();
  int _requests = 0;
  Timer? _idle;
  ModelActivity _activity = ModelActivity.idle;
  bool _background = false;
  bool _marked = false;
  bool _firstDecodePending = false;
  bool _awaitingFirstToken = false;
  bool _releaseRequested = false;
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
      level = math.min(level + 1, maxLevel);
      await store.setLevel(level);
      await store.setCleanRuns(0);
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
    final bytes = await _length(path);
    final settings = settingsFor(level: level, gpuPreferred: gpuPreferred, modelBytes: bytes, availableMemory: available);
    await _mark();
    LocalLlm? llm;
    Object? failure;
    for (final attempt in [
      settings,
      if (settings.gpu) settingsFor(level: 1, gpuPreferred: false, modelBytes: bytes),
    ]) {
      final candidate = _create();
      try {
        await candidate.load(path, attempt);
        llm = candidate;
        break;
      } catch (error) {
        failure = error;
        try {
          await candidate.unload();
        } catch (_) {}
      }
    }
    await _unmark();
    if (llm == null) {
      _set(ModelActivity.idle);
      throw ModelLoadException(false, failure);
    }
    if (_disposed) {
      await llm.unload();
      return;
    }
    _llm = llm;
    _path = path;
    _firstDecodePending = true;
    _set(ModelActivity.ready);
    _armIdle();
  }

  Future<void> resetCrashGuard() async {
    _marked = false;
    await store.setInflight(null);
    await store.setLevel(0);
    await store.setCleanRuns(0);
  }

  Stream<String> reply({
    required String path,
    required String system,
    required List<LlmTurn> history,
    required String message,
  }) {
    final request = _Request();
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () => unawaited(_produce(controller, request, path, system, history, message)),
      onCancel: () {
        request.cancelled = true;
        if (request.generating) _llm?.stop();
      },
    );
    return controller.stream;
  }

  Future<void> _produce(
    StreamController<String> controller,
    _Request request,
    String path,
    String system,
    List<LlmTurn> history,
    String message,
  ) async {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    _requests++;
    try {
      await previous;
      if (request.cancelled) return;
      await load(path);
      if (request.cancelled) return;
      final llm = _llm;
      if (llm == null) throw const ModelLoadException(false);
      await _generate(controller, request, llm, system, history, message);
    } catch (error, stackTrace) {
      if (!request.cancelled && !controller.isClosed) controller.addError(error, stackTrace);
    } finally {
      _requests--;
      done.complete();
      if (!controller.isClosed) unawaited(controller.close());
      if (_requests == 0 && _releaseRequested) {
        _releaseRequested = false;
        unawaited(unload());
      }
    }
  }

  Future<void> _generate(
    StreamController<String> controller,
    _Request request,
    LocalLlm llm,
    String system,
    List<LlmTurn> history,
    String message,
  ) async {
    _idle?.cancel();
    _set(ModelActivity.generating);
    final firstDecode = _firstDecodePending;
    var clean = !firstDecode;
    if (firstDecode) {
      _awaitingFirstToken = true;
      await _mark();
    }
    request.generating = true;
    try {
      await for (final delta in llm.reply(system: system, history: history, message: message)) {
        if (request.cancelled) {
          llm.stop();
          break;
        }
        if (!clean) {
          clean = true;
          await _cleanRun();
        }
        if (!controller.isClosed) controller.add(delta);
      }
      if (!clean && !request.cancelled) {
        clean = true;
        await _cleanRun();
      }
    } finally {
      request.generating = false;
      _awaitingFirstToken = false;
      if (!clean) await _unmark();
      if (_llm != null) _set(ModelActivity.ready);
      _armIdle();
    }
  }

  Future<void> _cleanRun() async {
    _firstDecodePending = false;
    _awaitingFirstToken = false;
    await _unmark();
    final level = await store.level();
    if (level <= 0) return;
    final runs = await store.cleanRuns() + 1;
    if (runs >= cleanRunsToRecover) {
      await store.setLevel(level - 1);
      await store.setCleanRuns(0);
    } else {
      await store.setCleanRuns(runs);
    }
  }

  Future<void> _mark() async {
    if (_background || _disposed) return;
    _marked = true;
    await store.setInflight(_session);
  }

  Future<void> _unmark() async {
    if (!_marked) return;
    _marked = false;
    await store.setInflight(null);
  }

  void stop() => _llm?.stop();

  void setBackground(bool background) {
    _background = background;
    if (background) {
      unawaited(_unmark());
      unawaited(releaseIfIdle());
    } else if (_activity == ModelActivity.loading || _awaitingFirstToken) {
      unawaited(_mark());
    }
  }

  void keep() => _releaseRequested = false;

  Future<void> releaseWhenIdle() async {
    if (_requests > 0 || _activity == ModelActivity.loading || _activity == ModelActivity.generating) {
      _releaseRequested = true;
      return;
    }
    await unload();
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
    _firstDecodePending = false;
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
