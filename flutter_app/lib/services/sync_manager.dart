// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'connectivity_service.dart';
import 'database_service.dart';
import 'offline_queue.dart';

enum SyncState {
  idle,
  syncing,
  error,
  offline,
}

enum SyncType {
  critical,
  foreground,
  background,
}

class SyncResult {
  final bool success;
  final String? error;
  final int itemsSynced;
  final DateTime syncedAt;

  SyncResult({
    required this.success,
    this.error,
    this.itemsSynced = 0,
    DateTime? syncedAt,
  }) : syncedAt = syncedAt ?? DateTime.now();

  factory SyncResult.success({int itemsSynced = 0}) {
    return SyncResult(success: true, itemsSynced: itemsSynced);
  }

  factory SyncResult.failure(String error) {
    return SyncResult(success: false, error: error);
  }
}

class SyncManager {
  static final SyncManager _instance = SyncManager._internal();
  factory SyncManager() => _instance;
  SyncManager._internal();

  final ConnectivityService _connectivity = ConnectivityService();
  final DatabaseService _db = DatabaseService();
  final OfflineQueue _offlineQueue = OfflineQueue();

  final ValueNotifier<SyncState> state = ValueNotifier(SyncState.idle);
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final ValueNotifier<DateTime?> lastSyncTime = ValueNotifier(null);

  final Map<String, Future<SyncResult> Function()> _syncCallbacks = {};

  bool _isInitialized = false;
  Timer? _autoSyncTimer;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _connectivity.initialize();

    _connectivity.onConnected(_onConnected);

    if (!_connectivity.isOnline.value) {
      state.value = SyncState.offline;
    }
  }

  void _onConnected() {

    if (state.value == SyncState.offline) {
      state.value = SyncState.idle;
    }
    _processOfflineQueueAndSync();
  }

  Future<void> _processOfflineQueueAndSync() async {

    await _offlineQueue.processQueue();

    await syncAll(type: SyncType.background);
  }

  void registerSyncCallback(String serviceName, Future<SyncResult> Function() callback) {
    _syncCallbacks[serviceName] = callback;
  }

  void unregisterSyncCallback(String serviceName) {
    _syncCallbacks.remove(serviceName);
  }

  Future<Map<String, SyncResult>> syncAll({SyncType type = SyncType.foreground}) async {
    if (!_connectivity.isOnline.value) {
      state.value = SyncState.offline;
      return {};
    }

    state.value = SyncState.syncing;
    lastError.value = null;

    final results = <String, SyncResult>{};
    var hasError = false;

    for (final entry in _syncCallbacks.entries) {
      try {
        results[entry.key] = await entry.value();
        if (!results[entry.key]!.success) {
          hasError = true;
        }
      } catch (e) {
        results[entry.key] = SyncResult.failure(e.toString());
        hasError = true;
      }
    }

    state.value = hasError ? SyncState.error : SyncState.idle;
    lastSyncTime.value = DateTime.now();

    return results;
  }

  Future<SyncResult> syncService(String serviceName) async {
    if (!_connectivity.isOnline.value) {
      return SyncResult.failure('Offline');
    }

    final callback = _syncCallbacks[serviceName];
    if (callback == null) {
      return SyncResult.failure('Service not registered: $serviceName');
    }

    state.value = SyncState.syncing;

    try {
      final result = await callback();
      state.value = result.success ? SyncState.idle : SyncState.error;
      if (!result.success) {
        lastError.value = result.error;
      }
      return result;
    } catch (e) {
      state.value = SyncState.error;
      lastError.value = e.toString();
      return SyncResult.failure(e.toString());
    }
  }

  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      if (_connectivity.isOnline.value) {
        syncAll(type: SyncType.background);
      }
    });
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  Future<Map<String, dynamic>?> getSyncStatus(String tableName) async {
    return await _db.getSyncStatus(tableName);
  }

  Future<void> updateSyncStatus(String tableName, {String? syncToken, String? error}) async {
    await _db.updateSyncStatus(tableName, syncToken: syncToken, error: error);
  }

  Future<bool> needsSync(String tableName, {Duration maxAge = const Duration(minutes: 15)}) async {
    final status = await _db.getSyncStatus(tableName);
    if (status == null) return true;

    final lastSync = status['last_sync_at'] as String?;
    if (lastSync == null) return true;

    final lastSyncTime = DateTime.parse(lastSync);
    return DateTime.now().difference(lastSyncTime) > maxAge;
  }

  Future<int> getPendingOperationCount() async {
    return await _db.getPendingOperationCount();
  }

  void dispose() {
    _autoSyncTimer?.cancel();
    _connectivity.removeOnConnected(_onConnected);
  }
}
