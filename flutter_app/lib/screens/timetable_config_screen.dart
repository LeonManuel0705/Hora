// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/timetable_period.dart';
import '../models/lesson.dart';
import '../theme.dart';
import 'school_screen.dart';

class TimetableConfigScreen extends StatefulWidget {
  const TimetableConfigScreen({super.key});

  @override
  State<TimetableConfigScreen> createState() => _TimetableConfigScreenState();
}

class _TimetableConfigScreenState extends State<TimetableConfigScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _weekToggled = false;

  bool _displayedIsAWeek(AppProvider provider) {
    final baseIsAWeek = provider.isCurrentlyAWeek();
    return _weekToggled ? !baseIsAWeek : baseIsAWeek;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().loadTimetablePeriods();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showWeekOverrideDialog(BuildContext context, AppProvider provider, bool isDark) {
    final isInverted = provider.abWeekInverted;
    final algorithmWeek = AppProvider.calculateIsAWeek(DateTime.now()) ? 'A' : 'B';
    final effectiveWeek = provider.isCurrentlyAWeek() ? 'A' : 'B';
    final oppositeWeek = effectiveWeek == 'A' ? 'B' : 'A';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isInverted ? 'Korrektur zurücksetzen?' : 'Woche korrigieren'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isInverted) ...[
              const Text('Die Wochenkorrektur ist aktiv.'),
              const SizedBox(height: 8),
              Text('Algorithmus sagt: $algorithmWeek-Woche'),
              Text('Aktuell angezeigt: $effectiveWeek-Woche'),
              const SizedBox(height: 12),
              const Text('Möchtest du die Korrektur zurücksetzen?'),
            ] else ...[
              Text('Das System zeigt $effectiveWeek-Woche an.'),
              const SizedBox(height: 8),
              Text(
                'Falls deine Schule diese Woche tatsächlich '
                '$oppositeWeek-Woche hat, kannst du die Zuordnung '
                'dauerhaft umkehren.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppTheme.primaryColor),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dies ändert die Woche dauerhaft — der Wechsel-Rhythmus bleibt erhalten.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              provider.toggleAbWeekInversion();
              setState(() => _weekToggled = false);
              Navigator.pop(dialogContext);
            },
            style: FilledButton.styleFrom(
              backgroundColor: isInverted ? AppTheme.danger : AppTheme.primaryColor,
            ),
            child: Text(isInverted ? 'Zurücksetzen' : 'Woche umkehren'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stundenplan konfigurieren'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Zeiten'),
            Tab(text: 'Raster'),
          ],
          labelColor: AppTheme.primaryColor,
          indicatorColor: AppTheme.primaryColor,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildZeitenTab(isDark),
          _buildRasterTab(isDark),
        ],
      ),
    );
  }

  Widget _buildZeitenTab(bool isDark) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final periods = provider.timetablePeriods
            .map((m) => TimetablePeriod.fromMap(m))
            .toList();

        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.65),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.schedule, color: AppTheme.primaryColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unterrichtszeiten',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Konfiguriere die Zeiten deiner Schulstunden',
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: periods.isEmpty
                  ? _buildEmptyPeriodsState(isDark)
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: periods.length,
                      itemBuilder: (context, index) {
                        final period = periods[index];
                        return _buildPeriodCard(period, isDark);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => _showAddPeriodDialog(periods.length + 1),
                icon: const Icon(Icons.add),
                label: const Text('Stunde hinzufügen'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyPeriodsState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_outlined,
              size: 48,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Keine Stunden konfiguriert',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Füge deine erste Schulstunde hinzu',
            style: TextStyle(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodCard(TimetablePeriod period, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.8),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${period.periodNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              title: Text(
                period.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: AppTheme.primaryColor),
                      const SizedBox(width: 4),
                      Text(period.timeRange),
                    ],
                  ),
                  if (period.hasSplit) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Geteilte Stunde (${period.splitBreakMinutes ?? 5} Min. Pause)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditPeriodDialog(period);
                  } else if (value == 'delete') {
                    _deletePeriod(period);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('Bearbeiten'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Löschen', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddPeriodDialog(int periodNumber) {
    _showPeriodDialog(periodNumber: periodNumber);
  }

  void _showEditPeriodDialog(TimetablePeriod period) {
    _showPeriodDialog(period: period);
  }

  void _showPeriodDialog({int? periodNumber, TimetablePeriod? period}) {
    final isEdit = period != null;
    final startTimeController = TextEditingController(text: period?.startTime ?? '08:00');
    final endTimeController = TextEditingController(text: period?.endTime ?? '08:45');
    final nameController = TextEditingController(text: period?.name ?? '');
    bool hasSplit = period?.hasSplit ?? false;
    int splitBreakMinutes = period?.splitBreakMinutes ?? 5;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Stunde bearbeiten' : 'Neue Stunde'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: '${periodNumber ?? period?.periodNumber}. Stunde',
                    prefixIcon: const Icon(Icons.label),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.access_time),
                        title: const Text('Start'),
                        subtitle: Text(startTimeController.text),
                        onTap: () async {
                          final time = await _selectTime(startTimeController.text);
                          if (time != null) {
                            setDialogState(() => startTimeController.text = time);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.access_time_filled),
                        title: const Text('Ende'),
                        subtitle: Text(endTimeController.text),
                        onTap: () async {
                          final time = await _selectTime(endTimeController.text);
                          if (time != null) {
                            setDialogState(() => endTimeController.text = time);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Geteilte Stunde'),
                  subtitle: const Text('Mit Pause in der Mitte'),
                  value: hasSplit,
                  onChanged: (value) => setDialogState(() => hasSplit = value),
                ),
                if (hasSplit) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Pausendauer: '),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: splitBreakMinutes,
                        items: [5, 10, 15, 20].map((m) => DropdownMenuItem(
                          value: m,
                          child: Text('$m Min.'),
                        )).toList(),
                        onChanged: (value) => setDialogState(() => splitBreakMinutes = value!),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                final startMinutes = _parseMinutes(startTimeController.text);
                final endMinutes = _parseMinutes(endTimeController.text);
                if (startMinutes == null || endMinutes == null) return;

                if (startMinutes >= endMinutes) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('Die Startzeit muss vor der Endzeit liegen.'),
                    ),
                  );
                  return;
                }

                final provider = this.context.read<AppProvider>();
                final pNum = periodNumber ?? period!.periodNumber;

                if (isEdit) {
                  provider.updateTimetablePeriod(
                    periodNumber: pNum,
                    name: nameController.text.isEmpty ? null : nameController.text,
                    startTime: startTimeController.text,
                    endTime: endTimeController.text,
                    hasSplit: hasSplit,
                    splitBreakMinutes: hasSplit ? splitBreakMinutes : null,
                  );
                } else {
                  provider.addTimetablePeriod(
                    periodNumber: pNum,
                    name: nameController.text.isEmpty ? null : nameController.text,
                    startTime: startTimeController.text,
                    endTime: endTimeController.text,
                    hasSplit: hasSplit,
                    splitBreakMinutes: hasSplit ? splitBreakMinutes : null,
                  );
                }

                Navigator.pop(context);
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    ).then((_) => Future.delayed(const Duration(milliseconds: 300), () {
      startTimeController.dispose();
      endTimeController.dispose();
      nameController.dispose();
    }));
  }

  int? _parseMinutes(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    return hours * 60 + minutes;
  }

  Future<String?> _selectTime(String currentTime) async {
    final total = _parseMinutes(currentTime) ?? 8 * 60;
    final initialTime = TimeOfDay(
      hour: (total ~/ 60).clamp(0, 23),
      minute: (total % 60).clamp(0, 59),
    );

    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (time != null) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return null;
  }

  void _deletePeriod(TimetablePeriod period) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stunde löschen?'),
        content: Text('Möchtest du "${period.displayName}" wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppProvider>().deleteTimetablePeriod(period.periodNumber);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  Widget _buildRasterTab(bool isDark) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final periods = provider.timetablePeriods
            .map((m) => TimetablePeriod.fromMap(m))
            .toList()
          ..sort((a, b) => a.periodNumber.compareTo(b.periodNumber));

        if (periods.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.grid_off, size: 48, color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                const Text('Bitte zuerst Unterrichtszeiten konfigurieren'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _tabController.animateTo(0),
                  child: const Text('Zu den Zeiten'),
                ),
              ],
            ),
          );
        }

        final currentWeekType = _displayedIsAWeek(provider) ? 'A' : 'B';
        final abWeeksEnabled = provider.abWeeksEnabled;

        return Column(
          children: [
            if (abWeeksEnabled)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Woche: '),
                              const SizedBox(width: 8),
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(value: true, label: Text('A')),
                                  ButtonSegment(value: false, label: Text('B')),
                                ],
                                selected: {_displayedIsAWeek(provider)},
                                onSelectionChanged: (value) {
                                  setState(() {
                                    _weekToggled = (value.first != provider.isCurrentlyAWeek());
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 14,
                                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Diese Woche ist laut System ${provider.isCurrentlyAWeek() ? "A" : "B"}-Woche',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _showWeekOverrideDialog(context, provider, isDark),
                              icon: Icon(
                                Icons.swap_horiz,
                                size: 18,
                                color: provider.abWeekInverted ? AppTheme.danger : AppTheme.primaryColor,
                              ),
                              label: Text(
                                provider.abWeekInverted
                                    ? 'Korrektur zurücksetzen'
                                    : 'Aktuelle Woche korrigieren',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: provider.abWeekInverted
                                    ? AppTheme.danger
                                    : AppTheme.primaryColor,
                                side: BorderSide(
                                  color: (provider.abWeekInverted
                                      ? AppTheme.danger
                                      : AppTheme.primaryColor).withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: _buildTimetableGrid(provider, periods, currentWeekType, abWeeksEnabled, isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimetableGrid(
    AppProvider provider,
    List<TimetablePeriod> periods,
    String weekType,
    bool abWeeksEnabled,
    bool isDark,
  ) {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
    const cellWidth = 90.0;
    const cellHeight = 70.0;
    const headerHeight = 40.0;
    const periodColumnWidth = 70.0;

    return Table(
      defaultColumnWidth: const FixedColumnWidth(cellWidth),
      columnWidths: const {0: FixedColumnWidth(periodColumnWidth)},
      border: TableBorder.all(
        color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
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
            ...days.map((day) => SizedBox(
              height: headerHeight,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withValues(alpha: 0.1),
                      AppTheme.primaryLight.withValues(alpha: 0.1),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),

        ...periods.map((period) => TableRow(
          children: [

            SizedBox(
              height: cellHeight,
              child: Container(
                padding: const EdgeInsets.all(4),
                color: isDark
                    ? AppTheme.darkCard.withValues(alpha: 0.5)
                    : AppTheme.lightCard.withValues(alpha: 0.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${period.periodNumber}.',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    Text(
                      period.startTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                    Text(
                      period.endTime,
                      style: TextStyle(
                        fontSize: 10,
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
                  weekType,
                  abWeeksEnabled,
                  isDark,
                ),
              );
            }),
          ],
        )),
      ],
    );
  }

  Widget _buildGridCell(
    List<Lesson> lessons,
    int dayOfWeek,
    TimetablePeriod period,
    String weekType,
    bool abWeeksEnabled,
    bool isDark,
  ) {
    if (lessons.isEmpty) {
      return InkWell(
        onTap: () => _showAddLessonForCell(dayOfWeek, period, abWeeksEnabled),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
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

    final lesson = lessons.first;
    final color = lesson.color != null
        ? Color(int.tryParse(lesson.color!.replaceFirst('#', '0xFF')) ?? 0xFF0057FF)
        : AppTheme.primaryColor;

    return InkWell(
      onTap: () => _showEditLessonForCell(lesson, abWeeksEnabled),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
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
            if (lesson.room != null) ...[
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
}
