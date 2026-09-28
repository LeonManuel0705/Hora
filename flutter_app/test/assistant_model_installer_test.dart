// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:app/services/assistant/local_model/model_downloader.dart';
import 'package:app/services/assistant/local_model/model_installer.dart';
import 'package:app/services/assistant/local_model/model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _model = ModelFile(
  repository: 'test/model',
  revision: 'abc',
  fileName: 'model.gguf',
  bytes: 1000,
  sha256: 'feed',
);

class _Transfer implements ModelTransfer {
  _Transfer(this.target, this.onProgress);

  final File target;
  final void Function(DownloadProgress progress) onProgress;
  final _completer = Completer<File>();
  bool cancelled = false;

  @override
  Future<File> get result => _completer.future;

  @override
  void cancel() {
    cancelled = true;
    fail(DownloadFailure.cancelled);
  }

  Future<void> finish() async {
    await target.writeAsBytes(List.filled(_model.bytes, 1));
    await ModelDownloader.partOf(target).delete().catchError((_) => ModelDownloader.partOf(target));
    if (!_completer.isCompleted) _completer.complete(target);
  }

  void fail(DownloadFailure failure) {
    if (!_completer.isCompleted) _completer.completeError(ModelDownloadException(failure));
  }
}

class _Host implements ModelInstallHost {
  _Host(this.directory);

  final String directory;
  ModelChoice choice = const ModelSupported(_model);
  int? free = 50000000000;
  int? memory = 8000000000;
  NetworkKind net = NetworkKind.wifi;
  Object? startError;
  final transfers = <_Transfer>[];
  final awake = <bool>[];
  final protected = <String>[];
  final started = <String>[];
  final changes = StreamController<NetworkKind>.broadcast();

  @override
  Future<ModelPlan> plan() async =>
      ModelPlan(choice: choice, directory: directory, freeBytes: free, totalMemory: memory);

  @override
  Future<int?> freeBytes(String directory) async => free;

  @override
  Future<NetworkKind> network() async => net;

  @override
  Stream<NetworkKind> get networkChanges => changes.stream;

  @override
  Future<void> keepAwake(bool on) async => awake.add(on);

  @override
  Future<void> protect(String path) async => protected.add(path);

  @override
  Future<ModelTransfer> download(ModelFile model, File target, void Function(DownloadProgress progress) onProgress) async {
    final transfer = _Transfer(target, onProgress);
    transfers.add(transfer);
    return transfer;
  }

