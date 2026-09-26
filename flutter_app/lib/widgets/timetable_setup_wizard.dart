// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme.dart';

class TimetableSetupWizard extends StatefulWidget {
  const TimetableSetupWizard({super.key});

  @override
  State<TimetableSetupWizard> createState() => _TimetableSetupWizardState();
}

class _TimetableSetupWizardState extends State<TimetableSetupWizard> {
  int _currentStep = 0;
  String _selectedTemplate = '';
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  int _periodCount = 8;
  List<int> _breakDurations = [];
  int _lessonDuration = 45;
  List<Map<String, dynamic>> _generatedPeriods = [];


  final List<Map<String, dynamic>> _customPeriods = [];

  void _selectTemplate(String template) {
    setState(() {
      _selectedTemplate = template;
      if (template == 'einzelstunden') {
        _lessonDuration = 45;
        _periodCount = 8;
        _breakDurations = List.generate(7, (i) => i == 1 ? 20 : 5);
      } else if (template == 'doppelstunden') {
        _lessonDuration = 90;
        _periodCount = 4;
        _breakDurations = List.generate(3, (i) => i == 1 ? 20 : 10);
      }
    });
  }

  void _updatePeriodCount(int newCount) {
    setState(() {
      _periodCount = newCount;
      while (_breakDurations.length < _periodCount - 1) {
        _breakDurations.add(5);
      }
      if (_breakDurations.length > _periodCount - 1) {
        _breakDurations = _breakDurations.sublist(0, _periodCount - 1);
      }
    });
  }

