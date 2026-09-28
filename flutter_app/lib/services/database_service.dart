// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/task.dart';
import '../brand.dart';

import 'database_web.dart' if (dart.library.io) 'database_native.dart' as db_platform;
import '../models/event.dart';
import '../models/lesson.dart';
import '../models/bookmark.dart';
import '../models/quick_note.dart';
import '../models/chat_message.dart';
import '../models/email.dart';
import '../models/vbb.dart';
import 'calendar_sync_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;
  static Future<Database>? _opening;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    final ready = _database;
    if (ready != null) return ready;
    final opening = _opening ??= _initDatabase();
    try {
      return _database = await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    await db_platform.initializeDatabaseFactory();
    for (final name in Brand.previousNames) {
      await db_platform.adoptPreviousDatabase('${name.toLowerCase()}.db', 'app.db');
    }

    final path = await db_platform.getDatabasePath('app.db');

    return await openDatabase(
      path,
      version: 12,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createNewFeatureTables(db);
    }
    if (oldVersion < 3) {

      await db.execute("ALTER TABLE tasks ADD COLUMN category TEXT DEFAULT 'general'");

      await db.execute("ALTER TABLE events ADD COLUMN category TEXT DEFAULT 'personal'");
    }

    if (oldVersion < 5) {
      await db.execute("ALTER TABLE lessons ADD COLUMN lesson_type TEXT");
    }

    if (oldVersion < 6) {

      await db.execute("ALTER TABLE lessons ADD COLUMN week_type TEXT DEFAULT 'both'");

      await db.execute('''
        CREATE TABLE IF NOT EXISTS timetable_periods (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          period_number INTEGER NOT NULL UNIQUE,
          name TEXT,
          start_time TEXT NOT NULL,
          end_time TEXT NOT NULL,
          has_split INTEGER DEFAULT 0,
          split_break_minutes INTEGER,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_reviews (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          achieved TEXT NOT NULL DEFAULT '',
          good TEXT NOT NULL DEFAULT '',
          better TEXT NOT NULL DEFAULT '',
          focus TEXT NOT NULL DEFAULT '',
          grateful TEXT NOT NULL DEFAULT '',
          energy INTEGER NOT NULL DEFAULT 5
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS weekly_reviews (
          id TEXT PRIMARY KEY,
          week_start TEXT NOT NULL,
          week_number INTEGER NOT NULL,
          highlights TEXT NOT NULL DEFAULT '',
          progress TEXT NOT NULL DEFAULT '',
          challenges TEXT NOT NULL DEFAULT '',
          learnings TEXT NOT NULL DEFAULT '',
          goals TEXT NOT NULL DEFAULT ''
        )
      ''');
    }

    if (oldVersion < 8) {
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN estimated_minutes INTEGER");
      } catch (_) {

      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS pomodoro_sessions (
          id TEXT PRIMARY KEY,
          task_id TEXT,
          started_at TEXT NOT NULL,
          duration_minutes INTEGER NOT NULL,
          completed INTEGER DEFAULT 1
        )
      ''');
    }

    if (oldVersion < 10) {
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN repeat_type TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN repeat_weekdays TEXT");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE tasks ADD COLUMN repeat_end_date TEXT");
      } catch (_) {}
    }

    if (oldVersion < 11) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS vbb_tickets (
          id TEXT PRIMARY KEY,
          ticket_type TEXT NOT NULL DEFAULT 'custom',
          ticket_name TEXT NOT NULL,
          zone_coverage TEXT NOT NULL DEFAULT 'all',
          valid_from TEXT,
          valid_until TEXT,
          auto_renews INTEGER DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 12) {
      for (final table in const ['drawings', 'projects', 'knowledge_entries']) {
        await _dropTableIfEmpty(db, table);
      }
    }

    await _createTrainingTables(db);
  }

  Future<void> _dropTableIfEmpty(Database db, String table) async {
    final existing = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', table],
    );
    if (existing.isEmpty) return;
    final rows = await db.rawQuery('SELECT 1 FROM $table LIMIT 1');
    if (rows.isEmpty) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  Future<void> _onCreate(Database db, int version) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day INTEGER NOT NULL,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL,
        muscle_groups TEXT,
        notes TEXT,
        is_holiday INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_sessions (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        duration INTEGER,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS health_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        sleep REAL,
        energy INTEGER,
        stress INTEGER,
        recovery INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_goals (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        target_date TEXT,
        completed INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        due_date TEXT,
        completed INTEGER DEFAULT 0,
        priority TEXT DEFAULT 'medium',
        category TEXT DEFAULT 'general',
        estimated_minutes INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        repeat_type TEXT,
        repeat_weekdays TEXT,
        repeat_end_date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pomodoro_sessions (
        id TEXT PRIMARY KEY,
        task_id TEXT,
        started_at TEXT NOT NULL,
        duration_minutes INTEGER NOT NULL,
        completed INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        location TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        all_day INTEGER DEFAULT 0,
        color TEXT,
        category TEXT DEFAULT 'personal',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE lessons (
        id TEXT PRIMARY KEY,
        subject TEXT NOT NULL,
        teacher TEXT,
        room TEXT,
        day_of_week INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        lesson_number INTEGER NOT NULL,
        color TEXT,
        lesson_type TEXT,
        week_type TEXT DEFAULT 'both',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS timetable_periods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        period_number INTEGER NOT NULL UNIQUE,
        name TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        has_split INTEGER DEFAULT 0,
        split_break_minutes INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_reviews (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        achieved TEXT NOT NULL DEFAULT '',
        good TEXT NOT NULL DEFAULT '',
        better TEXT NOT NULL DEFAULT '',
        focus TEXT NOT NULL DEFAULT '',
        grateful TEXT NOT NULL DEFAULT '',
        energy INTEGER NOT NULL DEFAULT 5
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS weekly_reviews (
        id TEXT PRIMARY KEY,
        week_start TEXT NOT NULL,
        week_number INTEGER NOT NULL,
        highlights TEXT NOT NULL DEFAULT '',
        progress TEXT NOT NULL DEFAULT '',
        challenges TEXT NOT NULL DEFAULT '',
        learnings TEXT NOT NULL DEFAULT '',
        goals TEXT NOT NULL DEFAULT ''
      )
    ''');

    await _createNewFeatureTables(db);
  }

  Future<void> _createNewFeatureTables(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        category TEXT DEFAULT 'Other',
        favicon TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quick_notes (
        id TEXT PRIMARY KEY,
        type TEXT DEFAULT 'note',
        title TEXT,
        content TEXT NOT NULL,
        word_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        short_name TEXT,
        color TEXT,
        teacher TEXT,
        room TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS homework (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subject_id INTEGER,
        notes TEXT,
        due_date TEXT,
        completed INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        role TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        metadata TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iserv_credentials (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        iserv_url TEXT NOT NULL,
        credential_key TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iserv_notifications (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        message TEXT,
        type TEXT,
        read INTEGER DEFAULT 0,
        timestamp TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iserv_exercises (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        course TEXT,
        teacher TEXT,
        due_date TEXT,
        status TEXT DEFAULT 'open',
        attachments_json TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iserv_events (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        start_time TEXT,
        end_time TEXT,
        location TEXT,
        description TEXT,
        calendar TEXT,
        all_day INTEGER DEFAULT 0,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vertretungsplan_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data_base64 TEXT NOT NULL,
        filename TEXT,
        content_type TEXT,
        page INTEGER DEFAULT 1,
        fetched_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS email_accounts (
        id TEXT PRIMARY KEY,
        email TEXT UNIQUE NOT NULL,
        provider TEXT NOT NULL,
        display_name TEXT,
        credential_key TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        added_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_emails (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        folder TEXT DEFAULT 'INBOX',
        from_email TEXT,
        from_name TEXT,
        to_email TEXT,
        subject TEXT,
        preview TEXT,
        body TEXT,
        date TEXT,
        is_read INTEGER DEFAULT 0,
        is_starred INTEGER DEFAULT 0,
        has_attachments INTEGER DEFAULT 0,
        cached_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES email_accounts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS email_folders (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        name TEXT NOT NULL,
        path TEXT,
        unread_count INTEGER DEFAULT 0,
        total_count INTEGER DEFAULT 0,
        FOREIGN KEY (account_id) REFERENCES email_accounts(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vbb_known_locations (
        key TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        vbb_id TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        type TEXT,
        products_json TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vbb_location_cache (
        query_key TEXT PRIMARY KEY,
        results_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vbb_route_cache (
        cache_key TEXT PRIMARY KEY,
        from_json TEXT NOT NULL,
        to_json TEXT NOT NULL,
        departure_time TEXT,
        routes_json TEXT NOT NULL,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vbb_favorite_routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        from_location_json TEXT NOT NULL,
        to_location_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vbb_tickets (
        id TEXT PRIMARY KEY,
        ticket_type TEXT NOT NULL DEFAULT 'custom',
        ticket_name TEXT NOT NULL,
        zone_coverage TEXT NOT NULL DEFAULT 'all',
        valid_from TEXT,
        valid_until TEXT,
        auto_renews INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS google_accounts (
        email TEXT PRIMARY KEY,
        token_key TEXT,
        refresh_token_key TEXT,
        added_at TEXT NOT NULL,
        last_sync_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS google_calendars (
        id TEXT PRIMARY KEY,
        account_email TEXT NOT NULL,
        name TEXT NOT NULL,
        color TEXT,
        is_primary INTEGER DEFAULT 0,
        is_visible INTEGER DEFAULT 1,
        access_role TEXT,
        FOREIGN KEY (account_email) REFERENCES google_accounts(email) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS google_events (
        id TEXT PRIMARY KEY,
        calendar_id TEXT NOT NULL,
        account_email TEXT NOT NULL,
        title TEXT NOT NULL,
        start_date TEXT,
        start_time TEXT,
        end_date TEXT,
        end_time TEXT,
        all_day INTEGER DEFAULT 0,
        location TEXT,
        description TEXT,
        color TEXT,
        sync_status TEXT DEFAULT 'synced',
        local_modified_at TEXT,
        server_modified_at TEXT,
        etag TEXT,
        FOREIGN KEY (calendar_id) REFERENCES google_calendars(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_status (
        table_name TEXT PRIMARY KEY,
        last_sync_at TEXT,
        last_full_sync_at TEXT,
        sync_token TEXT,
        next_page_token TEXT,
        error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        payload_json TEXT,
        created_at TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        status TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_cached_emails_account ON cached_emails(account_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cached_emails_date ON cached_emails(date DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_google_events_calendar ON google_events(calendar_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_operations_status ON pending_operations(status)');
  }

  Future<List<Task>> getTasks() async {
    final db = await database;
    final maps = await db.query('tasks', orderBy: 'due_date ASC, created_at DESC');
    return maps.map((map) => Task.fromMap(map)).toList();
  }

  Future<List<Task>> getTodayTasks() async {
    final db = await database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final maps = await db.query(
      'tasks',
      where: '(due_date >= ? AND due_date < ?) OR (due_date IS NULL AND completed = 0)',
      whereArgs: [today.toIso8601String(), tomorrow.toIso8601String()],
      orderBy: 'due_date ASC, created_at DESC',
    );
    return maps.map((map) => Task.fromMap(map)).toList();
  }

  Future<List<Task>> getOpenTasks() async {
    final db = await database;
    final maps = await db.query(
      'tasks',
      where: 'completed = 0',
      orderBy: 'due_date ASC, created_at DESC',
    );
    return maps.map((map) => Task.fromMap(map)).toList();
  }

  Future<void> insertTask(Task task) async {
    final db = await database;
    await db.insert('tasks', task.toMap());
  }

  Future<void> updateTask(Task task) async {
    final db = await database;
    await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleTaskComplete(String id, bool completed) async {
    final db = await database;
    await db.update(
      'tasks',
      {'completed': completed ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Event>> getEvents() async {
    final db = await database;
    final maps = await db.query('events', orderBy: 'start_time ASC');
    return maps.map((map) => Event.fromMap(map)).toList();
  }

  Future<List<Event>> getTodayEvents() async {
    final db = await database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final maps = await db.query(
      'events',
      where: 'start_time >= ? AND start_time < ?',
      whereArgs: [today.toIso8601String(), tomorrow.toIso8601String()],
      orderBy: 'start_time ASC',
    );
    return maps.map((map) => Event.fromMap(map)).toList();
  }

  Future<List<Event>> getUpcomingEvents({int days = 7}) async {
    final db = await database;
    final now = DateTime.now();
    final endDate = now.add(Duration(days: days));

    final maps = await db.query(
      'events',
      where: 'start_time >= ? AND start_time < ?',
      whereArgs: [now.toIso8601String(), endDate.toIso8601String()],
      orderBy: 'start_time ASC',
    );
    return maps.map((map) => Event.fromMap(map)).toList();
  }

  Future<void> insertEvent(Event event) async {
    final db = await database;
    await db.insert('events', event.toMap());
  }

  Future<void> updateEvent(Event event) async {
    final db = await database;
    await db.update(
      'events',
      event.toMap(),
      where: 'id = ?',
      whereArgs: [event.id],
    );
  }

  Future<void> deleteEvent(String id) async {
    final db = await database;
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Lesson>> getLessons() async {
    final db = await database;
    final maps = await db.query('lessons', orderBy: 'day_of_week ASC, lesson_number ASC');
    return maps.map((map) => Lesson.fromMap(map)).toList();
  }

  Future<List<Lesson>> getTodayLessons() async {
    final db = await database;
    final dayOfWeek = DateTime.now().weekday;

    final maps = await db.query(
      'lessons',
      where: 'day_of_week = ?',
      whereArgs: [dayOfWeek],
      orderBy: 'lesson_number ASC',
    );
    return maps.map((map) => Lesson.fromMap(map)).toList();
  }

  Future<List<Lesson>> getLessonsByDay(int dayOfWeek) async {
    final db = await database;
    final maps = await db.query(
      'lessons',
      where: 'day_of_week = ?',
      whereArgs: [dayOfWeek],
      orderBy: 'lesson_number ASC',
    );
    return maps.map((map) => Lesson.fromMap(map)).toList();
  }

  Future<void> insertLesson(Lesson lesson) async {
    final db = await database;
    await db.insert(
      'lessons',
      lesson.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateLesson(Lesson lesson) async {
    final db = await database;
    await db.update(
      'lessons',
      lesson.toMap(),
      where: 'id = ?',
      whereArgs: [lesson.id],
    );
  }

  Future<void> deleteLesson(String id) async {
    final db = await database;
    await db.delete('lessons', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getTimetablePeriods() async {
    final db = await database;
    return await db.query('timetable_periods', orderBy: 'period_number ASC');
  }

  Future<void> insertTimetablePeriod({
    required int periodNumber,
    String? name,
    required String startTime,
    required String endTime,
    bool hasSplit = false,
    int? splitBreakMinutes,
  }) async {
    final db = await database;
    await db.insert('timetable_periods', {
      'period_number': periodNumber,
      'name': name ?? '$periodNumber. Stunde',
      'start_time': startTime,
      'end_time': endTime,
      'has_split': hasSplit ? 1 : 0,
      'split_break_minutes': splitBreakMinutes,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateTimetablePeriod({
    required int periodNumber,
    String? name,
    String? startTime,
    String? endTime,
    bool? hasSplit,
    int? splitBreakMinutes,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (startTime != null) updates['start_time'] = startTime;
    if (endTime != null) updates['end_time'] = endTime;
    if (hasSplit != null) updates['has_split'] = hasSplit ? 1 : 0;
    if (splitBreakMinutes != null) updates['split_break_minutes'] = splitBreakMinutes;
    await db.update('timetable_periods', updates, where: 'period_number = ?', whereArgs: [periodNumber]);
  }

  Future<void> deleteTimetablePeriod(int periodNumber) async {
    final db = await database;
    await db.delete('timetable_periods', where: 'period_number = ?', whereArgs: [periodNumber]);
  }

  Future<void> clearTimetablePeriods() async {
    final db = await database;
    await db.delete('timetable_periods');
  }

  Future<void> seedDefaultTimetablePeriods() async {
    final db = await database;
    final existing = await db.query('timetable_periods');
    if (existing.isNotEmpty) return;

    final defaultPeriods = [
      {'period': 1, 'start': '08:00', 'end': '08:45'},
      {'period': 2, 'start': '08:50', 'end': '09:35'},
      {'period': 3, 'start': '09:55', 'end': '10:40'},
      {'period': 4, 'start': '10:45', 'end': '11:30'},
      {'period': 5, 'start': '11:50', 'end': '12:35'},
      {'period': 6, 'start': '12:40', 'end': '13:25'},
      {'period': 7, 'start': '13:30', 'end': '14:15'},
      {'period': 8, 'start': '14:20', 'end': '15:05'},
      {'period': 9, 'start': '15:10', 'end': '15:55'},
      {'period': 10, 'start': '16:00', 'end': '16:45'},
    ];

    for (final p in defaultPeriods) {
      await insertTimetablePeriod(
        periodNumber: p['period'] as int,
        startTime: p['start'] as String,
        endTime: p['end'] as String,
      );
    }
  }

  Future<int> getOpenTaskCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM tasks WHERE completed = 0');
    return result.first['count'] as int;
  }

  Future<int> getTodayEventCount() async {
    final db = await database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE start_time >= ? AND start_time < ?',
      [today.toIso8601String(), tomorrow.toIso8601String()],
    );
    return result.first['count'] as int;
  }

  Future<List<Bookmark>> getBookmarks() async {
    final db = await database;
    final maps = await db.query('bookmarks', orderBy: 'created_at DESC');
    return maps.map((map) => Bookmark.fromMap(map)).toList();
  }

  Future<List<Bookmark>> getBookmarksByCategory(String category) async {
    final db = await database;
    final maps = await db.query('bookmarks', where: 'category = ?', whereArgs: [category], orderBy: 'created_at DESC');
    return maps.map((map) => Bookmark.fromMap(map)).toList();
  }

  Future<void> insertBookmark(Bookmark bookmark) async {
    final db = await database;
    await db.insert('bookmarks', bookmark.toMap());
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    final db = await database;
    await db.update('bookmarks', bookmark.toMap(), where: 'id = ?', whereArgs: [bookmark.id]);
  }

  Future<void> deleteBookmark(String id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<QuickNote>> getQuickNotes() async {
    final db = await database;
    final maps = await db.query('quick_notes', orderBy: 'updated_at DESC');
    return maps.map((map) => QuickNote.fromMap(map)).toList();
  }

  Future<QuickNote?> getQuickNote(String id) async {
    final db = await database;
    final maps = await db.query('quick_notes', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return QuickNote.fromMap(maps.first);
  }

  Future<void> insertQuickNote(QuickNote note) async {
    final db = await database;
    await db.insert('quick_notes', note.toMap());
  }

  Future<void> updateQuickNote(QuickNote note) async {
    final db = await database;
    await db.update('quick_notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  Future<void> deleteQuickNote(String id) async {
    final db = await database;
    await db.delete('quick_notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getSubjects() async {
    final db = await database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        short_name TEXT,
        color TEXT,
        teacher TEXT,
        room TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    return await db.query('subjects', orderBy: 'name ASC');
  }

  Future<int> insertSubject({
    required String name,
    String? shortName,
    String? color,
    String? teacher,
    String? room,
  }) async {
    final db = await database;
    return await db.insert('subjects', {
      'name': name,
      'short_name': shortName,
      'color': color,
      'teacher': teacher,
      'room': room,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateSubject(int id, {
    String? name,
    String? shortName,
    String? color,
    String? teacher,
    String? room,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (shortName != null) updates['short_name'] = shortName;
    if (color != null) updates['color'] = color;
    if (teacher != null) updates['teacher'] = teacher;
    if (room != null) updates['room'] = room;
    await db.update('subjects', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSubject(int id) async {
    final db = await database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getHomework() async {
    final db = await database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS homework (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subject_id INTEGER,
        notes TEXT,
        due_date TEXT,
        completed INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    return await db.rawQuery('''
      SELECT h.*, s.name as subject_name, s.color as subject_color
      FROM homework h
      LEFT JOIN subjects s ON h.subject_id = s.id
      ORDER BY h.due_date ASC, h.created_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getOpenHomework() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT h.*, s.name as subject_name, s.color as subject_color
      FROM homework h
      LEFT JOIN subjects s ON h.subject_id = s.id
      WHERE h.completed = 0
      ORDER BY h.due_date ASC, h.created_at DESC
    ''');
  }

  Future<void> insertHomework({
    required String id,
    required String title,
    int? subjectId,
    String? notes,
    DateTime? dueDate,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('homework', {
      'id': id,
      'title': title,
      'subject_id': subjectId,
      'notes': notes,
      'due_date': dueDate?.toIso8601String(),
      'completed': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateHomework(String id, {
    String? title,
    int? subjectId,
    String? notes,
    DateTime? dueDate,
    bool? completed,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (title != null) updates['title'] = title;
    if (subjectId != null) updates['subject_id'] = subjectId;
    if (notes != null) updates['notes'] = notes;
    if (dueDate != null) updates['due_date'] = dueDate.toIso8601String();
    if (completed != null) updates['completed'] = completed ? 1 : 0;
    await db.update('homework', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleHomeworkComplete(String id, bool completed) async {
    final db = await database;
    await db.update(
      'homework',
      {'completed': completed ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteHomework(String id) async {
    final db = await database;
    await db.delete('homework', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChatMessage>> getChatMessages() async {
    final db = await database;
    final maps = await db.query('chat_messages', orderBy: 'timestamp ASC');
    return maps.map((map) => ChatMessage.fromMap(map)).toList();
  }

  Future<void> insertChatMessage(ChatMessage message) async {
    final db = await database;
    await db.insert('chat_messages', message.toMap());
  }

  Future<void> clearChatHistory() async {
    final db = await database;
    await db.delete('chat_messages');
  }

  Future<Map<String, dynamic>?> getSyncStatus(String tableName) async {
    final db = await database;
    final maps = await db.query('sync_status', where: 'table_name = ?', whereArgs: [tableName]);
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<void> updateSyncStatus(String tableName, {String? syncToken, String? error}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'sync_status',
      {
        'table_name': tableName,
        'last_sync_at': now,
        'sync_token': syncToken,
        'error': error,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final db = await database;
    return await db.query('pending_operations', where: 'status = ?', whereArgs: ['pending'], orderBy: 'created_at ASC');
  }

  Future<int> insertPendingOperation({
    required String operationType,
    required String entityType,
    String? entityId,
    String? payloadJson,
  }) async {
    final db = await database;
    return await db.insert('pending_operations', {
      'operation_type': operationType,
      'entity_type': entityType,
      'entity_id': entityId,
      'payload_json': payloadJson,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });
  }

  Future<void> markOperationCompleted(int id) async {
    final db = await database;
    await db.update('pending_operations', {'status': 'completed'}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markOperationFailed(int id, String error, {bool giveUp = true}) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_operations SET status = ?, last_error = ?, retry_count = retry_count + 1 WHERE id = ?',
      [giveUp ? 'failed' : 'pending', error, id],
    );
  }

  Future<void> clearCompletedOperations() async {
    final db = await database;
    await db.delete('pending_operations', where: 'status = ?', whereArgs: ['completed']);
  }

  Future<int> getPendingOperationCount() async {
    final db = await database;
    final result = await db.rawQuery("SELECT COUNT(*) as count FROM pending_operations WHERE status = 'pending'");
    return result.first['count'] as int;
  }

  Future<List<EmailAccount>> getEmailAccounts() async {
    final db = await database;
    final maps = await db.query('email_accounts', orderBy: 'added_at DESC');
    return maps.map((map) => EmailAccount.fromMap(_mapEmailAccountFromDb(map))).toList();
  }

  Map<String, dynamic> _mapEmailAccountFromDb(Map<String, dynamic> dbMap) {
    return {
      'id': dbMap['id'],
      'email': dbMap['email'],
      'display_name': dbMap['display_name'],
      'type': dbMap['provider'],
      'imap_host': null,
      'imap_port': null,
      'smtp_host': null,
      'smtp_port': null,
      'is_default': dbMap['is_active'],
      'created_at': dbMap['added_at'],
      'last_sync_at': null,
    };
  }

  Future<String?> getEmailAccountCredentialKey(String id) async {
    final db = await database;
    final rows = await db.query('email_accounts', columns: ['credential_key'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['credential_key'] as String?;
  }

  Future<void> insertEmailAccount(EmailAccount account, {String? credentialKey}) async {
    final db = await database;
    await db.insert('email_accounts', {
      'id': account.id,
      'email': account.email,
      'provider': account.type.name,
      'display_name': account.displayName,
      'credential_key': credentialKey ?? 'email_${account.id}',
      'is_active': account.isDefault ? 1 : 0,
      'added_at': account.createdAt.toIso8601String(),
    });
  }

  Future<void> updateEmailAccount(EmailAccount account) async {
    final db = await database;
    await db.update(
      'email_accounts',
      {
        'email': account.email,
        'provider': account.type.name,
        'display_name': account.displayName,
        'is_active': account.isDefault ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<void> deleteEmailAccount(String id) async {
    final db = await database;
    await db.delete('email_accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<EmailFolder>> getEmailFolders(String accountId) async {
    final db = await database;
    final maps = await db.query(
      'email_folders',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    return maps.map((map) => EmailFolder.fromMap(map)).toList();
  }

  Future<void> insertEmailFolder(EmailFolder folder) async {
    final db = await database;
    await db.insert('email_folders', {
      'id': folder.id,
      'account_id': folder.accountId,
      'name': folder.name,
      'path': folder.path,
      'unread_count': folder.unreadCount,
      'total_count': folder.totalCount,
    });
  }

  Future<void> updateEmailFolder(EmailFolder folder) async {
    final db = await database;
    await db.update(
      'email_folders',
      {
        'name': folder.name,
        'path': folder.path,
        'unread_count': folder.unreadCount,
        'total_count': folder.totalCount,
      },
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  Future<List<Email>> getCachedEmails({
    required String accountId,
    required String folderId,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    final maps = await db.query(
      'cached_emails',
      where: 'account_id = ?${folderId.isNotEmpty ? ' AND folder = ?' : ''}',
      whereArgs: folderId.isNotEmpty ? [accountId, folderId] : [accountId],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((map) => Email.fromMap(_mapCachedEmailFromDb(map))).toList();
  }

  Map<String, dynamic> _mapCachedEmailFromDb(Map<String, dynamic> dbMap) {
    return {
      'id': dbMap['id'],
      'account_id': dbMap['account_id'],
      'folder_id': dbMap['folder'] ?? '',
      'message_id': null,
      'subject': dbMap['subject'] ?? '',
      'from_address': dbMap['from_email'] ?? '',
      'from_name': dbMap['from_name'],
      'to_addresses': '["${dbMap['to_email'] ?? ''}"]',
      'cc_addresses': null,
      'bcc_addresses': null,
      'body_plain': dbMap['body'],
      'body_html': null,
      'date': dbMap['date'] ?? DateTime.now().toIso8601String(),
      'is_read': dbMap['is_read'],
      'is_starred': dbMap['is_starred'],
      'has_attachments': dbMap['has_attachments'],
      'attachments': null,
    };
  }

  Future<Email?> getCachedEmail(String id) async {
    final db = await database;
    final maps = await db.query('cached_emails', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Email.fromMap(_mapCachedEmailFromDb(maps.first));
  }

  Future<void> insertCachedEmail(Email email) async {
    final db = await database;
    await db.insert('cached_emails', {
      'id': email.id,
      'account_id': email.accountId,
      'folder': email.folderId,
      'from_email': email.from,
      'from_name': email.fromName,
      'to_email': email.to.isNotEmpty ? email.to.first : '',
      'subject': email.subject,
      'preview': email.preview,
      'body': email.bodyPlain,
      'date': email.date.toIso8601String(),
      'is_read': email.isRead ? 1 : 0,
      'is_starred': email.isStarred ? 1 : 0,
      'has_attachments': email.hasAttachments ? 1 : 0,
      'cached_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateCachedEmail(Email email) async {
    final db = await database;
    await db.update(
      'cached_emails',
      {
        'folder': email.folderId,
        'from_email': email.from,
        'from_name': email.fromName,
        'to_email': email.to.isNotEmpty ? email.to.first : '',
        'subject': email.subject,
        'preview': email.preview,
        'body': email.bodyPlain,
        'is_read': email.isRead ? 1 : 0,
        'is_starred': email.isStarred ? 1 : 0,
        'has_attachments': email.hasAttachments ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [email.id],
    );
  }

  Future<void> deleteCachedEmail(String id) async {
    final db = await database;
    await db.delete('cached_emails', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<VbbLocation>> getCachedVbbLocations(String query) async {
    final db = await database;
    final queryKey = query.toLowerCase();
    final maps = await db.query(
      'vbb_location_cache',
      where: 'query_key = ?',
      whereArgs: [queryKey],
    );
    if (maps.isEmpty) return [];

    final now = DateTime.now();
    final cached = maps.first;
    final cachedAt = DateTime.parse(cached['cached_at'] as String);

    if (now.difference(cachedAt).inDays > 7) {
      await db.delete('vbb_location_cache', where: 'query_key = ?', whereArgs: [queryKey]);
      return [];
    }

    final results = jsonDecode(cached['results_json'] as String) as List;
    return results.map((r) => VbbLocation.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> cacheVbbLocations(String query, List<VbbLocation> locations) async {
    final db = await database;
    await db.insert(
      'vbb_location_cache',
      {
        'query_key': query.toLowerCase(),
        'results_json': jsonEncode(locations.map((l) => l.toMap()).toList()),
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VbbJourney>> getCachedVbbRoutes(String cacheKey) async {
    final db = await database;
    final maps = await db.query(
      'vbb_route_cache',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
    );
    if (maps.isEmpty) return [];

    final now = DateTime.now();
    final cached = maps.first;
    final cachedAt = DateTime.parse(cached['cached_at'] as String);

    if (now.difference(cachedAt).inMinutes > 30) {
      await db.delete('vbb_route_cache', where: 'cache_key = ?', whereArgs: [cacheKey]);
      return [];
    }

    final results = jsonDecode(cached['routes_json'] as String) as List;
    return results.map((r) => VbbJourney.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<void> cacheVbbRoutes(String cacheKey, List<VbbJourney> journeys) async {
    final db = await database;
    final from = journeys.isNotEmpty ? journeys.first.from : null;
    final to = journeys.isNotEmpty ? journeys.first.to : null;

    await db.insert(
      'vbb_route_cache',
      {
        'cache_key': cacheKey,
        'from_json': from != null ? jsonEncode(from.toMap()) : '{}',
        'to_json': to != null ? jsonEncode(to.toMap()) : '{}',
        'routes_json': jsonEncode(journeys.map((j) => j.toMap()).toList()),
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VbbKnownLocation>> getVbbKnownLocations() async {
    final db = await database;
    final maps = await db.query('vbb_known_locations');
    return maps.map((map) => VbbKnownLocation.fromMap({
      'id': map['key'],
      'name': map['name'],
      'alias': map['key'],
      'location_id': map['vbb_id'] ?? '',
      'location_name': map['name'],
      'latitude': map['latitude'],
      'longitude': map['longitude'],
    })).toList();
  }

  Future<void> insertVbbKnownLocation(VbbKnownLocation location) async {
    final db = await database;
    await db.insert('vbb_known_locations', {
      'key': location.alias,
      'name': location.name,
      'vbb_id': location.locationId,
      'latitude': location.latitude ?? 0,
      'longitude': location.longitude ?? 0,
      'type': 'station',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteVbbKnownLocation(String id) async {
    final db = await database;
    await db.delete('vbb_known_locations', where: 'key = ?', whereArgs: [id]);
  }

  Future<List<VbbFavoriteRoute>> getVbbFavoriteRoutes() async {
    final db = await database;
    final maps = await db.query('vbb_favorite_routes', orderBy: 'created_at DESC');
    return maps.map((map) {
      final fromJson = jsonDecode(map['from_location_json'] as String) as Map<String, dynamic>;
      final toJson = jsonDecode(map['to_location_json'] as String) as Map<String, dynamic>;
      return VbbFavoriteRoute(
        id: (map['id'] as int).toString(),
        name: map['name'] as String,
        fromId: fromJson['id'] as String? ?? '',
        fromName: fromJson['name'] as String? ?? '',
        toId: toJson['id'] as String? ?? '',
        toName: toJson['name'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
      );
    }).toList();
  }

  Future<void> insertVbbFavoriteRoute(VbbFavoriteRoute route) async {
    final db = await database;
    await db.insert('vbb_favorite_routes', {
      'name': route.name,
      'from_location_json': jsonEncode({'id': route.fromId, 'name': route.fromName}),
      'to_location_json': jsonEncode({'id': route.toId, 'name': route.toName}),
      'created_at': route.createdAt.toIso8601String(),
    });
  }

  Future<void> deleteVbbFavoriteRoute(String id) async {
    final db = await database;
    await db.delete('vbb_favorite_routes', where: 'id = ?', whereArgs: [int.parse(id)]);
  }


  Future<List<VbbTicket>> getVbbTickets() async {
    final db = await database;
    final maps = await db.query('vbb_tickets', orderBy: 'created_at DESC');
    return maps.map((map) => VbbTicket.fromMap(map.map((k, v) => MapEntry(k, v)))).toList();
  }

  Future<void> insertVbbTicket(VbbTicket ticket) async {
    final db = await database;
    await db.insert('vbb_tickets', ticket.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateVbbTicket(VbbTicket ticket) async {
    final db = await database;
    await db.update('vbb_tickets', ticket.toMap(), where: 'id = ?', whereArgs: [ticket.id]);
  }

  Future<void> deleteVbbTicket(String id) async {
    final db = await database;
    await db.delete('vbb_tickets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearOldVbbCache() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await db.delete(
      'vbb_location_cache',
      where: 'cached_at < ?',
      whereArgs: [cutoff.toIso8601String()],
    );
    final routeCutoff = DateTime.now().subtract(const Duration(hours: 1));
    await db.delete(
      'vbb_route_cache',
      where: 'cached_at < ?',
      whereArgs: [routeCutoff.toIso8601String()],
    );
  }

  Future<List<GoogleCalendar>> getGoogleCalendars() async {
    final db = await database;
    final maps = await db.query('google_calendars');
    return maps.map((map) => GoogleCalendar.fromMap({
      'id': map['id'],
      'summary': map['name'],
      'description': null,
      'background_color': map['color'],
      'is_primary': map['is_primary'],
      'is_selected': map['is_visible'],
    })).toList();
  }

  Future<void> upsertGoogleCalendar(GoogleCalendar calendar) async {
    final db = await database;
    await db.insert('google_calendars', {
      'id': calendar.id,
      'account_email': '',
      'name': calendar.summary,
      'color': calendar.backgroundColor,
      'is_primary': calendar.isPrimary ? 1 : 0,
      'is_visible': calendar.isSelected ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<GoogleEvent?> getGoogleEvent(String id) async {
    final db = await database;
    final maps = await db.query('google_events', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return _googleEventFromMap(maps.first);
  }

  GoogleEvent _googleEventFromMap(Map<String, dynamic> map) {
    return GoogleEvent(
      id: map['id'] as String,
      calendarId: map['calendar_id'] as String,
      summary: map['title'] as String,
      description: map['description'] as String?,
      location: map['location'] as String?,
      start: DateTime.parse(map['start_time'] as String? ?? map['start_date'] as String),
      end: DateTime.parse(map['end_time'] as String? ?? map['end_date'] as String),
      isAllDay: (map['all_day'] as int?) == 1,
      isSynced: map['sync_status'] == 'synced',
    );
  }

  Future<List<GoogleEvent>> getGoogleEvents({
    required String calendarId,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await database;
    String where = 'calendar_id = ?';
    List<dynamic> whereArgs = [calendarId];

    if (from != null) {
      where += ' AND (start_time >= ? OR start_date >= ?)';
      whereArgs.addAll([from.toIso8601String(), from.toIso8601String().split('T')[0]]);
    }
    if (to != null) {
      where += ' AND (start_time <= ? OR start_date <= ?)';
      whereArgs.addAll([to.toIso8601String(), to.toIso8601String()]);
    }

    final maps = await db.query('google_events', where: where, whereArgs: whereArgs);
    return maps.map((m) => _googleEventFromMap(m)).toList();
  }

  Future<List<GoogleEvent>> getAllGoogleEvents({DateTime? from, DateTime? to}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;

    if (from != null || to != null) {
      final parts = <String>[];
      whereArgs = [];
      if (from != null) {
        parts.add('(start_time >= ? OR start_date >= ?)');
        whereArgs.addAll([from.toIso8601String(), from.toIso8601String().split('T')[0]]);
      }
      if (to != null) {
        parts.add('(start_time <= ? OR start_date <= ?)');
        whereArgs.addAll([to.toIso8601String(), to.toIso8601String()]);
      }
      where = parts.join(' AND ');
    }

    final maps = await db.query('google_events', where: where, whereArgs: whereArgs);
    return maps.map((m) => _googleEventFromMap(m)).toList();
  }

  Future<void> insertGoogleEvent(GoogleEvent event) async {
    final db = await database;
    await db.insert('google_events', {
      'id': event.id,
      'calendar_id': event.calendarId,
      'account_email': '',
      'title': event.summary,
      'start_date': event.isAllDay ? event.start.toIso8601String().split('T')[0] : null,
      'start_time': event.isAllDay ? null : event.start.toIso8601String(),
      'end_date': event.isAllDay ? event.end.toIso8601String().split('T')[0] : null,
      'end_time': event.isAllDay ? null : event.end.toIso8601String(),
      'all_day': event.isAllDay ? 1 : 0,
      'location': event.location,
      'description': event.description,
      'sync_status': event.isSynced ? 'synced' : 'pending',
    });
  }

  Future<void> updateGoogleEvent(GoogleEvent event) async {
    final db = await database;
    await db.update('google_events', {
      'title': event.summary,
      'start_date': event.isAllDay ? event.start.toIso8601String().split('T')[0] : null,
      'start_time': event.isAllDay ? null : event.start.toIso8601String(),
      'end_date': event.isAllDay ? event.end.toIso8601String().split('T')[0] : null,
      'end_time': event.isAllDay ? null : event.end.toIso8601String(),
      'all_day': event.isAllDay ? 1 : 0,
      'location': event.location,
      'description': event.description,
      'sync_status': event.isSynced ? 'synced' : 'pending',
    }, where: 'id = ?', whereArgs: [event.id]);
  }

  Future<void> deleteGoogleEvent(String id) async {
    final db = await database;
    await db.delete('google_events', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> saveSyncToken(String calendarId, String token) async {
    final db = await database;
    await db.insert('sync_status', {
      'table_name': 'google_calendar_$calendarId',
      'sync_token': token,
      'last_sync_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSyncToken(String calendarId) async {
    final db = await database;
    final maps = await db.query(
      'sync_status',
      where: 'table_name = ?',
      whereArgs: ['google_calendar_$calendarId'],
    );
    if (maps.isEmpty) return null;
    return maps.first['sync_token'] as String?;
  }

  Future<List<Map<String, dynamic>>> getDailyReviews() async {
    final db = await database;
    return db.query('daily_reviews', orderBy: 'date DESC');
  }

  Future<void> insertDailyReview(Map<String, dynamic> review) async {
    final db = await database;
    await db.insert('daily_reviews', review, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDailyReview(String id) async {
    final db = await database;
    await db.delete('daily_reviews', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getWeeklyReviews() async {
    final db = await database;
    return db.query('weekly_reviews', orderBy: 'week_start DESC');
  }

  Future<void> insertWeeklyReview(Map<String, dynamic> review) async {
    final db = await database;
    await db.insert('weekly_reviews', review, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWeeklyReview(String id) async {
    final db = await database;
    await db.delete('weekly_reviews', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertPomodoroSession(Map<String, dynamic> session) async {
    final db = await database;
    await db.insert('pomodoro_sessions', session, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPomodoroSessions({String? since}) async {
    final db = await database;
    if (since != null) {
      return db.query('pomodoro_sessions',
        where: 'started_at >= ?', whereArgs: [since],
        orderBy: 'started_at DESC');
    }
    return db.query('pomodoro_sessions', orderBy: 'started_at DESC');
  }

  Future<int> getPomodoroCountForTask(String taskId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM pomodoro_sessions WHERE task_id = ? AND completed = 1',
      [taskId],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<Map<String, dynamic>> getPomodoroStats({required String since}) async {
    final db = await database;
    final summary = await db.rawQuery(
      "SELECT COUNT(*) as count, COALESCE(SUM(duration_minutes), 0) as total_minutes FROM pomodoro_sessions WHERE started_at >= ? AND completed = 1",
      [since],
    );
    final byTask = await db.rawQuery(
      "SELECT task_id, COUNT(*) as sessions, COALESCE(SUM(duration_minutes), 0) as minutes FROM pomodoro_sessions WHERE started_at >= ? AND completed = 1 GROUP BY task_id ORDER BY minutes DESC",
      [since],
    );
    final byDay = await db.rawQuery(
      "SELECT substr(started_at, 1, 10) as day, COUNT(*) as count FROM pomodoro_sessions WHERE started_at >= ? AND completed = 1 GROUP BY day ORDER BY day",
      [since],
    );
    return {
      'total_sessions': summary.first['count'] as int? ?? 0,
      'total_minutes': summary.first['total_minutes'] as int? ?? 0,
      'by_task': byTask,
      'by_day': byDay,
    };
  }

  Future<Map<String, dynamic>> getWeeklyStats() async {
    final db = await database;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr = DateTime(weekStart.year, weekStart.month, weekStart.day).toIso8601String();

    final tasksCompleted = await db.rawQuery(
      "SELECT COUNT(*) as count FROM tasks WHERE completed = 1 AND updated_at >= ?",
      [weekStartStr],
    );
    final totalTasks = await db.rawQuery(
      "SELECT COUNT(*) as count FROM tasks WHERE created_at >= ?",
      [weekStartStr],
    );
    final pomodoroSessions = await db.rawQuery(
      "SELECT COUNT(*) as count, COALESCE(SUM(duration_minutes), 0) as total_minutes FROM pomodoro_sessions WHERE started_at >= ? AND completed = 1",
      [weekStartStr],
    );
    final pomodoroByDay = await db.rawQuery(
      "SELECT substr(started_at, 1, 10) as day, COUNT(*) as count FROM pomodoro_sessions WHERE started_at >= ? AND completed = 1 GROUP BY day ORDER BY day",
      [weekStartStr],
    );

    return {
      'tasks_completed': tasksCompleted.first['count'] as int? ?? 0,
      'tasks_total': totalTasks.first['count'] as int? ?? 0,
      'pomodoro_sessions': pomodoroSessions.first['count'] as int? ?? 0,
      'pomodoro_minutes': pomodoroSessions.first['total_minutes'] as int? ?? 0,
      'pomodoro_by_day': pomodoroByDay,
    };
  }

  Future<void> _createTrainingTables(Database db) async {

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_schedule (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day INTEGER NOT NULL,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL,
        muscle_groups TEXT,
        notes TEXT,
        is_holiday INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_sessions (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        duration INTEGER,
        notes TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS health_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        sleep REAL,
        energy INTEGER,
        stress INTEGER,
        recovery INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_goals (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        target_date TEXT,
        completed INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS training_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<List<dynamic>> getTrainingSchedule({required bool isHoliday}) async {
    final db = await database;

    await _createTrainingTables(db);

    final maps = await db.query(
      'training_schedule',
      where: 'is_holiday = ?',
      whereArgs: [isHoliday ? 1 : 0],
    );

    return maps;
  }

  Future<void> saveTrainingSchedule(List<dynamic> schedule, {required bool isHoliday}) async {
    final db = await database;

    await _createTrainingTables(db);

    await db.delete(
      'training_schedule',
      where: 'is_holiday = ?',
      whereArgs: [isHoliday ? 1 : 0],
    );

    for (final entry in schedule) {
      final map = entry.toMap();
      map['is_holiday'] = isHoliday ? 1 : 0;
      await db.insert('training_schedule', map);
    }
  }

  Future<List<dynamic>> getTrainingSessionsList() async {
    final db = await database;

    await _createTrainingTables(db);

    return await db.query('training_sessions', orderBy: 'date DESC');
  }

  Future<void> logTrainingSession(dynamic session) async {
    final db = await database;

    await _createTrainingTables(db);

    await db.insert(
      'training_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTrainingSession(String id) async {
    final db = await database;
    await db.delete('training_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<dynamic>> getHealthLogsList() async {
    final db = await database;

    await _createTrainingTables(db);

    return await db.query('health_logs', orderBy: 'date DESC');
  }

  Future<void> saveHealthLog(dynamic log) async {
    final db = await database;

    await _createTrainingTables(db);

    await db.insert(
      'health_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<dynamic>> getTrainingGoalsList() async {
    final db = await database;

    await _createTrainingTables(db);

    return await db.query('training_goals', orderBy: 'completed ASC, target_date ASC');
  }

  Future<void> saveTrainingGoal(dynamic goal) async {
    final db = await database;

    await _createTrainingTables(db);

    await db.insert(
      'training_goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTrainingGoal(String id) async {
    final db = await database;
    await db.delete('training_goals', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> getTrainingHolidayMode() async {
    final db = await database;

    await _createTrainingTables(db);

    final maps = await db.query(
      'training_settings',
      where: 'key = ?',
      whereArgs: ['holiday_mode'],
    );

    if (maps.isEmpty) return false;
    return maps.first['value'] == 'true';
  }

  Future<void> setTrainingHolidayMode(bool isHoliday) async {
    final db = await database;

    await _createTrainingTables(db);

    await db.insert(
      'training_settings',
      {'key': 'holiday_mode', 'value': isHoliday.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> cacheVertretungsplanFile({
    required String data,
    required int page,
    required String contentType,
  }) async {
    final db = await database;
    await db.delete('vertretungsplan_cache', where: 'page = ?', whereArgs: [page]);
    await db.insert('vertretungsplan_cache', {
      'data_base64': data,
      'page': page,
      'content_type': contentType,
      'fetched_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllCachedVertretungsplanFiles() async {
    final db = await database;
    final maps = await db.query(
      'vertretungsplan_cache',
      orderBy: 'page ASC',
    );
    return maps;
  }

  Future<void> clearVertretungsplanCache() async {
    final db = await database;
    await db.delete('vertretungsplan_cache');
  }

  Future<void> cacheVertretungsplan({
    required String htmlContent,
    required int page,
  }) async {
    await cacheVertretungsplanFile(
      data: htmlContent,
      page: page,
      contentType: 'text/html',
    );
  }

  Future<Map<String, dynamic>?> getCachedVertretungsplan(int page) async {
    final db = await database;
    final maps = await db.query(
      'vertretungsplan_cache',
      where: 'page = ?',
      whereArgs: [page],
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<DateTime?> getVertretungsplanCacheTime(int page) async {
    final cached = await getCachedVertretungsplan(page);
    if (cached == null) return null;
    final fetchedAt = cached['fetched_at'] as String?;
    if (fetchedAt == null) return null;
    return DateTime.tryParse(fetchedAt);
  }
}
