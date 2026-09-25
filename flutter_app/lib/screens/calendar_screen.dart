// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../providers/iserv_provider.dart';
import '../providers/vbb_provider.dart';
import '../models/event.dart';
import '../main.dart' show MainScreen;
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_list_item.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with TickerProviderStateMixin {
  static const _daysOfWeek = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  String _currentFilter = 'all';
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  late AnimationController _monthTransitionController;
  double _monthSlideDirection = 1.0;

  late AnimationController _dayEventsController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();

    _monthTransitionController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: 1.0,
    );

    _dayEventsController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: 1.0,
    );
  }

  void _changeMonth(int delta) {
    _monthSlideDirection = delta > 0 ? 1.0 : -1.0;
    _monthTransitionController.forward(from: 0.0);
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
  }

  void _selectDate(DateTime date) {
    if (_isSameDay(date, _selectedDate)) return;
    _dayEventsController.forward(from: 0.0);
    setState(() => _selectedDate = date);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _monthTransitionController.dispose();
    _dayEventsController.dispose();
    super.dispose();
  }

  List<Event> _filterEvents(List<Event> events) {
    var filtered = events;

    if (_currentFilter != 'all') {
      filtered = filtered.where((e) => e.category == _currentFilter).toList();
    }

    filtered.sort((a, b) => a.startTime.compareTo(b.startTime));

    return filtered;
  }

  List<Event> _getEventsForDate(List<Event> events, DateTime date) {
    final checkDate = DateTime(date.year, date.month, date.day);
    return events.where((e) {
      final eventStart = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
      final eventEnd = DateTime(e.endTime.year, e.endTime.month, e.endTime.day);
      return !checkDate.isBefore(eventStart) && !checkDate.isAfter(eventEnd);
    }).toList();
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'school':
        return AppTheme.accent1;
      case 'training':
        return AppTheme.trainingColor;
      case 'work':
        return AppTheme.warning;
      case 'holiday':
        return const Color(0xFFEF4444);
      case 'vacation':
        return const Color(0xFF22C55E);
      case 'iserv':
        return const Color(0xFFF59E0B);
      case 'personal':
      default:
        return AppTheme.accent3;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'school':
        return Icons.school_rounded;
      case 'training':
        return Icons.fitness_center_rounded;
      case 'work':
        return Icons.work_rounded;
      case 'holiday':
        return Icons.celebration_rounded;
      case 'vacation':
        return Icons.beach_access_rounded;
      case 'iserv':
        return Icons.cloud_rounded;
      case 'personal':
      default:
        return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        return Consumer<IServProvider>(
          builder: (context, iservProvider, child) {
            final allEvents = [...provider.events, ...iservProvider.calendarEvents];
            final filteredEvents = _filterEvents(allEvents);
            final selectedDayEvents = _getEventsForDate(filteredEvents, _selectedDate);

            return FadeTransition(
              opacity: _fadeAnimation,
              child: RefreshIndicator(
                onRefresh: () async {
                  await provider.refresh();
                  if (iservProvider.isConnected) {
                    await iservProvider.syncData();
                  }
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(context, isDark, iservProvider),
                    ),

                    SliverToBoxAdapter(
                      child: _buildCalendarCard(context, isDark, filteredEvents, isTablet),
                    ),

                    SliverToBoxAdapter(
                      child: _buildCategoryFilters(isDark),
                    ),

                    SliverToBoxAdapter(
                      child: AnimatedBuilder(
                        animation: _dayEventsController,
                        builder: (context, child) {
                          final progress = Curves.easeOutCubic.transform(_dayEventsController.value);
                          return Opacity(
                            opacity: progress.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1.0 - progress)),
                              child: child,
                            ),
                          );
                        },
                        child: _buildSelectedDayHeader(isDark, selectedDayEvents.length),
                      ),
                    ),

                    if (selectedDayEvents.isEmpty)
                      SliverToBoxAdapter(
                        child: _buildEmptyDayState(context, isDark),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(
                          key: ValueKey('events_${_currentFilter}_${_selectedDate.toIso8601String()}'),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final event = selectedDayEvents[index];
                              return AnimatedListItem(
                                index: index,
                                child: _ModernEventCard(
                                  event: event,
                                  categoryColor: _getCategoryColor(event.category),
                                  categoryIcon: _getCategoryIcon(event.category),
                                  onDelete: event.isIServEvent
                                      ? null
                                      : () => provider.deleteEvent(event.id),
                                  onEdit: event.isIServEvent
                                      ? null
                                      : () => _showEditEventDialog(context, event),
                                  isFirst: index == 0,
                                  isLast: index == selectedDayEvents.length - 1,
                                ),
                              );
                            },
                            childCount: selectedDayEvents.length,
                          ),
                        ),
                      ),

                    if (!_isToday(_selectedDate))
                      SliverToBoxAdapter(
                        child: _buildUpcomingSection(context, isDark, filteredEvents),
                      ),

                    const SliverPadding(
                      padding: EdgeInsets.only(bottom: 120),
                      sliver: SliverToBoxAdapter(child: SizedBox()),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, IServProvider iservProvider) {
    String iservStatus;
    if (!iservProvider.isConnected && iservProvider.username == null) {
      iservStatus = 'IServ: nicht verbunden';
    } else if (iservProvider.isSyncing) {
      iservStatus = 'IServ: synchronisiert...';
    } else {
      final calCount = iservProvider.calendarEvents.length;
      final evCount = iservProvider.events.length;
      iservStatus = 'IServ: $calCount Termine ($evCount roh)';
      if (iservProvider.lastSyncResult != null) {
        iservStatus += ' | ${iservProvider.lastSyncResult}';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTheme.gradientText('Kalender', fontSize: 36),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(DateTime.now()),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: kDebugMode ? () {
                    final debugText = 'Status: $iservStatus\n'
                        'Connected: ${iservProvider.isConnected}\n'
                        'Username: ${iservProvider.username ?? "none"}\n'
                        'IServ URL: ${iservProvider.iservUrl ?? "none"}\n'
                        'IServ Events: ${iservProvider.events.length}\n'
                        'Calendar Events: ${iservProvider.calendarEvents.length}\n'
                        'Show in Calendar: ${iservProvider.showIServInCalendar}\n'
                        'Last sync: ${iservProvider.lastSync}\n'
                        'Last result: ${iservProvider.lastSyncResult}\n'
                        '\n--- Provider Log ---\n${iservProvider.debugLog}'
                        '\n--- API Log ---\n${iservProvider.serviceApiLog}'
                        '\n--- Discovery Log ---\n${iservProvider.discoveryLog}';
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('IServ Debug'),
                        content: SingleChildScrollView(
                          child: SelectableText(
                            debugText,
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: debugText));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Log kopiert'), duration: Duration(seconds: 1)),
                              );
                            },
                            child: const Text('Kopieren'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              iservProvider.syncData();
                            },
                            child: const Text('Force Sync'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  } : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: iservProvider.isConnected
                          ? AppTheme.accent1.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: iservProvider.isConnected
                            ? AppTheme.accent1.withValues(alpha: 0.3)
                            : Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      iservStatus,
                      style: TextStyle(
                        fontSize: 10,
                        color: iservProvider.isConnected
                            ? AppTheme.accent1
                            : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.accent1],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showAddEventDialog(context, initialDate: _selectedDate),
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Neu',
                        style: TextStyle(
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
      ),
    );
  }

  Widget _buildCalendarCard(BuildContext context, bool isDark, List<Event> allEvents, bool isTablet) {
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startingWeekday = firstDayOfMonth.weekday;

    final eventsByDay = <int, List<Event>>{};
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_focusedMonth.year, _focusedMonth.month, day);
      eventsByDay[day] = _getEventsForDate(allEvents, date);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: GlassCard(
            borderRadius: 20,
            padding: EdgeInsets.zero,
            child: Column(
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Row(
              children: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chevron_left_rounded, size: 20),
                  ),
                  onPressed: () => _changeMonth(-1),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showMonthPicker(context),
                    child: AnimatedBuilder(
                      animation: _monthTransitionController,
                      builder: (context, child) {
                        final progress = Curves.easeOutCubic.transform(_monthTransitionController.value);
                        return Opacity(
                          opacity: progress.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(20 * _monthSlideDirection * (1.0 - progress), 0),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          Text(
                            DateFormat('MMMM', 'de_DE').format(_focusedMonth),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            '${_focusedMonth.year}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chevron_right_rounded, size: 20),
                  ),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _daysOfWeek
                  .map((day) => SizedBox(
                        width: isTablet ? 50 : 40,
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: day == 'Sa' || day == 'So'
                                ? AppTheme.primaryColor.withValues(alpha: 0.7)
                                : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),

          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: _monthTransitionController,
              builder: (context, child) {
                final progress = Curves.easeOutCubic.transform(_monthTransitionController.value);
                return Opacity(
                  opacity: progress.clamp(0.0, 1.0),
                  child: child,
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Builder(
                  builder: (context) {
                    final weeksNeeded = ((startingWeekday - 1 + daysInMonth + 6) ~/ 7);
                    final cellCount = weeksNeeded * 7;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: 0.7,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: cellCount,
                      itemBuilder: (context, index) {
                        final dayOffset = index - startingWeekday + 2;
                        if (dayOffset < 1 || dayOffset > daysInMonth) {
                          return const SizedBox();
                        }

                        final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayOffset);
                        final dayEvents = eventsByDay[dayOffset] ?? const [];
                        final isToday = _isToday(date);
                        final isSelected = _isSameDay(date, _selectedDate);
                        final isWeekend = date.weekday == 6 || date.weekday == 7;

                        return _CalendarDay(
                          day: dayOffset,
                          events: dayEvents,
                          isToday: isToday,
                          isSelected: isSelected,
                          isWeekend: isWeekend,
                          isDark: isDark,
                          onTap: () => _selectDate(date),
                          onDoubleTap: () {
                            _selectDate(date);
                            showAddEventDialog(context, initialDate: date);
                          },
                          getCategoryColor: _getCategoryColor,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),

          if (!_isSameMonth(_focusedMonth, DateTime.now()))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _focusedMonth = DateTime.now();
                    _selectedDate = DateTime.now();
                  });
                },
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('Heute'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                ),
              ),
            ),
        ],
      ),
      ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters(bool isDark) {
    final categories = [
      ('all', 'Alle', Icons.apps_rounded),
      ('school', 'Schule', Icons.school_rounded),
      ('training', 'Training', Icons.fitness_center_rounded),
      ('personal', 'Privat', Icons.person_rounded),
      ('work', 'Arbeit', Icons.work_rounded),
      ('holiday', 'Feiertage', Icons.celebration_rounded),
      ('vacation', 'Ferien', Icons.beach_access_rounded),
    ];

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final (filter, label, icon) = categories[index];
          final isSelected = _currentFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _dayEventsController.forward(from: 0.0);
                    setState(() => _currentFilter = filter);
                  },
                  borderRadius: BorderRadius.circular(9999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF7353CD)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: isSelected ? Colors.white : AppTheme.darkTextMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? Colors.white : AppTheme.darkTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedDayHeader(bool isDark, int eventCount) {
    final isToday = _isToday(_selectedDate);
    final isTomorrow = _isSameDay(_selectedDate, DateTime.now().add(const Duration(days: 1)));

    String label;
    if (isToday) {
      label = 'Heute';
    } else if (isTomorrow) {
      label = 'Morgen';
    } else {
      label = DateFormat('EEEE, d. MMMM', 'de_DE').format(_selectedDate);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTheme.sectionLabel(isDark),
          ),
          const SizedBox(height: 4),
          Text(
            eventCount == 0
                ? 'Keine Termine'
                : '$eventCount ${eventCount == 1 ? 'Termin' : 'Termine'}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDayState(BuildContext context, bool isDark) {
    return AnimatedBuilder(
      animation: _dayEventsController,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_dayEventsController.value);
        return Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.9 + 0.1 * t,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.all(32),
          child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                size: 40,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Keine Termine',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'An diesem Tag ist nichts geplant',
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => showAddEventDialog(context, initialDate: _selectedDate),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Termin hinzufügen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: const BorderSide(color: AppTheme.primaryColor),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildUpcomingSection(BuildContext context, bool isDark, List<Event> events) {
    final now = DateTime.now();
    final upcoming = events
        .where((e) => e.startTime.isAfter(now))
        .take(3)
        .toList();

    if (upcoming.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'KOMMENDE TERMINE',
            style: AppTheme.sectionLabel(isDark),
          ),
          const SizedBox(height: 12),
          ...upcoming.asMap().entries.map((entry) => AnimatedListItem(
            index: entry.key,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _UpcomingEventCard(
                event: entry.value,
                categoryColor: _getCategoryColor(entry.value.category),
                categoryIcon: _getCategoryIcon(entry.value.category),
                isDark: isDark,
                onTap: () {
                  _dayEventsController.forward(from: 0.0);
                  setState(() {
                    _selectedDate = entry.value.startTime;
                    _focusedMonth = DateTime(entry.value.startTime.year, entry.value.startTime.month);
                  });
                },
              ),
            ),
          )),
        ],
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  void _showMonthPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _MonthPickerSheet(
        selectedMonth: _focusedMonth,
        onMonthSelected: (month) {
          setState(() => _focusedMonth = month);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showEditEventDialog(BuildContext context, Event event) {
    showDialog(
      context: context,
      builder: (context) => _EventDialog(event: event),
    );
  }
}

class _CalendarDay extends StatefulWidget {
  final int day;
  final List<Event> events;
  final bool isToday;
  final bool isSelected;
  final bool isWeekend;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final Color Function(String) getCategoryColor;

  const _CalendarDay({
    required this.day,
    required this.events,
    required this.isToday,
    required this.isSelected,
    required this.isWeekend,
    required this.isDark,
    required this.onTap,
    this.onDoubleTap,
    required this.getCategoryColor,
  });

  @override
  State<_CalendarDay> createState() => _CalendarDayState();
}

class _CalendarDayState extends State<_CalendarDay> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
      lowerBound: 0.92,
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
    final colorCounts = <Color, int>{};
    for (final event in widget.events) {
      final color = widget.getCategoryColor(event.category);
      colorCounts[color] = (colorCounts[color] ?? 0) + 1;
    }
    final hasEvents = widget.events.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onTapDown: (_) => _scaleController.reverse(),
      onTapUp: (_) => _scaleController.forward(),
      onTapCancel: () => _scaleController.forward(),
      child: ScaleTransition(
        scale: _scaleController,
        child: Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? const Color(0xFF7353CD)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  border: widget.isToday && !widget.isSelected
                      ? Border.all(color: const Color(0xFF7353CD), width: 2)
                      : null,
                  boxShadow: widget.isToday
                      ? [BoxShadow(color: const Color(0xFF7353CD).withValues(alpha: 0.4), blurRadius: 10, spreadRadius: -2)]
                      : null,
                ),
                child: Center(
                  child: Text(
                    '${widget.day}',
                    style: TextStyle(
                      fontWeight: widget.isToday || widget.isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 14,
                      color: widget.isSelected
                          ? Colors.white
                          : widget.isToday
                              ? AppTheme.primaryColor
                              : widget.isWeekend
                                  ? AppTheme.primaryColor.withValues(alpha: 0.6)
                                  : null,
                    ),
                  ),
                ),
              ),
            ),
            if (hasEvents)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, top: 1),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 4,
                    child: Row(
                      children: colorCounts.entries.map((entry) {
                        return Expanded(
                          flex: entry.value,
                          child: Container(
                            color: widget.isSelected
                                ? Colors.white.withValues(alpha: 0.85)
                                : entry.key,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModernEventCard extends StatefulWidget {
  final Event event;
  final Color categoryColor;
  final IconData categoryIcon;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final bool isFirst;
  final bool isLast;

  const _ModernEventCard({
    required this.event,
    required this.categoryColor,
    required this.categoryIcon,
    this.onDelete,
    this.onEdit,
    required this.isFirst,
    required this.isLast,
  });

  @override
  State<_ModernEventCard> createState() => _ModernEventCardState();
}

class _ModernEventCardState extends State<_ModernEventCard> with SingleTickerProviderStateMixin {
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isReadOnly = widget.onDelete == null;

    Widget card = GestureDetector(
      onTapDown: (_) => _slideController.forward(),
      onTapUp: (_) => _slideController.reverse(),
      onTapCancel: () => _slideController.reverse(),
      child: AnimatedBuilder(
        animation: _slideController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(4 * _slideController.value, 0),
            child: child,
          );
        },
        child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          borderRadius: 16,
          padding: EdgeInsets.zero,
          onTap: widget.onEdit,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: widget.categoryColor, width: 4),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.categoryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.categoryIcon,
                      color: widget.categoryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.event.allDay ? 'Ganztags' : widget.event.timeRange,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                        if (widget.event.location != null && widget.event.location!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.event.location!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  context.read<VbbProvider>().setPendingDestination(widget.event.location!);
                                  MainScreen.navigateTo(15);
                                },
                                child: Tooltip(
                                  message: 'Route planen',
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: widget.categoryColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.directions_transit_rounded,
                                      size: 16,
                                      color: widget.categoryColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      Event.categories[widget.event.category] ?? widget.event.category,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.categoryColor,
                      ),
                    ),
                  ),
                ],
            ),
          ),
        ),
      ),
      ),
    );

    if (isReadOnly) return card;

    return Dismissible(
      key: Key(widget.event.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.danger,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Termin löschen'),
            content: const Text('Möchtest du diesen Termin wirklich löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => widget.onDelete?.call(),
      child: card,
    );
  }
}

