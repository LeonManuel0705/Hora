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
  ModelDownloadJob._(this.result, this._send);

  final Future<File> result;
  final void Function(String command) _send;

  static final _slots = <String, _Slot>{};

  void cancel() => _send(_cancelCommand);

  void reconnect() => _send(_reconnectCommand);

  static Future<ModelDownloadJob> start(
    ModelDownloadRequest request, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final target = request.target;
    final previous = _slots[target];
    final slot = _Slot();
    _slots[target] = slot;
    void release() {
      slot.finish();
      if (identical(_slots[target], slot)) _slots.remove(target);
    }

    if (previous != null) {
      previous.cancel();
      await previous.finished;
    }

    final port = ReceivePort();
    final completer = Completer<File>();
    SendPort? commands;
    final queued = <String>[];

    void finish() => port.close();

    port.listen((message) {
      if (message is SendPort) {
        commands = message;
        queued.forEach(message.send);
        queued.clear();
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
          target,
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
      release();
      rethrow;
    }

    final job = ModelDownloadJob._(completer.future, (command) {
      final open = commands;
      if (open == null) {
        queued.add(command);
      } else {
        open.send(command);
      }
    });
    slot.attach(job);
    unawaited(job.result.then((_) {}, onError: (_) {}).whenComplete(release));
    return job;
  }

  static const _cancelCommand = 'cancel';
  static const _reconnectCommand = 'reconnect';

  static Future<void> _run(List<Object?> args) async {
    final events = args[0] as SendPort;
    final commands = ReceivePort();
    final token = DownloadCancelToken();
    commands.listen((message) {
      if (message == _cancelCommand) token.cancel();
      if (message == _reconnectCommand) token.reconnect();
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

class _Slot {
  final _finished = Completer<void>();
  ModelDownloadJob? _job;
  bool _cancelled = false;

  Future<void> get finished => _finished.future;

  void cancel() {
    _cancelled = true;
    _job?.cancel();
  }

  void attach(ModelDownloadJob job) {
    _job = job;
    if (_cancelled) job.cancel();
  }

  void finish() {
    if (!_finished.isCompleted) _finished.complete();
  }
}
