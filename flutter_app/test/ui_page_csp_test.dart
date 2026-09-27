// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:app/web_ui/ui_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  Future<(String, String)> fetch(HttpClient client, UiServer server, List<Cookie> cookies) async {
    final request = await client.getUrl(Uri.parse('${server.origin}/hub/tasks'));
    request.cookies.addAll(cookies);
    final response = await request.close();
    final html = await response.transform(utf8.decoder).join();
    expect(response.statusCode, HttpStatus.ok);
    return (response.headers.value('content-security-policy') ?? '', html);
  }

  test('a served page runs only the scripts that carry the nonce from its own header', () async {
    final server = UiServer.instance;
    await server.start();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final login = await client.getUrl(server.entry('/hub/tasks'));
    login.followRedirects = false;
    final auth = await login.close();
    await auth.drain<void>();
    expect(auth.statusCode, HttpStatus.seeOther);

    final (policy, html) = await fetch(client, server, auth.cookies);
    final scripts = RegExp("script-src ([^;]+)").firstMatch(policy)!.group(1)!;
    final nonce = RegExp("'nonce-([0-9a-f]{32})'").firstMatch(scripts)!.group(1)!;
    expect(scripts, "'self' 'nonce-$nonce'");
    expect(html, isNot(contains('__APP_')));
    final runnable = RegExp(r'<script\b[^>]*>').allMatches(html).map((match) => match[0]!).where((tag) => !tag.contains('type="application/json"')).toList();
    expect(runnable, isNotEmpty);
    for (final tag in runnable) {
      expect(tag, contains('nonce="$nonce"'));
    }

    final (again, _) = await fetch(client, server, auth.cookies);
    expect(again, isNot(contains(nonce)));
  });
}
