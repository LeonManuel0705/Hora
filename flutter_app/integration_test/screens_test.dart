// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app/main.dart' as app;

const _screenCount = 15;

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> _tapIfFound(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) return false;
  await tester.tap(finder.first, warnIfMissed: false);
  await _pumpFor(tester, const Duration(milliseconds: 500));
  return true;
}

void _collect(WidgetTester tester, List<String> errors, String stage) {
  final exception = tester.takeException();
  if (exception != null) {
    errors.add('[$stage] $exception');
    debugPrint('=== ERROR during $stage ===\n$exception');
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every screen renders without errors', (tester) async {
    final errors = <String>[];

    app.main();
    await _pumpFor(tester, const Duration(seconds: 10));
    _collect(tester, errors, 'startup');

    if (find.text('Willkommen!').evaluate().isNotEmpty) {
      await _tapIfFound(tester, find.text('Brandenburg'));
      await _tapIfFound(tester, find.text('Weiter'));
      await _tapIfFound(tester, find.textContaining('Abschluss ${DateTime.now().year + 1}'));
      await _tapIfFound(tester, find.text('Weiter'));
      await _tapIfFound(tester, find.text('Mit Beispieldaten starten'));
      await _tapIfFound(tester, find.text("Los geht's"));
      await _pumpFor(tester, const Duration(seconds: 4));
      _collect(tester, errors, 'welcome dialog');
    }

    final platform = Platform.operatingSystem;
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await _pumpFor(tester, const Duration(milliseconds: 500));
    }

    for (var i = 0; i < _screenCount; i++) {
      app.MainScreen.navigateTo(i);
      await _pumpFor(tester, const Duration(milliseconds: 1500));
      await binding.takeScreenshot('$platform/screen_${i.toString().padLeft(2, '0')}');
      final before = errors.length;
      _collect(tester, errors, 'screen $i');
      debugPrint('SCREEN $i: ${errors.length == before ? 'ok' : 'error'}');
    }

    app.MainScreen.navigateTo(0);
    await _pumpFor(tester, const Duration(milliseconds: 800));
    await _tapIfFound(tester, find.text('Mehr'));
    await _pumpFor(tester, const Duration(milliseconds: 800));
    await binding.takeScreenshot('$platform/menu_panel');
    _collect(tester, errors, 'menu panel');

    for (final e in errors) {
      debugPrint('=== CAPTURED ERROR ===\n$e');
    }
    expect(errors, isEmpty, reason: '${errors.length} errors captured');
  });
}
