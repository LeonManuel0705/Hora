// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'curriculum.dart';
import 'offline_tools.dart' as tools;
import 'wiki_cache.dart';

enum AssistantSource { math, date, unit, formula, epoch, werk, topics, wikipedia, cached, unknown }

class AssistantResponse {
  const AssistantResponse({required this.text, required this.source, this.online = false});
  final String text;
  final AssistantSource source;
  final bool online;
}

class AssistantEngine {
  AssistantEngine._();
  static final AssistantEngine instance = AssistantEngine._();

  Future<void> initialize() async {
    await CurriculumService.instance.ensureLoaded();
  }

  /// Pure-offline answer path. Never touches the network.
  /// Returns [null] if nothing local matches.
  Future<AssistantResponse?> answerOffline(String message) async {
    await CurriculumService.instance.ensureLoaded();

    if (_isInjection(message)) {
      return const AssistantResponse(
        text: 'Ich konnte deine Frage gerade nicht beantworten – sie sah nicht wie eine natürliche Frage aus.',
        source: AssistantSource.unknown,
      );
    }

    final tool = tools.tryOfflineTool(message);
    if (tool != null) return AssistantResponse(text: tool, source: _toolSource(tool));

    final curr = CurriculumService.instance.tryCurriculum(message);
    if (curr != null) return AssistantResponse(text: curr, source: _currSource(curr));

    // Try cached Wikipedia hits without network.
    if (ResearchService.instance.wantsResearch(message)) {
      final entity = ResearchService.instance.extractEntity(message);
      if (entity != null) {
        final cached = await WikiCacheService.instance.cachedOnly(entity);
        if (cached != null) {
          return AssistantResponse(
            text: ResearchService.instance.formatResult(cached),
            source: AssistantSource.cached,
          );
        }
      }
    }

    final greet = _tryGreeting(message);
    if (greet != null) return AssistantResponse(text: greet, source: AssistantSource.unknown);

    return null;
  }

  Future<AssistantResponse?> answerExact(String message) async {
    await CurriculumService.instance.ensureLoaded();

    if (_isInjection(message)) {
      return const AssistantResponse(
        text: 'Das sah nicht wie eine normale Frage aus. Formulier sie bitte noch einmal in eigenen Worten.',
        source: AssistantSource.unknown,
      );
    }

    final tool = tools.tryOfflineTool(message);
    if (tool != null) return AssistantResponse(text: tool, source: _toolSource(tool));

    if (_looksLikeTask(message)) return null;

    final curr = CurriculumService.instance.tryCurriculum(message);
    if (curr != null) return AssistantResponse(text: curr, source: _currSource(curr));

    if (ResearchService.instance.wantsResearch(message)) {
      final entity = ResearchService.instance.extractEntity(message);
      if (entity != null) {
        final cached = await WikiCacheService.instance.cachedOnly(entity);
        if (cached != null) {
          return AssistantResponse(
            text: ResearchService.instance.formatResult(cached),
            source: AssistantSource.cached,
          );
        }
      }
    }
    return null;
  }

  static final _task = RegExp(
    r'^\s*(?:bitte\s+|kannst\s+du\s+(?:mir\s+)?|könntest\s+du\s+(?:mir\s+)?)?'
    r'(?:schreib|verfass|formulier|erstell|mach|hilf|übersetz|uebersetz|fass|vergleich|entwirf|plan|überleg|ueberleg|gib\s+mir|wie\s+(?:lerne|schreibe|bereite|plane|fange))',
    caseSensitive: false,
  );

  bool _looksLikeTask(String message) => message.length > 160 || _task.hasMatch(message);

  /// Full answer path: offline first, then online Wikipedia fallback for entity
  /// queries if the device has network. Never calls an LLM.
  Future<AssistantResponse> answer(String message, {bool online = true}) async {
    final local = await answerOffline(message);
    if (local != null) return local;

    if (online && ResearchService.instance.wantsResearch(message)) {
      final entity = ResearchService.instance.extractEntity(message);
      if (entity != null) {
        final hit = await WikiCacheService.instance.lookup(entity);
        if (hit != null) {
          return AssistantResponse(
            text: ResearchService.instance.formatResult(hit),
            source: AssistantSource.wikipedia,
            online: true,
          );
        }
        return AssistantResponse(
          text: 'Ich konnte zu **"$entity"** keinen Wikipedia-Eintrag finden. '
              'Prüfe bitte die Schreibweise oder gib mehr Kontext.',
          source: AssistantSource.unknown,
        );
      }
    }

    return const AssistantResponse(
      text: 'Ich konnte deine Frage gerade nicht beantworten – ich habe dafür keine Offline-Vorlage '
          'und ohne Internet auch keinen anderen Weg. Versuch es bitte anders zu formulieren.',
      source: AssistantSource.unknown,
    );
  }

  bool _isInjection(String message) {
    final m = message.toLowerCase();
    if (RegExp(r'\b(?:drop|delete|update|select|insert|alter|truncate)\s+(?:table|from|into)\b').hasMatch(m)) return true;
    if (m.contains('<script')) return true;
    if (message.contains('__import__')) return true;
    if (m.contains('eval(') && m.contains('import')) return true;
    return false;
  }

  AssistantSource _toolSource(String result) {
    if (result.contains('°C') || result.contains('°F') || result.contains('Meilen') ||
        result.contains('Pfund') || result.contains('Gallonen') ||
        RegExp(r'\*\*[\d.,]+\s+(?:km|m|ft|Fuß|kg|lb|l)\*\*').hasMatch(result)) {
      return AssistantSource.unit;
    }
    if (result.startsWith('Heute ist') || result.startsWith('Morgen ist') ||
        result.startsWith('Es ist ') || result.startsWith('Der ') || result.startsWith('In ')) {
      return AssistantSource.date;
    }
    return AssistantSource.math;
  }

  AssistantSource _currSource(String result) {
    if (result.contains(r'$$')) return AssistantSource.formula;
    if (result.contains('**Merkmale:**') || result.contains('**Wichtige Autoren:**')) {
      return AssistantSource.epoch;
    }
    if (RegExp(r'^\*\*[^*]+\*\*\s+—\s+').hasMatch(result)) return AssistantSource.werk;
    if (result.startsWith('**Klasse ')) return AssistantSource.topics;
    return AssistantSource.unknown;
  }

  String? _tryGreeting(String message) {
    final m = message.toLowerCase().trim();
    final hasGreeting = RegExp(r'(?<!\w)(?:hallo|hi|hey|moin)(?!\w)|guten\s+(?:morgen|tag|abend)').hasMatch(m);
    if (!hasGreeting) return null;
    final h = DateTime.now().hour;
    final prefix = h < 12 ? 'Guten Morgen' : (h < 18 ? 'Guten Tag' : 'Guten Abend');
    return '$prefix! Wie kann ich dir bei Schul-Themen helfen?';
  }
}
