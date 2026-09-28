// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'model_downloader.dart';
import 'model_manifest.dart';

enum NetworkKind { none, unmetered, metered }

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

  void reconnect();
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

  Future<void> forget();
}

enum InstallStage { checking, unsupported, offer, downloading, starting, ready, failed, installed }

enum InstallProblem { offline, storage, checksum, server, loadFailed }

enum InstallStart { started, needsMobileConfirmation, blocked }

enum InstallNotice { none, pausedForMobileData, retryAfterDamage }

enum _Stop { user, mobileData, storage }

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
    this.notice = InstallNotice.none,
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
  final InstallNotice notice;

  bool get busy => stage == InstallStage.downloading || stage == InstallStage.starting;

  int get loadedBytes =>
      stage == InstallStage.downloading ? math.max(partialBytes, progress?.received ?? 0) : partialBytes;
}

class ModelInstaller extends ChangeNotifier {
  ModelInstaller(
    this.host, {
    this.reserveBytes = 300 * 1000 * 1000,
    this.stallTimeout = const Duration(seconds: 4),
    this.spaceInterval = const Duration(seconds: 5),
  }) {
    _networkSubscription = host.networkChanges.listen(_networkChanged, onError: (_) {});
  }

  final ModelInstallHost host;
  final int reserveBytes;
  final Duration stallTimeout;
  final Duration spaceInterval;

