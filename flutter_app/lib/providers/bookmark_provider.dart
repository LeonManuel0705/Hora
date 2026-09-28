// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/bookmark.dart';
import '../services/database_service.dart';

class BookmarkProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final Uuid _uuid = const Uuid();

  List<Bookmark> _bookmarks = [];
  List<Bookmark> get bookmarks => _bookmarks;

  String _selectedCategory = 'All';
  String get selectedCategory => _selectedCategory;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Bookmark> get filteredBookmarks {
    if (_selectedCategory == 'All') {
      return _bookmarks;
    }
    return _bookmarks.where((b) => b.category == _selectedCategory).toList();
  }

  Map<String, List<Bookmark>> get bookmarksByCategory {
    final map = <String, List<Bookmark>>{};
    for (final bookmark in _bookmarks) {
      map.putIfAbsent(bookmark.category, () => []).add(bookmark);
    }
    return map;
  }

  int get totalCount => _bookmarks.length;

  Map<String, int> get countByCategory {
    final map = <String, int>{'All': _bookmarks.length};
    for (final category in Bookmark.categories) {
      map[category] = _bookmarks.where((b) => b.category == category).length;
    }
    return map;
  }

  Future<void> loadBookmarks() async {
    _isLoading = true;
    notifyListeners();

    try {
      _bookmarks = await _db.getBookmarks();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  Future<Bookmark> addBookmark({
    required String title,
    required String url,
    String category = 'Other',
    String? favicon,
  }) async {
    final now = DateTime.now();
    final bookmark = Bookmark(
      id: _uuid.v4(),
      title: title,
      url: url,
      category: category,
      favicon: favicon,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insertBookmark(bookmark);
    _bookmarks.insert(0, bookmark);
    notifyListeners();

    return bookmark;
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    final updated = bookmark.copyWith(updatedAt: DateTime.now());
    await _db.updateBookmark(updated);

    final index = _bookmarks.indexWhere((b) => b.id == bookmark.id);
    if (index != -1) {
      _bookmarks[index] = updated;
      notifyListeners();
    }
  }

  Future<void> deleteBookmark(String id) async {
    await _db.deleteBookmark(id);
    _bookmarks.removeWhere((b) => b.id == id);
    notifyListeners();
  }

  List<Bookmark> search(String query) {
    if (query.isEmpty) return filteredBookmarks;
    final lowercaseQuery = query.toLowerCase();
    return filteredBookmarks.where((b) =>
      b.title.toLowerCase().contains(lowercaseQuery) ||
      b.url.toLowerCase().contains(lowercaseQuery)
    ).toList();
  }
}
