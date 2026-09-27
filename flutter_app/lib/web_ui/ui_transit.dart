// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../brand.dart';

class _TransitFailure implements Exception {
  const _TransitFailure(this.message, this.status);

  final String message;
  final int status;
}

class UiTransit {
  UiTransit._();

  static final UiTransit instance = UiTransit._();
  static const _base = 'api.transitous.org';
  static const _maxCache = 400;
  static const _categories = {
    'HIGHSPEED_RAIL': 'fern',
    'LONG_DISTANCE': 'fern',
    'NIGHT_RAIL': 'fern',
    'COACH': 'fernbus',
    'REGIONAL_FAST_RAIL': 'regio',
    'REGIONAL_RAIL': 'regio',
    'RAIL': 'regio',
    'SUBURBAN': 'sbahn',
    'METRO': 'sbahn',
    'SUBWAY': 'ubahn',
    'TRAM': 'tram',
    'BUS': 'bus',
    'FERRY': 'faehre',
    'WALK': 'fuss',
    'BIKE': 'rad',
  };
  static const _longDistance = {'fern', 'fernbus'};

  final Map<String, (DateTime, Object?)> _cache = {};

  String? _arg(Map<String, String> args, String key, [int limit = 120]) {
    final value = args[key];
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.length > limit ? trimmed.substring(0, limit) : trimmed;
  }

