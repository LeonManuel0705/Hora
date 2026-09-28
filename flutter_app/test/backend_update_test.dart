// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:app/services/flask_server_service.dart';

void main() {
  late Directory root;
  late String bundle;
  late String dest;

  void write(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('backend-update-');
    bundle = p.join(root.path, 'bundle');
    dest = p.join(root.path, 'project');
    write(p.join(bundle, 'app', 'app.py'), 'new app');
    write(p.join(bundle, 'app', 'local_ai.py'), 'new module');
    write(p.join(bundle, 'requirements.txt'), 'flask\n');
    write(p.join(bundle, 'calendar_sync.py'), 'sync');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('a fresh folder gets the bundled backend and remembers the build', () {
    expect(FlaskServerService.bundleIsNewer(dest, 35), isTrue);
    FlaskServerService.installBundledBackend(bundle, dest, 35);
    expect(File(p.join(dest, 'app', 'local_ai.py')).readAsStringSync(), 'new module');
    expect(File(p.join(dest, 'requirements.txt')).readAsStringSync(), 'flask\n');
    expect(FlaskServerService.bundleIsNewer(dest, 35), isFalse);
  });

  test('an older extracted backend is replaced and the data stays', () {
    write(p.join(dest, 'app', 'app.py'), 'old app');
    write(p.join(dest, 'app', 'removed_module.py'), 'gone');
    write(p.join(dest, 'app', '__pycache__', 'app.cpython-39.pyc'), 'cache');
    write(p.join(dest, 'data', 'hub.db'), 'user data');
    write(p.join(dest, '.env'), 'SECRET_KEY=kept');
    write(p.join(dest, '.bundled-build'), '34\n');

    expect(FlaskServerService.bundleIsNewer(dest, 35), isTrue);
    FlaskServerService.installBundledBackend(bundle, dest, 35);

    expect(File(p.join(dest, 'app', 'app.py')).readAsStringSync(), 'new app');
    expect(File(p.join(dest, 'app', 'removed_module.py')).existsSync(), isFalse);
    expect(Directory(p.join(dest, 'app', '__pycache__')).existsSync(), isFalse);
    expect(File(p.join(dest, 'data', 'hub.db')).readAsStringSync(), 'user data');
    expect(File(p.join(dest, '.env')).readAsStringSync(), 'SECRET_KEY=kept');
    expect(Directory(p.join(dest, 'app.previous')).existsSync(), isFalse);
    expect(Directory(p.join(dest, 'app.incoming')).existsSync(), isFalse);
  });

  test('a backend extracted before the build was recorded is refreshed', () {
    write(p.join(dest, 'app', 'app.py'), 'old app');
    expect(FlaskServerService.bundleIsNewer(dest, 35), isTrue);
  });

  test('a git checkout is never replaced', () {
    write(p.join(dest, 'app', 'app.py'), 'developer source');
    Directory(p.join(dest, '.git')).createSync();
    expect(FlaskServerService.bundleIsNewer(dest, 35), isFalse);
  });

  test('a git worktree with a .git file is never replaced either', () {
    write(p.join(dest, 'app', 'app.py'), 'developer source');
    write(p.join(dest, '.git'), 'gitdir: elsewhere');
    expect(FlaskServerService.bundleIsNewer(dest, 35), isFalse);
  });

  test('leftovers of an interrupted update are cleaned up', () {
    write(p.join(dest, 'app', 'app.py'), 'old app');
    write(p.join(dest, 'app.incoming', 'half.py'), 'half');
    write(p.join(dest, 'app.previous', 'older.py'), 'older');
    FlaskServerService.installBundledBackend(bundle, dest, 35);
    expect(File(p.join(dest, 'app', 'app.py')).readAsStringSync(), 'new app');
    expect(Directory(p.join(dest, 'app.incoming')).existsSync(), isFalse);
    expect(Directory(p.join(dest, 'app.previous')).existsSync(), isFalse);
  });
}
