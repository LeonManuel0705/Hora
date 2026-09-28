// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../brand.dart';
import '../../../build_info.dart';
import 'local_llm.dart';
import 'model_debug.dart';
import 'model_device.dart';
import 'model_download_job.dart';
import 'model_downloader.dart';
import 'model_installer.dart';
import 'model_manifest.dart';
import 'model_runtime.dart';

class LocalAssistant with WidgetsBindingObserver {
  LocalAssistant._(this.installer, this.runtime) {
    WidgetsBinding.instance.addObserver(this);
  }

  final ModelInstaller installer;
  final ModelRuntime runtime;
  int _screens = 0;

  static LocalAssistant? _instance;

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static LocalAssistant? get instance {
    if (!supported) return null;
    return _instance ??= _create();
  }

  static LocalAssistant _create() {
    const device = ModelDevice();
    final runtime = ModelRuntime(
      create: createLocalLlm,
      store: PrefsRuntimeStore(),
      gpuPreferred: localLlmPrefersGpu(),
      availableMemory: () async => (await device.memory()).available,
    );
    late final LocalAssistant assistant;
    final installer = ModelInstaller(DeviceInstallHost(
      device: device,
      runtime: runtime,
      keepLoaded: () => assistant._screens > 0,
    ));
    return assistant = LocalAssistant._(installer, runtime);
  }

  void attach() => _screens++;

  void detach() {
    if (_screens > 0) _screens--;
    if (_screens == 0) unawaited(runtime.unload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        installer.appPaused();
        if (Platform.isIOS) runtime.stop();
        runtime.setBackground(true);
      case AppLifecycleState.resumed:
        runtime.setBackground(false);
        installer.appResumed();
      default:
        break;
    }
  }

  @override
  void didHaveMemoryPressure() => unawaited(runtime.releaseIfIdle());
}

class DeviceInstallHost implements ModelInstallHost {
  DeviceInstallHost({required this.device, required this.runtime, required this.keepLoaded});

  final ModelDevice device;
  final ModelRuntime runtime;
  final bool Function() keepLoaded;
  final Connectivity _connectivity = Connectivity();

  @override
  Future<ModelPlan> plan() async {
    final profile = await device.profile();
    final override = kDebugMode ? (await SharedPreferences.getInstance()).getString('assistant_debug_model') : null;
    final choice = debugModelChoice(freeBytes: profile.freeBytes, override: override) ??
        chooseModel(totalMemory: profile.totalMemory, runtimeAvailable: localLlmAvailable());
    return ModelPlan(
      choice: choice,
      directory: profile.directory,
      freeBytes: profile.freeBytes,
      totalMemory: profile.totalMemory,
    );
  }

  @override
  Future<int?> freeBytes(String directory) => device.freeBytes(directory);

  @override
  Future<NetworkKind> network() async => _kind(await _connectivity.checkConnectivity());

  @override
  Stream<NetworkKind> get networkChanges => _connectivity.onConnectivityChanged.map(_kind);

  @override
  Future<void> keepAwake(bool on) => device.keepScreenOn(on);

  @override
  Future<void> protect(String path) => device.excludeFromBackup(path);

  @override
  Future<ModelTransfer> download(
    ModelFile model,
    File target,
    void Function(DownloadProgress progress) onProgress,
  ) async {
    final job = await ModelDownloadJob.start(
      ModelDownloadRequest(
        url: model.url,
        target: target.path,
        bytes: model.bytes,
        checksum: model.sha256,
        userAgent: '${Brand.name}/${BuildInfo.version}',
      ),
      onProgress: onProgress,
    );
    return _JobTransfer(job);
  }

  @override
  Future<void> start(String path) async {
    await runtime.resetCrashGuard();
    await runtime.load(path);
    if (!keepLoaded()) await runtime.unload();
  }

  static NetworkKind _kind(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.none:
        return NetworkKind.none;
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
        return NetworkKind.wifi;
      case ConnectivityResult.mobile:
        return NetworkKind.mobile;
      default:
        return NetworkKind.other;
    }
  }
}

class _JobTransfer implements ModelTransfer {
  _JobTransfer(this.job);

  final ModelDownloadJob job;

  @override
  Future<File> get result => job.result;

  @override
  void cancel() => job.cancel();
}

class PrefsRuntimeStore implements RuntimeStore {
  static const _levelKey = 'assistant_model_level';
  static const _cleanRunsKey = 'assistant_model_clean_runs';
  static const _inflightKey = 'assistant_model_inflight';

  @override
  Future<int> level() async => (await SharedPreferences.getInstance()).getInt(_levelKey) ?? 0;

  @override
  Future<void> setLevel(int level) async => (await SharedPreferences.getInstance()).setInt(_levelKey, level);

  @override
  Future<int> cleanRuns() async => (await SharedPreferences.getInstance()).getInt(_cleanRunsKey) ?? 0;

  @override
  Future<void> setCleanRuns(int runs) async => (await SharedPreferences.getInstance()).setInt(_cleanRunsKey, runs);

  @override
  Future<String?> inflight() async => (await SharedPreferences.getInstance()).getString(_inflightKey);

  @override
  Future<void> setInflight(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_inflightKey);
    } else {
      await prefs.setString(_inflightKey, value);
    }
  }
}
