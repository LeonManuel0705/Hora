// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'model_downloader.dart';

class ModelDownloadRequest {
  const ModelDownloadRequest({
    required this.url,
    required this.target,
    required this.bytes,
    required this.checksum,
    this.userAgent,
  });

  final Uri url;
  final String target;
  final int bytes;
  final String checksum;
  final String? userAgent;
}

class ModelDownloadJob {
  ModelDownloadJob._(this.result, this._cancel);

  final Future<File> result;
  final void Function() _cancel;

  void cancel() => _cancel();

  static Future<ModelDownloadJob> start(
    ModelDownloadRequest request, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final port = ReceivePort();
    final completer = Completer<File>();
    SendPort? commands;
    var cancelled = false;

    void finish() => port.close();

    port.listen((message) {
      if (message is SendPort) {
        commands = message;
        if (cancelled) message.send(_cancelCommand);
        return;
      }
      if (message is Map) {
        switch (message['type']) {
          case 'progress':
            onProgress?.call(DownloadProgress(
              received: message['received'] as int,
              total: message['total'] as int,
              bytesPerSecond: (message['speed'] as num).toDouble(),
              checking: message['checking'] as bool,
            ));
          case 'done':
            if (!completer.isCompleted) completer.complete(File(message['path'] as String));
            finish();
          case 'error':
            if (!completer.isCompleted) {
              completer.completeError(ModelDownloadException(
                DownloadFailure.values[message['failure'] as int],
                message['detail'] as String,
              ));
            }
            finish();
        }
        return;
      }
      if (!completer.isCompleted) {
        completer.completeError(ModelDownloadException(DownloadFailure.network, 'worker stopped: $message'));
      }
      finish();
    });

    try {
      await Isolate.spawn(
        _run,
        <Object?>[
          port.sendPort,
          request.url.toString(),
          request.target,
          request.bytes,
          request.checksum,
          request.userAgent,
        ],
        onExit: port.sendPort,
        onError: port.sendPort,
        errorsAreFatal: true,
        debugName: 'model-download',
      );
    } catch (_) {
      port.close();
      rethrow;
    }

    return ModelDownloadJob._(completer.future, () {
      cancelled = true;
      commands?.send(_cancelCommand);
    });
  }

  static const _cancelCommand = 'cancel';

  static Future<void> _run(List<Object?> args) async {
    final events = args[0] as SendPort;
    final commands = ReceivePort();
    final token = DownloadCancelToken();
    commands.listen((message) {
      if (message == _cancelCommand) token.cancel();
    });
    events.send(commands.sendPort);
    try {
      final file = await ModelDownloader(userAgent: args[5] as String?).download(
        url: Uri.parse(args[1] as String),
        target: File(args[2] as String),
        bytes: args[3] as int,
        checksum: args[4] as String,
        cancel: token,
        onProgress: (progress) => events.send({
          'type': 'progress',
          'received': progress.received,
          'total': progress.total,
          'speed': progress.bytesPerSecond,
          'checking': progress.checking,
        }),
      );
      events.send({'type': 'done', 'path': file.path});
    } on ModelDownloadException catch (error) {
      events.send({'type': 'error', 'failure': error.failure.index, 'detail': error.detail});
    } catch (error) {
      events.send({'type': 'error', 'failure': DownloadFailure.network.index, 'detail': '$error'});
    } finally {
      commands.close();
    }
  }
}