  Future<Object?> _fetch(String path, Map<String, Object?> params, int ttl) async {
    final query = <String, String>{
      for (final entry in params.entries)
        if (entry.value != null && '${entry.value}'.isNotEmpty) entry.key: '${entry.value}',
    };
    final uri = Uri.https(_base, '/api/v1/$path', query);
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1).inSeconds < ttl) return hit.$2;
    final response = await http.get(uri, headers: {
      'User-Agent': '${Brand.name}/0.4 (Schul-App)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw _TransitFailure('Fahrplan antwortet mit ${response.statusCode}', 502);
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    _cache[key] = (DateTime.now(), data);
    if (_cache.length > _maxCache) {
      final oldest = _cache.entries.toList()..sort((a, b) => a.value.$1.compareTo(b.value.$1));
      for (final entry in oldest.take(100)) {
        _cache.remove(entry.key);
      }
    }
    return data;
  }

  static String _category(Object? mode) => _categories['${mode ?? ''}'] ?? 'sonst';

  static Map<String, Object?> _map(Object? value) => value is Map ? value.cast<String, Object?>() : const {};

  static List<Object?> _list(Object? value) => value is List ? value : const [];

  static String _lineName(Map<String, Object?> item) {
    var name = '${item['routeShortName'] ?? item['displayName'] ?? ''}'.trim();
    if (name.contains('(') && name.endsWith(')')) name = name.substring(0, name.lastIndexOf('(')).trim();
    return name;
  }

  static String _areaOf(Map<String, Object?> item) {
    final areas = _list(item['areas']).map(_map).toList();
    final preferred = areas.where((area) => area['default'] == true).firstOrNull ??
        areas.where((area) => area['matched'] == true).firstOrNull;
    return '${preferred?['name'] ?? ''}';
  }

  Future<(Map<String, Object?>, int)> _search(Map<String, String> args) async {
    final query = _arg(args, 'q', 80) ?? '';
    if (query.length < 2) return (<String, Object?>{'places': <Object?>[]}, 200);
    final near = _arg(args, 'nahe', 60);
    final bias = _arg(args, 'bias', 4) ?? (near != null && near.isNotEmpty ? '5' : null);
    final data = await _fetch('geocode', {'text': query, 'language': 'de', 'place': near, 'placeBias': bias}, 3600);
    final places = <Map<String, Object?>>[];
    for (final raw in _list(data)) {
      final item = _map(raw);
      final kind = {'STOP': 'stop', 'ADDRESS': 'address'}[item['type']] ?? 'place';
      if (item['country'] != null && item['country'] != 'DE' && kind != 'stop') continue;
      places.add({
        'id': kind == 'stop' ? item['id'] : '${item['lat']},${item['lon']}',
        'name': item['name'] ?? '',
        'area': _areaOf(item),
        'kind': kind,
        'modes': ({for (final mode in _list(item['modes'])) _category(mode)}.toList()..sort()),
        'lat': item['lat'],
        'lon': item['lon'],
      });
    }
    return (<String, Object?>{'places': places.take(8).toList()}, 200);
  }

  Future<(Map<String, Object?>, int)> _departures(Map<String, String> args) async {
    final stop = _arg(args, 'stop');
    if (stop == null || stop.isEmpty) return (<String, Object?>{'error': 'Haltestelle fehlt'}, 400);
    final count = (int.tryParse(args['n'] ?? '') ?? 14).clamp(1, 30);
    final data = _map(await _fetch('stoptimes', {'stopId': stop, 'n': count, 'time': _arg(args, 'zeit', 40)}, 30));
    final seen = <String, Map<String, Object?>>{};
    for (final raw in _list(data['stopTimes'])) {
      final item = _map(raw);
      final place = _map(item['place']);
      final planned = place['scheduledDeparture'] ?? place['departure'];
      final key = '${_category(item['mode'])}|${_lineName(item)}|$planned';
      final entry = <String, Object?>{
        'line': _lineName(item),
        'category': _category(item['mode']),
        'direction': item['headsign'] ?? _map(item['tripTo'])['name'] ?? '',
        'planned': planned,
        'time': place['departure'] ?? planned,
        'track': place['track'] ?? place['scheduledTrack'],
        'cancelled': item['cancelled'] == true || item['tripCancelled'] == true,
        'realtime': item['realTime'] == true,
      };
      final current = seen[key];
      if (current == null ||
          (entry['realtime'] == true && current['realtime'] != true) ||
          (entry['track'] != null && current['track'] == null)) {
        seen[key] = entry;
      }
    }
    final items = seen.values.toList()..sort((a, b) => '${a['time'] ?? ''}'.compareTo('${b['time'] ?? ''}'));
    return (<String, Object?>{'stop': _map(data['place'])['name'] ?? '', 'departures': items}, 200);
  }

  static Map<String, Object?> _leg(Map<String, Object?> leg) {
    final origin = _map(leg['from']);
    final target = _map(leg['to']);
    final duration = leg['duration'];
    final distance = leg['distance'];
    return {
      'category': _category(leg['mode']),
      'line': _lineName(leg),
      'headsign': leg['headsign'] ?? '',
      'agency': leg['agencyName'] ?? '',
      'from': {'name': origin['name'] ?? '', 'time': leg['startTime'], 'planned': leg['scheduledStartTime'], 'track': origin['track'] ?? origin['scheduledTrack']},
      'to': {'name': target['name'] ?? '', 'time': leg['endTime'], 'planned': leg['scheduledEndTime'], 'track': target['track'] ?? target['scheduledTrack']},
      'minutes': duration is num ? (duration / 60).round() : 0,
      'distance': distance is num ? distance.round() : 0,
      'stops': _list(leg['intermediateStops']).length,
      'realtime': leg['realTime'] == true,
      'cancelled': leg['cancelled'] == true,
    };
  }

  Future<(Map<String, Object?>, int)> _journeys(Map<String, String> args) async {
    final origin = _arg(args, 'von'), target = _arg(args, 'nach');
    if (origin == null || origin.isEmpty || target == null || target.isEmpty) {
      return (<String, Object?>{'error': 'Start oder Ziel fehlt'}, 400);
    }
    final data = _map(await _fetch('plan', {
      'fromPlace': origin,
      'toPlace': target,
      'time': _arg(args, 'zeit', 40),
      'arriveBy': args['ankunft'] == '1' ? 'true' : 'false',
      'numItineraries': 5,
    }, 45));
    final result = <Map<String, Object?>>[];
    for (final raw in _list(data['itineraries'])) {
      final item = _map(raw);
      final legs = _list(item['legs']).map((leg) => _leg(_map(leg))).toList();
      if (legs.isEmpty) continue;
      final rides = legs.where((leg) => leg['category'] != 'fuss' && leg['category'] != 'rad').toList();
      final ticket = rides.isEmpty
          ? 'fuss'
          : rides.any((leg) => _longDistance.contains(leg['category']))
              ? 'fern'
              : 'deutschland';
      final duration = item['duration'];
      result.add({
        'start': item['startTime'],
        'end': item['endTime'],
        'minutes': duration is num ? (duration / 60).round() : 0,
        'transfers': item['transfers'] ?? (rides.length - 1).clamp(0, 99),
        'legs': legs,
        'ticket': ticket,
        'realtime': rides.any((leg) => leg['realtime'] == true),
        'cancelled': rides.any((leg) => leg['cancelled'] == true),
      });
    }
    return (<String, Object?>{'journeys': result}, 200);
  }

  Future<(Map<String, Object?>, int)> _nearby(Map<String, String> args) async {
    final lat = double.tryParse(args['lat'] ?? ''), lon = double.tryParse(args['lon'] ?? '');
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
      return (<String, Object?>{'error': 'Standort fehlt'}, 400);
    }
    const span = 0.006;
    final data = await _fetch('map/stops', {'min': '${lat - span},${lon - span}', 'max': '${lat + span},${lon + span}'}, 300);
    final stops = <Map<String, Object?>>[
      for (final raw in _list(data))
        if (_map(raw)['stopId'] != null)
          {'id': _map(raw)['stopId'], 'name': _map(raw)['name'] ?? '', 'lat': _map(raw)['lat'], 'lon': _map(raw)['lon']},
    ];
    double distance(Map<String, Object?> stop) {
      final a = stop['lat'], b = stop['lon'];
      if (a is! num || b is! num) return double.infinity;
      return (a - lat) * (a - lat) + (b - lon) * (b - lon);
    }

    stops.sort((a, b) => distance(a).compareTo(distance(b)));
    final unique = <String, Map<String, Object?>>{};
    for (final stop in stops) {
      unique.putIfAbsent('${stop['name']}', () => stop);
    }
    return (<String, Object?>{'stops': unique.values.take(6).toList()}, 200);
  }

  Future<(Map<String, Object?>, int)> handle(String action, Map<String, String> args) async {
    final handler = switch (action) {
      'suche' => _search,
      'abfahrten' => _departures,
      'verbindungen' => _journeys,
      'naehe' => _nearby,
      _ => null,
    };
    if (handler == null) return (<String, Object?>{'error': 'unbekannt'}, 404);
    try {
      return await handler(args);
    } on _TransitFailure catch (failure) {
      return (<String, Object?>{'error': failure.message}, failure.status);
    } on TimeoutException {
      return (<String, Object?>{'error': 'Fahrplan gerade nicht erreichbar'}, 504);
    } on SocketException {
      return (<String, Object?>{'error': 'Fahrplan gerade nicht erreichbar'}, 504);
    } on http.ClientException {
      return (<String, Object?>{'error': 'Fahrplan gerade nicht erreichbar'}, 504);
    } catch (_) {
      return (<String, Object?>{'error': 'Unerwartete Antwort vom Fahrplan'}, 502);
    }
  }
}
