// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/quick_note.dart';
import '../services/database_service.dart';

class NotesProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final Uuid _uuid = const Uuid();

  List<QuickNote> _notes = [];
  List<QuickNote> get notes => _notes;

  String? _activeNoteId;
  String? get activeNoteId => _activeNoteId;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  QuickNote? get activeNote {
    if (_activeNoteId == null) return null;
    if (_notes.isEmpty) return null;
    return _notes.firstWhere(
      (n) => n.id == _activeNoteId,
      orElse: () => _notes.first,
    );
  }

  int get totalNotes => _notes.length;

  int get totalWordCount {
    return _notes.fold(0, (sum, note) => sum + note.wordCount);
  }

  Future<void> loadNotes() async {
    _isLoading = true;
    notifyListeners();

    try {
      _notes = await _db.getQuickNotes();

      if (_notes.isNotEmpty && _activeNoteId == null) {
        _activeNoteId = _notes.first.id;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setActiveNote(String id) {
    if (_activeNoteId != id) {
      _activeNoteId = id;
      _hasUnsavedChanges = false;
      notifyListeners();
    }
  }

  Future<QuickNote> createNote() async {
    final now = DateTime.now();
    final note = QuickNote(
      id: _uuid.v4(),
      content: '',
      wordCount: 0,
      createdAt: now,
      updatedAt: now,
    );

    await _db.insertQuickNote(note);
    _notes.insert(0, note);
    _activeNoteId = note.id;
    _hasUnsavedChanges = false;
    notifyListeners();

    return note;
  }

  Future<void> updateNoteContent(String id, String content) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final wordCount = QuickNote.calculateWordCount(content);
    final updated = _notes[index].copyWith(
      content: content,
      wordCount: wordCount,
      updatedAt: DateTime.now(),
    );

    await _db.updateQuickNote(updated);
    _notes[index] = updated;
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  void markUnsavedChanges() {
    if (!_hasUnsavedChanges) {
      _hasUnsavedChanges = true;
      notifyListeners();
    }
  }

  Future<void> deleteNote(String id) async {
    await _db.deleteQuickNote(id);
    _notes.removeWhere((n) => n.id == id);

    if (_activeNoteId == id) {
      _activeNoteId = _notes.isNotEmpty ? _notes.first.id : null;
    }
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  Future<void> deleteAllNotes() async {
    for (final note in _notes) {
      await _db.deleteQuickNote(note.id);
    }
    _notes.clear();
    _activeNoteId = null;
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  List<QuickNote> search(String query) {
    if (query.isEmpty) return _notes;
    final lowercaseQuery = query.toLowerCase();
    return _notes.where((n) =>
      n.content.toLowerCase().contains(lowercaseQuery)
    ).toList();
  }
}
