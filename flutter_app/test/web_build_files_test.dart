// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final headers = File('../landing-page/public/_headers').readAsStringSync();

  String block(String path) {
    final start = headers.indexOf('$path\n');
    expect(start, isNonNegative, reason: path);
    final end = headers.indexOf('\n\n', start);
    return headers.substring(start, end < 0 ? headers.length : end);
  }

  test('the bundled sqlite3 wasm matches the locked sqlite3 package', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final version = RegExp(r'\n  sqlite3:\n(?:    .*\n)*?    version: "([^"]+)"').firstMatch(lock)!.group(1)!;
    final source = File('lib/services/database_web.dart').readAsStringSync();
    final name = RegExp(r"sqliteWasmFile = '([^']+)'").firstMatch(source)!.group(1)!;
    expect(name, 'sqlite3-$version.wasm');
    final bytes = File('web/$name').readAsBytesSync();
    expect(bytes.sublist(0, 4), [0x00, 0x61, 0x73, 0x6d]);
  });

  test('the page worker may control the hub path and survives the start cleanup', () {
    final source = File('lib/web_ui/web_shell.dart').readAsStringSync();
    final worker = RegExp(r"_worker = '([^']+)'").firstMatch(source)!.group(1)!;
    final scope = RegExp(r"_scope = '([^']+)'").firstMatch(source)!.group(1)!;
    expect(File('web/$worker').existsSync(), isTrue);
    expect(block('/pwa/$worker'), contains('Service-Worker-Allowed: $scope'));
    expect(File('web/$worker').readAsStringSync(), contains('const SCOPE = "$scope"'));
    expect(File('web/index.html').readAsStringSync(), contains(worker.replaceAll('.', r'\.')));
    expect(File('web/flutter_bootstrap.js').readAsStringSync(), isNot(contains('serviceWorker')));
  });

  test('the web app may reach every outside service the shared logic calls', () {
    final policy = RegExp('Content-Security-Policy: (.*)').firstMatch(block('/pwa/*'))!.group(1)!;
    final connect = RegExp('connect-src ([^;]+)').firstMatch(policy)!.group(1)!.split(' ').toSet();
    final hosts = <String>{};
    for (final path in ['lib/web_ui/ui_transit.dart', 'lib/web_ui/ui_weather.dart', 'lib/services/holiday_service.dart']) {
      final source = File(path).readAsStringSync();
      hosts.addAll(RegExp(r"Uri\.https\('([^']+)'").allMatches(source).map((match) => 'https://${match[1]}'));
      hosts.addAll(RegExp(r"_base = '([^']+)'").allMatches(source).map((match) => 'https://${match[1]}'));
      hosts.addAll(RegExp(r"'(https://[a-z0-9.-]+)").allMatches(source).map((match) => match[1]!));
    }
    expect(hosts, isNotEmpty);
    expect(hosts.difference(connect), isEmpty);
    expect(block('/pwa/*'), contains('geolocation=(self)'));
  });
}
