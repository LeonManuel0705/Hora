// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../models/task.dart';
import '../theme.dart';
import '../widgets/page_fade_in.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/swipe_to_dismiss.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _currentFilter = 'today';

  List<Task> _filterTasks(List<Task> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfWeek = today.add(Duration(days: 7 - today.weekday));

    switch (_currentFilter) {
      case 'today':
        return tasks.where((t) {
          if (t.completed) return false;
          if (t.dueDate == null) return false;
          final dueDay = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          return dueDay.isAtSameMomentAs(today) || dueDay.isBefore(today);
        }).toList();
      case 'week':
        return tasks.where((t) {
          if (t.completed) return false;
          if (t.dueDate == null) return false;
          final dueDay = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          return dueDay.isAfter(today) && !dueDay.isAfter(endOfWeek);
        }).toList();
      case 'later':
        return tasks.where((t) {
          if (t.completed) return false;
          if (t.dueDate == null) return true;
          final dueDay = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          return dueDay.isAfter(endOfWeek);
        }).toList();
      case 'completed':
        return tasks.where((t) => t.completed).toList();
      case 'all':
      default:
        return tasks.where((t) => !t.completed).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final filteredTasks = _filterTasks(provider.tasks);

        final highPriority = filteredTasks.where((t) => t.priority == 'high').toList();
        final normalPriority = filteredTasks.where((t) => t.priority == 'medium').toList();
        final lowPriority = filteredTasks.where((t) => t.priority == 'low').toList();

        return PageFadeIn(
          child: RefreshIndicator(
          onRefresh: provider.refresh,
          child: CustomScrollView(
            slivers: [

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AppTheme.gradientText('Aufgaben', fontSize: 36),
                      GestureDetector(
                        onTap: () => showAddTaskDialog(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7353CD),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text('Neu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('today', 'Heute'),
                        const SizedBox(width: 8),
                        _buildFilterChip('week', 'Diese Woche'),
                        const SizedBox(width: 8),
                        _buildFilterChip('later', 'Später'),
                        const SizedBox(width: 8),
                        _buildFilterChip('all', 'Alle'),
                        const SizedBox(width: 8),
                        _buildFilterChip('completed', 'Erledigt'),
                      ],
                    ),
                  ),
                ),
              ),

              if (filteredTasks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context),
                )
              else ...[
                if (highPriority.isNotEmpty)
                  _buildTaskGroup(context, 'Hohe Priorität', highPriority, AppTheme.danger, provider),
                if (normalPriority.isNotEmpty)
                  _buildTaskGroup(context, 'Normal', normalPriority, AppTheme.primaryColor, provider),
                if (lowPriority.isNotEmpty)
                  _buildTaskGroup(context, 'Niedrige Priorität', lowPriority, AppTheme.success, provider),
              ],

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
  }

  Widget _buildFilterChip(String filter, String label) {
    final isSelected = _currentFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _currentFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7353CD) : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF71717A),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final messages = {
      'today': 'Keine Aufgaben für heute',
      'week': 'Keine Aufgaben diese Woche',
      'later': 'Keine späteren Aufgaben',
      'completed': 'Keine erledigten Aufgaben',
      'all': 'Keine Aufgaben vorhanden',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 64,
              color: AppTheme.primaryColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              messages[_currentFilter] ?? 'Keine Aufgaben',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showAddTaskDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Aufgabe hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildTaskGroup(
    BuildContext context,
    String title,
    List<Task> tasks,
    Color color,
    AppProvider provider,
  ) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
              borderRadius: 20,
              enableTapScale: false,
              child: Column(
                children: List.generate(tasks.length, (i) {
                  final task = tasks[i];
                  return AnimatedListItem(
                    index: i,
                    child: SwipeToDismissWidget(
                      onDismiss: () => provider.deleteTask(task.id),
                      confirmTitle: 'Aufgabe löschen?',
                      confirmMessage: 'Möchtest du diese Aufgabe wirklich löschen?',
                      confirmLabel: 'Löschen',
                      cancelLabel: 'Abbrechen',
                      child: _TaskListItem(
                        task: task,
                        onToggle: () => provider.toggleTaskComplete(task.id),
                        onDelete: () => provider.deleteTask(task.id),
                        onEdit: () => _showEditTaskDialog(context, task),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditTaskDialog(BuildContext context, Task task) {
    showDialog(
      context: context,
      builder: (context) => _TaskDialog(task: task),
    );
  }
}

class _TaskListItem extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _TaskListItem({
    required this.task,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  Color get categoryColor {
    switch (task.category) {
      case 'school':
        return AppTheme.accent1;
      case 'training':
        return AppTheme.trainingColor;
      case 'project':
        return AppTheme.projectsColor;
      case 'personal':
        return AppTheme.accent3;
      default:
        return AppTheme.gray;
    }
  }

  Widget _buildPriorityBadge() {
    String label;
    Color bgColor;
    Color textColor;

    switch (task.priority) {
      case 'high':
        label = 'Hoch';
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFFE11D48);
        break;
      case 'medium':
        label = 'Normal';
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFD97706);
        break;
      default:
        label = 'Niedrig';
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF059669);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = task.dueDate != null
        ? DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day)
        : null;
    final isOverdue = !task.completed && dueDay != null && dueDay.isBefore(today);

    final double itemOpacity = task.completed ? 0.6 : 1.0;

    return Opacity(
      opacity: itemOpacity,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: onToggle,
                child: Icon(
                  task.completed ? Icons.check_circle : Icons.circle_outlined,
                  color: task.completed
                      ? const Color(0xFF10B981)
                      : (isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA)),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              decoration: task.completed ? TextDecoration.lineThrough : null,
                              color: task.completed
                                  ? (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildPriorityBadge(),
                      ],
                    ),
                    if (task.description != null && task.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        task.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          decoration: task.completed ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (task.dueDate != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isOverdue
                                  ? AppTheme.danger.withValues(alpha: 0.1)
                                  : (isDark ? AppTheme.darkSurface : AppTheme.lightSurface),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _formatDueDate(task.dueDate!),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isOverdue ? AppTheme.danger : null,
                              ),
                            ),
                          ),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            Task.categories[task.category] ?? task.category,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: categoryColor,
                            ),
                          ),
                        ),
                        if (task.estimatedMinutes != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.info.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, size: 12, color: AppTheme.info),
                                const SizedBox(width: 3),
                                Text(
                                  Task.timeEstimates[task.estimatedMinutes] ?? '${task.estimatedMinutes} Min',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.info,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (task.repeatType != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.repeat, size: 12, color: AppTheme.primaryLight),
                                const SizedBox(width: 3),
                                Text(
                                  Task.repeatTypes[task.repeatType] ?? task.repeatType!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.primaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dueDay = DateTime(date.year, date.month, date.day);

    if (dueDay.isAtSameMomentAs(today)) {
      return 'Heute';
    } else if (dueDay.isAtSameMomentAs(tomorrow)) {
      return 'Morgen';
    } else if (dueDay.isBefore(today)) {
      return 'Überfällig';
    } else {
      return DateFormat('dd. MMM', 'de_DE').format(date);
    }
  }
}

class _TaskDialog extends StatefulWidget {
  final Task? task;

  const _TaskDialog({this.task});

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  DateTime? _dueDate;
  String _priority = 'medium';
  String _category = 'general';
  int? _estimatedMinutes;
  String? _repeatType;
  List<int> _repeatWeekdays = [];
  DateTime? _repeatEndDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task?.title ?? '');
    _descriptionController = TextEditingController(text: widget.task?.description ?? '');
    _dueDate = widget.task?.dueDate;
    _priority = widget.task?.priority ?? 'medium';
    _category = widget.task?.category ?? 'general';
    _estimatedMinutes = widget.task?.estimatedMinutes;
    _repeatType = widget.task?.repeatType;
    _repeatWeekdays = List<int>.from(widget.task?.repeatWeekdays ?? []);
    _repeatEndDate = widget.task?.repeatEndDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task != null ? 'Aufgabe bearbeiten' : 'Neue Aufgabe'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Titel',
                hintText: 'Was muss erledigt werden?',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Beschreibung (optional)',
                hintText: 'Weitere Details...',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(_dueDate != null
                  ? DateFormat('dd.MM.yyyy HH:mm').format(_dueDate!)
                  : 'Fällig am (optional)'),
              trailing: _dueDate != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dueDate = null),
                    )
                  : null,
              onTap: _selectDateTime,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(
                labelText: 'Priorität',
                prefixIcon: Icon(Icons.flag),
              ),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Niedrig')),
                DropdownMenuItem(value: 'medium', child: Text('Normal')),
                DropdownMenuItem(value: 'high', child: Text('Hoch')),
              ],
              onChanged: (value) => setState(() => _priority = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                labelText: 'Kategorie',
                prefixIcon: Icon(Icons.category),
              ),
              items: Task.categories.entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value))
              ).toList(),
              onChanged: (value) => setState(() => _category = value!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _estimatedMinutes,
              decoration: const InputDecoration(
                labelText: 'Geschätzte Dauer (optional)',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Keine Angabe')),
                ...Task.timeEstimates.entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value))
                ),
              ],
              onChanged: (value) => setState(() => _estimatedMinutes = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _repeatType,
              decoration: const InputDecoration(
                labelText: 'Wiederholung',
                prefixIcon: Icon(Icons.repeat),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Keine')),
                ...Task.repeatTypes.entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value))
                ),
              ],
              onChanged: (value) => setState(() {
                _repeatType = value;
                if (value != 'custom') _repeatWeekdays = [];
              }),
            ),
            if (_repeatType == 'custom') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Wochentage',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  final selected = _repeatWeekdays.contains(day);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _repeatWeekdays.remove(day);
                      } else {
                        _repeatWeekdays.add(day);
                        _repeatWeekdays.sort();
                      }
                    }),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? AppTheme.primaryColor
                            : AppTheme.primaryColor.withValues(alpha: 0.08),
                        border: Border.all(
                          color: selected
                              ? AppTheme.primaryColor
                              : AppTheme.primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        Task.weekdayLabels[index],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
            if (_repeatType != null) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_outlined),
                title: Text(_repeatEndDate != null
                    ? 'Endet am ${DateFormat('dd.MM.yyyy').format(_repeatEndDate!)}'
                    : 'Enddatum (optional)'),
                trailing: _repeatEndDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _repeatEndDate = null),
                      )
                    : null,
                onTap: _selectRepeatEndDate,
              ),
            ],
          ],
        ),
      ),
      ),
      actions: [
        if (widget.task != null)
          TextButton(
            onPressed: () {
              context.read<AppProvider>().deleteTask(widget.task!.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Löschen'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()),
      );

      if (time != null && mounted) {
        setState(() {
          _dueDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        });
      }
    }
  }

  Future<void> _selectRepeatEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _repeatEndDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (date != null && mounted) {
      setState(() => _repeatEndDate = date);
    }
  }

  void _save() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Titel eingeben')),
      );
      return;
    }

    final provider = context.read<AppProvider>();

    final repeatWeekdays = _repeatType == 'custom' && _repeatWeekdays.isNotEmpty
        ? _repeatWeekdays
        : null;
    final repeatEndDate = _repeatType != null ? _repeatEndDate : null;

    if (widget.task != null) {
      provider.updateTask(widget.task!.copyWith(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        dueDate: _dueDate,
        priority: _priority,
        category: _category,
        estimatedMinutes: _estimatedMinutes,
        repeatType: _repeatType,
        repeatWeekdays: repeatWeekdays,
        repeatEndDate: repeatEndDate,
      ));
    } else {
      provider.addTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        dueDate: _dueDate,
        priority: _priority,
        category: _category,
        estimatedMinutes: _estimatedMinutes,
        repeatType: _repeatType,
        repeatWeekdays: repeatWeekdays,
        repeatEndDate: repeatEndDate,
      );
    }

    Navigator.pop(context);
  }
}

void showAddTaskDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const _TaskDialog(),
  );
}
