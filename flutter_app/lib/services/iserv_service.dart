// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/iserv.dart';
import 'database_service.dart';
import 'encryption_service.dart';

@visibleForTesting
Future<void> forgetIServCredentials(Database db, EncryptionService encryption, {String? keep}) async {
  try {
    await encryption.deleteCredentialsWithPrefix('iserv_', keep: keep);
  } catch (_) {}
  await db.delete('iserv_credentials');
}

class IServService {
  static final IServService _instance = IServService._internal();
  factory IServService() => _instance;
  IServService._internal();

  final DatabaseService _db = DatabaseService();
  final EncryptionService _encryption = EncryptionService();
  Dio? _dio;
  CookieJar? _cookieJar;

  String? _sessionToken;
  String? _baseUrl;
  String? _currentUsername;
  bool _isWebViewSession = false;

  final StringBuffer _apiLog = StringBuffer();
  String get apiLog => kDebugMode ? _apiLog.toString() : '';
  void clearApiLog() => _apiLog.clear();
  void _log(String msg) {
    if (kDebugMode) {
      print('IServService: $msg');
      _apiLog.writeln('${DateTime.now().toString().substring(11, 19)} $msg');
      if (_apiLog.length > 8000) {
        final s = _apiLog.toString();
        _apiLog.clear();
        _apiLog.write(s.substring(s.length - 6000));
      }
    }
  }

  bool get isConnected => (_sessionToken != null && _dio != null) ||
                          (_isWebViewSession && _baseUrl != null);

  String? get iservUrl => _baseUrl;

  bool get hasDioSession => _dio != null && _cookieJar != null;

  Future<bool> hasValidCookies() async {
    if (_dio == null || _cookieJar == null || _baseUrl == null) return false;
    try {
      final cookies = await _cookieJar!.loadForRequest(Uri.parse(_baseUrl!));
      return cookies.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Dio _createDio(String baseUrl) {
    final cookieJar = CookieJar();
    _cookieJar = cookieJar;

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      followRedirects: false,
      validateStatus: (status) => status != null && status < 500,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
      },
    ));

