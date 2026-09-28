// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:app/services/web_data_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> fresh() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE ui_store (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, completed INTEGER DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE quick_notes (id TEXT PRIMARY KEY, title TEXT, content TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
    return db;
  }

  test('classic browser data lands in the new database once', () async {
    final db = await fresh();
    addTearDown(db.close);
    final asked = <String>[];
    Future<List<Map<String, Object?>>?> read(String name) async {
      asked.add(name);
      if (name == 'tasks') {
        return [
          {'id': 't1', 'title': 'Mathe S. 38', 'completed': true, 'created_at': '2026-09-01T10:00:00.000', 'legacy_flag': 'weg'},
          {'id': 't2', 'title': 'Referat', 'completed': false},
          {'id': 't3'},
        ];
      }
      if (name == 'quick_notes') {
        return [
          {'id': 'n1', 'title': 'Idee', 'content': {'text': 'Plakat'}},
        ];
      }
      return null;
    }

    final copied = await WebDataImport.run(db: db, read: read);
    expect(copied, 3);
    expect(asked, WebDataImport.tables);
    final tasks = await db.query('tasks', orderBy: 'id');
    expect(tasks.map((row) => row['id']), ['t1', 't2']);
    expect(tasks.first['completed'], 1);
    expect(tasks.first['created_at'], '2026-09-01T10:00:00.000');
    expect(tasks.last['updated_at'], isNotNull);
    final note = (await db.query('quick_notes')).single;
    expect(jsonDecode(note['content'] as String), {'text': 'Plakat'});

    await db.update('tasks', {'title': 'Mathe S. 40'}, where: 'id = ?', whereArgs: ['t1']);
    expect(await WebDataImport.run(db: db, read: read), 0);
    expect((await db.query('tasks', where: 'id = ?', whereArgs: ['t1'])).single['title'], 'Mathe S. 40');
  });

  test('an existing row is never overwritten by the classic copy', () async {
    final db = await fresh();
    addTearDown(db.close);
    await db.insert('tasks', {'id': 't1', 'title': 'Neu', 'created_at': 'a', 'updated_at': 'b'});
    await WebDataImport.run(db: db, read: (name) async => name == 'tasks' ? [{'id': 't1', 'title': 'Alt'}] : null);
    expect((await db.query('tasks')).single['title'], 'Neu');
  });
}
