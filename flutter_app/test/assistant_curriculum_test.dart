// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/assistant/curriculum.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await CurriculumService.instance.ensureLoaded();
  });

  group('formula lookup', () {
    for (final c in const [
      ['Was ist die Mitternachtsformel?', 'Mitternachtsformel'],
      ['Mitternachtsformel', 'Mitternachtsformel'],
      ['abc-Formel', 'Mitternachtsformel'],
      ['pq-Formel', 'pq-Formel'],
      ['Formel für Kreisfläche', 'Kreisfläche'],
      ['Formel für Kugelvolumen', 'Kugelvolumen'],
      ['Satz des Pythagoras', 'Pythagoras'],
      ['Binomische Formeln', 'Binomische Formeln'],
      ['Ableitung von sin(x)', 'sin'],
      ['Ableitung von cos', 'cos'],
      ['Ableitung von e^x', 'e^x'],
      ['Ableitung von ln x', 'ln'],
      ['Produktregel', 'Produktregel'],
      ['Kettenregel', 'Kettenregel'],
      ['Ohmsches Gesetz', 'Ohm'],
      ['Newton 2. Gesetz', 'Newton'],
      ['Hookesches Gesetz', 'Hooke'],
      ['Dichte', 'Dichte'],
      ['Formel für pH-Wert', 'pH'],
      ['Ideales Gasgesetz', 'Gas'],
      ['Skalarprodukt', 'Skalarprodukt'],
      ['Binomialverteilung', 'Binomialverteilung'],
      ['Wie berechnet man das Volumen einer Kugel?', 'Kugel'],
      ['Integral von x^2', 'Stammfunktion'],
      ['Bro ich brauch die Formel für den Kreis', 'Kreis'],
    ]) {
      test(c[0], () {
        final r = CurriculumService.instance.tryFormula(c[0]);
        expect(r, isNotNull, reason: 'no match for ${c[0]}');
        expect(r!.toLowerCase(), contains(c[1].toLowerCase()));
        expect(r, contains(r'$$'));
      });
    }

    test('rejects negation', () {
      expect(CurriculumService.instance.tryFormula('Kein Pythagoras'), isNull);
      expect(CurriculumService.instance.tryFormula('Nicht die pq-Formel bitte'), isNull);
      expect(CurriculumService.instance.tryFormula('Ich habe KEINE Lust auf Mitternachtsformel'), isNull);
    });

    test('question with trailing ignorance is NOT negated', () {
      expect(CurriculumService.instance.tryFormula('Was ist die Mitternachtsformel nochmal?'), isNotNull);
    });

    test('rejects chitchat', () {
      expect(CurriculumService.instance.tryFormula('Hallo'), isNull);
      expect(CurriculumService.instance.tryFormula('Was steht heute an?'), isNull);
    });
  });

  group('epoch lookup', () {
    for (final c in const [
      ['Was ist die Aufklärung?', 'Aufklärung'],
      ['Merkmale Sturm und Drang', 'Sturm und Drang'],
      ['Merkmale der Romantik', 'Romantik'],
      ['Wann war die Weimarer Klassik?', 'Klassik'],
      ['Expressionismus', 'Expressionismus'],
      ['Erklär mir den Barock', 'Barock'],
    ]) {
      test(c[0], () {
        final r = CurriculumService.instance.tryEpoche(c[0]);
        expect(r, isNotNull);
        expect(r, contains(c[1]));
      });
    }
    test('negated chitchat ignored', () {
      expect(CurriculumService.instance.tryEpoche('Ich mag die Romantik nicht'), isNull);
    });
  });

  group('werk lookup', () {
    for (final c in const [
      ['Wer schrieb Faust?', 'Goethe'],
      ['Wer hat Die Verwandlung geschrieben?', 'Kafka'],
      ['Autor von Der Prozess', 'Kafka'],
      ['Worum geht es in Effi Briest?', 'Fontane'],
      ['Wer schrieb Kabale und Liebe?', 'Schiller'],
      ['Handlung von Woyzeck', 'Büchner'],
      ['autor der verwandlung', 'Kafka'],
      ['wer hat Faust geschrieben', 'Goethe'],
    ]) {
      test(c[0], () {
        final r = CurriculumService.instance.tryWerk(c[0]);
        expect(r, isNotNull);
        expect(r, contains(c[1]));
      });
    }
    test('bare title without intent returns null', () {
      expect(CurriculumService.instance.tryWerk('Faust'), isNull);
    });
  });

  group('topics lookup', () {
    test('grade 11 physics', () {
      final r = CurriculumService.instance.tryTopics(
        'Was sind die Themen in der 11. Klasse am Gymnasium im Physik Grundkurs?',
      );
      expect(r, isNotNull);
      expect(r, contains('Klasse 11'));
      expect(r, contains('Feld'));
    });
    test('grade 9 mathe', () {
      final r = CurriculumService.instance.tryTopics('Themen in der 9. Klasse Mathe');
      expect(r, contains('Mitternachtsformel'));
    });
    test('grade only', () {
      final r = CurriculumService.instance.tryTopics('Welche Themen lernen wir in Klasse 9?');
      expect(r, contains('Klasse 9'));
      expect(r, contains('Mathe'));
    });
    test('invalid grade returns null', () {
      expect(CurriculumService.instance.tryTopics('Themen in Klasse 99'), isNull);
      expect(CurriculumService.instance.tryTopics('Themen in Klasse 0'), isNull);
      expect(CurriculumService.instance.tryTopics('Themen in Klasse 14'), isNull);
    });
    test('requires intent', () {
      expect(CurriculumService.instance.tryTopics('Klasse 11 ist anstrengend'), isNull);
    });

    for (var g = 1; g <= 13; g++) {
      test('every grade $g has data', () {
        final r = CurriculumService.instance.tryTopics('Welche Themen lernen wir in Klasse $g?');
        expect(r, isNotNull, reason: 'Klasse $g missing');
        expect(r, contains('Klasse $g'));
      });
    }

    for (final c in const [
      ['Themen Klasse 1 Deutsch', 'Buchstaben'],
      ['Themen Klasse 2 Mathe', 'Einmaleins'],
      ['Themen Klasse 3 Sachunterricht', 'Bundesland'],
      ['Themen Klasse 4 Englisch', 'Past'],
      ['Themen Klasse 5 Biologie', 'Wirbel'],
      ['Themen Klasse 6 Französisch', 'Présent'],
      ['Themen Klasse 6 Latein', 'Deklination'],
      ['Themen Klasse 7 Politik', 'Demokratie'],
      ['Themen Klasse 8 Informatik', 'Python'],
      ['Themen Klasse 9 Religion', 'Theodizee'],
      ['Themen Klasse 10 Ethik', 'Verantwortung'],
      ['Themen Klasse 11 Philosophie', 'Erkenntnis'],
      ['Themen Klasse 11 Psychologie', 'Wahrnehmung'],
      ['Themen Klasse 11 Wirtschaft', 'Markt'],
      ['Themen Klasse 12 Pädagogik', 'Erziehung'],
      ['Themen Klasse 12 Kunst', 'Bauhaus'],
      ['Themen Klasse 13 Sport', 'Bewegungslehre'],
      ['Inhalte Klasse 11 Spanisch', 'Lateinamerika'],
      ['Themen Klasse 5 Sport', 'Leichtathletik'],
      ['Themen Klasse 8 Musik', 'Klassik'],
    ]) {
      test('subject lookup: ${c[0]}', () {
        final r = CurriculumService.instance.tryTopics(c[0]);
        expect(r, isNotNull, reason: '${c[0]}: no match');
        expect(r, contains(c[1]));
      });
    }
  });

  group('concept lookup', () {
    for (final c in const [
      ['Was ist Photosynthese?', 'Chloroplast'],
      ['Erkläre mir die Mitose', 'Tochterzellen'],
      ['Was bedeutet DNA?', 'Erbinformation'],
      ['Was ist eine Metapher?', 'Sprachliches Bild'],
      ['Was ist eine Anapher?', 'Wiederholung'],
      ['Erkläre die Französische Revolution', '1789'],
      ['Was war der Erste Weltkrieg?', '1914'],
      ['Was ist der Holocaust?', 'sechs Millionen'],
      ['Was ist Stetigkeit?', 'lim'],
      ['Was ist eine Kurvendiskussion?', 'Definitionsbereich'],
      ['Was ist ein Wendepunkt?', 'Krümmung'],
      ['Was ist ein Atom?', 'Atomkern'],
      ['Was ist eine Säure?', 'Protonen'],
      ['Was ist Subjonctif?', 'Modus'],
      ['Was ist AcI?', 'Akkusativ'],
      ['Was ist Demokratie?', 'Volkssouveränität'],
      ['Was ist das Grundgesetz?', '1949'],
      ['Was ist Theodizee?', 'Leid'],
      ['Was ist Plattentektonik?', 'Lithosphären'],
      ['Was ist Klimawandel?', 'CO'],
      ['Was ist Energie?', 'Joule'],
      ['Was ist eine Synapse?', 'Neurotransmitter'],
    ]) {
      test('concept: ${c[0]}', () {
        final r = CurriculumService.instance.tryConcept(c[0]);
        expect(r, isNotNull, reason: 'no match: ${c[0]}');
        expect(r, contains(c[1]));
      });
    }

    test('negation blocks concept', () {
      expect(CurriculumService.instance.tryConcept('Ich habe keine Lust auf Photosynthese'), isNull);
    });
  });

  group('router tryCurriculum', () {
    test('formula wins over werk for Mitternachtsformel', () {
      final r = CurriculumService.instance.tryCurriculum('Was ist die pq-Formel?');
      expect(r, contains('pq-Formel'));
      expect(r, contains(r'$$'));
    });
    test('werk for Wer schrieb Faust', () {
      final r = CurriculumService.instance.tryCurriculum('Wer schrieb Faust?');
      expect(r, contains('Goethe'));
    });
    test('topics for Klasse 12 Deutsch', () {
      final r = CurriculumService.instance.tryCurriculum('Themen in Klasse 12 Deutsch');
      expect(r, contains('Klasse 12'));
    });
    test('casual chat returns null', () {
      for (final q in const ['Hallo', '2+2', 'Was steht heute an?', 'foo bar baz']) {
        expect(CurriculumService.instance.tryCurriculum(q), isNull, reason: q);
      }
    });
  });
}
