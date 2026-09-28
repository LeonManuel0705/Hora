// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../theme.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/glass_card.dart';
import '../widgets/page_fade_in.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  final DatabaseService _db = DatabaseService();

  DateTime _selectedWeekStart = DateTime.now();
  bool _isLoading = true;
  String? _error;

  List<TrainingEntry> _regularSchedule = [];
  List<TrainingEntry> _holidaySchedule = [];
  List<TrainingSession> _sessions = [];
  List<HealthLog> _healthLogs = [];
  List<TrainingGoal> _goals = [];

  bool _isHolidayMode = false;

  List<TrainingEntry> get _currentSchedule =>
      _isHolidayMode ? _holidaySchedule : _regularSchedule;

  @override
  void initState() {
    super.initState();
    _selectedWeekStart = _getWeekStart(DateTime.now());
    _loadData();
  }

  DateTime _getWeekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  int _getWeekNumber(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final thursday = day.add(Duration(days: 4 - day.weekday));
    final dayOfYear = thursday.difference(DateTime.utc(thursday.year, 1, 1)).inDays + 1;
    return (dayOfYear - 1) ~/ 7 + 1;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final regularMaps = await _db.getTrainingSchedule(isHoliday: false);
      final holidayMaps = await _db.getTrainingSchedule(isHoliday: true);
      final sessionMaps = await _db.getTrainingSessionsList();
      final healthMaps = await _db.getHealthLogsList();
      final goalMaps = await _db.getTrainingGoalsList();

      _regularSchedule = regularMaps.map((m) => TrainingEntry.fromMap(m as Map<String, dynamic>)).toList();
      _holidaySchedule = holidayMaps.map((m) => TrainingEntry.fromMap(m as Map<String, dynamic>)).toList();
      _sessions = sessionMaps.map((m) => TrainingSession.fromMap(m as Map<String, dynamic>)).toList();
      _healthLogs = healthMaps.map((m) => HealthLog.fromMap(m as Map<String, dynamic>)).toList();
      _goals = goalMaps.map((m) => TrainingGoal.fromMap(m as Map<String, dynamic>)).toList();
      _isHolidayMode = await _db.getTrainingHolidayMode();
    } catch (e, stackTrace) {
      debugPrint('TrainingScreen._loadData error: $e');
      debugPrint('Stack trace: $stackTrace');
      _error = 'Fehler beim Laden der Trainingsdaten.';
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = DateTime(_selectedWeekStart.year, _selectedWeekStart.month, _selectedWeekStart.day - 7);
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedWeekStart = DateTime(_selectedWeekStart.year, _selectedWeekStart.month, _selectedWeekStart.day + 7);
    });
  }

  void _goToCurrentWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
    });
  }

  Future<void> _toggleHolidayMode() async {
    final newMode = !_isHolidayMode;
    debugPrint('Toggling holiday mode: $_isHolidayMode -> $newMode');
    setState(() => _isHolidayMode = newMode);
    await _db.setTrainingHolidayMode(_isHolidayMode);
    debugPrint('Holiday mode saved. Current schedule has ${_currentSchedule.length} entries');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageFadeIn(
      child: Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isLoading
              ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
              : _error != null
                  ? KeyedSubtree(key: const ValueKey('error'), child: _buildErrorView())
                  : RefreshIndicator(
                      key: const ValueKey('content'),
                      onRefresh: _loadData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            _buildModeToggle(isDark),
                            const SizedBox(height: 16),

                            _buildWeekNavigation(),
                            const SizedBox(height: 16),

                            _buildPlanTypeInfo(),
                            const SizedBox(height: 16),

                            _buildScheduleSection(),
                            const SizedBox(height: 24),

                            _buildTodaySession(),
                            const SizedBox(height: 24),

                            _buildHealthSection(),
                            const SizedBox(height: 24),

                            _buildGoalsSection(),
                            const SizedBox(height: 120),
                          ],
                        ),
                      ),
                    ),
        ),
        Positioned(
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
          child: PageFadeIn(
            delay: const Duration(milliseconds: 300),
            child: FloatingActionButton(
              heroTag: 'fab_training',
              onPressed: _showAddOptions,
              backgroundColor: AppTheme.trainingColor,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildModeToggle(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: AppTheme.gradientText('Training', fontSize: 36),
        ),

        Container(
          decoration: BoxDecoration(
            gradient: _isHolidayMode
                ? null
                : LinearGradient(
                    colors: AppTheme.primaryGradient,
                  ),
            color: _isHolidayMode ? AppTheme.warning : null,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _toggleHolidayMode,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isHolidayMode ? Icons.beach_access : Icons.fitness_center,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isHolidayMode ? 'Ferien' : 'Normal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsets? padding}) {
    return GlassCard(
      borderRadius: 16,
      padding: padding ?? const EdgeInsets.all(16),
      enableTapScale: false,
      child: child,
    );
  }

  Widget _buildWeekNavigation() {
    final weekNum = _getWeekNumber(_selectedWeekStart);
    final isCurrentWeek = _getWeekStart(DateTime.now()) == _selectedWeekStart;

    return _buildGlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previousWeek,
          ),
          Expanded(
            child: GestureDetector(
              onTap: _goToCurrentWeek,
              child: Column(
                children: [
                  Text(
                    'KW $weekNum',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${DateFormat('d. MMM', 'de_DE').format(_selectedWeekStart)} - ${DateFormat('d. MMM yyyy', 'de_DE').format(_selectedWeekStart.add(const Duration(days: 6)))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _nextWeek,
          ),
          if (!isCurrentWeek)
            TextButton(
              onPressed: _goToCurrentWeek,
              child: const Text('Heute'),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanTypeInfo() {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      tint: _isHolidayMode ? AppTheme.warning : AppTheme.primaryColor,
      enableTapScale: false,
      child: Row(
        children: [
          Icon(
            _isHolidayMode ? Icons.beach_access : Icons.fitness_center,
            color: _isHolidayMode ? AppTheme.warning : AppTheme.primaryColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isHolidayMode ? 'Ferientrainingsplan' : 'Regulärer Trainingsplan',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isHolidayMode ? AppTheme.warning : AppTheme.primaryColor,
                  ),
                ),
                Text(
                  _isHolidayMode
                      ? 'Angepasster Plan für die Ferienzeit'
                      : 'Dein normaler Wochenplan',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showEditScheduleScreen(),
            child: const Text('Bearbeiten'),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    final schedule = _currentSchedule;
    final dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

    return _buildGlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.calendar_view_week, size: 20, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Trainingsplan',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (schedule.isEmpty)
                  TextButton.icon(
                    onPressed: () => _showEditScheduleScreen(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Plan erstellen'),
                  ),
              ],
            ),
          ),
          if (schedule.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 48,
                      color: AppPalette.ring.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Noch kein Trainingsplan erstellt',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tippe auf "Plan erstellen" um deinen\npersönlichen Trainingsplan anzulegen',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 7,
              separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
              itemBuilder: (context, index) {
                final dayIndex = index + 1;
                final entry = schedule.where((e) => e.day == dayIndex).firstOrNull;
                final date = _selectedWeekStart.add(Duration(days: index));
                final isToday = DateFormat('yyyy-MM-dd').format(date) ==
                    DateFormat('yyyy-MM-dd').format(DateTime.now());
                final session = _sessions.where((s) =>
                    DateFormat('yyyy-MM-dd').format(s.date) ==
                    DateFormat('yyyy-MM-dd').format(date)).firstOrNull;

                return AnimatedListItem(
                  index: index,
                  child: _ScheduleDayTile(
                    dayName: dayNames[index],
                    date: date,
                    entry: entry,
                    isToday: isToday,
                    isCompleted: session != null,
                    onTap: () => _showEditDayDialog(dayIndex, entry),
                    onComplete: entry != null ? () => _toggleDayComplete(date, entry) : null,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTodaySession() {
    final today = DateTime.now();
    final correctEntry = _currentSchedule.where((e) => e.day == today.weekday).firstOrNull;

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today, size: 20, color: AppTheme.accentColor),
              const SizedBox(width: 8),
              Text(
                'Heute',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
            if (correctEntry == null || correctEntry.type == 'rest')
              GlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.all(20),
                tint: AppTheme.success,
                enableTapScale: false,
                child: Row(
                  children: [
                    Text(
                      correctEntry?.icon ?? '😴',
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            correctEntry?.title ?? 'Ruhetag',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (correctEntry?.notes != null)
                            Text(
                              correctEntry!.notes!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              GlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.all(20),
                tint: AppTheme.accentColor,
                enableTapScale: false,
                child: Row(
                  children: [
                    Text(
                      correctEntry.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            correctEntry.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (correctEntry.muscleGroups != null)
                            Text(
                              correctEntry.muscleGroups!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => _logSession(correctEntry),
                      child: const Text('Starten'),
                    ),
                  ],
                ),
              ),
          ],
        ),
    );
  }

  Widget _buildHealthSection() {
    final todayLog = _healthLogs.where((h) =>
        DateFormat('yyyy-MM-dd').format(h.date) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now())).firstOrNull;

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite, size: 20, color: AppTheme.trainingColor),
              const SizedBox(width: 8),
              Text(
                'Wohlbefinden',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showHealthLogDialog(todayLog),
                child: Text(todayLog != null ? 'Bearbeiten' : 'Eintragen'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HealthStatCard(
                icon: Icons.bedtime,
                label: 'Schlaf',
                value: todayLog?.sleep != null ? '${todayLog!.sleep}h' : '--',
                color: AppTheme.info,
              ),
              const SizedBox(width: 12),
              _HealthStatCard(
                icon: Icons.bolt,
                label: 'Energie',
                value: todayLog?.energy != null ? '${todayLog!.energy}/10' : '--',
                color: AppTheme.warning,
              ),
              const SizedBox(width: 12),
              _HealthStatCard(
                icon: Icons.psychology,
                label: 'Stress',
                value: todayLog?.stress != null ? '${todayLog!.stress}/10' : '--',
                color: AppTheme.danger,
              ),
              const SizedBox(width: 12),
              _HealthStatCard(
                icon: Icons.healing,
                label: 'Erholung',
                value: todayLog?.recovery != null ? '${todayLog!.recovery}/10' : '--',
                color: AppTheme.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGoalsSection() {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, size: 20, color: AppTheme.success),
              const SizedBox(width: 8),
              Text(
                'Ziele',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _showGoalDialog(null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_goals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'Keine Ziele gesetzt\nTippe auf + um ein Ziel hinzuzufügen',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            ...(_goals.asMap().entries.map((e) => AnimatedListItem(
                  index: e.key,
                  child: _GoalTile(
                    goal: e.value,
                    onEdit: () => _showGoalDialog(e.value),
                    onDelete: () => _deleteGoal(e.value),
                    onToggle: () => _toggleGoal(e.value),
                  ),
                ))),
        ],
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('Training eintragen'),
              onTap: () {
                Navigator.pop(context);
                _logQuickSession();
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('Wohlbefinden eintragen'),
              onTap: () {
                Navigator.pop(context);
                _showHealthLogDialog(null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('Ziel hinzufügen'),
              onTap: () {
                Navigator.pop(context);
                _showGoalDialog(null);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar),
              title: const Text('Trainingsplan bearbeiten'),
              onTap: () {
                Navigator.pop(context);
                _showEditScheduleScreen();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditScheduleScreen() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final isHolidayAtOpen = _isHolidayMode;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) => _EditScheduleScreen(
          schedule: _currentSchedule,
          isHoliday: isHolidayAtOpen,
          onSave: (schedule) async {
            try {
              debugPrint('Saving full schedule with ${schedule.length} entries, isHoliday: $isHolidayAtOpen');
              await _db.saveTrainingSchedule(schedule, isHoliday: isHolidayAtOpen);
              await _loadData();
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Trainingsplan gespeichert!'),
                  backgroundColor: AppTheme.success,
                ),
              );
            } catch (e) {
              debugPrint('Error saving schedule: $e');
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Ein Fehler ist aufgetreten. Bitte versuche es erneut.'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  void _showEditDayDialog(int dayIndex, TrainingEntry? existing) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final isHolidayAtOpen = _isHolidayMode;
    final scheduleAtOpen = List<TrainingEntry>.from(_currentSchedule);
    final dayNames = ['', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => _EditDayBottomSheet(
        dayIndex: dayIndex,
        dayName: dayNames[dayIndex],
        existing: existing,
      ),
    );

    if (result is String && result == 'delete') {
      try {
        final schedule = List<TrainingEntry>.from(scheduleAtOpen);
        schedule.removeWhere((e) => e.day == dayIndex);
        debugPrint('Deleting day $dayIndex, saving schedule with ${schedule.length} entries, isHoliday: $isHolidayAtOpen');
        await _db.saveTrainingSchedule(schedule, isHoliday: isHolidayAtOpen);
        await _loadData();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Tag gelöscht!'),
            backgroundColor: AppTheme.success,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('Error deleting day: $e');
        debugPrint('Stack trace: $stackTrace');
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Löschen. Bitte versuche es erneut.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } else if (result != null) {
      try {
        final schedule = List<TrainingEntry>.from(scheduleAtOpen);
        schedule.removeWhere((e) => e.day == dayIndex);
        schedule.add(result as TrainingEntry);
        debugPrint('Saving schedule with ${schedule.length} entries, isHoliday: $isHolidayAtOpen');
        await _db.saveTrainingSchedule(schedule, isHoliday: isHolidayAtOpen);
        debugPrint('Schedule saved, reloading data...');
        await _loadData();
        debugPrint('Data reloaded. Regular: ${_regularSchedule.length}, Holiday: ${_holidaySchedule.length}');
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Tag gespeichert!'),
            backgroundColor: AppTheme.success,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('Error saving day: $e');
        debugPrint('Stack trace: $stackTrace');
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Speichern. Bitte versuche es erneut.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showHealthLogDialog(HealthLog? existing) {
    showDialog(
      context: context,
      builder: (context) => _HealthLogDialog(
        existing: existing,
        onSave: (log) async {
          try {
            await _db.saveHealthLog(log);
            await _loadData();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Wohlbefinden gespeichert!'),
                  backgroundColor: AppTheme.success,
                ),
              );
            }
          } catch (e) {
            debugPrint('Error saving health log: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ein Fehler ist aufgetreten. Bitte versuche es erneut.'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _showGoalDialog(TrainingGoal? existing) {
    showDialog(
      context: context,
      builder: (context) => _GoalDialog(
        existing: existing,
        onSave: (goal) async {
          try {
            await _db.saveTrainingGoal(goal);
            await _loadData();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ziel gespeichert!'),
                  backgroundColor: AppTheme.success,
                ),
              );
            }
          } catch (e) {
            debugPrint('Error saving goal: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ein Fehler ist aufgetreten. Bitte versuche es erneut.'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _logSession(TrainingEntry entry) async {
    try {
      await _db.logTrainingSession(TrainingSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: DateTime.now(),
        type: entry.type,
        title: entry.title,
        duration: 60,
        notes: null,
      ));
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Training eingetragen!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error logging session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ein Fehler ist aufgetreten. Bitte versuche es erneut.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _logQuickSession() async {
    final titleController = TextEditingController();
    final durationController = TextEditingController(text: '60');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Training eintragen'),
        content: SizedBox(
          width: 460,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Titel',
                hintText: 'z.B. Krafttraining',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: durationController,
              decoration: const InputDecoration(
                labelText: 'Dauer (Minuten)',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      titleController.dispose();
      durationController.dispose();
    });

    if (result == true && titleController.text.isNotEmpty) {
      try {
        await _db.logTrainingSession(TrainingSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          date: DateTime.now(),
          type: 'custom',
          title: titleController.text,
          duration: int.tryParse(durationController.text) ?? 60,
          notes: null,
        ));
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Training eingetragen!'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error saving quick session: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fehler beim Speichern. Bitte versuche es erneut.'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleDayComplete(DateTime date, TrainingEntry entry) async {
    try {
      final existingSession = _sessions.where((s) =>
          DateFormat('yyyy-MM-dd').format(s.date) ==
          DateFormat('yyyy-MM-dd').format(date)).firstOrNull;

      if (existingSession != null) {
        await _db.deleteTrainingSession(existingSession.id);
      } else {
        await _db.logTrainingSession(TrainingSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          date: date,
          type: entry.type,
          title: entry.title,
          duration: 60,
          notes: null,
        ));
      }
      await _loadData();
    } catch (e) {
      debugPrint('Error toggling day complete: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ein Fehler ist aufgetreten. Bitte versuche es erneut.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _deleteGoal(TrainingGoal goal) async {
    await _db.deleteTrainingGoal(goal.id);
    await _loadData();
  }

  Future<void> _toggleGoal(TrainingGoal goal) async {
    await _db.saveTrainingGoal(goal.copyWith(completed: !goal.completed));
    await _loadData();
  }
}

class _ScheduleDayTile extends StatelessWidget {
  final String dayName;
  final DateTime date;
  final TrainingEntry? entry;
  final bool isToday;
  final bool isCompleted;
  final VoidCallback onTap;
  final VoidCallback? onComplete;

  const _ScheduleDayTile({
    required this.dayName,
    required this.date,
    required this.entry,
    required this.isToday,
    required this.isCompleted,
    required this.onTap,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isToday
              ? AppTheme.primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: AppTheme.primaryColor)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayName,
              style: TextStyle(
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                color: isToday ? AppTheme.primaryColor : null,
                fontSize: 12,
              ),
            ),
            Text(
              date.day.toString(),
              style: TextStyle(
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                color: isToday ? AppTheme.primaryColor : null,
              ),
            ),
          ],
        ),
      ),
      title: Row(
        children: [
          if (entry != null) ...[
            Text(entry!.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              entry?.title ?? 'Nicht geplant',
              style: TextStyle(
                fontWeight: entry != null ? FontWeight.w500 : FontWeight.normal,
                color: entry == null ? AppPalette.ring : null,
                decoration: isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
      subtitle: entry?.muscleGroups != null || entry?.notes != null
          ? Text(entry?.muscleGroups ?? entry?.notes ?? '')
          : null,
      trailing: onComplete != null
          ? IconButton(
              icon: Icon(
                isCompleted ? Icons.check_circle : Icons.circle_outlined,
                color: isCompleted ? AppTheme.success : AppPalette.ring,
              ),
              onPressed: onComplete,
            )
          : const Icon(Icons.chevron_right),
    );
  }
}

class _HealthStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _HealthStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(12),
        tint: color,
        enableTapScale: false,
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  final TrainingGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _GoalTile({
    required this.goal,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(goal.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppTheme.danger,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ziel löschen'),
            content: const Text('Möchtest du dieses Ziel wirklich löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: GestureDetector(
          onTap: onToggle,
          child: Icon(
            goal.completed ? Icons.check_circle : Icons.circle_outlined,
            color: goal.completed ? AppTheme.success : AppPalette.ring,
          ),
        ),
        title: Text(
          goal.title,
          style: TextStyle(
            decoration: goal.completed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: goal.targetDate != null
            ? Text('Bis ${DateFormat('d. MMM yyyy', 'de_DE').format(goal.targetDate!)}')
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.edit, size: 18),
          onPressed: onEdit,
        ),
      ),
    );
  }
}

class _EditScheduleScreen extends StatefulWidget {
  final List<TrainingEntry> schedule;
  final bool isHoliday;
  final Future<void> Function(List<TrainingEntry>) onSave;

  const _EditScheduleScreen({
    required this.schedule,
    required this.isHoliday,
    required this.onSave,
  });

  @override
  State<_EditScheduleScreen> createState() => _EditScheduleScreenState();
}

class _EditScheduleScreenState extends State<_EditScheduleScreen> {
  late List<TrainingEntry> _schedule;
  final dayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
  final dayNamesShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _schedule = List.from(widget.schedule);
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'strength': return AppTheme.primaryColor;
      case 'cardio': return AppTheme.accentColor;
      case 'swimming': return AppTheme.info;
      case 'rest': return AppTheme.success;
      default: return AppTheme.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppPalette.surfaceDark : AppPalette.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isHoliday ? 'Ferienplan' : 'Trainingsplan',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppTheme.lightText,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSaving
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : FilledButton.icon(
                    onPressed: () async {
                      setState(() => _isSaving = true);
                      try {
                        await widget.onSave(_schedule);
                        if (context.mounted) Navigator.pop(context);
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Speichern'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          GlassCard(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            borderRadius: 16,
            padding: const EdgeInsets.all(16),
            tint: widget.isHoliday ? AppTheme.warning : AppTheme.primaryColor,
            enableTapScale: false,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (widget.isHoliday ? AppTheme.warning : AppTheme.primaryColor).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.isHoliday ? Icons.beach_access : Icons.fitness_center,
                    color: widget.isHoliday ? AppTheme.warning : AppTheme.primaryColor,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isHoliday ? 'Ferientrainingsplan' : 'Regulärer Trainingsplan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : AppTheme.lightText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tippe auf einen Tag um das Training anzupassen',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 7,
              itemBuilder: (context, index) {
                final dayIndex = index + 1;
                final entry = _schedule.where((e) => e.day == dayIndex).firstOrNull;
                final hasEntry = entry != null;

                return AnimatedListItem(
                  index: index,
                  child: GlassCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    borderRadius: 16,
                    padding: const EdgeInsets.all(16),
                    tint: hasEntry ? _getTypeColor(entry.type) : null,
                    onTap: () => _editDay(dayIndex, entry),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: hasEntry
                                ? _getTypeColor(entry.type).withValues(alpha: 0.2)
                                : (isDark ? Colors.white.withValues(alpha: 0.1) : AppPalette.ring.withValues(alpha: 0.1)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: hasEntry
                                ? Text(entry.icon, style: const TextStyle(fontSize: 24))
                                : Text(
                                    dayNamesShort[index],
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isDark ? Colors.white54 : AppPalette.ring,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dayNames[index],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: isDark ? Colors.white : AppTheme.lightText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hasEntry ? entry.title : 'Nicht geplant',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: hasEntry
                                      ? (isDark ? Colors.white70 : Colors.black87)
                                      : (isDark ? Colors.white38 : AppPalette.ring),
                                ),
                              ),
                              if (hasEntry && entry.muscleGroups != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  entry.muscleGroups!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _getTypeColor(entry.type).withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasEntry)
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: AppTheme.danger.withValues(alpha: 0.7)),
                                onPressed: () {
                                  setState(() {
                                    _schedule.removeWhere((e) => e.day == dayIndex);
                                  });
                                },
                              ),
                            Icon(
                              Icons.chevron_right,
                              color: isDark ? Colors.white38 : AppPalette.ring,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _editDay(int dayIndex, TrainingEntry? existing) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) => _EditDayBottomSheet(
        dayIndex: dayIndex,
        dayName: dayNames[dayIndex - 1],
        existing: existing,
      ),
    );

    if (result is String && result == 'delete') {
      setState(() {
        _schedule.removeWhere((e) => e.day == dayIndex);
      });
    } else if (result is TrainingEntry) {
      setState(() {
        _schedule.removeWhere((e) => e.day == dayIndex);
        _schedule.add(result);
      });
    }
  }
}

class _EditDayBottomSheet extends StatefulWidget {
  final int dayIndex;
  final String dayName;
  final TrainingEntry? existing;

  const _EditDayBottomSheet({
    required this.dayIndex,
    required this.dayName,
    required this.existing,
  });

  @override
  State<_EditDayBottomSheet> createState() => _EditDayBottomSheetState();
}

class _EditDayBottomSheetState extends State<_EditDayBottomSheet> {
  late TextEditingController _titleController;
  late TextEditingController _muscleGroupsController;
  late TextEditingController _notesController;
  String _type = 'strength';
  String _icon = '🏋️';

  final _typeOptions = [
    ('strength', 'Kraft', '🏋️', AppTheme.primaryColor),
    ('cardio', 'Cardio', '🏃', AppTheme.accentColor),
    ('swimming', 'Schwimmen', '🏊', AppTheme.info),
    ('rest', 'Ruhetag', '😴', AppTheme.success),
    ('other', 'Sonstiges', '⭐', AppTheme.warning),
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title ?? '');
    _muscleGroupsController = TextEditingController(text: widget.existing?.muscleGroups ?? '');
    _notesController = TextEditingController(text: widget.existing?.notes ?? '');
    _type = widget.existing?.type ?? 'strength';
    _icon = widget.existing?.icon ?? '🏋️';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _muscleGroupsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppPalette.overlayDark : AppPalette.overlay,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? AppPalette.lineDark : AppPalette.line,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomPadding),
            child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : AppPalette.lineStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    widget.dayName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.lightText,
                    ),
                  ),
                  const Spacer(),
                  if (widget.existing != null)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, 'delete'),
                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                      label: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Trainingsart',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _typeOptions.map((opt) {
                    final isSelected = _type == opt.$1;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _type = opt.$1;
                          _icon = opt.$3;
                          if (opt.$1 == 'rest' && _titleController.text.isEmpty) {
                            _titleController.text = 'Ruhetag';
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? opt.$4.withValues(alpha: 0.2) : (isDark ? Colors.white.withValues(alpha: 0.05) : AppPalette.ring.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? opt.$4 : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(opt.$3, style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Text(
                              opt.$2,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? opt.$4 : (isDark ? Colors.white70 : Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Titel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'z.B. Chest Day, Beine, etc.',
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : AppPalette.ring.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              if (_type != 'rest') ...[
                const SizedBox(height: 20),
                Text(
                  'Muskelgruppen (optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _muscleGroupsController,
                  decoration: InputDecoration(
                    hintText: 'z.B. Brust, Trizeps, Schultern',
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : AppPalette.ring.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Notizen (optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Zusätzliche Hinweise...',
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : AppPalette.ring.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_titleController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bitte Titel eingeben')),
                      );
                      return;
                    }
                    Navigator.pop(context, TrainingEntry(
                      day: widget.dayIndex,
                      title: _titleController.text,
                      type: _type,
                      icon: _icon,
                      muscleGroups: _muscleGroupsController.text.isEmpty ? null : _muscleGroupsController.text,
                      notes: _notesController.text.isEmpty ? null : _notesController.text,
                    ));
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: AppTheme.primaryColor,
                  ),
                  child: const Text('Speichern', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
        ),
    );
  }
}

class _EditDayDialog extends StatefulWidget {
  final int dayIndex;
  final TrainingEntry? existing;
  final Future<void> Function(TrainingEntry?) onSave;

  const _EditDayDialog({
    required this.dayIndex,
    required this.existing,
    required this.onSave,
  });

  @override
  State<_EditDayDialog> createState() => _EditDayDialogState();
}

class _EditDayDialogState extends State<_EditDayDialog> {
  late TextEditingController _titleController;
  late TextEditingController _muscleGroupsController;
  late TextEditingController _notesController;
  String _type = 'strength';
  String _icon = '🏋️';
  bool _isSaving = false;

  final _typeOptions = [
    ('strength', 'Krafttraining', '🏋️'),
    ('cardio', 'Cardio', '🏃'),
    ('swimming', 'Schwimmen', '🏊'),
    ('rest', 'Ruhetag', '😴'),
    ('other', 'Sonstiges', '⭐'),
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title ?? '');
    _muscleGroupsController = TextEditingController(text: widget.existing?.muscleGroups ?? '');
    _notesController = TextEditingController(text: widget.existing?.notes ?? '');
    _type = widget.existing?.type ?? 'strength';
    _icon = widget.existing?.icon ?? '🏋️';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _muscleGroupsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dayNames = ['', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

    return AlertDialog(
      title: Text('${dayNames[widget.dayIndex]} bearbeiten'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Typ'),
              items: _typeOptions.map((opt) => DropdownMenuItem(
                value: opt.$1,
                child: Row(
                  children: [
                    Text(opt.$3),
                    const SizedBox(width: 8),
                    Text(opt.$2),
                  ],
                ),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _type = value!;
                  _icon = _typeOptions.firstWhere((o) => o.$1 == value).$3;
                  if (value == 'rest' && _titleController.text.isEmpty) {
                    _titleController.text = 'Ruhetag';
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Titel',
                hintText: 'z.B. Chestday',
              ),
            ),
            const SizedBox(height: 16),
            if (_type != 'rest') ...[
              TextField(
                controller: _muscleGroupsController,
                decoration: const InputDecoration(
                  labelText: 'Muskelgruppen (optional)',
                  hintText: 'z.B. Brust, Trizeps',
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notizen (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        if (widget.existing != null)
          TextButton(
            onPressed: _isSaving ? null : () async {
              setState(() => _isSaving = true);
              try {
                await widget.onSave(null);
                if (context.mounted) Navigator.pop(context);
              } finally {
                if (mounted) setState(() => _isSaving = false);
              }
            },
            child: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
          ),
        ElevatedButton(
          onPressed: _isSaving ? null : () async {
            if (_titleController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bitte Titel eingeben')),
              );
              return;
            }
            setState(() => _isSaving = true);
            try {
              await widget.onSave(TrainingEntry(
                day: widget.dayIndex,
                title: _titleController.text,
                type: _type,
                icon: _icon,
                muscleGroups: _muscleGroupsController.text.isEmpty ? null : _muscleGroupsController.text,
                notes: _notesController.text.isEmpty ? null : _notesController.text,
              ));
              if (context.mounted) Navigator.pop(context);
            } finally {
              if (mounted) setState(() => _isSaving = false);
            }
          },
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}

class _HealthLogDialog extends StatefulWidget {
  final HealthLog? existing;
  final Function(HealthLog) onSave;

  const _HealthLogDialog({
    required this.existing,
    required this.onSave,
  });

  @override
  State<_HealthLogDialog> createState() => _HealthLogDialogState();
}

class _HealthLogDialogState extends State<_HealthLogDialog> {
  double _sleep = 7;
  int _energy = 5;
  int _stress = 5;
  int _recovery = 5;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _sleep = widget.existing!.sleep ?? 7;
      _energy = widget.existing!.energy ?? 5;
      _stress = widget.existing!.stress ?? 5;
      _recovery = widget.existing!.recovery ?? 5;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Wohlbefinden eintragen'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSlider('Schlaf (Stunden)', _sleep, 0, 12, (v) => setState(() => _sleep = v)),
            _buildSlider('Energie', _energy.toDouble(), 1, 10, (v) => setState(() => _energy = v.toInt())),
            _buildSlider('Stress', _stress.toDouble(), 1, 10, (v) => setState(() => _stress = v.toInt())),
            _buildSlider('Erholung', _recovery.toDouble(), 1, 10, (v) => setState(() => _recovery = v.toInt())),
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(HealthLog(
              id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
              date: DateTime.now(),
              sleep: _sleep,
              energy: _energy,
              stress: _stress,
              recovery: _recovery,
            ));
            Navigator.pop(context);
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _GoalDialog extends StatefulWidget {
  final TrainingGoal? existing;
  final Function(TrainingGoal) onSave;

  const _GoalDialog({
    required this.existing,
    required this.onSave,
  });

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late TextEditingController _titleController;
  DateTime? _targetDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existing?.title ?? '');
    _targetDate = widget.existing?.targetDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Ziel bearbeiten' : 'Neues Ziel'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Ziel',
              hintText: 'z.B. 100kg Bankdrücken',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_targetDate != null
                ? 'Zieldatum: ${DateFormat('d. MMM yyyy', 'de_DE').format(_targetDate!)}'
                : 'Zieldatum wählen (optional)'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_targetDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _targetDate = null),
                  ),
                const Icon(Icons.calendar_today),
              ],
            ),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _targetDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (date != null) {
                setState(() => _targetDate = date);
              }
            },
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
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bitte Ziel eingeben')),
              );
              return;
            }
            widget.onSave(TrainingGoal(
              id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
              title: _titleController.text,
              targetDate: _targetDate,
              completed: widget.existing?.completed ?? false,
            ));
            Navigator.pop(context);
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class TrainingEntry {
  final int day;
  final String title;
  final String type;
  final String icon;
  final String? muscleGroups;
  final String? notes;

  TrainingEntry({
    required this.day,
    required this.title,
    required this.type,
    required this.icon,
    this.muscleGroups,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'day': day,
    'title': title,
    'type': type,
    'icon': icon,
    'muscle_groups': muscleGroups,
    'notes': notes,
  };

  factory TrainingEntry.fromMap(Map<String, dynamic> map) => TrainingEntry(
    day: map['day'] is int ? map['day'] : int.parse(map['day'].toString()),
    title: map['title']?.toString() ?? '',
    type: map['type']?.toString() ?? 'strength',
    icon: map['icon']?.toString() ?? '🏋️',
    muscleGroups: map['muscle_groups']?.toString(),
    notes: map['notes']?.toString(),
  );
}

class TrainingSession {
  final String id;
  final DateTime date;
  final String type;
  final String title;
  final int duration;
  final String? notes;

  TrainingSession({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    required this.duration,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date.toIso8601String(),
    'type': type,
    'title': title,
    'duration': duration,
    'notes': notes,
  };

  factory TrainingSession.fromMap(Map<String, dynamic> map) => TrainingSession(
    id: map['id']?.toString() ?? '',
    date: DateTime.parse(map['date'].toString()),
    type: map['type']?.toString() ?? 'custom',
    title: map['title']?.toString() ?? '',
    duration: map['duration'] is int ? map['duration'] : int.tryParse(map['duration']?.toString() ?? '60') ?? 60,
    notes: map['notes']?.toString(),
  );
}

class HealthLog {
  final String id;
  final DateTime date;
  final double? sleep;
  final int? energy;
  final int? stress;
  final int? recovery;

  HealthLog({
    required this.id,
    required this.date,
    this.sleep,
    this.energy,
    this.stress,
    this.recovery,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date.toIso8601String(),
    'sleep': sleep,
    'energy': energy,
    'stress': stress,
    'recovery': recovery,
  };

  factory HealthLog.fromMap(Map<String, dynamic> map) => HealthLog(
    id: map['id']?.toString() ?? '',
    date: DateTime.parse(map['date'].toString()),
    sleep: map['sleep'] is double ? map['sleep'] : double.tryParse(map['sleep']?.toString() ?? ''),
    energy: map['energy'] is int ? map['energy'] : int.tryParse(map['energy']?.toString() ?? ''),
    stress: map['stress'] is int ? map['stress'] : int.tryParse(map['stress']?.toString() ?? ''),
    recovery: map['recovery'] is int ? map['recovery'] : int.tryParse(map['recovery']?.toString() ?? ''),
  );
}

class TrainingGoal {
  final String id;
  final String title;
  final DateTime? targetDate;
  final bool completed;

  TrainingGoal({
    required this.id,
    required this.title,
    this.targetDate,
    this.completed = false,
  });

  TrainingGoal copyWith({
    String? id,
    String? title,
    DateTime? targetDate,
    bool? completed,
  }) => TrainingGoal(
    id: id ?? this.id,
    title: title ?? this.title,
    targetDate: targetDate ?? this.targetDate,
    completed: completed ?? this.completed,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'target_date': targetDate?.toIso8601String(),
    'completed': completed ? 1 : 0,
  };

  factory TrainingGoal.fromMap(Map<String, dynamic> map) => TrainingGoal(
    id: map['id']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    targetDate: map['target_date'] != null ? DateTime.tryParse(map['target_date'].toString()) : null,
    completed: map['completed'] == 1 || map['completed'] == true,
  );
}
