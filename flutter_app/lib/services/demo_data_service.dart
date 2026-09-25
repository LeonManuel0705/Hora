// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import '../brand.dart';
import '../build_info.dart';
import '../models/task.dart';
import '../models/event.dart';
import '../models/lesson.dart';

class DemoDataService {
  static final DemoDataService _instance = DemoDataService._internal();
  factory DemoDataService() => _instance;
  DemoDataService._internal();

  DateTime get _todayMidnight {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
  DateTime get _today => _todayMidnight;
  DateTime get _tomorrow => _todayMidnight.add(const Duration(days: 1));
  DateTime get _dayAfterTomorrow => _todayMidnight.add(const Duration(days: 2));

  List<Task> getDemoTasks() {
    final now = DateTime.now();
    return [
      Task(
        id: 'demo-task-1',
        title: '${Brand.name} v${BuildInfo.version} Features planen',
        description: 'Neue Features für die nächste Version dokumentieren',
        dueDate: _today,
        completed: false,
        priority: 'high',
        category: 'project',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now,
      ),
      Task(
        id: 'demo-task-2',
        title: 'Mathe-Hausaufgaben',
        description: 'Seite 42, Aufgaben 1-5',
        dueDate: _tomorrow,
        completed: false,
        priority: 'high',
        category: 'school',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      ),
      Task(
        id: 'demo-task-3',
        title: 'Landing Page aktualisieren',
        description: 'Screenshots hinzufügen',
        dueDate: _today,
        completed: false,
        priority: 'medium',
        category: 'project',
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now,
      ),
      Task(
        id: 'demo-task-4',
        title: 'Trainingsplan erstellen',
        description: 'Wochenplan für Krafttraining',
        dueDate: _dayAfterTomorrow,
        completed: false,
        priority: 'medium',
        category: 'training',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now,
      ),
      Task(
        id: 'demo-task-5',
        title: 'Englisch-Vokabeln lernen',
        description: 'Unit 5 - 50 Vokabeln',
        dueDate: _tomorrow,
        completed: false,
        priority: 'medium',
        category: 'school',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now,
      ),
      Task(
        id: 'demo-task-6',
        title: 'Projekt-Präsentation vorbereiten',
        description: 'Folien für Informatik-Kurs',
        dueDate: _dayAfterTomorrow,
        completed: false,
        priority: 'high',
        category: 'school',
        createdAt: now.subtract(const Duration(days: 4)),
        updatedAt: now,
      ),
      Task(
        id: 'demo-task-7',
        title: 'Zimmer aufräumen',
        dueDate: null,
        completed: true,
        priority: 'low',
        category: 'personal',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 3)),
      ),
      Task(
        id: 'demo-task-8',
        title: 'Bug-Fix: Kalender-Sync',
        description: 'Google Calendar Events werden nicht aktualisiert',
        dueDate: _today,
        completed: true,
        priority: 'high',
        category: 'project',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
      Task(
        id: 'demo-task-9',
        title: 'Einkaufsliste schreiben',
        completed: true,
        priority: 'low',
        category: 'personal',
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 5)),
      ),
    ];
  }

  List<Task> getDemoTodayTasks() {
    return getDemoTasks()
        .where((t) => !t.completed && (t.dueDate == null || _isSameDay(t.dueDate!, _today)))
        .toList();
  }

  List<Task> getDemoOpenTasks() {
    return getDemoTasks().where((t) => !t.completed).toList();
  }

  List<Event> getDemoEvents() {
    final now = DateTime.now();
    return [
      Event(
        id: 'demo-event-1',
        title: 'Team-Meeting: ${Brand.name}',
        description: 'Wöchentliches Sync-Meeting',
        location: 'Online (Discord)',
        startTime: DateTime(_today.year, _today.month, _today.day, 14, 0),
        endTime: DateTime(_today.year, _today.month, _today.day, 15, 0),
        allDay: false,
        color: '#6366F1',
        category: 'work',
        createdAt: now.subtract(const Duration(days: 7)),
        updatedAt: now,
      ),
      Event(
        id: 'demo-event-2',
        title: 'Fitness-Studio',
        description: 'Beintraining',
        location: 'FitX Berlin',
        startTime: DateTime(_today.year, _today.month, _today.day, 17, 30),
        endTime: DateTime(_today.year, _today.month, _today.day, 19, 0),
        allDay: false,
        color: '#10B981',
        category: 'training',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now,
      ),
      Event(
        id: 'demo-event-3',
        title: 'Klausur: Mathematik',
        description: 'Analysis - Integralrechnung',
        location: 'Raum A204',
        startTime: DateTime(_tomorrow.year, _tomorrow.month, _tomorrow.day, 8, 0),
        endTime: DateTime(_tomorrow.year, _tomorrow.month, _tomorrow.day, 9, 30),
        allDay: false,
        color: '#EF4444',
        category: 'school',
        createdAt: now.subtract(const Duration(days: 14)),
        updatedAt: now,
      ),
      Event(
        id: 'demo-event-4',
        title: 'Arzttermin',
        description: 'Routine-Untersuchung',
        location: 'Praxis Dr. Müller',
        startTime: DateTime(_tomorrow.year, _tomorrow.month, _tomorrow.day, 15, 0),
        endTime: DateTime(_tomorrow.year, _tomorrow.month, _tomorrow.day, 15, 30),
        allDay: false,
        color: '#F59E0B',
        category: 'personal',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now,
      ),
      Event(
        id: 'demo-event-5',
        title: 'Geburtstag: Max',
        startTime: DateTime(_dayAfterTomorrow.year, _dayAfterTomorrow.month, _dayAfterTomorrow.day),
        endTime: DateTime(_dayAfterTomorrow.year, _dayAfterTomorrow.month, _dayAfterTomorrow.day, 23, 59),
        allDay: true,
        color: '#EC4899',
        category: 'personal',
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now,
      ),
      Event(
        id: 'demo-event-6',
        title: 'Code-Review Session',
        description: 'PR #42 besprechen',
        location: 'GitHub / Discord',
        startTime: DateTime(_dayAfterTomorrow.year, _dayAfterTomorrow.month, _dayAfterTomorrow.day, 19, 0),
        endTime: DateTime(_dayAfterTomorrow.year, _dayAfterTomorrow.month, _dayAfterTomorrow.day, 20, 30),
        allDay: false,
        color: '#8B5CF6',
        category: 'work',
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now,
      ),
    ];
  }

  List<Event> getDemoTodayEvents() {
    return getDemoEvents()
        .where((e) => _isSameDay(e.startTime, _today))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  List<Event> getDemoUpcomingEvents({int days = 7}) {
    final endDate = _today.add(Duration(days: days));
    return getDemoEvents()
        .where((e) => e.startTime.isAfter(_today.subtract(const Duration(days: 1))) &&
                      e.startTime.isBefore(endDate))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  List<Lesson> getDemoLessons() {
    final now = DateTime.now();
    final todayWeekday = _today.weekday;

    return [
      Lesson(
        id: 'demo-lesson-1',
        subject: 'Mathematik',
        teacher: 'Hr. Schmidt',
        room: 'A204',
        dayOfWeek: todayWeekday,
        startTime: '08:00',
        endTime: '09:30',
        lessonNumber: 1,
        color: '#EF4444',
        weekType: 'both',
        createdAt: now,
        updatedAt: now,
      ),
      Lesson(
        id: 'demo-lesson-2',
        subject: 'Englisch',
        teacher: 'Fr. Weber',
        room: 'B112',
        dayOfWeek: todayWeekday,
        startTime: '09:45',
        endTime: '11:15',
        lessonNumber: 2,
        color: '#3B82F6',
        weekType: 'A',
        createdAt: now,
        updatedAt: now,
      ),
      Lesson(
        id: 'demo-lesson-2b',
        subject: 'Physik',
        teacher: 'Hr. Klein',
        room: 'C203',
        dayOfWeek: todayWeekday,
        startTime: '09:45',
        endTime: '11:15',
        lessonNumber: 2,
        color: '#22C55E',
        weekType: 'B',
        createdAt: now,
        updatedAt: now,
      ),
      Lesson(
        id: 'demo-lesson-3',
        subject: 'Informatik',
        teacher: 'Hr. Muller',
        room: 'PC-Raum 1',
        dayOfWeek: todayWeekday,
        startTime: '11:30',
        endTime: '13:00',
        lessonNumber: 3,
        color: '#8B5CF6',
        weekType: 'both',
        createdAt: now,
        updatedAt: now,
      ),
      Lesson(
        id: 'demo-lesson-4',
        subject: 'Deutsch',
        teacher: 'Fr. Fischer',
        room: 'A108',
        dayOfWeek: todayWeekday,
        startTime: '13:45',
        endTime: '15:15',
        lessonNumber: 4,
        color: '#F59E0B',
        weekType: 'both',
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  List<Lesson> getDemoTodayLessons() {
    final todayWeekday = _today.weekday;
    return getDemoLessons()
        .where((l) => l.dayOfWeek == todayWeekday)
        .toList()
      ..sort((a, b) => a.lessonNumber.compareTo(b.lessonNumber));
  }

  List<Map<String, dynamic>> getDemoHomework() {
    return [
      {
        'id': 'demo-hw-1',
        'title': 'Integralrechnung Übungen',
        'subject_id': 1,
        'subject_name': 'Mathematik',
        'subject_color': '#EF4444',
        'notes': 'Seite 142, Aufgaben 3-8',
        'due_date': _tomorrow.toIso8601String(),
        'completed': 0,
      },
      {
        'id': 'demo-hw-2',
        'title': 'Essay: Climate Change',
        'subject_id': 2,
        'subject_name': 'Englisch',
        'subject_color': '#3B82F6',
        'notes': '500 Wörter minimum',
        'due_date': _dayAfterTomorrow.toIso8601String(),
        'completed': 0,
      },
      {
        'id': 'demo-hw-3',
        'title': 'Python-Projekt abgeben',
        'subject_id': 3,
        'subject_name': 'Informatik',
        'subject_color': '#8B5CF6',
        'notes': 'GitHub-Link in IServ hochladen',
        'due_date': _today.add(const Duration(days: 3)).toIso8601String(),
        'completed': 0,
      },
    ];
  }

  List<Map<String, dynamic>> getDemoOpenHomework() {
    return getDemoHomework().where((h) => h['completed'] == 0).toList();
  }

  List<Map<String, dynamic>> getDemoSubjects() {
    return [
      {'id': 1, 'name': 'Mathematik', 'short_name': 'Ma', 'color': '#EF4444', 'teacher': 'Hr. Schmidt', 'room': 'A204'},
      {'id': 2, 'name': 'Englisch', 'short_name': 'En', 'color': '#3B82F6', 'teacher': 'Fr. Weber', 'room': 'B112'},
      {'id': 3, 'name': 'Informatik', 'short_name': 'Inf', 'color': '#8B5CF6', 'teacher': 'Hr. Müller', 'room': 'PC-Raum 1'},
      {'id': 4, 'name': 'Deutsch', 'short_name': 'De', 'color': '#F59E0B', 'teacher': 'Fr. Fischer', 'room': 'A108'},
      {'id': 5, 'name': 'Physik', 'short_name': 'Ph', 'color': '#10B981', 'teacher': 'Hr. Becker', 'room': 'N201'},
    ];
  }

  Map<String, dynamic> getDemoTrainingData() {
    return {
      'sessions': [
        {
          'id': 1,
          'type': 'Krafttraining',
          'date': _today.subtract(const Duration(days: 1)).toIso8601String().split('T')[0],
          'duration': 75,
          'exercises': 'Bankdrücken, Schulterdrücken, Trizeps',
          'notes': 'Neuer PR bei Bankdrücken: 80kg',
        },
        {
          'id': 2,
          'type': 'Cardio',
          'date': _today.subtract(const Duration(days: 3)).toIso8601String().split('T')[0],
          'duration': 45,
          'exercises': '5km Laufen',
          'notes': 'Gutes Tempo, 5:30 min/km',
        },
        {
          'id': 3,
          'type': 'Krafttraining',
          'date': _today.subtract(const Duration(days: 4)).toIso8601String().split('T')[0],
          'duration': 60,
          'exercises': 'Kniebeugen, Beinpresse, Wadenheben',
          'notes': '',
        },
      ],
      'goals': [
        {
          'id': 1,
          'title': '100kg Bankdrücken',
          'target': '100',
          'deadline': _today.add(const Duration(days: 60)).toIso8601String().split('T')[0],
          'completed': false,
        },
        {
          'id': 2,
          'title': '10km unter 50 Minuten',
          'target': '50:00',
          'deadline': _today.add(const Duration(days: 30)).toIso8601String().split('T')[0],
          'completed': false,
        },
      ],
      'schedule': {
        'monday': 'Brust & Trizeps',
        'tuesday': 'Rücken & Bizeps',
        'wednesday': 'Ruhetag',
        'thursday': 'Beine',
        'friday': 'Schultern & Arme',
        'saturday': 'Cardio',
        'sunday': 'Ruhetag',
      },
    };
  }

  int getDemoOpenTaskCount() {
    return getDemoTasks().where((t) => !t.completed).length;
  }

  int getDemoTodayEventCount() {
    return getDemoTodayEvents().length;
  }

  int getDemoCompletedTaskCount() {
    return getDemoTasks().where((t) => t.completed).length;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
