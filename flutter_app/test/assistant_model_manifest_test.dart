// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:app/brand.dart';
import 'package:app/services/assistant/local_model/assistant_prompt.dart';
import 'package:app/services/assistant/local_model/model_downloader.dart';
import 'package:app/services/assistant/local_model/model_format.dart';
import 'package:app/services/assistant/local_model/model_manifest.dart';
import 'package:app/services/assistant/local_model/model_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model choice', () {
    ModelChoice pick(int? memory, {bool runtime = true}) => chooseModel(totalMemory: memory, runtimeAvailable: runtime);

    test('eight and more gigabytes get the Q4_K_M file', () {
      expect((pick(7811784704) as ModelSupported).file, ModelManifest.standard);
      expect((pick(12000000000) as ModelSupported).file, ModelManifest.standard);
      expect((pick(7000000000) as ModelSupported).file, ModelManifest.standard);
    });

    test('six gigabyte phones get the Q3_K_M file', () {
      expect((pick(6999999999) as ModelSupported).file, ModelManifest.compact);
      expect((pick(5700000000) as ModelSupported).file, ModelManifest.compact);
      expect((pick(4500000000) as ModelSupported).file, ModelManifest.compact);
    });

    test('below 4.5 GB the phone is not supported', () {
      expect((pick(4499999999) as ModelUnsupported).reason, ModelUnsupportedReason.memory);
      expect((pick(3700000000) as ModelUnsupported).reason, ModelUnsupportedReason.memory);
      expect((pick(null) as ModelUnsupported).reason, ModelUnsupportedReason.memory);
    });

    test('without a runtime for the CPU nothing is offered', () {
      expect((pick(12000000000, runtime: false) as ModelUnsupported).reason, ModelUnsupportedReason.architecture);
    });

    test('the manifest stays pinned', () {
      expect(ModelManifest.standard.bytes, 3106738272);
      expect(ModelManifest.standard.sha256, '740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8');
      expect(ModelManifest.compact.bytes, 2536786016);
      expect(ModelManifest.compact.sha256, '086e2f5ba85057f8f19712e3160a644728f74f323c9feeac4cd73fab11b43085');
      expect(
        ModelManifest.standard.url.toString(),
        'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/'
        '0314792d7f1f7e229411f620751375812bb9faf2/gemma-4-E2B-it-Q4_K_M.gguf',
      );
    });
  });

  group('formatting', () {
    test('progress line reads like the design', () {
      const progress = DownloadProgress(received: 1200000000, total: 3106738272, bytesPerSecond: 8400000);
      expect(formatProgress(progress), '1,2 von 3,1\u00a0GB · 8,4\u00a0MB/s · noch etwa 4\u00a0Min.');
    });

    test('sizes, speeds and times', () {
      expect(formatBytes(3106738272), '3,1\u00a0GB');
      expect(formatBytes(41300000000), '41\u00a0GB');
      expect(formatBytes(2536786016), '2,5\u00a0GB');
      expect(formatMissing(1400000000), '1,4\u00a0GB');
      expect(formatMissing(1310000000), '1,4\u00a0GB');
      expect(formatSpeed(870000), '0,9\u00a0MB/s');
      expect(formatRemaining(const Duration(seconds: 40)), 'noch weniger als 1\u00a0Min.');
      expect(formatRemaining(const Duration(minutes: 75)), 'noch etwa 1\u00a0Std. 15\u00a0Min.');
    });

    test('while checking a resumed file no speed is shown', () {
      const progress = DownloadProgress(received: 500000000, total: 3106738272, checking: true);
      expect(formatProgress(progress), '0,5 von 3,1\u00a0GB');
    });
  });

  group('load settings', () {
    test('iPhones with room use the GPU with the full context', () {
      final settings = settingsFor(level: 0, gpuPreferred: true, modelBytes: 3106738272, availableMemory: 5000000000);
      expect(settings.gpu, isTrue);
      expect(settings.contextSize, 4096);
    });

    test('tight memory or a previous crash fall back to a small CPU context', () {
      expect(settingsFor(level: 0, gpuPreferred: true, modelBytes: 3106738272, availableMemory: 3000000000).gpu, isFalse);
      final tight = settingsFor(level: 0, gpuPreferred: false, modelBytes: 3106738272, availableMemory: 1500000000);
      expect(tight.contextSize, 2048);
      final crashed = settingsFor(level: 1, gpuPreferred: true, modelBytes: 2536786016);
      expect(crashed.gpu, isFalse);
      expect(crashed.contextSize, 2048);
    });

    test('Android always runs on the CPU with the full context when memory allows', () {
      final settings = settingsFor(level: 0, gpuPreferred: false, modelBytes: 3106738272, availableMemory: 4000000000);
      expect(settings.gpu, isFalse);
      expect(settings.contextSize, 4096);
    });
  });

  group('system prompt', () {
    test('describes the day, the week, lessons, deadlines and tasks', () {
      final text = describeAssistantContext(AssistantContextData(
        now: DateTime(2026, 9, 28, 14, 5),
        week: 'A',
        lessons: const ['1. Block (8:00 bis 9:30): Mathe LK, Raum 204'],
        deadlines: const ['Klausur Mathe LK: Vektoren am Do 01.10.'],
        tasks: const ['Referat vorbereiten (fällig Fr 02.10.)'],
      ));
      expect(text, contains('Heute ist Montag, der 28. September 2026, 14:05 Uhr.'));
      expect(text, contains('Diese Woche ist A-Woche.'));
      expect(text, contains('- 1. Block (8:00 bis 9:30): Mathe LK, Raum 204'));
      expect(text, contains('- Klausur Mathe LK: Vektoren am Do 01.10.'));
      expect(text, contains('- Referat vorbereiten (fällig Fr 02.10.)'));
    });

    test('says so when the weekend or nothing is planned', () {
      final text = describeAssistantContext(AssistantContextData(now: DateTime(2026, 10, 3, 9)));
      expect(text, contains('Wochenende'));
      expect(text, contains('keine Klausuren, Tests oder Hausaufgaben'));
    });

    test('keeps the instructions short, German and without dashes', () {
      final prompt = buildAssistantSystemPrompt('Heute ist Montag.');
      expect(prompt, contains(Brand.name));
      expect(prompt, contains('Antworte immer auf Deutsch'));
      expect(prompt, endsWith('Heute ist Montag.'));
      expect(prompt.contains('—'), isFalse);
      expect(prompt.length, lessThan(1000));
    });
  });
}
