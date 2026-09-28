// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:app/services/assistant/local_model/model_downloader.dart';
import 'package:app/services/assistant/local_model/model_installer.dart';
import 'package:app/services/assistant/local_model/model_manifest.dart';

const testModel = ModelFile(
  repository: 'test/model',
  revision: 'abc',
  fileName: 'model.gguf',
  bytes: 1000,
  sha256: 'feed',
);

class FakeTransfer implements ModelTransfer {
  FakeTransfer(this.target, this.onProgress);

  final File target;
  final void Function(DownloadProgress progress) onProgress;
  final completer = Completer<File>();
  bool cancelled = false;
  int reconnects = 0;

  @override
  Future<File> get result => completer.future;

  @override
  void cancel() {
    cancelled = true;
    fail(DownloadFailure.cancelled);
  }

  @override
  void reconnect() => reconnects++;

  Future<void> finish() async {
    await target.writeAsBytes(List.filled(testModel.bytes, 1));
    await ModelDownloader.partOf(target).delete().catchError((_) => ModelDownloader.partOf(target));
    if (!completer.isCompleted) completer.complete(target);
  }

  void fail(DownloadFailure failure) {
    if (!completer.isCompleted) completer.completeError(ModelDownloadException(failure));
  }
}

class FakeInstallHost implements ModelInstallHost {
  FakeInstallHost(this.directory);

  final String directory;
  ModelChoice choice = const ModelSupported(testModel);
  int? free = 50000000000;
  int? memory = 8000000000;
  NetworkKind net = NetworkKind.unmetered;
  Object? startError;
  Completer<void>? planGate;
  Completer<void>? downloadGate;
  int forgotten = 0;
  final transfers = <FakeTransfer>[];
  final awake = <bool>[];
  final protected = <String>[];
  final started = <String>[];
  final changes = StreamController<NetworkKind>.broadcast();

  @override
  Future<ModelPlan> plan() async {
    final gate = planGate;
    if (gate != null) await gate.future;
    return ModelPlan(choice: choice, directory: directory, freeBytes: free, totalMemory: memory);
  }

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
    final transfer = FakeTransfer(target, onProgress);
    transfers.add(transfer);
    final gate = downloadGate;
    if (gate != null) await gate.future;
    return transfer;
  }

  @override
  Future<void> start(String path) async {
    started.add(path);
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> forget() async => forgotten++;
}