  void _generatePeriods() {
    if (_selectedTemplate == 'custom') return;

    final periods = <Map<String, dynamic>>[];
    var currentTime = DateTime(2000, 1, 1, _startTime.hour, _startTime.minute);

    for (int i = 1; i <= _periodCount; i++) {
      final endTime = currentTime.add(Duration(minutes: _lessonDuration));
      periods.add({
        'periodNumber': i,
        'name': null,
        'startTime':
            '${currentTime.hour.toString().padLeft(2, '0')}:${currentTime.minute.toString().padLeft(2, '0')}',
        'endTime':
            '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
        'hasSplit': false,
        'splitBreakMinutes': null,
      });


      int breakLen = (i - 1) < _breakDurations.length ? _breakDurations[i - 1] : 5;
      currentTime = endTime.add(Duration(minutes: breakLen));
    }

    _generatedPeriods = periods;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? AppPalette.overlayDark : AppPalette.overlay,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: .5) : const Color(0xFF14201A).withValues(alpha: .18),
              blurRadius: 36,
              spreadRadius: -10,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(isDark),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.1, 0), end: Offset.zero)
                        .animate(animation),
                    child: child,
                  ),
                ),
                child: _currentStep == 0
                    ? _buildTemplateStep(isDark)
                    : _currentStep == 1
                        ? _buildConfigStep(isDark)
                        : _buildConfirmStep(isDark),
              ),
            ),
            _buildFooter(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final icons = [
      Icons.style_outlined,
      Icons.tune,
      Icons.check_circle_outline
    ];
    final subtitles = ['Vorlage wählen', 'Anpassen', 'Bestätigen'];

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      color: isDark ? AppPalette.heroDark : AppPalette.pine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.chalk.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icons[_currentStep],
                    color: AppPalette.chalk, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Stundenraster',
                        style: TextStyle(
                            color: AppPalette.chalk,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text(subtitles[_currentStep],
                        style: TextStyle(
                            color: AppPalette.chalk.withValues(alpha: .8),
                            fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildStepPill(0, 'Vorlage'),
              const SizedBox(width: 6),
              _buildStepPill(1, 'Details'),
              const SizedBox(width: 6),
              _buildStepPill(2, 'Fertig'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: AppPalette.chalk.withValues(alpha: isCurrent ? .16 : isActive ? .08 : 0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppPalette.chalk.withValues(alpha: isCurrent ? .4 : .16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? AppPalette.chalk
                    : AppPalette.chalk.withValues(alpha: .2),
              ),
              child: Center(
                child: _currentStep > step
                    ? const Icon(Icons.check,
                        color: AppPalette.pine, size: 13)
                    : Text('${step + 1}',
                        style: TextStyle(
                            color: isActive
                                ? AppPalette.pine
                                : AppPalette.chalk,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    style: TextStyle(
                        color: AppPalette.chalk
                            .withValues(alpha: isActive ? 1.0 : 0.7),
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 12),
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateStep(bool isDark) {
    return Padding(
      key: const ValueKey('template'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTemplateCard('einzelstunden', 'Einzelstunden',
              '45 Minuten pro Stunde', Icons.looks_one_outlined, isDark),
          const SizedBox(height: 12),
          _buildTemplateCard('doppelstunden', 'Doppelstunden',
              '90 Minuten pro Block', Icons.looks_two_outlined, isDark),
          const SizedBox(height: 12),
          _buildTemplateCard('custom', 'Benutzerdefiniert',
              'Stunden einzeln festlegen', Icons.edit_outlined, isDark),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(
      String id, String title, String subtitle, IconData icon, bool isDark) {
    final isSelected = _selectedTemplate == id;
    final surface = isDark ? AppPalette.surfaceDark : AppPalette.surface;
    final accent = AppTheme.primaryColor;
    final onAccent = isDark ? Colors.white : AppPalette.chalk;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectTemplate(id),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? Color.alphaBlend(accent.withValues(alpha: isDark ? .16 : .06), surface)
                : surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accent
                  : (isDark ? AppPalette.lineDark : AppPalette.line),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent
                      : (isDark ? AppPalette.hoverDark : AppPalette.sunken),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 22,
                    color: isSelected
                        ? onAccent
                        : (isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted)),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 15,
                          color: isSelected
                              ? (isDark ? AppPalette.inkDark : AppPalette.ink)
                              : (isDark ? AppPalette.inkSoftDark : AppPalette.inkSoft))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted)),
                ],
              )),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(Icons.check, color: onAccent, size: 15),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigStep(bool isDark) {
    if (_selectedTemplate == 'custom') {
      return _buildCustomConfigStep(isDark);
    }
    return Padding(
      key: const ValueKey('config'),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Beginn'),
              trailing: GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                      context: context, initialTime: _startTime);
                  if (picked != null) setState(() => _startTime = picked);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor)),
                ),
              ),
            ),
            const Divider(),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                  'Anzahl ${_selectedTemplate == 'doppelstunden' ? 'Blöcke' : 'Stunden'}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      onPressed: _periodCount > 1
                          ? () => _updatePeriodCount(_periodCount - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('$_periodCount',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(
                      onPressed: _periodCount < 12
                          ? () => _updatePeriodCount(_periodCount + 1)
                          : null,
                      icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
            ),
            const Divider(),

            if (_breakDurations.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text('Pausen',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isDark
                            ? AppTheme.darkText
                            : AppTheme.lightText)),
              ),
              ...List.generate(_breakDurations.length, (i) {
                final label = _selectedTemplate == 'doppelstunden'
                    ? 'Nach Block ${i + 1}'
                    : 'Nach Stunde ${i + 1}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(label,
                              style: const TextStyle(fontSize: 13))),
                      DropdownButton<int>(
                        value: _breakDurations[i],
                        underline: const SizedBox(),
                        items: [0, 5, 10, 15, 20, 25, 30]
                            .map((m) => DropdownMenuItem(
                                value: m, child: Text('$m min')))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _breakDurations[i] = v!),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 16),

            Text('Vorschau', style: AppTheme.sectionLabel(isDark)),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              _generatePeriods();
              return Column(
                children: _generatedPeriods
                    .map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                    child: Text('${p['periodNumber']}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color:
                                                AppTheme.primaryColor))),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                  '${p['startTime']} - ${p['endTime']}',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87)),
                            ],
                          ),
                        ))
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomConfigStep(bool isDark) {
    return Padding(
      key: const ValueKey('custom'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Text('Stunden',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _addCustomPeriod,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Hinzufügen'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _customPeriods.isEmpty
                ? Center(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule,
                          size: 48,
                          color: isDark ? Colors.white24 : Colors.black12),
                      const SizedBox(height: 12),
                      Text('Füge deine erste Stunde hinzu',
                          style: TextStyle(
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38)),
                    ],
                  ))
                : ListView.builder(
                    itemCount: _customPeriods.length,
                    itemBuilder: (context, index) {
                      final p = _customPeriods[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  isDark ? Colors.white12 : Colors.black12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Center(
                                  child: Text('${index + 1}',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppTheme.primaryColor))),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () =>
                                  _editCustomPeriodTime(index, true),
                              child: Text(p['startTime'] as String,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.primaryColor)),
                            ),
                            Text(' - ',
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38)),
                            GestureDetector(
                              onTap: () =>
                                  _editCustomPeriodTime(index, false),
                              child: Text(p['endTime'] as String,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.primaryColor)),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38),
                              onPressed: () => setState(
                                  () => _customPeriods.removeAt(index)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _addCustomPeriod() {

    String defaultStart = '08:00';
    if (_customPeriods.isNotEmpty) {
      final lastEnd = _customPeriods.last['endTime'] as String;
      final parts = lastEnd.split(':');
      final endTime =
          DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
      final nextStart = endTime.add(const Duration(minutes: 5));
      defaultStart =
          '${nextStart.hour.toString().padLeft(2, '0')}:${nextStart.minute.toString().padLeft(2, '0')}';
    }

    final startParts = defaultStart.split(':');
    final startDt = DateTime(
        2000, 1, 1, int.parse(startParts[0]), int.parse(startParts[1]));
    final endDt = startDt.add(const Duration(minutes: 45));
    final defaultEnd =
        '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}';

    setState(() {
      _customPeriods.add({
        'periodNumber': _customPeriods.length + 1,
        'name': null,
        'startTime': defaultStart,
        'endTime': defaultEnd,
        'hasSplit': false,
        'splitBreakMinutes': null,
      });
    });
  }

  Future<void> _editCustomPeriodTime(int index, bool isStart) async {
    final current =
        _customPeriods[index][isStart ? 'startTime' : 'endTime'] as String;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked != null) {
      setState(() {
        _customPeriods[index][isStart ? 'startTime' : 'endTime'] =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Widget _buildConfirmStep(bool isDark) {
    final periods =
        _selectedTemplate == 'custom' ? _customPeriods : _generatedPeriods;

    return Padding(
      key: const ValueKey('confirm'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.sage.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 18, color: AppPalette.sage),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                        '${periods.length} Stunden konfiguriert',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white70
                                : Colors.black54))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: periods.length,
              itemBuilder: (context, index) {
                final p = periods[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                            child: Text(
                                '${p['periodNumber'] ?? index + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14))),
                      ),
                      const SizedBox(width: 14),
                      Text(
                          '${p['startTime']} - ${p['endTime']}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white
                                  : Colors.black87)),
                      const Spacer(),
                      Text(
                          _getDurationLabel(
                              p['startTime'] as String,
                              p['endTime'] as String),
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getDurationLabel(String start, String end) {
    final sp = start.split(':');
    final ep = end.split(':');
    final s = int.parse(sp[0]) * 60 + int.parse(sp[1]);
    final e = int.parse(ep[0]) * 60 + int.parse(ep[1]);
    final mins = e - s;
    if (mins >= 60) return '${mins ~/ 60}h ${mins % 60}min';
    return '${mins}min';
  }

  Widget _buildFooter(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: isDark ? AppPalette.lineDark : AppPalette.line))),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
                child: OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Zurück'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppPalette.inkDark : AppPalette.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                      color: isDark ? AppPalette.lineStrongDark : AppPalette.lineStrong),
                  shape: const StadiumBorder()),
            )),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _canProceed() ? _handleNext : null,
              icon: Icon(
                  _currentStep == 2
                      ? Icons.check
                      : Icons.arrow_forward,
                  size: 18),
              label:
                  Text(_currentStep == 2 ? 'Speichern' : 'Weiter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppPalette.brandDark : AppPalette.pine,
                foregroundColor: isDark ? AppPalette.inkDark : AppPalette.chalk,
                disabledBackgroundColor: isDark
                    ? AppPalette.lineDark
                    : AppPalette.lineStrong,
                disabledForegroundColor: isDark ? AppPalette.inkMutedDark : AppPalette.inkMuted,
                elevation: 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: StadiumBorder(
                    side: isDark && _canProceed()
                        ? const BorderSide(color: Color(0xFF3E5541))
                        : BorderSide.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    if (_currentStep == 0) return _selectedTemplate.isNotEmpty;
    if (_currentStep == 1) {
      if (_selectedTemplate == 'custom') return _customPeriods.isNotEmpty;
      return true;
    }
    return true;
  }

  void _handleNext() {
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
      if (_selectedTemplate != 'custom') _generatePeriods();
    } else if (_currentStep == 1) {
      if (_selectedTemplate != 'custom') _generatePeriods();
      setState(() => _currentStep = 2);
    } else {
      _save();
    }
  }

  Future<void> _save() async {
    final periods = _selectedTemplate == 'custom'
        ? _customPeriods
            .asMap()
            .entries
            .map((e) => {
                  ...e.value,
                  'periodNumber': e.key + 1,
                })
            .toList()
        : _generatedPeriods;

    final provider = context.read<AppProvider>();
    await provider.replaceAllTimetablePeriods(periods);

    if (mounted) Navigator.pop(context);
  }
}
