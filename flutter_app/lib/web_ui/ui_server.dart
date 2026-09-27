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
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../brand.dart';
import '../build_info.dart';
import 'ui_api.dart';
import 'ui_data.dart';
import 'ui_db.dart';

class UiServer {
  UiServer._();

  static final UiServer instance = UiServer._();
  static const preferredPort = 47291;
  static const _cookie = 'ui_key';
  static const _maxBody = 1024 * 1024;
  static const pages = {
    '/hub': 'home',
    '/hub/tasks': 'tasks',
    '/hub/calendar': 'calendar',
    '/hub/school': 'school',
    '/hub/vbb': 'vbb',
    '/hub/email': 'email',
    '/hub/settings': 'settings',
  };
  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'svg': 'image/svg+xml',
    'woff2': 'font/woff2',
    'png': 'image/png',
    'json': 'application/json; charset=utf-8',
    'txt': 'text/plain; charset=utf-8',
  };
  static const _policy = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; "
      "img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";

  String _token = _randomToken();
  final Map<String, String> _templates = {};
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
    final extension = relative.contains('.') ? relative.substring(relative.lastIndexOf('.') + 1) : '';
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.etagHeader, tag);
    if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == tag) {
      response.statusCode = HttpStatus.notModified;
      return;
    }
    response.headers.set(HttpHeaders.contentTypeHeader, _types[extension] ?? 'application/octet-stream');
    response.add(bytes);
  }

  static String _fingerprint(Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return '"${bytes.length.toRadixString(16)}-${hash.toRadixString(16)}"';
  }

  Future<String> _template(String page) async =>
      _templates[page] ??= await rootBundle.loadString('assets/ui/pages/$page.html', cache: false);

  static String scriptJson(Object? value) => jsonEncode(value)
      .replaceAll('<', r'\u003c')
      .replaceAll('>', r'\u003e')
      .replaceAll('&', r'\u0026')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');

  static String _escape(String value) => const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

  String _theme(Map<String, Object?> store, SharedPreferences prefs) {
    final choice = store['app-theme-choice'];
    if (choice == 'light' || choice == 'dark') return choice as String;
    if (store.containsKey('app-theme-choice')) return 'auto';
    if ((prefs.getString('theme_switch_mode') ?? 'system') == 'system') return 'auto';
    final mode = prefs.getString('theme_mode');
    return mode == 'dark' || mode == 'light' ? mode! : 'auto';
  }

  Future<void> _page(HttpRequest request, String page) async {
    final response = request.response;
    final db = await UiDb.open();
    final prefs = await SharedPreferences.getInstance();
    final store = await UiDb.store(db);
    final pinned = isoDay(request.uri.queryParameters['datum']);
    final current = DateTime.now();
    final now = pinned == null
        ? current
        : dayOf(pinned).add(Duration(hours: current.hour, minutes: current.minute, seconds: current.second));
    final data = await UiData(db, prefs, now).build(page, store);
    final theme = _theme(store, prefs);
    final tasks = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tasks')) ?? 0;
    final tour = prefs.getString('tour_state') == null && prefs.containsKey('user_bundesland') && tasks == 0;
    final values = {
      '__APP_BRAND__': _escape(Brand.name),
      '__APP_THEME__': theme,
      '__APP_SCHEME__': theme == 'dark' ? 'dark' : 'light',
      '__APP_MOTION__': store['app-motion'] == 'minimal' ? 'minimal' : 'calm',
      '__APP_TOUR__': tour ? '1' : '0',
      '__APP_VERSION__': _escape(BuildInfo.version),
      '__APP_DATA__': scriptJson(data),
      '__APP_STORE__': scriptJson(store),
    };
    final html = (await _template(page)).replaceAllMapped(RegExp(r'__APP_[A-Z]+__'), (match) => values[match[0]] ?? match[0]!);
    response.headers
      ..set(HttpHeaders.contentTypeHeader, _types['html']!)
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('Content-Security-Policy', _policy);
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
