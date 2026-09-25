// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/notes_provider.dart';
import '../theme.dart';
import '../utils/platform_utils.dart';
import 'page_fade_in.dart';

class QuickNoteFab extends StatelessWidget {
  const QuickNoteFab({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFadeIn(
      delay: const Duration(milliseconds: 300),
      child: FloatingActionButton(
        heroTag: 'quick_note_fab',
        onPressed: () => showQuickNoteModal(context),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

void showQuickNoteModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 600),
    builder: (context) => const QuickNoteModal(),
  );
}

class QuickNoteModal extends StatefulWidget {
  const QuickNoteModal({super.key});

  @override
  State<QuickNoteModal> createState() => _QuickNoteModalState();
}

class _QuickNoteModalState extends State<QuickNoteModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();

  String _selectedType = 'note';
  int? _selectedSubjectId;
  DateTime? _dueDate;
  bool _isLoading = false;

  List<Map<String, dynamic>> _subjects = [];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final provider = context.read<AppProvider>();
    final subjects = await provider.getSubjects();
    if (mounted) {
      setState(() {
        _subjects = subjects.map((s) => {
          'id': s['id'],
          'name': s['name'],
        }).toList();
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  bool get _showSubjectField => _selectedType == 'homework';
  bool get _showDueDateField => _selectedType == 'homework' || _selectedType == 'task';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    final modalContainer = Container(
      margin: EdgeInsets.only(bottom: keyboardHeight),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: shouldUseBlur ? 0.7 : 0.85)
            : Colors.white.withValues(alpha: shouldUseBlur ? 0.85 : 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: AppTheme.primaryGradient,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_note, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Schnelle Notiz',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Text(
                  'Typ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                _buildTypeSelector(),
                const SizedBox(height: 20),

                if (_showSubjectField) ...[
                  Text(
                    'Fach',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSubjectDropdown(),
                  const SizedBox(height: 20),
                ],

                Text(
                  'Titel',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    hintText: _getTitleHint(),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Bitte Titel eingeben';
                    }
                    return null;
                  },
                  autofocus: true,
                ),
                const SizedBox(height: 20),

                Text(
                  'Inhalt',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    hintText: 'Details...',
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),

                if (_showDueDateField) ...[
                  Text(
                    'Fällig am',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDatePicker(),
                  const SizedBox(height: 20),
                ],

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Speichern',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: shouldUseBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: modalContainer,
            )
          : modalContainer,
    );
  }

  Widget _buildTypeSelector() {
    return Wrap(
      spacing: 8,
      children: [
        _TypeChip(
          label: 'Notiz',
          icon: Icons.note_outlined,
          isSelected: _selectedType == 'note',
          onTap: () => setState(() => _selectedType = 'note'),
        ),
        _TypeChip(
          label: 'Hausaufgabe',
          icon: Icons.assignment_outlined,
          isSelected: _selectedType == 'homework',
          onTap: () => setState(() => _selectedType = 'homework'),
        ),
        _TypeChip(
          label: 'Aufgabe',
          icon: Icons.task_alt_outlined,
          isSelected: _selectedType == 'task',
          onTap: () => setState(() => _selectedType = 'task'),
        ),
        _TypeChip(
          label: 'Idee',
          icon: Icons.lightbulb_outline,
          isSelected: _selectedType == 'idea',
          onTap: () => setState(() => _selectedType = 'idea'),
        ),
      ],
    );
  }

  Widget _buildSubjectDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonFormField<int>(
        initialValue: _selectedSubjectId,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        hint: const Text('Fach wählen...'),
        items: _subjects.map((subject) {
          return DropdownMenuItem<int>(
            value: subject['id'] as int,
            child: Text(subject['name'] as String),
          );
        }).toList(),
        onChanged: (value) => setState(() => _selectedSubjectId = value),
      ),
    );
  }

  Widget _buildDatePicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _selectDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 20,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
            const SizedBox(width: 12),
            Text(
              _dueDate != null
                  ? '${_dueDate!.day}.${_dueDate!.month}.${_dueDate!.year}'
                  : 'Datum wählen...',
              style: TextStyle(
                color: _dueDate != null
                    ? null
                    : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
              ),
            ),
            const Spacer(),
            if (_dueDate != null)
              GestureDetector(
                onTap: () => setState(() => _dueDate = null),
                child: Icon(
                  Icons.clear,
                  size: 20,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _dueDate = date);
    }
  }

  String _getTitleHint() {
    switch (_selectedType) {
      case 'note':
        return 'Was möchtest du notieren?';
      case 'homework':
        return 'Welche Hausaufgabe?';
      case 'task':
        return 'Was muss erledigt werden?';
      case 'idea':
        return 'Was ist deine Idee?';
      default:
        return 'Titel eingeben...';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final provider = context.read<AppProvider>();
    final notesProvider = context.read<NotesProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final title = _titleController.text.trim();
      final content = _contentController.text.trim();

      switch (_selectedType) {
        case 'task':
          await provider.addTask(
            title: title,
            description: content.isNotEmpty ? content : null,
            dueDate: _dueDate,
          );
          break;
        case 'homework':
          if (_selectedSubjectId == null) {
            messenger.showSnackBar(
              SnackBar(
                content: const Text('Bitte wähle ein Fach aus'),
                backgroundColor: AppTheme.danger,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
            setState(() => _isLoading = false);
            return;
          }
          await provider.addHomework(
            title: title,
            subjectId: _selectedSubjectId,
            notes: content.isNotEmpty ? content : null,
            dueDate: _dueDate,
          );
          break;
        case 'note':
        case 'idea':
        default:
          await provider.addQuickNote(
            type: _selectedType,
            title: title,
            content: content.isNotEmpty ? content : null,
          );
          await notesProvider.loadNotes();
          break;
      }

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(_getSuccessMessage()),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Fehler beim Speichern. Bitte versuche es erneut.'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getSuccessMessage() {
    switch (_selectedType) {
      case 'task':
        return 'Aufgabe erstellt';
      case 'homework':
        return 'Hausaufgabe gespeichert';
      case 'idea':
        return 'Idee gespeichert';
      default:
        return 'Notiz gespeichert';
    }
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final chipContainer = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primaryColor.withValues(alpha: isDark ? 0.25 : 0.2)
            : (isDark
                ? Colors.white.withValues(alpha: shouldUseBlur ? 0.08 : 0.14)
                : Colors.white.withValues(alpha: shouldUseBlur ? 0.5 : 0.7)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.5)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected
                ? AppTheme.primaryColor
                : (isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? AppTheme.primaryColor
                  : (isDark ? Colors.white70 : Colors.black54),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: shouldUseBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: chipContainer,
              )
            : chipContainer,
      ),
    );
  }
}
