// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'ui_api.dart';
import 'ui_pages.dart';

class UiBridgeRequest {
  const UiBridgeRequest({
    required this.method,
    required this.path,
    this.query = '',
    this.body,
    this.contentType,
    this.navigate = false,
    this.from,
  });

  factory UiBridgeRequest.fromMessage(Map<Object?, Object?> message) => UiBridgeRequest(
        method: '${message['method'] ?? 'GET'}'.toUpperCase(),
        path: '${message['path'] ?? ''}',
        query: '${message['query'] ?? ''}',
        body: message['body'] is String ? message['body'] as String : null,
        contentType: message['contentType'] is String ? message['contentType'] as String : null,
        navigate: message['navigate'] == true,
        from: message['from'] is String ? message['from'] as String : null,
      );

  final String method;
  final String path;
  final String query;
  final String? body;
  final String? contentType;
  final bool navigate;
  final String? from;

  bool get fromHub => from == '/hub' || (from?.startsWith('/hub/') ?? false);

  Map<String, String> get parameters {
    try {
      return Uri.splitQueryString(query.startsWith('?') ? query.substring(1) : query);
    } catch (_) {
      return const {};
    }
  }
}

class UiBridgeReply {
  const UiBridgeReply(this.status, {this.headers = const {}, this.body});

  factory UiBridgeReply.json(int status, Object? value) => UiBridgeReply(
        status,
        headers: const {'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store'},
        body: jsonEncode(value),
      );

  final int status;
  final Map<String, String> headers;
  final Object? body;
}

typedef UiAssetLoader = Future<Uint8List> Function(String key);

class UiBridge {
  UiBridge({required this.api, required this.pages, required this.openNative, this.startScript, UiAssetLoader? assets})
      : _load = assets ?? _bundle;

  static const maxBody = 1024 * 1024;
  static const _skipped = {'klassisch'};

  final UiApi api;
  final UiPages pages;
  final Future<bool> Function(String name) openNative;
  final String? startScript;
  final UiAssetLoader _load;
  final Map<String, Uint8List> _assets = {};

  static Future<Uint8List> _bundle(String key) async {
    final data = await rootBundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<UiBridgeReply> handle(UiBridgeRequest request) async {
    try {
      if (request.navigate) return await _page(request);
      if (request.path.startsWith('/static/')) return await _asset(request, request.path.substring(8));
      if (request.path.startsWith('/api/')) return await _api(request);
      return const UiBridgeReply(404);
    } catch (_) {
      return UiBridgeReply.json(500, {'success': false, 'error': 'Interner Fehler'});
    }
  }

  static UiBridgeReply _missing() => const UiBridgeReply(
        404,
        headers: {'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store'},
        body: '<!doctype html><html lang="de"><meta charset="utf-8"><title>Nicht gefunden</title><p>Diese Seite gibt es nicht.</p></html>',
      );

  Future<UiBridgeReply> _page(UiBridgeRequest request) async {
    final path = request.path;
    if (path == '/hub/') return const UiBridgeReply(303, headers: {'Location': '/hub'});
    final page = uiPageRoutes[path];
    if (page != null) {
      if (request.method != 'GET') return const UiBridgeReply(405);
      final nonce = UiPages.nonce();
      final html = await pages.render(page, nonce: nonce, day: request.parameters['datum'], startScript: startScript);
      return UiBridgeReply(200, headers: {
        'Content-Type': uiContentTypes['html']!,
        'Cache-Control': 'no-store',
        'Content-Security-Policy': UiPages.policy(nonce, framed: true),
        'Referrer-Policy': 'same-origin',
        'X-Content-Type-Options': 'nosniff',
      }, body: html);
    }
    final segments = Uri.parse(path).pathSegments;
    if (segments.length == 2 && segments.first == 'hub' && request.fromHub) {
      if (_skipped.contains(segments[1]) || await openNative(segments[1])) return const UiBridgeReply(204);
    }
    return _missing();
  }

  Future<UiBridgeReply> _asset(UiBridgeRequest request, String relative) async {
    if (request.method != 'GET' || relative.isEmpty || relative.contains('..') || relative.startsWith('/')) {
      return const UiBridgeReply(404);
    }
    var bytes = _assets[relative];
    if (bytes == null) {
      try {
        bytes = await _load('assets/ui/static/$relative');
      } catch (_) {
        return const UiBridgeReply(404);
      }
      _assets[relative] = bytes;
    }
    return UiBridgeReply(200, headers: {'Content-Type': uiContentType(relative), 'X-Content-Type-Options': 'nosniff'}, body: bytes);
  }

  Future<UiBridgeReply> _api(UiBridgeRequest request) async {
    final json = (request.contentType ?? '').split(';').first.trim().toLowerCase() == 'application/json';
    Object? body;
    if (request.method != 'GET' && request.method != 'DELETE') {
      final text = request.body ?? '';
      if (text.length > maxBody || utf8.encode(text).length > maxBody) return const UiBridgeReply(413);
      if (json && text.isNotEmpty) {
        try {
          body = jsonDecode(text);
        } catch (_) {
          return UiBridgeReply.json(400, {'success': false, 'error': 'Ungültiges JSON'});
        }
      }
    }
    final reply = await api.handle(UiRequest(
      method: request.method,
      segments: Uri.parse(request.path).pathSegments.skip(1).toList(),
      query: request.parameters,
      json: json,
      body: body,
    ));
    return UiBridgeReply.json(reply.status, reply.body);
  }
}
