// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'web_tab_guard.dart';

const sqliteWasmFile = 'sqlite3-3.3.4.wasm';
const webDatabaseStore = 'app_databases';

bool _factoryReady = false;

Future<void> initializeDatabaseFactory() async {
  if (_factoryReady) return;
  await WebTabGuard.instance.claim();
  databaseFactory = createDatabaseFactoryFfiWeb(
    noWebWorker: true,
    options: SqfliteFfiWebOptions(sqlite3WasmUri: Uri.parse(sqliteWasmFile), indexedDbName: webDatabaseStore),
  );
  _factoryReady = true;
}

Future<String> getDatabasePath(String dbName) async {
  return dbName;
}

Future<void> adoptPreviousDatabase(String previousName, String dbName) async {}
