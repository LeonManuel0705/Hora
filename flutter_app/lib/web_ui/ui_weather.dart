// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class UiPlace {
  const UiPlace(this.name, this.lat, this.lon);

  final String name;
  final double lat;
  final double lon;
}

class UiWeather {
  UiWeather._();

  static final UiWeather instance = UiWeather._();
  static const _cacheKey = 'ui_weather_cache';
  static const _maxAge = Duration(minutes: 30);

  Future<void>? _running;

  Map<String, Object?>? _read(SharedPreferences prefs) {
    try {
      final value = jsonDecode(prefs.getString(_cacheKey) ?? 'null');
      return value is Map<String, Object?> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static int? _round(Object? value) => value is num ? value.round() : null;

  Map<String, Object?> view(SharedPreferences prefs, DateTime now) {
    final city = prefs.getString('weather_city') ?? '';
    final cache = _read(prefs);
    final empty = <String, Object?>{'place': city, 'high': null, 'low': null, 'wind': null, 'hours': <Object?>[]};
    if (cache == null || cache['city'] != city) return empty;
    final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final tomorrow = now.add(const Duration(days: 1));
    final nextDay = '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    final hourly = cache['hourly'] is Map ? cache['hourly'] as Map : const {};
    final times = hourly['time'] is List ? hourly['time'] as List : const [];
    final temps = hourly['temperature_2m'] is List ? hourly['temperature_2m'] as List : const [];
    final rains = hourly['precipitation_probability'] is List ? hourly['precipitation_probability'] as List : const [];
    final hours = <Map<String, Object?>>[];
    Map<String, Object?>? morning;
    for (var index = 0; index < times.length && index < temps.length; index++) {
      final time = '${times[index]}';
      final temp = _round(temps[index]);
      if (time.length < 13 || temp == null) continue;
      final hour = int.tryParse(time.substring(11, 13));
      if (hour == null) continue;
      final rain = index < rains.length ? _round(rains[index]) ?? 0 : 0;
      if (time.startsWith(day)) hours.add({'h': hour, 'temp': temp, 'rain': rain});
      if (time.startsWith(nextDay) && hour == 7) morning = {'temp': temp, 'rain': rain};
    }
    final daily = cache['daily'] is Map ? cache['daily'] as Map : const {};
    final dates = daily['time'] is List ? daily['time'] as List : const [];
    final at = dates.indexOf(day);
    int? dailyValue(String key) {
      final values = daily[key];
      return at >= 0 && values is List && at < values.length ? _round(values[at]) : null;
    }

    final current = cache['current'] is Map ? cache['current'] as Map : const {};
    final fresh = '${current['time'] ?? ''}'.startsWith(day);
    return {
      'place': city,
      'high': dailyValue('temperature_2m_max'),
      'low': dailyValue('temperature_2m_min'),
      'wind': fresh ? _round(current['wind_speed_10m']) : null,
      'hours': hours,
      if (morning != null) 'tomorrowMorning': morning,
    };
  }

  Future<void> refresh({bool force = false}) => _running ??= _refresh(force).whenComplete(() => _running = null);

  Future<void> _refresh(bool force) async {
    final prefs = await SharedPreferences.getInstance();
    final city = prefs.getString('weather_city');
    final lat = prefs.getDouble('weather_lat');
    final lon = prefs.getDouble('weather_lon');
    if (city == null || lat == null || lon == null) return;
    final cache = _read(prefs);
    final fetched = DateTime.tryParse('${cache?['fetched'] ?? ''}');
    if (!force && cache?['city'] == city && fetched != null && DateTime.now().difference(fetched) < _maxAge) return;
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,wind_speed_10m,weather_code',
      'hourly': 'temperature_2m,precipitation_probability',
      'daily': 'temperature_2m_max,temperature_2m_min',
      'timezone': 'Europe/Berlin',
      'forecast_days': '2',
    });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body);
      if (body is! Map<String, Object?>) return;
      await prefs.setString(_cacheKey, jsonEncode({
        'city': city,
        'fetched': DateTime.now().toIso8601String(),
        'current': body['current'],
        'hourly': body['hourly'],
        'daily': body['daily'],
      }));
    } catch (_) {}
  }

  Future<UiPlace?> geocode(String name) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': name, 'count': '1', 'language': 'de'});
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      final results = body is Map ? body['results'] : null;
      if (results is! List || results.isEmpty || results.first is! Map) return null;
      final first = results.first as Map;
      final lat = first['latitude'], lon = first['longitude'];
      if (lat is! num || lon is! num) return null;
      return UiPlace('${first['name'] ?? name}', lat.toDouble(), lon.toDouble());
    } catch (_) {
      return null;
    }
  }

  Future<UiPlace?> setPlace(String name) async {
    final wanted = name.trim();
    if (wanted.isEmpty) return null;
    final place = await geocode(wanted);
    if (place == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weather_city', place.name);
    await prefs.setDouble('weather_lat', place.lat);
    await prefs.setDouble('weather_lon', place.lon);
    unawaited(refresh(force: true));
    return place;
  }
}
