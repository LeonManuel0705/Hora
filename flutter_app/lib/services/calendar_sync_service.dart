// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'database_service.dart';
import 'encryption_service.dart';
import 'connectivity_service.dart';
import 'offline_queue.dart';

class CalendarSyncService {
  static final CalendarSyncService _instance = CalendarSyncService._internal();
  factory CalendarSyncService() => _instance;
  CalendarSyncService._internal();

  static const String _calendarApiBase = 'https://www.googleapis.com/calendar/v3';

  final DatabaseService _db = DatabaseService();
  final EncryptionService _encryption = EncryptionService();
  final ConnectivityService _connectivity = ConnectivityService();
  final OfflineQueue _offlineQueue = OfflineQueue();
  final Uuid _uuid = const Uuid();

  String? _accessToken;
  DateTime? _tokenExpiry;

  Future<bool> hasValidCredentials() async {
    final tokens = await _encryption.getGoogleTokens('default');
    return tokens != null && tokens['access_token'] != null;
  }

  Future<String?> _getValidAccessToken() async {
    if (_accessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    final tokens = await _encryption.getGoogleTokens('default');
    if (tokens == null) return null;

    _accessToken = tokens['access_token'] as String?;

    final expiryStr = tokens['expires_at'] as String?;
    if (expiryStr != null) {
      _tokenExpiry = DateTime.tryParse(expiryStr);
    }

    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!)) {
      final refreshToken = tokens['refresh_token'] as String?;
      if (refreshToken != null) {
        final newAccessToken = await _refreshAccessToken(refreshToken);
        if (newAccessToken != null) {
          _accessToken = newAccessToken;
        } else {
          _accessToken = null;
          return null;
        }
      } else {
        _accessToken = null;
        return null;
      }
    }

