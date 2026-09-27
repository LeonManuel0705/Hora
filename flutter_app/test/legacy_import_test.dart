// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:app/services/legacy_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _key = '0123456789abcdef0123456789abcdef0123456789abcdef';

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
    File(p.join(legacy, '.env')).writeAsStringSync(
      'FLASK_ENV=development\nSECRET_KEY=$_key\nNEXUS_DATA_DIR=/woanders\nNEXUS_PORT=6060\nGOOGLE_CLIENT_ID=abc.apps # Kommentar\n',
    );
  });

  tearDown(() {
    if (!Platform.isWindows) Process.runSync('chmod', ['-R', 'u+rwX', documents.path]);
    documents.deleteSync(recursive: true);
  });

  String? find() => LegacyImport.findLegacyFolder(documents: documents.path, target: target, previousNames: const ['Nexus']);
  Future<LegacyImportOutcome> copy() => LegacyImport.copyInto(legacy: legacy, target: target);
  List<String> leftovers() => Directory(target).existsSync()
      ? Directory(target).listSync(followLinks: false).map((entity) => p.basename(entity.path)).where((name) => name.startsWith('.data-import-')).toList()
      : const [];
  String targetEnv() => File(p.join(target, '.env')).readAsStringSync();
  Map<String, String?> targetSettings() => LegacyImport.readEnv(targetEnv()).map((key, entry) => MapEntry(key, entry.value));

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

  test('copies data, keeps the old folder and restricts access', () async {
    Link(p.join(legacy, 'data', 'outside')).createSync(Directory.systemTemp.path);
    expect(await copy(), LegacyImportOutcome.imported);
    expect(File(p.join(target, 'data', 'nexus.db')).readAsStringSync(), 'db');
    expect(File(p.join(target, 'data', 'nested', 'school_tests.json')).existsSync(), isTrue);
    expect(FileSystemEntity.typeSync(p.join(target, 'data', 'outside'), followLinks: false), FileSystemEntityType.notFound);
    expect(leftovers(), isEmpty);
    expect(File(p.join(legacy, 'data', 'nexus.db')).existsSync(), isTrue);
    if (!Platform.isWindows) {
      expect(File(p.join(target, 'data', '.secret_key')).statSync().mode & 0x1FF, 0x180);
      expect(Directory(p.join(target, 'data')).statSync().mode & 0x1FF, 0x1C0);
      expect(File(p.join(target, '.env')).statSync().mode & 0x1FF, 0x180);
    }
  });

  test('takes only the key and the Google settings, line by line as they were', () async {
    expect(await copy(), LegacyImportOutcome.imported);
    expect(targetEnv(), 'SECRET_KEY=$_key\nGOOGLE_CLIENT_ID=abc.apps # Kommentar\n');
    expect(targetSettings(), {'SECRET_KEY': _key, 'GOOGLE_CLIENT_ID': 'abc.apps'});
  });

  for (final line in ['export SECRET_KEY="$_key" # Kommentar', "SECRET_KEY='$_key'", r'SECRET_KEY=abc\nzz0123456789abcdef0123456789abcdef']) {
    test('keeps an unusual key line exactly: $line', () async {
      File(p.join(legacy, '.env')).writeAsStringSync('$line\n');
      expect(await copy(), LegacyImportOutcome.imported);
      expect(targetEnv(), '$line\n');
    });
  }

  test('reads quoted values the way python-dotenv does', () {
    final entries = LegacyImport.readEnv('A="x" # Kommentar\nB=\'y\'\nC="unterminiert\nD=frei # Notiz\nE="a\\nb"\nF=a\\nb\n');
    expect(entries['A']!.value, 'x');
    expect(entries['B']!.value, 'y');
    expect(entries['C']!.value, isNull);
    expect(entries['D']!.value, 'frei');
    expect(entries['E']!.value, 'a\nb');
    expect(entries['F']!.value, r'a\nb');
  });

  test('leaves an unterminated key behind', () async {
    File(p.join(legacy, '.env')).writeAsStringSync('SECRET_KEY="$_key\n');
    expect(await copy(), LegacyImportOutcome.imported);
    expect(File(p.join(target, '.env')).existsSync(), isFalse);
  });

  test('copes with an old environment file that is not UTF-8', () async {
    File(p.join(legacy, '.env')).writeAsBytesSync([
      ...'# Schl'.codeUnits, 0xFC, ...'ssel\nSECRET_KEY=$_key\nGOOGLE_PROJECT_ID=gr'.codeUnits, 0xFC, ...'n\n'.codeUnits,
    ]);
    expect(await copy(), LegacyImportOutcome.imported);
    expect(targetEnv(), 'SECRET_KEY=$_key\n');
  });

  test('treats empty and template values in the new file as missing', () async {
    Directory(target).createSync(recursive: true);
    File(p.join(target, '.env')).writeAsStringSync('SECRET_KEY=\nGOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com\n');
    expect(await copy(), LegacyImportOutcome.imported);
    expect(targetSettings(), {'SECRET_KEY': _key, 'GOOGLE_CLIENT_ID': 'abc.apps'});
  });

  test('sees no conflict when the new file already has the same key in another spelling', () async {
    Directory(target).createSync(recursive: true);
    File(p.join(target, '.env')).writeAsStringSync('SECRET_KEY="$_key" # gleich\n');
    expect(await copy(), LegacyImportOutcome.imported);
    expect(targetEnv(), 'SECRET_KEY="$_key" # gleich\nGOOGLE_CLIENT_ID=abc.apps # Kommentar\n');
  });

  test('puts the environment file back when the final move fails', () async {
    Directory(target).createSync(recursive: true);
    File(p.join(target, '.env')).writeAsStringSync('FLASK_ENV=production\n');
    LegacyImport.beforeMove = (target) => File(p.join(target, 'data')).writeAsStringSync('im Weg');
    addTearDown(() => LegacyImport.beforeMove = null);
    expect(await copy(), LegacyImportOutcome.failed);
    expect(targetEnv(), 'FLASK_ENV=production\n');
    expect(leftovers(), isEmpty);
  });

  test('removes a created environment file when the final move fails', () async {
    LegacyImport.beforeMove = (target) => File(p.join(target, 'data')).writeAsStringSync('im Weg');
    addTearDown(() => LegacyImport.beforeMove = null);
    expect(await copy(), LegacyImportOutcome.failed);
    expect(File(p.join(target, '.env')).existsSync(), isFalse);
  });

  test('only clears leftovers it made itself', () async {
    Directory(p.join(target, '.data-import-notizen')).createSync(recursive: true);
    Directory(p.join(target, '.data-import-AbC123')).createSync(recursive: true);
    expect(await copy(), LegacyImportOutcome.imported);
    expect(Directory(p.join(target, '.data-import-notizen')).existsSync(), isTrue);
    expect(Directory(p.join(target, '.data-import-AbC123')).existsSync(), Platform.isWindows);
  });

  for (final rejected in ['your-secret-key-here', 'nexus-hub-secret-key-change-me', 'CHANGEME']) {
    test('leaves a key behind that the backend would reject: $rejected', () async {
      File(p.join(legacy, '.env')).writeAsStringSync('SECRET_KEY="$rejected"\n');
      expect(await copy(), LegacyImportOutcome.imported);
      expect(File(p.join(target, '.env')).existsSync(), isFalse);
      expect(File(p.join(target, 'data', 'nexus.db')).existsSync(), isTrue);
    });
  }

  test('adds the old key to an environment file that has none', () async {
    Directory(target).createSync(recursive: true);
    File(p.join(target, '.env')).writeAsStringSync('FLASK_ENV=production');
    expect(await copy(), LegacyImportOutcome.imported);
    expect(targetEnv(), 'FLASK_ENV=production\nSECRET_KEY=$_key\nGOOGLE_CLIENT_ID=abc.apps # Kommentar\n');
  });

  test('refuses to mix data with a different key and changes nothing', () async {
    Directory(target).createSync(recursive: true);
    File(p.join(target, '.env')).writeAsStringSync('SECRET_KEY=${'f' * 64}\n');
    expect(await copy(), LegacyImportOutcome.keyConflict);
    expect(Directory(p.join(target, 'data')).existsSync(), isFalse);
    expect(File(p.join(target, '.env')).readAsStringSync(), 'SECRET_KEY=${'f' * 64}\n');
  });

  test('skips when data appeared in the meantime', () async {
    Directory(p.join(target, 'data')).createSync(recursive: true);
    expect(await copy(), LegacyImportOutcome.skipped);
    expect(File(p.join(target, '.env')).existsSync(), isFalse);
  });

  test('reports a failed copy and leaves nothing half done', () async {
    if (Platform.isWindows) return;
    Directory(target).createSync(recursive: true);
    File(p.join(target, '.env')).writeAsStringSync('FLASK_ENV=production\n');
    final locked = File(p.join(legacy, 'data', 'nested', 'locked.json'))..writeAsStringSync('{}');
    Process.runSync('chmod', ['000', locked.path]);
    expect(await copy(), LegacyImportOutcome.failed);
    expect(Directory(p.join(target, 'data')).existsSync(), isFalse);
    expect(leftovers(), isEmpty);
    expect(targetEnv(), 'FLASK_ENV=production\n');
  });

  test('never follows a staging link that someone left behind', () async {
    Directory(target).createSync(recursive: true);
    final guard = Directory(p.join(documents.path, 'guard'))..createSync();
    File(p.join(guard.path, 'keep.txt')).writeAsStringSync('keep');
    Link(p.join(target, '.data-import-left')).createSync(guard.path);
    expect(await copy(), LegacyImportOutcome.imported);
    expect(File(p.join(guard.path, 'keep.txt')).readAsStringSync(), 'keep');
    expect(guard.listSync().length, 1);
    expect(FileSystemEntity.typeSync(p.join(target, '.data-import-left'), followLinks: false), FileSystemEntityType.link);
  });
}
