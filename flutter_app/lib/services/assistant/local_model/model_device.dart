// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/services.dart';

class DeviceProfile {
  const DeviceProfile({this.directory, this.freeBytes, this.totalMemory, this.availableMemory});

  final String? directory;
  final int? freeBytes;
  final int? totalMemory;
  final int? availableMemory;
}

class MemorySnapshot {
  const MemorySnapshot({this.total, this.available, this.low = false});

  final int? total;
  final int? available;
  final bool low;
}

class NetworkStatus {
  const NetworkStatus({required this.connected, required this.metered});

  final bool connected;
  final bool metered;

  static NetworkStatus? from(Object? value) {
    if (value is! Map) return null;
    final connected = value['connected'];
    final metered = value['metered'];
    if (connected is! bool || metered is! bool) return null;
    return NetworkStatus(connected: connected, metered: metered);
  }
}

class ModelDevice {
  const ModelDevice();

  static const _channel = MethodChannel('app/assistant_model');
  static const _networkEvents = EventChannel('app/assistant_model/network');

  Future<NetworkStatus?> network() async {
    try {
      return NetworkStatus.from(await _channel.invokeMethod<Object?>('network'));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Stream<NetworkStatus> networkChanges() => _networkEvents
      .receiveBroadcastStream()
      .map(NetworkStatus.from)
      .where((status) => status != null)
      .cast<NetworkStatus>();

  Future<DeviceProfile> profile() async {
    final values = await _channel.invokeMapMethod<String, Object?>('profile') ?? const {};
    return DeviceProfile(
      directory: values['directory'] as String?,
      freeBytes: _int(values['freeBytes']),
      totalMemory: _int(values['totalMemory']),
      availableMemory: _int(values['availableMemory']),
    );
  }

  Future<MemorySnapshot> memory() async {
    try {
      final values = await _channel.invokeMapMethod<String, Object?>('memory') ?? const {};
      return MemorySnapshot(
        total: _int(values['total']),
        available: _int(values['available']),
        low: values['low'] == true,
      );
    } on PlatformException {
      return const MemorySnapshot();
    } on MissingPluginException {
      return const MemorySnapshot();
    }
  }

  Future<int?> freeBytes(String path) async {
    try {
      return _int(await _channel.invokeMethod<Object?>('freeSpace', {'path': path}));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  Future<void> excludeFromBackup(String path) async {
    try {
      await _channel.invokeMethod<Object?>('excludeFromBackup', {'path': path});
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;
}
