// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

enum LegacyImportOutcome { imported, skipped, failed, keyConflict, unclearOld, unclearNew }

class EnvEntry {
  const EnvEntry(this.value, this.line);

  final String value;
  final String line;
}

class LegacyImport {
  LegacyImport._();

  static const minimumSecretLength = 32;
  static const placeholderSecrets = {'your-secret-key-here', 'secret-key-change-me', 'changeme', 'please-change-me'};
  static const carriedSettings = {
    'SECRET_KEY': <String>{},
    'GOOGLE_CLIENT_ID': {'your-client-id.apps.googleusercontent.com'},
    'GOOGLE_CLIENT_SECRET': {'GOCSPX-your-client-secret'},
    'GOOGLE_PROJECT_ID': {'your-project-id'},
  };
  static const _marker = '.import-work';
  static const _dotenvScript = 'import json, sys\n'
      'from dotenv import dotenv_values\n'
      'print(json.dumps(dotenv_values(sys.argv[1])))\n';

  static String? findLegacyFolder({
    required String documents,
    required String target,
    required List<String> previousNames,
  }) {
    final targetData = p.join(target, 'data');
    if (FileSystemEntity.typeSync(targetData, followLinks: false) != FileSystemEntityType.notFound) return null;
    for (final name in previousNames) {
      final folder = p.join(documents, name);
      if (p.equals(folder, target)) continue;
      final data = p.join(folder, 'data');
      if (FileSystemEntity.typeSync(folder, followLinks: false) != FileSystemEntityType.directory) continue;
      if (FileSystemEntity.typeSync(data, followLinks: false) != FileSystemEntityType.directory) continue;
      if (Directory(data).listSync(followLinks: false).isEmpty) continue;
      return folder;
    }
    return null;
  }

  static bool acceptableSecret(String? key) =>
      key != null && key.length >= minimumSecretLength && !placeholderSecrets.contains(key.trim().toLowerCase());

  static bool providedValue(String key, String? value) {
    if (value == null || value.isEmpty || value.contains('�') || value.contains(r'${')) return false;
    if (carriedSettings[key]!.contains(value)) return false;
    return key != 'SECRET_KEY' || acceptableSecret(value);
  }

  static final _assignment = RegExp(r'^[ \t]*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_.\-]*)[ \t]*=[ \t]*(.*)$');
  static final _quotedKey = RegExp(r'''^[ \t]*(?:export[ \t]+)?['"]''');
  static final _trailer = RegExp(r'^[ \t]*(?:#.*)?$');

  static Map<String, EnvEntry> readEnvBytes(List<int> bytes, {bool strict = false}) {
    final bom = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
    return readEnv(utf8.decode(bom ? bytes.sublist(3) : bytes, allowMalformed: !strict), skipFirstLine: bom);
  }

