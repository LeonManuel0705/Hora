// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:app/web_ui/ui_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the page policy runs only scripts that carry the nonce', () {
    final scripts = RegExp("script-src ([^;]+)").firstMatch(UiServer.policy('abc'))!.group(1);
    expect(scripts, "'self' 'nonce-abc'");
  });

  test('every runnable script in the bundled pages carries the nonce placeholder', () {
    final pages = Directory('assets/ui/pages').listSync().whereType<File>().where((file) => file.path.endsWith('.html')).toList();
    expect(pages, isNotEmpty);
    for (final page in pages) {
      final tags = RegExp(r'<script\b[^>]*>').allMatches(page.readAsStringSync()).map((match) => match[0]!);
      final runnable = tags.where((tag) => !tag.contains('type="application/json"')).toList();
      expect(runnable, isNotEmpty, reason: page.path);
      for (final tag in runnable) {
        expect(tag, contains('nonce="__APP_NONCE__"'), reason: page.path);
      }
    }
  });
}