    return _accessToken;
  }

  Future<String?> _refreshAccessToken(String refreshToken) async {


    _accessToken = null;
    _tokenExpiry = null;
    return null;
  }

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) async {
    await _encryption.storeGoogleTokens(
      email: 'default',
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiry,
    );
    _accessToken = accessToken;
    _tokenExpiry = expiry;
  }

  Future<void> clearTokens() async {
    await _encryption.deleteGoogleTokens('default');
    await _encryption.deleteCredential('google_tokens');
    _accessToken = null;
    _tokenExpiry = null;
  }

  Future<List<GoogleCalendar>> getCalendars() async {
    final accessToken = await _getValidAccessToken();
    if (accessToken == null) return [];

    if (!_connectivity.isOnline.value) {
      return await _db.getGoogleCalendars();
    }

    try {
      final response = await http.get(
        Uri.parse('$_calendarApiBase/users/me/calendarList'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = data['items'] as List;

        final calendars = items.map((item) {
          return GoogleCalendar(
            id: item['id'] as String,
            summary: item['summary'] as String? ?? 'Calendar',
            description: item['description'] as String?,
            backgroundColor: item['backgroundColor'] as String?,
            isPrimary: item['primary'] == true,
            isSelected: true,
          );
        }).toList();

        for (final calendar in calendars) {
          await _db.upsertGoogleCalendar(calendar);
        }

        return calendars;
      }
    } catch (_) {
    }

    return await _db.getGoogleCalendars();
  }

  Future<SyncResult> syncCalendar(String calendarId, {String? syncToken}) async {
    final accessToken = await _getValidAccessToken();
    if (accessToken == null) {
      return SyncResult(success: false, error: 'Nicht angemeldet');
    }

    if (!_connectivity.isOnline.value) {
      return SyncResult(success: false, error: 'Keine Internetverbindung');
    }

    try {
      final baseParams = <String, String>{
        'singleEvents': 'true',
        'maxResults': '250',
      };

      if (syncToken != null) {
        baseParams['syncToken'] = syncToken;
      } else {
        baseParams['orderBy'] = 'startTime';
        baseParams['timeMin'] = DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
        baseParams['timeMax'] = DateTime.now().add(const Duration(days: 365)).toUtc().toIso8601String();
      }

      int added = 0;
      int updated = 0;
      int deleted = 0;
      String? nextSyncToken;
      String? pageToken;

      do {
        final params = Map<String, String>.from(baseParams);
        if (pageToken != null) {
          params['pageToken'] = pageToken;
        }

        final uri = Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events')
            .replace(queryParameters: params);

        final response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $accessToken'},
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final items = data['items'] as List? ?? [];

          for (final item in items) {
            final eventId = item['id'] as String;
            final status = item['status'] as String?;

            if (status == 'cancelled') {
              await _db.deleteGoogleEvent(eventId);
              deleted++;
              continue;
            }

            final event = GoogleEvent.fromApiResponse(item as Map<String, dynamic>, calendarId);
            final existing = await _db.getGoogleEvent(eventId);

            if (existing != null) {
              await _db.updateGoogleEvent(event);
              updated++;
            } else {
              await _db.insertGoogleEvent(event);
              added++;
            }
          }

          nextSyncToken = data['nextSyncToken'] as String?;
          pageToken = data['nextPageToken'] as String?;
        } else if (response.statusCode == 410 ||
            (response.statusCode == 400 && syncToken != null)) {
          return await syncCalendar(calendarId, syncToken: null);
        } else {
          return SyncResult(success: false, error: 'Unbekannter Fehler');
        }
      } while (pageToken != null);

      if (nextSyncToken != null) {
        await _db.saveSyncToken(calendarId, nextSyncToken);
      }

      return SyncResult(
        success: true,
        added: added,
        updated: updated,
        deleted: deleted,
        nextSyncToken: nextSyncToken,
      );
    } catch (e) {
      debugPrint('Calendar sync error: $e');
      return SyncResult(success: false, error: 'Kalender-Sync fehlgeschlagen');
    }
  }

  Future<List<GoogleEvent>> getEvents(String calendarId, {DateTime? from, DateTime? to}) async {
    return await _db.getGoogleEvents(
      calendarId: calendarId,
      from: from,
      to: to,
    );
  }

  Future<List<GoogleEvent>> getAllEvents({DateTime? from, DateTime? to}) async {
    return await _db.getAllGoogleEvents(from: from, to: to);
  }

  Future<GoogleEvent?> createEvent({
    required String calendarId,
    required String summary,
    required DateTime start,
    required DateTime end,
    bool isAllDay = false,
    String? description,
    String? location,
  }) async {
    final event = GoogleEvent(
      id: _uuid.v4(),
      calendarId: calendarId,
      summary: summary,
      description: description,
      location: location,
      start: start,
      end: end,
      isAllDay: isAllDay,
      isSynced: false,
    );

    await _db.insertGoogleEvent(event);

    final queuePayload = {
      ...event.toApiMap(),
      'calendar_id': calendarId,
    };

    if (!_connectivity.isOnline.value) {
      await _offlineQueue.enqueue(
        operationType: OperationType.create,
        entityType: EntityType.googleEvent,
        entityId: event.id,
        payload: queuePayload,
      );
      return event;
    }

    final accessToken = await _getValidAccessToken();
    if (accessToken == null) {
      await _offlineQueue.enqueue(
        operationType: OperationType.create,
        entityType: EntityType.googleEvent,
        entityId: event.id,
        payload: queuePayload,
      );
      return event;
    }

    try {
      final response = await http.post(
        Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(event.toApiMap()),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final syncedEvent = GoogleEvent.fromApiResponse(data, calendarId).copyWith(isSynced: true);
        await _db.updateGoogleEvent(syncedEvent);
        return syncedEvent;
      }
    } catch (e) {
      await _offlineQueue.enqueue(
        operationType: OperationType.create,
        entityType: EntityType.googleEvent,
        entityId: event.id,
        payload: queuePayload,
      );
    }

    return event;
  }

  Future<bool> updateEvent(GoogleEvent event) async {
    await _db.updateGoogleEvent(event.copyWith(isSynced: false));

    final queuePayload = {
      ...event.toApiMap(),
      'calendar_id': event.calendarId,
    };

    if (!_connectivity.isOnline.value) {
      await _offlineQueue.enqueue(
        operationType: OperationType.update,
        entityType: EntityType.googleEvent,
        entityId: event.id,
        payload: queuePayload,
      );
      return true;
    }

    final accessToken = await _getValidAccessToken();
    if (accessToken == null) {
      await _offlineQueue.enqueue(
        operationType: OperationType.update,
        entityType: EntityType.googleEvent,
        entityId: event.id,
        payload: queuePayload,
      );
      return true;
    }

    try {
      final response = await http.put(
        Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(event.calendarId)}/events/${Uri.encodeComponent(event.id)}'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(event.toApiMap()),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        await _db.updateGoogleEvent(event.copyWith(isSynced: true));
        return true;
      }
    } catch (e) {
      await _offlineQueue.enqueue(
        operationType: OperationType.update,
        entityType: EntityType.googleEvent,
        entityId: event.id,
        payload: queuePayload,
      );
    }

    return false;
  }

  Future<bool> deleteEvent(String eventId, String calendarId) async {
    await _db.deleteGoogleEvent(eventId);

    if (!_connectivity.isOnline.value) {
      await _offlineQueue.enqueue(
        operationType: OperationType.delete,
        entityType: EntityType.googleEvent,
        entityId: eventId,
        payload: {'calendar_id': calendarId},
      );
      return true;
    }

    final accessToken = await _getValidAccessToken();
    if (accessToken == null) {
      await _offlineQueue.enqueue(
        operationType: OperationType.delete,
        entityType: EntityType.googleEvent,
        entityId: eventId,
        payload: {'calendar_id': calendarId},
      );
      return true;
    }

    try {
      final response = await http.delete(
        Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(eventId)}'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 20));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      await _offlineQueue.enqueue(
        operationType: OperationType.delete,
        entityType: EntityType.googleEvent,
        entityId: eventId,
        payload: {'calendar_id': calendarId},
      );
    }

    return false;
  }

  Future<Map<String, SyncResult>> syncAllCalendars() async {
    final results = <String, SyncResult>{};
    final calendars = await _db.getGoogleCalendars();

    for (final calendar in calendars.where((c) => c.isSelected)) {
      final syncToken = await _db.getSyncToken(calendar.id);
      final result = await syncCalendar(calendar.id, syncToken: syncToken);
      results[calendar.id] = result;
    }

    return results;
  }

  Future<void> processOfflineQueue() async {
    if (!_connectivity.isOnline.value) return;

    final accessToken = await _getValidAccessToken();
    if (accessToken == null) return;

    final operations = await _offlineQueue.getPendingOperations();
    final eventOps = operations.where((op) => op.entityType == EntityType.googleEvent);

    for (final op in eventOps) {
      bool success = false;

      switch (op.operationType) {
        case OperationType.create:
          if (op.payload != null && op.entityId != null) {
            final calendarId = op.payload!['calendar_id'] as String? ?? 'primary';
            try {
              final response = await http.post(
                Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events'),
                headers: {
                  'Authorization': 'Bearer $accessToken',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(op.payload),
              ).timeout(const Duration(seconds: 20));

              if (response.statusCode == 200) {
                final data = jsonDecode(response.body) as Map<String, dynamic>;
                final syncedEvent = GoogleEvent.fromApiResponse(data, calendarId).copyWith(isSynced: true);
                await _db.deleteGoogleEvent(op.entityId!);
                await _db.insertGoogleEvent(syncedEvent);
                success = true;
              }
            } catch (e) {
              if (kDebugMode) debugPrint('CalendarSync: create op failed: $e');
            }
          }
          break;

        case OperationType.update:
          if (op.payload != null && op.entityId != null) {
            final calendarId = op.payload!['calendar_id'] as String? ?? 'primary';
            try {
              final response = await http.put(
                Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(op.entityId!)}'),
                headers: {
                  'Authorization': 'Bearer $accessToken',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode(op.payload),
              ).timeout(const Duration(seconds: 20));

              if (response.statusCode == 200) {
                final existingEvent = await _db.getGoogleEvent(op.entityId!);
                if (existingEvent != null) {
                  await _db.updateGoogleEvent(existingEvent.copyWith(isSynced: true));
                }
                success = true;
              }
            } catch (e) {
              if (kDebugMode) debugPrint('CalendarSync: update op failed: $e');
            }
          }
          break;

        case OperationType.delete:
          final calendarId = op.payload?['calendar_id'] as String?;
          if (calendarId != null && op.entityId != null) {
            try {
              final response = await http.delete(
                Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(op.entityId!)}'),
                headers: {'Authorization': 'Bearer $accessToken'},
              ).timeout(const Duration(seconds: 20));
              success = response.statusCode == 204 || response.statusCode == 200 || response.statusCode == 410;
            } catch (e) {
              if (kDebugMode) debugPrint('CalendarSync: delete op failed: $e');
            }
          }
          break;
      }

      if (success && op.id != null) {
        await _db.markOperationCompleted(op.id!);
      }
    }
  }

  Future<void> initialize() async {
    _offlineQueue.registerProcessor(EntityType.googleEvent, _processGoogleEventOperation);

    _connectivity.onConnected(() async {
      await Future.delayed(const Duration(seconds: 2));
      try {
        await syncAllCalendars();
      } catch (_) {}
    });
  }

  Future<bool> _processGoogleEventOperation(PendingOperation op) async {
    final accessToken = await _getValidAccessToken();
    if (accessToken == null) return false;

    switch (op.operationType) {
      case OperationType.create:
        if (op.payload != null && op.entityId != null) {
          final calendarId = op.payload!['calendar_id'] as String? ?? 'primary';
          try {
            final response = await http.post(
              Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events'),
              headers: {
                'Authorization': 'Bearer $accessToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(op.payload),
            ).timeout(const Duration(seconds: 20));

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body) as Map<String, dynamic>;
              final syncedEvent = GoogleEvent.fromApiResponse(data, calendarId).copyWith(isSynced: true);
              await _db.deleteGoogleEvent(op.entityId!);
              await _db.insertGoogleEvent(syncedEvent);
              return true;
            }
          } catch (e) {
            return false;
          }
        }
        return false;

      case OperationType.update:
        if (op.payload != null && op.entityId != null) {
          final calendarId = op.payload!['calendar_id'] as String? ?? 'primary';
          try {
            final response = await http.put(
              Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(op.entityId!)}'),
              headers: {
                'Authorization': 'Bearer $accessToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(op.payload),
            ).timeout(const Duration(seconds: 20));

            if (response.statusCode == 200) {
              final existingEvent = await _db.getGoogleEvent(op.entityId!);
              if (existingEvent != null) {
                await _db.updateGoogleEvent(existingEvent.copyWith(isSynced: true));
              }
              return true;
            }
          } catch (e) {
            return false;
          }
        }
        return false;

      case OperationType.delete:
        final calendarId = op.payload?['calendar_id'] as String?;
        if (calendarId != null && op.entityId != null) {
          try {
            final response = await http.delete(
              Uri.parse('$_calendarApiBase/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(op.entityId!)}'),
              headers: {'Authorization': 'Bearer $accessToken'},
            ).timeout(const Duration(seconds: 20));
            return response.statusCode == 204 || response.statusCode == 200 || response.statusCode == 410;
          } catch (e) {
            return false;
          }
        }
        return false;
    }
  }
}

