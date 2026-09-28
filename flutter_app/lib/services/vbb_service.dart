// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/vbb.dart';
import 'database_service.dart';
import 'connectivity_service.dart';

class VbbService {
  static final VbbService _instance = VbbService._internal();
  factory VbbService() => _instance;
  VbbService._internal();

  static const String _baseUrl = 'https://v6.vbb.transport.rest';

  final DatabaseService _db = DatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();
  final Uuid _uuid = const Uuid();

  Future<List<VbbLocation>> searchLocations(String query) async {
    if (query.length < 2) return [];

    final cached = await _db.getCachedVbbLocations(query);
    if (cached.isNotEmpty) {
      return cached;
    }

    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_baseUrl/locations?query=${Uri.encodeComponent(query)}&results=10'),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw Exception('Netzwerkfehler: Server nicht erreichbar ($e)');
    }

    if (response.statusCode != 200) {
      throw Exception('Server-Fehler (${response.statusCode})');
    }

    final List<dynamic> data = jsonDecode(response.body);
    final locations = data
        .map((json) => VbbLocation.fromApiResponse(json as Map<String, dynamic>))
        .where((loc) => loc.id.isNotEmpty && loc.name.isNotEmpty)
        .toList();

    await _db.cacheVbbLocations(query, locations);