  @override
  Future<void> start(String path) async {
    started.add(path);
    final error = startError;
    if (error != null) throw error;
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late Directory dir;
  late _Host host;
  late ModelInstaller installer;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('model_installer_test');
    host = _Host(dir.path);
    installer = ModelInstaller(host, reserveBytes: 100, stallTimeout: const Duration(milliseconds: 30));
  });

  tearDown(() async {
    installer.dispose();
    await host.changes.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File part() => File('${dir.path}/${_model.fileName}.part');

  test('a fresh phone is offered the install with size and free space', () async {
    await installer.refresh();
    final state = installer.state;
    expect(state.stage, InstallStage.offer);
    expect(state.model, _model);
    expect(state.freeBytes, 50000000000);
    expect(state.partialBytes, 0);
    expect(state.onMobileData, isFalse);
  });

  test('unsupported phones get the reason and their memory', () async {
    host
      ..choice = const ModelUnsupported(ModelUnsupportedReason.memory)
      ..memory = 3700000000;
    await installer.refresh();
    expect(installer.state.stage, InstallStage.unsupported);
    expect(installer.state.unsupported, ModelUnsupportedReason.memory);
    expect(installer.state.totalMemory, 3700000000);
    expect(await installer.install(), InstallStart.blocked);
    expect(host.transfers, isEmpty);
  });

  test('install, verify, start and open', () async {
    await installer.refresh();
    expect(await installer.install(), InstallStart.started);
    expect(installer.state.stage, InstallStage.downloading);
    expect(host.awake.last, isTrue);

    host.transfers.single.onProgress(const DownloadProgress(received: 400, total: 1000, bytesPerSecond: 100));
    expect(installer.state.progress?.received, 400);

    await host.transfers.single.finish();
    await _settle();
    expect(installer.state.stage, InstallStage.ready);
    expect(host.protected.single, endsWith(_model.fileName));
    expect(host.started.single, installer.modelPath);
    expect(host.awake.last, isFalse);

    installer.open();
    expect(installer.state.stage, InstallStage.installed);

    final again = ModelInstaller(_Host(dir.path));
    await again.refresh();
    expect(again.state.stage, InstallStage.installed);
    again.dispose();
  });

  test('a double tap starts only one download', () async {
    await installer.refresh();
    final results = await Future.wait([installer.install(), installer.install()]);
    expect(results, everyElement(InstallStart.started));
    expect(host.transfers, hasLength(1));
  });

  test('mobile data needs an explicit yes', () async {
    host.net = NetworkKind.mobile;
    await installer.refresh();
    expect(installer.state.onMobileData, isTrue);
    expect(await installer.install(), InstallStart.needsMobileConfirmation);
    expect(host.transfers, isEmpty);
    expect(installer.state.stage, InstallStage.offer);
    expect(await installer.install(allowMobileData: true), InstallStart.started);
    expect(host.transfers, hasLength(1));
  });

  test('offline fails right away and retry starts once the phone is back online', () async {
    host.net = NetworkKind.none;
    await installer.refresh();
    expect(await installer.install(), InstallStart.blocked);
    expect(installer.state.stage, InstallStage.failed);
    expect(installer.state.problem, InstallProblem.offline);
    expect(host.transfers, isEmpty);

    host.net = NetworkKind.wifi;
    expect(await installer.retry(), InstallStart.started);
    expect(installer.state.stage, InstallStage.downloading);
  });

  test('too little space reports how much is missing, counting what is already there', () async {
    await part().writeAsBytes(List.filled(300, 1));
    host.free = 500;
    await installer.refresh();
    expect(installer.state.partialBytes, 300);
    expect(await installer.install(), InstallStart.blocked);
    expect(installer.state.problem, InstallProblem.storage);
    expect(installer.state.missingBytes, 1000 - 300 + 100 - 500);
  });

  test('a broken file is loaded once more from scratch, then reported', () async {
    await installer.refresh();
    await installer.install();
    host.transfers.single.fail(DownloadFailure.checksum);
    await _settle();
    expect(installer.state.stage, InstallStage.downloading);
    expect(installer.state.secondAttempt, isTrue);
    expect(host.transfers, hasLength(2));

    host.transfers.last.fail(DownloadFailure.checksum);
    await _settle();
    expect(installer.state.stage, InstallStage.failed);
    expect(installer.state.problem, InstallProblem.checksum);
  });

  test('cancel keeps the part and offers to continue', () async {
    await installer.refresh();
    await installer.install();
    await part().writeAsBytes(List.filled(420, 1));
    installer.cancel();
    await _settle();
    expect(host.transfers.single.cancelled, isTrue);
    expect(installer.state.stage, InstallStage.offer);
    expect(installer.state.partialBytes, 420);
    expect(host.awake.last, isFalse);
    expect(await part().exists(), isTrue);
  });

  test('network and server trouble end up as their own errors', () async {
    await installer.refresh();
    await installer.install();
    host.transfers.single.fail(DownloadFailure.network);
    await _settle();
    expect(installer.state.problem, InstallProblem.offline);

    await installer.retry();
    host.transfers.last.fail(DownloadFailure.server);
    await _settle();
    expect(installer.state.problem, InstallProblem.server);
  });

  test('a model that does not start can be retried without a new download', () async {
    host.startError = StateError('no memory');
    await installer.refresh();
    await installer.install();
    await host.transfers.single.finish();
    await _settle();
    expect(installer.state.stage, InstallStage.failed);
    expect(installer.state.problem, InstallProblem.loadFailed);

    host.startError = null;
    await installer.retry();
    expect(installer.state.stage, InstallStage.ready);
    expect(host.transfers, hasLength(1));
    expect(host.started, hasLength(2));
  });

  test('remove deletes everything and offers the install again', () async {
    await installer.refresh();
    await installer.install();
    await host.transfers.single.finish();
    await _settle();
    installer.open();
    await installer.remove();
    expect(installer.state.stage, InstallStage.offer);
    expect(await File(installer.modelPath!).exists(), isFalse);
    expect(await dir.list().isEmpty, isTrue);
  });

  test('the mobile hint follows the connection', () async {
    await installer.refresh();
    host.changes.add(NetworkKind.mobile);
    await _settle();
    expect(installer.state.onMobileData, isTrue);
    host.changes.add(NetworkKind.wifi);
    await _settle();
    expect(installer.state.onMobileData, isFalse);
  });

  test('old files go, an unmarked finished file is checked again', () async {
    await File('${dir.path}/old-model.gguf').writeAsBytes([1, 2, 3]);
    await File('${dir.path}/${_model.fileName}').writeAsBytes(List.filled(_model.bytes, 1));
    await installer.refresh();
    expect(installer.state.stage, InstallStage.offer);
    await installer.install();
    expect(await File('${dir.path}/old-model.gguf').exists(), isFalse);
    expect(await File('${dir.path}/${_model.fileName}').exists(), isFalse);
    expect(await part().length(), _model.bytes);
  });

  test('a download that stalled while the app was away restarts on return', () async {
    await installer.refresh();
    await installer.install();
    installer.appPaused();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    installer.appResumed();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(host.transfers.first.cancelled, isTrue);
    expect(host.transfers, hasLength(2));
    expect(installer.state.stage, InstallStage.downloading);
  });

  test('a download that kept going is left alone', () async {
    await installer.refresh();
    await installer.install();
    installer.appPaused();
    installer.appResumed();
    final transfer = host.transfers.single;
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      transfer.onProgress(DownloadProgress(received: 100 + i, total: 1000));
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(transfer.cancelled, isFalse);
    expect(host.transfers, hasLength(1));
  });
}
