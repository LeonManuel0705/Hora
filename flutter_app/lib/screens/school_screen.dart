// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_provider.dart';
import '../providers/iserv_provider.dart';
import '../models/lesson.dart';
import '../models/timetable_period.dart';
import '../services/database_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/iserv_webview_login.dart';
import '../widgets/page_fade_in.dart';
import '../widgets/timetable_setup_wizard.dart';

Color _parseColor(dynamic colorValue, [Color fallback = AppPalette.ring]) {
  if (colorValue == null) return fallback;
  try {
    final str = colorValue as String;
    return Color(int.parse(str.replaceFirst('#', '0xFF')));
  } catch (_) {
    return fallback;
  }
}

const _markOptions = [
  {'label': '1+', 'value': 0.7},
  {'label': '1', 'value': 1.0},
  {'label': '1-', 'value': 1.3},
  {'label': '2+', 'value': 1.7},
  {'label': '2', 'value': 2.0},
  {'label': '2-', 'value': 2.3},
  {'label': '3+', 'value': 2.7},
  {'label': '3', 'value': 3.0},
  {'label': '3-', 'value': 3.3},
  {'label': '4+', 'value': 3.7},
  {'label': '4', 'value': 4.0},
  {'label': '4-', 'value': 4.3},
  {'label': '5+', 'value': 4.7},
  {'label': '5', 'value': 5.0},
  {'label': '5-', 'value': 5.3},
  {'label': '6', 'value': 6.0},
];

String _markValueToLabel(double value) {
  for (final o in _markOptions) {
    if (((o['value'] as double) - value).abs() < 0.05) return o['label'] as String;
  }
  return value.toStringAsFixed(1);
}

Color _getMarkColor(double value) {
  if (value <= 1.3) return AppTheme.success;
  if (value <= 2.3) return AppPalette.moss;
  if (value <= 3.3) return AppPalette.amber;
  if (value <= 4.3) return AppTheme.warning;
  return AppTheme.danger;
}

class SchoolScreen extends StatefulWidget {
  const SchoolScreen({super.key});

  @override
  State<SchoolScreen> createState() => _SchoolScreenState();
}

