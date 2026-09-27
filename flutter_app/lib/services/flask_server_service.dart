// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode;
import 'package:path/path.dart' as p;

import '../brand.dart';

enum FlaskServerState { idle, starting, ready, error, alreadyRunning }

enum SetupResult { success, brewNotFound, error, unsupportedPlatform }

class FlaskServerService {
  static final FlaskServerService _instance = FlaskServerService._internal();
  factory FlaskServerService() => _instance;
  FlaskServerService._internal();

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
  String get url => 'http://localhost:$port';

  String get _homeDir =>
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';

  String get _defaultProjectPath => p.join(_homeDir, 'Documents', Brand.name);

  Future<void> start() async {
    if (isReady) return;

    state.value = FlaskServerState.starting;
    _errorMessage = null;
    isPythonMissing = false;

    // 1. Reuse an already-running server. This works on every platform,
    //    including Windows/Linux where we may not be able to spawn Python
    //    ourselves — the user can start `python -m app.app` manually and the
    //    app will simply attach to it.
    if (await _isServerRunning()) {
      _externalServer = true;
      state.value = FlaskServerState.alreadyRunning;
      if (kDebugMode) {
        print('FlaskServer: Reusing already-running server on port $port');
      }
      return;
    }

    await _extractBundledBackend();

    // Clear a dead listener squatting the port (the health check above already
    // proved nothing healthy is answering, so this only removes a stuck one).
    await _killExistingServerOnPort();

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
  }) async {
    try {
      final process = await Process.start(executable, args);
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

  // Terminate only processes LISTENING on our port — never processes merely
  // connected to it (a browser tab, curl, the Electron wrapper). Guarded per
  // platform because lsof does not exist on Windows.
  Future<void> _killExistingServerOnPort() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('netstat', ['-ano']);
        final listener = RegExp(
          r'^\s*TCP\s+\S+:' '$port' r'\s+\S+\s+LISTENING\s+(\d+)\s*$',
          caseSensitive: false,
        );
        final pids = <int>{};
        for (final line in (result.stdout as String).split('\n')) {
          final match = listener.firstMatch(line.trimRight());
          if (match == null) continue;
          final pid = int.tryParse(match.group(1)!);
          if (pid != null && pid != 0) pids.add(pid);
        }
        for (final pid in pids) {
          if (kDebugMode) print('FlaskServer: taskkill listener $pid on port $port');
          await Process.run('taskkill', ['/PID', '$pid', '/F']);
        }
        if (pids.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } else {
        final result =
            await Process.run('lsof', ['-ti', 'tcp:$port', '-sTCP:LISTEN']);
        final pids = (result.stdout as String)
            .trim()
            .split('\n')
            .where((s) => s.isNotEmpty);
        for (final pid in pids) {
          final pidInt = int.tryParse(pid.trim());
          if (pidInt != null) {
            if (kDebugMode) {
              print('FlaskServer: Killing stale listener $pidInt on port $port');
            }
            Process.killPid(pidInt, ProcessSignal.sigterm);
          }
        }
        if (pids.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      if (kDebugMode) print('FlaskServer: Could not check for stale server: $e');
    }
  }

  Future<bool> _isServerRunning() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('http://localhost:$port/'));
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
    final locator = Platform.isWindows ? 'where' : 'which';
    for (final cmd in candidates) {
      try {
        final result = await Process.run(locator, [cmd]);
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
    final envRoot = Platform.environment['HUB_ROOT'];
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
