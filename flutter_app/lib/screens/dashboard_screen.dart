// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../providers/app_provider.dart';
import '../models/task.dart';
import '../models/event.dart';
import '../services/weather_service.dart';
import '../theme.dart';
import '../widgets/page_fade_in.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_glass_card.dart';
import '../widgets/animated_counter.dart';
import '../widgets/animated_list_item.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Task> _todayTasks = [];
  List<Event> _todayEvents = [];
  List<Event> _upcomingEvents = [];
  List<Map<String, dynamic>> _deadlines = [];
  bool _isLoading = true;
  String? _error;
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  WeatherData? _weatherData;
  final WeatherService _weatherService = WeatherService();

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadWeather();

    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        final now = DateTime.now();
        if (now.minute != _currentTime.minute) {
          setState(() => _currentTime = now);
        }
      }
    });
  }

  Future<void> _loadWeather() async {
    final weather = await _weatherService.getWeather();
    if (mounted) {
      setState(() => _weatherData = weather);
    }
  }

  AppProvider? _provider;
  Timer? _debounceTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    if (_provider != provider) {
      _provider?.removeListener(_onProviderChanged);
      _provider = provider;
      _provider!.addListener(_onProviderChanged);
    }
  }

  void _onProviderChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    _debounceTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_isLoading) {
    } else {
      setState(() => _error = null);
    }

    try {
      final provider = context.read<AppProvider>();
      final tasks = await provider.getTodayTasks();
      final events = await provider.getTodayEvents();
      final upcoming = await provider.getUpcomingEvents(days: 3);

      final deadlines = await _loadDeadlines(provider);

      if (mounted) {
        setState(() {
          _todayTasks = tasks;
          _todayEvents = events;
          _upcomingEvents = upcoming;
          _deadlines = deadlines;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Fehler beim Laden der Daten';
          _isLoading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadDeadlines(AppProvider provider) async {
    final deadlines = <Map<String, dynamic>>[];
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    try {
      final homework = await provider.getOpenHomework();
      for (final hw in homework) {
        final dueDateStr = hw['due_date'] as String?;
        if (dueDateStr == null) continue;

        final dueDate = DateTime.parse(dueDateStr);
        final dueDateStart = DateTime(dueDate.year, dueDate.month, dueDate.day);
        final daysUntil = dueDateStart.difference(todayStart).inDays;

        if (daysUntil >= 0 && daysUntil <= 3) {
          deadlines.add({
            'type': 'homework',
            'icon': Icons.edit_note,
            'title': hw['title'] ?? 'Hausaufgabe',
            'subject': hw['subject_name'] ?? '',
            'days': daysUntil,
            'urgency': daysUntil == 0 ? 'urgent' : daysUntil == 1 ? 'warning' : 'normal',
          });
        }
      }
    } catch (_) {
    }

    try {
      final tasks = await provider.getOpenTasks();
      for (final task in tasks) {
        if (task.dueDate == null) continue;

        final dueDateStart = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day);
        final daysUntil = dueDateStart.difference(todayStart).inDays;

        if (daysUntil >= 0 && daysUntil <= 2) {
          deadlines.add({
            'type': 'task',
            'icon': Icons.check_circle_outline,
            'title': task.title,
            'subject': '',
            'days': daysUntil,
            'urgency': daysUntil == 0 ? 'urgent' : daysUntil == 1 ? 'warning' : 'normal',
          });
        }
      }
    } catch (_) {
    }

    deadlines.sort((a, b) => (a['days'] as int).compareTo(b['days'] as int));

    return deadlines;
  }

  String _getGreeting() {
    final hour = _currentTime.hour;
    if (hour < 6) return 'Gute Nacht';
    if (hour < 12) return 'Guten Morgen';
    if (hour < 18) return 'Guten Tag';
    return 'Guten Abend';
  }

  String _formatTime() {
    return DateFormat('HH:mm').format(_currentTime);
  }

  String _formatDate() {
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(_currentTime);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return PageFadeIn(
          child: RefreshIndicator(
          onRefresh: () async {
            await provider.refresh();
            if (!mounted) return;
            await _loadData();
            if (!mounted) return;
            await _loadWeather();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTheme.gradientText('Übersicht', fontSize: 36),
                  const SizedBox(height: 16),

                  _buildHeroSection(context, isDark),
                  const SizedBox(height: 12),

                  _buildStatusBar(isDark, provider),
                  const SizedBox(height: 16),

                  if (_error != null) ...[
                    _buildErrorBanner(isDark),
                    const SizedBox(height: 16),
                  ],

                  _buildQuickStats(context, isDark, provider),
                  const SizedBox(height: 16),

                  _buildDailyCapacity(isDark),
                  const SizedBox(height: 16),

                  if (_todayEvents.isNotEmpty || _upcomingEvents.isNotEmpty) ...[
                    _buildNextEventCard(context, isDark),
                    const SizedBox(height: 16),
                  ],

                  if (_deadlines.isNotEmpty) ...[
                    _buildDeadlinesSection(context, isDark),
                    const SizedBox(height: 16),
                  ],

                  _buildTasksSection(context, isDark, provider),
                  const SizedBox(height: 16),

                  _buildEventsSection(context, isDark),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildHeroSection(BuildContext context, bool isDark) {
    return LiquidGlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(),
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w300,
                    color: isDark ? AppPalette.inkDark : AppPalette.ink,
                    height: 1,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _getGreeting(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_weatherData != null) _buildWeatherWidget(isDark),
        ],
      ),
    );
  }

  Widget _buildWeatherWidget(bool isDark) {
    if (_weatherData == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _weatherData!.weatherIcon,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 8),
              Text(
                '${_weatherData!.temperature.round()}°',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white : AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _weatherData!.weatherDescription,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          Text(
            _weatherData!.city,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _loadData,
            color: AppTheme.danger,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(bool isDark, AppProvider provider) {
    final openTasks = _todayTasks.where((t) => !t.completed).length;
    final completedTasks = _todayTasks.where((t) => t.completed).length;
    final hasDeadlines = _deadlines.isNotEmpty;
    final hasTraining = provider.events.any((e) =>
        e.category == 'training' &&
        e.startTime.year == DateTime.now().year &&
        e.startTime.month == DateTime.now().month &&
        e.startTime.day == DateTime.now().day);

    Color taskColor;
    String taskLabel;
    if (openTasks == 0 && completedTasks > 0) {
      taskColor = AppTheme.success;
      taskLabel = 'Alles erledigt';
    } else if (openTasks > 5) {
      taskColor = AppTheme.warning;
      taskLabel = '$openTasks offen';
    } else {
      taskColor = AppTheme.success;
      taskLabel = '$openTasks offen';
    }

    Color deadlineColor = hasDeadlines ? AppTheme.warning : AppTheme.success;
    String deadlineLabel = hasDeadlines ? '${_deadlines.length} fällig' : 'Keine';

    Color trainingColor = hasTraining ? AppTheme.success : (isDark ? Colors.white38 : Colors.black26);
    String trainingLabel = hasTraining ? 'Heute geplant' : 'Kein Training';

    return LiquidGlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatusDot(color: taskColor, label: 'Aufgaben', detail: taskLabel, isDark: isDark),
          Container(width: 1, height: 28, color: isDark ? Colors.white12 : Colors.black12),
          _StatusDot(color: deadlineColor, label: 'Deadlines', detail: deadlineLabel, isDark: isDark),
          Container(width: 1, height: 28, color: isDark ? Colors.white12 : Colors.black12),
          _StatusDot(color: trainingColor, label: 'Training', detail: trainingLabel, isDark: isDark),
        ],
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context, bool isDark, AppProvider provider) {
    final openTasks = _todayTasks.where((t) => !t.completed).length;
    final completedTasks = _todayTasks.where((t) => t.completed).length;
    final eventsCount = _todayEvents.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: (MediaQuery.of(context).size.width - 56) / 3,
            child: _QuickStatCard(
              icon: Icons.check_circle,
              numericValue: completedTasks,
              label: 'Erledigt',
              color: AppTheme.success,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: (MediaQuery.of(context).size.width - 56) / 3,
            child: _QuickStatCard(
              icon: Icons.pending_actions,
              numericValue: openTasks,
              label: 'Offen',
              color: openTasks > 5 ? AppTheme.warning : AppTheme.primaryColor,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: (MediaQuery.of(context).size.width - 56) / 3,
            child: _QuickStatCard(
              icon: Icons.event,
              numericValue: eventsCount,
              label: 'Termine',
              color: AppTheme.info,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyCapacity(bool isDark) {
    final openTasks = _todayTasks.where((t) => !t.completed).toList();
    final tasksWithEstimate = openTasks.where((t) => t.estimatedMinutes != null).toList();
    if (tasksWithEstimate.isEmpty) return const SizedBox.shrink();

    final totalMinutes = tasksWithEstimate.fold<int>(0, (sum, t) => sum + t.estimatedMinutes!);
    final completedMinutes = _todayTasks
        .where((t) => t.completed && t.estimatedMinutes != null)
        .fold<int>(0, (sum, t) => sum + t.estimatedMinutes!);
    final allEstimated = openTasks.length == tasksWithEstimate.length;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeStr = hours > 0
        ? (mins > 0 ? '${hours}h ${mins}min' : '${hours}h')
        : '${mins}min';

    final completedHours = completedMinutes ~/ 60;
    final completedMins = completedMinutes % 60;
    final completedStr = completedHours > 0
        ? (completedMins > 0 ? '${completedHours}h ${completedMins}min' : '${completedHours}h')
        : '${completedMins}min';

    final progress = (completedMinutes + totalMinutes) > 0
        ? completedMinutes / (completedMinutes + totalMinutes)
        : 0.0;

    return LiquidGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18, color: AppTheme.info),
              const SizedBox(width: 8),
              Text(
                'Tagesplan',
                style: AppTheme.sectionLabel(isDark),
              ),
              const Spacer(),
              Text(
                '$completedStr / ${allEstimated ? timeStr : '~$timeStr'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppPalette.iris,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!allEstimated) ...[
            const SizedBox(height: 6),
            Text(
              '${openTasks.length - tasksWithEstimate.length} Aufgaben ohne Zeitschätzung',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNextEventCard(BuildContext context, bool isDark) {
    final nextEvent = _todayEvents.isNotEmpty ? _todayEvents.first :
                      _upcomingEvents.isNotEmpty ? _upcomingEvents.first : null;

    if (nextEvent == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final diff = nextEvent.startTime.difference(now);
    String timeUntil;

    if (diff.inDays > 0) {
      timeUntil = 'in ${diff.inDays} Tag${diff.inDays > 1 ? 'en' : ''}';
    } else if (diff.inHours > 0) {
      timeUntil = 'in ${diff.inHours}h ${diff.inMinutes % 60}min';
    } else if (diff.inMinutes > 0) {
      timeUntil = 'in ${diff.inMinutes} min';
    } else {
      timeUntil = 'Jetzt';
    }

    return LiquidGlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      tint: AppTheme.primaryColor.withValues(alpha: 0.15),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              timeUntil,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nächster Termin',
                  style: AppTheme.sectionLabel(isDark),
                ),
                const SizedBox(height: 4),
                Text(
                  nextEvent.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${nextEvent.timeRange}${nextEvent.location != null ? ' - ${nextEvent.location}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlinesSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Deadlines',
          icon: Icons.warning_amber_rounded,
          iconColor: AppTheme.warning,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        ...(_deadlines.take(3).toList().asMap().entries.map((entry) => AnimatedListItem(
          index: entry.key,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DeadlineCard(deadline: entry.value, isDark: isDark),
          ),
        ))),
      ],
    );
  }

  Widget _buildTasksSection(BuildContext context, bool isDark, AppProvider provider) {
    final openTasks = _todayTasks.where((t) => !t.completed).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Heute erledigen',
          icon: Icons.task_alt,
          iconColor: AppTheme.primaryColor,
          isDark: isDark,
          trailing: openTasks.isNotEmpty ? TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Alle', style: TextStyle(color: AppTheme.primaryColor)),
          ) : null,
        ),
        const SizedBox(height: 12),
        GlassCard(
          borderRadius: 16,
          padding: EdgeInsets.zero,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isLoading
                ? const Padding(
                    key: ValueKey('tasks_loading'),
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : openTasks.isEmpty
                    ? _EmptyStateCompact(
                        key: const ValueKey('tasks_empty'),
                        icon: Icons.check_circle_outline,
                        message: 'Keine Aufgaben',
                        isDark: isDark,
                      )
                    : ListView.separated(
                        key: const ValueKey('tasks_content'),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: openTasks.take(5).length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                        itemBuilder: (context, index) {
                          final task = openTasks[index];
                          return AnimatedListItem(
                            index: index,
                            child: _TaskRow(
                              task: task,
                              isDark: isDark,
                              onToggle: () async {
                                await provider.toggleTaskComplete(task.id);
                                await _loadData();
                              },
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Termine heute',
          icon: Icons.calendar_today,
          iconColor: AppTheme.accentColor,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        GlassCard(
          borderRadius: 16,
          padding: EdgeInsets.zero,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isLoading
                ? const Padding(
                    key: ValueKey('events_loading'),
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _todayEvents.isEmpty
                    ? _EmptyStateCompact(
                        key: const ValueKey('events_empty'),
                        icon: Icons.event_available,
                        message: 'Keine Termine',
                        isDark: isDark,
                      )
                    : ListView.separated(
                        key: const ValueKey('events_content'),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _todayEvents.take(5).length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                        itemBuilder: (context, index) {
                          final event = _todayEvents[index];
                          return AnimatedListItem(
                            index: index,
                            child: _EventRow(event: event, isDark: isDark),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;
  final String detail;
  final bool isDark;

  const _StatusDot({
    required this.color,
    required this.label,
    required this.detail,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            Text(
              detail,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickStatCard extends StatelessWidget {
  final IconData icon;
  final int numericValue;
  final String label;
  final Color color;
  final bool isDark;

  const _QuickStatCard({
    required this.icon,
    required this.numericValue,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      borderRadius: 16,
      tint: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          AnimatedCounter(
            value: numericValue,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final bool isDark;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.isDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: AppTheme.sectionLabel(isDark),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _DeadlineCard extends StatelessWidget {
  final Map<String, dynamic> deadline;
  final bool isDark;

  const _DeadlineCard({required this.deadline, required this.isDark});

  Color get urgencyColor {
    switch (deadline['urgency']) {
      case 'urgent': return AppTheme.danger;
      case 'warning': return AppTheme.warning;
      default: return AppTheme.primaryColor;
    }
  }

  String get countdownText {
    final days = deadline['days'] as int;
    if (days == 0) return 'HEUTE';
    if (days == 1) return 'Morgen';
    return '$days Tage';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: urgencyColor.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: urgencyColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: urgencyColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                countdownText,
                style: TextStyle(
                  fontSize: (deadline['days'] as int) == 0 ? 10 : 11,
                  fontWeight: FontWeight.bold,
                  color: urgencyColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deadline['title'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      deadline['icon'] as IconData,
                      size: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      deadline['type'] == 'homework' ? 'Hausaufgabe' : 'Aufgabe',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    if ((deadline['subject'] as String).isNotEmpty) ...[
                      Text(' - ', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
                      Text(
                        deadline['subject'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final bool isDark;
  final VoidCallback onToggle;

  const _TaskRow({
    required this.task,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: onToggle,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: task.completed ? AppTheme.success : Colors.transparent,
                  border: Border.all(
                    color: task.completed ? AppTheme.success : (isDark ? Colors.white38 : Colors.black26),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: task.completed
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      decoration: task.completed ? TextDecoration.lineThrough : null,
                      color: task.completed
                          ? (isDark ? Colors.white38 : Colors.black38)
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (task.dueDate != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('HH:mm').format(task.dueDate!),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _PriorityDot(priority: task.priority),
          ],
        ),
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  final String priority;

  const _PriorityDot({required this.priority});

  Color get color {
    switch (priority) {
      case 'high': return AppTheme.danger;
      case 'medium': return AppTheme.warning;
      default: return AppTheme.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final Event event;
  final bool isDark;

  const _EventRow({required this.event, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final eventColor = event.color != null
        ? Color(int.tryParse(event.color!.replaceFirst('#', '0xFF')) ?? 0xFF7353CD)
        : AppTheme.primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: eventColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  event.timeRange,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          if (event.location != null) ...[
            Icon(
              Icons.location_on,
              size: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                event.location!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyStateCompact extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;

  const _EmptyStateCompact({
    super.key,
    required this.icon,
    required this.message,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
          const SizedBox(width: 10),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}
