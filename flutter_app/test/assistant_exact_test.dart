// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:app/services/assistant/assistant_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final engine = AssistantEngine.instance;
  final lovelace = {
    'title': 'Ada Lovelace',
    'extract': 'Ada Lovelace war eine britische Mathematikerin.',
    'url': 'https://de.wikipedia.org/wiki/Ada_Lovelace',
    'disambiguation': false,
  };

  group('questions for the on-device model', () {
    test('SQL words in a question are fine, the model has no database', () async {
      for (final question in const [
        'Was macht INSERT INTO in SQL?',
        'Wofür braucht man DELETE FROM?',
        'Erklär mir ALTER TABLE',
      ]) {
        final answer = await engine.answerExact(question);
        expect(answer?.text ?? '', isNot(contains('normale Frage')), reason: question);
      }
    });

    test('online, people and terms come from Wikipedia as before', () async {
      final asked = <String>[];
      final answer = await engine.answerExact('Wer war Ada Lovelace?', online: true, lookup: (entity) async {
        asked.add(entity);
        return lovelace;
      });
      expect(asked, ['Ada Lovelace']);
      expect(answer?.source, AssistantSource.wikipedia);
      expect(answer?.online, isTrue);
      expect(answer?.text, contains('britische Mathematikerin'));
      expect(answer?.text, contains('https://de.wikipedia.org/wiki/Ada_Lovelace'));
    });

    test('offline the question goes to the model and nothing is looked up', () async {
      final answer = await engine.answerExact('Wer war Ada Lovelace?', online: false, lookup: (entity) async {
        fail('no lookup offline');
      });
      expect(answer, isNull);
    });

    test('without a Wikipedia article the model answers', () async {
      final answer = await engine.answerExact('Wer war Ada Lovelace?', online: true, lookup: (_) async => null);
      expect(answer, isNull);
    });

    test('tasks never trigger a lookup', () async {
      final answer = await engine.answerExact('Schreib mir eine Zusammenfassung über Ada Lovelace', online: true,
          lookup: (entity) async {
        fail('no lookup for tasks');
      });
      expect(answer, isNull);
    });
  });
}
