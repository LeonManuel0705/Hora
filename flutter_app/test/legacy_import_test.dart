// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:app/services/legacy_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory documents;
  late String legacy;
  late String target;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('legacy-import-');
    legacy = p.join(documents.path, 'Nexus');
    target = p.join(documents.path, 'Aktuell');
    Directory(p.join(legacy, 'data', 'nested')).createSync(recursive: true);
    File(p.join(legacy, 'data', 'nexus.db')).writeAsStringSync('db');
    File(p.join(legacy, 'data', '.secret_key')).writeAsStringSync('key');
    File(p.join(legacy, 'data', 'nested', 'school_tests.json')).writeAsStringSync('[]');
    File(p.join(legacy, '.env')).writeAsStringSync('SECRET_KEY=alt');
  });

  tearDown(() => documents.deleteSync(recursive: true));

  String? find() => LegacyImport.findLegacyFolder(documents: documents.path, target: target, previousNames: const ['Nexus']);

  test('finds the old folder when the new one has no data yet', () {
    expect(find(), legacy);
  });

  test('leaves an existing new data folder alone', () {
    Directory(p.join(target, 'data')).createSync(recursive: true);
    expect(find(), isNull);
  });

  test('ignores an old folder without data', () {
    Directory(p.join(legacy, 'data')).deleteSync(recursive: true);
    Directory(p.join(legacy, 'data')).createSync();
    expect(find(), isNull);
  });

  test('ignores an old folder that is only a link', () {
    final real = Directory(p.join(documents.path, 'elsewhere'))..createSync();
    Directory(legacy).renameSync(p.join(real.path, 'Nexus'));
    Link(legacy).createSync(p.join(real.path, 'Nexus'));
    expect(find(), isNull);
  });

  test('copies data and the key, keeps the old folder and restricts access', () async {
    Link(p.join(legacy, 'data', 'outside')).createSync(Directory.systemTemp.path);
    expect(await LegacyImport.copyInto(legacy: legacy, target: target), isTrue);
    expect(File(p.join(target, 'data', 'nexus.db')).readAsStringSync(), 'db');
    expect(File(p.join(target, 'data', 'nested', 'school_tests.json')).existsSync(), isTrue);
    expect(File(p.join(target, '.env')).readAsStringSync(), 'SECRET_KEY=alt');
    expect(FileSystemEntity.typeSync(p.join(target, 'data', 'outside'), followLinks: false), FileSystemEntityType.notFound);
    expect(Directory(p.join(target, '.data-import')).existsSync(), isFalse);
    expect(File(p.join(legacy, 'data', 'nexus.db')).existsSync(), isTrue);
    if (!Platform.isWindows) {
      expect(File(p.join(target, 'data', '.secret_key')).statSync().mode & 0x1FF, 0x180);
      expect(Directory(p.join(target, 'data')).statSync().mode & 0x1FF, 0x1C0);
      expect(File(p.join(target, '.env')).statSync().mode & 0x1FF, 0x180);
    }
  });

  test('never overwrites an existing environment file or data folder', () async {
    Directory(target).createSync(recursive: true);
    File(p.join(target, '.env')).writeAsStringSync('SECRET_KEY=neu');
    expect(await LegacyImport.copyInto(legacy: legacy, target: target), isTrue);
    expect(File(p.join(target, '.env')).readAsStringSync(), 'SECRET_KEY=neu');
    expect(await LegacyImport.copyInto(legacy: legacy, target: target), isFalse);
  });
}
