// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:hive/hive.dart';
import '../models/task.dart';
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
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<void>? _schemaUpgrade;

  Future<Box> _box(String name) async {
    _schemaUpgrade ??= _upgradeSchema();
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return await Hive.openBox(name);
  }

  Future<void> _upgradeSchema() async {
    try {
      final meta = await Hive.openBox('meta');
      final version = meta.get('schema_version') as int? ?? 0;
      if (version < 1) {
        for (final name in const ['drawings', 'projects', 'knowledge_entries']) {
          final box = await Hive.openBox(name);
          final isEmpty = box.isEmpty;
          await box.close();
          if (isEmpty) await Hive.deleteBoxFromDisk(name);
        }
        await meta.put('schema_version', 1);
      }
    } catch (_) {}
  }

  Map<String, dynamic> _cast(dynamic data) {
    if (data is Map) {
      return data.map((k, v) {
        if (v is Map) return MapEntry(k.toString(), _cast(v));
        if (v is List) {
          return MapEntry(
            k.toString(),
            v.map((e) => e is Map ? _cast(e) : e).toList(),
          );
        }
        return MapEntry(k.toString(), v);
      });
    }
    return {};
  }


  Future<List<Task>> getTasks() async {
    final box = await _box('tasks');
    return box.values.map((v) => Task.fromMap(_cast(v))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Task>> getTodayTasks() async {
    final tasks = await getTasks();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return tasks.where((t) {
      if (t.dueDate == null) return false;
      return t.dueDate!.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
             t.dueDate!.isBefore(todayEnd);
    }).toList();
  }

  Future<List<Task>> getOpenTasks() async {
    final tasks = await getTasks();
    return tasks.where((t) => !t.completed).toList();
  }

  Future<void> insertTask(Task task) async {
    final box = await _box('tasks');
    await box.put(task.id, task.toMap());
  }

  Future<void> updateTask(Task task) async {
    final box = await _box('tasks');
    await box.put(task.id, task.toMap());
  }

  Future<void> deleteTask(String id) async {
    final box = await _box('tasks');
    await box.delete(id);
  }

  Future<void> toggleTaskComplete(String id, bool completed) async {
    final box = await _box('tasks');
    final data = box.get(id);
    if (data != null) {
      final map = _cast(data);
      map['completed'] = completed ? 1 : 0;
      map['updated_at'] = DateTime.now().toIso8601String();
      await box.put(id, map);
    }
  }


  Future<List<Event>> getEvents() async {
    final box = await _box('events');
    return box.values.map((v) => Event.fromMap(_cast(v))).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<List<Event>> getTodayEvents() async {
    final events = await getEvents();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return events.where((e) =>
      e.startTime.isBefore(todayEnd) && e.endTime.isAfter(todayStart)
    ).toList();
  }

  Future<List<Event>> getUpcomingEvents({int days = 7}) async {
    final events = await getEvents();
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: days));
    return events.where((e) =>
      e.startTime.isAfter(now) && e.startTime.isBefore(cutoff)
    ).toList();
  }

  Future<void> insertEvent(Event event) async {
    final box = await _box('events');
    await box.put(event.id, event.toMap());
  }

  Future<void> updateEvent(Event event) async {
    final box = await _box('events');
    await box.put(event.id, event.toMap());
  }

  Future<void> deleteEvent(String id) async {
    final box = await _box('events');
    await box.delete(id);
  }


  Future<List<Lesson>> getLessons() async {
    final box = await _box('lessons');
    return box.values.map((v) => Lesson.fromMap(_cast(v))).toList()
      ..sort((a, b) {
        final dayCompare = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (dayCompare != 0) return dayCompare;
        return a.lessonNumber.compareTo(b.lessonNumber);
      });
  }

  Future<List<Lesson>> getTodayLessons() async {
    final dayOfWeek = DateTime.now().weekday;
    return getLessonsByDay(dayOfWeek);
  }

  Future<List<Lesson>> getLessonsByDay(int dayOfWeek) async {
    final lessons = await getLessons();
    return lessons.where((l) => l.dayOfWeek == dayOfWeek).toList();
  }

  Future<void> insertLesson(Lesson lesson) async {
    final box = await _box('lessons');
    await box.put(lesson.id, lesson.toMap());
  }

  Future<void> updateLesson(Lesson lesson) async {
    final box = await _box('lessons');
    await box.put(lesson.id, lesson.toMap());
  }

  Future<void> deleteLesson(String id) async {
    final box = await _box('lessons');
    await box.delete(id);
  }


  Future<List<Map<String, dynamic>>> getTimetablePeriods() async {
    final box = await _box('timetable_periods');
    final periods = box.values.map((v) => _cast(v)).toList();
    periods.sort((a, b) =>
      ((a['period_number'] as int?) ?? 0).compareTo((b['period_number'] as int?) ?? 0));
    return periods;
  }

  Future<void> insertTimetablePeriod({
    required int periodNumber,
    String? name,
    required String startTime,
    required String endTime,
    bool hasSplit = false,
    int? splitBreakMinutes,
  }) async {
    final box = await _box('timetable_periods');
    await box.put(periodNumber, {
      'period_number': periodNumber,
      'name': name ?? '$periodNumber. Stunde',
      'start_time': startTime,
      'end_time': endTime,
      'has_split': hasSplit ? 1 : 0,
      'split_break_minutes': splitBreakMinutes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateTimetablePeriod({
    required int periodNumber,
    String? name,
    String? startTime,
    String? endTime,
    bool? hasSplit,
    int? splitBreakMinutes,
  }) async {
    final box = await _box('timetable_periods');
    final data = box.get(periodNumber);
    if (data != null) {
      final map = _cast(data);
      if (name != null) map['name'] = name;
      if (startTime != null) map['start_time'] = startTime;
      if (endTime != null) map['end_time'] = endTime;
      if (hasSplit != null) map['has_split'] = hasSplit ? 1 : 0;
      if (splitBreakMinutes != null) map['split_break_minutes'] = splitBreakMinutes;
      await box.put(periodNumber, map);
    }
  }

  Future<void> deleteTimetablePeriod(int periodNumber) async {
    final box = await _box('timetable_periods');
    await box.delete(periodNumber);
  }

  Future<void> clearTimetablePeriods() async {
    final box = await _box('timetable_periods');
    await box.clear();
  }

  Future<void> seedDefaultTimetablePeriods() async {
    final box = await _box('timetable_periods');
    if (box.isNotEmpty) return;

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


  Future<void> cacheVertretungsplanFile({
    required String data,
    required int page,
    required String contentType,
  }) async {
    final box = await _box('vertretungsplan_cache');
    await box.put(page, {
      'data_base64': data,
      'page': page,
      'content_type': contentType,
      'fetched_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllCachedVertretungsplanFiles() async {
    final box = await _box('vertretungsplan_cache');
    final files = box.values.map((v) => _cast(v)).toList();
    files.sort((a, b) =>
      ((a['page'] as int?) ?? 0).compareTo((b['page'] as int?) ?? 0));
    return files;
  }

  Future<void> clearVertretungsplanCache() async {
    final box = await _box('vertretungsplan_cache');
    await box.clear();
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
    final box = await _box('vertretungsplan_cache');
    final data = box.get(page);
    if (data == null) return null;
    return _cast(data);
  }

  Future<DateTime?> getVertretungsplanCacheTime(int page) async {
    final cached = await getCachedVertretungsplan(page);
    if (cached == null) return null;
    final fetchedAt = cached['fetched_at'] as String?;
    if (fetchedAt == null) return null;
    return DateTime.tryParse(fetchedAt);
  }


  Future<int> getOpenTaskCount() async {
    final tasks = await getOpenTasks();
    return tasks.length;
  }

  Future<int> getTodayEventCount() async {
    final events = await getTodayEvents();
    return events.length;
  }


  Future<List<Bookmark>> getBookmarks() async {
    final box = await _box('bookmarks');
    return box.values.map((v) => Bookmark.fromMap(_cast(v))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Bookmark>> getBookmarksByCategory(String category) async {
    final bookmarks = await getBookmarks();
    return bookmarks.where((b) => b.category == category).toList();
  }

  Future<void> insertBookmark(Bookmark bookmark) async {
    final box = await _box('bookmarks');
    await box.put(bookmark.id, bookmark.toMap());
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    final box = await _box('bookmarks');
    await box.put(bookmark.id, bookmark.toMap());
  }

  Future<void> deleteBookmark(String id) async {
    final box = await _box('bookmarks');
    await box.delete(id);
  }


  Future<List<QuickNote>> getQuickNotes() async {
    final box = await _box('quick_notes');
    return box.values.map((v) => QuickNote.fromMap(_cast(v))).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<QuickNote?> getQuickNote(String id) async {
    final box = await _box('quick_notes');
    final data = box.get(id);
    if (data == null) return null;
    return QuickNote.fromMap(_cast(data));
  }

  Future<void> insertQuickNote(QuickNote note) async {
    final box = await _box('quick_notes');
    await box.put(note.id, note.toMap());
  }

  Future<void> updateQuickNote(QuickNote note) async {
    final box = await _box('quick_notes');
    await box.put(note.id, note.toMap());
  }

  Future<void> deleteQuickNote(String id) async {
    final box = await _box('quick_notes');
    await box.delete(id);
  }


  Future<List<Map<String, dynamic>>> getSubjects() async {
    final box = await _box('subjects');
    return box.keys.map((key) {
      final map = _cast(box.get(key));
      map['id'] = key is int ? key : int.tryParse(key.toString()) ?? 0;
      return map;
    }).toList();
  }

  Future<int> insertSubject({
    required String name,
    String? shortName,
    String? color,
    String? teacher,
    String? room,
  }) async {
    final box = await _box('subjects');
    final meta = await _box('meta');
    final nextId = (meta.get('next_subject_id') as int?) ?? 1;
    await meta.put('next_subject_id', nextId + 1);

    final map = <String, dynamic>{
      'name': name,
      'short_name': shortName,
      'color': color,
      'teacher': teacher,
      'room': room,
    };
    await box.put(nextId, map);
    return nextId;
  }

  Future<void> updateSubject(int id, {
    String? name,
    String? shortName,
    String? color,
    String? teacher,
    String? room,
  }) async {
    final box = await _box('subjects');
    final data = box.get(id);
    if (data != null) {
      final map = _cast(data);
      if (name != null) map['name'] = name;
      if (shortName != null) map['short_name'] = shortName;
      if (color != null) map['color'] = color;
      if (teacher != null) map['teacher'] = teacher;
      if (room != null) map['room'] = room;
      await box.put(id, map);
    }
  }

  Future<void> deleteSubject(int id) async {
    final box = await _box('subjects');
    await box.delete(id);
  }


  Future<List<Map<String, dynamic>>> getHomework() async {
    final box = await _box('homework');
    return box.values.map((v) => _cast(v)).toList();
  }

  Future<List<Map<String, dynamic>>> getOpenHomework() async {
    final all = await getHomework();
    return all.where((h) => (h['completed'] as int?) != 1).toList();
  }

  Future<void> insertHomework({
    required String id,
    required String title,
    int? subjectId,
    String? notes,
    DateTime? dueDate,
  }) async {
    final box = await _box('homework');
    await box.put(id, {
      'id': id,
      'title': title,
      'subject_id': subjectId,
      'notes': notes,
      'due_date': dueDate?.toIso8601String(),
      'completed': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateHomework(String id, {
    String? title,
    int? subjectId,
    String? notes,
    DateTime? dueDate,
    bool? completed,
  }) async {
    final box = await _box('homework');
    final data = box.get(id);
    if (data != null) {
      final map = _cast(data);
      if (title != null) map['title'] = title;
      if (subjectId != null) map['subject_id'] = subjectId;
      if (notes != null) map['notes'] = notes;
      if (dueDate != null) map['due_date'] = dueDate.toIso8601String();
      if (completed != null) map['completed'] = completed ? 1 : 0;
      await box.put(id, map);
    }
  }

  Future<void> toggleHomeworkComplete(String id, bool completed) async {
    await updateHomework(id, completed: completed);
  }

  Future<void> deleteHomework(String id) async {
    final box = await _box('homework');
    await box.delete(id);
  }


  Future<List<ChatMessage>> getChatMessages() async {
    final box = await _box('chat_messages');
    return box.values.map((v) => ChatMessage.fromMap(_cast(v))).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> insertChatMessage(ChatMessage message) async {
    final box = await _box('chat_messages');
    await box.put(message.id, message.toMap());
  }

  Future<void> clearChatHistory() async {
    final box = await _box('chat_messages');
    await box.clear();
  }


  Future<Map<String, dynamic>?> getSyncStatus(String tableName) async {
    final box = await _box('sync_status');
    final data = box.get(tableName);
    if (data == null) return null;
    return _cast(data);
  }

  Future<void> updateSyncStatus(String tableName, {String? syncToken, String? error}) async {
    final box = await _box('sync_status');
    final existing = _cast(box.get(tableName) ?? {});
    existing['table_name'] = tableName;
    existing['last_sync_at'] = DateTime.now().toIso8601String();
    if (syncToken != null) existing['sync_token'] = syncToken;
    if (error != null) existing['error'] = error;
    await box.put(tableName, existing);
  }


  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final box = await _box('pending_operations');
    final ops = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final map = _cast(box.get(key));
      final status = map['status'] as String? ?? 'pending';
      if (status == 'pending') {
        map['id'] = key is int ? key : int.tryParse(key.toString());
        ops.add(map);
      }
    }
    ops.sort((a, b) {
      final aCreated = a['created_at'] as String? ?? '';
      final bCreated = b['created_at'] as String? ?? '';
      return aCreated.compareTo(bCreated);
    });
    return ops;
  }

  Future<int> insertPendingOperation({
    required String operationType,
    required String entityType,
    String? entityId,
    String? payloadJson,
  }) async {
    final box = await _box('pending_operations');
    final meta = await _box('meta');
    final nextId = (meta.get('next_pending_op_id') as int?) ?? 1;
    await meta.put('next_pending_op_id', nextId + 1);

    await box.put(nextId, {
      'id': nextId,
      'operation_type': operationType,
      'entity_type': entityType,
      'entity_id': entityId,
      'payload_json': payloadJson,
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
      'status': 'pending',
      'last_error': null,
    });
    return nextId;
  }

  Future<void> markOperationCompleted(int id) async {
    final box = await _box('pending_operations');
    final data = box.get(id);
    if (data != null) {
      final map = _cast(data);
      map['status'] = 'completed';
      await box.put(id, map);
    }
  }

  Future<void> markOperationFailed(int id, String error, {bool giveUp = true}) async {
    final box = await _box('pending_operations');
    final data = box.get(id);
    if (data != null) {
      final map = _cast(data);
      map['status'] = giveUp ? 'failed' : 'pending';
      map['last_error'] = error;
      map['retry_count'] = ((map['retry_count'] as int?) ?? 0) + 1;
      await box.put(id, map);
    }
  }

  Future<void> clearCompletedOperations() async {
    final box = await _box('pending_operations');
    final keysToDelete = <dynamic>[];
    for (final key in box.keys) {
      final map = _cast(box.get(key));
      if (map['status'] == 'completed') {
        keysToDelete.add(key);
      }
    }
    await box.deleteAll(keysToDelete);
  }

  Future<int> getPendingOperationCount() async {
    final box = await _box('pending_operations');
    int count = 0;
    for (final key in box.keys) {
      final map = _cast(box.get(key));
      if (map['status'] == 'pending') count++;
    }
    return count;
  }


  Future<List<EmailAccount>> getEmailAccounts() async {
    final box = await _box('email_accounts');
    return box.values.map((v) => EmailAccount.fromMap(_cast(v))).toList();
  }

  Future<void> insertEmailAccount(EmailAccount account, {String? credentialKey}) async {
    final box = await _box('email_accounts');
    await box.put(account.id, {
      ...account.toMap(),
      'credential_key': credentialKey ?? 'email_${account.id}',
    });
  }

  Future<String?> getEmailAccountCredentialKey(String id) async {
    final box = await _box('email_accounts');
    final data = box.get(id);
    if (data == null) return null;
    return _cast(data)['credential_key'] as String?;
  }

  Future<void> updateEmailAccount(EmailAccount account) async {
    final box = await _box('email_accounts');
    final existing = box.get(account.id);
    final credentialKey =
        existing == null ? null : _cast(existing)['credential_key'] as String?;
    await box.put(account.id, {
      ...account.toMap(),
      'credential_key': credentialKey ?? 'email_${account.id}',
    });
  }

  Future<void> deleteEmailAccount(String id) async {
    final box = await _box('email_accounts');
    await box.delete(id);
  }

  Future<List<EmailFolder>> getEmailFolders(String accountId) async {
    final box = await _box('email_folders');
    return box.values
        .map((v) => EmailFolder.fromMap(_cast(v)))
        .where((f) => f.accountId == accountId)
        .toList();
  }

  Future<void> insertEmailFolder(EmailFolder folder) async {
    final box = await _box('email_folders');
    await box.put(folder.id, folder.toMap());
  }

  Future<void> updateEmailFolder(EmailFolder folder) async {
    final box = await _box('email_folders');
    await box.put(folder.id, folder.toMap());
  }

  Future<List<Email>> getCachedEmails({
    required String accountId,
    required String folderId,
    int limit = 50,
    int offset = 0,
  }) async {
    final box = await _box('cached_emails');
    final emails = box.values
        .map((v) => Email.fromMap(_cast(v)))
        .where((e) => e.accountId == accountId && e.folderId == folderId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (offset >= emails.length) return [];
    final end = (offset + limit).clamp(0, emails.length);
    return emails.sublist(offset, end);
  }

  Future<Email?> getCachedEmail(String id) async {
    final box = await _box('cached_emails');
    final data = box.get(id);
    if (data == null) return null;
    return Email.fromMap(_cast(data));
  }

  Future<void> insertCachedEmail(Email email) async {
    final box = await _box('cached_emails');
    await box.put(email.id, email.toMap());
  }

  Future<void> updateCachedEmail(Email email) async {
    final box = await _box('cached_emails');
    await box.put(email.id, email.toMap());
  }

  Future<void> deleteCachedEmail(String id) async {
    final box = await _box('cached_emails');
    await box.delete(id);
  }


  Future<List<VbbLocation>> getCachedVbbLocations(String query) async {
    final box = await _box('vbb_location_cache');
    final data = box.get(query.toLowerCase());
    if (data == null) return [];
    final list = data as List;
    return list.map((v) => VbbLocation.fromMap(_cast(v))).toList();
  }

  Future<void> cacheVbbLocations(String query, List<VbbLocation> locations) async {
    final box = await _box('vbb_location_cache');
    await box.put(query.toLowerCase(), locations.map((l) => l.toMap()).toList());
  }

  Future<List<VbbJourney>> getCachedVbbRoutes(String cacheKey) async => [];
  Future<void> cacheVbbRoutes(String cacheKey, List<VbbJourney> journeys) async {}

  Future<List<VbbKnownLocation>> getVbbKnownLocations() async {
    final box = await _box('vbb_known_locations');
    return box.values.map((v) => VbbKnownLocation.fromMap(_cast(v))).toList();
  }

  Future<void> insertVbbKnownLocation(VbbKnownLocation location) async {
    final box = await _box('vbb_known_locations');
    await box.put(location.id, location.toMap());
  }

  Future<void> deleteVbbKnownLocation(String id) async {
    final box = await _box('vbb_known_locations');
    await box.delete(id);
  }

  Future<List<VbbFavoriteRoute>> getVbbFavoriteRoutes() async {
    final box = await _box('vbb_favorite_routes');
    return box.values.map((v) => VbbFavoriteRoute.fromMap(_cast(v))).toList();
  }

  Future<void> insertVbbFavoriteRoute(VbbFavoriteRoute route) async {
    final box = await _box('vbb_favorite_routes');
    await box.put(route.id, route.toMap());
  }

  Future<void> deleteVbbFavoriteRoute(String id) async {
    final box = await _box('vbb_favorite_routes');
    await box.delete(id);
  }


  Future<List<VbbTicket>> getVbbTickets() async {
    final box = await _box('vbb_tickets');
    return box.values.map((v) => VbbTicket.fromMap(_cast(v))).toList();
  }

  Future<void> insertVbbTicket(VbbTicket ticket) async {
    final box = await _box('vbb_tickets');
    await box.put(ticket.id, ticket.toMap());
  }

  Future<void> updateVbbTicket(VbbTicket ticket) async {
    final box = await _box('vbb_tickets');
    await box.put(ticket.id, ticket.toMap());
  }

  Future<void> deleteVbbTicket(String id) async {
    final box = await _box('vbb_tickets');
    await box.delete(id);
  }

  Future<void> clearOldVbbCache() async {
    final box = await _box('vbb_location_cache');
    await box.clear();
  }


  Future<List<GoogleCalendar>> getGoogleCalendars() async {
    final box = await _box('google_calendars');
    return box.values.map((v) => GoogleCalendar.fromMap(_cast(v))).toList();
  }

  Future<void> upsertGoogleCalendar(GoogleCalendar calendar) async {
    final box = await _box('google_calendars');
    await box.put(calendar.id, calendar.toMap());
  }

  Future<GoogleEvent?> getGoogleEvent(String id) async {
    final box = await _box('google_events');
    final data = box.get(id);
    if (data == null) return null;
    return GoogleEvent.fromMap(_cast(data));
  }

  Future<List<GoogleEvent>> getGoogleEvents({
    required String calendarId,
    DateTime? from,
    DateTime? to,
  }) async {
    final box = await _box('google_events');
    var events = box.values
        .map((v) => GoogleEvent.fromMap(_cast(v)))
        .where((e) => e.calendarId == calendarId);

    if (from != null) {
      events = events.where((e) => e.end.isAfter(from));
    }
    if (to != null) {
      events = events.where((e) => e.start.isBefore(to));
    }

    return events.toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<List<GoogleEvent>> getAllGoogleEvents({DateTime? from, DateTime? to}) async {
    final box = await _box('google_events');
    var events = box.values.map((v) => GoogleEvent.fromMap(_cast(v)));

    if (from != null) {
      events = events.where((e) => e.end.isAfter(from));
    }
    if (to != null) {
      events = events.where((e) => e.start.isBefore(to));
    }

    return events.toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  Future<void> insertGoogleEvent(GoogleEvent event) async {
    final box = await _box('google_events');
    await box.put(event.id, event.toMap());
  }

  Future<void> updateGoogleEvent(GoogleEvent event) async {
    final box = await _box('google_events');
    await box.put(event.id, event.toMap());
  }

  Future<void> deleteGoogleEvent(String id) async {
    final box = await _box('google_events');
    await box.delete(id);
  }

  Future<void> saveSyncToken(String calendarId, String token) async {
    final box = await _box('sync_tokens');
    await box.put(calendarId, token);
  }

  Future<String?> getSyncToken(String calendarId) async {
    final box = await _box('sync_tokens');
    return box.get(calendarId) as String?;
  }


  Future<List<dynamic>> getTrainingSchedule({required bool isHoliday}) async {
    final box = await _box('training');
    final key = isHoliday ? 'schedule_holiday' : 'schedule_normal';
    final data = box.get(key);
    if (data == null) return [];
    return List.from(data);
  }

  Future<void> saveTrainingSchedule(List<dynamic> schedule, {required bool isHoliday}) async {
    final box = await _box('training');
    final key = isHoliday ? 'schedule_holiday' : 'schedule_normal';
    await box.put(key, schedule);
  }

  Future<List<dynamic>> getTrainingSessionsList() async {
    final box = await _box('training_sessions');
    return box.values.toList();
  }

  Future<void> logTrainingSession(dynamic session) async {
    final box = await _box('training_sessions');
    if (session is Map) {
      final id = session['id'] as String?;
      if (id != null) {
        await box.put(id, session);
        return;
      }
    }
    await box.add(session);
  }

  Future<void> deleteTrainingSession(String id) async {
    final box = await _box('training_sessions');
    await box.delete(id);
  }

  Future<List<dynamic>> getHealthLogsList() async {
    final box = await _box('health_logs');
    return box.values.toList();
  }

  Future<void> saveHealthLog(dynamic log) async {
    final box = await _box('health_logs');
    if (log is Map) {
      final id = log['id'] as String?;
      if (id != null) {
        await box.put(id, log);
        return;
      }
    }
    await box.add(log);
  }

  Future<List<dynamic>> getTrainingGoalsList() async {
    final box = await _box('training_goals');
    return box.values.toList();
  }

  Future<void> saveTrainingGoal(dynamic goal) async {
    final box = await _box('training_goals');
    if (goal is Map) {
      final id = goal['id'] as String?;
      if (id != null) {
        await box.put(id, goal);
        return;
      }
    }
    await box.add(goal);
  }

  Future<void> deleteTrainingGoal(String id) async {
    final box = await _box('training_goals');
    await box.delete(id);
  }

  Future<bool> getTrainingHolidayMode() async {
    final box = await _box('training');
    return box.get('holiday_mode') as bool? ?? false;
  }

  Future<void> setTrainingHolidayMode(bool isHoliday) async {
    final box = await _box('training');
    await box.put('holiday_mode', isHoliday);
  }


  // --- Daily / weekly reviews (Hive parity with native sqflite) ---

  Future<List<Map<String, dynamic>>> getDailyReviews() async {
    final box = await _box('daily_reviews');
    final entries = box.values.map((v) => _cast(v)).toList();
    entries.sort((a, b) =>
        ((b['date'] as String?) ?? '').compareTo((a['date'] as String?) ?? ''));
    return entries;
  }

  Future<void> insertDailyReview(Map<String, dynamic> review) async {
    final box = await _box('daily_reviews');
    final id = review['id'] as String?;
    if (id != null) await box.put(id, review);
  }

  Future<void> deleteDailyReview(String id) async {
    final box = await _box('daily_reviews');
    await box.delete(id);
  }

  Future<List<Map<String, dynamic>>> getWeeklyReviews() async {
    final box = await _box('weekly_reviews');
    final entries = box.values.map((v) => _cast(v)).toList();
    entries.sort((a, b) => ((b['week_start'] as String?) ?? '')
        .compareTo((a['week_start'] as String?) ?? ''));
    return entries;
  }

  Future<void> insertWeeklyReview(Map<String, dynamic> review) async {
    final box = await _box('weekly_reviews');
    final id = review['id'] as String?;
    if (id != null) await box.put(id, review);
  }

  Future<void> deleteWeeklyReview(String id) async {
    final box = await _box('weekly_reviews');
    await box.delete(id);
  }


  // --- Pomodoro sessions & stats ---

  Future<void> insertPomodoroSession(Map<String, dynamic> session) async {
    final box = await _box('pomodoro_sessions');
    final id = session['id'] as String?;
    if (id != null) await box.put(id, session);
  }

  Future<List<Map<String, dynamic>>> getPomodoroSessions({String? since}) async {
    final box = await _box('pomodoro_sessions');
    var sessions = box.values.map((v) => _cast(v)).toList();
    if (since != null) {
      sessions = sessions
          .where((s) => ((s['started_at'] as String?) ?? '').compareTo(since) >= 0)
          .toList();
    }
    sessions.sort((a, b) => ((b['started_at'] as String?) ?? '')
        .compareTo((a['started_at'] as String?) ?? ''));
    return sessions;
  }

  Future<int> getPomodoroCountForTask(String taskId) async {
    final box = await _box('pomodoro_sessions');
    return box.values
        .map((v) => _cast(v))
        .where((s) => s['task_id'] == taskId && _isCompleted(s['completed']))
        .length;
  }

  bool _isCompleted(dynamic v) => v == 1 || v == true;

  Future<Map<String, dynamic>> getPomodoroStats({required String since}) async {
    final sessions = (await getPomodoroSessions(since: since))
        .where((s) => _isCompleted(s['completed']))
        .toList();

    var totalMinutes = 0;
    final byTaskAgg = <String?, Map<String, int>>{};
    final byDayAgg = <String, int>{};
    for (final s in sessions) {
      final minutes = (s['duration_minutes'] as int?) ?? 0;
      totalMinutes += minutes;
      final taskId = s['task_id'] as String?;
      final agg = byTaskAgg.putIfAbsent(taskId, () => {'sessions': 0, 'minutes': 0});
      agg['sessions'] = agg['sessions']! + 1;
      agg['minutes'] = agg['minutes']! + minutes;
      final day = ((s['started_at'] as String?) ?? '').padRight(10).substring(0, 10);
      byDayAgg[day] = (byDayAgg[day] ?? 0) + 1;
    }

    final byTask = byTaskAgg.entries
        .map((e) => {
              'task_id': e.key,
              'sessions': e.value['sessions'],
              'minutes': e.value['minutes'],
            })
        .toList()
      ..sort((a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int));

    final byDay = (byDayAgg.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => {'day': e.key, 'count': e.value})
        .toList();

    return {
      'total_sessions': sessions.length,
      'total_minutes': totalMinutes,
      'by_task': byTask,
      'by_day': byDay,
    };
  }

  Future<Map<String, dynamic>> getWeeklyStats() async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr =
        DateTime(weekStart.year, weekStart.month, weekStart.day).toIso8601String();

    final tasks = await getTasks();
    final tasksCompleted = tasks
        .where((t) =>
            t.completed && t.updatedAt.toIso8601String().compareTo(weekStartStr) >= 0)
        .length;
    final tasksTotal = tasks
        .where((t) => t.createdAt.toIso8601String().compareTo(weekStartStr) >= 0)
        .length;

    final sessions = (await getPomodoroSessions(since: weekStartStr))
        .where((s) => _isCompleted(s['completed']))
        .toList();
    var pomodoroMinutes = 0;
    final byDayAgg = <String, int>{};
    for (final s in sessions) {
      pomodoroMinutes += (s['duration_minutes'] as int?) ?? 0;
      final day = ((s['started_at'] as String?) ?? '').padRight(10).substring(0, 10);
      byDayAgg[day] = (byDayAgg[day] ?? 0) + 1;
    }
    final pomodoroByDay = (byDayAgg.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => {'day': e.key, 'count': e.value})
        .toList();

    return {
      'tasks_completed': tasksCompleted,
      'tasks_total': tasksTotal,
      'pomodoro_sessions': sessions.length,
      'pomodoro_minutes': pomodoroMinutes,
      'pomodoro_by_day': pomodoroByDay,
    };
  }

  Future<dynamic> get database async => throw Exception('Database not available on web - using Hive/IndexedDB');
}
