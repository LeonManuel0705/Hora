// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

enum LegacyImportOutcome { imported, skipped, failed, keyConflict }

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

  static final _assignment = RegExp(r'^[ \t]*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_.\-]*)[ \t]*=[ \t]*(.*)$');
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
      final raw = match[2]!;
      final value = _parseValue(raw);
      if (value == null) continue;
      entries[match[1]!] = EnvEntry(value, line);
    }
    return entries;
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

  static bool _provided(String key, EnvEntry? entry) {
    final value = entry?.value;
    if (value == null || value.isEmpty || entry!.line.contains('\uFFFD')) return false;
    if (value.contains(r'${')) return false;
    if (carriedSettings[key]!.contains(value)) return false;
    return key != 'SECRET_KEY' || acceptableSecret(value);
  }

  static String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

  static Map<String, EnvEntry> _legacyEntries(String legacy) {
    final path = p.join(legacy, '.env');
    if (FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.file) return {};
    try {
      return readEnvBytes(File(path).readAsBytesSync(), strict: true);
    } on FormatException {
      return {};
    }
  }

  static Future<LegacyImportOutcome> copyInto({
    required String legacy,
    required String target,
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
      final legacyEntries = _legacyEntries(legacy);
      final envType = FileSystemEntity.typeSync(targetEnv.path, followLinks: false);
      if (envType != FileSystemEntityType.notFound && envType != FileSystemEntityType.file) return LegacyImportOutcome.failed;
      originalBytes = envType == FileSystemEntityType.file ? targetEnv.readAsBytesSync() : null;
      final targetEntries = originalBytes == null ? <String, EnvEntry>{} : readEnvBytes(originalBytes);

      final legacyKey = legacyEntries['SECRET_KEY'];
      final targetKey = targetEntries['SECRET_KEY'];
      if (_provided('SECRET_KEY', legacyKey) && _provided('SECRET_KEY', targetKey) && legacyKey!.value != targetKey!.value) {
        return LegacyImportOutcome.keyConflict;
      }
      final added = [
        for (final key in carriedSettings.keys)
          if (_provided(key, legacyEntries[key]) && !_provided(key, targetEntries[key])) legacyEntries[key]!.line,
      ];

      Directory(target).createSync(recursive: true);
      cleanUp(target);
      staging = Directory(target).createTempSync('.data-import-');
      _copyWithoutLinks(Directory(p.join(legacy, 'data')), staging);
      await _ownerOnly(staging.path);

      if (added.isNotEmpty) {
        envWork = Directory(target).createTempSync('.env-import-');
        final original = originalBytes == null ? '' : _decode(originalBytes);
        final separator = original.isEmpty || original.endsWith('\n') ? '' : '\n';
        final pending = File(p.join(envWork.path, 'env'));
        pending.writeAsBytesSync([...?originalBytes, ...utf8.encode('$separator${added.join('\n')}\n')], flush: true);
        await _ownerOnly(pending.path);
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
      await _renameWithRetry(staging, targetData);
      staging = null;
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

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  static final _workName = RegExp(
    r'^\.(?:data|env)-import-(?:[A-Za-z0-9]{6}|\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?)$',
  );

  static void cleanUp(String target) {
    if (FileSystemEntity.typeSync(target, followLinks: false) != FileSystemEntityType.directory) return;
    for (final entity in Directory(target).listSync(followLinks: false)) {
      if (entity is! Directory || !_workName.hasMatch(p.basename(entity.path))) continue;
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
