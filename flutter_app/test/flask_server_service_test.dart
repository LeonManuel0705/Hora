// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/flask_server_service.dart';

void main() {
  final flask = FlaskServerService();

  test('the hub itself counts as the hub', () {
    expect(flask.isHubUrl(flask.hubUrl), isTrue);
    expect(flask.isHubUrl('http://localhost:5050/hub/klassisch/school'), isTrue);
    expect(flask.isHubUrl('http://127.0.0.1:5050/hub/pomodoro?x=1#top'), isTrue);
    expect(flask.isHubUrl('http://LOCALHOST:5050/hub'), isTrue);
  });

  test('look-alike addresses do not count as the hub', () {
    for (final url in [
      'http://localhost:5050@attacker.example/',
      'http://localhost:5050.attacker.example/',
      'http://localhost:50501/hub',
      'http://localhost/hub',
      'https://localhost:5050/hub',
      'http://user@localhost:5050/hub',
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
}
