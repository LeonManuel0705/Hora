// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app/services/assistant/local_model/model_download_job.dart';
import 'package:app/services/assistant/local_model/model_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class _Server {
  _Server._(this.server, this.content);

  final HttpServer server;
  final Uint8List content;
  final ranges = <String?>[];
  final paths = <String>[];
  bool ignoreRange = false;
  int? dropAfter;
  Duration chunkDelay = Duration.zero;
  int chunkSize = 64 * 1024;
  Map<String, String> redirects = {};
  int? status;

  static Future<_Server> start(Uint8List content) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final wrapper = _Server._(server, content);
    server.listen(wrapper._handle);
    return wrapper;
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    paths.add(request.uri.path);
    final target = redirects[request.uri.path];
    if (target != null) {
      response.statusCode = HttpStatus.found;
      response.headers.set(HttpHeaders.locationHeader, target);
      await response.close();
      return;
    }
    if (status != null) {
      response.statusCode = status!;
      await response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    var start = 0;
    if (range != null && !ignoreRange) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
      if (start >= content.length) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${content.length - 1}/${content.length}');
    }
    response.contentLength = content.length - start;
    final drop = dropAfter;
    dropAfter = null;
    var sent = 0;
    for (var offset = start; offset < content.length; offset += chunkSize) {
      final end = min(offset + chunkSize, content.length);
      if (drop != null && sent >= drop) {
        try {
          await response.close();
        } catch (_) {}
        return;
      }
      response.add(content.sublist(offset, end));
      sent += end - offset;
      await response.flush();
      if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
    }
    await response.close();
  }

  Future<void> close() => server.close(force: true);
}

Uint8List _content(int length) {
  final random = Random(7);
  return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
}

