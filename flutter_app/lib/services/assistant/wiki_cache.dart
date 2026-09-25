// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../brand.dart';

/// Wikipedia REST lookup + on-device disk cache. Fetches once online, then
/// answers repeat queries fully offline for 30 days.
class WikiCacheService {
  WikiCacheService._();
  static final WikiCacheService instance = WikiCacheService._();

  static const _userAgent = '${Brand.name}Assistant/1.0 (${Brand.repository})';
  static const _timeout = Duration(seconds: 6);
  static const _ttl = Duration(days: 30);
  static const _maxEntries = 200;
  static const _prefsKey = 'wiki.cache.v1';

  Future<Map<String, dynamic>> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCache(Map<String, dynamic> cache) async {
    if (cache.length > _maxEntries) {
      final entries = cache.entries.toList()
        ..sort((a, b) {
          final ta = ((a.value as Map)['ts'] ?? 0) as int;
          final tb = ((b.value as Map)['ts'] ?? 0) as int;
          return tb.compareTo(ta);
        });
      cache = Map.fromEntries(entries.take(_maxEntries));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(cache));
  }

  Future<Map<String, dynamic>?> _get(String key) async {
    final cache = await _loadCache();
    final entry = cache[key];
    if (entry == null) return null;
    final ts = (entry['ts'] ?? 0) as int;
    if (DateTime.now().millisecondsSinceEpoch - ts > _ttl.inMilliseconds) return null;
    return (entry['data'] as Map).cast<String, dynamic>();
  }

  Future<void> _put(String key, Map<String, dynamic> data) async {
    final cache = await _loadCache();
    cache[key] = {'ts': DateTime.now().millisecondsSinceEpoch, 'data': data};
    await _saveCache(cache);
  }