class _SchoolScreenState extends State<SchoolScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  bool _weekToggled = false;
  bool? _lastKnownInversion;
  int _selectedSubTab = 0;
  int _previousSubTab = 0;
  final DatabaseService _db = DatabaseService();

  late AnimationController _tabTransitionController;

  final List<String> _subTabs = ['Stundenplan', 'Fächer', 'Hausaufgaben', 'Tests', 'Klausuren', 'Noten', 'IServ'];
  final List<String> _days = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
  final List<String> _daysFull = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag'];

  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _homework = [];
  List<Map<String, dynamic>> _tests = [];
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _grades = [];
  bool _isLoading = true;
  String _gradeSystem = 'points';
  int _classLevel = 10;
  bool _iservLoggingIn = false;
  String? _iservLoginError;

  final PageController _vertretungsplanPageController = PageController();
  int _currentVertretungsplanPage = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _loadAllData();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<AppProvider>();
      await provider.loadTimetablePeriods();
      if (!provider.timetableSetupCompleted && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const TimetableSetupWizard(),
        );
        if (mounted) {
          await _loadAllData();
        }
      }
    });
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _classLevel = prefs.getInt('school_class_level') ?? 10;
      _gradeSystem = _classLevel <= 10 ? 'marks' : 'points';
      _subjects = await _db.getSubjects();

      if (!mounted) return;
      final provider = context.read<AppProvider>();
      final existingNames = _subjects.map((s) => s['name'] as String).toSet();
      final seenNames = <String>{};
      for (final lesson in provider.lessons) {
        final name = lesson.subject.trim();
        if (name.isNotEmpty && !existingNames.contains(name) && seenNames.add(name)) {
          await _db.insertSubject(
            name: name,
            teacher: lesson.teacher,
            room: lesson.room,
            color: lesson.color,
          );
        }
      }
      if (seenNames.isNotEmpty) {
        _subjects = await _db.getSubjects();
      }

      _homework = await _db.getHomework();
      await _loadTests();
      await _loadExams();
      await _loadGrades();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTests() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tests (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subject_id INTEGER,
        date TEXT,
        notes TEXT,
        grade TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    _tests = await db.rawQuery('''
      SELECT t.*, s.name as subject_name, s.color as subject_color
      FROM tests t
      LEFT JOIN subjects s ON t.subject_id = s.id
      ORDER BY t.date ASC
    ''');
  }

  Future<void> _loadExams() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exams (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subject_id INTEGER,
        date TEXT,
        notes TEXT,
        grade TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    _exams = await db.rawQuery('''
      SELECT e.*, s.name as subject_name, s.color as subject_color
      FROM exams e
      LEFT JOIN subjects s ON e.subject_id = s.id
      ORDER BY e.date ASC
    ''');
  }

  Future<void> _loadGrades() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grades (
        id TEXT PRIMARY KEY,
        subject_id INTEGER NOT NULL,
        semester TEXT NOT NULL,
        type TEXT NOT NULL,
        points INTEGER NOT NULL,
        notes TEXT,
        date TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    try { await db.execute('ALTER TABLE grades ADD COLUMN grade_system TEXT DEFAULT \'points\''); } catch (_) {}
    try { await db.execute('ALTER TABLE grades ADD COLUMN value REAL'); } catch (_) {}
    try { await db.execute('ALTER TABLE subjects ADD COLUMN course_type TEXT'); } catch (_) {}
    _grades = await db.rawQuery('''
      SELECT g.*, s.name as subject_name, s.color as subject_color, s.course_type as course_type
      FROM grades g
      LEFT JOIN subjects s ON g.subject_id = s.id
      ORDER BY g.date DESC
    ''');
  }

  bool _displayedIsAWeek(AppProvider provider) {
    final baseIsAWeek = provider.isCurrentlyAWeek();
    return _weekToggled ? !baseIsAWeek : baseIsAWeek;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tabTransitionController.dispose();
    _vertretungsplanPageController.dispose();
    super.dispose();
  }

  void _switchTab(int newIndex) async {
    if (newIndex == _selectedSubTab) return;
    _previousSubTab = _selectedSubTab;

    await _tabTransitionController.animateTo(0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeIn,
    );
    if (!mounted) return;

    setState(() => _selectedSubTab = newIndex);

    await _tabTransitionController.animateTo(1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        if (_lastKnownInversion != null && _lastKnownInversion != provider.abWeekInverted) {
          _weekToggled = false;
        }
        _lastKnownInversion = provider.abWeekInverted;

        return PageFadeIn(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTheme.gradientText('Schule', fontSize: 36),
                      ),
                      if (provider.abWeeksEnabled)
                        GestureDetector(
                          onTap: () => setState(() => _weekToggled = !_weekToggled),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _displayedIsAWeek(provider) ? AppTheme.primaryColor : AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _displayedIsAWeek(provider) ? 'A' : 'B',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Woche',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_subTabs.length, (index) {
                        final isSelected = _selectedSubTab == index;
                        return Padding(
                          padding: EdgeInsets.only(right: index < _subTabs.length - 1 ? 8 : 0),
                          child: _TabChip(
                            label: _subTabs[index],
                            isSelected: isSelected,
                            onTap: () => _switchTab(index),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : AnimatedBuilder(
                      animation: _tabTransitionController,
                      builder: (context, child) {
                        final t = _tabTransitionController.value;
                        final slideDir = _selectedSubTab >= _previousSubTab ? 1.0 : -1.0;
                        return Opacity(
                          opacity: t.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(20 * (1 - t) * slideDir, 0),
                            child: child,
                          ),
                        );
                      },
                      child: _buildSubTabContent(provider, isDark),
                    ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget _buildSubTabContent(AppProvider provider, bool isDark) {
    switch (_selectedSubTab) {
      case 0:
        return _buildStundenplanTab(provider, isDark);
      case 1:
        return _buildSubjectsTab(isDark);
      case 2:
        return _buildHomeworkTab(isDark);
      case 3:
        return _buildTestsTab(isDark);
      case 4:
        return _buildExamsTab(isDark);
      case 5:
        return _buildGradesTab(isDark);
      case 6:
        return _buildIServTab(isDark);
      default:
        return _buildStundenplanTab(provider, isDark);
    }
  }

  Widget _buildStundenplanTab(AppProvider provider, bool isDark) {
    return Column(
      children: [
        GlassCard(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          padding: EdgeInsets.zero,
          borderRadius: 12,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Heute'),
              Tab(text: 'Morgen'),
              Tab(text: 'Woche'),
            ],
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            indicatorColor: AppTheme.primaryColor,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDaySchedule(provider, _getTodayWeekday(), 'Heute', isDark),
              _buildDaySchedule(provider, _getTomorrowWeekday(), 'Morgen', isDark),
              _buildWeekOverview(provider, isDark),
            ],
          ),
        ),
      ],
    );
  }

  int _getTodayWeekday() {
    final today = DateTime.now().weekday;
    return today <= 5 ? today : 1;
  }

  int _getTomorrowWeekday() {
    final tomorrow = (DateTime.now().weekday % 7) + 1;
    if (tomorrow > 5) return 1;
    return tomorrow;
  }

  bool _isTomorrowNextWeek() {
    final today = DateTime.now().weekday;
    return today >= 5;
  }

  Widget _buildDaySchedule(AppProvider provider, int dayOfWeek, String dayLabel, bool isDark) {
    final now = DateTime.now();
    final isToday = dayLabel == 'Heute';

    final displayed = _displayedIsAWeek(provider);
    final showsNextWeek = (dayLabel == 'Morgen' && _isTomorrowNextWeek()) || (isToday && now.weekday > 5);
    String currentWeekType;
    if (showsNextWeek) {
      currentWeekType = displayed ? 'B' : 'A';
    } else {
      currentWeekType = displayed ? 'A' : 'B';
    }

    final lessonsForDay = provider.lessons
        .where((l) => l.dayOfWeek == dayOfWeek)
        .where((l) => !provider.abWeeksEnabled || l.weekType == 'both' || l.weekType == currentWeekType)
        .toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));

    return RefreshIndicator(
      onRefresh: () async {
        await provider.refresh();
        await _loadAllData();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          if (isToday && DateTime.now().weekday > 5) ...[
            GlassCard(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              padding: const EdgeInsets.all(16),
              borderRadius: 12,
              child: Row(
                children: [
                  Icon(Icons.weekend_rounded, color: AppTheme.primaryColor, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wochenende',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: isDark ? AppTheme.darkText : AppTheme.lightText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hier siehst du den Plan für nächsten Montag.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isToday && lessonsForDay.isNotEmpty && DateTime.now().weekday <= 5) ...[
            _buildCurrentLessonCard(lessonsForDay, now, isDark),
            const SizedBox(height: 16),
          ],
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _daysFull[dayOfWeek - 1],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${lessonsForDay.length} Stunden',
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (lessonsForDay.isEmpty)
            _buildEmptyDayState(context, isDark, dayOfWeek)
          else ...[
            ...lessonsForDay.map((lesson) => _LessonCard(
              lesson: lesson,
              onDelete: () => provider.deleteLesson(lesson.id),
              onEdit: () => _showEditLessonDialog(context, lesson),
              isCurrentLesson: isToday && _isCurrentLesson(lesson, now),
            )),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => showAddLessonDialog(context, dayOfWeek: dayOfWeek, abWeeksEnabled: provider.abWeeksEnabled),
                icon: const Icon(Icons.add),
                label: const Text('Weitere Stunde hinzufügen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildCurrentLessonCard(List<Lesson> lessons, DateTime now, bool isDark) {
    Lesson? currentLesson;
    Lesson? nextLesson;

    for (int i = 0; i < lessons.length; i++) {
      if (_isCurrentLesson(lessons[i], now)) {
        currentLesson = lessons[i];
        if (i + 1 < lessons.length) {
          nextLesson = lessons[i + 1];
        }
        break;
      }
    }

    if (currentLesson == null) {
      for (final lesson in lessons) {
        final startParts = lesson.startTime.split(':');
        final lessonStart = DateTime(now.year, now.month, now.day,
            int.parse(startParts[0]), int.parse(startParts[1]));
        if (lessonStart.isAfter(now)) {
          nextLesson = lesson;
          break;
        }
      }
    }

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      tint: currentLesson != null ? AppTheme.primaryColor : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: currentLesson != null ? Colors.greenAccent : AppTheme.warning,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (currentLesson != null ? Colors.greenAccent : AppTheme.warning).withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currentLesson != null ? 'Aktuell' : 'Nächste Stunde',
                style: TextStyle(
                  color: currentLesson != null ? Colors.white70 : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (currentLesson != null) ...[
            Text(
              currentLesson.subject,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${currentLesson.timeRange}${currentLesson.room != null ? ' • Raum ${currentLesson.room}' : ''}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            if (nextLesson != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.arrow_forward, size: 14, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      'Danach: ${nextLesson.subject}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (nextLesson != null) ...[
            Text(
              nextLesson.subject,
              style: TextStyle(
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Beginnt um ${nextLesson.startTime}${nextLesson.room != null ? ' • Raum ${nextLesson.room}' : ''}',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 13,
              ),
            ),
          ] else ...[
            Text(
              'Keine weiteren Stunden heute',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                fontSize: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isCurrentLesson(Lesson lesson, DateTime now) {
    final startParts = lesson.startTime.split(':');
    final endParts = lesson.endTime.split(':');

    final lessonStart = DateTime(now.year, now.month, now.day,
        int.parse(startParts[0]), int.parse(startParts[1]));
    final lessonEnd = DateTime(now.year, now.month, now.day,
        int.parse(endParts[0]), int.parse(endParts[1]));

    return now.isAfter(lessonStart) && now.isBefore(lessonEnd);
  }

  Widget _buildWeekOverview(AppProvider provider, bool isDark) {
    final periods = provider.timetablePeriods
        .map((m) => TimetablePeriod.fromMap(m))
        .toList()
      ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));

    if (periods.isEmpty) {
      return _buildEmptyPeriodsState(isDark);
    }

    final currentWeekType = _displayedIsAWeek(provider) ? 'A' : 'B';
    final abWeeksEnabled = provider.abWeeksEnabled;

    return Column(
      children: [
        if (abWeeksEnabled)
          GlassCard(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            borderRadius: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Woche: ',
                  style: TextStyle(
                    color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                _buildGlassWeekToggle(isDark, provider),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildTimetableGrid(provider, periods, currentWeekType, abWeeksEnabled, isDark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassWeekToggle(bool isDark, AppProvider provider) {
    return GlassContainer(
      borderRadius: 10,
      blurSigma: 8,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildWeekToggleButton('A', true, isDark, provider),
          _buildWeekToggleButton('B', false, isDark, provider),
        ],
      ),
    );
  }

  Widget _buildWeekToggleButton(String label, bool isAWeekButton, bool isDark, AppProvider provider) {
    final isSelected = _displayedIsAWeek(provider) == isAWeekButton;
    return GestureDetector(
      onTap: () => setState(() => _weekToggled = (isAWeekButton != provider.isCurrentlyAWeek())),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [AppTheme.primaryColor, AppTheme.primaryColor])
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black54),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPeriodsState(bool isDark) {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.all(32),
        borderRadius: 20,
        child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.schedule_outlined,
                    size: 48,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Keine Unterrichtszeiten',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Konfiguriere zuerst deine Schulstunden',
                  style: TextStyle(
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/timetable-config');
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Zeiten konfigurieren'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
      ),
    );
  }
  Widget _buildTimetableGrid(
    AppProvider provider,
    List<TimetablePeriod> periods,
    String weekType,
    bool abWeeksEnabled,
    bool isDark,
  ) {
    const cellWidth = 85.0;
    const cellHeight = 70.0;
    const headerHeight = 44.0;
    const periodColumnWidth = 65.0;

    return GlassContainer(
      borderRadius: 16,
      blurSigma: 10,
      child: Table(
            defaultColumnWidth: const FixedColumnWidth(cellWidth),
            columnWidths: const {0: FixedColumnWidth(periodColumnWidth)},
            border: TableBorder.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
            children: [
              TableRow(
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: Center(
                      child: Text(
                        'Zeit',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  ..._days.asMap().entries.map((entry) {
                    final dayIndex = entry.key;
                    final day = entry.value;
                    final isToday = DateTime.now().weekday == dayIndex + 1;
                    return SizedBox(
                      height: headerHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: isToday ? 0.24 : 0.08),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                day,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isToday
                                      ? AppTheme.primaryColor
                                      : (isDark ? AppTheme.darkText : AppTheme.lightText),
                                ),
                              ),
                              if (isToday)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              ...periods.map((period) => TableRow(
                children: [
                  SizedBox(
                    height: cellHeight,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.white.withValues(alpha: 0.3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                '${period.periodNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            period.startTime,
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                          Text(
                            period.endTime,
                            style: TextStyle(
                              fontSize: 9,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...List.generate(5, (dayIndex) {
                    final dayOfWeek = dayIndex + 1;
                    final lessonsForCell = provider.lessons
                        .where((l) => l.dayOfWeek == dayOfWeek && l.lessonNumber == period.periodNumber)
                        .where((l) => !abWeeksEnabled || l.weekType == 'both' || l.weekType == weekType)
                        .toList();

                    return SizedBox(
                      height: cellHeight,
                      child: _buildGridCell(
                        lessonsForCell,
                        dayOfWeek,
                        period,
                        abWeeksEnabled,
                        isDark,
                      ),
                    );
                  }),
                ],
              )),
            ],
          ),
    );
  }

  Widget _buildGridCell(
    List<Lesson> lessons,
    int dayOfWeek,
    TimetablePeriod period,
    bool abWeeksEnabled,
    bool isDark,
  ) {
    if (lessons.isEmpty) {
      return InkWell(
        onTap: () => _showAddLessonForCell(dayOfWeek, period, abWeeksEnabled),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.white.withValues(alpha: 0.2),
          ),
          child: Center(
            child: Icon(
              Icons.add,
              color: (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted).withValues(alpha: 0.3),
              size: 20,
            ),
          ),
        ),
      );
    }

    if (lessons.isEmpty) return const SizedBox.shrink();
    final lesson = lessons.first;
    final color = _parseColor(lesson.color, AppTheme.primaryColor);

    return InkWell(
      onTap: () => _showEditLessonForCell(lesson, abWeeksEnabled),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.25 : 0.2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              lesson.subject.length > 8
                  ? '${lesson.subject.substring(0, 8)}.'
                  : lesson.subject,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: color,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            if (lesson.room != null && lesson.room!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                lesson.room!,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (lesson.weekType != 'both' && abWeeksEnabled) ...[
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  lesson.weekType,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddLessonForCell(int dayOfWeek, TimetablePeriod period, bool abWeeksEnabled) {
    showAddLessonDialog(
      context,
      dayOfWeek: dayOfWeek,
      lessonNumber: period.periodNumber,
      startTime: period.startTime,
      endTime: period.endTime,
      abWeeksEnabled: abWeeksEnabled,
    );
  }

  void _showEditLessonForCell(Lesson lesson, bool abWeeksEnabled) {
    showEditLessonDialog(context, lesson, abWeeksEnabled: abWeeksEnabled);
  }

  Widget _buildEmptyDayState(BuildContext context, bool isDark, int dayOfWeek) {
    final abWeeksEnabled = context.read<AppProvider>().abWeeksEnabled;
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wb_sunny_outlined,
            size: 64,
            color: AppTheme.primaryColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Keine Stunden',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dieser Tag ist noch leer',
            style: TextStyle(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => showAddLessonDialog(context, dayOfWeek: dayOfWeek, abWeeksEnabled: abWeeksEnabled),
            icon: const Icon(Icons.add),
            label: const Text('Stunde hinzufügen'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: _subjects.isEmpty
          ? _buildEmptyState(
              icon: Icons.school,
              title: 'Keine Fächer',
              subtitle: 'Füge deine Schulfächer hinzu',
              buttonText: 'Fach hinzufügen',
              onAdd: () => _showAddSubjectDialog(isDark),
              isDark: isDark,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._subjects.asMap().entries.map((entry) => AnimatedListItem(
                  index: entry.key,
                  child: _SubjectCard(
                    subject: entry.value,
                    onEdit: () => _showEditSubjectDialog(entry.value, isDark),
                    onDelete: () => _deleteSubject(entry.value['id']),
                  ),
                )),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: () => _showAddSubjectDialog(isDark),
                      icon: const Icon(Icons.add),
                      label: const Text('Fach hinzufügen'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
    );
  }

  void _showAddSubjectDialog(bool isDark) {
    _showSubjectDialog(null, isDark);
  }

  void _showEditSubjectDialog(Map<String, dynamic> subject, bool isDark) {
    _showSubjectDialog(subject, isDark);
  }

  void _showSubjectDialog(Map<String, dynamic>? subject, bool isDark) {
    final nameController = TextEditingController(text: subject?['name'] ?? '');
    final shortController = TextEditingController(text: subject?['short_name'] ?? '');
    final teacherController = TextEditingController(text: subject?['teacher'] ?? '');
    final roomController = TextEditingController(text: subject?['room'] ?? '');
    String? selectedColor = subject?['color'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(subject != null ? 'Fach bearbeiten' : 'Neues Fach'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'z.B. Mathematik',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: shortController,
                  decoration: const InputDecoration(
                    labelText: 'Kürzel (optional)',
                    hintText: 'z.B. MA',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: teacherController,
                  decoration: const InputDecoration(
                    labelText: 'Lehrer (optional)',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: roomController,
                  decoration: const InputDecoration(
                    labelText: 'Raum (optional)',
                    prefixIcon: Icon(Icons.room),
                  ),
                ),
                const SizedBox(height: 16),
                _ColorPicker(
                  selectedColor: selectedColor,
                  onColorSelected: (color) => selectedColor = color,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;

              if (subject != null) {
                await _db.updateSubject(
                  subject['id'],
                  name: nameController.text.trim(),
                  shortName: shortController.text.trim().isEmpty ? null : shortController.text.trim(),
                  teacher: teacherController.text.trim().isEmpty ? null : teacherController.text.trim(),
                  room: roomController.text.trim().isEmpty ? null : roomController.text.trim(),
                  color: selectedColor,
                );
              } else {
                await _db.insertSubject(
                  name: nameController.text.trim(),
                  shortName: shortController.text.trim().isEmpty ? null : shortController.text.trim(),
                  teacher: teacherController.text.trim().isEmpty ? null : teacherController.text.trim(),
                  room: roomController.text.trim().isEmpty ? null : roomController.text.trim(),
                  color: selectedColor,
                );
              }
              await _loadAllData();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ).then((_) {
      nameController.dispose();
      shortController.dispose();
      teacherController.dispose();
      roomController.dispose();
    });
  }

  Future<void> _deleteSubject(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fach löschen?'),
        content: const Text('Möchtest du dieses Fach wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteSubject(id);
      await _loadAllData();
    }
  }

  Widget _buildHomeworkTab(bool isDark) {
    final openHomework = _homework.where((h) => h['completed'] != 1).toList();
    final completedHomework = _homework.where((h) => h['completed'] == 1).toList();

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: _homework.isEmpty
          ? _buildEmptyState(
              icon: Icons.assignment,
              title: 'Keine Hausaufgaben',
              subtitle: 'Füge deine Hausaufgaben hinzu',
              buttonText: 'Hausaufgabe hinzufügen',
              onAdd: () => _showHomeworkDialog(null, isDark),
              isDark: isDark,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (openHomework.isNotEmpty) ...[
                  _SectionHeader(title: 'Offen (${openHomework.length})', isDark: isDark),
                  ...openHomework.asMap().entries.map((entry) => AnimatedListItem(
                    index: entry.key,
                    child: _HomeworkCard(
                      homework: entry.value,
                      onToggle: () => _toggleHomework(entry.value),
                      onEdit: () => _showHomeworkDialog(entry.value, isDark),
                      onDelete: () => _deleteHomework(entry.value['id']),
                    ),
                  )),
                ],
                if (completedHomework.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionHeader(title: 'Erledigt (${completedHomework.length})', isDark: isDark),
                  ...completedHomework.asMap().entries.map((entry) => AnimatedListItem(
                    index: entry.key,
                    child: _HomeworkCard(
                      homework: entry.value,
                      onToggle: () => _toggleHomework(entry.value),
                      onEdit: () => _showHomeworkDialog(entry.value, isDark),
                      onDelete: () => _deleteHomework(entry.value['id']),
                    ),
                  )),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: () => _showHomeworkDialog(null, isDark),
                      icon: const Icon(Icons.add),
                      label: const Text('Hausaufgabe hinzufügen'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
    );
  }

  void _showHomeworkDialog(Map<String, dynamic>? homework, bool isDark) {
    final titleController = TextEditingController(text: homework?['title'] ?? '');
    final notesController = TextEditingController(text: homework?['notes'] ?? '');
    int? selectedSubjectId = homework?['subject_id'];
    DateTime? dueDate = homework?['due_date'] != null ? DateTime.parse(homework!['due_date']) : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(homework != null ? 'Hausaufgabe bearbeiten' : 'Neue Hausaufgabe'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Aufgabe'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedSubjectId,
                  decoration: const InputDecoration(labelText: 'Fach'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Kein Fach')),
                    ..._subjects.map((s) => DropdownMenuItem(
                      value: s['id'] as int,
                      child: Text(s['name'] as String),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() => selectedSubjectId = v),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(dueDate != null
                      ? DateFormat('d. MMM yyyy', 'de_DE').format(dueDate!)
                      : 'Fälligkeitsdatum wählen'),
                  trailing: dueDate != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setDialogState(() => dueDate = null),
                        )
                      : null,
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: dueDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) setDialogState(() => dueDate = date);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notizen (optional)'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;

                if (homework != null) {
                  await _db.updateHomework(
                    homework['id'],
                    title: titleController.text.trim(),
                    subjectId: selectedSubjectId,
                    notes: notesController.text.trim(),
                    dueDate: dueDate,
                  );
                } else {
                  await _db.insertHomework(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleController.text.trim(),
                    subjectId: selectedSubjectId,
                    notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                    dueDate: dueDate,
                  );
                }
                try { await _loadAllData(); } catch (_) {}
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    ).then((_) {
      titleController.dispose();
      notesController.dispose();
    });
  }

  Future<void> _toggleHomework(Map<String, dynamic> hw) async {
    await _db.toggleHomeworkComplete(hw['id'], hw['completed'] != 1);
    await _loadAllData();
  }

  Future<void> _deleteHomework(String id) async {
    await _db.deleteHomework(id);
    await _loadAllData();
  }

  Widget _buildTestsTab(bool isDark) {
    final upcoming = _tests.where((t) {
      if (t['date'] == null) return true;
      return DateTime.parse(t['date']).isAfter(DateTime.now().subtract(const Duration(days: 1)));
    }).toList();
    final past = _tests.where((t) {
      if (t['date'] == null) return false;
      return DateTime.parse(t['date']).isBefore(DateTime.now().subtract(const Duration(days: 1)));
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: _tests.isEmpty
          ? _buildEmptyState(
              icon: Icons.quiz,
              title: 'Keine Tests',
              subtitle: 'Füge anstehende Tests hinzu',
              buttonText: 'Test hinzufügen',
              onAdd: () => _showTestExamDialog(null, isExam: false, isDark: isDark),
              isDark: isDark,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (upcoming.isNotEmpty) ...[
                  _SectionHeader(title: 'Anstehend (${upcoming.length})', isDark: isDark),
                  ...upcoming.asMap().entries.map((entry) => AnimatedListItem(
                    index: entry.key,
                    child: _TestExamCard(
                      item: entry.value,
                      isExam: false,
                      onEdit: () => _showTestExamDialog(entry.value, isExam: false, isDark: isDark),
                      onDelete: () => _deleteTest(entry.value['id']),
                    ),
                  )),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionHeader(title: 'Vergangen (${past.length})', isDark: isDark),
                  ...past.asMap().entries.map((entry) => AnimatedListItem(
                    index: entry.key,
                    child: _TestExamCard(
                      item: entry.value,
                      isExam: false,
                      onEdit: () => _showTestExamDialog(entry.value, isExam: false, isDark: isDark),
                      onDelete: () => _deleteTest(entry.value['id']),
                    ),
                  )),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: () => _showTestExamDialog(null, isExam: false, isDark: isDark),
                      icon: const Icon(Icons.add),
                      label: const Text('Test hinzufügen'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
    );
  }

  Widget _buildExamsTab(bool isDark) {
    final upcoming = _exams.where((e) {
      if (e['date'] == null) return true;
      return DateTime.parse(e['date']).isAfter(DateTime.now().subtract(const Duration(days: 1)));
    }).toList();
    final past = _exams.where((e) {
      if (e['date'] == null) return false;
      return DateTime.parse(e['date']).isBefore(DateTime.now().subtract(const Duration(days: 1)));
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: _exams.isEmpty
          ? _buildEmptyState(
              icon: Icons.edit_note,
              title: 'Keine Klausuren',
              subtitle: 'Füge anstehende Klausuren hinzu',
              buttonText: 'Klausur hinzufügen',
              onAdd: () => _showTestExamDialog(null, isExam: true, isDark: isDark),
              isDark: isDark,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (upcoming.isNotEmpty) ...[
                  _SectionHeader(title: 'Anstehend (${upcoming.length})', isDark: isDark),
                  ...upcoming.asMap().entries.map((entry) => AnimatedListItem(
                    index: entry.key,
                    child: _TestExamCard(
                      item: entry.value,
                      isExam: true,
                      onEdit: () => _showTestExamDialog(entry.value, isExam: true, isDark: isDark),
                      onDelete: () => _deleteExam(entry.value['id']),
                    ),
                  )),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionHeader(title: 'Vergangen (${past.length})', isDark: isDark),
                  ...past.asMap().entries.map((entry) => AnimatedListItem(
                    index: entry.key,
                    child: _TestExamCard(
                      item: entry.value,
                      isExam: true,
                      onEdit: () => _showTestExamDialog(entry.value, isExam: true, isDark: isDark),
                      onDelete: () => _deleteExam(entry.value['id']),
                    ),
                  )),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: OutlinedButton.icon(
                      onPressed: () => _showTestExamDialog(null, isExam: true, isDark: isDark),
                      icon: const Icon(Icons.add),
                      label: const Text('Klausur hinzufügen'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
    );
  }

  void _showTestExamDialog(Map<String, dynamic>? item, {required bool isExam, required bool isDark}) {
    final titleController = TextEditingController(text: item?['title'] ?? '');
    final notesController = TextEditingController(text: item?['notes'] ?? '');
    final gradeController = TextEditingController(text: item?['grade'] ?? '');
    int? selectedSubjectId = item?['subject_id'];
    DateTime? date = item?['date'] != null ? DateTime.parse(item!['date']) : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item != null
              ? '${isExam ? 'Klausur' : 'Test'} bearbeiten'
              : 'Neue${isExam ? ' Klausur' : 'r Test'}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: isExam ? 'Thema' : 'Thema'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedSubjectId,
                  decoration: const InputDecoration(labelText: 'Fach'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Kein Fach')),
                    ..._subjects.map((s) => DropdownMenuItem(
                      value: s['id'] as int,
                      child: Text(s['name'] as String),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() => selectedSubjectId = v),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(date != null
                      ? DateFormat('d. MMM yyyy', 'de_DE').format(date!)
                      : 'Datum wählen'),
                  trailing: date != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setDialogState(() => date = null),
                        )
                      : null,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: gradeController,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notizen (optional)'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty) return;

                final db = await _db.database;
                final table = isExam ? 'exams' : 'tests';

                if (item != null) {
                  await db.update(table, {
                    'title': titleController.text.trim(),
                    'subject_id': selectedSubjectId,
                    'date': date?.toIso8601String(),
                    'grade': gradeController.text.trim().isEmpty ? null : gradeController.text.trim(),
                    'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                  }, where: 'id = ?', whereArgs: [item['id']]);
                } else {
                  await db.insert(table, {
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'title': titleController.text.trim(),
                    'subject_id': selectedSubjectId,
                    'date': date?.toIso8601String(),
                    'grade': gradeController.text.trim().isEmpty ? null : gradeController.text.trim(),
                    'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                    'created_at': DateTime.now().toIso8601String(),
                  });
                }
                try { await _loadAllData(); } catch (_) {}
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    ).then((_) {
      titleController.dispose();
      notesController.dispose();
      gradeController.dispose();
    });
  }

  Future<void> _deleteTest(String id) async {
    final db = await _db.database;
    await db.delete('tests', where: 'id = ?', whereArgs: [id]);
    await _loadAllData();
  }

  Future<void> _deleteExam(String id) async {
    final db = await _db.database;
    await db.delete('exams', where: 'id = ?', whereArgs: [id]);
    await _loadAllData();
  }

  String _selectedSemester = 'Q1';

  Widget _buildGradesTab(bool isDark) {
    final isMarks = _gradeSystem == 'marks';
    final semesters = isMarks
        ? ['$_classLevel/1', '$_classLevel/2', 'all']
        : ['Q1', 'Q2', 'Q3', 'Q4', 'all'];

    if (!semesters.contains(_selectedSemester)) {
      _selectedSemester = semesters.first;
    }

    final currentSemesters = isMarks
        ? ['$_classLevel/1', '$_classLevel/2']
        : ['Q1', 'Q2', 'Q3', 'Q4'];

    final currentSystemGrades = _grades.where((g) {
      final matchesSystem = (g['grade_system'] ?? 'points') == _gradeSystem;
      if (!matchesSystem) return false;
      if (isMarks) {
        final sem = g['semester'] as String? ?? '';
        return currentSemesters.contains(sem);
      }
      return true;
    }).toList();

    final archivedGrades = _grades.where((g) {
      final matchesSystem = (g['grade_system'] ?? 'points') == _gradeSystem;
      if (!matchesSystem) return true;
      if (isMarks) {
        final sem = g['semester'] as String? ?? '';
        return !currentSemesters.contains(sem);
      }
      return false;
    }).toList();

    final filteredGrades = _selectedSemester == 'all'
        ? currentSystemGrades
        : currentSystemGrades.where((g) => g['semester'] == _selectedSemester).toList();

    double? overallAvg;
    double? klausurAvg;
    double? sonstigeAvg;

    if (isMarks) {
      final marksWithValue = filteredGrades.where((g) => g['value'] != null).toList();
      if (marksWithValue.isNotEmpty) {
        overallAvg = marksWithValue.map((g) => (g['value'] as num).toDouble()).reduce((a, b) => a + b) / marksWithValue.length;
      }
    } else {
      final klausurGrades = filteredGrades.where((g) => g['type'] == 'Klausur').toList();
      final sonstigeGradesList = filteredGrades.where((g) => g['type'] != 'Klausur').toList();

      klausurAvg = klausurGrades.isNotEmpty
          ? klausurGrades.map((g) => g['points'] as int).reduce((a, b) => a + b) / klausurGrades.length
          : null;
      sonstigeAvg = sonstigeGradesList.isNotEmpty
          ? sonstigeGradesList.map((g) => g['points'] as int).reduce((a, b) => a + b) / sonstigeGradesList.length
          : null;

      if (klausurAvg != null && sonstigeAvg != null) {
        overallAvg = (klausurAvg * 1 + sonstigeAvg * 2) / 3;
      } else if (klausurAvg != null) {
        overallAvg = klausurAvg;
      } else if (sonstigeAvg != null) {
        overallAvg = sonstigeAvg;
      }
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: semesters.map((semester) {
                  final isSelected = _selectedSemester == semester;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSemester = semester),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: semester == 'all' ? 16 : 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Text(
                          semester == 'all' ? 'Alle' : semester,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppPalette.ring,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          if (overallAvg != null)
            GlassCard(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              borderRadius: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (isMarks)
                    _buildSummaryItem('Gesamt', overallAvg.toStringAsFixed(1), AppTheme.primaryColor, isDark)
                  else ...[
                    _buildSummaryItem('Gesamt', overallAvg.toStringAsFixed(1), AppTheme.primaryColor, isDark),
                    if (klausurAvg != null)
                      _buildSummaryItem('Klausuren (1/3)', klausurAvg.toStringAsFixed(1), AppTheme.primaryLight, isDark),
                    if (sonstigeAvg != null)
                      _buildSummaryItem('Sonstige (2/3)', sonstigeAvg.toStringAsFixed(1), AppTheme.accentColor, isDark),
                  ],
                ],
              ),
            ),

          _FullGradeCalculatorCard(isDark: isDark, subjects: _subjects, gradeSystem: _gradeSystem),
          const SizedBox(height: 16),

          Row(
            children: [
              _SectionHeader(title: 'Notenübersicht', isDark: isDark),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showAddGradeDialog(isDark),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Note'),
              ),
            ],
          ),

          if (filteredGrades.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.grade, size: 48, color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'Keine Noten eingetragen',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showAddGradeDialog(isDark),
                    icon: const Icon(Icons.add),
                    label: const Text('Note hinzufügen'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
            )
          else
            ..._buildGradesBySubject(filteredGrades, isDark),

          if (archivedGrades.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildArchiveSection(archivedGrades, isDark),
          ],

          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildArchiveSection(List<Map<String, dynamic>> archivedGrades, bool isDark) {
    final archiveLabel = _gradeSystem == 'marks'
        ? 'Archiv (andere Klassenstufen & Punkte)'
        : 'Archiv (Noten)';

    final Map<int, List<Map<String, dynamic>>> bySubject = {};
    for (final g in archivedGrades) {
      final sid = g['subject_id'] as int;
      bySubject.putIfAbsent(sid, () => []).add(g);
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      child: ExpansionTile(
        leading: Icon(Icons.archive_outlined, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
        title: Text(archiveLabel, style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
        )),
        subtitle: Text('${archivedGrades.length} Noten', style: TextStyle(
          fontSize: 12,
          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
        )),
        children: bySubject.entries.map((entry) {
          final grades = entry.value;
          final subjectName = grades.first['subject_name'] ?? 'Unbekannt';
          final isArchivedMarks = (grades.first['grade_system'] ?? 'points') == 'marks';

          return ListTile(
            dense: true,
            title: Text(subjectName as String, style: TextStyle(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            )),
            subtitle: Text(
              grades.map((g) {
                if (isArchivedMarks && g['value'] != null) {
                  return _markValueToLabel((g['value'] as num).toDouble());
                }
                return '${g['points']}P';
              }).join(', '),
              style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color, bool isDark) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showAddGradeDialog(bool isDark) {
    final isMarks = _gradeSystem == 'marks';
    int? selectedSubjectId;
    final defaultSemester = isMarks ? '$_classLevel/1' : 'Q1';
    String selectedSemester = _selectedSemester == 'all' ? defaultSemester : _selectedSemester;
    String selectedType = 'Mündlich';
    final pointsController = TextEditingController();
    double? selectedMarkValue;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Neue Note'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int?>(
                  initialValue: selectedSubjectId,
                  decoration: const InputDecoration(labelText: 'Fach'),
                  items: _subjects.map((s) => DropdownMenuItem(
                    value: s['id'] as int,
                    child: Row(
                      children: [
                        Text(s['name'] as String),
                        if (!isMarks && s['course_type'] != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: s['course_type'] == 'LK' ? AppTheme.primaryColor.withValues(alpha: 0.2) : AppPalette.ring.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s['course_type'] as String,
                              style: TextStyle(fontSize: 10, color: s['course_type'] == 'LK' ? AppTheme.primaryColor : AppPalette.ring),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedSubjectId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedSemester,
                  decoration: const InputDecoration(labelText: 'Halbjahr'),
                  items: (isMarks ? ['$_classLevel/1', '$_classLevel/2'] : ['Q1', 'Q2', 'Q3', 'Q4'])
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedSemester = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Art'),
                  items: ['Klausur', 'Mündlich', 'Test', 'Referat', 'Hausarbeit', 'Sonstige']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedType = v!),
                ),
                const SizedBox(height: 16),
                if (isMarks)
                  DropdownButtonFormField<double>(
                    initialValue: selectedMarkValue,
                    decoration: const InputDecoration(labelText: 'Note'),
                    items: _markOptions.map((o) => DropdownMenuItem(
                      value: o['value'] as double,
                      child: Text('${o['label']}  (${(o['value'] as double).toStringAsFixed(1)})'),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => selectedMarkValue = v),
                  )
                else
                  TextField(
                    controller: pointsController,
                    decoration: const InputDecoration(
                      labelText: 'Punkte (0-15)',
                      hintText: 'z.B. 12',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                if (!isMarks) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('Gewichtung:', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
                        const SizedBox(height: 4),
                        Text(
                          selectedType == 'Klausur' ? 'Zählt zu Klausuren (1/3)' : 'Zählt zu Sonstige (2/3)',
                          style: TextStyle(fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () async {
                if (selectedSubjectId == null) return;

                final db = await _db.database;
                if (isMarks) {
                  if (selectedMarkValue == null) return;
                  await db.insert('grades', {
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'subject_id': selectedSubjectId,
                    'semester': selectedSemester,
                    'type': selectedType,
                    'points': 0,
                    'value': selectedMarkValue,
                    'grade_system': 'marks',
                    'date': DateTime.now().toIso8601String(),
                    'created_at': DateTime.now().toIso8601String(),
                  });
                } else {
                  if (pointsController.text.isEmpty) return;
                  final points = int.tryParse(pointsController.text);
                  if (points == null || points < 0 || points > 15) return;
                  await db.insert('grades', {
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'subject_id': selectedSubjectId,
                    'semester': selectedSemester,
                    'type': selectedType,
                    'points': points,
                    'grade_system': 'points',
                    'date': DateTime.now().toIso8601String(),
                    'created_at': DateTime.now().toIso8601String(),
                  });
                }
                try { await _loadAllData(); } catch (_) {}
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    ).then((_) {
      pointsController.dispose();
    });
  }

  List<Widget> _buildGradesBySubject(List<Map<String, dynamic>> grades, bool isDark) {
    final isMarks = _gradeSystem == 'marks';
    final Map<int, List<Map<String, dynamic>>> gradesBySubject = {};
    for (final grade in grades) {
      final subjectId = grade['subject_id'] as int;
      gradesBySubject.putIfAbsent(subjectId, () => []).add(grade);
    }

    return gradesBySubject.entries.where((entry) => entry.value.isNotEmpty).map((entry) {
      final subjectGrades = entry.value;
      final subjectName = subjectGrades.first['subject_name'] ?? 'Unbekannt';
      final courseType = subjectGrades.first['course_type'];

      if (isMarks) {
        final marksWithValue = subjectGrades.where((g) => g['value'] != null).toList();
        if (marksWithValue.isEmpty) return const SizedBox.shrink();
        final avgMark = marksWithValue.map((g) => (g['value'] as num).toDouble()).reduce((a, b) => a + b) / marksWithValue.length;
        final avgColor = _getMarkColor(avgMark);

        return GlassCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.zero,
          borderRadius: 12,
          child: ExpansionTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: avgColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  _markValueToLabel(avgMark),
                  style: TextStyle(color: avgColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            title: Text(subjectName as String, overflow: TextOverflow.ellipsis),
            subtitle: Text('${subjectGrades.length} Noten'),
            children: subjectGrades.map((g) {
              final markVal = g['value'] != null ? (g['value'] as num).toDouble() : 0.0;
              final markColor = _getMarkColor(markVal);
              return ListTile(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: markColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      _markValueToLabel(markVal),
                      style: TextStyle(color: markColor, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
                title: Text(g['type'] as String),
                subtitle: Text(g['semester'] as String),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteGrade(g['id']),
                ),
              );
            }).toList(),
          ),
        );
      }

      final klausuren = subjectGrades.where((g) => g['type'] == 'Klausur').toList();
      final sonstige = subjectGrades.where((g) => g['type'] != 'Klausur').toList();

      double avgPoints;
      if (klausuren.isNotEmpty && sonstige.isNotEmpty) {
        final klausurAvg = klausuren.map((g) => g['points'] as int).reduce((a, b) => a + b) / klausuren.length;
        final sonstigeAvg = sonstige.map((g) => g['points'] as int).reduce((a, b) => a + b) / sonstige.length;
        avgPoints = (klausurAvg * 1 + sonstigeAvg * 2) / 3;
      } else if (klausuren.isNotEmpty) {
        avgPoints = klausuren.map((g) => g['points'] as int).reduce((a, b) => a + b) / klausuren.length;
      } else {
        avgPoints = sonstige.map((g) => g['points'] as int).reduce((a, b) => a + b) / sonstige.length;
      }

      return GlassCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.zero,
        borderRadius: 12,
        child: ExpansionTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getGradeColor(avgPoints.round()).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                avgPoints.toStringAsFixed(1),
                style: TextStyle(
                  color: _getGradeColor(avgPoints.round()),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          title: Row(
            children: [
              Flexible(child: Text(subjectName as String, overflow: TextOverflow.ellipsis)),
              if (courseType != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: courseType == 'LK'
                        ? AppTheme.primaryColor.withValues(alpha: 0.2)
                        : AppPalette.ring.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    courseType == 'LK' ? 'LK (2x)' : courseType as String,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: courseType == 'LK' ? AppTheme.primaryColor : AppPalette.ring,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text('${subjectGrades.length} Noten • K: ${klausuren.length} • S: ${sonstige.length}'),
          children: subjectGrades.map((g) => ListTile(
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _getGradeColor(g['points'] as int).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '${g['points']}',
                  style: TextStyle(
                    color: _getGradeColor(g['points'] as int),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            title: Text(g['type'] as String),
            subtitle: Text('${g['semester']} • ${g['type'] == 'Klausur' ? '1/3' : '2/3'}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteGrade(g['id']),
            ),
          )).toList(),
        ),
      );
    }).toList();
  }

  Color _getGradeColor(int points) {
    if (points >= 13) return AppTheme.success;
    if (points >= 10) return AppPalette.moss;
    if (points >= 7) return AppTheme.warning;
    if (points >= 4) return AppTheme.warning;
    return AppTheme.danger;
  }

  Future<void> _deleteGrade(String id) async {
    final db = await _db.database;
    await db.delete('grades', where: 'id = ?', whereArgs: [id]);
    await _loadAllData();
  }

  Widget _buildIServTab(bool isDark) {
    return Consumer<IServProvider>(
      builder: (context, iservProvider, child) {
        if (!iservProvider.isConnected) {
          return _buildEmptyState(
            icon: Icons.school,
            title: 'IServ verbinden',
            subtitle: 'Verbinde dein IServ-Konto\num Aufgaben und Termine zu sehen',
            buttonText: 'Mit IServ anmelden',
            onAdd: () => _showIServLoginDialog(context),
            isDark: isDark,
          );
        }

        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              GlassCard(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                borderRadius: 12,
                tint: AppTheme.success,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'IServ verbunden',
                      style: TextStyle(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => iservProvider.disconnect(),
                      child: const Text('Trennen'),
                    ),
                  ],
                ),
              ),
              GlassCard(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: EdgeInsets.zero,
                borderRadius: 12,
                child: TabBar(
                  tabs: const [
                    Tab(text: 'Aufgaben'),
                    Tab(text: 'Termine'),
                    Tab(text: 'Vertretung'),
                  ],
                  labelColor: AppTheme.primaryColor,
                  unselectedLabelColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  indicatorColor: AppTheme.primaryColor,
                  dividerColor: Colors.transparent,
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildIServComingSoon('IServ Aufgaben', isDark),
                    _buildIServComingSoon('IServ Termine', isDark),
                    _buildVertretungsplanTab(isDark, iservProvider),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIServComingSoon(String title, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 48,
              color: AppTheme.primaryColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Bald verfügbar',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark ? AppPalette.inkDark : AppPalette.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$title werden bald unterstützt',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVertretungsplanTab(bool isDark, IServProvider provider) {
    final iservUrl = provider.iservUrl;

    if (iservUrl == null || !provider.isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.school_outlined,
                size: 48,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'Bitte mit IServ verbinden',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Verbinde dich oben mit deinem IServ-Account,\num den Vertretungsplan anzuzeigen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.vertretungsplanFiles.isEmpty &&
        !provider.isVertretungsplanLoading &&
        provider.vertretungsplanError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.fetchVertretungsplan();
      });
    }

    if (provider.isVertretungsplanLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Lade Vertretungsplan...',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (provider.vertretungsplanError != null && provider.vertretungsplanFiles.isEmpty) {
      final isSessionExpired = provider.vertretungsplanError!.contains('Sitzung abgelaufen') ||
                               provider.vertretungsplanError!.contains('anmelden');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSessionExpired ? Icons.login : Icons.error_outline,
                size: 48,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
              const SizedBox(height: 16),
              Text(
                provider.vertretungsplanError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
              const SizedBox(height: 16),
              if (isSessionExpired)
                ElevatedButton.icon(
                  onPressed: () => _showIServLoginDialog(context),
                  icon: const Icon(Icons.login),
                  label: const Text('Neu anmelden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => provider.fetchVertretungsplan(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut versuchen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (provider.vertretungsplanFiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                size: 48,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'Kein Vertretungsplan verfügbar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => provider.fetchVertretungsplan(),
                icon: const Icon(Icons.refresh),
                label: const Text('Aktualisieren'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final files = provider.vertretungsplanFiles;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: provider.isVertretungsplanFromCache
                ? AppTheme.warning.withValues(alpha: 0.1)
                : AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                provider.isVertretungsplanFromCache ? Icons.offline_bolt : Icons.info_outline,
                color: provider.isVertretungsplanFromCache ? AppTheme.warning : AppTheme.primaryColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.isVertretungsplanFromCache
                      ? 'Offline-Daten (${files.length} Seiten)'
                      : 'Vertretungsplan (${files.length} Seiten)',
                  style: TextStyle(
                    color: provider.isVertretungsplanFromCache ? AppTheme.warning : AppTheme.primaryColor,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                onPressed: provider.isVertretungsplanLoading ? null : () => provider.fetchVertretungsplan(),
                icon: provider.isVertretungsplanLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.refresh,
                        color: provider.isVertretungsplanFromCache ? AppTheme.warning : AppTheme.primaryColor,
                        size: 20,
                      ),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _vertretungsplanPageController,
            itemCount: files.length,
            onPageChanged: (index) {
              setState(() {
                _currentVertretungsplanPage = index;
              });
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openFullscreenVertretungsplan(context, files, index, isDark),
                child: _buildVertretungsplanPage(files[index], isDark),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Tippen für Vollbild',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
        ),
        if (files.length > 1)
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(files.length, (index) {
                final isActive = index == _currentVertretungsplanPage;
                return Container(
                  width: isActive ? 10 : 8,
                  height: isActive ? 10 : 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AppTheme.primaryColor
                        : AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildVertretungsplanPage(Map<String, dynamic> file, bool isDark) {
    final data = file['data'] as String?;
    final contentType = file['contentType'] as String? ?? '';

    if (data == null || data.isEmpty) {
      return Center(
        child: Text(
          'Keine Daten',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
        ),
      );
    }

    try {
      final bytes = base64Decode(data);

      if (contentType.contains('image')) {
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 48, color: AppTheme.error),
                    SizedBox(height: 8),
                    Text('Bild konnte nicht geladen werden',
                      style: TextStyle(color: AppTheme.error),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }

      if (contentType.contains('pdf')) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf, size: 64, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                'PDF-Datei',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(bytes.length / 1024).toStringAsFixed(1)} KB',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ],
          ),
        );
      }

      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.contain,
        ),
      );
    } catch (e) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            SizedBox(height: 8),
            Text('Fehler beim Laden. Bitte versuche es erneut.',
              style: TextStyle(color: AppTheme.error, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }

  void _openFullscreenVertretungsplan(
    BuildContext context,
    List<Map<String, dynamic>> files,
    int initialIndex,
    bool isDark,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullscreenVertretungsplanViewer(
            files: files,
            initialIndex: initialIndex,
            isDark: isDark,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onAdd,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(buttonText),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditLessonDialog(BuildContext context, Lesson lesson) {
    final abWeeksEnabled = context.read<AppProvider>().abWeeksEnabled;
    showDialog(
      context: context,
      builder: (context) => _LessonDialog(lesson: lesson, abWeeksEnabled: abWeeksEnabled),
    );
  }

  void _showIServLoginDialog(BuildContext context) {
    final provider = context.read<IServProvider>();
    final savedUrl = provider.iservUrl ?? '';
    final urlController = TextEditingController(text: savedUrl);
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _iservLoggingIn = false;
    _iservLoginError = null;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppTheme.darkCard : null,
          title: const Text('Mit IServ verbinden'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
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
                    labelText: 'IServ URL',
                    hintText: 'z.B. gymnasium.iserv.de',
                    prefixIcon: Icon(Icons.public),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  enabled: !_iservLoggingIn,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Benutzername',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  enabled: !_iservLoggingIn,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Passwort',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  enabled: !_iservLoggingIn,
                  onSubmitted: _iservLoggingIn ? null : (_) => _directIServLogin(
                    dialogContext,
                    setDialogState,
                    urlController.text.trim(),
                    usernameController.text.trim(),
                    passwordController.text,
                  ),
                ),
                if (_iservLoginError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _iservLoginError!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: _iservLoggingIn ? null : () => Navigator.pop(dialogContext),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: _iservLoggingIn ? null : () {
                final url = urlController.text.trim();
                if (url.isEmpty) {
                  setDialogState(() => _iservLoginError = 'Bitte gib zuerst die IServ-URL deiner Schule ein.');
                  return;
                }
                Navigator.pop(dialogContext);
                _showIServWebViewLogin(context, url);
              },
              child: const Text('WebView Login'),
            ),
            FilledButton(
              onPressed: _iservLoggingIn ? null : () => _directIServLogin(
                dialogContext,
                setDialogState,
                urlController.text.trim(),
                usernameController.text.trim(),
                passwordController.text,
              ),
              child: _iservLoggingIn
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Anmelden'),
            ),
          ],
        ),
      ),
    ).then((_) {
      urlController.dispose();
      usernameController.dispose();
      passwordController.dispose();
    });
  }

  Future<void> _directIServLogin(
    BuildContext dialogContext,
    void Function(void Function()) setDialogState,
    String url,
    String username,
    String password,
  ) async {
    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte alle Felder ausfüllen'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setDialogState(() => _iservLoggingIn = true);

    final provider = context.read<IServProvider>();
    final result = await provider.connect(
      username: username,
      password: password,
      iservUrl: url,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IServ erfolgreich verbunden')),
      );
    } else {
      if (dialogContext.mounted) {
        setDialogState(() {
          _iservLoggingIn = false;
          _iservLoginError = result['error'] ?? 'Anmeldung fehlgeschlagen';
        });
      }
    }
  }

  void _showIServWebViewLogin(BuildContext context, String iservUrl) {
    final provider = context.read<IServProvider>();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => IServWebViewLogin(
          iservUrl: iservUrl,
          onLoginSuccess: (cookies, username) async {
            Navigator.of(context).pop();

            final result = await provider.connectWithWebViewCookies(
              iservUrl: iservUrl,
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTheme.sectionLabel(isDark),
      ),
    );
  }
}

class _ColorPicker extends StatefulWidget {
  final String? selectedColor;
  final Function(String) onColorSelected;

  const _ColorPicker({this.selectedColor, required this.onColorSelected});

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late String? _selected;

  static const _colors = [
    '#667EEA', '#764BA2', '#F093FB',
    '#22C55E', '#F59E0B', '#EF4444',
    '#06B6D4', '#8B5CF6',
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Farbe', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _colors.map((color) {
            final isSelected = _selected == color;
            return GestureDetector(
              onTap: () {
                setState(() => _selected = color);
                widget.onColorSelected(color);
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: Color(int.parse(color.replaceFirst('#', '0xFF'))).withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ] : null,
                ),
                child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final Map<String, dynamic> subject;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SubjectCard({required this.subject, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(subject['color'], AppTheme.primaryColor);
    final String subjectName = (subject['name'] as String?) ?? '';
    final String avatarText = ((subject['short_name'] as String?) ??
            (subjectName.length >= 2 ? subjectName.substring(0, 2) : subjectName))
        .toUpperCase();

    return Dismissible(
      key: Key('subject_${subject['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.danger,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Löschen bestätigen'),
            content: const Text('Möchtest du diesen Eintrag wirklich löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppPalette.terracotta),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.zero,
        borderRadius: 12,
        onTap: onEdit,
        child: ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                avatarText,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          title: Text(subject['name'] as String),
          subtitle: subject['teacher'] != null ? Text(subject['teacher'] as String) : null,
          trailing: subject['room'] != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(subject['room'] as String, style: TextStyle(color: color, fontSize: 12)),
                )
              : null,
        ),
      ),
    );
  }
}

class _HomeworkCard extends StatelessWidget {
  final Map<String, dynamic> homework;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HomeworkCard({required this.homework, required this.onToggle, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCompleted = homework['completed'] == 1;
    final color = _parseColor(homework['subject_color'], AppTheme.primaryColor);

    return Dismissible(
      key: Key('hw_${homework['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Löschen bestätigen'),
            content: const Text('Möchtest du diesen Eintrag wirklich löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppPalette.terracotta),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.zero,
        borderRadius: 12,
        onTap: onEdit,
        child: ListTile(
          leading: GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isCompleted ? AppTheme.success : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isCompleted ? AppTheme.success : AppPalette.ring),
              ),
              child: isCompleted ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
            ),
          ),
          title: Text(
            homework['title'] as String,
            style: TextStyle(decoration: isCompleted ? TextDecoration.lineThrough : null),
          ),
          subtitle: Row(
            children: [
              if (homework['subject_name'] != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    homework['subject_name'] as String,
                    style: TextStyle(color: color, fontSize: 10),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (homework['due_date'] != null)
                Text(
                  DateFormat('d. MMM', 'de_DE').format(DateTime.parse(homework['due_date'] as String)),
                  style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestExamCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isExam;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TestExamCard({required this.item, required this.isExam, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _parseColor(item['subject_color'], AppTheme.primaryColor);

    return Dismissible(
      key: Key('${isExam ? 'exam' : 'test'}_${item['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Löschen bestätigen'),
            content: const Text('Möchtest du diesen Eintrag wirklich löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppPalette.terracotta),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.zero,
        borderRadius: 12,
        onTap: onEdit,
        child: ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isExam ? Icons.edit_note : Icons.quiz, color: color),
          ),
          title: Text(item['title'] as String),
          subtitle: Row(
            children: [
              if (item['subject_name'] != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(item['subject_name'] as String, style: TextStyle(color: color, fontSize: 10)),
                ),
                const SizedBox(width: 8),
              ],
              if (item['date'] != null)
                Text(
                  DateFormat('d. MMM yyyy', 'de_DE').format(DateTime.parse(item['date'] as String)),
                  style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                ),
            ],
          ),
          trailing: item['grade'] != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(item['grade'] as String, style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold)),
                )
              : null,
        ),
      ),
    );
  }
}

class _FullGradeCalculatorCard extends StatefulWidget {
  final bool isDark;
  final List<Map<String, dynamic>> subjects;
  final String gradeSystem;

  const _FullGradeCalculatorCard({required this.isDark, required this.subjects, required this.gradeSystem});

  @override
  State<_FullGradeCalculatorCard> createState() => _FullGradeCalculatorCardState();
}

class _FullGradeCalculatorCardState extends State<_FullGradeCalculatorCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  late Animation<double> _fadeAnimation;
  bool get _isMarks => widget.gradeSystem == 'marks';

  final _pointsController = TextEditingController();
  int? _selectedGradePoints;
  double? _selectedMarkConvert;
  String _converterResult = '';

  final _currentAvgController = TextEditingController();
  final _gradeCountController = TextEditingController();
  final _targetAvgController = TextEditingController();
  String _targetResult = '';

  final _klausur1Controller = TextEditingController();
  final _klausur2Controller = TextEditingController();
  final _klausur3Controller = TextEditingController();
  final _klausur4Controller = TextEditingController();
  final _sonstigeAvgController = TextEditingController();
  final _sonstigeGradesController = TextEditingController();
  String _subjectGradeResult = '';

  static const _gradeTable = [
    {'points': 15, 'grade': '1+', 'rating': 'Sehr gut', 'color': AppPalette.sage},
    {'points': 14, 'grade': '1', 'rating': 'Sehr gut', 'color': AppPalette.sage},
    {'points': 13, 'grade': '1-', 'rating': 'Sehr gut', 'color': AppPalette.sage},
    {'points': 12, 'grade': '2+', 'rating': 'Gut', 'color': AppPalette.slate},
    {'points': 11, 'grade': '2', 'rating': 'Gut', 'color': AppPalette.slate},
    {'points': 10, 'grade': '2-', 'rating': 'Gut', 'color': AppPalette.slate},
    {'points': 9, 'grade': '3+', 'rating': 'Befriedigend', 'color': AppPalette.amber},
    {'points': 8, 'grade': '3', 'rating': 'Befriedigend', 'color': AppPalette.amber},
    {'points': 7, 'grade': '3-', 'rating': 'Befriedigend', 'color': AppPalette.amber},
    {'points': 6, 'grade': '4+', 'rating': 'Ausreichend', 'color': AppPalette.ochre},
    {'points': 5, 'grade': '4', 'rating': 'Ausreichend', 'color': AppPalette.ochre},
    {'points': 4, 'grade': '4-', 'rating': 'Ausreichend', 'color': AppPalette.ochre},
    {'points': 3, 'grade': '5+', 'rating': 'Mangelhaft', 'color': AppPalette.terracotta},
    {'points': 2, 'grade': '5', 'rating': 'Mangelhaft', 'color': AppPalette.terracotta},
    {'points': 1, 'grade': '5-', 'rating': 'Mangelhaft', 'color': AppPalette.terracotta},
    {'points': 0, 'grade': '6', 'rating': 'Ungenügend', 'color': AppPalette.terracottaInk},
  ];

  static const _marksTable = [
    {'label': '1+', 'value': 0.7, 'rating': 'Sehr gut', 'color': AppPalette.sage},
    {'label': '1', 'value': 1.0, 'rating': 'Sehr gut', 'color': AppPalette.sage},
    {'label': '1-', 'value': 1.3, 'rating': 'Sehr gut', 'color': AppPalette.sage},
    {'label': '2+', 'value': 1.7, 'rating': 'Gut', 'color': AppPalette.slate},
    {'label': '2', 'value': 2.0, 'rating': 'Gut', 'color': AppPalette.slate},
    {'label': '2-', 'value': 2.3, 'rating': 'Gut', 'color': AppPalette.slate},
    {'label': '3+', 'value': 2.7, 'rating': 'Befriedigend', 'color': AppPalette.amber},
    {'label': '3', 'value': 3.0, 'rating': 'Befriedigend', 'color': AppPalette.amber},
    {'label': '3-', 'value': 3.3, 'rating': 'Befriedigend', 'color': AppPalette.amber},
    {'label': '4+', 'value': 3.7, 'rating': 'Ausreichend', 'color': AppPalette.ochre},
    {'label': '4', 'value': 4.0, 'rating': 'Ausreichend', 'color': AppPalette.ochre},
    {'label': '4-', 'value': 4.3, 'rating': 'Ausreichend', 'color': AppPalette.ochre},
    {'label': '5+', 'value': 4.7, 'rating': 'Mangelhaft', 'color': AppPalette.terracotta},
    {'label': '5', 'value': 5.0, 'rating': 'Mangelhaft', 'color': AppPalette.terracotta},
    {'label': '5-', 'value': 5.3, 'rating': 'Mangelhaft', 'color': AppPalette.terracotta},
    {'label': '6', 'value': 6.0, 'rating': 'Ungenügend', 'color': AppPalette.terracottaInk},
  ];

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubic,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _expandController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeIn),
    );
  }

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  String _pointsToGrade(int points) {
    if (points < 0 || points > 15) return '-';
    return _gradeTable.firstWhere((e) => e['points'] == points)['grade'] as String;
  }

  String _pointsToRating(int points) {
    if (points < 0 || points > 15) return '-';
    return _gradeTable.firstWhere((e) => e['points'] == points)['rating'] as String;
  }

  Color _pointsToColor(int points) {
    if (points < 0 || points > 15) return AppPalette.ring;
    return _gradeTable.firstWhere((e) => e['points'] == points)['color'] as Color;
  }

  void _convertPointsToGrade() {
    final points = int.tryParse(_pointsController.text);
    if (points != null && points >= 0 && points <= 15) {
      setState(() {
        _selectedGradePoints = points;
        _converterResult = '${_pointsToGrade(points)} (${_pointsToRating(points)})';
      });
    } else {
      setState(() {
        _selectedGradePoints = null;
        _converterResult = '';
      });
    }
  }

  void _convertGradeToPoints(int? points) {
    if (points != null) {
      setState(() {
        _selectedGradePoints = points;
        _pointsController.text = points.toString();
        _converterResult = '${_pointsToGrade(points)} (${_pointsToRating(points)})';
      });
    }
  }

  void _selectMarkForConvert(double? value) {
    if (value != null) {
      final entry = _marksTable.firstWhere((e) => ((e['value'] as double) - value).abs() < 0.05);
      setState(() {
        _selectedMarkConvert = value;
        _converterResult = '${entry['label']} (${entry['rating']})';
      });
    }
  }

  void _calculateNeededGrade() {
    final currentAvg = double.tryParse(_currentAvgController.text);
    final gradeCount = int.tryParse(_gradeCountController.text);
    final targetAvg = double.tryParse(_targetAvgController.text);

    if (currentAvg == null || gradeCount == null || targetAvg == null) {
      setState(() => _targetResult = 'Bitte alle Felder ausfüllen');
      return;
    }

    final neededGrade = targetAvg * (gradeCount + 1) - currentAvg * gradeCount;

    setState(() {
      if (_isMarks) {
        if (neededGrade > 6.0) {
          _targetResult = 'Du bräuchtest ${neededGrade.toStringAsFixed(1)} - leider nicht erreichbar';
        } else if (neededGrade < 0.7) {
          _targetResult = 'Ziel bereits erreicht! Jede Note reicht aus.';
        } else {
          _targetResult = 'Du brauchst mindestens ${_markValueToLabel(neededGrade)} (${neededGrade.toStringAsFixed(1)})';
        }
      } else {
        if (neededGrade < 0) {
          _targetResult = 'Du brauchst weniger als 0 Punkte - Ziel bereits erreicht!';
        } else if (neededGrade > 15) {
          _targetResult = 'Du bräuchtest ${neededGrade.toStringAsFixed(1)} Punkte - leider nicht erreichbar';
        } else {
          final roundedGrade = neededGrade.ceil();
          _targetResult = 'Du brauchst mindestens $roundedGrade Punkte (${_pointsToGrade(roundedGrade)})';
        }
      }
    });
  }

  void _calculateSubjectGrade() {
    if (_isMarks) {
      _calculateSubjectGradeMarks();
    } else {
      _calculateSubjectGradePoints();
    }
  }

  void _calculateSubjectGradeMarks() {
    final text = _sonstigeGradesController.text;
    if (text.isEmpty) {
      setState(() => _subjectGradeResult = 'Bitte Noten eingeben');
      return;
    }
    final parts = text.split(RegExp(r'[,;\s]+'));
    final List<double> values = [];
    for (final part in parts) {
      final v = double.tryParse(part.trim());
      if (v != null && v >= 0.7 && v <= 6.0) values.add(v);
    }
    if (values.isEmpty) {
      setState(() => _subjectGradeResult = 'Keine gültigen Noten erkannt');
      return;
    }
    final avg = values.reduce((a, b) => a + b) / values.length;
    setState(() {
      _subjectGradeResult = 'Fachnote: ${_markValueToLabel(avg)} (${avg.toStringAsFixed(2)})\n${values.length} Noten';
    });
  }

  void _calculateSubjectGradePoints() {
    List<double> klausurGrades = [];
    for (final controller in [_klausur1Controller, _klausur2Controller, _klausur3Controller, _klausur4Controller]) {
      final grade = double.tryParse(controller.text);
      if (grade != null && grade >= 0 && grade <= 15) {
        klausurGrades.add(grade);
      }
    }

    List<double> sonstigeGrades = [];
    final sonstigeAvg = double.tryParse(_sonstigeAvgController.text);
    if (sonstigeAvg != null && sonstigeAvg >= 0 && sonstigeAvg <= 15) {
      sonstigeGrades.add(sonstigeAvg);
    } else if (_sonstigeGradesController.text.isNotEmpty) {
      final parts = _sonstigeGradesController.text.split(RegExp(r'[,;\s]+'));
      for (final part in parts) {
        final grade = double.tryParse(part.trim());
        if (grade != null && grade >= 0 && grade <= 15) {
          sonstigeGrades.add(grade);
        }
      }
    }

    if (klausurGrades.isEmpty && sonstigeGrades.isEmpty) {
      setState(() => _subjectGradeResult = 'Bitte mindestens eine Note eingeben');
      return;
    }

    double? klausurAvg = klausurGrades.isNotEmpty
        ? klausurGrades.reduce((a, b) => a + b) / klausurGrades.length
        : null;
    double? sonstigeAvgCalc = sonstigeGrades.isNotEmpty
        ? sonstigeGrades.reduce((a, b) => a + b) / sonstigeGrades.length
        : null;

    double finalGrade;
    String breakdown;
    if (klausurAvg != null && sonstigeAvgCalc != null) {
      finalGrade = (klausurAvg * 1 + sonstigeAvgCalc * 2) / 3;
      breakdown = 'Klausuren: ${klausurAvg.toStringAsFixed(1)} (1/3) + Sonstige: ${sonstigeAvgCalc.toStringAsFixed(1)} (2/3)';
    } else if (klausurAvg != null) {
      finalGrade = klausurAvg;
      breakdown = 'Nur Klausuren: ${klausurAvg.toStringAsFixed(1)}';
    } else {
      finalGrade = sonstigeAvgCalc!;
      breakdown = 'Nur Sonstige: ${sonstigeAvgCalc.toStringAsFixed(1)}';
    }

    setState(() {
      _subjectGradeResult = 'Fachnote: ${finalGrade.toStringAsFixed(1)} Punkte (${_pointsToGrade(finalGrade.round())})\n$breakdown';
    });
  }

  @override
  void dispose() {
    _expandController.dispose();
    _pointsController.dispose();
    _currentAvgController.dispose();
    _gradeCountController.dispose();
    _targetAvgController.dispose();
    _klausur1Controller.dispose();
    _klausur2Controller.dispose();
    _klausur3Controller.dispose();
    _klausur4Controller.dispose();
    _sonstigeAvgController.dispose();
    _sonstigeGradesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      child: Column(
        children: [
          InkWell(
            onTap: _toggleExpand,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.calculate, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text('Notenrechner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    child: Icon(
                      Icons.expand_more,
                      color: widget.isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizeTransition(
            sizeFactor: _expandAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  const Divider(height: 1),
                  Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isMarks) ...[
                    _buildSectionTitle('Note ⇄ Bewertung'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<double>(
                      initialValue: _selectedMarkConvert,
                      decoration: InputDecoration(
                        labelText: 'Note auswählen',
                        filled: true,
                        fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _marksTable.map((e) => DropdownMenuItem(
                        value: e['value'] as double,
                        child: Text('${e['label']}  (${(e['value'] as double).toStringAsFixed(1)})'),
                      )).toList(),
                      onChanged: _selectMarkForConvert,
                    ),
                  ] else ...[
                    _buildSectionTitle('Punkte ⇄ Note'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pointsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Punkte (0-15)',
                              filled: true,
                              fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onChanged: (_) => _convertPointsToGrade(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('⇄', style: TextStyle(fontSize: 20, color: AppTheme.primaryColor)),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedGradePoints,
                            decoration: InputDecoration(
                              labelText: 'Note',
                              filled: true,
                              fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: _gradeTable.map((e) => DropdownMenuItem(
                              value: e['points'] as int,
                              child: Text('${e['grade']} (${e['points']}P)'),
                            )).toList(),
                            onChanged: _convertGradeToPoints,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_converterResult.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isMarks
                            ? (_selectedMarkConvert != null ? _getMarkColor(_selectedMarkConvert!).withValues(alpha: 0.1) : AppPalette.ring.withValues(alpha: 0.1))
                            : (_selectedGradePoints != null ? _pointsToColor(_selectedGradePoints!).withValues(alpha: 0.1) : AppPalette.ring.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _converterResult,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _isMarks
                                  ? (_selectedMarkConvert != null ? _getMarkColor(_selectedMarkConvert!) : AppPalette.ring)
                                  : (_selectedGradePoints != null ? _pointsToColor(_selectedGradePoints!) : AppPalette.ring),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  _buildSectionTitle('Welche Note brauche ich?'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _currentAvgController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Aktueller Ø',
                            hintText: _isMarks ? 'z.B. 2.3' : 'z.B. 10.5',
                            filled: true,
                            fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _gradeCountController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Anzahl',
                            hintText: 'z.B. 5',
                            filled: true,
                            fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _targetAvgController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Ziel-Ø',
                            hintText: _isMarks ? 'z.B. 2.0' : 'z.B. 12',
                            filled: true,
                            fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _calculateNeededGrade,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                      ),
                      child: const Text('Berechnen'),
                    ),
                  ),
                  if (_targetResult.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_targetResult, textAlign: TextAlign.center),
                    ),
                  ],

                  const SizedBox(height: 24),

                  if (_isMarks) ...[
                    _buildSectionTitle('Fachnote berechnen (Durchschnitt)'),
                    const SizedBox(height: 12),
                    Text('Noten (kommagetrennt)', style: TextStyle(fontSize: 12, color: widget.isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sonstigeGradesController,
                      decoration: InputDecoration(
                        hintText: 'z.B. 2.0, 1.3, 2.7, 3.0',
                        filled: true,
                        fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ] else ...[
                    _buildSectionTitle('Fachnote berechnen (1/3 Klausur + 2/3 Sonstige)'),
                    const SizedBox(height: 12),
                    Text('Klausuren (1/3)', style: TextStyle(fontSize: 12, color: widget.isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildSmallInput(_klausur1Controller, 'K1')),
                        const SizedBox(width: 8),
                        Expanded(child: _buildSmallInput(_klausur2Controller, 'K2')),
                        const SizedBox(width: 8),
                        Expanded(child: _buildSmallInput(_klausur3Controller, 'K3')),
                        const SizedBox(width: 8),
                        Expanded(child: _buildSmallInput(_klausur4Controller, 'K4')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Sonstige Leistungen (2/3)', style: TextStyle(fontSize: 12, color: widget.isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sonstigeAvgController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Ø Sonstige',
                        hintText: 'z.B. 11.5',
                        filled: true,
                        fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  ],
                  if (!_isMarks) ...[
                    const SizedBox(height: 8),
                    Text('oder einzelne Noten:', style: TextStyle(fontSize: 11, color: widget.isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _sonstigeGradesController,
                      decoration: InputDecoration(
                        hintText: 'z.B. 12, 11, 13, 10, 9',
                        filled: true,
                        fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _calculateSubjectGrade,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: BorderSide(color: AppTheme.primaryColor),
                      ),
                      child: const Text('Fachnote berechnen'),
                    ),
                  ),
                  if (_subjectGradeResult.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_subjectGradeResult, textAlign: TextAlign.center),
                    ),
                  ],

                  const SizedBox(height: 24),

                  _buildSectionTitle(_isMarks ? 'Noten-Tabelle' : 'Punkte-Noten-Tabelle'),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: widget.isDark ? AppTheme.darkCard : AppTheme.lightCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                          ),
                          child: Row(
                            children: [
                              if (!_isMarks)
                                const Expanded(child: Text('Punkte', style: TextStyle(fontWeight: FontWeight.bold))),
                              const Expanded(child: Text('Note', style: TextStyle(fontWeight: FontWeight.bold))),
                              if (_isMarks)
                                const Expanded(child: Text('Wert', style: TextStyle(fontWeight: FontWeight.bold))),
                              const Expanded(flex: 2, child: Text('Bewertung', style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                          ),
                        ),
                        if (_isMarks)
                          ...List.generate(_marksTable.length, (index) {
                            final entry = _marksTable[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: (entry['color'] as Color).withValues(alpha: 0.05),
                                border: index < _marksTable.length - 1
                                    ? Border(bottom: BorderSide(color: widget.isDark ? AppTheme.darkBorder : AppTheme.lightBorder))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry['label'] as String,
                                      style: TextStyle(fontWeight: FontWeight.w600, color: entry['color'] as Color),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      (entry['value'] as double).toStringAsFixed(1),
                                      style: TextStyle(fontWeight: FontWeight.w600, color: entry['color'] as Color),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      entry['rating'] as String,
                                      style: TextStyle(color: entry['color'] as Color),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                        else
                          ...List.generate(_gradeTable.length, (index) {
                            final entry = _gradeTable[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: (entry['color'] as Color).withValues(alpha: 0.05),
                                border: index < _gradeTable.length - 1
                                    ? Border(bottom: BorderSide(color: widget.isDark ? AppTheme.darkBorder : AppTheme.lightBorder))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${entry['points']}',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: entry['color'] as Color),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      entry['grade'] as String,
                                      style: TextStyle(fontWeight: FontWeight.w600, color: entry['color'] as Color),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      entry['rating'] as String,
                                      style: TextStyle(color: entry['color'] as Color),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  Widget _buildSmallInput(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: widget.isDark ? AppPalette.lineDark : AppPalette.sunken,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final bool isCurrentLesson;

  const _LessonCard({required this.lesson, required this.onDelete, required this.onEdit, this.isCurrentLesson = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lessonColor = _parseColor(lesson.color, AppTheme.primaryColor);
    final isWhiteColor = lesson.color == '#FFFFFF';

    return Dismissible(
      key: Key(lesson.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Stunde löschen?'),
            content: Text('Möchtest du "${lesson.subject}" wirklich löschen?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isCurrentLesson
              ? Color.alphaBlend(AppPalette.sand.withValues(alpha: isDark ? .14 : .24), isDark ? AppPalette.surfaceDark : AppPalette.surface)
              : (isDark ? AppPalette.surfaceDark : AppPalette.surface),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrentLesson
                ? AppPalette.sandDeep
                : (isDark ? AppPalette.lineDark : AppPalette.line),
            width: isCurrentLesson ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: lessonColor,
                    borderRadius: BorderRadius.circular(12),
                    border: isWhiteColor ? Border.all(color: AppPalette.lineStrong) : null,
                    boxShadow: [
                      BoxShadow(
                        color: lessonColor.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${lesson.lessonNumber}',
                      style: TextStyle(
                        color: isWhiteColor ? Colors.black87 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              lesson.subject,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lesson.lessonType != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: lessonColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: lessonColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                lesson.lessonType == 'Leistungskurs' ? 'LK' : lesson.lessonType == 'Grundkurs' ? 'GK' : 'SK',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: lessonColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: isDark ? Colors.white60 : Colors.black45),
                          const SizedBox(width: 4),
                          Text(lesson.timeRange, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black45)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (lesson.teacher != null) Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.person, size: 14, color: isDark ? Colors.white60 : Colors.black45),
                      const SizedBox(width: 4),
                      Text(lesson.teacher!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black45)),
                    ]),
                    if (lesson.room != null) ...[
                      const SizedBox(height: 2),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.room, size: 14, color: isDark ? Colors.white60 : Colors.black45),
                        const SizedBox(width: 4),
                        Text(lesson.room!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black45)),
                      ]),
                    ],
                  ],
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: isDark ? Colors.white38 : Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonDialog extends StatefulWidget {
  final Lesson? lesson;
  final int? dayOfWeek;
  final int? lessonNumber;
  final String? startTime;
  final String? endTime;
  final bool abWeeksEnabled;

  const _LessonDialog({
    this.lesson,
    this.dayOfWeek,
    this.lessonNumber,
    this.startTime,
    this.endTime,
    this.abWeeksEnabled = true,
  });

  @override
  State<_LessonDialog> createState() => _LessonDialogState();
}

class _LessonDialogState extends State<_LessonDialog> {
  late TextEditingController _subjectController;
  late TextEditingController _teacherController;
  late TextEditingController _roomController;
  late int _dayOfWeek;
  late int _lessonNumber;
  String _startTime = '08:00';
  String _endTime = '09:30';
  String? _selectedColor;
  String? _selectedLessonType;
  String _selectedWeekType = 'both';

  static const _colorOptions = [
    '#667EEA', '#764BA2', '#F093FB', '#22C55E', '#F59E0B', '#EF4444', '#06B6D4', '#8B5CF6',
    '#9CA3AF', '#FFFFFF', '#EC4899', '#F472B6', '#6366F1', '#14B8A6', '#84CC16', '#A855F7',
  ];

  @override
  void initState() {
    super.initState();
    _subjectController = TextEditingController(text: widget.lesson?.subject ?? '');
    _teacherController = TextEditingController(text: widget.lesson?.teacher ?? '');
    _roomController = TextEditingController(text: widget.lesson?.room ?? '');
    _dayOfWeek = widget.lesson?.dayOfWeek ?? widget.dayOfWeek ?? DateTime.now().weekday;
    if (_dayOfWeek > 5) _dayOfWeek = 1;
    _lessonNumber = widget.lesson?.lessonNumber ?? widget.lessonNumber ?? 1;
    _startTime = widget.lesson?.startTime ?? widget.startTime ?? '08:00';
    _endTime = widget.lesson?.endTime ?? widget.endTime ?? '09:30';
    _selectedColor = widget.lesson?.color;
    _selectedLessonType = widget.lesson?.lessonType;
    _selectedWeekType = widget.lesson?.weekType ?? 'both';

    _subjectController.addListener(_onSubjectChanged);
  }

  void _onSubjectChanged() {
    if (widget.lesson != null) return;

    final subject = _subjectController.text.trim().toLowerCase();
    if (subject.isEmpty) return;

    final provider = context.read<AppProvider>();
    final existingLesson = provider.lessons.firstWhere(
      (l) => l.subject.toLowerCase() == subject,
      orElse: () => Lesson(
        id: '',
        subject: '',
        dayOfWeek: 1,
        startTime: '08:00',
        endTime: '09:30',
        lessonNumber: 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (existingLesson.id.isNotEmpty) {
      setState(() {
        if (_teacherController.text.isEmpty && existingLesson.teacher != null) {
          _teacherController.text = existingLesson.teacher!;
        }
        if (_roomController.text.isEmpty && existingLesson.room != null) {
          _roomController.text = existingLesson.room!;
        }
        if (_selectedColor == null && existingLesson.color != null) {
          _selectedColor = existingLesson.color;
        }
        if (_selectedLessonType == null && existingLesson.lessonType != null) {
          _selectedLessonType = existingLesson.lessonType;
        }
      });
    }
  }

  @override
  void dispose() {
    _subjectController.removeListener(_onSubjectChanged);
    _subjectController.dispose();
    _teacherController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.lesson != null ? 'Stunde bearbeiten' : 'Neue Stunde'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            TextField(controller: _subjectController, decoration: const InputDecoration(labelText: 'Fach', hintText: 'z.B. Mathematik'), autofocus: true),
            const SizedBox(height: 16),
            TextField(controller: _teacherController, decoration: const InputDecoration(labelText: 'Lehrer (optional)', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 16),
            TextField(controller: _roomController, decoration: const InputDecoration(labelText: 'Raum (optional)', prefixIcon: Icon(Icons.room))),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _dayOfWeek,
              decoration: const InputDecoration(labelText: 'Tag', prefixIcon: Icon(Icons.calendar_today)),
              items: const [
                DropdownMenuItem(value: 1, child: Text('Montag')),
                DropdownMenuItem(value: 2, child: Text('Dienstag')),
                DropdownMenuItem(value: 3, child: Text('Mittwoch')),
                DropdownMenuItem(value: 4, child: Text('Donnerstag')),
                DropdownMenuItem(value: 5, child: Text('Freitag')),
              ],
              onChanged: (value) => setState(() => _dayOfWeek = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _lessonNumber,
              decoration: const InputDecoration(labelText: 'Stunde', prefixIcon: Icon(Icons.format_list_numbered)),
              items: List.generate(10, (i) => i + 1).map((n) => DropdownMenuItem(value: n, child: Text('$n. Stunde'))).toList(),
              onChanged: (value) => setState(() => _lessonNumber = value!),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.access_time), title: const Text('Start'), subtitle: Text(_startTime), onTap: () => _selectTime(true))),
                Expanded(child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.access_time_filled), title: const Text('Ende'), subtitle: Text(_endTime), onTap: () => _selectTime(false))),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedLessonType,
              decoration: const InputDecoration(labelText: 'Kursart (optional)', prefixIcon: Icon(Icons.school)),
              items: const [
                DropdownMenuItem(value: null, child: Text('Keine Angabe')),
                DropdownMenuItem(value: 'Grundkurs', child: Text('Grundkurs')),
                DropdownMenuItem(value: 'Leistungskurs', child: Text('Leistungskurs')),
                DropdownMenuItem(value: 'Seminarkurs', child: Text('Seminarkurs')),
              ],
              onChanged: (value) => setState(() => _selectedLessonType = value),
            ),
            if (widget.abWeeksEnabled) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedWeekType,
                decoration: const InputDecoration(labelText: 'Woche', prefixIcon: Icon(Icons.calendar_view_week)),
                items: const [
                  DropdownMenuItem(value: 'both', child: Text('Beide Wochen')),
                  DropdownMenuItem(value: 'A', child: Text('Nur A-Woche')),
                  DropdownMenuItem(value: 'B', child: Text('Nur B-Woche')),
                ],
                onChanged: (value) => setState(() => _selectedWeekType = value!),
              ),
            ],
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Farbe', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _colorOptions.map((color) {
                    final isSelected = _selectedColor == color;
                    final colorValue = Color(int.parse(color.replaceFirst('#', '0xFF')));
                    final isWhite = color == '#FFFFFF';
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: colorValue,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? (isWhite ? Colors.black : Colors.white)
                                : (isWhite ? AppPalette.lineStrong : Colors.transparent),
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected ? [BoxShadow(color: colorValue.withValues(alpha: 0.5), blurRadius: 8)] : null,
                        ),
                        child: isSelected ? Icon(Icons.check, color: isWhite ? Colors.black : Colors.white, size: 16) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
      actions: [
        if (widget.lesson != null)
          TextButton(
            onPressed: () {
              context.read<AppProvider>().deleteLesson(widget.lesson!.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Löschen'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }

  Future<void> _selectTime(bool isStart) async {
    final currentTime = isStart ? _startTime : _endTime;
    final parts = currentTime.split(':');
    final initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));

    final time = await showTimePicker(context: context, initialTime: initialTime);
    if (time != null && mounted) {
      final formatted = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _startTime = formatted;
        } else {
          _endTime = formatted;
        }
      });
    }
  }

  void _save() {
    if (_subjectController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Fach eingeben')));
      return;
    }

    final provider = context.read<AppProvider>();

    if (widget.lesson != null) {
      provider.updateLesson(widget.lesson!.copyWith(
        subject: _subjectController.text.trim(),
        teacher: _teacherController.text.trim().isEmpty ? null : _teacherController.text.trim(),
        room: _roomController.text.trim().isEmpty ? null : _roomController.text.trim(),
        dayOfWeek: _dayOfWeek,
        lessonNumber: _lessonNumber,
        startTime: _startTime,
        endTime: _endTime,
        color: _selectedColor,
        lessonType: _selectedLessonType,
        weekType: _selectedWeekType,
      ));
    } else {
      provider.addLesson(
        subject: _subjectController.text.trim(),
        teacher: _teacherController.text.trim().isEmpty ? null : _teacherController.text.trim(),
        room: _roomController.text.trim().isEmpty ? null : _roomController.text.trim(),
        dayOfWeek: _dayOfWeek,
        lessonNumber: _lessonNumber,
        startTime: _startTime,
        endTime: _endTime,
        color: _selectedColor,
        lessonType: _selectedLessonType,
        weekType: _selectedWeekType,
      );
    }

    Navigator.pop(context);
  }
}

class _IServLoginDialog extends StatefulWidget {
  const _IServLoginDialog();

  @override
  State<_IServLoginDialog> createState() => _IServLoginDialogState();
}

class _IServLoginDialogState extends State<_IServLoginDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('IServ Anmeldung'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _urlController, decoration: const InputDecoration(labelText: 'IServ URL', hintText: 'z.B. gymnasium-berlin.de', prefixIcon: Icon(Icons.link)), keyboardType: TextInputType.url),
            const SizedBox(height: 16),
            TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Benutzername', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Passwort', prefixIcon: Icon(Icons.lock)), obscureText: true, autocorrect: false, enableSuggestions: false),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _isLoading ? null : _login,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Anmelden'),
        ),
      ],
    );
  }

  Future<void> _login() async {
    if (_urlController.text.trim().isEmpty || _usernameController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      setState(() => _error = 'Bitte alle Felder ausfüllen');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final provider = context.read<IServProvider>();
      final result = await provider.connect(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        iservUrl: _urlController.text.trim(),
      );

      if (mounted) {
        if (result['success'] == true) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IServ erfolgreich verbunden')));
        } else {
          setState(() { _error = result['error'] ?? 'Anmeldung fehlgeschlagen'; _isLoading = false; });
        }
      }
    } catch (e) {
      debugPrint('Connection error: $e');
      if (mounted) setState(() { _error = 'Verbindungsfehler. Bitte versuche es erneut.'; _isLoading = false; });
    }
  }
}

class _TabChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.isSelected, required this.onTap});

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.animateTo(0.95),
      onTapUp: (_) {
        _scaleController.animateTo(1.0);
        widget.onTap();
      },
      onTapCancel: () => _scaleController.animateTo(1.0),
      child: ScaleTransition(
        scale: _scaleController,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppTheme.primaryColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected
                  ? Colors.white
                  : AppPalette.ring,
              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

void showAddLessonDialog(
  BuildContext context, {
  int? dayOfWeek,
  int? lessonNumber,
  String? startTime,
  String? endTime,
  bool abWeeksEnabled = true,
}) {
  showDialog(
    context: context,
    builder: (context) => _LessonDialog(
      dayOfWeek: dayOfWeek,
      lessonNumber: lessonNumber,
      startTime: startTime,
      endTime: endTime,
      abWeeksEnabled: abWeeksEnabled,
    ),
  );
}

void showEditLessonDialog(BuildContext context, Lesson lesson, {bool abWeeksEnabled = true}) {
  showDialog(
    context: context,
    builder: (context) => _LessonDialog(
      lesson: lesson,
      abWeeksEnabled: abWeeksEnabled,
    ),
  );
}

class _FullscreenVertretungsplanViewer extends StatefulWidget {
  final List<Map<String, dynamic>> files;
  final int initialIndex;
  final bool isDark;

  const _FullscreenVertretungsplanViewer({
    required this.files,
    required this.initialIndex,
    required this.isDark,
  });

  @override
  State<_FullscreenVertretungsplanViewer> createState() => _FullscreenVertretungsplanViewerState();
}

class _FullscreenVertretungsplanViewerState extends State<_FullscreenVertretungsplanViewer> {
  late PageController _pageController;
  late int _currentPage;
  bool _isZoomed = false;
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final wasZoomed = _isZoomed;
    _isZoomed = scale > 1.05;
    if (wasZoomed != _isZoomed) {
      setState(() {});
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _toggleZoom(TapDownDetails details, BoxConstraints constraints) {
    final position = details.localPosition;
    if (_isZoomed) {
      _transformationController.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      final x = -position.dx * (scale - 1);
      final y = -position.dy * (scale - 1);
      _transformationController.value = Matrix4.identity()
        ..translateByDouble(x, y, 0.0, 1.0)
        ..scaleByDouble(scale, scale, scale, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.shortestSide >= 600;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              physics: _isZoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: widget.files.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
                _resetZoom();
              },
              itemBuilder: (context, index) {
                return _buildFullscreenImage(widget.files[index], index == _currentPage);
              },
            ),
            Positioned(
              top: isTablet ? 20 : 8,
              right: isTablet ? 20 : 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
            if (widget.files.length > 1)
              Positioned(
                bottom: isTablet ? 40 : 20,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentPage + 1} / ${widget.files.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(widget.files.length, (index) {
                        final isActive = index == _currentPage;
                        return GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            width: isActive ? 12 : 8,
                            height: isActive ? 12 : 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive ? Colors.white : Colors.white54,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            if (widget.files.length > 1 && _currentPage == widget.initialIndex)
              Positioned(
                bottom: isTablet ? 120 : 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swipe, color: Colors.white70, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Wischen zum Blättern',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreenImage(Map<String, dynamic> file, bool isCurrentPage) {
    final data = file['data'] as String?;
    final contentType = file['contentType'] as String? ?? '';

    if (data == null || data.isEmpty) {
      return const Center(
        child: Text(
          'Keine Daten',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    try {
      final bytes = base64Decode(data);

      if (contentType.contains('image')) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                GestureDetector(
                  onDoubleTapDown: isCurrentPage
                      ? (details) => _toggleZoom(details, constraints)
                      : null,
                  child: InteractiveViewer(
                    transformationController: isCurrentPage ? _transformationController : null,
                    minScale: 0.5,
                    maxScale: 5.0,
                    panEnabled: true,
                    scaleEnabled: true,
                    child: Center(
                      child: Image.memory(
                        Uint8List.fromList(bytes),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image, size: 64, color: Colors.white54),
                                SizedBox(height: 12),
                                Text(
                                  'Bild konnte nicht geladen werden',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (isCurrentPage && _isZoomed)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${(_transformationController.value.getMaxScaleOnAxis()).toStringAsFixed(1)}x',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (isCurrentPage && !_isZoomed)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app, color: Colors.white54, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Doppeltippen zum Zoomen',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      }

      if (contentType.contains('pdf')) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf, size: 80, color: Colors.white54),
              const SizedBox(height: 16),
              const Text(
                'PDF-Datei',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(bytes.length / 1024).toStringAsFixed(1)} KB',
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        );
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onDoubleTapDown: isCurrentPage
                ? (details) => _toggleZoom(details, constraints)
                : null,
            child: InteractiveViewer(
              transformationController: isCurrentPage ? _transformationController : null,
              minScale: 0.5,
              maxScale: 5.0,
              panEnabled: true,
              scaleEnabled: true,
              child: Center(
                child: Image.memory(
                  Uint8List.fromList(bytes),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Error loading content: $e');
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            SizedBox(height: 12),
            Text(
              'Ein Fehler ist aufgetreten.',
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }
}
