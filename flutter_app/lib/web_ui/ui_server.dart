// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_api.dart';
import 'ui_pages.dart';

class UiServer {
  UiServer._();

  static final UiServer instance = UiServer._();
  static const preferredPort = 47291;
  static const _cookie = 'ui_key';
  static const _maxBody = 1024 * 1024;
  static const pages = uiPageRoutes;
  static String policy(String nonce) => UiPages.policy(nonce);

  String _token = _randomToken();
  final UiPages _pages = UiPages();
  final Map<String, (Uint8List, String)> _assets = {};
  HttpServer? _server;
  Future<void>? _starting;
  UiApi _api = UiApi(null);

  String get token => _token;

  int get port => _server?.port ?? 0;

  String get origin => 'http://127.0.0.1:$port';

  static String _randomToken() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
  }

  Uri entry([String path = '/hub']) =>
      Uri.parse('$origin/auth').replace(queryParameters: {'key': token, 'next': path});

  Future<void> start({UiHost? host}) {
    if (host != null) _api = UiApi(host);
    return _starting ??= _bind().catchError((Object error) {
      _starting = null;
      throw error;
    });
  }

  Future<void> _bind() async {
    if (kDebugMode) {
      final debug = (await SharedPreferences.getInstance()).getString('ui_debug_token');
      if (debug != null && debug.length >= 16) _token = debug;
    }
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, preferredPort);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    server.autoCompress = true;
    server.listen(_handle, onError: (Object _) {}, cancelOnError: false);
    _server = server;
  }

  Future<bool> ensureAlive() async {
    final server = _server;
    if (server == null) {
      await start();
      return false;
    }
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final request = await client.get('127.0.0.1', server.port, '/ping').timeout(const Duration(seconds: 1));
      final response = await request.close().timeout(const Duration(seconds: 1));
      await response.drain<void>();
      if (response.statusCode == HttpStatus.noContent) return true;
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    try {
      await server.close(force: true);
    } catch (_) {}
    _server = null;
    _starting = null;
    await start();
    return false;
  }

  bool _sameHost(HttpRequest request) {
    final host = request.headers.host;
    return host == '127.0.0.1' && request.headers.port == port;
  }

  bool _authorized(HttpRequest request) {
    for (final cookie in request.cookies) {
      if (cookie.name == _cookie && _same(cookie.value, token)) return true;
    }
    return false;
  }

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  void _secure(HttpResponse response) {
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Frame-Options', 'DENY');
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      _secure(response);
      final path = request.uri.path;
      if (!_sameHost(request)) return _plain(response, HttpStatus.forbidden);
      if (path == '/ping') return _plain(response, HttpStatus.noContent);
      if (path == '/auth') return _auth(request);
      if (!_authorized(request)) return _plain(response, HttpStatus.forbidden);
      final origin = request.headers.value('origin');
      if (request.method != 'GET' && origin != null && origin != this.origin) return _plain(response, HttpStatus.forbidden);
      if (path == '/' || path == '/hub/') return _redirect(response, '/hub');
      if (path.startsWith('/static/')) return await _asset(request, path.substring(8));
      if (path.startsWith('/api/')) return await _apiCall(request);
      final page = pages[path];
      if (page != null && request.method == 'GET') return await _page(request, page);
      _plain(response, HttpStatus.notFound);
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'success': false, 'error': 'Interner Fehler'}));
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void _plain(HttpResponse response, int status) {
    response.statusCode = status;
  }

  void _redirect(HttpResponse response, String target) {
    response.statusCode = HttpStatus.seeOther;
    response.headers.set(HttpHeaders.locationHeader, target);
  }

  void _auth(HttpRequest request) {
    final response = request.response;
    final key = request.uri.queryParameters['key'] ?? '';
    if (!_same(key, token)) return _plain(response, HttpStatus.forbidden);
    var next = request.uri.queryParameters['next'] ?? '/hub';
    if (!next.startsWith('/hub') || next.contains('//') || next.contains('\\')) next = '/hub';
    response.cookies.add(Cookie(_cookie, token)
      ..httpOnly = true
      ..path = '/'
      ..sameSite = SameSite.strict);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    _redirect(response, next);
  }

  Future<void> _asset(HttpRequest request, String relative) async {
    final response = request.response;
    if (request.method != 'GET' || relative.isEmpty || relative.contains('..') || relative.startsWith('/')) {
      return _plain(response, HttpStatus.notFound);
    }
    var asset = _assets[relative];
    if (asset == null) {
      try {
        final data = await rootBundle.load('assets/ui/static/$relative');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        asset = (bytes, _fingerprint(bytes));
        _assets[relative] = asset;
      } catch (_) {
        return _plain(response, HttpStatus.notFound);
      }
    }
    final (bytes, tag) = asset;
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.etagHeader, tag);
    if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == tag) {
      response.statusCode = HttpStatus.notModified;
      return;
    }
    response.headers.set(HttpHeaders.contentTypeHeader, uiContentType(relative));
    response.add(bytes);
  }

  static String _fingerprint(Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return '"${bytes.length.toRadixString(16)}-${hash.toRadixString(16)}"';
  }

  static String scriptJson(Object? value) => UiPages.scriptJson(value);

  Future<void> _page(HttpRequest request, String page) async {
    final response = request.response;
    final nonce = UiPages.nonce();
    final html = await _pages.render(page, nonce: nonce, day: request.uri.queryParameters['datum']);
    response.headers
      ..set(HttpHeaders.contentTypeHeader, uiContentTypes['html']!)
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('Content-Security-Policy', policy(nonce));
    response.write(html);
  }

  Future<void> _apiCall(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments.skip(1).toList();
    final type = request.headers.contentType?.mimeType;
    final json = type == 'application/json';
    Object? body;
    if (request.method != 'GET' && request.method != 'DELETE') {
      if ((request.contentLength) > _maxBody) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBody) {
          response.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
      }
      if (json && bytes.isNotEmpty) {
        try {
          body = jsonDecode(utf8.decode(bytes));
        } catch (_) {
          response.statusCode = HttpStatus.badRequest;
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'success': false, 'error': 'Ungültiges JSON'}));
          return;
        }
      }
    }
    final reply = await _api.handle(UiRequest(
      method: request.method,
      segments: segments,
      query: request.uri.queryParameters,
      json: json,
      body: body,
    ));
    response.statusCode = reply.status;
    response.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(reply.body));
  }
}
