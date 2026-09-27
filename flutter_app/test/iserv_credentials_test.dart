// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:app/services/encryption_service.dart';
import 'package:app/services/iserv_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _url = 'https://iserv.schule.de';

void main() {
  final encryption = EncryptionService();
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE iserv_credentials (id INTEGER PRIMARY KEY, username TEXT NOT NULL, '
      'iserv_url TEXT NOT NULL, credential_key TEXT NOT NULL, created_at TEXT NOT NULL)',
    );
  });

  tearDown(() => db.close());

  Future<String> remember(String username, String password) async {
    final key = await encryption.storeIServCredentials(username: username, password: password, iservUrl: _url);
    await db.insert('iserv_credentials', {
      'username': username,
      'iserv_url': _url,
      'credential_key': key,
      'created_at': DateTime.now().toIso8601String(),
    });
    return key;
  }

  Future<Map<String, String>> stored() => const FlutterSecureStorage().readAll();

  test('disconnecting forgets the stored password', () async {
    await remember('anna.schmidt', 'geheim');
    await forgetIServCredentials(db, encryption);
    expect(await db.query('iserv_credentials'), isEmpty);
    expect(await stored(), isEmpty);
  });

  test('a new login keeps its own password and drops the previous one', () async {
    await remember('anna.schmidt', 'geheim');
    final key = await encryption.storeIServCredentials(username: 'ben.meyer', password: 'neu', iservUrl: _url);
    await forgetIServCredentials(db, encryption, keep: key);
    expect((await stored()).keys, [key]);
  });

  test('passwords orphaned by earlier logouts are swept, other secrets stay', () async {
    await encryption.storeIServCredentials(username: 'alter.nutzer', password: 'alt', iservUrl: _url);
    await encryption.storeCredential('email_abc', 'mail-passwort');
    final key = await remember('anna.schmidt', 'geheim');
    await forgetIServCredentials(db, encryption, keep: key);
    expect((await stored()).keys.toSet(), {key, 'email_abc'});
    expect(await db.query('iserv_credentials'), isEmpty);
  });

  test('clearing an account removes its hashed keys', () async {
    await encryption.storeIServCredentials(username: 'anna.schmidt', password: 'geheim', iservUrl: _url);
    await encryption.clearAccountCredentials('anna.schmidt');
    expect(await stored(), isEmpty);
  });
}
