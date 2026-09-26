// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/app_provider.dart';
import '../models/task.dart';
import '../services/database_service.dart'
    if (dart.library.html) '../services/database_service_web.dart';
import '../theme.dart';
import '../services/focus_mode_service.dart';
import '../widgets/page_fade_in.dart';
import '../widgets/glass_card.dart';

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> with TickerProviderStateMixin {
  static const int workDuration = 25 * 60;
  static const int shortBreakDuration = 5 * 60;
  static const int longBreakDuration = 15 * 60;

  int _currentDuration = workDuration;
  int _remainingSeconds = workDuration;
  Timer? _timer;
  bool _isRunning = false;
  int _sessionsCompleted = 0;
  PomodoroMode _currentMode = PomodoroMode.work;
  bool _focusModeEnabled = false;
  bool _hasPermission = false;
  Task? _linkedTask;
  DateTime? _sessionStartedAt;
  String _statsRange = 'week';
  Map<String, dynamic>? _stats;

  final FocusModeService _focusModeService = FocusModeService();
  final DatabaseService _db = DatabaseService();
  static const _uuid = Uuid();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    _checkFocusModePermission();
    _loadStats();
  }

  String _sinceForRange(String range) {
    final now = DateTime.now();
    final DateTime start;
    switch (range) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      default:
        start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    }
    return start.toIso8601String();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _db.getPomodoroStats(since: _sinceForRange(_statsRange));
      if (mounted) {
        setState(() => _stats = stats);
      }
    } catch (_) {}
  }

  Future<void> _checkFocusModePermission() async {
    final hasPermission = await _focusModeService.hasPermission();
    if (mounted) {
      setState(() => _hasPermission = hasPermission);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();

    if (_focusModeEnabled) {
      _focusModeService.disableFocusMode();
    }
    super.dispose();
  }

  void _startTimer() async {
    _timer?.cancel();
    setState(() {
      _isRunning = true;
      if (_currentMode == PomodoroMode.work && _sessionStartedAt == null) {
        _sessionStartedAt = DateTime.now();
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _onTimerComplete();
      }
    });

    if (_currentMode == PomodoroMode.work) {
      final enabled = await _focusModeService.enableFocusMode();
      if (mounted) {
        setState(() => _focusModeEnabled = enabled);
      }
    }
  }

  void _pauseTimer() async {
    _timer?.cancel();
    setState(() => _isRunning = false);

    if (_focusModeEnabled) {
      await _focusModeService.disableFocusMode();
      if (mounted) {
        setState(() => _focusModeEnabled = false);
      }
    }
  }

  void _resetTimer() async {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _currentDuration;
    });

    if (_focusModeEnabled) {
      await _focusModeService.disableFocusMode();
      if (mounted) {
        setState(() => _focusModeEnabled = false);
      }
    }
  }

  void _onTimerComplete() async {
    _timer?.cancel();
    HapticFeedback.heavyImpact();

    if (_focusModeEnabled) {
      await _focusModeService.disableFocusMode();
      if (mounted) {
        setState(() => _focusModeEnabled = false);
      }
    }

    if (!mounted) return;
    final wasWork = _currentMode == PomodoroMode.work;

    setState(() {
      _isRunning = false;
      if (wasWork) {
        _sessionsCompleted++;
        if (_sessionsCompleted % 4 == 0) {
          _switchMode(PomodoroMode.longBreak);
        } else {
          _switchMode(PomodoroMode.shortBreak);
        }
      } else {
        _switchMode(PomodoroMode.work);
      }
    });

    if (wasWork) {
      _savePomodoroSession().then((_) => _loadStats());
    }

    _showCompletionDialog();
  }

  Future<void> _savePomodoroSession() async {
    try {
      await _db.insertPomodoroSession({
        'id': _uuid.v4(),
        'task_id': _linkedTask?.id,
        'started_at': (_sessionStartedAt ?? DateTime.now()).toIso8601String(),
        'duration_minutes': workDuration ~/ 60,
        'completed': 1,
      });
    } catch (_) {}
    _sessionStartedAt = null;
  }

  void _switchMode(PomodoroMode mode) {
    setState(() {
      _currentMode = mode;
      switch (mode) {
        case PomodoroMode.work:
          _currentDuration = workDuration;
          break;
        case PomodoroMode.shortBreak:
          _currentDuration = shortBreakDuration;
          break;
        case PomodoroMode.longBreak:
          _currentDuration = longBreakDuration;
          break;
      }
      _remainingSeconds = _currentDuration;
    });
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_currentMode == PomodoroMode.work ? 'Pause beendet!' : 'Session beendet!'),
        content: Text(
          _currentMode == PomodoroMode.work
              ? 'Zeit zu arbeiten! Du hast $_sessionsCompleted Sessions abgeschlossen.'
              : 'Gut gemacht! Nimm dir eine ${_currentMode == PomodoroMode.longBreak ? 'lange' : 'kurze'} Pause.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _startTimer();
            },
            child: const Text('Starten'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double get _progress => _remainingSeconds / _currentDuration;

  Color get _modeColor {
    switch (_currentMode) {
      case PomodoroMode.work:
        return AppTheme.primaryColor;
      case PomodoroMode.shortBreak:
        return AppPalette.sage;
      case PomodoroMode.longBreak:
        return AppPalette.lake;
    }
  }

  String get _modeLabel {
    switch (_currentMode) {
      case PomodoroMode.work:
        return 'Fokus';
      case PomodoroMode.shortBreak:
        return 'Kurze Pause';
      case PomodoroMode.longBreak:
        return 'Lange Pause';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageFadeIn(
      child: ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AppTheme.gradientText('Pomodoro', fontSize: 36),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Fokussiere dich mit der Pomodoro-Technik',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildTaskSelector(isDark),
        ),

        const SizedBox(height: 24),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GlassCard(
            borderRadius: 40,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            enableTapScale: false,
            child: Column(
              children: [
                _buildModeSelectorPills(isDark),

                const SizedBox(height: 32),

                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isRunning ? _pulseAnimation.value : 1.0,
                      child: child,
                    );
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                    final timerWidth = (constraints.maxWidth * 0.7).clamp(220.0, 340.0);
                    final timerHeight = timerWidth * (200 / 280);
                    return SizedBox(
                    width: timerWidth,
                    height: timerHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                width: double.infinity,
                                height: timerHeight * (1.0 - _progress),
                                decoration: BoxDecoration(
                                  color: _modeColor.withValues(alpha: 0.1),
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatTime(_remainingSeconds),
                                  style: TextStyle(
                                    fontSize: 72,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -2,
                                    color: _modeColor,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _modeLabel,
                                  style: TextStyle(
                                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  },
                  ),
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final completed = index < (_sessionsCompleted % 4);
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: completed
                            ? _modeColor
                            : (isDark ? AppPalette.lineDark : AppPalette.line),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildControlButton(
                      icon: Icons.refresh,
                      onPressed: _resetTimer,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: _isRunning ? _pauseTimer : _startTimer,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _modeColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: _modeColor.withValues(alpha: 0.3),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isRunning ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    _buildControlButton(
                      icon: Icons.skip_next,
                      onPressed: () {
                        _timer?.cancel();
                        _onTimerComplete();
                      },
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildStatsSection(isDark),
        ),

        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildFocusModeCard(isDark),
        ),

        const SizedBox(height: 120),
      ],
      ),
    );
  }

  Widget _buildModeSelectorPills(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? AppPalette.lineDark.withValues(alpha: 0.8)
            : AppPalette.sunken.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _buildModePill('Fokus', PomodoroMode.work, isDark)),
          Expanded(child: _buildModePill('Kurze Pause', PomodoroMode.shortBreak, isDark)),
          Expanded(child: _buildModePill('Lange Pause', PomodoroMode.longBreak, isDark)),
        ],
      ),
    );
  }

  Widget _buildModePill(String label, PomodoroMode mode, bool isDark) {
    final isActive = _currentMode == mode;
    return GestureDetector(
      onTap: () {
        if (!_isRunning) {
          _switchMode(mode);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? AppPalette.lineDark : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive
                  ? (isDark ? Colors.white : AppTheme.lightText)
                  : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFocusModeCard(bool isDark) {
    return GlassCard(
      enableTapScale: false,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_focusModeEnabled
                      ? AppTheme.success
                      : AppTheme.info)
                  .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _focusModeEnabled
                  ? Icons.do_not_disturb_on
                  : Icons.do_not_disturb_off,
              color:
                  _focusModeEnabled ? AppTheme.success : AppTheme.info,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fokus-Modus',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _focusModeEnabled
                      ? 'Benachrichtigungen blockiert'
                      : _hasPermission
                          ? 'Startet automatisch mit Timer'
                          : 'Berechtigung erforderlich',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (!_hasPermission)
            TextButton(
              onPressed: () async {
                await _focusModeService.requestPermission();
                await _checkFocusModePermission();
              },
              child: const Text('Erlauben'),
            )
          else if (_focusModeEnabled)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Aktiv',
                style: TextStyle(
                  color: AppTheme.success,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(bool isDark) {
    final totalSessions = _stats?['total_sessions'] as int? ?? 0;
    final totalMinutes = _stats?['total_minutes'] as int? ?? 0;
    final byTask = (_stats?['by_task'] as List<Map<String, dynamic>>?) ?? [];
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
    final provider = context.read<AppProvider>();

    return GlassCard(
      enableTapScale: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Lernstatistik', style: Theme.of(context).textTheme.titleMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statsRange,
                    isDense: true,
                    style: Theme.of(context).textTheme.bodySmall,
                    items: const [
                      DropdownMenuItem(value: 'today', child: Text('Heute')),
                      DropdownMenuItem(value: 'week', child: Text('Diese Woche')),
                      DropdownMenuItem(value: 'month', child: Text('Dieser Monat')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _statsRange = v);
                        _loadStats();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.local_fire_department,
                  color: AppTheme.pomodoroColor,
                  value: '$totalSessions',
                  label: 'Sitzungen',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.timer,
                  color: AppTheme.info,
                  value: timeStr,
                  label: 'Lernzeit',
                  isDark: isDark,
                ),
              ),
            ],
          ),
          if (byTask.isNotEmpty && totalMinutes > 0) ...[
            const SizedBox(height: 16),
            Text('Nach Aufgabe', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...byTask.take(5).map((item) {
              final taskId = item['task_id'] as String?;
              final task = taskId != null
                  ? provider.tasks.where((t) => t.id == taskId).firstOrNull
                  : null;
              final name = task?.title ?? 'Ohne Aufgabe';
              final itemMinutes = item['minutes'] as int? ?? 0;
              final sessions = item['sessions'] as int? ?? 0;
              final percent = totalMinutes > 0 ? itemMinutes / totalMinutes : 0.0;
              final itemHours = itemMinutes ~/ 60;
              final itemMins = itemMinutes % 60;
              final itemTimeStr = itemHours > 0 ? '${itemHours}h ${itemMins}m' : '${itemMins}m';
              final color = task != null ? AppTheme.primaryColor : (isDark ? Colors.white38 : Colors.black38);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                        ),
                        Text('$sessions Sitzung${sessions != 1 ? 'en' : ''}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percent,
                              minHeight: 6,
                              backgroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 50,
                          child: Text(itemTimeStr,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600, fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold, color: color,
          )),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildTaskSelector(bool isDark) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enableTapScale: false,
      child: InkWell(
        onTap: _isRunning ? null : _showTaskPicker,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Icon(
              _linkedTask != null ? Icons.task_alt : Icons.add_task,
              color: _linkedTask != null ? AppTheme.primaryColor : (isDark ? Colors.white54 : Colors.black45),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _linkedTask?.title ?? 'Aufgabe verknüpfen (optional)',
                style: TextStyle(
                  fontSize: 14,
                  color: _linkedTask != null
                      ? (isDark ? Colors.white : AppTheme.lightText)
                      : (isDark ? Colors.white54 : Colors.black45),
                  fontWeight: _linkedTask != null ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_linkedTask != null)
              GestureDetector(
                onTap: _isRunning ? null : () => setState(() => _linkedTask = null),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
          ],
        ),
      ),
    );
  }

  void _showTaskPicker() {
    final provider = context.read<AppProvider>();
    final openTasks = provider.tasks.where((t) => !t.completed).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppPalette.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Aufgabe wählen',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.lightText,
                ),
              ),
            ),
            Expanded(
              child: openTasks.isEmpty
                  ? Center(
                      child: Text(
                        'Keine offenen Aufgaben',
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: openTasks.length,
                      itemBuilder: (context, index) {
                        final task = openTasks[index];
                        final isSelected = _linkedTask?.id == task.id;
                        return ListTile(
                          leading: Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? AppTheme.primaryColor : null,
                          ),
                          title: Text(task.title),
                          subtitle: task.estimatedMinutes != null
                              ? Text(Task.timeEstimates[task.estimatedMinutes] ?? '${task.estimatedMinutes} Min')
                              : null,
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _priorityColor(task.priority).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              task.priority == 'high' ? 'Hoch' : task.priority == 'low' ? 'Niedrig' : 'Normal',
                              style: TextStyle(fontSize: 11, color: _priorityColor(task.priority)),
                            ),
                          ),
                          onTap: () {
                            setState(() => _linkedTask = task);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'high': return AppTheme.danger;
      case 'low': return AppTheme.info;
      default: return AppTheme.warning;
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      color: color,
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        padding: const EdgeInsets.all(16),
      ),
    );
  }
}

enum PomodoroMode { work, shortBreak, longBreak }
