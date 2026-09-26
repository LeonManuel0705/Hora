// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notes_provider.dart';
import '../theme.dart';
import '../widgets/page_fade_in.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_list_item.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final TextEditingController _textController = TextEditingController();
  Timer? _autoSaveTimer;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<NotesProvider>().loadNotes();
      if (!mounted) return;
      _initializeTextController();
    });
  }

  void _initializeTextController() {
    if (_isInitialized) return;
    final provider = context.read<NotesProvider>();
    final activeNote = provider.activeNote;
    if (activeNote != null) {
      _textController.text = activeNote.content;
    }
    _isInitialized = true;
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    final provider = context.read<NotesProvider>();
    provider.markUnsavedChanges();

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      if (provider.activeNoteId != null) {
        provider.updateNoteContent(provider.activeNoteId!, text);
      }
    });
  }

  void _createNewNote() async {
    final provider = context.read<NotesProvider>();
    await provider.createNote();
    _textController.clear();
  }

  void _switchNote(String noteId) {
    final provider = context.read<NotesProvider>();

    if (provider.activeNoteId != null && provider.hasUnsavedChanges) {
      provider.updateNoteContent(provider.activeNoteId!, _textController.text);
    }

    provider.setActiveNote(noteId);
    final note = provider.notes.firstWhere((n) => n.id == noteId);
    _textController.text = note.content;
  }

  void _deleteCurrentNote() {
    final provider = context.read<NotesProvider>();
    if (provider.activeNoteId == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppPalette.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.ring,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                'Notiz löschen?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Diese Notiz wird dauerhaft gelöscht.',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await provider.deleteNote(provider.activeNoteId!);
                        _textController.text = provider.activeNote?.content ?? '';
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Löschen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<NotesProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return PageFadeIn(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(context, isDark, provider),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(child: _buildStatCard(
                      context,
                      isDark: isDark,
                      icon: Icons.note,
                      value: '${provider.totalNotes}',
                      label: 'Notizen',
                      color: AppTheme.notesColor,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard(
                      context,
                      isDark: isDark,
                      icon: Icons.text_fields,
                      value: '${provider.activeNote?.wordCount ?? 0}',
                      label: 'Wörter',
                      color: AppTheme.primary,
                    )),
                  ],
                ),

                const SizedBox(height: 20),

                _buildSectionHeader(
                  context,
                  isDark: isDark,
                  title: 'Deine Notizen',
                  icon: Icons.folder_outlined,
                  iconColor: AppTheme.notesColor,
                ),
                const SizedBox(height: 12),

                _buildNoteTabs(context, isDark, provider),

                const SizedBox(height: 20),

                _buildSectionHeader(
                  context,
                  isDark: isDark,
                  title: 'Editor',
                  icon: Icons.edit_note,
                  iconColor: AppTheme.primary,
                  trailing: provider.hasUnsavedChanges
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 8, color: AppTheme.warning),
                              SizedBox(width: 4),
                              Text(
                                'Speichert...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.warning,
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),

                _buildEditor(context, isDark, provider),

                const SizedBox(height: 120),
              ],
            ),

              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                child: FloatingActionButton(
                  heroTag: 'fab_notes',
                  onPressed: _createNewNote,
                  backgroundColor: AppTheme.notesColor,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, NotesProvider provider) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      enableTapScale: false,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.notesColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.sticky_note_2, color: AppTheme.notesColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTheme.gradientText('Notizen', fontSize: 36),
                Text(
                  'Gedanken festhalten',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          if (provider.activeNoteId != null)
            IconButton(
              onPressed: _deleteCurrentNote,
              icon: Icon(
                Icons.delete_outline,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required bool isDark,
    required String title,
    required IconData icon,
    required Color iconColor,
    Widget? trailing,
  }) {
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
        Text(
          title,
          style: AppTheme.sectionLabel(isDark),
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing,
        ],
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      enableTapScale: false,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteTabs(BuildContext context, bool isDark, NotesProvider provider) {
    if (provider.notes.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(32),
        borderRadius: 16,
        enableTapScale: false,
        child: Column(
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 48,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              'Keine Notizen',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tippe auf + um eine Notiz zu erstellen',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: provider.notes.length,
        itemBuilder: (context, index) {
          final note = provider.notes[index];
          final isActive = note.id == provider.activeNoteId;
          return AnimatedListItem(
            index: index,
            child: Padding(
              padding: EdgeInsets.only(right: index < provider.notes.length - 1 ? 10 : 0),
              child: GestureDetector(
                onTap: () => _switchNote(note.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.notesColor
                        : (isDark ? AppPalette.surfaceDark : AppPalette.surface),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(
                        color: isActive
                            ? AppPalette.iris
                            : Colors.transparent,
                        width: isActive ? 3 : 0,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    children: [
                      Icon(
                        Icons.description,
                        size: 16,
                        color: isActive
                            ? Colors.white
                            : (isDark ? Colors.white54 : Colors.black45),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (note.preview.isEmpty
                                ? 'Notiz ${index + 1}'
                                : note.preview)
                            .length > 12
                            ? '${(note.preview.isEmpty ? 'Notiz ${index + 1}' : note.preview).substring(0, 12)}...'
                            : (note.preview.isEmpty ? 'Notiz ${index + 1}' : note.preview),
                        style: TextStyle(
                          fontSize: 13,
                          color: isActive
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditor(BuildContext context, bool isDark, NotesProvider provider) {
    return GlassCard(
      padding: EdgeInsets.zero,
      borderRadius: 16,
      enableTapScale: false,
      child: Column(
        children: [
          Container(
            height: MediaQuery.of(context).size.height >= 768
                ? MediaQuery.of(context).size.height * 0.5
                : 300,
            padding: const EdgeInsets.all(16),
            child: provider.notes.isEmpty
                ? Center(
                    child: Text(
                      'Erstelle eine Notiz um zu beginnen',
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  )
                : TextField(
                    controller: _textController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Schreibe etwas...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      border: InputBorder.none,
                      filled: true,
                      fillColor: isDark
                          ? AppPalette.lineDark.withValues(alpha: 0.3)
                          : AppPalette.sunken.withValues(alpha: 0.3),
                    ),
                    onChanged: _onTextChanged,
                  ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.20),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                const SizedBox(width: 6),
                Text(
                  'Automatisches Speichern',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.notesColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${provider.activeNote?.wordCount ?? 0} Wörter',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.notesColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
