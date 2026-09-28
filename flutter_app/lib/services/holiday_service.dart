// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import 'database_service.dart';

class HolidayService {
  static final HolidayService _instance = HolidayService._internal();
  factory HolidayService() => _instance;
  HolidayService._internal();

  final Dio _dio = Dio();
  final DatabaseService _db = DatabaseService();

  static const bundeslandCodes = {
    'Baden-Württemberg': 'BW',
    'Bayern': 'BY',
    'Berlin': 'BE',
    'Brandenburg': 'BB',
    'Bremen': 'HB',
    'Hamburg': 'HH',
    'Hessen': 'HE',
    'Mecklenburg-Vorpommern': 'MV',
    'Niedersachsen': 'NI',
    'Nordrhein-Westfalen': 'NW',
    'Rheinland-Pfalz': 'RP',
    'Saarland': 'SL',
    'Sachsen': 'SN',
    'Sachsen-Anhalt': 'ST',
    'Schleswig-Holstein': 'SH',
    'Thüringen': 'TH',
  };

  Future<String?> getUserBundesland() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_bundesland');
  }

  Future<int?> getGraduationYear() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('graduation_year');
  }

  String? getBundeslandCode(String bundesland) {
    return bundeslandCodes[bundesland];
  }

  Future<List<Event>> importHolidays({int? year, bool force = false}) async {
    if (kDebugMode) print('HolidayService: Starting holiday import (force: $force)');

    final bundesland = await getUserBundesland();
    if (bundesland == null) {
      if (kDebugMode) print('HolidayService: No Bundesland selected');
      return [];
    }

    final code = getBundeslandCode(bundesland);
    if (code == null) {
      if (kDebugMode) print('HolidayService: Unknown Bundesland code for: $bundesland');
      return [];
    }

    final graduationYear = await getGraduationYear() ?? (DateTime.now().year + 3);

    final graduationCutoff = DateTime(graduationYear, 9, 1);
    if (kDebugMode) print('HolidayService: Importing holidays for $bundesland ($code) until graduation year $graduationYear (cutoff: $graduationCutoff)');

    final currentYear = DateTime.now().year;
    final events = <Event>[];

    for (int targetYear = currentYear; targetYear <= graduationYear; targetYear++) {
      if (kDebugMode) print('HolidayService: Fetching holidays for year $targetYear...');

      final publicHolidays = await _fetchPublicHolidays(code, targetYear);
      events.addAll(publicHolidays);
      if (kDebugMode) print('HolidayService: Got ${publicHolidays.length} public holidays for $targetYear');

      if (targetYear == currentYear) {
        final prevYearSchoolHolidays = await _fetchSchoolHolidays(code, targetYear - 1);
        events.addAll(prevYearSchoolHolidays);
        if (kDebugMode) print('HolidayService: Got ${prevYearSchoolHolidays.length} school holidays for ${targetYear - 1} (may span into $targetYear)');
      }

      final schoolHolidays = await _fetchSchoolHolidays(code, targetYear);
      events.addAll(schoolHolidays);
      if (kDebugMode) print('HolidayService: Got ${schoolHolidays.length} school holidays for $targetYear');
    }

    final filteredEvents = events.where((e) => e.startTime.isBefore(graduationCutoff)).toList();
    if (kDebugMode) print('HolidayService: Filtered from ${events.length} to ${filteredEvents.length} events (removed post-graduation holidays)');

    final savedCount = await _saveHolidaysToDatabase(filteredEvents);

    if (kDebugMode) {
      final db = await _db.database;
      final verifyResult = await db.rawQuery(
        'SELECT COUNT(*) as c FROM events WHERE category IN (?, ?)',
        ['holiday', 'vacation']
      );
      final dbCount = verifyResult.first['c'] as int? ?? 0;
      print('HolidayService: Import complete - fetched: ${events.length}, newly saved: $savedCount, total in DB: $dbCount');

      if (savedCount == 0 && events.isNotEmpty && dbCount == 0) {
        print('HolidayService: WARNING - No holidays saved to database! Check for errors above.');
      }
    }

    return filteredEvents;
  }

  Future<List<Event>> _fetchPublicHolidays(String bundeslandCode, int year) async {
    try {
      if (kDebugMode) print('HolidayService: Fetching public holidays for $bundeslandCode/$year');

      final response = await _dio.get(
        'https://feiertage-api.de/api/',
        queryParameters: {
          'jahr': year,
          'nur_land': bundeslandCode,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        if (kDebugMode) print('HolidayService: Public holidays API failed - status: ${response.statusCode}');
        return await _fetchPublicHolidaysNager(bundeslandCode, year);
      }

      Map<String, dynamic> data;
      if (response.data is Map) {
        data = Map<String, dynamic>.from(response.data as Map);
      } else if (response.data is String) {
        data = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else {
        if (kDebugMode) print('HolidayService: Unexpected response type for public holidays');
        return await _fetchPublicHolidaysNager(bundeslandCode, year);
      }

      final events = <Event>[];
      final now = DateTime.now();

      for (final entry in data.entries) {
        final holidayName = entry.key;
        final holidayData = entry.value as Map<String, dynamic>;
        final dateStr = holidayData['datum'] as String?;

        if (dateStr == null) continue;

        final date = DateTime.parse(dateStr);
        final id = 'holiday_${bundeslandCode}_${dateStr}_${holidayName.hashCode}';

        events.add(Event(
          id: id,
          title: holidayName,
          description: 'Gesetzlicher Feiertag',
          startTime: DateTime(date.year, date.month, date.day, 0, 0),
          endTime: DateTime(date.year, date.month, date.day, 23, 59),
          allDay: true,
          category: 'holiday',
          color: '#EF4444',
          createdAt: now,
          updatedAt: now,
        ));
      }

      if (kDebugMode) print('HolidayService: Got ${events.length} public holidays');
      return events;
    } catch (e) {
      if (kDebugMode) print('HolidayService: Error fetching public holidays: $e - trying fallback');
      return _fetchPublicHolidaysNager(bundeslandCode, year);
    }
  }

  Future<List<Event>> _fetchPublicHolidaysNager(String bundeslandCode, int year) async {
    try {
      final response = await _dio.get(
        'https://date.nager.at/api/v3/publicholidays/$year/DE',
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        return [];
      }

      final List<dynamic> data = response.data;
      final events = <Event>[];
      final now = DateTime.now();

      for (final holiday in data) {
        final counties = holiday['counties'] as List<dynamic>?;
        final isNational = counties == null || counties.isEmpty;
        final appliesToBundesland = isNational ||
            counties.any((c) => c.toString().contains(bundeslandCode));

        if (!appliesToBundesland) continue;

        final dateStr = holiday['date'] as String?;
        final name = holiday['localName'] as String? ?? holiday['name'] as String?;

        if (dateStr == null || name == null) continue;

        final date = DateTime.parse(dateStr);
        final id = 'holiday_nager_${bundeslandCode}_${dateStr}_${name.hashCode}';

        events.add(Event(
          id: id,
          title: name,
          description: 'Gesetzlicher Feiertag',
          startTime: DateTime(date.year, date.month, date.day, 0, 0),
          endTime: DateTime(date.year, date.month, date.day, 23, 59),
          allDay: true,
          category: 'holiday',
          color: '#EF4444',
          createdAt: now,
          updatedAt: now,
        ));
      }

      return events;
    } catch (e) {
      return [];
    }
  }

  Future<List<Event>> _fetchSchoolHolidays(String bundeslandCode, int year) async {

    final events = await _fetchSchoolHolidaysFromSchulferienApi(bundeslandCode, year);
    if (events.isNotEmpty) {
      return events;
    }

    if (kDebugMode) print('HolidayService: Primary API returned no data, trying fallback...');
    return _fetchSchoolHolidaysFromFerienApi(bundeslandCode, year);
  }

  Future<List<Event>> _fetchSchoolHolidaysFromSchulferienApi(String bundeslandCode, int year) async {
    try {
      if (kDebugMode) print('HolidayService: Fetching school holidays from schulferien-api.de for $bundeslandCode/$year');

      final response = await _dio.get(
        'https://schulferien-api.de/api/v1/$year/$bundeslandCode/',
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        if (kDebugMode) print('HolidayService: schulferien-api.de failed - status: ${response.statusCode}');
        return [];
      }

      List<dynamic> data;
      if (response.data is List) {
        data = response.data as List<dynamic>;
      } else if (response.data is String) {
        data = jsonDecode(response.data as String) as List<dynamic>;
      } else {
        if (kDebugMode) print('HolidayService: Unexpected response type: ${response.data.runtimeType}');
        return [];
      }

      if (kDebugMode) print('HolidayService: Got ${data.length} school holidays from schulferien-api.de');

      final events = <Event>[];
      final now = DateTime.now();

      for (final holiday in data) {
        try {

          final name = (holiday['name_cp'] ?? holiday['name']) as String?;
          final startStr = holiday['start'] as String?;
          final endStr = holiday['end'] as String?;

          if (name == null || startStr == null || endStr == null) {
            if (kDebugMode) print('HolidayService: Skipping holiday with missing data');
            continue;
          }

          final start = DateTime.parse(startStr);
          final end = DateTime.parse(endStr);
          final id = 'vacation_${bundeslandCode}_${startStr}_${name.hashCode}';

          events.add(Event(
            id: id,
            title: name,
            description: 'Schulferien',
            startTime: DateTime(start.year, start.month, start.day, 0, 0),
            endTime: DateTime(end.year, end.month, end.day, 23, 59),
            allDay: true,
            category: 'vacation',
            color: '#22C55E',
            createdAt: now,
            updatedAt: now,
          ));

          if (kDebugMode) print('HolidayService: Added vacation: $name ($startStr - $endStr)');
        } catch (e) {
          if (kDebugMode) print('HolidayService: Error parsing holiday entry: $e');
          continue;
        }
      }

      if (kDebugMode) print('HolidayService: Successfully created ${events.length} vacation events');
      return events;
    } catch (e) {
      if (kDebugMode) print('HolidayService: Error fetching from schulferien-api.de: $e');
      return [];
    }
  }

  Future<List<Event>> _fetchSchoolHolidaysFromFerienApi(String bundeslandCode, int year) async {
    try {
      if (kDebugMode) print('HolidayService: Fetching school holidays from ferien-api.de for $bundeslandCode/$year');

      final response = await _dio.get(
        'https://ferien-api.de/api/v1/holidays/$bundeslandCode/$year',
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        if (kDebugMode) print('HolidayService: ferien-api.de failed - status: ${response.statusCode}');
        return [];
      }

      List<dynamic> data;
      if (response.data is List) {
        data = response.data as List<dynamic>;
      } else if (response.data is String) {
        data = jsonDecode(response.data as String) as List<dynamic>;
      } else {
        if (kDebugMode) print('HolidayService: Unexpected response type: ${response.data.runtimeType}');
        return [];
      }

      if (kDebugMode) print('HolidayService: Got ${data.length} school holidays from ferien-api.de');

      final events = <Event>[];
      final now = DateTime.now();

      for (final holiday in data) {
        try {
          final name = holiday['name'] as String?;
          final startStr = holiday['start'] as String?;
          final endStr = holiday['end'] as String?;

          if (name == null || startStr == null || endStr == null) {
            continue;
          }

          final start = DateTime.parse(startStr);
          final end = DateTime.parse(endStr);
          final id = 'vacation_${bundeslandCode}_${startStr}_${name.hashCode}';

          final translatedName = _translateVacationName(name);

          events.add(Event(
            id: id,
            title: translatedName,
            description: 'Schulferien',
            startTime: DateTime(start.year, start.month, start.day, 0, 0),
            endTime: DateTime(end.year, end.month, end.day, 23, 59),
            allDay: true,
            category: 'vacation',
            color: '#22C55E',
            createdAt: now,
            updatedAt: now,
          ));
        } catch (e) {
          continue;
        }
      }

      return events;
    } catch (e) {
      if (kDebugMode) print('HolidayService: Error fetching from ferien-api.de: $e');
      return [];
    }
  }

  String _translateVacationName(String name) {
    final translations = {
      'winterferien': 'Winterferien',
      'osterferien': 'Osterferien',
      'pfingstferien': 'Pfingstferien',
      'sommerferien': 'Sommerferien',
      'herbstferien': 'Herbstferien',
      'weihnachtsferien': 'Weihnachtsferien',
      'frühjahrsferien': 'Frühjahrsferien',
      'himmelfahrt': 'Himmelfahrtsferien',
      'fronleichnam': 'Fronleichnam',
    };

    final lowerName = name.toLowerCase();
    for (final entry in translations.entries) {
      if (lowerName.contains(entry.key)) {
        return entry.value;
      }
    }

    final firstWord = name.split(' ').first;
    if (firstWord.isNotEmpty) {
      return firstWord[0].toUpperCase() + firstWord.substring(1).toLowerCase();
    }
    return name;
  }

  Future<int> _saveHolidaysToDatabase(List<Event> events) async {
    final db = await _db.database;
    int savedCount = 0;
    int skippedCount = 0;
    int errorCount = 0;

    for (final event in events) {
      try {
        final existing = await db.query(
          'events',
          where: 'id = ?',
          whereArgs: [event.id],
        );

        if (existing.isEmpty) {
          await db.insert('events', event.toMap());
          savedCount++;
          if (kDebugMode) print('HolidayService: Saved event: ${event.title}');
        } else {
          skippedCount++;
        }
      } catch (e) {
        errorCount++;
        if (kDebugMode) print('HolidayService: ERROR saving event "${event.title}": $e');
        if (kDebugMode) print('HolidayService: Event data: ${event.toMap()}');
      }
    }

    if (kDebugMode) print('HolidayService: Database save complete - saved: $savedCount, skipped (duplicates): $skippedCount, errors: $errorCount');
    return savedCount;
  }

  Future<void> clearHolidays() async {
    final db = await _db.database;
    await db.delete(
      'events',
      where: 'category IN (?, ?)',
      whereArgs: ['holiday', 'vacation'],
    );
  }

  Future<List<Event>> refreshHolidays() async {
    await clearHolidays();
    return importHolidays();
  }

  Future<bool> hasImportedHolidays() async {
    final db = await _db.database;
    final year = DateTime.now().year;
    final startOfYear = DateTime(year, 1, 1);
    final endOfYear = DateTime(year + 1, 6, 30);

    final prevYearStart = DateTime(year - 1, 1, 1);

    final holidays = await db.query(
      'events',
      where: 'category = ? AND start_time >= ? AND start_time <= ?',
      whereArgs: ['holiday', startOfYear.toIso8601String(), endOfYear.toIso8601String()],
      limit: 1,
    );

    final vacations = await db.query(
      'events',
      where: 'category = ? AND start_time >= ? AND start_time <= ?',
      whereArgs: ['vacation', prevYearStart.toIso8601String(), endOfYear.toIso8601String()],
      limit: 1,
    );

    final hasHolidays = holidays.isNotEmpty;
    final hasVacations = vacations.isNotEmpty;

    if (kDebugMode) print('HolidayService: hasImportedHolidays - holidays: $hasHolidays, vacations: $hasVacations');

    return hasHolidays && hasVacations;
  }

  Future<Map<String, int>> getHolidayCounts() async {
    final db = await _db.database;

    final holidays = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE category = ?',
      ['holiday'],
    );

    final vacations = await db.rawQuery(
      'SELECT COUNT(*) as count FROM events WHERE category = ?',
      ['vacation'],
    );

    return {
      'holidays': holidays.first['count'] as int? ?? 0,
      'vacations': vacations.first['count'] as int? ?? 0,
    };
  }

  Future<List<Event>> getHolidays() async {
    final db = await _db.database;
    final results = await db.query(
      'events',
      where: 'category IN (?, ?)',
      whereArgs: ['holiday', 'vacation'],
      orderBy: 'start_time ASC',
    );
    return results.map((m) => Event.fromMap(m)).toList();
  }
}
