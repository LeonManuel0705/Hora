// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../models/event.dart';
import '../models/lesson.dart';
import '../models/quick_note.dart';
import '../services/database_service.dart' if (dart.library.html) '../services/database_service_web.dart';
import '../services/demo_data_service.dart';

class AppProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final DemoDataService _demo = DemoDataService();
  final _uuid = const Uuid();

  List<Task> _tasks = [];
  List<Event> _events = [];
  List<Lesson> _lessons = [];
  int _openTaskCount = 0;
  int _todayEventCount = 0;
  bool _isLoading = true;
  String? _error;
  ThemeMode _themeMode = ThemeMode.light;
  String _themeSwitchMode = 'system';
  TimeOfDay _scheduleLightTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _scheduleDarkTime = const TimeOfDay(hour: 20, minute: 0);
  Timer? _scheduleTimer;
  bool _demoMode = false;
  bool _abWeeksEnabled = true;
  bool _abWeekInverted = false;
  bool _timetableSetupCompleted = false;
  bool get timetableSetupCompleted => _timetableSetupCompleted;

  List<Task> get tasks => _demoMode ? _demo.getDemoTasks() : _tasks;
  String? _lastAddedTaskId;
  String? get lastAddedTaskId => _lastAddedTaskId;
  List<Event> get events => _demoMode ? _demo.getDemoEvents() : _events;
  List<Lesson> get lessons => _demoMode ? _demo.getDemoLessons() : _lessons;
  int get openTaskCount => _demoMode ? _demo.getDemoOpenTaskCount() : _openTaskCount;
  int get todayEventCount => _demoMode ? _demo.getDemoTodayEventCount() : _todayEventCount;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ThemeMode get themeMode => _themeSwitchMode == 'system' ? ThemeMode.system : _themeMode;
  String get themeSwitchMode => _themeSwitchMode;
  TimeOfDay get scheduleLightTime => _scheduleLightTime;
  TimeOfDay get scheduleDarkTime => _scheduleDarkTime;
  bool get demoMode => _demoMode;
  bool get abWeeksEnabled => _abWeeksEnabled;
  bool get abWeekInverted => _abWeekInverted;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _demoMode = prefs.getBool('demo_mode') ?? false;

      final themeModeStr = prefs.getString('theme_mode') ?? 'light';
      _themeMode = themeModeStr == 'light' ? ThemeMode.light : ThemeMode.dark;

      _themeSwitchMode = prefs.getString('theme_switch_mode') ?? 'system';
      _scheduleLightTime = TimeOfDay(
        hour: prefs.getInt('schedule_light_hour') ?? 7,
        minute: prefs.getInt('schedule_light_minute') ?? 0,
      );
      _scheduleDarkTime = TimeOfDay(
        hour: prefs.getInt('schedule_dark_hour') ?? 20,
        minute: prefs.getInt('schedule_dark_minute') ?? 0,
      );

      if (_themeSwitchMode == 'schedule') {
        _applyScheduleTheme();
        _startScheduleTimer();
      }

      _abWeeksEnabled = prefs.getBool('ab_weeks_enabled') ?? true;
      _abWeekInverted = prefs.getBool('ab_week_inverted') ?? false;

      _timetableSetupCompleted = prefs.getBool('timetable_setup_completed') ?? false;

      if (!_timetableSetupCompleted) {
        final existingPeriods = await _db.getTimetablePeriods();
        if (existingPeriods.isNotEmpty) {
          _timetableSetupCompleted = true;
          await prefs.setBool('timetable_setup_completed', true);
        }
      }

      if (!_demoMode) {
        await Future.wait([
          loadTasks(),
          loadEvents(),
          loadLessons(),
          loadStats(),
          loadTimetablePeriods(),
        ]);
      } else {

        await loadTimetablePeriods();
      }
    } catch (e) {
      debugPrint('AppProvider initialize error: $e');
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setDemoMode(bool enabled) async {
    _demoMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('demo_mode', enabled);
    notifyListeners();
  }

  Future<void> toggleDemoMode() async {
    await setDemoMode(!_demoMode);
  }

  Future<void> refresh() async {
    await initialize();
  }

  Future<void> loadTasks() async {
    try {
      _tasks = await _db.getTasks();
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('loadTasks error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<List<Task>> getTodayTasks() async {
    if (_demoMode) return _demo.getDemoTodayTasks();
    return await _db.getTodayTasks();
  }

  Future<List<Task>> getOpenTasks() async {
    if (_demoMode) return _demo.getDemoOpenTasks();
    return await _db.getOpenTasks();
  }

  Future<void> addTask({
    required String title,
    String? description,
    DateTime? dueDate,
    String priority = 'medium',
    String category = 'general',
    int? estimatedMinutes,
    String? repeatType,
    List<int>? repeatWeekdays,
    DateTime? repeatEndDate,
  }) async {
    final now = DateTime.now();
    final task = Task(
      id: _uuid.v4(),
      title: title,
      description: description,
      dueDate: dueDate,
      priority: priority,
      category: category,
      estimatedMinutes: estimatedMinutes,
      createdAt: now,
      updatedAt: now,
      repeatType: repeatType,
      repeatWeekdays: repeatWeekdays,
      repeatEndDate: repeatEndDate,
    );
    await _db.insertTask(task);
    _lastAddedTaskId = task.id;
    await loadTasks();
    await loadStats();
  }

  Future<void> updateTask(Task task) async {
    final updatedTask = task.copyWith(updatedAt: DateTime.now());
    await _db.updateTask(updatedTask);
    await loadTasks();
    await loadStats();
  }

  Future<void> toggleTaskComplete(String id) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == id);
    if (taskIndex != -1) {
      final task = _tasks[taskIndex];
      await _db.toggleTaskComplete(id, !task.completed);
      await loadTasks();
      await loadStats();
    }
  }

  Future<void> deleteTask(String id) async {
    await _db.deleteTask(id);
    await loadTasks();
    await loadStats();
  }

  Future<void> loadEvents() async {
    try {
      _events = await _db.getEvents();
      final holidayCount = _events.where((e) => e.category == 'holiday').length;
      final vacationCount = _events.where((e) => e.category == 'vacation').length;
      debugPrint('AppProvider: Loaded ${_events.length} events (holidays: $holidayCount, vacations: $vacationCount)');
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('loadEvents error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<List<Event>> getTodayEvents() async {
    if (_demoMode) return _demo.getDemoTodayEvents();
    return await _db.getTodayEvents();
  }

  Future<List<Event>> getUpcomingEvents({int days = 7}) async {
    if (_demoMode) return _demo.getDemoUpcomingEvents(days: days);
    return await _db.getUpcomingEvents(days: days);
  }

  Future<void> addEvent({
    required String title,
    String? description,
    String? location,
    required DateTime startTime,
    required DateTime endTime,
    bool allDay = false,
    String? color,
    String category = 'personal',
  }) async {
    final now = DateTime.now();
    final event = Event(
      id: _uuid.v4(),
      title: title,
      description: description,
      location: location,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      color: color,
      category: category,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insertEvent(event);
    await loadEvents();
    await loadStats();
  }

  Future<void> updateEvent(Event event) async {
    final updatedEvent = event.copyWith(updatedAt: DateTime.now());
    await _db.updateEvent(updatedEvent);
    await loadEvents();
    await loadStats();
  }

  Future<void> deleteEvent(String id) async {
    await _db.deleteEvent(id);
    await loadEvents();
    await loadStats();
  }

  Future<void> loadLessons() async {
    try {
      _lessons = await _db.getLessons();
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('loadLessons error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<List<Lesson>> getTodayLessons() async {
    if (_demoMode) return _demo.getDemoTodayLessons();
    return await _db.getTodayLessons();
  }

  Future<List<Lesson>> getLessonsByDay(int dayOfWeek) async {
    if (_demoMode) {
      return _demo.getDemoLessons().where((l) => l.dayOfWeek == dayOfWeek).toList();
    }
    return await _db.getLessonsByDay(dayOfWeek);
  }

  Future<void> addLesson({
    required String subject,
    String? teacher,
    String? room,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    required int lessonNumber,
    String? color,
    String? lessonType,
    String weekType = 'both',
  }) async {
    final now = DateTime.now();
    final lesson = Lesson(
      id: _uuid.v4(),
      subject: subject,
      teacher: teacher,
      room: room,
      dayOfWeek: dayOfWeek,
      startTime: startTime,
      endTime: endTime,
      lessonNumber: lessonNumber,
      color: color,
      lessonType: lessonType,
      weekType: weekType,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insertLesson(lesson);
    await loadLessons();
  }

  Future<void> updateLesson(Lesson lesson) async {
    final updatedLesson = lesson.copyWith(updatedAt: DateTime.now());
    await _db.updateLesson(updatedLesson);
    await loadLessons();
  }

  Future<void> deleteLesson(String id) async {
    await _db.deleteLesson(id);
    await loadLessons();
  }

  List<Map<String, dynamic>> _timetablePeriods = [];
  List<Map<String, dynamic>> get timetablePeriods => _timetablePeriods;

  Future<void> loadTimetablePeriods() async {
    try {
      _timetablePeriods = await _db.getTimetablePeriods();

      if (_timetablePeriods.isEmpty && _timetableSetupCompleted) {
        await _db.seedDefaultTimetablePeriods();
        _timetablePeriods = await _db.getTimetablePeriods();
      }
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('loadTimetablePeriods error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> addTimetablePeriod({
    required int periodNumber,
    String? name,
    required String startTime,
    required String endTime,
    bool hasSplit = false,
    int? splitBreakMinutes,
  }) async {
    await _db.insertTimetablePeriod(
      periodNumber: periodNumber,
      name: name,
      startTime: startTime,
      endTime: endTime,
      hasSplit: hasSplit,
      splitBreakMinutes: splitBreakMinutes,
    );
    await loadTimetablePeriods();
  }

  Future<void> updateTimetablePeriod({
    required int periodNumber,
    String? name,
    String? startTime,
    String? endTime,
    bool? hasSplit,
    int? splitBreakMinutes,
  }) async {
    await _db.updateTimetablePeriod(
      periodNumber: periodNumber,
      name: name,
      startTime: startTime,
      endTime: endTime,
      hasSplit: hasSplit,
      splitBreakMinutes: splitBreakMinutes,
    );
    await loadTimetablePeriods();
  }

  Future<void> deleteTimetablePeriod(int periodNumber) async {
    await _db.deleteTimetablePeriod(periodNumber);
    await loadTimetablePeriods();
  }

  Future<void> setTimetableSetupCompleted(bool value) async {
    _timetableSetupCompleted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('timetable_setup_completed', value);
    notifyListeners();
  }

  Future<void> replaceAllTimetablePeriods(List<Map<String, dynamic>> periods) async {
    await _db.clearTimetablePeriods();
    for (final p in periods) {
      await _db.insertTimetablePeriod(
        periodNumber: p['periodNumber'] as int,
        name: p['name'] as String?,
        startTime: p['startTime'] as String,
        endTime: p['endTime'] as String,
        hasSplit: p['hasSplit'] as bool? ?? false,
        splitBreakMinutes: p['splitBreakMinutes'] as int?,
      );
    }
    await setTimetableSetupCompleted(true);
    await loadTimetablePeriods();
  }

  static bool calculateIsAWeek(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final firstDayOfYear = DateTime.utc(date.year, 1, 1);
    final daysSinceFirst = day.difference(firstDayOfYear).inDays;
    final weekNumber = (daysSinceFirst + firstDayOfYear.weekday - 1) ~/ 7 + 1;
    return weekNumber % 2 == 0;
  }

  static String getWeekTypeForDate(DateTime date) {
    return calculateIsAWeek(date) ? 'A' : 'B';
  }

  List<Lesson> getLessonsForDayAndWeek(int dayOfWeek, String weekType, {bool abWeeksEnabled = true}) {
    final allLessons = _demoMode ? _demo.getDemoLessons() : _lessons;
    return allLessons.where((l) {
      if (l.dayOfWeek != dayOfWeek) return false;
      if (!abWeeksEnabled) return true;
      return l.weekType == 'both' || l.weekType == weekType;
    }).toList()..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
  }

  Future<void> loadStats() async {
    try {
      _openTaskCount = await _db.getOpenTaskCount();
      _todayEventCount = await _db.getTodayEventCount();
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('loadStats error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _themeMode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> setThemeSwitchMode(String mode) async {
    _themeSwitchMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_switch_mode', mode);

    _scheduleTimer?.cancel();
    _scheduleTimer = null;

    if (mode == 'schedule') {
      _applyScheduleTheme();
      _startScheduleTimer();
    }
    notifyListeners();
  }

  Future<void> setScheduleTimes({TimeOfDay? lightTime, TimeOfDay? darkTime}) async {
    if (lightTime != null) _scheduleLightTime = lightTime;
    if (darkTime != null) _scheduleDarkTime = darkTime;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('schedule_light_hour', _scheduleLightTime.hour);
    await prefs.setInt('schedule_light_minute', _scheduleLightTime.minute);
    await prefs.setInt('schedule_dark_hour', _scheduleDarkTime.hour);
    await prefs.setInt('schedule_dark_minute', _scheduleDarkTime.minute);

    if (_themeSwitchMode == 'schedule') {
      _applyScheduleTheme();
    }
    notifyListeners();
  }

  void _applyScheduleTheme() {
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final lightMinutes = _scheduleLightTime.hour * 60 + _scheduleLightTime.minute;
    final darkMinutes = _scheduleDarkTime.hour * 60 + _scheduleDarkTime.minute;

    bool shouldBeLight;
    if (lightMinutes < darkMinutes) {
      shouldBeLight = nowMinutes >= lightMinutes && nowMinutes < darkMinutes;
    } else {
      shouldBeLight = nowMinutes >= lightMinutes || nowMinutes < darkMinutes;
    }

    final newMode = shouldBeLight ? ThemeMode.light : ThemeMode.dark;
    if (_themeMode != newMode) {
      _themeMode = newMode;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('theme_mode', newMode == ThemeMode.light ? 'light' : 'dark');
      });
      notifyListeners();
    }
  }

  void _startScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _applyScheduleTheme();
    });
  }

  Future<void> setAbWeeksEnabled(bool enabled) async {
    _abWeeksEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ab_weeks_enabled', enabled);
    notifyListeners();
  }

  bool isCurrentlyAWeek([DateTime? date]) {
    final raw = calculateIsAWeek(date ?? DateTime.now());
    return _abWeekInverted ? !raw : raw;
  }

  String getEffectiveWeekType([DateTime? date]) {
    return isCurrentlyAWeek(date) ? 'A' : 'B';
  }

  Future<void> setAbWeekInverted(bool inverted) async {
    _abWeekInverted = inverted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ab_week_inverted', inverted);
    notifyListeners();
  }

  Future<void> toggleAbWeekInversion() async {
    await setAbWeekInverted(!_abWeekInverted);
  }

  Future<List<Map<String, dynamic>>> getSubjects() async {
    if (_demoMode) return _demo.getDemoSubjects();
    return await _db.getSubjects();
  }

  Future<int> addSubject({
    required String name,
    String? shortName,
    String? color,
    String? teacher,
    String? room,
  }) async {
    return await _db.insertSubject(
      name: name,
      shortName: shortName,
      color: color,
      teacher: teacher,
      room: room,
    );
  }

  Future<void> addHomework({
    required String title,
    int? subjectId,
    String? notes,
    DateTime? dueDate,
  }) async {
    await _db.insertHomework(
      id: _uuid.v4(),
      title: title,
      subjectId: subjectId,
      notes: notes,
      dueDate: dueDate,
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getHomework() async {
    if (_demoMode) return _demo.getDemoHomework();
    return await _db.getHomework();
  }

  Future<List<Map<String, dynamic>>> getOpenHomework() async {
    if (_demoMode) return _demo.getDemoOpenHomework();
    return await _db.getOpenHomework();
  }

  Future<void> toggleHomeworkComplete(String id, bool completed) async {
    await _db.toggleHomeworkComplete(id, completed);
    notifyListeners();
  }

  Future<void> deleteHomework(String id) async {
    await _db.deleteHomework(id);
    notifyListeners();
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    super.dispose();
  }

  Future<void> addQuickNote({
    required String type,
    required String title,
    String? content,
  }) async {
    final now = DateTime.now();
    final wordCount = QuickNote.calculateWordCount(content ?? '');

    final note = QuickNote(
      id: _uuid.v4(),
      type: type,
      title: title,
      content: content ?? '',
      wordCount: wordCount,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insertQuickNote(note);
    notifyListeners();
  }
}