class _UpcomingEventCard extends StatelessWidget {
  final Event event;
  final Color categoryColor;
  final IconData categoryIcon;
  final bool isDark;
  final VoidCallback onTap;

  const _UpcomingEventCard({
    required this.event,
    required this.categoryColor,
    required this.categoryIcon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 12,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: categoryColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            DateFormat('EEEE, d. MMM', 'de_DE').format(event.startTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ],
                ),
    );
  }
}

class _MonthPickerSheet extends StatelessWidget {
  final DateTime selectedMonth;
  final Function(DateTime) onMonthSelected;

  const _MonthPickerSheet({
    required this.selectedMonth,
    required this.onMonthSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentYear = DateTime.now().year;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Monat auswählen',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = DateTime(currentYear, index + 1);
                final isSelected = selectedMonth.month == index + 1 &&
                                   selectedMonth.year == currentYear;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onMonthSelected(month),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        DateFormat('MMM', 'de_DE').format(month),
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? Colors.white : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _EventDialog extends StatefulWidget {
  final Event? event;
  final DateTime? initialDate;

  const _EventDialog({this.event, this.initialDate});

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;
  late DateTime _startTime;
  late DateTime _endTime;
  bool _allDay = false;
  String _category = 'personal';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event?.title ?? '');
    _descriptionController = TextEditingController(text: widget.event?.description ?? '');
    _locationController = TextEditingController(text: widget.event?.location ?? '');

    if (widget.event != null) {
      _startTime = widget.event!.startTime;
      _endTime = widget.event!.endTime;
    } else {
      final date = widget.initialDate ?? DateTime.now();
      final now = DateTime.now();
      final bool isToday = date.year == now.year && date.month == now.month && date.day == now.day;
      final int startHour = isToday ? (now.hour + 1).clamp(0, 23) : 9;
      _startTime = DateTime(date.year, date.month, date.day, startHour, 0);
      _endTime = _startTime.add(const Duration(hours: 1));
    }

    _allDay = widget.event?.allDay ?? false;
    _category = widget.event?.category ?? 'personal';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.event != null ? Icons.edit_rounded : Icons.add_rounded,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.event != null ? 'Termin bearbeiten' : 'Neuer Termin',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Titel',
                  hintText: 'Was steht an?',
                  prefixIcon: const Icon(Icons.title_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Beschreibung (optional)',
                  hintText: 'Weitere Details...',
                  prefixIcon: const Icon(Icons.description_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Ort (optional)',
                  hintText: 'Wo findet es statt?',
                  prefixIcon: const Icon(Icons.location_on_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: 'Kategorie',
                  prefixIcon: const Icon(Icons.category_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: Event.categories.entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value))
                ).toList(),
                onChanged: (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: const Text('Ganztags'),
                  value: _allDay,
                  onChanged: (value) => setState(() => _allDay = value),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _DateTimeButton(
                      label: 'Start',
                      dateTime: _startTime,
                      allDay: _allDay,
                      onTap: () => _selectDateTime(true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateTimeButton(
                      label: 'Ende',
                      dateTime: _endTime,
                      allDay: _allDay,
                      onTap: () => _selectDateTime(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  if (widget.event != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Termin löschen'),
                              content: const Text('Möchtest du diesen Termin wirklich löschen?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Abbrechen'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && context.mounted) {
                            context.read<AppProvider>().deleteEvent(widget.event!.id);
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.delete_rounded),
                        label: const Text('Löschen'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  if (widget.event != null) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Speichern'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateTime(bool isStart) async {
    final initialDate = isStart ? _startTime : _endTime;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (date == null || !mounted) return;

    if (_allDay) {
      setState(() {
        if (isStart) {
          _startTime = DateTime(date.year, date.month, date.day);
        } else {
          _endTime = DateTime(date.year, date.month, date.day, 23, 59);
        }
      });
    } else {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );

      if (time != null && mounted) {
        setState(() {
          final newDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
          if (isStart) {
            _startTime = newDateTime;
            if (_endTime.isBefore(_startTime)) {
              _endTime = _startTime.add(const Duration(hours: 1));
            }
          } else {
            _endTime = newDateTime;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Titel eingeben')),
      );
      return;
    }

    final provider = context.read<AppProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (widget.event != null) {
        await provider.updateEvent(widget.event!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          startTime: _startTime,
          endTime: _endTime,
          allDay: _allDay,
          category: _category,
        ));
      } else {
        await provider.addEvent(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          location: _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          startTime: _startTime,
          endTime: _endTime,
          allDay: _allDay,
          category: _category,
        );
      }

      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(widget.event != null ? 'Termin aktualisiert' : 'Termin gespeichert'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Fehler beim Speichern: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }
}

class _DateTimeButton extends StatelessWidget {
  final String label;
  final DateTime dateTime;
  final bool allDay;
  final VoidCallback onTap;

  const _DateTimeButton({
    required this.label,
    required this.dateTime,
    required this.allDay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('dd.MM.yyyy').format(dateTime),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!allDay)
                Text(
                  DateFormat('HH:mm').format(dateTime),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.primaryColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void showAddEventDialog(BuildContext context, {DateTime? initialDate}) {
  showDialog(
    context: context,
    builder: (context) => _EventDialog(initialDate: initialDate),
  );
}
