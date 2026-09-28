// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'model_downloader.dart';
import 'model_manifest.dart';

enum NetworkKind { none, wifi, mobile, other }

class ModelPlan {
  const ModelPlan({required this.choice, this.directory, this.freeBytes, this.totalMemory});

  final ModelChoice choice;
  final String? directory;
  final int? freeBytes;
  final int? totalMemory;
}

abstract class ModelTransfer {
  Future<File> get result;

  void cancel();
}

abstract class ModelInstallHost {
  Future<ModelPlan> plan();

  Future<int?> freeBytes(String directory);

  Future<NetworkKind> network();

  Stream<NetworkKind> get networkChanges;

  Future<void> keepAwake(bool on);

  Future<void> protect(String path);

  Future<ModelTransfer> download(ModelFile model, File target, void Function(DownloadProgress progress) onProgress);

  Future<void> start(String path);
}

enum InstallStage { checking, unsupported, offer, downloading, starting, ready, failed, installed }

enum InstallProblem { offline, storage, checksum, server, loadFailed }

enum InstallStart { started, needsMobileConfirmation, blocked }

@immutable
class InstallState {
  const InstallState(
    this.stage, {
    this.model,
    this.partialBytes = 0,
    this.freeBytes,
    this.onMobileData = false,
    this.progress,
    this.problem,
    this.missingBytes = 0,
    this.unsupported,
    this.totalMemory,
    this.secondAttempt = false,
  });

  final InstallStage stage;
  final ModelFile? model;
  final int partialBytes;
  final int? freeBytes;
  final bool onMobileData;
  final DownloadProgress? progress;
  final InstallProblem? problem;
  final int missingBytes;
  final ModelUnsupportedReason? unsupported;
  final int? totalMemory;
  final bool secondAttempt;

  bool get busy => stage == InstallStage.downloading || stage == InstallStage.starting;
}

class ModelInstaller extends ChangeNotifier {
  ModelInstaller(this.host, {this.reserveBytes = 300 * 1000 * 1000, this.stallTimeout = const Duration(seconds: 4)}) {
    _networkSubscription = host.networkChanges.listen(_networkChanged);
  }

  final ModelInstallHost host;
  final int reserveBytes;
  final Duration stallTimeout;

  InstallState _state = const InstallState(InstallStage.checking);
  ModelFile? _model;
  String? _directory;
  ModelTransfer? _transfer;
  int _generation = 0;
  bool _mobileAllowed = false;
  bool _starting = false;
  bool _checksumRetried = false;
  bool _pausedWhileLoading = false;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _stallCheck;
  Future<void>? _refreshing;
  StreamSubscription<NetworkKind>? _networkSubscription;
  bool _disposed = false;

  InstallState get state => _state;

  String? get modelPath {
    final model = _model;
    final directory = _directory;
    if (model == null || directory == null) return null;
    return '$directory/${model.fileName}';
  }

  bool get isInstalled => _state.stage == InstallStage.installed || _state.stage == InstallStage.ready;

  File? get _target => modelPath == null ? null : File(modelPath!);

