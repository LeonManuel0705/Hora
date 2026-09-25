// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';


final _trustedNotificationDomains = [
  Uri.parse(Brand.website).host,
  'github.com',
];


@pragma('vm:entry-point')
void _onNotificationTapped(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null || !payload.startsWith('https://')) return;
  final uri = Uri.tryParse(payload);
  if (uri == null) return;
  final host = uri.host.toLowerCase();
  final isTrusted = _trustedNotificationDomains.any(
    (d) => host == d || host.endsWith('.$d'),
  );
  if (isTrusted) {
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const _macChannel = MethodChannel('app/notifications');

  final FlutterLocalNotificationsPlugin _flnPlugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;

  bool get _isMacOS => !kIsWeb && Platform.isMacOS;
  // flutter_local_notifications has no Windows implementation, so Windows is
  // deliberately excluded — otherwise init/show silently throw and are swallowed,
  // making it look supported when it is not. (Desktop update prompts are shown
  // via the in-app update dialog instead.)
  bool get _useFLN =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isLinux);
  bool get isInitialized => _initialized;
  bool get permissionGranted => _permissionGranted;

  Future<void> initialize() async {
    if (_initialized) return;

    if (_isMacOS) {
      try {
        final granted = await _macChannel.invokeMethod<bool>('requestPermissions');
        _permissionGranted = granted ?? false;
        _initialized = true;
        if (kDebugMode) print('NotificationService: macOS native channel initialized, permissionGranted=$_permissionGranted');
      } catch (e) {
        _initialized = true;
        if (kDebugMode) print('NotificationService: macOS initialize() error: $e');
      }
    } else if (_useFLN) {
      try {
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
        const initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
          linux: linuxSettings,
        );

        final result = await _flnPlugin.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );
        _initialized = result ?? false;

        if (Platform.isAndroid) {
          final androidPlugin = _flnPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          _permissionGranted = await androidPlugin?.requestNotificationsPermission() ?? false;
        } else if (Platform.isIOS) {
          final iosPlugin = _flnPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
          _permissionGranted = await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ?? false;
        } else {
          _permissionGranted = _initialized;
        }

        if (kDebugMode) print('NotificationService: FLN initialized=$_initialized, permissionGranted=$_permissionGranted');
      } catch (e) {
        _initialized = true;
        if (kDebugMode) print('NotificationService: FLN initialize() error: $e');
      }
    }
  }


  Future<bool> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      if (kDebugMode) print('NotificationService: showNotification skipped — not initialized');
      return false;
    }

    if (_isMacOS) {
      return _showMacNotification(id: id, title: title, body: body, payload: payload);
    } else if (_useFLN) {
      return _showFLNNotification(id: id, title: title, body: body, payload: payload);
    }

    return false;
  }

  Future<bool> _showMacNotification({required int id, required String title, required String body, String? payload}) async {
    try {
      await _macChannel.invokeMethod('showNotification', {
        'id': id,
        'title': title,
        'body': body,
        if (payload != null) 'payload': payload,
      });
      if (kDebugMode) print('NotificationService: macOS notification sent — id=$id');
      return true;
    } on PlatformException catch (e) {
      if (kDebugMode) print('NotificationService: macOS PlatformException: ${e.code} — ${e.message}');
      return false;
    } catch (e) {
      if (kDebugMode) print('NotificationService: macOS error: $e');
      return false;
    }
  }

  Future<bool> _showFLNNotification({required int id, required String title, required String body, String? payload}) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'updates',
        'Updates',
        channelDescription: 'Benachrichtigungen über neue ${Brand.name}-Versionen',
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      const linuxDetails = LinuxNotificationDetails();
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        linux: linuxDetails,
      );

      await _flnPlugin.show(id, title, body, details, payload: payload);
      if (kDebugMode) print('NotificationService: FLN notification sent — id=$id');
      return true;
    } catch (e) {
      if (kDebugMode) print('NotificationService: FLN error: $e');
      return false;
    }
  }


  Future<bool> requestPermissions() async {
    if (_isMacOS) {
      try {
        final granted = await _macChannel.invokeMethod<bool>('requestPermissions');
        _permissionGranted = granted ?? false;
        return _permissionGranted;
      } catch (e) {
        if (kDebugMode) print('NotificationService: requestPermissions() error: $e');
        return false;
      }
    } else if (_useFLN) {
      if (Platform.isAndroid) {
        final androidPlugin = _flnPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        _permissionGranted = await androidPlugin?.requestNotificationsPermission() ?? false;
      } else if (Platform.isIOS) {
        final iosPlugin = _flnPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        _permissionGranted = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ?? false;
      }
      return _permissionGranted;
    }
    return false;
  }


  Future<Map<String, int>> getAuthorizationStatus() async {
    if (!_isMacOS) return {};
    try {
      final result = await _macChannel.invokeMapMethod<String, int>('getAuthorizationStatus');
      return result ?? {};
    } catch (e) {
      if (kDebugMode) print('NotificationService: getAuthorizationStatus() error: $e');
      return {};
    }
  }
}