  static Map<String, EnvEntry> readEnv(String text, {bool skipFirstLine = false}) {
    final entries = <String, EnvEntry>{};
    final lines = const LineSplitter().convert(text);
    for (var index = skipFirstLine ? 1 : 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.trimLeft().startsWith('#')) continue;
      final match = _assignment.firstMatch(line);
      if (match == null) continue;
      final value = _parseValue(match[2]!);
      if (value == null) continue;
      entries[match[1]!] = EnvEntry(value, line);
    }
    return entries;
  }

  static bool ambiguous(String text) {
    for (final line in const LineSplitter().convert(text)) {
      if (line.trimLeft().startsWith('#')) continue;
      if (_quotedKey.hasMatch(line)) return true;
      final match = _assignment.firstMatch(line);
      if (match != null && _unterminated(match[2]!)) return true;
    }
    return false;
  }

  static bool _unterminated(String raw) {
    if (!raw.startsWith("'") && !raw.startsWith('"')) return false;
    for (var index = 1; index < raw.length; index++) {
      if (raw[index] == '\\') {
        index++;
        continue;
      }
      if (raw[index] == raw[0]) return false;
    }
    return true;
  }

  static String? _parseValue(String raw) {
    if (raw.startsWith("'") || raw.startsWith('"')) {
      final quote = raw[0];
      final buffer = StringBuffer();
      for (var index = 1; index < raw.length; index++) {
        final char = raw[index];
        if (char == '\\' && index + 1 < raw.length) {
          final next = raw[index + 1];
          final escapes = quote == "'" ? const {'\\': '\\', "'": "'"} : const {'\\': '\\', "'": "'", '"': '"', 'a': '\x07', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v'};
          if (escapes.containsKey(next)) {
            buffer.write(escapes[next]);
            index++;
            continue;
          }
        }
        if (char == quote) return _trailer.hasMatch(raw.substring(index + 1)) ? buffer.toString() : null;
        buffer.write(char);
      }
      return null;
    }
    return raw.replaceFirst(RegExp(r'\s+#.*$'), '').trimRight();
  }

  static Future<Map<String, String?>?> dotenvValues(
    String python,
    String path, {
    required String workingDirectory,
    @visibleForTesting Duration timeout = const Duration(seconds: 20),
  }) async {
    Process? process;
    try {
      process = await Process.start(python, ['-I', '-c', _dotenvScript, path], workingDirectory: workingDirectory);
      final output = process.stdout.transform(utf8.decoder).join().catchError((Object _) => '');
      unawaited(process.stderr.drain<void>());
      final started = process;
      final code = await started.exitCode.timeout(timeout, onTimeout: () {
        started.kill(ProcessSignal.sigkill);
        return -1;
      });
      if (code != 0) return null;
      final decoded = jsonDecode((await output).trim());
      if (decoded is! Map) return null;
      return {for (final entry in decoded.entries) '${entry.key}': entry.value == null ? null : '${entry.value}'};
    } catch (_) {
      process?.kill(ProcessSignal.sigkill);
      return null;
    }
  }

  static String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  static Future<LegacyImportOutcome> copyInto({
    required String legacy,
    required String target,
    String? python,
    @visibleForTesting void Function(String target)? beforeMove,
  }) async {
    final targetData = p.join(target, 'data');
    final targetEnv = File(p.join(target, '.env'));
    Directory? staging;
    Directory? envWork;
    List<int>? originalBytes;
    var envReplaced = false;
    try {
      if (FileSystemEntity.typeSync(targetData, followLinks: false) != FileSystemEntityType.notFound) {
        return LegacyImportOutcome.skipped;
      }
      final legacyPath = p.join(legacy, '.env');
      final legacyExists = FileSystemEntity.typeSync(legacyPath, followLinks: false) == FileSystemEntityType.file;
      final legacyBytes = legacyExists ? File(legacyPath).readAsBytesSync() : <int>[];
      var legacyEntries = <String, EnvEntry>{};
      String? legacyText;
      if (legacyExists) {
        try {
          legacyEntries = readEnvBytes(legacyBytes, strict: true);
          legacyText = utf8.decode(legacyBytes);
        } on FormatException {
          legacyEntries = {};
        }
      }

      final envType = FileSystemEntity.typeSync(targetEnv.path, followLinks: false);
      if (envType != FileSystemEntityType.notFound && envType != FileSystemEntityType.file) return LegacyImportOutcome.failed;
      originalBytes = envType == FileSystemEntityType.file ? targetEnv.readAsBytesSync() : null;
      final targetEntries = originalBytes == null ? <String, EnvEntry>{} : readEnvBytes(originalBytes);

      final legacyTruth = python != null && legacyText != null ? await dotenvValues(python, legacyPath, workingDirectory: legacy) : null;
      final targetTruth = python != null && originalBytes != null ? await dotenvValues(python, targetEnv.path, workingDirectory: legacy) : null;
      final checked = python != null && (legacyTruth != null || legacyText == null) && (targetTruth != null || originalBytes == null);
      if (!checked && legacyText != null && ambiguous(legacyText)) return LegacyImportOutcome.unclearOld;
      if (!checked && originalBytes != null && ambiguous(_decode(originalBytes))) return LegacyImportOutcome.unclearNew;

      String? legacyValue(String key) => legacyText == null ? null : (checked ? (legacyTruth?[key]) : legacyEntries[key]?.value);
      String? targetValue(String key) => checked ? (targetTruth?[key]) : targetEntries[key]?.value;
      bool legacyProvides(String key) => providedValue(key, legacyValue(key)) && !(legacyEntries[key]?.line.contains(r'${') ?? false);

      if (legacyProvides('SECRET_KEY') && providedValue('SECRET_KEY', targetValue('SECRET_KEY')) &&
          legacyValue('SECRET_KEY') != targetValue('SECRET_KEY')) {
        return LegacyImportOutcome.keyConflict;
      }
      final added = <String, EnvEntry>{};
      for (final key in carriedSettings.keys) {
        if (!legacyProvides(key) || providedValue(key, targetValue(key))) continue;
        final entry = legacyEntries[key];
        if (entry == null || entry.value != legacyValue(key)) return LegacyImportOutcome.unclearOld;
        added[key] = entry;
      }

      Directory(target).createSync(recursive: true);
      cleanUp(target);
      staging = _workFolder(target, '.data-import-');
      final copied = Directory(p.join(staging.path, 'data'));
      _copyWithoutLinks(Directory(p.join(legacy, 'data')), copied);
      await _ownerOnly(staging.path);

      if (added.isNotEmpty) {
        envWork = _workFolder(target, '.env-import-');
        final original = originalBytes == null ? '' : _decode(originalBytes);
        final separator = original.isEmpty || original.endsWith('\n') ? '' : '\n';
        final pending = File(p.join(envWork.path, 'env'));
        pending.writeAsBytesSync([...?originalBytes, ...utf8.encode('$separator${added.values.map((entry) => entry.line).join('\n')}\n')], flush: true);
        await _ownerOnly(envWork.path);
        if (checked) {
          final result = await dotenvValues(python, pending.path, workingDirectory: legacy);
          final expected = {...?targetTruth, for (final key in added.keys) key: legacyValue(key)};
          if (result == null || !_sameValues(result, expected)) return LegacyImportOutcome.unclearNew;
        }
        final nowType = FileSystemEntity.typeSync(targetEnv.path, followLinks: false);
        final nowBytes = nowType == FileSystemEntityType.file ? targetEnv.readAsBytesSync() : null;
        if ((nowBytes == null) != (originalBytes == null) || (nowBytes != null && !_sameBytes(nowBytes, originalBytes!))) {
          throw const FileSystemException('.env wurde während der Übernahme geändert');
        }
        if (originalBytes != null) {
          File(p.join(envWork.path, 'original')).writeAsBytesSync(originalBytes, flush: true);
          await _ownerOnly(p.join(envWork.path, 'original'));
        }
        pending.renameSync(targetEnv.path);
        envReplaced = true;
      }

      beforeMove?.call(target);
      await _renameWithRetry(copied, targetData);
      return LegacyImportOutcome.imported;
    } catch (_) {
      if (envReplaced) {
        try {
          final backup = File(p.join(envWork!.path, 'original'));
          if (originalBytes != null && backup.existsSync()) {
            backup.renameSync(targetEnv.path);
          } else if (originalBytes == null && targetEnv.existsSync()) {
            targetEnv.deleteSync();
          }
        } catch (_) {}
      }
      return LegacyImportOutcome.failed;
    } finally {
      for (final folder in [staging, envWork]) {
        try {
          if (folder != null && folder.existsSync()) folder.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  static bool _sameValues(Map<String, String?> actual, Map<String, String?> expected) {
    if (actual.length != expected.length) return false;
    for (final entry in expected.entries) {
      if (!actual.containsKey(entry.key) || actual[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static Directory _workFolder(String target, String prefix) {
    final folder = Directory(target).createTempSync(prefix);
    File(p.join(folder.path, _marker)).writeAsStringSync('');
    return folder;
  }

  static final _workName = RegExp(
    r'^\.(?:data|env)-import-(?:[A-Za-z0-9]{6}|\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?)$',
  );

  static void cleanUp(String target) {
    if (FileSystemEntity.typeSync(target, followLinks: false) != FileSystemEntityType.directory) return;
    for (final entity in Directory(target).listSync(followLinks: false)) {
      if (entity is! Directory || !_workName.hasMatch(p.basename(entity.path))) continue;
      if (FileSystemEntity.typeSync(p.join(entity.path, _marker), followLinks: false) != FileSystemEntityType.file) continue;
      try {
        entity.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> _renameWithRetry(Directory source, String destination) async {
    for (var attempt = 1;; attempt++) {
      try {
        source.renameSync(destination);
        return;
      } on FileSystemException {
        if (!Platform.isWindows || attempt >= 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
  }

  static void _copyWithoutLinks(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(followLinks: false)) {
      if (entity is Link) continue;
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        _copyWithoutLinks(entity, Directory(target));
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }

  static Future<void> _ownerOnly(String path) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', ['-R', 'u=rwX,go=', path]);
    if (result.exitCode != 0) throw FileSystemException('chmod fehlgeschlagen', path);
  }
}
