// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

import '../brand.dart';
import '../build_info.dart';
import 'ui_data.dart';
import 'ui_db.dart';

const uiPageRoutes = {
  '/hub': 'home',
  '/hub/tasks': 'tasks',
  '/hub/calendar': 'calendar',
  '/hub/school': 'school',
  '/hub/vbb': 'vbb',
  '/hub/email': 'email',
  '/hub/settings': 'settings',
};

const uiContentTypes = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'svg': 'image/svg+xml',
  'woff2': 'font/woff2',
  'png': 'image/png',
  'json': 'application/json; charset=utf-8',
  'txt': 'text/plain; charset=utf-8',
};

String uiContentType(String path) {
  final extension = path.contains('.') ? path.substring(path.lastIndexOf('.') + 1) : '';
  return uiContentTypes[extension] ?? 'application/octet-stream';
}

class UiPages {
  UiPages({this.browser = false});

  final bool browser;
  final Map<String, String> _templates = {};

  static String policy(String nonce, {bool framed = false}) =>
      "default-src 'self'; script-src 'self' 'nonce-$nonce'; style-src 'self' 'unsafe-inline'; "
      "img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors ${framed ? "'self'" : "'none'"}; "
      "base-uri 'none'; form-action 'self'";

  static String nonce() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String scriptJson(Object? value) => jsonEncode(value)
      .replaceAll('<', r'\u003c')
      .replaceAll('>', r'\u003e')
      .replaceAll('&', r'\u0026')
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');

  static String _escape(String value) => const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

  static String themeOf(Map<String, Object?> store, SharedPreferences prefs) {
    final choice = store['app-theme-choice'];
    if (choice == 'light' || choice == 'dark') return choice as String;
    if (store.containsKey('app-theme-choice')) return 'auto';
    if ((prefs.getString('theme_switch_mode') ?? 'system') == 'system') return 'auto';
    final mode = prefs.getString('theme_mode');
    return mode == 'dark' || mode == 'light' ? mode! : 'auto';
  }

  static String withStartScript(String html, String nonce, String script) {
    final tag = '<script nonce="$nonce">$script</script>';
    const charset = '<meta charset="utf-8">';
    final at = html.indexOf(charset);
    if (at >= 0) return html.replaceRange(at + charset.length, at + charset.length, tag);
    final head = html.indexOf('<head>');
    return head < 0 ? '$tag$html' : html.replaceRange(head + 6, head + 6, tag);
  }

  Future<String> _template(String page) async =>
      _templates[page] ??= await rootBundle.loadString('assets/ui/pages/$page.html', cache: false);

  Future<String> render(String page, {required String nonce, String? day, String? startScript}) async {
    final db = await UiDb.open();
    final prefs = await SharedPreferences.getInstance();
    final store = await UiDb.store(db);
    final pinned = isoDay(day);
    final current = DateTime.now();
    final now = pinned == null
        ? current
        : dayOf(pinned).add(Duration(hours: current.hour, minutes: current.minute, seconds: current.second));
    final data = await UiData(db, prefs, now, browser: browser).build(page, store);
    final theme = themeOf(store, prefs);
    final tasks = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM tasks')) ?? 0;
    final tour = prefs.getString('tour_state') == null && prefs.containsKey('user_bundesland') && tasks == 0;
    final values = {
      '__APP_NONCE__': nonce,
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
    return startScript == null ? html : withStartScript(html, nonce, startScript);
  }
}
