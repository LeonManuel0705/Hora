// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum DownloadFailure { network, storage, checksum, server, cancelled }

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.failure, [this.detail = '']);

  final DownloadFailure failure;
  final String detail;

  @override
  String toString() => 'ModelDownloadException(${failure.name}${detail.isEmpty ? '' : ': $detail'})';
}

class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    this.bytesPerSecond = 0,
    this.checking = false,
  });

  final int received;
  final int total;
  final double bytesPerSecond;
  final bool checking;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);

  Duration? get remaining {
    if (checking || bytesPerSecond < 1 || received >= total) return null;
    return Duration(seconds: ((total - received) / bytesPerSecond).ceil());
  }
}

class DownloadCancelToken {
  final _callbacks = <void Function()>{};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List.of(_callbacks)) {
      callback();
    }
  }

  void _listen(void Function() callback) => _callbacks.add(callback);

  void _forget(void Function() callback) => _callbacks.remove(callback);
}

class ModelDownloader {
  ModelDownloader({
    this.userAgent,
    this.connectTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 30),
    this.maxRedirects = 8,
    this.attempts = 4,
    this.retryDelay = const Duration(seconds: 2),
    this.progressInterval = const Duration(milliseconds: 250),
  });

  final String? userAgent;
  final Duration connectTimeout;
  final Duration idleTimeout;
  final int maxRedirects;
  final int attempts;
  final Duration retryDelay;
  final Duration progressInterval;

  static const _flushBytes = 1 << 20;
  static const _redirects = {301, 302, 303, 307, 308};

  static File partOf(File target) => File('${target.path}.part');

  Future<File> download({
    required Uri url,
    required File target,
    required int bytes,
    required String checksum,
    DownloadCancelToken? cancel,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final token = cancel ?? DownloadCancelToken();
    final part = partOf(target);
    final reporter = _Reporter(onProgress, progressInterval);
    await target.parent.create(recursive: true);
    var failures = 0;
    var restarts = 0;
    while (true) {
      _check(token);
      final before = await _length(part);
      try {
        return await _attempt(url, target, part, bytes, checksum.toLowerCase(), token, reporter);
      } on _Restart catch (restart) {
        restarts++;
        await _delete(part);
        if (restarts > 2) throw ModelDownloadException(DownloadFailure.server, restart.reason);
      } on ModelDownloadException catch (error) {
        if (error.failure != DownloadFailure.network || token.isCancelled) rethrow;
        if (await _length(part) > before) failures = 0;
        failures++;
        if (failures >= attempts) rethrow;
        await _wait(retryDelay * failures, token);
      }
    }
  }

  Future<File> _attempt(
    Uri url,
    File target,
    File part,
    int bytes,
    String expected,
    DownloadCancelToken token,
    _Reporter reporter,
  ) async {
    var offset = await _length(part);
    if (offset > bytes) {
      await _delete(part);
      offset = 0;
    }
    var digest = _DigestSink();
    var hasher = sha256.startChunkedConversion(digest);
    if (offset > 0) {
      var hashed = 0;
      try {
        await for (final chunk in part.openRead(0, offset)) {
          _check(token);
          hasher.add(chunk);
          hashed += chunk.length;
          reporter.checking(hashed, bytes);
        }
      } on FileSystemException {
        throw const _Restart('part unreadable');
      }
      if (hashed != offset) throw const _Restart('part changed');
    }
    if (offset == bytes) {
      hasher.close();
      return _finish(digest, expected, part, target);
    }

    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..autoUncompress = false;
    if (userAgent != null) client.userAgent = userAgent;
    void abort() => client.close(force: true);
    token._listen(abort);
    RandomAccessFile? file;
    final pending = BytesBuilder(copy: false);
    try {
      final response = await _open(client, url, offset);
      var received = offset;
      switch (response.statusCode) {
        case HttpStatus.partialContent:
          final range = _ContentRange.parse(response.headers.value(HttpHeaders.contentRangeHeader));
          if (range == null || range.start != offset || (range.total != null && range.total != bytes)) {
            _discard(response);
            throw ModelDownloadException(DownloadFailure.server, 'unexpected range ${range?.text}');
          }
        case HttpStatus.ok:
          final length = response.contentLength;
          if (length >= 0 && length != bytes) {
            _discard(response);
            throw ModelDownloadException(DownloadFailure.server, 'unexpected size $length');
          }
          if (offset > 0) {
            digest = _DigestSink();
            hasher = sha256.startChunkedConversion(digest);
            received = 0;
          }
        case HttpStatus.requestedRangeNotSatisfiable:
          _discard(response);
          throw const _Restart('range not satisfiable');
        default:
          final status = response.statusCode;
          _discard(response);
          final transient = status >= 500 || status == HttpStatus.tooManyRequests || status == HttpStatus.requestTimeout;
          throw ModelDownloadException(transient ? DownloadFailure.network : DownloadFailure.server, 'HTTP $status');
      }

      reporter.restart(received);
      file = await part.open(mode: received == 0 ? FileMode.write : FileMode.append);
      await for (final chunk in response.timeout(idleTimeout)) {
        if (token.isCancelled) break;
        received += chunk.length;
        if (received > bytes) throw const _Restart('more data than expected');
        hasher.add(chunk);
        pending.add(chunk);
        if (pending.length >= _flushBytes) await file.writeFrom(pending.takeBytes());
        reporter.progress(received, bytes);
      }
      _check(token);
      if (pending.isNotEmpty) await file.writeFrom(pending.takeBytes());
      await file.close();
      file = null;
      if (received < bytes) throw const ModelDownloadException(DownloadFailure.network, 'connection ended early');
      reporter.progress(received, bytes, force: true);
      hasher.close();
      return await _finish(digest, expected, part, target);
    } on ModelDownloadException catch (error) {
      if (token.isCancelled && error.failure == DownloadFailure.network) throw _cancelled;
      rethrow;
    } on _Restart {
      rethrow;
    } on FileSystemException catch (error) {
      if (token.isCancelled) throw _cancelled;
      throw ModelDownloadException(DownloadFailure.storage, _noSpace(error) ? 'no space' : error.message);
    } on Object catch (error) {
      if (token.isCancelled) throw _cancelled;
      if (error is TimeoutException || error is IOException || error is HttpException || error is TlsException) {
        throw ModelDownloadException(DownloadFailure.network, '$error');
      }
      rethrow;
    } finally {
      token._forget(abort);
      final open = file;
      if (open != null) {
        try {
          if (pending.isNotEmpty) await open.writeFrom(pending.takeBytes());
        } catch (_) {}
        try {
          await open.close();
        } catch (_) {}
      }
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _open(HttpClient client, Uri url, int offset) async {
    var current = url;
    for (var hop = 0;; hop++) {
      final request = await client.getUrl(current).timeout(connectTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      final response = await request.close().timeout(connectTimeout);
      if (!_redirects.contains(response.statusCode)) return response;
      final location = response.headers.value(HttpHeaders.locationHeader);
      _discard(response);
      if (location == null || location.isEmpty) {
        throw const ModelDownloadException(DownloadFailure.server, 'redirect without location');
      }
      if (hop >= maxRedirects) throw const ModelDownloadException(DownloadFailure.server, 'too many redirects');
      final next = current.resolve(location);
      if (current.scheme == 'https' && next.scheme != 'https') {
        throw const ModelDownloadException(DownloadFailure.server, 'redirect leaves https');
      }
      current = next;
    }
  }

  Future<File> _finish(_DigestSink digest, String expected, File part, File target) async {
    final actual = digest.value?.toString();
    if (actual != expected) {
      await _delete(part);
      throw ModelDownloadException(DownloadFailure.checksum, 'got $actual');
    }
    return part.rename(target.path);
  }

  static const _cancelled = ModelDownloadException(DownloadFailure.cancelled);

  static void _check(DownloadCancelToken token) {
    if (token.isCancelled) throw _cancelled;
  }

  static void _discard(HttpClientResponse response) {
    response.listen(null, onError: (_) {}, cancelOnError: true).cancel().catchError((_) {});
  }

  static bool _noSpace(FileSystemException error) {
    final code = error.osError?.errorCode;
    return code == 28 || code == 112 || code == 39 || code == 69 || code == 122;
  }

  static Future<int> _length(File file) async {
    try {
      return await file.exists() ? await file.length() : 0;
    } on FileSystemException {
      return 0;
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  static Future<void> _wait(Duration delay, DownloadCancelToken token) async {
    final done = Completer<void>();
    final timer = Timer(delay, () {
      if (!done.isCompleted) done.complete();
    });
    void stop() {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    }

    token._listen(stop);
    await done.future;
    token._forget(stop);
    _check(token);
  }
}

class _Restart implements Exception {
  const _Restart(this.reason);

  final String reason;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _ContentRange {
  const _ContentRange(this.start, this.end, this.total, this.text);

  final int start;
  final int end;
  final int? total;
  final String text;

  static _ContentRange? parse(String? header) {
    if (header == null) return null;
    final match = RegExp(r'^\s*bytes\s+(\d+)-(\d+)/(\d+|\*)\s*$').firstMatch(header);
    if (match == null) return null;
    return _ContentRange(
      int.parse(match[1]!),
      int.parse(match[2]!),
      match[3] == '*' ? null : int.parse(match[3]!),
      header,
    );
  }
}

class _Reporter {
  _Reporter(this.callback, this.interval);

  final void Function(DownloadProgress progress)? callback;
  final Duration interval;
  final _clock = Stopwatch()..start();
  final _samples = <(int, int)>[];
  int _last = -1 << 40;

  void restart(int received) {
    _samples
      ..clear()
      ..add((_clock.elapsedMilliseconds, received));
  }

  void checking(int hashed, int total) {
    final now = _clock.elapsedMilliseconds;
    if (now - _last < interval.inMilliseconds && hashed < total) return;
    _last = now;
    callback?.call(DownloadProgress(received: hashed, total: total, checking: true));
  }

  void progress(int received, int total, {bool force = false}) {
    final now = _clock.elapsedMilliseconds;
    if (!force && now - _last < interval.inMilliseconds) return;
    _last = now;
    _samples.add((now, received));
    while (_samples.length > 2 && now - _samples.first.$1 > 6000) {
      _samples.removeAt(0);
    }
    final first = _samples.first;
    final span = now - first.$1;
    final speed = span >= 900 ? (received - first.$2) * 1000 / span : 0.0;
    callback?.call(DownloadProgress(received: received, total: total, bytesPerSecond: speed));
  }
}