  InstallState _state = const InstallState(InstallStage.checking);
  ModelFile? _model;
  String? _directory;
  ModelTransfer? _transfer;
  Future<ModelTransfer>? _arriving;
  int _generation = 0;
  int _epoch = 0;
  bool _mobileAllowed = false;
  bool _starting = false;
  bool _checksumRetried = false;
  bool _pausedForMobile = false;
  InstallNotice _notice = InstallNotice.none;
  _Stop? _stop;
  bool _pausedWhileLoading = false;
  int _written = 0;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _stallCheck;
  Timer? _spaceCheck;
  bool _checkingSpace = false;
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
    final epoch = _epoch;
    bool stale() => _disposed || epoch != _epoch || _state.busy || _starting;
    final ModelPlan plan;
    try {
      plan = await host.plan();
    } catch (_) {
      if (!stale()) _emit(const InstallState(InstallStage.unsupported, unsupported: ModelUnsupportedReason.platform));
      return;
    }
    if (stale()) return;
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
      if (!stale()) _emit(InstallState(InstallStage.installed, model: model));
      return;
    }
    final network = await _network();
    final partial = await _partLength();
    if (stale()) return;
    _emit(_offer(model, partial: partial, free: plan.freeBytes, network: network));
  }

  Future<InstallStart> install({bool allowMobileData = false}) async {
    if (_state.busy || _starting) return InstallStart.started;
    final model = _model;
    final directory = _directory;
    if (_state.stage == InstallStage.unsupported || _state.stage == InstallStage.checking) return InstallStart.blocked;
    if (model == null || directory == null) return InstallStart.blocked;
    _starting = true;
    _epoch++;
    try {
      if (allowMobileData) _mobileAllowed = true;
      final network = await _network();
      if (network == NetworkKind.none) {
        _fail(InstallProblem.offline, partial: await _partLength());
        return InstallStart.blocked;
      }
      if (network == NetworkKind.metered && !_mobileAllowed) return InstallStart.needsMobileConfirmation;
      await _clearOthers(model);
      await _reclaimUnmarked(model);
      final partial = await _partLength();
      final free = await host.freeBytes(directory);
      final needed = model.bytes - partial + reserveBytes;
      if (free != null && free < needed) {
        _fail(InstallProblem.storage, missing: needed - free, partial: partial);
        return InstallStart.blocked;
      }
      final second = _notice == InstallNotice.retryAfterDamage;
      if (!second) _checksumRetried = false;
      _pausedForMobile = false;
      await _startTransfer(model, partial, secondAttempt: second);
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
    _requestStop(_Stop.user);
  }

  void open() {
    if (_state.stage == InstallStage.ready) _emit(InstallState(InstallStage.installed, model: _state.model));
  }

  Future<void> remove() async {
    _generation++;
    _epoch++;
    _stallCheck?.cancel();
    _stopSpaceChecks();
    _stop = null;
    _pausedForMobile = false;
    _notice = InstallNotice.none;
    _checksumRetried = false;
    final transfer = _transfer;
    final arriving = _arriving;
    _transfer = null;
    _arriving = null;
    for (final running in [
      if (transfer != null) Future<ModelTransfer>.value(transfer),
      if (arriving != null) arriving,
    ]) {
      try {
        final active = await running;
        active.cancel();
        await active.result.then((_) {}, onError: (_) {});
      } catch (_) {}
    }
    unawaited(host.keepAwake(false));
    try {
      await host.forget();
    } catch (_) {}
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
      _transfer?.reconnect();
    });
  }

  void _requestStop(_Stop reason) {
    _stop ??= reason;
    _transfer?.cancel();
  }

  Future<void> _startTransfer(ModelFile model, int partial, {bool secondAttempt = false}) async {
    final previous = _transfer;
    _transfer = null;
    final generation = ++_generation;
    _epoch++;
    _notice = InstallNotice.none;
    _stop = null;
    _written = partial;
    _lastProgress = DateTime.now();
    _emit(InstallState(
      InstallStage.downloading,
      model: model,
      partialBytes: partial,
      progress: DownloadProgress(received: partial, total: model.bytes),
      secondAttempt: secondAttempt,
    ));
    unawaited(host.keepAwake(true));
    if (previous != null) {
      previous.cancel();
      await previous.result.then((_) {}, onError: (_) {});
      if (generation != _generation) return;
    }
    _startSpaceChecks(model, generation);
    final ModelTransfer transfer;
    try {
      final arriving = host.download(model, _target!, (progress) {
        if (generation != _generation) return;
        _lastProgress = DateTime.now();
        if (!progress.checking) _written = progress.received;
        _emit(InstallState(
          InstallStage.downloading,
          model: model,
          partialBytes: partial,
          progress: progress,
          secondAttempt: secondAttempt,
        ));
      });
      _arriving = arriving;
      transfer = await arriving;
    } catch (error) {
      if (generation == _generation) {
        _arriving = null;
        await _downloadFailed(generation, model, error);
      }
      return;
    }
    if (generation != _generation) {
      transfer.cancel();
      return;
    }
    _arriving = null;
    _transfer = transfer;
    if (_stop != null) transfer.cancel();
    transfer.result.then(
      (file) async {
        if (generation != _generation) return;
        _transfer = null;
        _stopSpaceChecks();
        await _downloaded(generation, model, file);
      },
      onError: (Object error) async {
        if (generation != _generation) return;
        _transfer = null;
        _stopSpaceChecks();
        await _downloadFailed(generation, model, error);
      },
    );
  }

  Future<void> _downloaded(int generation, ModelFile model, File file) async {
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
      if (generation == _generation) _fail(InstallProblem.storage, missing: 1);
      return;
    }
    if (generation != _generation) return;
    await _startModel();
  }

  Future<void> _startModel() async {
    final path = modelPath;
    final model = _model;
    if (path == null || model == null) return;
    final epoch = ++_epoch;
    _emit(InstallState(InstallStage.starting, model: model));
    unawaited(host.keepAwake(true));
    try {
      await host.start(path);
      if (epoch == _epoch) _emit(InstallState(InstallStage.ready, model: model));
    } catch (_) {
      if (epoch == _epoch) _fail(InstallProblem.loadFailed);
    } finally {
      unawaited(host.keepAwake(false));
    }
  }

  Future<void> _downloadFailed(int generation, ModelFile model, Object error) async {
    final failure = error is ModelDownloadException ? error.failure : DownloadFailure.server;
    final stop = _stop;
    _stop = null;
    unawaited(host.keepAwake(false));
    if (failure == DownloadFailure.cancelled || stop != null) {
      final partial = await _partLength();
      if (generation != _generation) return;
      switch (stop ?? _Stop.user) {
        case _Stop.storage:
          final free = _directory == null ? null : await host.freeBytes(_directory!);
          if (generation != _generation) return;
          final needed = model.bytes - partial + reserveBytes;
          _fail(InstallProblem.storage, missing: math.max(1, needed - (free ?? 0)), partial: partial);
        case _Stop.mobileData:
          _pausedForMobile = true;
          _notice = InstallNotice.pausedForMobileData;
          await _offerAgain(generation, model, partial);
        case _Stop.user:
          await _offerAgain(generation, model, partial);
      }
      return;
    }
    switch (failure) {
      case DownloadFailure.checksum:
        if (!_checksumRetried) {
          _checksumRetried = true;
          if (await _network() == NetworkKind.metered && !_mobileAllowed) {
            if (generation != _generation) return;
            _notice = InstallNotice.retryAfterDamage;
            await _offerAgain(generation, model, 0);
            return;
          }
          if (generation != _generation) return;
          await _startTransfer(model, 0, secondAttempt: true);
          return;
        }
        _fail(InstallProblem.checksum);
      case DownloadFailure.storage:
        final partial = await _partLength();
        final free = _directory == null ? null : await host.freeBytes(_directory!);
        if (generation != _generation) return;
        final needed = model.bytes - partial + reserveBytes;
        _fail(InstallProblem.storage, missing: math.max(1, needed - (free ?? 0)), partial: partial);
      case DownloadFailure.network:
        final partial = await _partLength();
        if (generation == _generation) _fail(InstallProblem.offline, partial: partial);
      case DownloadFailure.server:
      case DownloadFailure.cancelled:
        final partial = await _partLength();
        if (generation == _generation) _fail(InstallProblem.server, partial: partial);
    }
  }

  Future<void> _offerAgain(int generation, ModelFile model, int partial) async {
    final network = await _network();
    final free = _directory == null ? null : await host.freeBytes(_directory!);
    if (generation != _generation) return;
    _emit(_offer(model, partial: partial, free: free, network: network));
  }

  InstallState _offer(ModelFile model, {required int partial, int? free, required NetworkKind network}) {
    return InstallState(
      InstallStage.offer,
      model: model,
      partialBytes: partial,
      freeBytes: free,
      onMobileData: network == NetworkKind.metered,
      notice: _notice,
    );
  }

  void _fail(InstallProblem problem, {int missing = 0, int partial = 0}) {
    unawaited(host.keepAwake(false));
    _emit(InstallState(
      InstallStage.failed,
      model: _state.model ?? _model,
      problem: problem,
      missingBytes: missing,
      partialBytes: partial,
    ));
  }

  void _startSpaceChecks(ModelFile model, int generation) {
    _stopSpaceChecks();
    final directory = _directory;
    if (directory == null) return;
    _spaceCheck = Timer.periodic(spaceInterval, (_) async {
      if (_checkingSpace || generation != _generation || _state.stage != InstallStage.downloading) return;
      _checkingSpace = true;
      try {
        final free = await host.freeBytes(directory);
        if (free == null || generation != _generation || _state.stage != InstallStage.downloading) return;
        if (free - (model.bytes - _written) < reserveBytes ~/ 2) _requestStop(_Stop.storage);
      } catch (_) {
        return;
      } finally {
        _checkingSpace = false;
      }
    });
  }

  void _stopSpaceChecks() {
    _spaceCheck?.cancel();
    _spaceCheck = null;
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
      return NetworkKind.unmetered;
    }
  }

  void _networkChanged(NetworkKind network) {
    switch (_state.stage) {
      case InstallStage.offer:
        if (_pausedForMobile && network == NetworkKind.unmetered) {
          unawaited(install());
          return;
        }
        final metered = network == NetworkKind.metered;
        if (metered == _state.onMobileData) return;
        final model = _state.model;
        if (model == null) return;
        _emit(_offer(model, partial: _state.partialBytes, free: _state.freeBytes, network: network));
      case InstallStage.downloading:
        if (network == NetworkKind.metered && !_mobileAllowed) _requestStop(_Stop.mobileData);
      default:
        break;
    }
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
    _epoch++;
    _stallCheck?.cancel();
    _stopSpaceChecks();
    _transfer?.cancel();
    unawaited(_arriving?.then((transfer) => transfer.cancel(), onError: (_) {}));
    unawaited(_networkSubscription?.cancel());
    unawaited(host.keepAwake(false));
    super.dispose();
  }
}