    dio.interceptors.add(CookieManager(cookieJar));
    return dio;
  }

  Future<bool> autoReconnect() async {
    if (isConnected && _dio != null) return true;

    try {
      final db = await _db.database;
      final credentials = await db.query('iserv_credentials', orderBy: 'created_at DESC', limit: 1);

      if (credentials.isNotEmpty) {
        final cred = IServCredentials.fromMap(credentials.first);
        _baseUrl = cred.iservUrl;
        _currentUsername = cred.username;

        final secureCredentials = await _encryption.getIServCredentials(cred.credentialKey);
        final storedPassword = secureCredentials?['password'] ?? '';

        if (storedPassword.isNotEmpty) {
          final result = await connect(
            username: cred.username,
            password: storedPassword,
            iservUrl: cred.iservUrl,
          );
          return result['success'] == true;
        } else {
          _isWebViewSession = false;
          if (kDebugMode) print('IServ: autoReconnect - no password stored (WebView session), cannot re-authenticate');
          return false;
        }
      }
    } catch (e) {
      if (kDebugMode) print('IServ: Auto-reconnect failed: $e');
    }

    return false;
  }

  Future<IServCredentials?> getSavedCredentials() async {
    try {
      final db = await _db.database;
      final credentials = await db.query('iserv_credentials', orderBy: 'created_at DESC', limit: 1);

      if (credentials.isNotEmpty) {
        return IServCredentials.fromMap(credentials.first);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> connect({
    required String username,
    required String password,
    required String iservUrl,
  }) async {
    try {
      String normalizedUrl = iservUrl
          .replaceAll(RegExp(r'^https?://'), '')
          .replaceAll(RegExp(r'/+$'), '');
      final testUri = Uri.tryParse('https://$normalizedUrl');
      if (testUri == null || testUri.host.isEmpty || testUri.userInfo.isNotEmpty) {
        return {'success': false, 'error': 'Ungültige IServ-URL'};
      }
      _baseUrl = 'https://$normalizedUrl';

      final dio = _createDio(_baseUrl!);

      final loginData = <String, dynamic>{
        '_username': username,
        '_password': password,
      };
      String postUrl = '/iserv/login_check';

      try {
        final loginPageResponse = await dio.get(
          '/iserv/login',
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
          ),
        );
        final html = loginPageResponse.data?.toString() ?? '';
        if (kDebugMode) print('IServ: Login page status: ${loginPageResponse.statusCode}, length: ${html.length}');

        final formAction = RegExp(r'<form[^>]*action="([^"]*)"', dotAll: true).firstMatch(html);
        if (formAction != null) {
          final action = formAction.group(1)!;
          if (action.isNotEmpty) {
            postUrl = action.startsWith('/') ? action : '/iserv/$action';
            if (kDebugMode) print('IServ: Found form action: $postUrl');
          }
        }

        final hiddenInputs = RegExp(
          r'<input[^>]*type=["\x27]hidden["\x27][^>]*/?>',
          dotAll: true,
          caseSensitive: false,
        ).allMatches(html);

        for (final input in hiddenInputs) {
          final inputHtml = input.group(0)!;
          final nameMatch = RegExp(r'name=["\x27]([^"\x27]+)["\x27]').firstMatch(inputHtml);
          final valueMatch = RegExp(r'value=["\x27]([^"\x27]*)["\x27]').firstMatch(inputHtml);
          if (nameMatch != null) {
            final name = nameMatch.group(1)!;
            final value = valueMatch?.group(1) ?? '';
            loginData[name] = value;
            if (kDebugMode) print('IServ: Found hidden field: $name (${value.length} chars)');
          }
        }

        final hiddenInputsAlt = RegExp(
          r'<input[^>]*name=["\x27]([^"\x27]+)["\x27][^>]*type=["\x27]hidden["\x27][^>]*value=["\x27]([^"\x27]*)["\x27][^>]*/?>',
          dotAll: true,
          caseSensitive: false,
        ).allMatches(html);

        for (final input in hiddenInputsAlt) {
          final name = input.group(1)!;
          final value = input.group(2) ?? '';
          if (!loginData.containsKey(name)) {
            loginData[name] = value;
            if (kDebugMode) print('IServ: Found hidden field (alt): $name (${value.length} chars)');
          }
        }

        if (loginData.length <= 2) {
          if (kDebugMode) print('IServ: WARNING - No hidden form fields found!');
          final lowerHtml = html.toLowerCase();
          if (lowerHtml.contains('_username') || lowerHtml.contains('username')) {
            if (kDebugMode) print('IServ: Page contains username field');
          }
          if (lowerHtml.contains('password')) {
            if (kDebugMode) print('IServ: Page contains password field');
          }
          if (kDebugMode) print('IServ: Page start: ${html.substring(0, html.length > 1000 ? 1000 : html.length)}');
        }
      } catch (e) {
        if (kDebugMode) print('IServ: Could not fetch login page: $e');
      }

      if (kDebugMode) print('IServ: Posting login with ${loginData.length} fields to $postUrl');

      final response = await dio.post(
        postUrl,
        data: loginData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (kDebugMode) print('IServ: Login response status: ${response.statusCode}');
      if (kDebugMode) print('IServ: Login response location: ${response.headers.value('location')}');

      if (response.statusCode == 302 || response.statusCode == 200) {
        final location = response.headers.value('location') ?? '';
        if (!location.contains('login') && !location.contains('error')) {
          _dio = dio;
          _currentUsername = username;
          _sessionToken = 'session_active';

          final credentialKey = await _encryption.storeIServCredentials(
            username: username,
            password: password,
            iservUrl: _baseUrl!,
          );

          final db = await _db.database;
          await forgetIServCredentials(db, _encryption, keep: credentialKey);
          await db.insert(
            'iserv_credentials',
            IServCredentials(
              username: username,
              iservUrl: _baseUrl!,
              credentialKey: credentialKey,
              createdAt: DateTime.now(),
            ).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          return {'success': true};
        }
      }

      return {'success': false, 'error': 'Anmeldung fehlgeschlagen'};
    } catch (e) {
      return {'success': false, 'error': 'Verbindungsfehler. Bitte überprüfe deine Internetverbindung.'};
    }
  }

  Future<void> disconnect() async {
    _dio = null;
    _cookieJar = null;
    _sessionToken = null;
    _baseUrl = null;
    _currentUsername = null;
    _isWebViewSession = false;

    try {
      final db = await _db.database;
      await forgetIServCredentials(db, _encryption);
    } catch (_) {}
  }

  Future<bool> refreshWithWebViewCookies(List<dynamic> cookies) async {
    if (_baseUrl == null || _cookieJar == null) return false;

    try {
      final uri = Uri.parse(_baseUrl!);
      final cookieList = <Cookie>[];

      for (final c in cookies) {
        try {
          String? name;
          String? value;

          if (c is Map) {
            name = c['name']?.toString();
            value = c['value']?.toString() ?? '';
          } else {
            name = c.name?.toString();
            value = c.value?.toString() ?? '';
          }

          if (name != null && name.isNotEmpty) {
            final cookie = Cookie(name, value);
            cookie.domain = uri.host;
            cookie.path = '/';
            cookieList.add(cookie);
          }
        } catch (_) {}
      }

      if (kDebugMode) print('IServ: Refreshing Dio with ${cookieList.length} cookies from WebView');

      if (cookieList.isNotEmpty) {
        await _cookieJar!.saveFromResponse(uri, cookieList);
        return true;
      }

      return false;
    } catch (e) {
      if (kDebugMode) print('IServ: Failed to refresh cookies: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> connectWithWebViewCookies({
    required String iservUrl,
    required List<dynamic> cookies,
    String? username,
  }) async {
    try {
      String normalizedUrl = iservUrl
          .replaceAll(RegExp(r'^https?://'), '')
          .replaceAll(RegExp(r'/+$'), '');
      _baseUrl = 'https://$normalizedUrl';

      final cookieJar = CookieJar();
      _cookieJar = cookieJar;

      final dio = Dio(BaseOptions(
        baseUrl: _baseUrl!,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
        },
      ));

      dio.interceptors.add(CookieManager(cookieJar));

      final cookieList = <Cookie>[];

      for (final c in cookies) {
        try {
          String? name;
          String? value;
          String? domain;
          String? path;

          if (c is Map) {
            name = c['name']?.toString();
            value = c['value']?.toString() ?? '';
            domain = c['domain']?.toString();
            path = c['path']?.toString();
          } else {
            name = c.name?.toString();
            value = c.value?.toString() ?? '';
            try { domain = c.domain?.toString(); } catch (_) {}
            try { path = c.path?.toString(); } catch (_) {}
          }

          if (name != null && name.isNotEmpty) {
            final cookie = Cookie(name, value);
            if (domain != null) cookie.domain = domain;
            if (path != null) cookie.path = path;
            try {
              if (c.expiresDate != null) {
                cookie.expires = DateTime.fromMillisecondsSinceEpoch(c.expiresDate!.toInt());
              }
            } catch (_) {}
            try { cookie.httpOnly = c.isHttpOnly ?? false; } catch (_) {}
            try { cookie.secure = c.isSecure ?? false; } catch (_) {}
            cookieList.add(cookie);
          }
        } catch (_) {}
      }

      final baseUri = Uri.parse(_baseUrl!);
      final cookieDomain = baseUri.host;

      for (final cookie in cookieList) {
        cookie.domain = cookieDomain;
        cookie.path = '/';
      }

      if (kDebugMode) print('IServ: Saving ${cookieList.length} cookies for domain: $cookieDomain');
      for (final c in cookieList) {
        final valuePreview = c.value.length > 10 ? '${c.value.substring(0, 10)}...' : c.value;
        if (kDebugMode) print('  Cookie: ${c.name}=$valuePreview domain=${c.domain} path=${c.path}');
      }

      try {
        await cookieJar.saveFromResponse(baseUri, cookieList);
        if (kDebugMode) print('IServ: Cookies saved successfully to jar');
      } catch (e) {
        if (kDebugMode) print('IServ: Failed to save cookies: $e');
      }

      bool isLoggedIn = false;
      try {
        final verifyResponse = await dio.get('/iserv/');
        final verifyBody = verifyResponse.data?.toString() ?? '';

        isLoggedIn = verifyBody.contains('Abmelden') ||
                     verifyBody.contains('logout') ||
                     verifyBody.contains('iserv-menu') ||
                     verifyBody.contains('iserv-nav') ||
                     verifyBody.contains('IServ-Dashboard') ||
                     verifyBody.contains('Mein IServ') ||
                     verifyBody.contains('class="nav"') ||
                     verifyBody.contains('data-module') ||
                     (verifyBody.contains('/iserv/') && !verifyBody.contains('login_check') && !verifyBody.contains('_username'));
      } catch (e) {
        if (cookieList.isEmpty) {
          return {'success': false, 'error': 'Verbindungsfehler. Bitte überprüfe deine Internetverbindung.'};
        }
      }

      if (!isLoggedIn && cookieList.isEmpty) {
        try {
          final retryDio = Dio(BaseOptions(
            baseUrl: _baseUrl!,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            followRedirects: true,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            },
          ));
          retryDio.interceptors.add(CookieManager(cookieJar));

          final retryResponse = await retryDio.get('/iserv/');
          final retryBody = retryResponse.data?.toString() ?? '';

          isLoggedIn = !retryBody.contains('login_check') &&
                       !retryBody.contains('_username') &&
                       !retryBody.contains('_password');
        } catch (_) {}
      }

      _sessionToken = 'webview_session_active';
      _currentUsername = username ?? 'IServ-Nutzer';
      _dio = dio;
      _isWebViewSession = true;

      final credentialKey = await _encryption.storeIServCredentials(
        username: _currentUsername!,
        password: '',
        iservUrl: _baseUrl!,
      );

      final db = await _db.database;
      await forgetIServCredentials(db, _encryption, keep: credentialKey);
      await db.insert(
        'iserv_credentials',
        IServCredentials(
          username: _currentUsername!,
          iservUrl: _baseUrl!,
          credentialKey: credentialKey,
          createdAt: DateTime.now(),
        ).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return {'success': true, 'username': _currentUsername};
    } catch (e) {
      return {'success': false, 'error': 'Ein Fehler ist aufgetreten. Bitte versuche es erneut.'};
    }
  }

  Future<List<IServNotification>> getNotifications() async {
    if (!isConnected || _dio == null) return getCachedNotifications();

    try {
      final response = await _dio!.get(
        '/iserv/messenger/api/messages',
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode != 200) return await getCachedNotifications();

      final data = response.data;

      if (data is! List) {
        if (kDebugMode) print('IServ: Notifications response is not a List, returning cached');
        return await getCachedNotifications();
      }

      final List<IServNotification> notifications = [];
      final now = DateTime.now();

      for (final item in data) {
        notifications.add(IServNotification(
          id: item['id']?.toString() ?? '',
          title: item['title'] ?? item['subject'] ?? '',
          message: item['message'] ?? item['body'] ?? '',
          type: item['type'],
          read: item['read'] == true,
          timestamp: item['date'] != null
              ? DateTime.parse(item['date'])
              : now,
          cachedAt: now,
        ));
      }

      await _cacheNotifications(notifications);

      return notifications;
    } catch (e) {

      return getCachedNotifications();
    }
  }

  Future<List<IServExercise>> getExercises() async {
    if (!isConnected || _dio == null) return getCachedExercises();

    try {
      final response = await _dio!.get(
        '/iserv/exercise/api/exercises',
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.json,
        ),
      );

      if (response.statusCode != 200) return await getCachedExercises();

      final data = response.data;

      if (data is! Map || data['data'] is! List) {
        if (kDebugMode) print('IServ: Exercises response is not valid, returning cached');
        return await getCachedExercises();
      }

      final List<IServExercise> exercises = [];
      final now = DateTime.now();

      for (final item in data['data']) {
        exercises.add(IServExercise(
          id: item['id']?.toString() ?? '',
          title: item['title'] ?? '',
          description: item['description'],
          course: item['course']?['name'] ?? item['course'],
          teacher: item['teacher']?['name'] ?? item['teacher'],
          dueDate: item['endDate'] != null
              ? DateTime.parse(item['endDate'])
              : null,
          status: item['status'] ?? 'open',
          cachedAt: now,
        ));
      }

      await _cacheExercises(exercises);

      return exercises;
    } catch (e) {

      return getCachedExercises();
    }
  }

  Future<List<IServEvent>> getEvents({int? userGrade}) async {
    _log('getEvents: isConnected=$isConnected, hasDio=${_dio != null}, baseUrl=$_baseUrl, webView=$_isWebViewSession');
    if (!isConnected || _dio == null) {
      _log('getEvents: NOT connected → returning cached');
      return getCachedEvents();
    }

    try {
      final now = DateTime.now();
      final start = now.subtract(const Duration(days: 30));
      final end = now.add(const Duration(days: 90));


      _log('getEvents: fetching event sources...');
      final sourcesResponse = await _dio!.get(
        '/iserv/calendar/api/eventsources',
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      _log('getEvents: eventsources status=${sourcesResponse.statusCode}, type=${sourcesResponse.headers.value("content-type")}');

      if (sourcesResponse.statusCode != 200) {
        _log('getEvents: eventsources non-200 → cached');
        return await getCachedEvents();
      }

      final sourcesData = sourcesResponse.data;
      List? sourcesList;
      if (sourcesData is List) {
        sourcesList = sourcesData;
      } else if (sourcesData is Map) {
        sourcesList = sourcesData.values.toList();
      }

      if (sourcesList == null || sourcesList.isEmpty) {
        _log('getEvents: no event sources found. Data: ${sourcesData.toString().substring(0, (sourcesData.toString().length).clamp(0, 300))}');
        return await getCachedEvents();
      }

      _log('getEvents: found ${sourcesList.length} event sources');

      final calendarIds = <String>[];
      final pluginIds = <String>[];
      for (final source in sourcesList) {
        if (source is! Map) continue;
        final id = source['id']?.toString() ?? '';
        final type = source['type']?.toString() ?? '';
        _log('  source: id=$id, type=$type');
        if (type == 'cal' && id.isNotEmpty) {
          calendarIds.add(id);
        } else if (type == 'plugin' && id.isNotEmpty) {
          pluginIds.add(id);
        }
      }

      _log('getEvents: ${calendarIds.length} calendars, ${pluginIds.length} plugins');

      final List<IServEvent> allEvents = [];
      final startStr = start.toIso8601String();
      final endStr = end.toIso8601String();

      if (calendarIds.isNotEmpty) {
        _log('getEvents: trying multi-feed for ${calendarIds.length} calendars...');
        final multiFeedEvents = await _fetchFromFeed(
          '/iserv/calendar/feed/calendar-multi',
          {'start': startStr, 'end': endStr, 'calendars[]': calendarIds},
          now,
        );

        if (multiFeedEvents != null) {
          allEvents.addAll(multiFeedEvents);
          _log('getEvents: multi-feed → ${multiFeedEvents.length} events');
        } else {
          _log('getEvents: multi-feed failed, trying individual feeds...');
          for (final calId in calendarIds) {
            final events = await _fetchFromFeed(
              '/iserv/calendar/feed/calendar',
              {'start': startStr, 'end': endStr, 'calendar': calId},
              now,
            );
            if (events != null) {
              allEvents.addAll(events);
              _log('  calendar $calId → ${events.length} events');
            }
          }
        }
      }

      if (pluginIds.isNotEmpty) {
        for (final pluginId in pluginIds) {
          final events = await _fetchFromFeed(
            '/iserv/calendar/feed/plugin',
            {'start': startStr, 'end': endStr, 'plugin': pluginId},
            now,
          );
          if (events != null) {
            allEvents.addAll(events);
            _log('  plugin $pluginId → ${events.length} events');
          }
        }
      }

      _log('getEvents: total ${allEvents.length} events (raw)');

      final seen = <String>{};
      allEvents.removeWhere((e) {
        final key = '${e.title}|${e.startTime?.toIso8601String()}';
        if (seen.contains(key)) return true;
        seen.add(key);
        return false;
      });
      _log('getEvents: ${allEvents.length} after dedup');

      if (userGrade != null) {
        final before = allEvents.length;
        final explicitGrade = RegExp(
          r'(?:JGST\.?\s*|Klasse\s+|Kl\.?\s*)(\d+)',
          caseSensitive: false,
        );
        final classSection = RegExp(r'\b(\d{1,2})[A-Za-z]\b');

        allEvents.removeWhere((e) {
          final text = '${e.title} ${e.description ?? ''}';

          final explicitMatch = explicitGrade.firstMatch(text);
          if (explicitMatch != null) {
            final eventGrade = int.tryParse(explicitMatch.group(1)!);
            return eventGrade != null && eventGrade != userGrade;
          }

          final sectionMatch = classSection.firstMatch(text);
          if (sectionMatch != null) {
            final eventGrade = int.tryParse(sectionMatch.group(1)!);
            if (eventGrade != null && eventGrade >= 5 && eventGrade <= 13 && eventGrade != userGrade) {
              return true;
            }
          }

          return false;
        });
        _log('getEvents: ${allEvents.length} after grade filter (was $before, grade=$userGrade)');
      }

      if (allEvents.isNotEmpty) {
        await _cacheEvents(allEvents);
      }

      return allEvents;
    } catch (e) {
      _log('getEvents: EXCEPTION: $e');
      return getCachedEvents();
    }
  }

  Future<List<IServEvent>?> _fetchFromFeed(
    String endpoint, Map<String, dynamic> params, DateTime now,
  ) async {
    try {
      final response = await _dio!.get(
        endpoint,
        queryParameters: params,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      _log('  feed $endpoint → status=${response.statusCode}');

      if (response.statusCode != 200) return null;

      final data = response.data;
      final List<IServEvent> events = [];

      if (data is List) {
        for (final item in data) {
          final e = _parseIServEvent(item, now);
          if (e != null) events.add(e);
        }
      } else if (data is Map) {
        for (final entry in data.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is List) {
            for (final item in value) {
              final e = _parseIServEvent(item, now);
              if (e != null) events.add(e);
            }
          } else if (value is Map && value.containsKey('error')) {
            _log('  feed source $key: error=${value['error']}');
          }
        }
      }

      return events.isEmpty && data is! List && data is! Map ? null : events;
    } catch (e) {
      _log('  feed $endpoint → EXCEPTION: $e');
      return null;
    }
  }

  IServEvent? _parseIServEvent(dynamic item, DateTime now) {
    if (item is! Map) return null;
    final title = item['title'] ?? item['summary'] ?? item['subject'] ?? '';
    final startRaw = item['start'];
    final endRaw = item['end'];
    final startTime = _parseEventDateTime(startRaw);
    var endTime = _parseEventDateTime(endRaw);

    bool allDay = item['allDay'] == true || item['allday'] == true;
    if (!allDay && startRaw is String && !startRaw.contains('T')) {
      allDay = true;
    }

    if (allDay && endTime != null && startTime != null) {
      endTime = endTime.subtract(const Duration(days: 1));
      if (endTime.isBefore(startTime)) {
        endTime = startTime;
      }
    }

    if (_apiLog.length < 4000) {
      _log('  event: "$title" raw=$startRaw→$endRaw parsed=$startTime→$endTime allDay=$allDay');
    }
    return IServEvent(
      id: _eventId(item, title, startRaw),
      title: title,
      startTime: startTime,
      endTime: endTime,
      location: item['location'],
      description: item['description'],
      calendar: item['calendar'] ?? item['calendarId'] ?? item['calendarName'],
      allDay: allDay,
      cachedAt: now,
    );
  }

  DateTime? _parseEventDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final dt = DateTime.tryParse(value);
      if (dt == null) return null;
      return dt.isUtc ? dt.toLocal() : dt;
    }
    if (value is Map) {
      final dateStr = value['dateTime'] ?? value['date'] ?? value['start'];
      if (dateStr is String) {
        final dt = DateTime.tryParse(dateStr);
        if (dt == null) return null;
        return dt.isUtc ? dt.toLocal() : dt;
      }
    }
    return null;
  }

  final String _discoveryLog = '';
  String get discoveryLog => kDebugMode ? _discoveryLog : '';

  Future<void> _cacheNotifications(List<IServNotification> notifications) async {
    if (notifications.isEmpty) return;

    final db = await _db.database;
    final batch = db.batch();

    batch.delete('iserv_notifications');

    for (final notification in notifications) {
      batch.insert('iserv_notifications', notification.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<void> _cacheExercises(List<IServExercise> exercises) async {
    if (exercises.isEmpty) return;

    final db = await _db.database;
    final batch = db.batch();

    batch.delete('iserv_exercises');

    for (final exercise in exercises) {
      batch.insert('iserv_exercises', exercise.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  String _decodeBody(dynamic data) {
    if (data is List<int>) return utf8.decode(data, allowMalformed: true);
    return data?.toString() ?? '';
  }

  String _eventId(dynamic item, String title, dynamic startRaw) {
    final raw = item['id']?.toString() ?? item['uid']?.toString();
    if (raw != null && raw.isNotEmpty) return raw;
    return 'gen_${title.hashCode}_${startRaw ?? ''}';
  }

  Future<void> _cacheEvents(List<IServEvent> events) async {
    if (events.isEmpty) return;

    final db = await _db.database;
    final batch = db.batch();

    batch.delete('iserv_events');

    for (final event in events) {
      batch.insert('iserv_events', event.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  Future<List<IServNotification>> getCachedNotifications() async {
    final db = await _db.database;
    final results = await db.query('iserv_notifications', orderBy: 'timestamp DESC');
    return results.map((m) => IServNotification.fromMap(m)).toList();
  }

  Future<List<IServExercise>> getCachedExercises() async {
    final db = await _db.database;
    final results = await db.query('iserv_exercises', orderBy: 'due_date ASC');
    return results.map((m) => IServExercise.fromMap(m)).toList();
  }

  Future<List<IServEvent>> getCachedEvents() async {
    final db = await _db.database;
    final results = await db.query('iserv_events', orderBy: 'start_time ASC');
    return results.map((m) => IServEvent.fromMap(m)).toList();
  }

  Future<void> syncAll() async {
    if (!isConnected) {
      final reconnected = await autoReconnect();
      if (!reconnected) return;
    }

    await Future.wait([
      getNotifications(),
      getExercises(),
      getEvents(),
    ]);
  }

  Future<Map<String, dynamic>> fetchVertretungsplan({int displayId = 3}) async {
    if (_dio == null || _baseUrl == null) {
      final reconnected = await autoReconnect();
      if (!reconnected || _dio == null || _baseUrl == null) {
        return await _getCachedVertretungsplanResult();
      }
    }

    try {
      final List<Map<String, dynamic>> files = [];

      final showUrl = '$_baseUrl/iserv/infodisplay/show/$displayId';

      if (_cookieJar != null) {
        final cookies = await _cookieJar!.loadForRequest(Uri.parse(showUrl));
        if (kDebugMode) print('IServ Vertretungsplan: Found ${cookies.length} cookies for $showUrl');
        for (final c in cookies) {
          if (kDebugMode) print('  Cookie: ${c.name} domain=${c.domain} path=${c.path}');
        }
      } else {
        if (kDebugMode) print('IServ Vertretungsplan: WARNING - No cookie jar available!');
      }

      final htmlResponse = await _dio!.get(
        showUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (htmlResponse.statusCode == 200) {
        final contentType = htmlResponse.headers.value('content-type') ?? '';

        if (contentType.contains('application/pdf')) {
          final data = base64Encode(htmlResponse.data as List<int>);
          await _db.cacheVertretungsplanFile(data: data, page: 1, contentType: 'application/pdf');
          return {
            'success': true,
            'files': [{'data': data, 'contentType': 'application/pdf', 'page': 1}],
            'isFromCache': false,
          };
        }

        if (contentType.contains('text/html')) {
          final html = _decodeBody(htmlResponse.data);

          final urlsToTry = <String>{};

          bool isInfodisplayUrl(String url) {
            final resolved = _resolveUrl(url);
            return resolved.contains('/iserv/infodisplay/');
          }

          final infodisplayRegex = RegExp(r'/iserv/infodisplay/(?:file|pdf)/[^\s"' "'" r'><]+', caseSensitive: false);
          for (final match in infodisplayRegex.allMatches(html)) {
            final src = match.group(0);
            if (src != null) urlsToTry.add(_resolveUrl(src));
          }

          final imgRegex = RegExp(r'<img[^>]+src=["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false);
          for (final match in imgRegex.allMatches(html)) {
            final src = match.group(1);
            if (src != null && !src.startsWith('data:') && isInfodisplayUrl(src)) {
              urlsToTry.add(_resolveUrl(src));
            }
          }

          final iframeRegex = RegExp(r'<iframe[^>]+src=["' "'" r']([^"' "'" r']+)["' "'" r']', caseSensitive: false);
          for (final match in iframeRegex.allMatches(html)) {
            final src = match.group(1);
            if (src != null && isInfodisplayUrl(src)) {
              urlsToTry.add(_resolveUrl(src));
            }
          }

          final objectRegex = RegExp(r'(?:data|src)=["' "'" r']([^"' "'" r']+\.(?:pdf|png|jpg|jpeg|gif))["' "'" r']', caseSensitive: false);
          for (final match in objectRegex.allMatches(html)) {
            final src = match.group(1);
            if (src != null && isInfodisplayUrl(src)) {
              urlsToTry.add(_resolveUrl(src));
            }
          }

          for (int i = 1; i <= 6; i++) {
            urlsToTry.add('$_baseUrl/iserv/infodisplay/file/$displayId/$i');
          }

          if (kDebugMode) print('IServ Vertretungsplan: Found ${urlsToTry.length} infodisplay URLs to try');

          for (final url in urlsToTry) {
            if (files.length >= 6) break;

            try {
              final response = await _dio!.get(
                url,
                options: Options(
                  responseType: ResponseType.bytes,
                  receiveTimeout: const Duration(seconds: 8),
                  validateStatus: (status) => status != null && status < 500,
                ),
              );

              if (response.statusCode == 200 && response.data != null) {
                final ct = response.headers.value('content-type') ?? '';
                final bytes = response.data as List<int>;

                if (ct.contains('text/html') || ct.contains('svg') || bytes.length < 1000) {
                  continue;
                }

                if (ct.contains('pdf') || ct.contains('image')) {
                  final data = base64Encode(bytes);
                  files.add({
                    'data': data,
                    'contentType': ct,
                    'page': files.length + 1,
                  });
                }
              }
            } catch (e) {
              continue;
            }
          }
        }
      }

      if (files.isNotEmpty) {
        await _db.clearVertretungsplanCache();
        for (final file in files) {
          await _db.cacheVertretungsplanFile(
            data: file['data'] as String,
            page: file['page'] as int,
            contentType: file['contentType'] as String,
          );
        }
        return {
          'success': true,
          'files': files,
          'isFromCache': false,
        };
      }

      return await _getCachedVertretungsplanResult();

    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        return await _getCachedVertretungsplanResult();
      }
      return await _getCachedVertretungsplanResult();
    } catch (e) {
      return await _getCachedVertretungsplanResult();
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('/')) {
      return '$_baseUrl$url';
    }
    return '$_baseUrl/$url';
  }

  Future<Map<String, dynamic>> _getCachedVertretungsplanResult() async {
    final cachedFiles = await _db.getAllCachedVertretungsplanFiles();
    if (cachedFiles.isNotEmpty) {
      final files = cachedFiles.map((cached) => {
        'data': cached['data_base64'] as String?,
        'contentType': cached['content_type'] as String? ?? 'image/png',
        'page': cached['page'] as int? ?? 1,
      }).toList();

      return {
        'success': true,
        'files': files,
        'isFromCache': true,
        'cachedAt': cachedFiles.first['fetched_at'] as String?,
      };
    }
    return {
      'success': false,
      'error': 'Keine Daten verfügbar. Bitte mit IServ verbinden.',
      'isFromCache': false,
    };
  }

  Future<List<Map<String, dynamic>>> getCachedVertretungsplanFiles() async {
    return await _db.getAllCachedVertretungsplanFiles();
  }
}
