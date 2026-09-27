// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show ValueNotifier, kDebugMode, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brand.dart';
import 'legacy_import.dart';

enum FlaskServerState { idle, starting, ready, error, alreadyRunning }

enum SetupResult { success, brewNotFound, error, unsupportedPlatform }

class FlaskServerService {
  static final FlaskServerService _instance = FlaskServerService._internal();
  factory FlaskServerService() => _instance;
  FlaskServerService._internal();

  static const _backendPidsKey = 'hub_backend_pids';

  final String _desktopToken = _newToken();
  RandomAccessFile? _instanceLock;
  Process? _flaskProcess;
  bool _externalServer = false;
  String? _errorMessage;

  bool isPythonMissing = false;
  bool isSettingUp = false;
  final ValueNotifier<String> setupProgress = ValueNotifier('');

  final ValueNotifier<FlaskServerState> state =
      ValueNotifier(FlaskServerState.idle);

  String get errorMessage => _errorMessage ?? '';
  bool get isReady =>
      state.value == FlaskServerState.ready ||
      state.value == FlaskServerState.alreadyRunning;
  int get port => 5050;
  String get url => 'http://127.0.0.1:$port';
  String get hubUrl => '$url/hub';
  String get desktopToken => _desktopToken;

  bool isHubUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'http' &&
        uri.userInfo.isEmpty &&
        uri.host == '127.0.0.1' &&
        uri.port == port;
  }

  static String _newToken() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String get _homeDir =>
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';

  static String _system32(String exe) => p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32', exe);

  String get _defaultProjectPath => p.join(_homeDir, 'Documents', Brand.name);

  Future<bool> Function(String previousName)? confirmLegacyImport;

  static String? _env(String name) {
    final prefixes = [
      'HUB',
      for (final previous in Brand.previousNames) previous.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_'),
    ].where((prefix) => RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(prefix));
    for (final prefix in prefixes) {
      final value = Platform.environment['${prefix}_$name'];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _legacyFolder() {
    final home = _homeDir;
    if (home.isEmpty) return null;
    return LegacyImport.findLegacyFolder(
      documents: p.join(home, 'Documents'),
      target: _defaultProjectPath,
      previousNames: Brand.previousNames,
    );
  }

  Future<String?> _importLegacyData({required bool sole}) async {
    final legacy = _legacyFolder();
    if (legacy == null) return null;
    final name = p.basename(legacy);
    if (!sole) {
      return '${Brand.name} übernimmt gerade in einem anderen Fenster die Daten aus $name.\n'
          'Schließ dieses Fenster oder versuch es gleich noch einmal.';
    }
    final ask = confirmLegacyImport;
    if (ask == null || !await ask(name)) return null;
    final outcome = await LegacyImport.copyInto(
      legacy: legacy,
      target: _defaultProjectPath,
      python: await _findPythonPath(legacy),
    );
    if (kDebugMode) print('FlaskServer: Import from $legacy: $outcome');
    switch (outcome) {
      case LegacyImportOutcome.imported:
      case LegacyImportOutcome.skipped:
        return null;
      case LegacyImportOutcome.keyConflict:
        return 'Die Daten aus Dokumente/$name wurden nicht übernommen.\n'
            'Dokumente/${Brand.name}/.env hat einen anderen SECRET_KEY, damit wären deine Zugangsdaten unlesbar.';
      case LegacyImportOutcome.unclearOld:
        return 'Dokumente/$name/.env lässt sich nicht eindeutig lesen, deshalb wurde nichts übernommen.\n'
            'Prüf die Datei, zum Beispiel auf ein fehlendes Anführungszeichen, und versuch es noch einmal.';
      case LegacyImportOutcome.unclearNew:
        return 'Dokumente/${Brand.name}/.env lässt sich nicht eindeutig lesen oder nachprüfen, deshalb wurde nichts übernommen.\n'
            'Prüf die Datei, zum Beispiel auf ein fehlendes Anführungszeichen, und versuch es noch einmal.';
      case LegacyImportOutcome.failed:
        return 'Die Übernahme aus Dokumente/$name hat nicht geklappt.\n'
            'Der alte Ordner ist unverändert. Versuch es noch einmal.';
    }
  }

  Future<void> start() async {
    if (isReady) return;

    state.value = FlaskServerState.starting;
    _errorMessage = null;
    isPythonMissing = false;

    // 1. Reuse an already-running server. This works on every platform,
    //    including Windows/Linux where we may not be able to spawn Python
    //    ourselves — the user can start `python -m app.app` manually and the
    //    app will simply attach to it.
    bool sole;
    try {
      sole = await _isSoleInstance();
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Could not take the instance lock: $e');
      sole = false;
    }

    Set<int>? leftovers;
    if (await _isServerRunning()) {
      leftovers = sole ? await _ownLeftovers() : <int>{};
      if (leftovers.isEmpty) {
        _externalServer = true;
        state.value = FlaskServerState.alreadyRunning;
        if (kDebugMode) {
          print('FlaskServer: Reusing already-running server on port $port');
        }
        return;
      }
    }

    if (sole) {
      try {
        LegacyImport.cleanUp(_defaultProjectPath);
      } catch (_) {}
    }
    final located = await _resolveProjectRoot();
    if (located == null || p.equals(located, _defaultProjectPath)) {
      String? problem;
      try {
        problem = await _importLegacyData(sole: sole || !_lockContended);
      } catch (_) {
        problem = 'Die alten Daten ließen sich nicht übernehmen.\n'
            'Der alte Ordner ist unverändert. Versuch es noch einmal.';
      }
      if (problem != null) {
        _errorMessage = problem;
        state.value = FlaskServerState.error;
        return;
      }
    }
    await _extractBundledBackend();

    // Clear a dead listener squatting the port, or the backend an earlier run
    // of this app left behind, so the one started now runs the current code.
    await _killExistingServerOnPort(only: sole ? leftovers : const <int>{});

    final root = await _resolveProjectRoot();
    if (root == null) {
      _errorMessage = 'Projektordner nicht gefunden.\n'
          'Erwartet: Documents/${Brand.name} mit app/app.py';
      state.value = FlaskServerState.error;
      return;
    }

    final pythonPath = await _findPythonPath(root);
    if (pythonPath == null) {
      isPythonMissing = true;
      _errorMessage = 'Python 3 wurde nicht gefunden.\n'
          'Bitte installiere Python 3.';
      state.value = FlaskServerState.error;
      return;
    }
    await _syncPipDependencies(root, pythonPath);
    final listenersBefore = await _listenerPids();

    try {
      if (kDebugMode) {
        print('FlaskServer: Starting with $pythonPath in $root');
      }

      _flaskProcess = await Process.start(
        pythonPath,
        ['-m', 'app.app'],
        workingDirectory: root,
        environment: {
          ...Platform.environment,
          'HUB_HOST': '127.0.0.1',
          'FLASK_ENV': 'development',
          'HUB_DESKTOP_TOKEN': _desktopToken,
        },
      );

      _flaskProcess!.stdout.transform(const SystemEncoding().decoder).listen(
        (data) {
          if (kDebugMode) print('Flask stdout: $data');
        },
      );

      _flaskProcess!.stderr.transform(const SystemEncoding().decoder).listen(
        (data) {
          if (kDebugMode) print('Flask stderr: $data');
        },
      );

      _flaskProcess!.exitCode.then((code) {
        if (state.value == FlaskServerState.ready ||
            state.value == FlaskServerState.starting) {
          if (kDebugMode) print('FlaskServer: Process exited with code $code');
          _errorMessage = 'Server unerwartet beendet (Code: $code)';
          state.value = FlaskServerState.error;
          _flaskProcess = null;
        }
      });

      final ready = await _waitForServer();
      if (ready) {
        await _rememberServer(listenersBefore);
        state.value = FlaskServerState.ready;
        if (kDebugMode) print('FlaskServer: Ready on port $port');
      } else {
        _errorMessage = 'Server konnte nicht gestartet werden.\n'
            'Timeout nach 15 Sekunden.';
        state.value = FlaskServerState.error;
        await _killProcess();
      }
    } catch (e) {
      _errorMessage = 'Fehler beim Starten: $e';
      state.value = FlaskServerState.error;
      await _killProcess();
    }
  }

  Future<void> restart() async {
    await shutdown();
    _externalServer = false;
    await start();
  }

  Future<void> shutdown() async {
    if (_externalServer) {
      if (kDebugMode) print('FlaskServer: External server, skipping shutdown');
      state.value = FlaskServerState.idle;
      return;
    }
    await _killProcess();
    state.value = FlaskServerState.idle;
  }

  Future<SetupResult> setupPython() async {
    // Automatic Python installation is implemented via Homebrew and is
    // macOS-only. On Windows/Linux, direct the user to install Python manually
    // (the UI offers a python.org link).
    if (!Platform.isMacOS) {
      setupProgress.value =
          'Automatische Installation wird nur auf macOS unterstützt.\n'
          'Bitte installiere Python 3 manuell (python.org) und starte neu.';
      return SetupResult.unsupportedPlatform;
    }

    if (isSettingUp) return SetupResult.error;
    isSettingUp = true;
    setupProgress.value = 'Python-Installation wird vorbereitet...';

    try {
      final root = await _resolveProjectRoot() ?? _defaultProjectPath;

      String? pythonPath = await _findSystemPython3();

      if (pythonPath == null) {
        setupProgress.value = 'Prüfe ob Homebrew verfügbar ist...';
        final brewWhich = await Process.run('which', ['brew']);
        if (brewWhich.exitCode == 0) {
          setupProgress.value = 'Installiere Python 3 via Homebrew...\n'
              'Das kann einige Minuten dauern.';
          final brewResult = await _runProcessWithProgress(
            'brew',
            ['install', 'python3'],
            progressPrefix: 'Homebrew',
          );
          if (brewResult != 0) {
            setupProgress.value = 'Homebrew-Installation fehlgeschlagen.';
            isSettingUp = false;
            return SetupResult.error;
          }
          pythonPath = await _findSystemPython3();
        } else {
          setupProgress.value = 'Homebrew nicht gefunden.\n'
              'Prüfe Xcode Command Line Tools...';
          if (File('/usr/bin/python3').existsSync()) {
            pythonPath = '/usr/bin/python3';
          }
        }
      }

      if (pythonPath == null) {
        setupProgress.value = 'Python 3 konnte nicht installiert werden.\n'
            'Bitte installiere Homebrew oder Python manuell.';
        isSettingUp = false;
        return SetupResult.brewNotFound;
      }

      if (kDebugMode) print('FlaskServer: Setup using Python at $pythonPath');

      final venvPath = p.join(root, 'venv');
      if (!Directory(venvPath).existsSync()) {
        setupProgress.value = 'Erstelle virtuelle Umgebung...';
        final venvResult = await Process.run(
          pythonPath,
          ['-m', 'venv', 'venv'],
          workingDirectory: root,
        );
        if (venvResult.exitCode != 0) {
          final stderr = (venvResult.stderr as String).trim();
          setupProgress.value = 'venv-Erstellung fehlgeschlagen.\n$stderr';
          isSettingUp = false;
          return SetupResult.error;
        }
      }

      final venvPython = p.join(venvPath, 'bin', 'python3');
      final reqPath = p.join(root, 'requirements.txt');
      if (File(reqPath).existsSync()) {
        setupProgress.value = 'Installiere Abhängigkeiten...\n'
            'Das kann einige Minuten dauern.';
        final pipResult = await _runProcessWithProgress(
          File(venvPython).existsSync() ? venvPython : pythonPath,
          ['-m', 'pip', 'install', '-r', reqPath],
          progressPrefix: 'pip',
          workingDirectory: root,
        );
        if (pipResult != 0) {
          setupProgress.value = 'pip install fehlgeschlagen.';
          isSettingUp = false;
          return SetupResult.error;
        }
      }

      setupProgress.value = 'Installation abgeschlossen. Server wird gestartet...';
      isPythonMissing = false;
      isSettingUp = false;

      await start();
      return SetupResult.success;
    } catch (e) {
      setupProgress.value = 'Unerwarteter Fehler: $e';
      isSettingUp = false;
      return SetupResult.error;
    }
  }

  Future<String?> _findSystemPython3() async {
    for (final path in [
      '/usr/bin/python3',
      '/usr/local/bin/python3',
      '/opt/homebrew/bin/python3'
    ]) {
      if (File(path).existsSync()) {
        try {
          final version = await Process.run(path, ['--version']);
          final versionStr = '${version.stdout}${version.stderr}';
          if (versionStr.contains('Python 3')) return path;
        } catch (_) {}
      }
    }

    try {
      final result = await Process.run('which', ['python3']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) {
          final version = await Process.run(path, ['--version']);
          final versionStr = '${version.stdout}${version.stderr}';
          if (versionStr.contains('Python 3')) return path;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<int> _runProcessWithProgress(
    String executable,
    List<String> args, {
    String progressPrefix = '',
    String? workingDirectory,
  }) async {
    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
      );
      final prefix = progressPrefix.isNotEmpty ? '$progressPrefix: ' : '';

      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        final line = data.trim();
        if (line.isNotEmpty) {
          setupProgress.value = '$prefix$line';
          if (kDebugMode) print('Setup stdout: $line');
        }
      });

      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        final line = data.trim();
        if (line.isNotEmpty) {
          setupProgress.value = '$prefix$line';
          if (kDebugMode) print('Setup stderr: $line');
        }
      });

      return await process.exitCode;
    } catch (e) {
      if (kDebugMode) print('Setup process error: $e');
      return -1;
    }
  }

  // Only processes LISTENING on 127.0.0.1:port, where the backend binds, count —
  // never processes merely connected to it (a browser tab, curl, the Electron
  // wrapper). Guarded per platform because lsof does not exist on Windows.
  Future<Set<int>> _listenerPids() async {
    final pids = <int>{};
    try {
      if (Platform.isWindows) {
        final result = await Process.run(_system32('netstat.exe'), ['-ano']);
        pids.addAll(parseNetstatListeners(result.stdout as String, port));
      } else {
        final result = await Process.run(
            'lsof', ['-t', '-iTCP@127.0.0.1:$port', '-sTCP:LISTEN']);
        for (final line in (result.stdout as String).split('\n')) {
          final pid = int.tryParse(line.trim());
          if (pid != null) pids.add(pid);
        }
      }
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Could not list listeners on port $port: $e');
    }
    return pids;
  }

  @visibleForTesting
  static Set<int> parseNetstatListeners(String output, int port) {
    final listener = RegExp(
      r'^\s*TCP\s+127\.0\.0\.1:' '$port' r'\s+0\.0\.0\.0:0\s+\S+\s+(\d+)\s*$',
      caseSensitive: false,
    );
    final pids = <int>{};
    for (final line in output.split('\n')) {
      final match = listener.firstMatch(line.trimRight());
      if (match == null) continue;
      final pid = int.tryParse(match.group(1)!);
      if (pid != null && pid != 0) pids.add(pid);
    }
    return pids;
  }

  Future<void> _killExistingServerOnPort({Set<int>? only}) async {
    var pids = await _listenerPids();
    if (only != null) pids = pids.intersection(only);
    if (pids.isEmpty) return;
    try {
      for (final pid in pids) {
        if (kDebugMode) print('FlaskServer: Stopping listener $pid on port $port');
        if (Platform.isWindows) {
          await Process.run(_system32('taskkill.exe'), ['/PID', '$pid', '/F']);
        } else {
          Process.killPid(pid, ProcessSignal.sigterm);
        }
      }
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Could not stop a listener: $e');
    }
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if ((await _listenerPids()).intersection(pids).isEmpty) return;
    }
  }

  Future<void> _rememberServer(Set<int> listenersBefore) async {
    if (_instanceLock == null) return;
    try {
      final pids = (await _listenerPids()).difference(listenersBefore);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_backendPidsKey, [for (final pid in pids) '$pid']);
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Could not record the backend: $e');
    }
  }

  Future<Set<int>> _ownLeftovers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recorded = {
        for (final pid in prefs.getStringList(_backendPidsKey) ?? const <String>[])
          if (int.tryParse(pid) case final value?) value,
      };
      if (recorded.isEmpty) return {};
      return (await _listenerPids()).intersection(recorded);
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Could not check for a leftover backend: $e');
      return {};
    }
  }

  bool _lockContended = false;

  static bool _contention(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == null) return true;
    if (Platform.isWindows) return code == 32 || code == 33;
    return code == 11 || code == 13 || code == 35;
  }

  Future<bool> _isSoleInstance() async {
    if (_instanceLock != null) return true;
    _lockContended = false;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = await File(p.join(dir.path, 'backend.lock')).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
      _instanceLock = file;
      return true;
    } on FileSystemException catch (error) {
      _lockContended = _contention(error);
      await file.close();
      return false;
    }
  }

  Future<bool> _isServerRunning() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('$url/'));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      await response.drain();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _findPythonPath(String projectRoot) async {
    final venvPaths = Platform.isWindows
        ? [
            p.join(projectRoot, 'venv', 'Scripts', 'python.exe'),
            p.join(projectRoot, '.venv', 'Scripts', 'python.exe'),
            p.join(projectRoot, 'env', 'Scripts', 'python.exe'),
          ]
        : [
            p.join(projectRoot, 'venv', 'bin', 'python3'),
            p.join(projectRoot, '.venv', 'bin', 'python3'),
            p.join(projectRoot, 'env', 'bin', 'python3'),
          ];
    for (final path in venvPaths) {
      if (File(path).existsSync()) {
        if (kDebugMode) print('FlaskServer: Found venv Python at $path');
        return path;
      }
    }

    final candidates =
        Platform.isWindows ? ['python', 'py'] : ['python3', 'python'];
    final locator = Platform.isWindows ? _system32('where.exe') : 'which';
    for (final cmd in candidates) {
      try {
        final result = await Process.run(
            locator, [Platform.isWindows ? '\$PATH:$cmd' : cmd]);
        if (result.exitCode == 0) {
          // `where` can return several lines; take the first hit.
          final path = (result.stdout as String)
              .trim()
              .split('\n')
              .first
              .trim();
          if (path.isNotEmpty) {
            final version = await Process.run(path, ['--version']);
            final versionStr =
                (version.stdout as String) + (version.stderr as String);
            if (versionStr.contains('Python 3')) {
              if (Platform.isWindows && cmd == 'py') {
                final interpreter = await _resolveLauncherInterpreter(path);
                if (interpreter != null) {
                  if (kDebugMode) {
                    print('FlaskServer: py launcher resolved to $interpreter');
                  }
                  return interpreter;
                }
              }
              if (kDebugMode) print('FlaskServer: Found system Python at $path');
              return path;
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _resolveLauncherInterpreter(String launcher) async {
    try {
      final result = await Process.run(
        launcher,
        ['-3', '-c', 'import sys; print(sys.executable)'],
      );
      final interpreter = (result.stdout as String).trim();
      if (result.exitCode == 0 &&
          interpreter.isNotEmpty &&
          File(interpreter).existsSync()) {
        return interpreter;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _syncPipDependencies(String root, String pythonPath) async {
    final reqFile = File(p.join(root, 'requirements.txt'));
    if (!reqFile.existsSync()) return;

    final hashFile = File(p.join(root, '.requirements_hash'));
    final currentHash = reqFile.readAsStringSync().hashCode.toString();
    if (hashFile.existsSync() &&
        hashFile.readAsStringSync().trim() == currentHash) {
      return;
    }

    if (kDebugMode) print('FlaskServer: Syncing pip dependencies...');
    try {
      // `python -m pip` works identically on every platform and avoids having
      // to locate a pip binary (which differs: bin/pip vs Scripts/pip.exe).
      final result = await Process.run(
        pythonPath,
        ['-m', 'pip', 'install', '-r', reqFile.path, '--quiet'],
        workingDirectory: root,
      );
      if (result.exitCode == 0) {
        hashFile.writeAsStringSync(currentHash);
        if (kDebugMode) print('FlaskServer: pip sync done');
      } else {
        if (kDebugMode) print('FlaskServer: pip sync failed: ${result.stderr}');
      }
    } catch (e) {
      if (kDebugMode) print('FlaskServer: pip sync error: $e');
    }
  }

  String? _findBundledBackend() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      if (Platform.isMacOS)
        p.join(exeDir.parent.path, 'Resources', 'backend'), // macOS .app/Contents/Resources
      p.join(exeDir.path, 'backend'), // Windows/Linux next to the executable
      p.join(exeDir.path, 'data', 'backend'), // Windows/Linux data dir
    ];
    for (final c in candidates) {
      if (File(p.join(c, 'app', 'app.py')).existsSync()) return c;
    }
    return null;
  }

  Future<bool> _extractBundledBackend() async {
    final bundlePath = _findBundledBackend();
    if (bundlePath == null) {
      if (kDebugMode) print('FlaskServer: No bundled backend found in app bundle');
      return false;
    }

    final home = _homeDir;
    if (home.isEmpty) return false;

    final dest = _defaultProjectPath;

    // NEVER overwrite an existing backend tree — it is the user's live,
    // possibly git-managed and uncommitted, source. Only extract on a fresh
    // install where no app/app.py exists yet.
    if (File(p.join(dest, 'app', 'app.py')).existsSync()) {
      if (kDebugMode) {
        print('FlaskServer: Backend already present at $dest, skipping extraction');
      }
      return true;
    }

    try {
      if (kDebugMode) {
        print('FlaskServer: Extracting backend from $bundlePath to $dest');
      }
      setupProgress.value = 'Backend wird kopiert...';

      Directory(dest).createSync(recursive: true);
      _copyDirectory(
          Directory(p.join(bundlePath, 'app')), Directory(p.join(dest, 'app')));

      final reqSrc = File(p.join(bundlePath, 'requirements.txt'));
      if (reqSrc.existsSync()) {
        reqSrc.copySync(p.join(dest, 'requirements.txt'));
      }

      final calSrc = File(p.join(bundlePath, 'calendar_sync.py'));
      if (calSrc.existsSync()) {
        calSrc.copySync(p.join(dest, 'calendar_sync.py'));
      }

      setupProgress.value = '';
      if (kDebugMode) print('FlaskServer: Backend extracted successfully');
      return true;
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Extract failed: $e');
      return false;
    }
  }

  // Cross-platform recursive directory copy (replaces the macOS-only `cp -R`).
  void _copyDirectory(Directory src, Directory dest) {
    dest.createSync(recursive: true);
    for (final entity in src.listSync(recursive: false)) {
      final name = p.basename(entity.path);
      final target = p.join(dest.path, name);
      if (entity is Directory) {
        _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }

  Future<String?> _resolveProjectRoot() async {
    final envRoot = _env('ROOT');
    if (envRoot != null && _hasAppPy(envRoot)) return envRoot;

    final home = _homeDir;
    if (home.isEmpty) return null;

    var dir = File(Platform.resolvedExecutable).parent;
    for (int i = 0; i < 10 && p.isWithin(home, dir.path); i++) {
      if (_hasAppPy(dir.path)) return dir.path;
      dir = dir.parent;
    }

    final fallback = _defaultProjectPath;
    if (_hasAppPy(fallback)) return fallback;

    return null;
  }

  bool _hasAppPy(String dir) {
    return File(p.join(dir, 'app', 'app.py')).existsSync();
  }

  Future<bool> _waitForServer({
    int maxRetries = 30,
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      await Future.delayed(interval);
      if (await _isServerRunning()) return true;

      if (_flaskProcess == null) return false;
    }
    return false;
  }

  Future<void> _killProcess() async {
    if (_flaskProcess == null) return;

    try {
      if (kDebugMode) print('FlaskServer: Sending SIGTERM');
      _flaskProcess!.kill(ProcessSignal.sigterm);

      final exited = await _flaskProcess!.exitCode
          .timeout(const Duration(seconds: 3), onTimeout: () => -1);

      if (exited == -1) {
        if (kDebugMode) print('FlaskServer: SIGTERM timeout, sending SIGKILL');
        _flaskProcess!.kill(ProcessSignal.sigkill);
      }
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Error killing process: $e');
    }

    _flaskProcess = null;
  }
}