class GoogleCalendar {
  final String id;
  final String summary;
  final String? description;
  final String? backgroundColor;
  final bool isPrimary;
  final bool isSelected;

  GoogleCalendar({
    required this.id,
    required this.summary,
    this.description,
    this.backgroundColor,
    this.isPrimary = false,
    this.isSelected = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'summary': summary,
      'description': description,
      'background_color': backgroundColor,
      'is_primary': isPrimary ? 1 : 0,
      'is_selected': isSelected ? 1 : 0,
    };
  }

  factory GoogleCalendar.fromMap(Map<String, dynamic> map) {
    return GoogleCalendar(
      id: map['id'] as String,
      summary: map['summary'] as String,
      description: map['description'] as String?,
      backgroundColor: map['background_color'] as String?,
      isPrimary: (map['is_primary'] as int?) == 1,
      isSelected: (map['is_selected'] as int?) == 1,
    );
  }

  GoogleCalendar copyWith({
    String? id,
    String? summary,
    String? description,
    String? backgroundColor,
    bool? isPrimary,
    bool? isSelected,
  }) {
    return GoogleCalendar(
      id: id ?? this.id,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isPrimary: isPrimary ?? this.isPrimary,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class GoogleEvent {
  final String id;
  final String calendarId;
  final String summary;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String? recurringEventId;
  final bool isSynced;

  GoogleEvent({
    required this.id,
    required this.calendarId,
    required this.summary,
    this.description,
    this.location,
    required this.start,
    required this.end,
    this.isAllDay = false,
    this.recurringEventId,
    this.isSynced = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'calendar_id': calendarId,
      'summary': summary,
      'description': description,
      'location': location,
      'start_time': start.toIso8601String(),
      'end_time': end.toIso8601String(),
      'is_all_day': isAllDay ? 1 : 0,
      'recurring_event_id': recurringEventId,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory GoogleEvent.fromMap(Map<String, dynamic> map) {
    return GoogleEvent(
      id: map['id'] as String,
      calendarId: map['calendar_id'] as String,
      summary: map['summary'] as String,
      description: map['description'] as String?,
      location: map['location'] as String?,
      start: DateTime.parse(map['start_time'] as String),
      end: DateTime.parse(map['end_time'] as String),
      isAllDay: (map['is_all_day'] as int?) == 1,
      recurringEventId: map['recurring_event_id'] as String?,
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  factory GoogleEvent.fromApiResponse(Map<String, dynamic> json, String calendarId) {
    DateTime start;
    DateTime end;
    bool isAllDay = false;

    if (json['start']['date'] != null) {

      isAllDay = true;
      start = DateTime.parse(json['start']['date'] as String);
      final exclusiveEnd = DateTime.parse(json['end']['date'] as String);
      end = DateTime(exclusiveEnd.year, exclusiveEnd.month, exclusiveEnd.day - 1);
      if (end.isBefore(start)) end = start;
    } else {
      start = DateTime.parse(json['start']['dateTime'] as String);
      end = DateTime.parse(json['end']['dateTime'] as String);
    }

    return GoogleEvent(
      id: json['id'] as String,
      calendarId: calendarId,
      summary: json['summary'] as String? ?? 'Untitled',
      description: json['description'] as String?,
      location: json['location'] as String?,
      start: start,
      end: end,
      isAllDay: isAllDay,
      recurringEventId: json['recurringEventId'] as String?,
      isSynced: true,
    );
  }

  Map<String, dynamic> toApiMap() {
    final map = <String, dynamic>{
      'summary': summary,
    };

    if (description != null) map['description'] = description;
    if (location != null) map['location'] = location;

    if (isAllDay) {
      map['start'] = {'date': '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}'};
      final exclusiveEnd = DateTime(end.year, end.month, end.day + 1);
      map['end'] = {'date': '${exclusiveEnd.year}-${exclusiveEnd.month.toString().padLeft(2, '0')}-${exclusiveEnd.day.toString().padLeft(2, '0')}'};
    } else {
      map['start'] = {'dateTime': start.toUtc().toIso8601String()};
      map['end'] = {'dateTime': end.toUtc().toIso8601String()};
    }

    return map;
  }

  GoogleEvent copyWith({
    String? id,
    String? calendarId,
    String? summary,
    String? description,
    String? location,
    DateTime? start,
    DateTime? end,
    bool? isAllDay,
    String? recurringEventId,
    bool? isSynced,
  }) {
    return GoogleEvent(
      id: id ?? this.id,
      calendarId: calendarId ?? this.calendarId,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      start: start ?? this.start,
      end: end ?? this.end,
      isAllDay: isAllDay ?? this.isAllDay,
      recurringEventId: recurringEventId ?? this.recurringEventId,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  String get startTimeDisplay =>
      '${start.hour}:${start.minute.toString().padLeft(2, '0')}';

  String get endTimeDisplay =>
      '${end.hour}:${end.minute.toString().padLeft(2, '0')}';

  String get dateDisplay {
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${weekdays[start.weekday - 1]}, ${start.day}.${start.month}.';
  }
}

class SyncResult {
  final bool success;
  final String? error;
  final int added;
  final int updated;
  final int deleted;
  final String? nextSyncToken;

  SyncResult({
    required this.success,
    this.error,
    this.added = 0,
    this.updated = 0,
    this.deleted = 0,
    this.nextSyncToken,
  });

  int get totalChanges => added + updated + deleted;
}
