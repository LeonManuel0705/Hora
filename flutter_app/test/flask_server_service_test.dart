// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/flask_server_service.dart';

void main() {
  final flask = FlaskServerService();

  test('the hub itself counts as the hub', () {
    expect(flask.isHubUrl(flask.hubUrl), isTrue);
    expect(flask.isHubUrl('http://127.0.0.1:5050/hub/klassisch/school'), isTrue);
    expect(flask.isHubUrl('http://127.0.0.1:5050/hub/pomodoro?x=1#top'), isTrue);
  });

  test('look-alike addresses do not count as the hub', () {
    for (final url in [
      'http://localhost:5050/hub',
      'http://127.0.0.1:5050@attacker.example/',
      'http://127.0.0.1:5050.attacker.example/',
      'http://127.0.0.1:50501/hub',
      'http://127.0.0.1/hub',
      'https://127.0.0.1:5050/hub',
      'http://user@127.0.0.1:5050/hub',
      'http://[::1]:5050/hub',
      'http://0.0.0.0:5050/hub',
      'file:///etc/passwd',
      'javascript:alert(1)',
      '',
      'not a url',
    ]) {
      expect(flask.isHubUrl(url), isFalse, reason: url);
    }
  });

  test('the desktop token is 64 hex characters', () {
    expect(flask.desktopToken, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('netstat listeners on 127.0.0.1 are found in English and German output',
      () {
    const english = '''
Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1016\r
  TCP    127.0.0.1:5050         0.0.0.0:0              LISTENING       4242\r
  TCP    0.0.0.0:5050           0.0.0.0:0              LISTENING       6060\r
  TCP    [::]:5050              [::]:0                 LISTENING       5151\r
  TCP    [::1]:5050             [::]:0                 LISTENING       5252\r
  TCP    127.0.0.1:5050         127.0.0.1:51234        ESTABLISHED     4242\r
  TCP    127.0.0.1:51234        127.0.0.1:5050         ESTABLISHED     7777\r
  TCP    127.0.0.1:50501        0.0.0.0:0              LISTENING       8888\r
  UDP    127.0.0.1:5050         *:*                                    9999\r
''';
    const german = '''
Aktive Verbindungen

  Proto  Lokale Adresse         Remoteadresse          Status           PID
  TCP    127.0.0.1:5050         0.0.0.0:0              ABHÖREN         4242\r
  TCP    [::]:5050              [::]:0                 ABHÖREN         5151\r
  TCP    127.0.0.1:5050         127.0.0.1:51234        HERGESTELLT     4242\r
  TCP    127.0.0.1:51234        127.0.0.1:5050         HERGESTELLT     7777\r
''';
    expect(FlaskServerService.parseNetstatListeners(english, 5050), {4242});
    expect(FlaskServerService.parseNetstatListeners(german, 5050), {4242});
    expect(FlaskServerService.parseNetstatListeners(english, 5051), isEmpty);
  });

  test('the handshake MAC matches the backend formula', () {
    expect(
      FlaskServerService.handshakeMac('secret-desktop-token', 'ab' * 32),
      'f697551661345628b872d2e5ee45585ede16dfe543cc3d177be4ee161aef79e7',
    );
  });

  test('MACs only match when they are equal', () {
    final mac = FlaskServerService.handshakeMac('token', '00' * 32);
    final flipped = (mac[0] == 'a' ? 'b' : 'a') + mac.substring(1);
    expect(FlaskServerService.sameMac(mac, mac), isTrue);
    expect(FlaskServerService.sameMac(mac, flipped), isFalse);
    expect(FlaskServerService.sameMac(mac, mac.substring(1)), isFalse);
  });

  group('against a local server', () {
    const token = 'desktop-token-for-tests';

    Future<T> withServer<T>(
      void Function(HttpRequest request) respond,
      Future<T> Function(Uri base) body,
    ) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(respond);
      try {
        return await body(Uri.parse('http://127.0.0.1:${server.port}'));
      } finally {
        await server.close(force: true);
      }
    }

    void answer(HttpRequest request, int status, String body) {
      request.response
        ..statusCode = status
        ..write(body)
        ..close();
    }

    String nonceOf(HttpRequest request) =>
        request.uri.queryParameters['nonce'] ?? '';

    test('a backend that knows the token passes the handshake', () async {
      String? path;
      String? nonce;
      final ok = await withServer((request) {
        path = request.uri.path;
        nonce = nonceOf(request);
        answer(request, 200,
            jsonEncode({'mac': FlaskServerService.handshakeMac(token, nonce!)}));
      }, (base) => FlaskServerService.verifyBackend(base, token));
      expect(ok, isTrue);
      expect(path, '/api/desktop-handshake');
      expect(nonce, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('anything else fails the handshake', () async {
      final responses = <void Function(HttpRequest)>[
        (r) => answer(r, 200,
            jsonEncode({'mac': FlaskServerService.handshakeMac('other', nonceOf(r))})),
        (r) => answer(r, 200,
            jsonEncode({'mac': FlaskServerService.handshakeMac(token, '00' * 32)})),
        (r) => answer(r, 404, jsonEncode({'error': 'Not found'})),
        (r) => answer(r, 200, 'not json'),
        (r) => answer(r, 200, jsonEncode({'mac': 42})),
        (r) => answer(r, 200, 'x' * 10000),
        (r) => r.response
          ..statusCode = 302
          ..headers.set('location', 'http://127.0.0.1:9/')
          ..close(),
      ];
      for (final respond in responses) {
        expect(
          await withServer(
              respond, (base) => FlaskServerService.verifyBackend(base, token)),
          isFalse,
        );
      }
    });

    test('the login code is asked for with the token and checked', () async {
      String? method;
      String? header;
      final code = await withServer((request) {
        method = request.method;
        header = request.headers.value('x-hub-token');
        answer(request, 200, jsonEncode({'code': 'cd' * 32}));
      }, (base) => FlaskServerService.requestLoginCode(base, token));
      expect(code, 'cd' * 32);
      expect(method, 'POST');
      expect(header, token);
    });

    test('the health probe does not wait for an endless body', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..bufferOutput = false
          ..statusCode = 200;
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
          try {
            request.response.add([120]);
          } catch (_) {
            timer.cancel();
          }
        });
      });
      final watch = Stopwatch()..start();
      final answering = await FlaskServerService.isAnswering(
          Uri.parse('http://127.0.0.1:${server.port}'));
      await server.close(force: true);
      expect(answering, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
    });

    test('the health probe counts a silent listener as running', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final held = <Socket>[];
      socket.listen(held.add);
      final watch = Stopwatch()..start();
      final answering = await FlaskServerService.isAnswering(
          Uri.parse('http://127.0.0.1:${socket.port}'));
      for (final connection in held) {
        connection.destroy();
      }
      await socket.close();
      expect(answering, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 6)));
    });

    test('the health probe sees a closed port as nothing running', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      await server.close(force: true);
      expect(await FlaskServerService.isAnswering(base), isFalse);
    });

    test('a refused or malformed login code gives nothing', () async {
      final responses = <void Function(HttpRequest)>[
        (r) => answer(r, 401, jsonEncode({'error': 'Unauthorized'})),
        (r) => answer(r, 200, jsonEncode({'code': 'CD' * 32})),
        (r) => answer(r, 200, jsonEncode({'code': 'cd' * 31})),
        (r) => answer(r, 200, jsonEncode({'code': '../hub'})),
        (r) => answer(r, 200, 'not json'),
      ];
      for (final respond in responses) {
        expect(
          await withServer(respond,
              (base) => FlaskServerService.requestLoginCode(base, token)),
          isNull,
        );
      }
    });
  });
}
