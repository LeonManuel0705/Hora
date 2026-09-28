// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/foundation.dart';

import 'model_manifest.dart';

const _override = String.fromEnvironment('ASSISTANT_DEBUG_MODEL');

const _tinyRepository = 'unsloth/SmolLM2-135M-Instruct-GGUF';
const _tinyRevision = '9e6855bc4be717fca1ef21360a1db4b29d5c559a';

const _tiny = ModelFile(
  repository: _tinyRepository,
  revision: _tinyRevision,
  fileName: 'SmolLM2-135M-Instruct-Q4_K_M.gguf',
  bytes: 105454144,
  sha256: 'ed5fa30c487b282ec156c29062f1222e5c20875a944ac98289dbd242e947f747',
);

ModelChoice? debugModelChoice({int? freeBytes, String? override}) {
  if (!kDebugMode) return null;
  final name = override ?? _override;
  if (name.isEmpty) return null;
  switch (name) {
    case 'tiny':
      return const ModelSupported(_tiny);
    case 'tiny-broken':
      return ModelSupported(ModelFile(
        repository: _tiny.repository,
        revision: _tiny.revision,
        fileName: _tiny.fileName,
        bytes: _tiny.bytes,
        sha256: '0' * 64,
      ));
    case 'not-gguf':
      return const ModelSupported(ModelFile(
        repository: _tinyRepository,
        revision: _tinyRevision,
        fileName: 'README.md',
        bytes: 4567,
        sha256: 'b464dc4a9ff26fea06ec45165546bbeb0c32b1a7847babcef048d5b84486ed84',
      ));
    case 'oversized':
      return ModelSupported(ModelFile(
        repository: _tiny.repository,
        revision: _tiny.revision,
        fileName: _tiny.fileName,
        bytes: (freeBytes ?? 0) + 1100 * 1000 * 1000,
        sha256: _tiny.sha256,
      ));
    case 'unsupported':
      return const ModelUnsupported(ModelUnsupportedReason.memory);
    case 'unsupported-cpu':
      return const ModelUnsupported(ModelUnsupportedReason.architecture);
  }
  return null;
}
