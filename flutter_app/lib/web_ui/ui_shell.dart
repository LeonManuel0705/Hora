// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show showWelcomeSetup;
import '../providers/app_provider.dart';
import '../providers/iserv_provider.dart';
import '../screens/assistant_screen.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/review_screen.dart';
import '../screens/training_screen.dart';
import '../services/holiday_service.dart';
import 'ui_api.dart';

class UiNativePage {
  const UiNativePage(this.title, this.build, {this.reload = false});

  final String title;
  final Widget Function() build;
  final bool reload;
}

final uiNativePages = <String, UiNativePage>{
  'assistant': UiNativePage('Assistent', () => const AssistantScreen(), reload: true),
  'pomodoro': UiNativePage('Pomodoro', () => const PomodoroScreen(), reload: true),
  'training': UiNativePage('Training', () => const TrainingScreen()),
  'bookmarks': UiNativePage('Lesezeichen', () => const BookmarksScreen()),
  'review': UiNativePage('Review', () => const ReviewScreen()),
};

mixin UiShellHost<T extends StatefulWidget> on State<T> implements UiHost {
  final Set<String> _changes = {};
  Timer? _changeTimer;

  Future<void> reloadPage();

  Future<R?> overPage<R>(Future<R?> Function() show) => show();

  void disposeHost() => _changeTimer?.cancel();

  Future<void> openNativePage(UiNativePage page) async {
    await overPage(() => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (context) {
            final dark = Theme.of(context).brightness == Brightness.dark;
            return Semantics(
              label: page.title,
              explicitChildNodes: true,
              child: Scaffold(
                appBar: AppBar(
                  systemOverlayStyle: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: Colors.transparent,
                    systemNavigationBarContrastEnforced: false,
                  ),
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                ),
                body: SafeArea(top: false, child: page.build()),
              ),
            );
          },
        )));
    if (page.reload && mounted) await reloadPage();
  }

  Future<void> welcomeOrHolidays() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (!prefs.containsKey('user_bundesland')) {
      final result = await overPage(() => showWelcomeSetup(context, withDemo: false));
      if (result != null) {
        await prefs.setString('user_bundesland', result.bundesland);
        await prefs.setInt('graduation_year', result.graduationYear);
        try {
          await HolidayService().importHolidays();
        } catch (_) {}
        if (mounted) {
          unawaited(context.read<AppProvider>().loadEvents());
          await reloadPage();
        }
      }
    } else {
      unawaited(_importHolidaysIfNeeded());
    }
  }

  Future<void> _importHolidaysIfNeeded() async {
    try {
      final service = HolidayService();
      if (await service.hasImportedHolidays()) return;
      final events = await service.importHolidays();
      if (events.isNotEmpty && mounted) {
        unawaited(context.read<AppProvider>().loadEvents());
        await reloadPage();
      }
    } catch (_) {}
  }

  @override
  Future<Map<String, Object?>> connectIserv(String url, String user, String password) async {
    final result = await context.read<IServProvider>().connect(username: user, password: password, iservUrl: url);
    return result.cast<String, Object?>();
  }

  @override
  Future<void> disconnectIserv() => context.read<IServProvider>().disconnect();

  @override
  Map<String, Object?> iservStatus() {
    final provider = context.read<IServProvider>();
    return {'connected': provider.isConnected, 'has_credentials': provider.isConnected || provider.username != null};
  }

  @override
  Future<int> changeState(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_bundesland', name);
    final events = await HolidayService().refreshHolidays();
    return events.length;
  }

  @override
  Future<void> themeChoice(String? choice) async {
    final provider = context.read<AppProvider>();
    if (choice == null) {
      await provider.setThemeSwitchMode('system');
      return;
    }
    await provider.setThemeSwitchMode('manual');
    await provider.setThemeMode(choice == 'dark' ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  void dataChanged(String area) {
    _changes.add(area);
    _changeTimer?.cancel();
    _changeTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      final areas = Set<String>.of(_changes);
      _changes.clear();
      if (areas.contains('tasks')) unawaited(provider.loadTasks());
      if (areas.contains('events')) unawaited(provider.loadEvents());
      if (areas.contains('school')) unawaited(provider.loadLessons());
    });
  }
}
