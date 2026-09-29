// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/web_ui/ui_api.dart';
import 'package:app/web_ui/ui_bridge.dart';
import 'package:app/web_ui/ui_pages.dart';
import 'package:app/web_ui/web_start_script.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory folder;
  final opened = <String>[];
  final loaded = <String>[];

  setUpAll(() async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('ui-bridge-');
    await databaseFactoryFfi.setDatabasesPath(folder.path);
    SharedPreferences.setMockInitialValues({'user_bundesland': 'Brandenburg'});
  });

  tearDownAll(() async {
    try {
      await folder.delete(recursive: true);
    } catch (_) {}
  });

  UiBridge bridge({bool known = true}) => UiBridge(
        api: UiApi(null),
        pages: UiPages(browser: true),
        openNative: (name) async {
          opened.add(name);
          return known;
        },
        startScript: webStartScript,
        assets: (key) async {
          loaded.add(key);
          if (key.endsWith('missing.js')) throw StateError('missing');
          return Uint8List.fromList(utf8.encode('export const key = "$key";'));
        },
      );

  Map<String, Object?> pageData(String html) {
    final match = RegExp(r'<script type="application/json" id="appData">(.*?)</script>', dotAll: true).firstMatch(html)!;
    return (jsonDecode(match.group(1)!) as Map).cast<String, Object?>();
  }

  Future<UiBridgeReply> api(UiBridge bridge, String method, String path, [Object? body]) => bridge.handle(UiBridgeRequest(
        method: method,
        path: path,
        body: body == null ? null : body is String ? body : jsonEncode(body),
        contentType: body == null ? null : 'application/json',
      ));

  test('a page is rendered with the web start script and a framable nonce policy', () async {
    final reply = await bridge().handle(const UiBridgeRequest(method: 'GET', path: '/hub/tasks', navigate: true));
    expect(reply.status, 200);
    final policy = reply.headers['Content-Security-Policy']!;
    final nonce = RegExp("'nonce-([0-9a-f]{32})'").firstMatch(policy)!.group(1)!;
    expect(policy, contains("frame-ancestors 'self'"));
    expect(RegExp('script-src ([^;]+)').firstMatch(policy)!.group(1), "'self' 'nonce-$nonce'");
    final html = reply.body as String;
    expect(html, isNot(contains('__APP_')));
    expect(html, contains('root.dataset.shell = "web"'));
    final runnable = RegExp(r'<script\b[^>]*>').allMatches(html).map((match) => match[0]!).where((tag) => !tag.contains('type="application/json"'));
    for (final tag in runnable) {
      expect(tag, contains('nonce="$nonce"'));
    }
    expect(html.indexOf('root.dataset.shell'), lessThan(html.indexOf('<script type="module"')));
  });

  test('the settings page talks about the browser, not the device', () async {
    final reply = await bridge().handle(const UiBridgeRequest(method: 'GET', path: '/hub/settings', navigate: true));
    final page = pageData(reply.body as String)['page'] as Map;
    expect(page['native'], isFalse);
  });

  test('native screens open in Flutter and keep the current page', () async {
    opened.clear();
    final assistant = await bridge().handle(const UiBridgeRequest(method: 'GET', path: '/hub/assistant', navigate: true, from: '/hub/tasks'));
    expect(assistant.status, 204);
    expect(opened, ['assistant']);
    final classic = await bridge().handle(const UiBridgeRequest(method: 'GET', path: '/hub/klassisch', navigate: true, from: '/hub'));
    expect(classic.status, 204);
    expect(opened, ['assistant']);
    final unknown = await bridge(known: false).handle(const UiBridgeRequest(method: 'GET', path: '/hub/unbekannt', navigate: true, from: '/hub'));
    expect(unknown.status, 404);
    final slash = await bridge().handle(const UiBridgeRequest(method: 'GET', path: '/hub/', navigate: true));
    expect(slash.status, 303);
    expect(slash.headers['Location'], '/hub');
  });

  test('only the hub pages themselves can open a native screen', () async {
    opened.clear();
    for (final from in [null, '/pwa/', '/hubx', '/']) {
      final reply = await bridge().handle(UiBridgeRequest(method: 'GET', path: '/hub/assistant', navigate: true, from: from));
      expect(reply.status, 404, reason: '$from');
    }
    expect(opened, isEmpty);
    final page = await bridge().handle(const UiBridgeRequest(method: 'GET', path: '/hub/tasks', navigate: true));
    expect(page.headers['Referrer-Policy'], 'same-origin');
  });

  test('a task created through the bridge shows up on the next page load', () async {
    final hub = bridge();
    final created = await api(hub, 'POST', '/api/ui/tasks', {'title': 'Vektoren S. 38', 'date': null, 'minutes': 25});
    expect(created.status, 200);
    final task = (jsonDecode(created.body as String) as Map)['task'] as Map;
    expect(task['title'], 'Vektoren S. 38');
    final done = await api(hub, 'PATCH', '/api/ui/tasks/${Uri.encodeComponent('${task['id']}')}', {'done': true});
    expect(done.status, 200);
    final page = await hub.handle(const UiBridgeRequest(method: 'GET', path: '/hub/tasks', navigate: true));
    final tasks = (pageData(page.body as String)['tasks'] as List).cast<Map>();
    final saved = tasks.singleWhere((item) => item['id'] == task['id']);
    expect(saved['done'], isTrue);
  });

  test('stored settings are read back into the next page', () async {
    final hub = bridge();
    final saved = await api(hub, 'PUT', '/api/ui/store/app-task-filter', '"woche"');
    expect(saved.status, 200);
    final page = await hub.handle(const UiBridgeRequest(method: 'GET', path: '/hub/tasks', navigate: true));
    final store = RegExp(r'<script type="application/json" id="appStore">(.*?)</script>', dotAll: true).firstMatch(page.body as String)!;
    expect((jsonDecode(store.group(1)!) as Map)['app-task-filter'], 'woche');
  });

  test('a subject made in the settings keeps its grades, tests and tasks', () async {
    final hub = bridge();
    const own = {'custom': true, 'name': 'Geografie', 'short': 'Geo', 'hue': 'moss', 'type': 'GK', 'teacher': '', 'room': ''};
    final stored = await api(hub, 'PUT', '/api/ui/store/app-subjects', {
      'items': {'geo-own': own, 'geo-gone': own},
      'removed': ['geo-gone'],
    });
    expect(stored.status, 200);
    Future<Map<String, Object?>> school() async =>
        pageData((await hub.handle(const UiBridgeRequest(method: 'GET', path: '/hub/school', navigate: true))).body as String);
    final semester = ((await school())['page'] as Map)['semester'];
    final grade = await api(hub, 'POST', '/api/ui/grades', {'subject': 'geo-own', 'points': 11, 'type': 'test', 'semester': semester, 'title': 'Klimazonen'});
    expect(grade.status, 200);
    final gradeId = ((jsonDecode(grade.body as String) as Map)['grade'] as Map)['id'];
    final when = DateTime.now().add(const Duration(days: 4));
    final day = '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    final test = await api(hub, 'POST', '/api/ui/deadlines', {'kind': 'Test', 'title': 'Stadtgeografie', 'date': day, 'subject': 'geo-own'});
    expect(((jsonDecode(test.body as String) as Map)['deadline'] as Map)['subject'], 'geo-own');
    final task = await api(hub, 'POST', '/api/ui/tasks', {'title': 'Karte beschriften', 'subject': 'geo-own'});
    expect(((jsonDecode(task.body as String) as Map)['task'] as Map)['subject'], 'geo-own');
    final page = await school();
    final grades = ((page['page'] as Map)['grades'] as List).cast<Map>();
    expect(grades.where((item) => item['id'] == gradeId && item['subject'] == 'geo-own'), hasLength(1));
    final deadlines = (page['deadlines'] as List).cast<Map>();
    expect(deadlines.where((item) => item['title'] == 'Stadtgeografie' && item['subject'] == 'geo-own'), hasLength(1));
    expect((await api(hub, 'POST', '/api/ui/grades', {'subject': 'geo-gone', 'points': 9})).status, 400);
    expect((await api(hub, 'POST', '/api/ui/grades', {'subject': 'nirgends', 'points': 9})).status, 400);
  });

  test('broken or oversized requests are refused like on the device server', () async {
    final hub = bridge();
    final invalid = await api(hub, 'POST', '/api/ui/tasks', '{"title": ');
    expect(invalid.status, 400);
    expect(jsonDecode(invalid.body as String), {'success': false, 'error': 'Ungültiges JSON'});
    final large = await api(hub, 'POST', '/api/ui/notes', 'x' * (UiBridge.maxBody + 1));
    expect(large.status, 413);
    final unknown = await api(hub, 'GET', '/api/nirgends');
    expect(unknown.status, 404);
    final other = await hub.handle(const UiBridgeRequest(method: 'GET', path: '/sonstwo'));
    expect(other.status, 404);
  });

  test('static files come from the bundle once and never from outside it', () async {
    loaded.clear();
    final hub = bridge();
    final first = await hub.handle(const UiBridgeRequest(method: 'GET', path: '/static/app/js/main.js', query: '?v=1'));
    expect(first.status, 200);
    expect(first.headers['Content-Type'], startsWith('text/javascript'));
    expect(utf8.decode(first.body as Uint8List), contains('assets/ui/static/app/js/main.js'));
    await hub.handle(const UiBridgeRequest(method: 'GET', path: '/static/app/js/main.js'));
    expect(loaded, ['assets/ui/static/app/js/main.js']);
    for (final path in ['/static/../pubspec.yaml', '/static/', '/static//etc/passwd']) {
      expect((await hub.handle(UiBridgeRequest(method: 'GET', path: path))).status, 404, reason: path);
    }
    expect((await hub.handle(const UiBridgeRequest(method: 'POST', path: '/static/app/js/main.js'))).status, 404);
    expect((await hub.handle(const UiBridgeRequest(method: 'GET', path: '/static/missing.js'))).status, 404);
  });

  test('worker messages become bridge requests', () {
    final request = UiBridgeRequest.fromMessage({
      'type': 'hub-request',
      'navigate': true,
      'method': 'get',
      'path': '/hub/school',
      'query': '?datum=2026-09-28&t=10:15',
      'from': '/hub',
      'body': null,
      'contentType': null,
    });
    expect(request.method, 'GET');
    expect(request.navigate, isTrue);
    expect(request.fromHub, isTrue);
    expect(request.parameters, {'datum': '2026-09-28', 't': '10:15'});
  });

  test('the start script cannot end the script block it is placed in', () {
    expect(webStartScript.toLowerCase(), isNot(contains('</script')));
    final html = UiPages.withStartScript('<html><head>\n<meta charset="utf-8"><title>x</title></head></html>', 'abc', 'go();');
    expect(html, '<html><head>\n<meta charset="utf-8"><script nonce="abc">go();</script><title>x</title></head></html>');
  });
}