  File? get _marker => _directory == null ? null : File('$_directory/installed.json');

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    if (_state.busy || _starting) return;
    final ModelPlan plan;
    try {
      plan = await host.plan();
    } catch (_) {
      _emit(const InstallState(InstallStage.unsupported, unsupported: ModelUnsupportedReason.platform));
      return;
    }
    final choice = plan.choice;
    if (choice is ModelUnsupported) {
      _model = null;
      _emit(InstallState(InstallStage.unsupported, unsupported: choice.reason, totalMemory: plan.totalMemory));
      return;
    }
    if (plan.directory == null) {
      _emit(const InstallState(InstallStage.unsupported, unsupported: ModelUnsupportedReason.platform));
      return;
    }
    final model = (choice as ModelSupported).file;
    _model = model;
    _directory = plan.directory;
    if (await _isInstalled(model)) {
      _emit(InstallState(InstallStage.installed, model: model));
      return;
    }
    final network = await _network();
    _emit(InstallState(
      InstallStage.offer,
      model: model,
      partialBytes: await _partLength(),
      freeBytes: plan.freeBytes,
      onMobileData: network == NetworkKind.mobile,
    ));
  }

  Future<InstallStart> install({bool allowMobileData = false}) async {
    if (_state.busy || _starting) return InstallStart.started;
    final model = _model;
    final directory = _directory;
    if (_state.stage == InstallStage.unsupported || _state.stage == InstallStage.checking) return InstallStart.blocked;
    if (model == null || directory == null) return InstallStart.blocked;
    _starting = true;
    try {
      if (allowMobileData) _mobileAllowed = true;
      final network = await _network();
      if (network == NetworkKind.none) {
        _fail(InstallProblem.offline);
        return InstallStart.blocked;
      }
      if (network == NetworkKind.mobile && !_mobileAllowed) return InstallStart.needsMobileConfirmation;
      await _clearOthers(model);
      await _reclaimUnmarked(model);
      final partial = await _partLength();
      final free = await host.freeBytes(directory);
      final needed = model.bytes - partial + reserveBytes;
      if (free != null && free < needed) {
        _fail(InstallProblem.storage, missing: needed - free);
        return InstallStart.blocked;
      }
      _checksumRetried = false;
      await _startTransfer(model, partial);
      return InstallStart.started;
    } finally {
      _starting = false;
    }
  }

  Future<InstallStart> retry() async {
    if (_state.stage != InstallStage.failed) return InstallStart.blocked;
    if (_state.problem == InstallProblem.loadFailed) {
      await _startModel();
      return InstallStart.started;
    }
    return install(allowMobileData: _mobileAllowed);
  }

  void cancel() {
    if (_state.stage != InstallStage.downloading) return;
    _transfer?.cancel();
  }

  void open() {
    if (_state.stage == InstallStage.ready) _emit(InstallState(InstallStage.installed, model: _state.model));
  }

  Future<void> remove() async {
    _generation++;
    _stallCheck?.cancel();
    final transfer = _transfer;
    _transfer = null;
    if (transfer != null) {
      transfer.cancel();
      await transfer.result.then((_) {}, onError: (_) {});
    }
    unawaited(host.keepAwake(false));
    final directory = _directory;
    if (directory != null) {
      try {
        final folder = Directory(directory);
        if (await folder.exists()) {
          await for (final entry in folder.list()) {
            await entry.delete(recursive: true);
          }
        }
      } on FileSystemException {
        return;
      }
    }
    _state = const InstallState(InstallStage.checking);
    await refresh();
  }

  void appPaused() {
    _pausedWhileLoading = _state.stage == InstallStage.downloading;
    _stallCheck?.cancel();
  }

  void appResumed() {
    if (!_pausedWhileLoading) return;
    _pausedWhileLoading = false;
    _stallCheck?.cancel();
    _stallCheck = Timer(stallTimeout, () {
      if (_state.stage != InstallStage.downloading) return;
      if (DateTime.now().difference(_lastProgress) < stallTimeout) return;
      unawaited(_restartTransfer());
    });
  }

  Future<void> _restartTransfer() async {
    final model = _model;
    final transfer = _transfer;
    if (model == null || transfer == null) return;
    _generation++;
    _transfer = null;
    transfer.cancel();
    await transfer.result.then((_) {}, onError: (_) {});
    if (_disposed || _state.stage != InstallStage.downloading) return;
    await _startTransfer(model, await _partLength());
  }

  Future<void> _startTransfer(ModelFile model, int partial, {bool secondAttempt = false}) async {
    final generation = ++_generation;
    _lastProgress = DateTime.now();
    _emit(InstallState(
      InstallStage.downloading,
      model: model,
      partialBytes: partial,
      progress: DownloadProgress(received: partial, total: model.bytes),
      secondAttempt: secondAttempt,
    ));
    unawaited(host.keepAwake(true));
    final ModelTransfer transfer;
    try {
      transfer = await host.download(model, _target!, (progress) {
        if (generation != _generation) return;
        _lastProgress = DateTime.now();
        _emit(InstallState(
          InstallStage.downloading,
          model: model,
          partialBytes: partial,
          progress: progress,
          secondAttempt: secondAttempt,
        ));
      });
    } catch (error) {
      if (generation == _generation) await _downloadFailed(model, error);
      return;
    }
    if (generation != _generation) {
      transfer.cancel();
      return;
    }
    _transfer = transfer;
    transfer.result.then(
      (file) async {
        if (generation != _generation) return;
        _transfer = null;
        await _downloaded(model, file);
      },
      onError: (Object error) async {
        if (generation != _generation) return;
        _transfer = null;
        await _downloadFailed(model, error);
      },
    );
  }

  Future<void> _downloaded(ModelFile model, File file) async {
    await host.protect(file.path);
    try {
      await _marker!.writeAsString(jsonEncode({
        'repository': model.repository,
        'revision': model.revision,
        'file': model.fileName,
        'bytes': model.bytes,
        'sha256': model.sha256,
      }));
    } on FileSystemException {
      _fail(InstallProblem.storage, missing: 1);
      return;
    }
    await _startModel();
  }

  Future<void> _startModel() async {
    final path = modelPath;
    final model = _model;
    if (path == null || model == null) return;
    _emit(InstallState(InstallStage.starting, model: model));
    unawaited(host.keepAwake(true));
    try {
      await host.start(path);
      _emit(InstallState(InstallStage.ready, model: model));
    } catch (_) {
      _fail(InstallProblem.loadFailed);
    } finally {
      unawaited(host.keepAwake(false));
    }
  }

  Future<void> _downloadFailed(ModelFile model, Object error) async {
    final failure = error is ModelDownloadException ? error.failure : DownloadFailure.server;
    switch (failure) {
      case DownloadFailure.cancelled:
        unawaited(host.keepAwake(false));
        final network = await _network();
        _emit(InstallState(
          InstallStage.offer,
          model: model,
          partialBytes: await _partLength(),
          freeBytes: _directory == null ? null : await host.freeBytes(_directory!),
          onMobileData: network == NetworkKind.mobile,
        ));
      case DownloadFailure.checksum:
        if (!_checksumRetried) {
          _checksumRetried = true;
          await _startTransfer(model, 0, secondAttempt: true);
          return;
        }
        _fail(InstallProblem.checksum);
      case DownloadFailure.storage:
        final partial = await _partLength();
        final free = _directory == null ? null : await host.freeBytes(_directory!);
        final needed = model.bytes - partial + reserveBytes;
        _fail(InstallProblem.storage, missing: math.max(1, needed - (free ?? 0)));
      case DownloadFailure.network:
        _fail(InstallProblem.offline);
      case DownloadFailure.server:
        _fail(InstallProblem.server);
    }
  }

  void _fail(InstallProblem problem, {int missing = 0}) {
    unawaited(host.keepAwake(false));
    _emit(InstallState(
      InstallStage.failed,
      model: _state.model,
      problem: problem,
      missingBytes: missing,
      partialBytes: _state.partialBytes,
    ));
  }

  Future<bool> _isInstalled(ModelFile model) async {
    try {
      final marker = jsonDecode(await _marker!.readAsString());
      if (marker is! Map || marker['sha256'] != model.sha256 || marker['file'] != model.fileName) return false;
      final file = _target!;
      return await file.exists() && await file.length() == model.bytes;
    } catch (_) {
      return false;
    }
  }

  Future<void> _reclaimUnmarked(ModelFile model) async {
    final target = _target!;
    try {
      if (await target.exists() && !await _isInstalled(model)) {
        await target.rename(ModelDownloader.partOf(target).path);
      }
    } on FileSystemException {
      return;
    }
  }

  Future<void> _clearOthers(ModelFile model) async {
    final directory = _directory;
    if (directory == null) return;
    final keep = {model.fileName, '${model.fileName}.part', 'installed.json'};
    try {
      final folder = Directory(directory);
      if (!await folder.exists()) {
        await folder.create(recursive: true);
        return;
      }
      await for (final entry in folder.list()) {
        final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
        if (!keep.contains(name)) await entry.delete(recursive: true);
      }
    } on FileSystemException {
      return;
    }
  }

  Future<int> _partLength() async {
    final target = _target;
    if (target == null) return 0;
    try {
      final part = ModelDownloader.partOf(target);
      return await part.exists() ? await part.length() : 0;
    } on FileSystemException {
      return 0;
    }
  }

  Future<NetworkKind> _network() async {
    try {
      return await host.network();
    } catch (_) {
      return NetworkKind.other;
    }
  }

  void _networkChanged(NetworkKind network) {
    if (_state.stage != InstallStage.offer) return;
    final mobile = network == NetworkKind.mobile;
    if (mobile == _state.onMobileData) return;
    _emit(InstallState(
      InstallStage.offer,
      model: _state.model,
      partialBytes: _state.partialBytes,
      freeBytes: _state.freeBytes,
      onMobileData: mobile,
    ));
  }

  void _emit(InstallState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _stallCheck?.cancel();
    _transfer?.cancel();
    unawaited(_networkSubscription?.cancel());
    unawaited(host.keepAwake(false));
    super.dispose();
  }
}
