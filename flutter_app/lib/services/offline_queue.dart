// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import 'connectivity_service.dart';

enum OperationType {
  create,
  update,
  delete,
}

enum EntityType {
  task,
  event,
  lesson,
  bookmark,
  quickNote,
  email,
  iservNotification,
  googleEvent,
}

class PendingOperation {
  final int? id;
  final OperationType operationType;
  final EntityType entityType;
  final String? entityId;
  final Map<String, dynamic>? payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;
  final String status;

  PendingOperation({
    this.id,
    required this.operationType,
    required this.entityType,
    this.entityId,
    this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
    this.lastError,
    this.status = 'pending',
  }) : createdAt = createdAt ?? DateTime.now();

  factory PendingOperation.fromMap(Map<String, dynamic> map) {
    return PendingOperation(
      id: map['id'] as int?,
      operationType: OperationType.values.firstWhere(
        (e) => e.name == map['operation_type'],
        orElse: () => OperationType.create,
      ),
      entityType: EntityType.values.firstWhere(
        (e) => e.name == map['entity_type'],
        orElse: () => EntityType.task,
      ),
      entityId: map['entity_id'] as String?,
      payload: map['payload_json'] != null
          ? jsonDecode(map['payload_json'] as String) as Map<String, dynamic>
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      retryCount: map['retry_count'] as int? ?? 0,
      lastError: map['last_error'] as String?,
      status: map['status'] as String? ?? 'pending',
    );
  }
}

class OfflineQueue {
  static final OfflineQueue _instance = OfflineQueue._internal();
  factory OfflineQueue() => _instance;
  OfflineQueue._internal();

  final DatabaseService _db = DatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  final ValueNotifier<int> pendingCount = ValueNotifier(0);
  final ValueNotifier<bool> isProcessing = ValueNotifier(false);

  final Map<EntityType, Future<bool> Function(PendingOperation)> _processors = {};

  static const int maxRetries = 3;

  void registerProcessor(
    EntityType entityType,
    Future<bool> Function(PendingOperation) processor,
  ) {
    _processors[entityType] = processor;
  }

  void unregisterProcessor(EntityType entityType) {
    _processors.remove(entityType);
  }

  Future<int> enqueue({
    required OperationType operationType,
    required EntityType entityType,
    String? entityId,
    Map<String, dynamic>? payload,
  }) async {
    final id = await _db.insertPendingOperation(
      operationType: operationType.name,
      entityType: entityType.name,
      entityId: entityId,
      payloadJson: payload != null ? jsonEncode(payload) : null,
    );
    await _updatePendingCount();
    return id;
  }

  Future<void> processQueue() async {
    if (!_connectivity.isOnline.value) {
      return;
    }

    if (isProcessing.value) {
      return;
    }

    isProcessing.value = true;

    try {
      final operations = await _db.getPendingOperations();

      for (final opMap in operations) {
        final operation = PendingOperation.fromMap(opMap);

        final processor = _processors[operation.entityType];
        if (processor == null) {

          continue;
        }

        try {
          final success = await processor(operation);

          if (success) {
            await _db.markOperationCompleted(operation.id!);
          } else {
            await _db.markOperationFailed(
              operation.id!,
              'Processor returned false',
              giveUp: operation.retryCount + 1 >= maxRetries,
            );
          }
        } catch (e) {
          if (_isNetworkError(e)) {
            break;
          }
          await _db.markOperationFailed(
            operation.id!,
            e.toString(),
            giveUp: operation.retryCount + 1 >= maxRetries,
          );
        }
      }
    } finally {
      isProcessing.value = false;
      await _updatePendingCount();
    }
  }

  bool _isNetworkError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
           errorStr.contains('socket') ||
           errorStr.contains('connection') ||
           errorStr.contains('timeout');
  }

  Future<void> _updatePendingCount() async {
    pendingCount.value = await _db.getPendingOperationCount();
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    final operations = await _db.getPendingOperations();
    return operations.map((m) => PendingOperation.fromMap(m)).toList();
  }

  Future<void> clearCompleted() async {
    await _db.clearCompletedOperations();
    await _updatePendingCount();
  }

  Future<int> getPendingCount() async {
    return await _db.getPendingOperationCount();
  }

  Future<void> initialize() async {
    await _updatePendingCount();
  }
}
