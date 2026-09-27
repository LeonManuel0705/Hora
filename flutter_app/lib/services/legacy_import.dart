// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:path/path.dart' as p;

class LegacyImport {
  LegacyImport._();

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

  static Future<bool> copyInto({required String legacy, required String target}) async {
    final targetData = p.join(target, 'data');
    if (FileSystemEntity.typeSync(targetData, followLinks: false) != FileSystemEntityType.notFound) return false;
    final staging = Directory(p.join(target, '.data-import'));
    try {
      Directory(target).createSync(recursive: true);
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      _copyWithoutLinks(Directory(p.join(legacy, 'data')), staging);
      final legacyEnv = p.join(legacy, '.env');
      final targetEnv = File(p.join(target, '.env'));
      if (FileSystemEntity.typeSync(legacyEnv, followLinks: false) == FileSystemEntityType.file &&
          FileSystemEntity.typeSync(targetEnv.path, followLinks: false) == FileSystemEntityType.notFound) {
        File(legacyEnv).copySync(targetEnv.path);
        await _ownerOnly(targetEnv.path);
      }
      await _ownerOnly(staging.path);
      staging.renameSync(targetData);
      return true;
    } catch (_) {
      try {
        if (staging.existsSync()) staging.deleteSync(recursive: true);
      } catch (_) {}
      return false;
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
