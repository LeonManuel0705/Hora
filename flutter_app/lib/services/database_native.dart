// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io' show File, Platform;

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
// sqflite_ffi re-exports sqflite, so importing both is redundant.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiInitialized = false;

Future<void> initializeDatabaseFactory() async {
  // sqflite ships native implementations only for Android and Darwin
  // (iOS/macOS). On Windows and Linux we must switch to the FFI factory,
  // otherwise every openDatabase() call throws UnsupportedError.
  if ((Platform.isWindows || Platform.isLinux) && !_ffiInitialized) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
  }
}

Future<String> getDatabasePath(String dbName) async {
  // getDatabasesPath() is only implemented by the native Android/Darwin
  // plugins. On Windows/Linux use the app support directory instead.
  if (Platform.isWindows || Platform.isLinux) {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, dbName);
  }
  final dbPath = await getDatabasesPath();
  return join(dbPath, dbName);
}

Future<void> adoptPreviousDatabase(String previousName, String dbName) async {
  final target = File(await getDatabasePath(dbName));
  final previous = File(await getDatabasePath(previousName));
  if (await target.exists() || !await previous.exists()) return;
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final file = File('${previous.path}$suffix');
    if (await file.exists()) await file.rename('${target.path}$suffix');
  }
}
