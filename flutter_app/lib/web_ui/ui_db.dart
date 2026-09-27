// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';

class UiStoreTooLarge implements Exception {
  const UiStoreTooLarge();
}

class UiDb {
  UiDb._();

  static const storeKeys = {
    'app-timetable-edits', 'app-block-times', 'app-ab-swap', 'app-ab-weeks', 'app-subjects', 'app-teachers', 'app-rooms',
    'app-settings', 'app-motion', 'app-theme-choice', 'app-single-keys', 'app-task-filter', 'app-cal-view',
  };
  static const maxValueBytes = 256 * 1024;
  static const iservDoneKey = 'native:iserv-done';
  static const iservHiddenKey = 'native:iserv-hidden';

  static Future<void>? _migration;

  static Future<Database> open() async {
    final db = await DatabaseService().database;
    await (_migration ??= _migrate(db).catchError((Object error) {
      _migration = null;
      throw error;
    }));
    return db;
  }

  static Future<Set<String>> _columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return {for (final row in rows) row['name'] as String};
  }

  static Future<void> _addColumns(Database db, String table, Map<String, String> columns) async {
    final existing = await _columns(db, table);
    if (existing.isEmpty) return;
    for (final entry in columns.entries) {
      if (!existing.contains(entry.key)) {
        await db.execute('ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}');
      }
    }
  }

  static Future<void> _migrate(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS ui_store (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)');
    for (final table in const ['tests', 'exams']) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $table (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          subject_id INTEGER,
          date TEXT,
          notes TEXT,
          grade TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await _addColumns(db, table, {'time': 'TEXT'});
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grades (
        id TEXT PRIMARY KEY,
        subject_id INTEGER NOT NULL,
        semester TEXT NOT NULL,
        type TEXT NOT NULL,
        points INTEGER NOT NULL,
        notes TEXT,
        date TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await _addColumns(db, 'grades', {'grade_system': "TEXT DEFAULT 'points'", 'value': 'REAL'});
    await _addColumns(db, 'subjects', {'course_type': 'TEXT'});
    await _addColumns(db, 'tasks', {
      'subject': 'TEXT',
      'someday': 'INTEGER DEFAULT 0',
      'deadline_ref': 'TEXT',
      'source': 'TEXT',
      'completed_at': 'TEXT',
    });
  }

  static Future<Map<String, Object?>> store(Database db) async {
    final rows = await db.query('ui_store');
    final result = <String, Object?>{};
    for (final row in rows) {
      final key = row['key'] as String;
      if (!storeKeys.contains(key)) continue;
      try {
        result[key] = jsonDecode(row['value'] as String);
      } catch (_) {}
    }
    return result;
  }

  static Future<void> save(Database db, String key, Object? value) async {
    final text = jsonEncode(value);
    if (utf8.encode(text).length > maxValueBytes) throw const UiStoreTooLarge();
    await db.insert(
      'ui_store',
      {'key': key, 'value': text, 'updated_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> remove(Database db, String key) async {
    await db.delete('ui_store', where: 'key = ?', whereArgs: [key]);
  }

  static Future<Set<String>> idSet(Database db, String key) async {
    final rows = await db.query('ui_store', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return {};
    try {
      final value = jsonDecode(rows.first['value'] as String);
      return value is List ? {for (final item in value) '$item'} : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> changeIdSet(Database db, String key, String id, bool present) async {
    final ids = await idSet(db, key);
    final changed = present ? ids.add(id) : ids.remove(id);
    if (changed) await save(db, key, ids.toList()..sort());
  }
}