  Future<String?> _fetchExtendedExtract(String title, String lang) async {
    try {
      final r = await http
          .get(
            Uri.https('$lang.wikipedia.org', '/w/api.php', {
              'action': 'query',
              'format': 'json',
              'prop': 'extracts',
              'titles': title,
              'explaintext': '1',
              'redirects': '1',
            }),
            headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
          )
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final pages = (data['query']?['pages'] as Map?)?.cast<String, dynamic>();
      if (pages == null) return null;
      for (final page in pages.values) {
        final ext = (page['extract'] as String?)?.trim() ?? '';
        if (ext.isEmpty) continue;
        if (ext.length <= 4500) return ext;
        var snippet = ext.substring(0, 4500);
        final lastBoundary = [snippet.lastIndexOf('. '), snippet.lastIndexOf('! '),
            snippet.lastIndexOf('? '), snippet.lastIndexOf('\n')].reduce((a, b) => a > b ? a : b);
        if (lastBoundary > 4500 * 0.6) snippet = snippet.substring(0, lastBoundary + 1);
        return '${snippet.trimRight()} […]';
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> lookup(String entity, {String lang = 'de'}) async {
    if (entity.trim().isEmpty) return null;
    final cacheKey = '$lang:${entity.trim().toLowerCase()}';

    final cached = await _get(cacheKey);
    if (cached != null) return cached;

    for (final tryLang in (lang == 'en' ? ['en'] : [lang, 'en'])) {
      try {
        final r = await http
            .get(
              Uri.https('$tryLang.wikipedia.org', '/api/rest_v1/page/summary/${Uri.encodeComponent(entity)}'),
              headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
            )
            .timeout(_timeout);
        if (r.statusCode == 404) continue;
        if (r.statusCode != 200) continue;
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (data['type'] == 'disambiguation') {
          final result = {
            'title': data['title'] ?? entity,
            'extract': data['extract'] ?? 'Mehrdeutig – mehrere Bedeutungen.',
            'url': (data['content_urls']?['desktop']?['page']) ?? '',
            'disambiguation': true,
            'lang': tryLang,
          };
          await _put(cacheKey, result);
          return result;
        }
        final lead = ((data['extract'] as String?) ?? '').trim();
        if (lead.isEmpty) continue;
        final title = (data['title'] ?? entity) as String;
        final extended = await _fetchExtendedExtract(title, tryLang);
        final full = (extended != null && extended.length > lead.length) ? extended : lead;
        final result = {
          'title': title,
          'extract': full,
          'url': (data['content_urls']?['desktop']?['page']) ?? '',
          'disambiguation': false,
          'lang': tryLang,
        };
        await _put(cacheKey, result);
        return result;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Quick cache-only lookup — never touches the network.
  Future<Map<String, dynamic>?> cachedOnly(String entity, {String lang = 'de'}) async {
    return _get('$lang:${entity.trim().toLowerCase()}');
  }
}

class ResearchService {
  ResearchService._();
  static final ResearchService instance = ResearchService._();

  static final _mathHints = RegExp(
    r'[+\-*/=^]|\\frac|\\sqrt|\\int|\blöse\b|\bberechne\b|\bableiten?\b|\bintegriere\b',
    caseSensitive: false,
  );
  static final _factPatterns = [
    RegExp(r'\b(?:wer|was)\s+(?:ist|war|sind|waren)\b', caseSensitive: false),
    RegExp(r'\b(?:was|wer)\s+hat\s+\S+\s+(?:gemacht|getan|erfunden|geschrieben|komponiert|entwickelt|entdeckt|gegründet)\b', caseSensitive: false),
    RegExp(r'\b(?:info(?:s|rmationen)?|biograf(?:ie|ien)|lebenslauf)\s+(?:zu|über|von|about)\b', caseSensitive: false),
    RegExp(r'\berkläre?\s+mir\b.*\b(?:person|autor|künstler|wissenschaftler|mathematiker|schriftsteller|politiker|begriff)\b', caseSensitive: false),
    RegExp(r'\b(?:gib|zeig|bring|sag)\s+mir\b.*\b(?:info|biografie|fakten|daten)\b', caseSensitive: false),
    RegExp(r'\bwann\s+(?:lebte|starb|wurde\s+geboren|fand\s+statt)\b', caseSensitive: false),
    RegExp(r'\bschreibe?\s+(?:mir\s+)?(?:eine?\s+)?(?:biografie|lebenslauf)\b', caseSensitive: false),
  ];

  bool wantsResearch(String message) {
    if (message.isEmpty || message.length > 400) return false;
    if (_mathHints.hasMatch(message)) return false;
    return _factPatterns.any((p) => p.hasMatch(message));
  }

  String? extractEntity(String message) {
    if (message.isEmpty) return null;
    var m = message.trim();
    m = m.replaceFirst(RegExp(r'^\s*(?:bitte\s+)?', caseSensitive: false), '');

    const patterns = [
      r'(?:info(?:s|rmationen)?|biograf(?:ie|ien)|lebenslauf|fakten|daten)\s+(?:zu|über|von|about)\s+([^?!\n]+?)(?:\s*[?!]|$)',
      r'(?:wer|was)\s+(?:ist|war|sind|waren)\s+([^?!\n]+?)(?:\s*[?!]|$)',
      r'(?:was|wer)\s+hat\s+([^?!\n]+?)\s+(?:gemacht|getan|erfunden|geschrieben|komponiert|entwickelt|entdeckt|gegründet)\b',
      r'erkläre?\s+mir\s+([^?!\n]+?)(?:\s*[?!]|$)',
      r'schreibe?\s+(?:mir\s+)?(?:eine?\s+)?(?:biografie|lebenslauf)\s+(?:zu|über|von)\s+([^?!\n]+?)(?:\s*[?!]|$)',
    ];
    for (final pat in patterns) {
      final match = RegExp(pat, caseSensitive: false).firstMatch(m);
      if (match != null) {
        final cleaned = _cleanEntity(match.group(1) ?? '');
        if (cleaned != null) return cleaned;
      }
    }
    return null;
  }

  static const _descriptors =
      'person|persönlichkeit|figur|autor(?:in)?|schriftsteller(?:in)?|dichter(?:in)?|'
      'philosoph(?:in)?|wissenschaftler(?:in)?|mathematiker(?:in)?|physiker(?:in)?|'
      'politiker(?:in)?|künstler(?:in)?|maler(?:in)?|komponist(?:in)?|erfinder(?:in)?|'
      'unternehmer(?:in)?|firma|unternehmen|begriff|thema|ort|stadt|land|ereignis';
  static const _fillers = r'(?:bitte|mal|eigentlich|genau|noch|doch|auch)';

  String? _cleanEntity(String entity) {
    if (entity.isEmpty) return null;
    var e = entity.trim().replaceAll(RegExp(r'''^['",;: ]+|['",;: ]+$'''), '');
    e = e.replaceAll(RegExp(r'\s*\([^)]*\)?\s*$'), '').trim();
    e = e.replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ').trim();
    e = e.split(RegExp(r'\s+(?:und|oder|bzw\.?|sowie|aber|doch|denn|weil|damit|sodass|wenn|falls)\s+', caseSensitive: false))[0].trim();
    e = e.replaceAll(RegExp(r'\s+(?:im|in\s+der|in\s+dem|in\s+den|als|aus)\s+.+$', caseSensitive: false), '').trim();
    e = e.replaceAll(RegExp(r'\s+von\s+(?![A-ZÄÖÜ])\S.*$'), '').trim();
    e = e.replaceAll(RegExp(r',\s*(?:der|die|das|den|dem|ein|eine|einen|einem|einer)\b.*$', caseSensitive: false), '').trim();
    e = e.replaceAll(RegExp(r'\s+(?:der|die|das|welche[rsn]?)\s+(?:\S+\s+){0,6}?(?:ist|war|hat|macht|machte|schrieb|lebte|starb|erfand|gründete)\b.*$', caseSensitive: false), '').trim();
    for (var i = 0; i < 3; i++) {
      final n = e.replaceFirst(
        RegExp(r'^(?:der\s+|die\s+|das\s+|dem\s+|den\s+|einem\s+|einer\s+|eines\s+|ein\s+|eine\s+)?(?:[a-zäöüß]+e[rnms]?\s+){0,3}(?:' + _descriptors + r')\s+', caseSensitive: false),
        '',
      ).trim();
      if (n == e) break;
      e = n;
    }
    e = e.replaceFirst(RegExp(r'^(?:der|die|das|dem|den|ein|eine|einen|einem|einer|eines)\s+', caseSensitive: false), '').trim();
    e = e.replaceFirst(RegExp(r'\s+' + _fillers + r'\s*$', caseSensitive: false), '').trim();
    e = e.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (e.length < 2 || e.length > 120 || e.split(' ').length > 9) return null;
    return e;
  }

  String formatResult(Map<String, dynamic> result) {
    final buf = StringBuffer('**${result["title"]}**');
    if (result['disambiguation'] == true) buf.write(' *(Begriffsklärung)*');
    buf.writeln();
    buf.writeln();
    buf.writeln(result['extract']);
    final url = result['url'] as String? ?? '';
    if (url.isNotEmpty) {
      buf.writeln();
      buf.writeln('Quelle: $url');
    }
    return buf.toString().trimRight();
  }
}
