// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../services/database_service.dart';
import '../services/offline_ai_service.dart';

class AssistantProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final OfflineAIService _aiService = OfflineAIService();
  final Uuid _uuid = const Uuid();

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  static const List<Map<String, String>> quickActions = [
    {'label': '📐 Mathe lösen', 'prompt': 'Löse diese Gleichung: '},
    {'label': '📝 Aufsatz-Gliederung', 'prompt': 'Erstelle eine Gliederung zum Thema '},
    {'label': '📖 Text zusammenfassen', 'prompt': 'Wie fasse ich einen Text zusammen?'},
    {'label': '📅 Mein Stundenplan', 'prompt': 'Was habe ich heute?'},
  ];

  Future<void> loadHistory() async {
    _isLoading = true;
    notifyListeners();

    try {
      _messages = await _db.getChatMessages();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;
    if (_isProcessing) return;

    final userMessage = ChatMessage.user(
      id: _uuid.v4(),
      content: content.trim(),
    );
    _messages.add(userMessage);
    await _db.insertChatMessage(userMessage);

    _isProcessing = true;
    notifyListeners();

    try {

      final response = await _aiService.processQuery(content);

      final assistantMessage = ChatMessage.assistant(
        id: _uuid.v4(),
        content: response,
      );
      _messages.add(assistantMessage);
      await _db.insertChatMessage(assistantMessage);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    await _db.clearChatHistory();
    _messages.clear();
    notifyListeners();
  }

  String solveMath(String equation) {
    return _aiService.solveMath(equation);
  }

  String generateEssayOutline(String topic) {
    return _aiService.generateEssayOutline(topic);
  }

  String getSummarizeHelp() {
    return _aiService.getSummarizeHelp();
  }
}
