// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:path/path.dart' as p;

enum LegacyImportOutcome { imported, skipped, failed, keyConflict }

class LegacyImport {
  LegacyImport._();

  static const carriedSettings = ['SECRET_KEY', 'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_PROJECT_ID'];
  static const minimumSecretLength = 32;
  static const placeholderSecrets = {'your-secret-key-here', 'secret-key-change-me', 'changeme', 'please-change-me'};

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

  static Map<String, String> readSettings(String text) {
    final values = <String, String>{};
    final line = RegExp(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$');
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final match = line.firstMatch(raw);
      if (match == null || raw.trimLeft().startsWith('#')) continue;
      var value = match[2]!;
      if (value.length >= 2 && (value[0] == '"' || value[0] == "'") && value.endsWith(value[0])) {
        value = value.substring(1, value.length - 1);
      } else {
        value = value.replaceFirst(RegExp(r'\s+#.*$'), '');
      }
      values[match[1]!] = value;
    }
    return values;
  }

  static String _settingLine(String key, String value) =>
      RegExp(r'^[A-Za-z0-9_.:/@+-]*$').hasMatch(value) ? '$key=$value' : '$key="${value.replaceAll('"', r'\"')}"';

  static Future<LegacyImportOutcome> copyInto({required String legacy, required String target}) async {
    final targetData = p.join(target, 'data');
    if (FileSystemEntity.typeSync(targetData, followLinks: false) != FileSystemEntityType.notFound) {
      return LegacyImportOutcome.skipped;
    }

    final legacyEnv = p.join(legacy, '.env');
    final legacySettings = FileSystemEntity.typeSync(legacyEnv, followLinks: false) == FileSystemEntityType.file
        ? readSettings(File(legacyEnv).readAsStringSync())
        : <String, String>{};
    final carried = <String, String>{
      for (final key in carriedSettings)
        if (legacySettings[key] != null && legacySettings[key]!.isNotEmpty) key: legacySettings[key]!,
    };
    if (!acceptableSecret(carried['SECRET_KEY'])) carried.remove('SECRET_KEY');

    final targetEnv = File(p.join(target, '.env'));
    final envType = FileSystemEntity.typeSync(targetEnv.path, followLinks: false);
    if (envType != FileSystemEntityType.notFound && envType != FileSystemEntityType.file) return LegacyImportOutcome.failed;
    final originalEnv = envType == FileSystemEntityType.file ? targetEnv.readAsStringSync() : null;
    final targetSettings = originalEnv == null ? <String, String>{} : readSettings(originalEnv);
    final targetKey = targetSettings['SECRET_KEY'];
    if (carried.containsKey('SECRET_KEY') && targetKey != null && targetKey.isNotEmpty && targetKey != carried['SECRET_KEY']) {
      return LegacyImportOutcome.keyConflict;
    }
    final missing = {
      for (final entry in carried.entries)
        if (!targetSettings.containsKey(entry.key)) entry.key: entry.value,
    };

    Directory? staging;
    var envTouched = false;
    try {
      Directory(target).createSync(recursive: true);
      _removeStaleStaging(target);
      staging = Directory(target).createTempSync('.data-import-');
      _copyWithoutLinks(Directory(p.join(legacy, 'data')), staging);
      await _ownerOnly(staging.path);
      if (missing.isNotEmpty) {
        final lines = missing.entries.map((entry) => _settingLine(entry.key, entry.value)).join('\n');
        final prefix = originalEnv == null || originalEnv.isEmpty || originalEnv.endsWith('\n') ? (originalEnv ?? '') : '$originalEnv\n';
        envTouched = true;
        targetEnv.writeAsStringSync('$prefix$lines\n', flush: true);
        await _ownerOnly(targetEnv.path);
      }
      await _renameWithRetry(staging, targetData);
      return LegacyImportOutcome.imported;
    } catch (_) {
      try {
        if (staging != null && staging.existsSync()) staging.deleteSync(recursive: true);
      } catch (_) {}
      if (envTouched) {
        try {
          if (originalEnv == null) {
            if (targetEnv.existsSync()) targetEnv.deleteSync();
          } else {
            targetEnv.writeAsStringSync(originalEnv, flush: true);
          }
        } catch (_) {}
      }
      return LegacyImportOutcome.failed;
    }
  }

  static void _removeStaleStaging(String target) {
    for (final entity in Directory(target).listSync(followLinks: false)) {
      if (entity is! Directory || !p.basename(entity.path).startsWith('.data-import-')) continue;
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
