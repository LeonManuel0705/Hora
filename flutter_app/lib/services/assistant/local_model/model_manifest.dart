// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

class ModelFile {
  const ModelFile({
    required this.repository,
    required this.revision,
    required this.fileName,
    required this.bytes,
    required this.sha256,
  });

  final String repository;
  final String revision;
  final String fileName;
  final int bytes;
  final String sha256;

  Uri get url => Uri.https('huggingface.co', '/$repository/resolve/$revision/$fileName');

  @override
  bool operator ==(Object other) =>
      other is ModelFile &&
      other.repository == repository &&
      other.revision == revision &&
      other.fileName == fileName &&
      other.bytes == bytes &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(repository, revision, fileName, bytes, sha256);
}

class ModelManifest {
  ModelManifest._();

  static const repository = 'unsloth/gemma-4-E2B-it-GGUF';
  static const revision = '0314792d7f1f7e229411f620751375812bb9faf2';

  static const standard = ModelFile(
    repository: repository,
    revision: revision,
    fileName: 'gemma-4-E2B-it-Q4_K_M.gguf',
    bytes: 3106738272,
    sha256: '740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8',
  );

  static const compact = ModelFile(
    repository: repository,
    revision: revision,
    fileName: 'gemma-4-E2B-it-Q3_K_M.gguf',
    bytes: 2536786016,
    sha256: '086e2f5ba85057f8f19712e3160a644728f74f323c9feeac4cd73fab11b43085',
  );

  static const standardMinMemory = 7000000000;
  static const compactMinMemory = 4500000000;

  static const all = [standard, compact];
}

enum ModelUnsupportedReason { memory, architecture, platform }

sealed class ModelChoice {
  const ModelChoice();
}

class ModelSupported extends ModelChoice {
  const ModelSupported(this.file);

  final ModelFile file;
}

class ModelUnsupported extends ModelChoice {
  const ModelUnsupported(this.reason);

  final ModelUnsupportedReason reason;
}

ModelChoice chooseModel({required int? totalMemory, required bool runtimeAvailable}) {
  if (!runtimeAvailable) return const ModelUnsupported(ModelUnsupportedReason.architecture);
  final memory = totalMemory ?? 0;
  if (memory >= ModelManifest.standardMinMemory) return const ModelSupported(ModelManifest.standard);
  if (memory >= ModelManifest.compactMinMemory) return const ModelSupported(ModelManifest.compact);
  return const ModelUnsupported(ModelUnsupportedReason.memory);
}
