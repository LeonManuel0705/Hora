// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/bookmark_provider.dart';
import '../models/bookmark.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/page_fade_in.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookmarkProvider>().loadBookmarks();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddBookmarkDialog() {
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    String selectedCategory = 'Other';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          title: const Text('Lesezeichen hinzufügen'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titel',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Kategorie',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  dropdownColor: isDark ? AppTheme.darkSurface : Colors.white,
                  items: Bookmark.categories.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedCategory = value);
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
                if (titleController.text.isNotEmpty && urlController.text.isNotEmpty) {
                  String url = urlController.text.trim();
                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://$url';
                  }
                  final parsed = Uri.tryParse(url);
                  if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority ||
                      (parsed.scheme != 'http' && parsed.scheme != 'https')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bitte eine gültige URL eingeben'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  context.read<BookmarkProvider>().addBookmark(
                    title: titleController.text.trim(),
                    url: url,
                    category: selectedCategory,
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        );
        },
      ),
    ).then((_) {
      titleController.dispose();
      urlController.dispose();
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PageFadeIn(
      child: Stack(
        children: [
          Consumer<BookmarkProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final categoryFiltered = provider.filteredBookmarks;
              final bookmarks = _searchQuery.isEmpty
                  ? categoryFiltered
                  : categoryFiltered.where((b) =>
                      b.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      b.url.toLowerCase().contains(_searchQuery.toLowerCase())
                    ).toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppTheme.gradientText('Lesezeichen', fontSize: 36),
                  const SizedBox(height: 20),

                  GlassCard(
                    borderRadius: 16,
                    padding: EdgeInsets.zero,
                    hasShadow: false,
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Lesezeichen suchen...',
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
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _CategoryChip(
                          label: 'Alle',
                          count: provider.countByCategory['All'] ?? 0,
                          isSelected: provider.selectedCategory == 'All',
                          onTap: () => provider.setCategory('All'),
                        ),
                        const SizedBox(width: 8),
                        ...Bookmark.categories.map((category) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _CategoryChip(
                            label: _getCategoryLabel(category),
                            count: provider.countByCategory[category] ?? 0,
                            isSelected: provider.selectedCategory == category,
                            onTap: () => provider.setCategory(category),
                            color: _getCategoryColor(category),
                          ),
                        )),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: bookmarks.isEmpty
                        ? GlassCard(
                            key: ValueKey('empty_${provider.selectedCategory}_$_searchQuery'),
                            borderRadius: 16,
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.bookmark_border,
                                  size: 64,
                                  color: isDark ? Colors.white38 : Colors.black26,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Keine Ergebnisse'
                                      : 'Keine Lesezeichen',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            key: ValueKey('content_${provider.selectedCategory}_$_searchQuery'),
                            children: bookmarks.asMap().entries.map((e) => AnimatedListItem(
                              index: e.key,
                              child: _BookmarkCard(
                                bookmark: e.value,
                                onTap: () => _launchUrl(e.value.url),
                                onDelete: () => provider.deleteBookmark(e.value.id),
                              ),
                            )).toList(),
                          ),
                  ),

                  const SizedBox(height: 120),
                ],
              );
            },
          ),

          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: PageFadeIn(
              delay: const Duration(milliseconds: 300),
              child: FloatingActionButton(
                heroTag: 'fab_bookmarks',
                onPressed: _showAddBookmarkDialog,
                backgroundColor: AppTheme.primary,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'Work': return 'Arbeit';
      case 'Personal': return 'Persönlich';
      case 'Dev': return 'Entwicklung';
      case 'Other': return 'Sonstiges';
      default: return category;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Work': return AppTheme.blue;
      case 'Personal': return AppTheme.green;
      case 'Dev': return AppTheme.purple;
      case 'Other': return AppTheme.gray;
      default: return AppTheme.primary;
    }
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7353CD)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : const Color(0xFF71717A),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.7)
                    : const Color(0xFF71717A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookmarkCard({
    required this.bookmark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: Key(bookmark.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Löschen bestätigen'),
            content: const Text('Möchtest du dieses Lesezeichen wirklich löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Löschen'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.all(16),
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    bookmark.title.isNotEmpty
                        ? bookmark.title[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
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
                      bookmark.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        bookmark.domain,
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 20,
                color: isDark ? Colors.white54 : Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
