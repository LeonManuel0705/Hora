// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/page_fade_in.dart';
import '../services/database_service.dart'
    if (dart.library.html) '../services/database_service_web.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  final DatabaseService _db = DatabaseService();
  List<KnowledgeEntry> _entries = [];
  bool _isLoading = true;

  String _searchQuery = '';
  String? _selectedCategory;

  List<String> get _categories => _entries.map((e) => e.category).toSet().toList();

  List<KnowledgeEntry> get _filteredEntries {
    return _entries.where((entry) {
      final matchesSearch = entry.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          entry.content.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          entry.tags.any((tag) => tag.toLowerCase().contains(_searchQuery.toLowerCase()));
      final matchesCategory = _selectedCategory == null || entry.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final rows = await _db.getKnowledgeEntries();
      if (!mounted) return;
      setState(() {
        _entries = rows.map(KnowledgeEntry.fromMap).toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addEntry(KnowledgeEntry entry) async {
    await _db.insertKnowledgeEntry(entry.toMap());
    if (!mounted) return;
    setState(() => _entries.insert(0, entry));
  }

  Future<void> _updateEntry(KnowledgeEntry updated) async {
    await _db.updateKnowledgeEntry(updated.id, updated.toMap());
    if (!mounted) return;
    setState(() {
      final index = _entries.indexWhere((e) => e.id == updated.id);
      if (index != -1) _entries[index] = updated;
    });
  }

  Future<void> _deleteEntry(KnowledgeEntry entry) async {
    await _db.deleteKnowledgeEntry(entry.id);
    if (!mounted) return;
    setState(() => _entries.remove(entry));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageFadeIn(
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
            _buildHeader(context, isDark),
            const SizedBox(height: 20),

            GlassCard(
              borderRadius: 16,
              padding: EdgeInsets.zero,
              hasShadow: false,
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Suchen...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCategoryChip(null, 'Alle', isDark),
                  ..._categories.map((cat) => _buildCategoryChip(cat, cat, isDark)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: _buildStatCard(
                  context,
                  isDark: isDark,
                  icon: Icons.article,
                  value: '${_entries.length}',
                  label: 'Einträge',
                  color: AppTheme.knowledgeColor,
                )),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard(
                  context,
                  isDark: isDark,
                  icon: Icons.category,
                  value: '${_categories.length}',
                  label: 'Kategorien',
                  color: AppTheme.projectsColor,
                )),
              ],
            ),

            const SizedBox(height: 24),

            _buildSectionHeader(
              context,
              isDark: isDark,
              title: 'Einträge',
              icon: Icons.article,
              iconColor: AppTheme.knowledgeColor,
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ))
            else if (_filteredEntries.isEmpty)
              _buildEmptyState(context, isDark)
            else
              ..._filteredEntries.asMap().entries.map((e) => AnimatedListItem(
                index: e.key,
                child: _buildEntryCard(context, e.value, isDark),
              )),

            const SizedBox(height: 120),
          ],
        ),

          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: FloatingActionButton(
              heroTag: 'fab_knowledge',
              onPressed: () => _showAddEntryDialog(context),
              backgroundColor: AppTheme.knowledgeColor,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return AppTheme.gradientText('Wissen', fontSize: 36);
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required bool isDark,
    required String title,
    required IconData icon,
    required Color iconColor,
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
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 48,
            color: isDark ? Colors.white38 : Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            'Keine Einträge',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tippe auf + um einen Eintrag zu erstellen',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String? category, String label, bool isDark) {
    final isSelected = _selectedCategory == category;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF7353CD)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : const Color(0xFF71717A),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
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
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
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

  Widget _buildEntryCard(BuildContext context, KnowledgeEntry entry, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(16),
        onTap: () => _showEntryDetails(context, entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.knowledgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.article, color: AppTheme.knowledgeColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        entry.category,
                        style: const TextStyle(
                          color: AppTheme.knowledgeColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              entry.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: entry.tags.map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.knowledgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      color: AppTheme.knowledgeColor,
                      fontSize: 12,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showEntryDetails(BuildContext context, KnowledgeEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.knowledgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.article, color: AppTheme.knowledgeColor, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.knowledgeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                entry.category,
                                style: const TextStyle(
                                  color: AppTheme.knowledgeColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Erstellt am ${_formatDate(entry.createdAt)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.content,
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white70 : Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: entry.tags.map((tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.knowledgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '#$tag',
                              style: const TextStyle(
                                color: AppTheme.knowledgeColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditEntryDialog(context, entry);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Bearbeiten'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteEntry(entry);
                      },
                      icon: const Icon(Icons.delete, color: AppTheme.danger),
                      label: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
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

  void _showAddEntryDialog(BuildContext context) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final categoryController = TextEditingController();
    final tagsController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.knowledgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_circle, color: AppTheme.knowledgeColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Neuer Eintrag',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: titleController,
                label: 'Titel',
                hint: 'z.B. Flutter Widgets',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: categoryController,
                label: 'Kategorie',
                hint: 'z.B. Programmierung',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: contentController,
                label: 'Inhalt',
                hint: 'Schreibe hier deinen Eintrag...',
                isDark: isDark,
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: tagsController,
                label: 'Tags (kommagetrennt)',
                hint: 'z.B. Flutter, Dart, Mobile',
                isDark: isDark,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty) {
                      final now = DateTime.now();
                      final entry = KnowledgeEntry(
                        id: now.toIso8601String(),
                        title: titleController.text,
                        content: contentController.text,
                        category: categoryController.text.isEmpty
                            ? 'Allgemein'
                            : categoryController.text,
                        createdAt: now,
                        updatedAt: now,
                        tags: tagsController.text
                            .split(',')
                            .map((t) => t.trim())
                            .where((t) => t.isNotEmpty)
                            .toList(),
                      );
                      Navigator.pop(context);
                      _addEntry(entry);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.knowledgeColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Speichern'),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) => Future.delayed(const Duration(milliseconds: 300), () {
      titleController.dispose();
      contentController.dispose();
      categoryController.dispose();
      tagsController.dispose();
    }));
  }

  void _showEditEntryDialog(BuildContext context, KnowledgeEntry entry) {
    final titleController = TextEditingController(text: entry.title);
    final contentController = TextEditingController(text: entry.content);
    final categoryController = TextEditingController(text: entry.category);
    final tagsController = TextEditingController(text: entry.tags.join(', '));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.knowledgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit, color: AppTheme.knowledgeColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Eintrag bearbeiten',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: titleController,
                label: 'Titel',
                hint: 'z.B. Flutter Widgets',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: categoryController,
                label: 'Kategorie',
                hint: 'z.B. Programmierung',
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: contentController,
                label: 'Inhalt',
                hint: 'Schreibe hier deinen Eintrag...',
                isDark: isDark,
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: tagsController,
                label: 'Tags (kommagetrennt)',
                hint: 'z.B. Flutter, Dart, Mobile',
                isDark: isDark,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty) {
                      final updated = KnowledgeEntry(
                        id: entry.id,
                        title: titleController.text,
                        content: contentController.text,
                        category: categoryController.text.isEmpty
                            ? 'Allgemein'
                            : categoryController.text,
                        createdAt: entry.createdAt,
                        updatedAt: DateTime.now(),
                        tags: tagsController.text
                            .split(',')
                            .map((t) => t.trim())
                            .where((t) => t.isNotEmpty)
                            .toList(),
                      );
                      Navigator.pop(context);
                      _updateEntry(updated);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.knowledgeColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Speichern'),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) => Future.delayed(const Duration(milliseconds: 300), () {
      titleController.dispose();
      contentController.dispose();
      categoryController.dispose();
      tagsController.dispose();
    }));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isDark,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }
}

class KnowledgeEntry {
  final String id;
  final String title;
  final String content;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;

  KnowledgeEntry({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'topic': category,
      'tags': tags.join(','),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static KnowledgeEntry fromMap(Map<String, dynamic> map) {
    final tagsRaw = (map['tags'] as String?) ?? '';
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

    return KnowledgeEntry(
      id: map['id'] as String,
      title: map['title'] as String,
      content: (map['content'] as String?) ?? '',
      category: (map['topic'] as String?) ?? 'Allgemein',
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ?? DateTime.now(),
      tags: tags,
    );
  }
}
