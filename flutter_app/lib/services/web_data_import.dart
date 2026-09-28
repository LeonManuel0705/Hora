// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:sqflite/sqflite.dart';

import '../web_ui/ui_db.dart';

typedef ClassicBoxReader = Future<List<Map<String, Object?>>?> Function(String name);

class WebDataImport {
  WebDataImport._();

  static const marker = 'native:classic-import';
  static const tables = [
    'subjects', 'lessons', 'timetable_periods', 'tasks', 'events', 'homework', 'quick_notes', 'bookmarks',
    'chat_messages', 'daily_reviews', 'weekly_reviews', 'pomodoro_sessions', 'training_sessions', 'training_goals',
    'health_logs', 'vbb_known_locations', 'vbb_favorite_routes', 'vbb_tickets',
  ];

  static Future<int> run({Database? db, ClassicBoxReader? read}) async {
    final database = db ?? await UiDb.open();
    final done = await database.query('ui_store', columns: ['key'], where: 'key = ?', whereArgs: [marker], limit: 1);
    if (done.isNotEmpty) return 0;
    final reader = read ?? _readBox;
    var copied = 0;
    for (final table in tables) {
      final rows = await reader(table);
      if (rows == null || rows.isEmpty) continue;
      final columns = {for (final row in await database.rawQuery('PRAGMA table_info($table)')) row['name'] as String};
      if (columns.isEmpty) continue;
      final stamp = DateTime.now().toIso8601String();
      final batch = database.batch();
      for (final row in rows) {
        final values = <String, Object?>{
          for (final entry in row.entries)
            if (columns.contains(entry.key)) entry.key: _plain(entry.value),
        };
        if (values.isEmpty) continue;
        for (final column in const ['created_at', 'updated_at']) {
          if (columns.contains(column)) values[column] ??= stamp;
        }
        batch.insert(table, values, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final results = await batch.commit(continueOnError: true);
      copied += results.whereType<int>().where((id) => id > 0).length;
    }
    await UiDb.save(database, marker, copied);
    return copied;
  }

  static Object? _plain(Object? value) {
    if (value == null || value is num || value is String) return value;
    if (value is bool) return value ? 1 : 0;
    if (value is DateTime) return value.toIso8601String();
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  static Future<List<Map<String, Object?>>?> _readBox(String name) async {
    if (!await Hive.boxExists(name)) return null;
    final box = await Hive.openBox<dynamic>(name);
    try {
      return [
        for (final value in box.values)
          if (value is Map) {for (final entry in value.entries) '${entry.key}': entry.value},
      ];
    } finally {
      await box.close();
    }
  }
}
