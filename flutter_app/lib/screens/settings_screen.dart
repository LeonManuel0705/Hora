// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../brand.dart';
import '../providers/app_provider.dart';
import '../providers/iserv_provider.dart';
import '../services/holiday_service.dart';
import '../services/notification_service.dart';
import '../build_info.dart';
import '../theme.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/glass_card.dart';
import '../widgets/iserv_webview_login.dart';
import '../widgets/page_fade_in.dart';
import 'timetable_config_screen.dart';
import '../tutorial/tutorial.dart';
import '../widgets/timetable_setup_wizard.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _weatherCity;
  String? _bundesland;
  int? _graduationYear;
  bool _isImportingHolidays = false;
  int _classLevel = 10;

  static const _bundeslaender = [
    'Baden-Württemberg',
    'Bayern',
    'Berlin',
    'Brandenburg',
    'Bremen',
    'Hamburg',
    'Hessen',
    'Mecklenburg-Vorpommern',
    'Niedersachsen',
    'Nordrhein-Westfalen',
    'Rheinland-Pfalz',
    'Saarland',
    'Sachsen',
    'Sachsen-Anhalt',
    'Schleswig-Holstein',
    'Thüringen',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _weatherCity = prefs.getString('weather_city');
      _bundesland = prefs.getString('user_bundesland');
      _graduationYear = prefs.getInt('graduation_year');
      _classLevel = prefs.getInt('school_class_level') ?? 10;
    });
  }

  Future<void> _saveWeatherLocation(String city, double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weather_city', city);
    await prefs.setDouble('weather_lat', lat);
    await prefs.setDouble('weather_lon', lon);
    setState(() {
      _weatherCity = city;
    });
  }

  Future<void> _setClassLevel(int level) async {
    final oldSystem = _classLevel <= 10 ? 'marks' : 'points';
    final newSystem = level <= 10 ? 'marks' : 'points';

    if (oldSystem != newSystem && _classLevel != 10) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notensystem ändert sich'),
          content: Text(
            'Klasse $level verwendet ${level <= 10 ? "Noten (1-6)" : "Punkte (0-15)"}. '
            'Bestehende ${oldSystem == "marks" ? "Noten" : "Punkte"} werden archiviert.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fortfahren')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('school_class_level', level);
    await prefs.setString('grade_system', newSystem);
    setState(() {
      _classLevel = level;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return PageFadeIn(
          child: ListView(
          padding: const EdgeInsets.all(20),
          children: [

            AnimatedListItem(
              index: 0,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: AppTheme.gradientText('Einstellungen', fontSize: 36),
              ),
            ),

            AnimatedListItem(
              index: 1,
              child: _buildSectionTitle(context, 'Erscheinungsbild', Icons.palette),
            ),
            AnimatedListItem(
              index: 2,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(children: [
                _buildSwitchTile(
                  icon: Icons.dark_mode,
                  title: 'Dark Mode',
                  subtitle: provider.themeMode == ThemeMode.dark || (provider.themeSwitchMode == 'system' && isDark)
                      ? 'Aktiviert' : 'Deaktiviert',
                  value: provider.themeMode == ThemeMode.dark || (provider.themeSwitchMode == 'system' && isDark),
                  onChanged: provider.themeSwitchMode == 'manual' ? (_) => provider.toggleTheme() : null,
                  isDark: isDark,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.brightness_auto, color: AppTheme.primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Theme-Modus', style: Theme.of(context).textTheme.titleSmall),
                            Text(
                              provider.themeSwitchMode == 'manual' ? 'Manuell umschalten'
                                  : provider.themeSwitchMode == 'system' ? 'Folgt dem System'
                                  : 'Nach Zeitplan',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      _ThemeModeChip(
                        icon: Icons.touch_app,
                        label: 'Manuell',
                        isSelected: provider.themeSwitchMode == 'manual',
                        onTap: () => provider.setThemeSwitchMode('manual'),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _ThemeModeChip(
                        icon: Icons.phone_android,
                        label: 'System',
                        isSelected: provider.themeSwitchMode == 'system',
                        onTap: () => provider.setThemeSwitchMode('system'),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _ThemeModeChip(
                        icon: Icons.schedule,
                        label: 'Zeitplan',
                        isSelected: provider.themeSwitchMode == 'schedule',
                        onTap: () => provider.setThemeSwitchMode('schedule'),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
                if (provider.themeSwitchMode == 'schedule') ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ScheduleTimeButton(
                            icon: Icons.light_mode,
                            label: 'Light ab',
                            time: provider.scheduleLightTime,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: provider.scheduleLightTime,
                              );
                              if (picked != null) {
                                provider.setScheduleTimes(lightTime: picked);
                              }
                            },
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ScheduleTimeButton(
                            icon: Icons.dark_mode,
                            label: 'Dark ab',
                            time: provider.scheduleDarkTime,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: provider.scheduleDarkTime,
                              );
                              if (picked != null) {
                                provider.setScheduleTimes(darkTime: picked);
                              }
                            },
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ]),
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 3,
              child: _buildSectionTitle(context, 'Stundenplan', Icons.school),
            ),
            AnimatedListItem(
              index: 4,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(children: [
                _buildSwitchTile(
                  icon: Icons.swap_horiz,
                  title: 'A/B-Wochen',
                  subtitle: provider.abWeeksEnabled
                      ? 'Wechselnde Stundenpläne aktiv'
                      : 'Manche Schulen haben wechselnde A/B-Wochen',
                  value: provider.abWeeksEnabled,
                  onChanged: (value) => provider.setAbWeeksEnabled(value),
                  isDark: isDark,
                ),
                if (provider.abWeeksEnabled)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Du kannst im Schul-Tab zwischen A und B-Woche wechseln.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.grid_on, color: AppTheme.primaryColor, size: 20),
                  ),
                  title: const Text('Stundenplan konfigurieren'),
                  subtitle: const Text('Zeiten und Fächer einrichten'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TimetableConfigScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_fix_high, color: AppTheme.primaryLight, size: 20),
                  ),
                  title: const Text('Stundenraster-Assistent'),
                  subtitle: const Text('Zeiten neu konfigurieren'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const TimetableSetupWizard(),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 5,
              child: GlassCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                borderRadius: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.school, color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        const Text('Klassenstufe', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _classLevel,
                      decoration: InputDecoration(
                        labelText: 'Aktuelle Klasse',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: List.generate(9, (i) => i + 5).map((grade) {
                        final system = grade <= 10 ? 'Noten (1-6)' : 'Punkte (0-15)';
                        return DropdownMenuItem(
                          value: grade,
                          child: Text('Klasse $grade — $system'),
                        );
                      }).toList(),
                      onChanged: (v) { if (v != null) _setClassLevel(v); },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _classLevel <= 10 ? Icons.format_list_numbered : Icons.stars,
                          size: 14,
                          color: AppTheme.primaryColor.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _classLevel <= 10 ? 'Mittelstufe — einfacher Notendurchschnitt' : 'Oberstufe — 1/3 Klausur, 2/3 Sonstige',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.darkTextMuted
                                : AppTheme.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 6,
              child: _buildSectionTitle(context, 'Feiertage & Ferien', Icons.celebration),
            ),
            AnimatedListItem(
              index: 7,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.sage.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on, color: AppPalette.sage, size: 20),
                  ),
                  title: const Text('Bundesland'),
                  subtitle: Text(_bundesland ?? 'Nicht festgelegt'),
                  trailing: TextButton(
                    onPressed: () => _showBundeslandDialog(context),
                    child: const Text('Ändern'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.slate.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.school, color: AppPalette.slate, size: 20),
                  ),
                  title: const Text('Schulzeit bis'),
                  subtitle: Text(_graduationYear != null
                      ? '$_graduationYear (${_graduationYear! - DateTime.now().year} Jahre)'
                      : 'Nicht festgelegt'),
                  trailing: TextButton(
                    onPressed: () => _showGraduationYearDialog(context),
                    child: const Text('Ändern'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.terracotta.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.refresh, color: AppPalette.terracotta, size: 20),
                  ),
                  title: const Text('Feiertage aktualisieren'),
                  subtitle: const Text('Lade Feiertage und Ferien neu'),
                  trailing: _isImportingHolidays
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton(
                          onPressed: _bundesland != null ? () => _refreshHolidays(context) : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                          ),
                          child: const Text('Aktualisieren'),
                        ),
                ),
                if (_bundesland == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppPalette.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppPalette.amber.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: AppPalette.ochre),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Wähle zuerst ein Bundesland aus, um Feiertage zu importieren',
                              style: TextStyle(fontSize: 12, color: AppPalette.ochre),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ]),
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 8,
              child: _buildSectionTitle(context, 'Wetter', Icons.wb_sunny),
            ),
            AnimatedListItem(
              index: 9,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on, color: AppTheme.warning, size: 20),
                  ),
                  title: const Text('Standort'),
                  subtitle: Text(_weatherCity ?? 'Nicht festgelegt'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _showLocationDialog(context),
                        child: const Text('Ändern'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _autoDetectLocation(context),
                          icon: const Icon(Icons.my_location, size: 16),
                          label: const Text('Auto-erkennen'),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 10,
              child: _buildSectionTitle(context, 'IServ-Konto', Icons.school),
            ),
            AnimatedListItem(
              index: 11,
              child: Consumer<IServProvider>(
              builder: (context, iservProvider, child) {
                return GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 16,
                  child: Column(children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: iservProvider.isConnected
                              ? AppTheme.success.withValues(alpha: 0.1)
                              : AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          iservProvider.isConnected ? Icons.check_circle : Icons.link,
                          color: iservProvider.isConnected ? AppTheme.success : AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      title: Text(iservProvider.isConnected ? 'Verbunden' : 'Nicht verbunden'),
                      subtitle: Text(iservProvider.isConnected
                          ? 'IServ-Konto aktiv'
                          : 'Verbinde dein Schulkonto'),
                      trailing: iservProvider.isConnected
                          ? TextButton(
                              onPressed: () => _confirmDisconnectIServ(context, iservProvider),
                              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                              child: const Text('Trennen'),
                            )
                          : FilledButton(
                              onPressed: () => _showIServLoginDialog(context),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                              ),
                              child: const Text('Verbinden'),
                            ),
                    ),
                    if (iservProvider.isConnected) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildFeatureChip('Stundenplan', Icons.calendar_today),
                            _buildFeatureChip('E-Mail', Icons.email),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('IServ-Termine im Kalender'),
                        subtitle: const Text('IServ-Kalender in der App anzeigen'),
                        value: iservProvider.showIServInCalendar,
                        onChanged: (value) {
                          iservProvider.showIServInCalendar = value;
                        },
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppPalette.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.cloud_rounded,
                            color: AppPalette.amber,
                            size: 20,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppPalette.plum.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.school_outlined, color: AppPalette.plum, size: 20),
                        ),
                        title: const Text('Klassenstufe'),
                        subtitle: Text(iservProvider.userGrade != null
                            ? 'Klasse ${iservProvider.userGrade} — Filtert JGST-Termine'
                            : 'Nicht festgelegt'),
                        trailing: TextButton(
                          onPressed: () => _showGradeDialog(context, iservProvider),
                          child: Text(iservProvider.userGrade != null ? 'Ändern' : 'Einstellen'),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppPalette.slate.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.sync, color: AppPalette.slate, size: 20),
                        ),
                        title: Text('Termine: ${iservProvider.events.length} (${iservProvider.calendarEvents.length} im Kalender)'),
                        subtitle: Text(
                          iservProvider.lastSyncResult ?? 'Noch nicht synchronisiert',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: iservProvider.isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                onPressed: () => iservProvider.syncData(),
                                icon: const Icon(Icons.refresh, size: 20),
                              ),
                      ),
                      if (!kIsWeb && Platform.isMacOS) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.notifications_active, color: AppTheme.warning, size: 20),
                          ),
                          title: const Text('Test-Benachrichtigung'),
                          subtitle: Text(
                            NotificationService().permissionGranted
                                ? 'Berechtigung erteilt — macOS-Benachrichtigung testen'
                                : 'Keine Berechtigung — in System-Einstellungen erlauben',
                            style: TextStyle(
                              color: NotificationService().permissionGranted
                                  ? null
                                  : AppTheme.danger,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              final ns = NotificationService();
                              if (!ns.isInitialized) {
                                await ns.initialize();
                              }
                              if (!ns.permissionGranted) {
                                final granted = await ns.requestPermissions();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(granted
                                          ? 'Berechtigung erteilt!'
                                          : 'Berechtigung verweigert. Bitte in System-Einstellungen → Datenschutz & Sicherheit → Mitteilungen aktivieren.'),
                                      duration: const Duration(seconds: 5),
                                    ),
                                  );
                                }
                                return;
                              }
                              final status = await ns.getAuthorizationStatus();
                              if (kDebugMode) print('NotificationService status: $status');
                              final sent = await ns.showNotification(
                                id: 9999,
                                title: '${Brand.name} Benachrichtigung',
                                body: 'macOS-Benachrichtigungen funktionieren!',
                              );
                              if (context.mounted) {
                                final authStatus = status['status'] ?? -1;
                                final alertStyle = status['alertStyle'] ?? -1;
                                String msg;
                                if (!sent) {
                                  msg = 'Fehler beim Senden. Status=$authStatus, Style=$alertStyle';
                                } else if (alertStyle == 0) {
                                  msg = 'Gesendet, aber Stil ist "Keine" — System-Einstellungen → Mitteilungen → ${Brand.name} → "Banner" wählen';
                                } else {
                                  msg = 'Benachrichtigung gesendet! (Status=$authStatus, Style=$alertStyle)';
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(msg),
                                    duration: const Duration(seconds: 6),
                                  ),
                                );
                              }
                            },
                            child: const Text('Senden'),
                          ),
                        ),
                      ],
                    ],
                  ]),
                );
              },
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 12,
              child: _buildSectionTitle(context, 'Benachrichtigungen', Icons.notifications),
            ),
            AnimatedListItem(
              index: 13,
              child: _NotificationSettingsCard(isDark: isDark),
            ),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 14,
              child: _buildSectionTitle(context, 'Google-Konten', Icons.account_circle),
            ),
            AnimatedListItem(
              index: 15,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.slate.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.account_circle, color: AppPalette.slate, size: 20),
                  ),
                  title: const Text('Verbundene Konten'),
                  subtitle: const Text('Für Kalender & E-Mail'),
                  trailing: FilledButton.icon(
                    onPressed: () => _showGoogleConnectInfo(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Verbinden'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppPalette.amber.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppPalette.ochre),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Google-Konten werden bald unterstützt',
                            style: TextStyle(fontSize: 12, color: AppPalette.ochre),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 16,
              child: _buildSectionTitle(context, 'Daten', Icons.storage),
            ),
            AnimatedListItem(
              index: 17,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(children: [
                _buildSwitchTile(
                  icon: Icons.science_outlined,
                  title: 'Beispieldaten anzeigen',
                  subtitle: provider.demoMode ? 'Demo-Daten werden angezeigt' : 'Deine echten Daten werden angezeigt',
                  value: provider.demoMode,
                  onChanged: (value) async {
                    await provider.setDemoMode(value);
                    if (!value) await provider.refresh();
                  },
                  isDark: isDark,
                ),
                if (provider.demoMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppPalette.amber.withValues(alpha: 0.1),
                        border: Border.all(color: AppPalette.amber.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppPalette.ochre, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Im Demo-Modus werden Beispieldaten anstelle deiner echten Daten angezeigt. Deine Daten bleiben gespeichert.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.task_alt, color: AppTheme.primaryColor, size: 20),
                  ),
                  title: const Text('Aufgaben'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${provider.tasks.length}',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.event, color: AppTheme.primaryLight, size: 20),
                  ),
                  title: const Text('Termine'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${provider.events.length}',
                      style: TextStyle(
                        color: AppTheme.primaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.school, color: AppTheme.accentColor, size: 20),
                  ),
                  title: const Text('Stundenplan-Einträge'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${provider.lessons.length}',
                      style: TextStyle(
                        color: AppTheme.accentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 17,
              child: _buildSectionTitle(context, 'Tutorial', Icons.tour),
            ),
            AnimatedListItem(
              index: 17,
              child: GlassCard(
                padding: EdgeInsets.zero,
                borderRadius: 16,
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: AppTheme.primaryColor, size: 20),
                  ),
                  title: const Text('Tutorial starten'),
                  subtitle: const Text('Tinte zeigt dir in einer Minute, wo was ist.'),
                  onTap: Tutorial.start,
                ),
              ),
            ),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 18,
              child: _buildSectionTitle(context, 'Gefahrenzone', Icons.warning, isWarning: true),
            ),
            AnimatedListItem(
              index: 19,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              tint: AppTheme.danger.withValues(alpha: 0.05),
              child: Column(
                    children: [
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_sweep, color: AppTheme.warning, size: 20),
                        ),
                        title: const Text('Erledigte Aufgaben löschen'),
                        subtitle: const Text('Entfernt alle abgeschlossenen Aufgaben'),
                        onTap: () => _showDeleteCompletedDialog(context, provider),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_forever, color: AppTheme.danger, size: 20),
                        ),
                        title: const Text('Alle Daten löschen'),
                        subtitle: const Text('Setzt die App auf Werkseinstellungen zurück'),
                        onTap: () => _showResetDialog(context, provider),
                      ),
                    ],
                  ),
            )),
            const SizedBox(height: 20),

            AnimatedListItem(
              index: 20,
              child: _buildSectionTitle(context, 'Über ${Brand.name}', Icons.info),
            ),
            AnimatedListItem(
              index: 21,
              child: GlassCard(
              padding: EdgeInsets.zero,
              borderRadius: 16,
              child: Column(children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.hub, color: Colors.white, size: 20),
                  ),
                  title: const Text('Version'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '${BuildInfo.versionName} (Build ${BuildInfo.buildNumber})',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.plum.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.person, color: AppPalette.plum, size: 20),
                  ),
                  title: const Text('Entwickler'),
                  trailing: const Text('Leon Manuel Töpper'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.balance, color: AppPalette.teal, size: 20),
                  ),
                  title: const Text('Lizenz'),
                  subtitle: const Text('Quellcode offen einsehbar'),
                  trailing: const Text('AGPL-3.0'),
                  onTap: () => _launchUrl('${Brand.repository}/blob/main/LICENSE'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.ring.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.code, color: AppPalette.ring, size: 20),
                  ),
                  title: const Text('Quellcode'),
                  subtitle: const Text('Vollständiger Quellcode dieser Version'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launchUrl(Brand.repository),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Brand.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppPalette.inkDark : AppPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dein persönliches Organisations-Hub',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Zentralisiert. Zuverlässig. Effizient.',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            )),

            const SizedBox(height: 120),
          ],
        ),
        );
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        borderRadius: 10,
        blurSigma: 5,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isWarning ? AppTheme.danger : AppTheme.primaryColor,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isWarning ? AppTheme.danger : AppTheme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
    required bool isDark,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primaryColor, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.primaryColor,
        activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.3),
        inactiveThumbColor: isDark ? Colors.white38 : AppPalette.ring,
        inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _buildFeatureChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showLocationDialog(BuildContext context) {
    final controller = TextEditingController(text: _weatherCity ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Standort festlegen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Stadt',
            hintText: 'z.B. Berlin',
            prefixIcon: Icon(Icons.location_city),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              final city = controller.text.trim();
              if (city.isEmpty) return;

              try {
                final geoUrl = Uri.parse(
                  'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=de',
                );
                final response = await http.get(geoUrl);
                if (response.statusCode == 200) {
                  final data = jsonDecode(response.body);
                  final results = data['results'] as List?;
                  if (results != null && results.isNotEmpty) {
                    final lat = (results[0]['latitude'] as num).toDouble();
                    final lon = (results[0]['longitude'] as num).toDouble();
                    await _saveWeatherLocation(city, lat, lon);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stadt nicht gefunden')),
                      );
                    }
                    return;
                  }
                } else {
                  await _saveWeatherLocation(city, 52.52, 13.41);
                }
              } catch (_) {
                await _saveWeatherLocation(city, 52.52, 13.41);
              }
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Standort gesetzt: $city')),
                );
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _autoDetectLocation(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Standort-Erkennung wird bald unterstützt')),
    );
  }

  void _showIServLoginDialog(BuildContext context) {
    final urlController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final screenContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mit IServ verbinden'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gib deine IServ-URL und Anmeldedaten ein, oder nutze den WebView-Login.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'IServ-URL',
                  hintText: 'z.B. gymnasium-berlin.de',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Benutzername',
                  prefixIcon: Icon(Icons.person),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _directIServLogin(
                  dialogContext,
                  screenContext,
                  urlController.text.trim(),
                  usernameController.text.trim(),
                  passwordController.text,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty) return;
              Navigator.pop(dialogContext);
              _startWebViewLogin(screenContext, url);
            },
            child: const Text('WebView Login'),
          ),
          FilledButton(
            onPressed: () => _directIServLogin(
              dialogContext,
              screenContext,
              urlController.text.trim(),
              usernameController.text.trim(),
              passwordController.text,
            ),
            child: const Text('Anmelden'),
          ),
        ],
      ),
    ).then((_) {
      urlController.dispose();
      usernameController.dispose();
      passwordController.dispose();
    });
  }

  Future<void> _directIServLogin(BuildContext dialogContext, BuildContext screenContext, String url, String username, String password) async {
    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(screenContext).showSnackBar(
        const SnackBar(
          content: Text('Bitte alle Felder ausfüllen'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    Navigator.pop(dialogContext);

    if (!mounted) return;
    final provider = screenContext.read<IServProvider>();
    final result = await provider.connect(
      username: username,
      password: password,
      iservUrl: url,
    );

    if (!mounted) return;
    if (screenContext.mounted) {
      if (result['success'] == true) {
        ScaffoldMessenger.of(screenContext).showSnackBar(
          const SnackBar(content: Text('IServ erfolgreich verbunden')),
        );
      } else {
        ScaffoldMessenger.of(screenContext).showSnackBar(
          SnackBar(content: Text(result['error'] ?? 'Anmeldung fehlgeschlagen')),
        );
      }
    }
  }

  void _startWebViewLogin(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => IServWebViewLogin(
          iservUrl: url,
          onLoginSuccess: (cookies, username) async {
            Navigator.of(context).pop();
            final provider = context.read<IServProvider>();
            final result = await provider.connectWithWebViewCookies(
              iservUrl: url,
              cookies: cookies,
              username: username,
            );
            if (context.mounted) {
              if (result['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('IServ erfolgreich verbunden')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result['error'] ?? 'Anmeldung fehlgeschlagen')),
                );
              }
            }
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _confirmDisconnectIServ(BuildContext context, IServProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('IServ trennen?'),
        content: const Text('Möchtest du die Verbindung zu IServ wirklich trennen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              provider.disconnect();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('IServ getrennt')),
              );
            },
            child: const Text('Trennen'),
          ),
        ],
      ),
    );
  }

  void _showGoogleConnectInfo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google-Konten werden bald unterstützt')),
    );
  }

  void _showDeleteCompletedDialog(BuildContext context, AppProvider provider) {
    final completedTasks = provider.tasks.where((t) => t.completed).toList();

    if (completedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine erledigten Aufgaben vorhanden')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erledigte Aufgaben löschen?'),
        content: Text('Möchtest du ${completedTasks.length} erledigte Aufgaben endgültig löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
            onPressed: () async {
              Navigator.pop(context);
              for (final task in completedTasks) {
                await provider.deleteTask(task.id);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${completedTasks.length} Aufgaben gelöscht')),
                );
              }
            },
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  void _showResetDialog(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alle Daten löschen?'),
        content: const Text(
          'Dies kann nicht rückgängig gemacht werden. '
          'Alle Aufgaben, Termine und Stundenplan-Einträge werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              Navigator.pop(context);

              for (final task in List.from(provider.tasks)) {
                await provider.deleteTask(task.id);
              }
              for (final event in List.from(provider.events)) {
                await provider.deleteEvent(event.id);
              }
              for (final lesson in List.from(provider.lessons)) {
                await provider.deleteLesson(lesson.id);
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Alle Daten wurden gelöscht')),
                );
              }
            },
            child: const Text('Alle Daten löschen'),
          ),
        ],
      ),
    );
  }

  void _showBundeslandDialog(BuildContext context) {
    String? selected = _bundesland;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bundesland auswählen'),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _bundeslaender.length,
              itemBuilder: (context, index) {
                final bundesland = _bundeslaender[index];
                final isSelected = selected == bundesland;

                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      bundesland,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? AppTheme.primaryColor : null,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 20)
                        : null,
                    onTap: () => setDialogState(() => selected = bundesland),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected != null
                  ? () async {
                      Navigator.pop(context);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('user_bundesland', selected!);
                      setState(() => _bundesland = selected);

                      if (context.mounted) {
                        _showRefreshHolidaysPrompt(context);
                      }
                    }
                  : null,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGraduationYearDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int? selected = _graduationYear;
    final currentYear = DateTime.now().year;
    final years = List.generate(11, (i) => currentYear + i);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Schulzeit bis'),
              const SizedBox(height: 8),
              Text(
                'Ferien und Feiertage werden bis zu den Sommerferien dieses Jahres importiert.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: years.length,
              itemBuilder: (context, index) {
                final year = years[index];
                final isSelected = selected == year;
                final yearsFromNow = year - currentYear;
                final label = yearsFromNow == 0
                    ? 'Dieses Jahr'
                    : yearsFromNow == 1
                        ? 'Nächstes Jahr'
                        : 'In $yearsFromNow Jahren';

                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : Colors.transparent,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor.withValues(alpha: 0.2)
                            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.school,
                          size: 18,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : (isDark ? Colors.white54 : Colors.black38),
                        ),
                      ),
                    ),
                    title: Text(
                      '$year',
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? AppTheme.primaryColor : null,
                      ),
                    ),
                    subtitle: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 20)
                        : null,
                    onTap: () => setDialogState(() => selected = year),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected != null
                  ? () async {
                      Navigator.pop(context);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('graduation_year', selected!);
                      setState(() => _graduationYear = selected);

                      if (context.mounted) {
                        _showRefreshHolidaysPrompt(context);
                      }
                    }
                  : null,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  void _showGradeDialog(BuildContext context, IServProvider iservProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int? selected = iservProvider.userGrade;
    bool autoIncrement = iservProvider.gradeAutoIncrement;
    final grades = List.generate(9, (i) => i + 5);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Klassenstufe'),
              const SizedBox(height: 8),
              Text(
                'Termine anderer Jahrgangsstufen (JGST) werden aus dem Kalender gefiltert.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: grades.length,
                    itemBuilder: (context, index) {
                      final grade = grades[index];
                      final isSelected = selected == grade;
                      final label = grade <= 10
                          ? 'Klasse $grade'
                          : grade == 11
                              ? 'Qualifikationsphase (Q1/Q2)'
                              : grade == 12
                                  ? 'Qualifikationsphase (Q3/Q4)'
                                  : 'Klasse 13';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryColor.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryColor.withValues(alpha: 0.2)
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '$grade',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isSelected
                                      ? AppTheme.primaryColor
                                      : (isDark ? Colors.white54 : Colors.black38),
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            label,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              color: isSelected ? AppTheme.primaryColor : null,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 20)
                              : null,
                          onTap: () => setDialogState(() => selected = grade),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Automatisch hochstufen', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      'Jedes Schuljahr (August) +1',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45),
                    ),
                    value: autoIncrement,
                    onChanged: (v) => setDialogState(() => autoIncrement = v),
                    activeThumbColor: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (selected != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  iservProvider.setUserGrade(null);
                  iservProvider.setGradeAutoIncrement(autoIncrement);
                },
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                child: const Text('Zurücksetzen'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected != null
                  ? () {
                      Navigator.pop(context);
                      iservProvider.setUserGrade(selected);
                      iservProvider.setGradeAutoIncrement(autoIncrement);
                    }
                  : null,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRefreshHolidaysPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feiertage aktualisieren?'),
        content: const Text(
          'Möchtest du die Feiertage und Ferien neu importieren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Später'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _refreshHolidays(context);
            },
            child: const Text('Ja, importieren'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshHolidays(BuildContext context) async {
    setState(() => _isImportingHolidays = true);

    try {
      final holidayService = HolidayService();
      await holidayService.refreshHolidays();

      if (context.mounted) {
        context.read<AppProvider>().refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feiertage und Ferien wurden importiert'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Importieren. Bitte versuche es erneut.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImportingHolidays = false);
      }
    }
  }
}

class _NotificationSettingsCard extends StatefulWidget {
  final bool isDark;
  const _NotificationSettingsCard({required this.isDark});

  @override
  State<_NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends State<_NotificationSettingsCard> {
  bool _masterToggle = true;
  bool _calendarEnabled = true;
  bool _tasksEnabled = true;
  bool _homeworkEnabled = true;
  bool _schoolEnabled = true;
  bool _trainingEnabled = true;
  bool _pomodoroEnabled = true;
  bool _testsEnabled = true;
  int _homeworkLeadDays = 1;
  int _schoolLeadMinutes = 10;
  int _trainingLeadMinutes = 15;
  int _testsLeadDays = 1;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _masterToggle = prefs.getBool('notif_master') ?? true;
      _calendarEnabled = prefs.getBool('notif_calendar') ?? true;
      _tasksEnabled = prefs.getBool('notif_tasks') ?? true;
      _homeworkEnabled = prefs.getBool('notif_homework') ?? true;
      _schoolEnabled = prefs.getBool('notif_school') ?? true;
      _trainingEnabled = prefs.getBool('notif_training') ?? true;
      _pomodoroEnabled = prefs.getBool('notif_pomodoro') ?? true;
      _testsEnabled = prefs.getBool('notif_tests') ?? true;
      _homeworkLeadDays = prefs.getInt('notif_homework_lead') ?? 1;
      _schoolLeadMinutes = prefs.getInt('notif_school_lead') ?? 10;
      _trainingLeadMinutes = prefs.getInt('notif_training_lead') ?? 15;
      _testsLeadDays = prefs.getInt('notif_tests_lead') ?? 1;
      _quietStart = TimeOfDay(
        hour: prefs.getInt('notif_quiet_start_h') ?? 22,
        minute: prefs.getInt('notif_quiet_start_m') ?? 0,
      );
      _quietEnd = TimeOfDay(
        hour: prefs.getInt('notif_quiet_end_h') ?? 7,
        minute: prefs.getInt('notif_quiet_end_m') ?? 0,
      );
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is int) await prefs.setInt(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      child: Column(
        children: [
          SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.notifications, color: AppTheme.primaryColor, size: 20),
            ),
            title: const Text('Benachrichtigungen'),
            subtitle: Text(_masterToggle ? 'Aktiviert' : 'Deaktiviert'),
            value: _masterToggle,
            onChanged: (v) {
              setState(() => _masterToggle = v);
              _save('notif_master', v);
            },
            activeThumbColor: AppTheme.primaryColor,
            activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.3),
          ),

          if (_masterToggle) ...[
            const Divider(height: 1),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalette.iris.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.do_not_disturb, color: AppPalette.iris, size: 20),
              ),
              title: const Text('Ruhezeitraum'),
              subtitle: Text(
                '${_quietStart.hour.toString().padLeft(2, '0')}:${_quietStart.minute.toString().padLeft(2, '0')} '
                '— ${_quietEnd.hour.toString().padLeft(2, '0')}:${_quietEnd.minute.toString().padLeft(2, '0')}',
              ),
              trailing: TextButton(
                onPressed: () async {
                  final start = await showTimePicker(context: context, initialTime: _quietStart);
                  if (start == null) return;
                  if (!context.mounted) return;
                  final end = await showTimePicker(context: context, initialTime: _quietEnd);
                  if (end == null) return;
                  if (!mounted) return;
                  setState(() {
                    _quietStart = start;
                    _quietEnd = end;
                  });
                  _save('notif_quiet_start_h', start.hour);
                  _save('notif_quiet_start_m', start.minute);
                  _save('notif_quiet_end_h', end.hour);
                  _save('notif_quiet_end_m', end.minute);
                },
                child: const Text('Ändern'),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kategorien',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
            ),

            _buildCategoryToggle('Kalender', 'Erinnerungen vor Terminen', _calendarEnabled, (v) {
              setState(() => _calendarEnabled = v);
              _save('notif_calendar', v);
            }),
            _buildCategoryToggle('Aufgaben', 'Fällige und überfällige Aufgaben', _tasksEnabled, (v) {
              setState(() => _tasksEnabled = v);
              _save('notif_tasks', v);
            }),
            _buildCategoryToggleWithLead(
              'Hausaufgaben', 'Erinnerung vor Abgabe', _homeworkEnabled,
              (v) { setState(() => _homeworkEnabled = v); _save('notif_homework', v); },
              _homeworkLeadDays, 'Tage', 0, 30,
              (v) { setState(() => _homeworkLeadDays = v); _save('notif_homework_lead', v); },
            ),
            _buildCategoryToggleWithLead(
              'Stundenplan', 'Nächste Unterrichtsstunde', _schoolEnabled,
              (v) { setState(() => _schoolEnabled = v); _save('notif_school', v); },
              _schoolLeadMinutes, 'Min', 1, 60,
              (v) { setState(() => _schoolLeadMinutes = v); _save('notif_school_lead', v); },
            ),
            _buildCategoryToggleWithLead(
              'Training', 'Geplante Trainingseinheiten', _trainingEnabled,
              (v) { setState(() => _trainingEnabled = v); _save('notif_training', v); },
              _trainingLeadMinutes, 'Min', 1, 120,
              (v) { setState(() => _trainingLeadMinutes = v); _save('notif_training_lead', v); },
            ),
            _buildCategoryToggle('Pomodoro', 'Arbeits-/Pausenphase beendet', _pomodoroEnabled, (v) {
              setState(() => _pomodoroEnabled = v);
              _save('notif_pomodoro', v);
            }),
            _buildCategoryToggleWithLead(
              'Klausuren & Tests', 'Erinnerung vor Prüfungen', _testsEnabled,
              (v) { setState(() => _testsEnabled = v); _save('notif_tests', v); },
              _testsLeadDays, 'Tage', 0, 30,
              (v) { setState(() => _testsLeadDays = v); _save('notif_tests_lead', v); },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppTheme.primaryColor,
      dense: true,
    );
  }

  Widget _buildCategoryToggleWithLead(
    String title, String subtitle, bool value, ValueChanged<bool> onToggle,
    int leadValue, String leadUnit, int leadMin, int leadMax, ValueChanged<int> onLeadChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white54 : Colors.black45)),
              ],
            ),
          ),
          if (value)
            SizedBox(
              width: 56,
              height: 32,
              child: TextFormField(
                key: ValueKey('lead_$title'),
                initialValue: '$leadValue',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixText: leadUnit,
                  suffixStyle: const TextStyle(fontSize: 10),
                  isDense: true,
                ),
                onChanged: (s) {
                  final v = int.tryParse(s);
                  if (v != null && v >= leadMin && v <= leadMax) onLeadChanged(v);
                },
              ),
            ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onToggle,
            activeThumbColor: AppTheme.primaryColor,
            activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _ThemeModeChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primaryColor.withValues(alpha: 0.15)
                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? AppTheme.primaryColor
                    : (isDark ? Colors.white54 : Colors.black45),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : (isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleTimeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool isDark;

  const _ScheduleTimeButton({
    required this.icon,
    required this.label,
    required this.time,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isDark ? Colors.white60 : Colors.black54),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

