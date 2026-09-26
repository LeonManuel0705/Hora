// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../brand.dart';
import '../build_info.dart';
import '../theme.dart';
import 'notification_service.dart';

class UpdateService {
  static String get currentVersion => BuildInfo.version;
  static String get currentVersionName => BuildInfo.versionName;

  static const String _versionUrl = '${Brand.website}/version.json';
  static const Duration _connectionTimeout = Duration(seconds: 2);
  static const String _skippedVersionKey = 'update_skipped_version';
  static final List<String> _trustedUpdateDomains = [
    Uri.parse(Brand.website).host,
  ];

  static final List<String> _trustedGitHubPaths = [
    '${Uri.parse(Brand.repository).path}/releases/',
  ];


  static Future<UpdateInfo?> checkForUpdate({bool ignoreSkipped = false}) async {
    try {
      final response = await http.get(Uri.parse(_versionUrl))
          .timeout(_connectionTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final remoteVersion = data['version'] as String;

        if (_isNewerVersion(remoteVersion, currentVersion)) {
          if (!ignoreSkipped) {
            final prefs = await SharedPreferences.getInstance();
            final skippedVersion = prefs.getString(_skippedVersionKey);
            if (skippedVersion == remoteVersion) return null;
          }

          final rawUpdateUrl = _getPlatformUrl(data) ?? data['updateUrl'] as String? ?? '${Brand.website}/download';
          final updateUrl = _validateUpdateUrl(rawUpdateUrl)
              ? rawUpdateUrl
              : '${Brand.website}/download';
          return UpdateInfo(
            version: remoteVersion,
            versionName: data['versionName'] as String? ?? remoteVersion,
            updateUrl: updateUrl,
            changelog: (data['changelog'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ?? [],
          );
        }
      }
    } on TimeoutException {
      debugPrint('Update check: Connection timeout');
    } catch (e) {
      debugPrint('Update check error: $e');
    }
    return null;
  }


  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedVersionKey, version);
  }


  static Future<void> sendUpdateNotification(UpdateInfo updateInfo) async {
    try {
      final notificationService = NotificationService();
      if (!notificationService.isInitialized) {
        await notificationService.initialize();
      }
      await notificationService.showNotification(
        id: 9999,
        title: '${Brand.name} Update verfügbar',
        body: '${updateInfo.versionName} ist jetzt verfügbar. Tippe um herunterzuladen.',
        payload: updateInfo.updateUrl,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Update notification error: $e');
    }
  }

  static String? _getPlatformUrl(Map<String, dynamic> data) {
    final platformUrls = data['platformUrls'] as Map<String, dynamic>?;
    if (platformUrls == null) return null;

    String platformKey;
    if (kIsWeb) {
      platformKey = 'web';
    } else if (Platform.isAndroid) {
      platformKey = 'android';
    } else if (Platform.isIOS) {
      platformKey = 'ios';
    } else if (Platform.isMacOS) {
      platformKey = 'macos';
    } else if (Platform.isWindows) {
      platformKey = 'windows';
    } else if (Platform.isLinux) {
      platformKey = 'linux';
    } else {
      return null;
    }

    return platformUrls[platformKey] as String?;
  }

  static bool _isNewerVersion(String remote, String current) {
    try {
      final remoteParts = remote.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < remoteParts.length && i < currentParts.length; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
      return remoteParts.length > currentParts.length;
    } catch (e) {
      return remote != current;
    }
  }

  static bool _validateUpdateUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https') return false;
      final host = uri.host.toLowerCase();
      if (_trustedUpdateDomains.any((domain) =>
          host == domain || host.endsWith('.$domain'))) {
        return true;
      }
      if (host == 'github.com') {
        final path = uri.path.toLowerCase();
        return _trustedGitHubPaths.any((trustedPath) =>
            path.startsWith(trustedPath.toLowerCase()));
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }
}

class UpdateInfo {
  final String version;
  final String versionName;
  final String updateUrl;
  final List<String> changelog;

  UpdateInfo({
    required this.version,
    required this.versionName,
    required this.updateUrl,
    required this.changelog,
  });
}

class UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? AppPalette.overlayDark : AppPalette.overlay,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: .5) : const Color(0xFF14201A).withValues(alpha: .18),
              blurRadius: 36,
              spreadRadius: -10,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primaryColor,
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Neues Update verfügbar',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    ),
                    child: Text(
                      'Version ${updateInfo.versionName}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (updateInfo.changelog.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Neuheiten',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...updateInfo.changelog.take(4).map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),

            Container(
              height: 1,
              color: isDark ? AppPalette.lineDark : AppPalette.line,
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _openUpdateUrl(updateInfo.updateUrl);
                      },
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text(
                        'Herunterladen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: isDark ? AppPalette.brandDark : AppPalette.pine,
                        foregroundColor: isDark ? AppPalette.inkDark : AppPalette.chalk,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: StadiumBorder(
                          side: isDark ? const BorderSide(color: Color(0xFF3E5541)) : BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Später',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 20,
                        color: (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)
                            .withValues(alpha: 0.5),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            UpdateService.skipVersion(updateInfo.version);
                            Navigator.of(context).pop();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            'Überspringen',
                            style: TextStyle(
                              color: (isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted).withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Installiert: ${UpdateService.currentVersionName}',
                style: TextStyle(
                  fontSize: 12,
                  color: (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)
                      .withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUpdateUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('canLaunchUrl error: $e');
    }
    // canLaunchUrl can be over-conservative (Android package-visibility, some
    // desktop setups); attempt the launch directly rather than silently failing.
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error opening URL: $e');
    }
  }
}