void main() {
  late Directory dir;
  late Uint8List content;
  late String checksum;
  late _Server server;

  ModelDownloader downloader() => ModelDownloader(
        retryDelay: const Duration(milliseconds: 20),
        idleTimeout: const Duration(seconds: 5),
        progressInterval: Duration.zero,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('model_download_test');
    content = _content(700 * 1024 + 123);
    checksum = sha256.convert(content).toString();
    server = await _Server.start(content);
  });

  tearDown(() async {
    await server.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File target() => File('${dir.path}/model.gguf');

  test('downloads, verifies and renames into place', () async {
    final progress = <DownloadProgress>[];
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
      onProgress: progress.add,
    );
    expect(file.path, target().path);
    expect(await file.readAsBytes(), content);
    expect(await ModelDownloader.partOf(target()).exists(), isFalse);
    expect(progress.last.received, content.length);
    expect(server.ranges.single, isNull);
  });

  test('resumes a partial file with a range request and hashes the existing part first', () async {
    const existing = 300 * 1024;
    await ModelDownloader.partOf(target()).writeAsBytes(content.sublist(0, existing));
    final progress = <DownloadProgress>[];
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
      onProgress: progress.add,
    );
    expect(await file.readAsBytes(), content);
    expect(server.ranges.single, 'bytes=$existing-');
    expect(progress.where((p) => p.checking), isNotEmpty);
    expect(progress.where((p) => !p.checking).first.received, greaterThan(existing));
  });

  test('starts over when the server ignores the range', () async {
    server.ignoreRange = true;
    await ModelDownloader.partOf(target()).writeAsBytes(content.sublist(0, 1000));
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
    );
    expect(await file.readAsBytes(), content);
  });

  test('rejects a file with the wrong checksum and removes the part', () async {
    await expectLater(
      downloader().download(
        url: server.url('/model.gguf'),
        target: target(),
        bytes: content.length,
        checksum: 'a' * 64,
      ),
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.checksum)),
    );
    expect(await ModelDownloader.partOf(target()).exists(), isFalse);
    expect(await target().exists(), isFalse);
  });

  test('a corrupted part fails the checksum once it is complete', () async {
    final broken = Uint8List.fromList(content)..[10] ^= 0xff;
    await ModelDownloader.partOf(target()).writeAsBytes(broken.sublist(0, 400 * 1024));
    await expectLater(
      downloader().download(
        url: server.url('/model.gguf'),
        target: target(),
        bytes: content.length,
        checksum: checksum,
      ),
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.checksum)),
    );
    expect(await ModelDownloader.partOf(target()).exists(), isFalse);
  });

  test('cancel keeps the partial file and a later call resumes it', () async {
    server
      ..chunkSize = 16 * 1024
      ..chunkDelay = const Duration(milliseconds: 15);
    final token = DownloadCancelToken();
    await expectLater(
      downloader().download(
        url: server.url('/model.gguf'),
        target: target(),
        bytes: content.length,
        checksum: checksum,
        cancel: token,
        onProgress: (progress) {
          if (progress.received >= 100 * 1024) token.cancel();
        },
      ),
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.cancelled)),
    );
    final part = ModelDownloader.partOf(target());
    final kept = await part.readAsBytes();
    expect(kept.length, greaterThanOrEqualTo(100 * 1024));
    expect(kept.length, lessThan(content.length));
    expect(kept, content.sublist(0, kept.length));
    expect(await target().exists(), isFalse);

    server.chunkDelay = Duration.zero;
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
    );
    expect(await file.readAsBytes(), content);
    expect(server.ranges.last, 'bytes=${kept.length}-');
  });

  test('follows relative and absolute redirects and keeps the range header', () async {
    server.redirects = {
      '/resolve/model.gguf': '/cdn/step',
      '/cdn/step': server.url('/files/model.gguf').toString(),
    };
    await ModelDownloader.partOf(target()).writeAsBytes(content.sublist(0, 5000));
    final file = await downloader().download(
      url: server.url('/resolve/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
    );
    expect(await file.readAsBytes(), content);
    expect(server.paths, ['/resolve/model.gguf', '/cdn/step', '/files/model.gguf']);
    expect(server.ranges.single, 'bytes=5000-');
  });

  test('gives up on redirect loops', () async {
    server.redirects = {'/a': '/b', '/b': '/a'};
    await expectLater(
      downloader().download(url: server.url('/a'), target: target(), bytes: content.length, checksum: checksum),
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.server)),
    );
  });

  test('resumes on its own after the connection drops', () async {
    server.dropAfter = 200 * 1024;
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
    );
    expect(await file.readAsBytes(), content);
    expect(server.ranges, hasLength(2));
    expect(server.ranges.last, startsWith('bytes='));
  });

  test('a dropped connection continues without hashing the part again', () async {
    server.dropAfter = 200 * 1024;
    final progress = <DownloadProgress>[];
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
      onProgress: progress.add,
    );
    expect(await file.readAsBytes(), content);
    expect(server.ranges, hasLength(2));
    expect(progress.where((p) => p.checking), isEmpty);
  });

  test('reconnect opens a fresh connection and keeps the running hash', () async {
    server
      ..chunkSize = 16 * 1024
      ..chunkDelay = const Duration(milliseconds: 10);
    final token = DownloadCancelToken();
    final progress = <DownloadProgress>[];
    var asked = false;
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
      cancel: token,
      onProgress: (p) {
        progress.add(p);
        if (!asked && p.received >= 150 * 1024) {
          asked = true;
          token.reconnect();
        }
      },
    );
    expect(await file.readAsBytes(), content);
    expect(server.ranges, hasLength(2));
    expect(server.ranges.last, startsWith('bytes='));
    expect(progress.where((p) => p.checking), isEmpty);
  });

  test('a second job for the same file stops the first before it writes', () async {
    server
      ..chunkSize = 8 * 1024
      ..chunkDelay = const Duration(milliseconds: 15);
    final request = ModelDownloadRequest(
      url: server.url('/model.gguf'),
      target: target().path,
      bytes: content.length,
      checksum: checksum,
    );
    final seen = Completer<void>();
    final first = await ModelDownloadJob.start(request, onProgress: (p) {
      if (p.received > 0 && !seen.isCompleted) seen.complete();
    });
    await seen.future;
    server.chunkDelay = Duration.zero;
    final second = await ModelDownloadJob.start(request);
    await expectLater(
      first.result,
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.cancelled)),
    );
    expect(await (await second.result).readAsBytes(), content);
  });

  test('reports missing files as a server failure', () async {
    server.status = HttpStatus.notFound;
    await expectLater(
      downloader().download(url: server.url('/model.gguf'), target: target(), bytes: content.length, checksum: checksum),
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.server)),
    );
  });

  test('reports an unreachable server as a network failure', () async {
    final port = server.server.port;
    await server.close();
    await expectLater(
      downloader().download(
        url: Uri.parse('http://127.0.0.1:$port/model.gguf'),
        target: target(),
        bytes: content.length,
        checksum: checksum,
      ),
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.network)),
    );
  });

  test('a complete part is verified without a request', () async {
    await ModelDownloader.partOf(target()).writeAsBytes(content);
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
    );
    expect(await file.readAsBytes(), content);
    expect(server.paths, isEmpty);
  });

  test('a part longer than the file is thrown away', () async {
    await ModelDownloader.partOf(target()).writeAsBytes(Uint8List(content.length + 10));
    final file = await downloader().download(
      url: server.url('/model.gguf'),
      target: target(),
      bytes: content.length,
      checksum: checksum,
    );
    expect(await file.readAsBytes(), content);
    expect(server.ranges.single, isNull);
  });

  test('the background job downloads and can be cancelled', () async {
    final done = await ModelDownloadJob.start(ModelDownloadRequest(
      url: server.url('/model.gguf'),
      target: target().path,
      bytes: content.length,
      checksum: checksum,
    ));
    expect(await (await done.result).readAsBytes(), content);

    await target().delete();
    server
      ..chunkSize = 8 * 1024
      ..chunkDelay = const Duration(milliseconds: 20);
    final seen = Completer<void>();
    final job = await ModelDownloadJob.start(
      ModelDownloadRequest(url: server.url('/model.gguf'), target: target().path, bytes: content.length, checksum: checksum),
      onProgress: (progress) {
        if (progress.received > 0 && !seen.isCompleted) seen.complete();
      },
    );
    await seen.future;
    job.cancel();
    await expectLater(
      job.result,
      throwsA(isA<ModelDownloadException>().having((e) => e.failure, 'failure', DownloadFailure.cancelled)),
    );
    expect(await ModelDownloader.partOf(target()).length(), greaterThan(0));
  });
}