    return locations;
  }

  Future<VbbLocation?> getStation(String id) async {
    if (!_connectivity.isOnline.value) {
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/stops/$id'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return VbbLocation.fromApiResponse(data);
      }
    } catch (_) {
    }

    return null;
  }

  Future<List<VbbJourney>> searchRoutes({
    required String fromId,
    required String toId,
    DateTime? departure,
    bool isDeparture = true,
  }) async {
    final debugSteps = <String>[];
    debugSteps.add('searchRoutes: from=$fromId, to=$toId, departure=$departure, isDeparture=$isDeparture');

    final cacheKey = '${fromId}_${toId}_${departure?.toIso8601String() ?? 'now'}';

    final cached = await _db.getCachedVbbRoutes(cacheKey);
    if (cached.isNotEmpty) {
      debugSteps.add('Returning ${cached.length} cached routes');
      developer.log(debugSteps.join(' | '), name: 'VBB');
      return cached;
    }
    debugSteps.add('No cache hit');

    final params = {
      'from': fromId,
      'to': toId,
      'results': '5',
      'stopovers': 'true',
      'tickets': 'true',
    };

    if (departure != null) {
      params[isDeparture ? 'departure' : 'arrival'] = departure.toIso8601String();
    }

    final uri = Uri.parse('$_baseUrl/journeys').replace(queryParameters: params);
    debugSteps.add('URL: $uri');

    final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 15));
      debugSteps.add('HTTP ${response.statusCode}, body=${response.body.length} bytes');
    } catch (e) {
      debugSteps.add('FAIL network: ${e.runtimeType}: $e');
      developer.log(debugSteps.join(' | '), name: 'VBB');
      throw Exception('Netzwerkfehler: Server nicht erreichbar (${e.runtimeType}: $e)');
    }

    if (response.statusCode != 200) {
      String detail = '';
      try {
        final errBody = jsonDecode(response.body);
        detail = errBody['msg'] ?? errBody['error'] ?? response.body.substring(0, 200);
      } catch (_) {
        detail = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
      }
      debugSteps.add('FAIL HTTP ${response.statusCode}: $detail');
      developer.log(debugSteps.join(' | '), name: 'VBB');
      throw Exception('Server-Fehler (HTTP ${response.statusCode}): $detail');
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final journeysJson = data['journeys'] as List? ?? [];
      debugSteps.add('Parsed ${journeysJson.length} journeys');

      final journeys = journeysJson
          .map((json) => VbbJourney.fromApiResponse(json as Map<String, dynamic>))
          .toList();

      debugSteps.add('Mapped ${journeys.length} VbbJourney objects');
      developer.log(debugSteps.join(' | '), name: 'VBB');

      await _db.cacheVbbRoutes(cacheKey, journeys);
      return journeys;
    } catch (e) {
      debugSteps.add('FAIL parse: ${e.runtimeType}: $e');
      developer.log(debugSteps.join(' | '), name: 'VBB');
      throw Exception('Daten-Fehler: Antwort konnte nicht verarbeitet werden (${e.runtimeType}: $e)');
    }
  }

  Future<List<VbbDeparture>> getDepartures(String stationId, {int duration = 30}) async {
    final http.Response response;
    try {
      response = await http.get(
        Uri.parse('$_baseUrl/stops/$stationId/departures?duration=$duration&results=20'),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw Exception('Netzwerkfehler: Server nicht erreichbar ($e)');
    }

    if (response.statusCode != 200) {
      throw Exception('Server-Fehler (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final departuresJson = data['departures'] as List;
    return departuresJson
        .map((json) => VbbDeparture.fromApiResponse(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<VbbKnownLocation>> getKnownLocations() async {
    return await _db.getVbbKnownLocations();
  }

  Future<VbbKnownLocation> addKnownLocation({
    required String name,
    required String alias,
    required VbbLocation location,
  }) async {
    final knownLocation = VbbKnownLocation(
      id: _uuid.v4(),
      name: name,
      alias: alias,
      locationId: location.id,
      locationName: location.name,
      latitude: location.latitude,
      longitude: location.longitude,
    );

    await _db.insertVbbKnownLocation(knownLocation);
    return knownLocation;
  }

  Future<void> removeKnownLocation(String id) async {
    await _db.deleteVbbKnownLocation(id);
  }

  Future<List<VbbFavoriteRoute>> getFavoriteRoutes() async {
    return await _db.getVbbFavoriteRoutes();
  }

  Future<VbbFavoriteRoute> addFavoriteRoute({
    required String name,
    required VbbLocation from,
    required VbbLocation to,
  }) async {
    final route = VbbFavoriteRoute(
      id: _uuid.v4(),
      name: name,
      fromId: from.id,
      fromName: from.name,
      toId: to.id,
      toName: to.name,
      createdAt: DateTime.now(),
    );

    await _db.insertVbbFavoriteRoute(route);
    return route;
  }

  Future<void> removeFavoriteRoute(String id) async {
    await _db.deleteVbbFavoriteRoute(id);
  }

  Future<bool> hasKnownLocations() async {
    final existing = await getKnownLocations();
    return existing.isNotEmpty;
  }

  Future<bool> hasHomeLocation() async {
    final locations = await getKnownLocations();
    return locations.any((loc) => loc.alias == 'home');
  }

  Future<bool> hasSchoolLocation() async {
    final locations = await getKnownLocations();
    return locations.any((loc) => loc.alias == 'school');
  }

  Future<VbbKnownLocation?> getHomeLocation() async {
    final locations = await getKnownLocations();
    try {
      return locations.firstWhere((loc) => loc.alias == 'home');
    } catch (_) {
      return null;
    }
  }

  Future<VbbKnownLocation?> getSchoolLocation() async {
    final locations = await getKnownLocations();
    try {
      return locations.firstWhere((loc) => loc.alias == 'school');
    } catch (_) {
      return null;
    }
  }

  Future<void> clearOldCache() async {
    await _db.clearOldVbbCache();
  }


  Future<List<VbbTicket>> getTickets() async {
    return await _db.getVbbTickets();
  }

  Future<VbbTicket> addTicket({
    required String ticketType,
    required String ticketName,
    required String zoneCoverage,
    DateTime? validFrom,
    DateTime? validUntil,
    bool autoRenews = false,
  }) async {
    final ticket = VbbTicket(
      id: _uuid.v4(),
      ticketType: ticketType,
      ticketName: ticketName,
      zoneCoverage: zoneCoverage,
      validFrom: validFrom,
      validUntil: validUntil,
      autoRenews: autoRenews,
      createdAt: DateTime.now(),
    );
    await _db.insertVbbTicket(ticket);
    return ticket;
  }

  Future<void> updateTicket(VbbTicket ticket) async {
    await _db.updateVbbTicket(ticket);
  }

  Future<void> removeTicket(String id) async {
    await _db.deleteVbbTicket(id);
  }
}
