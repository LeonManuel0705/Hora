// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/assistant/offline_tools.dart' as tools;

void main() {
  group('math', () {
    for (final c in const [
      ['2+2', '4'],
      ['3 * (4+5)', '27'],
      ['Berechne 15 * 7', '105'],
      ['Was ist 100 / 4?', '25'],
      ['7 mal 8', '56'],
      ['20 minus 5', '15'],
      ['50 durch 4', '12,5'],
      ['2 hoch 10', '1024'],
      ['15% von 200', '30'],
      ['wurzel aus 16', '4'],
      ['Wurzel aus 144', '12'],
      ['sqrt(144)', '12'],
      ['was ergibt 3 hoch 4', '81'],
      ['ich rechne 15 durch 3', '5'],
      ['2+2 🙂', '4'],
    ]) {
      test(c[0], () {
        final r = tools.tryCalc(c[0]);
        expect(r, isNotNull, reason: 'no match for ${c[0]}');
        expect(r, contains(c[1]));
      });
    }

    test('division by zero explicit', () {
      expect(tools.tryCalc('10 durch 0'), contains('nicht definiert'));
    });
    test('rejects text', () => expect(tools.tryCalc('Wer ist Einstein?'), isNull));
    test('rejects code injection', () {
      expect(tools.tryCalc('__import__("os")'), isNull);
      expect(tools.tryCalc('eval("2+2")'), isNull);
    });
  });

  group('dates', () {
    final fixed = DateTime(2026, 4, 23);

    test('today', () {
      final r = tools.tryDateMath('Welcher Wochentag ist heute?', now: fixed);
      expect(r, contains('Heute ist'));
    });
    test('tomorrow', () {
      final r = tools.tryDateMath('Welcher Wochentag ist morgen?', now: fixed);
      expect(r, contains('Morgen ist'));
    });
    test('specific date', () {
      final r = tools.tryDateMath('Welcher Wochentag ist der 24.12.2026?', now: fixed);
      expect(r, contains('24.12.2026'));
      expect(r, contains('Donnerstag'));
    });
    test('tag der woche variant', () {
      final r = tools.tryDateMath('welcher tag der woche ist der 01.01.2030', now: fixed);
      expect(r, contains('01.01.2030'));
    });
    test('days until', () {
      final r = tools.tryDateMath('Wie viele Tage bis zum 01.06.2027?', now: fixed);
      expect(r, anyOf(contains('Tage'), contains('heute')));
    });
    test('time bare', () => expect(tools.tryDateMath('Uhrzeit', now: fixed), contains('Uhr')));
    test('time question', () => expect(tools.tryDateMath('Wie spät', now: fixed), contains('Uhr')));
    test('invalid date returns null', () {
      expect(tools.tryDateMath('welcher tag ist der 32.13.2026', now: fixed), isNull);
    });
  });

  group('units', () {
    for (final c in const [
      ['100 km in meilen', '62'],
      ['20 grad celsius in fahrenheit', '68'],
      ['0 C in F', '32'],
      ['1 kg in pfund', '2,2'],
      ['100 F in C', '37'],
      ['-40 C in F', '-40'],
      ['-40 F in C', '-40'],
      ['5 meter in fuß', '16,4'],
      ['3 pound in kg', '1,3'],
      ['100 miles in km', '160'],
    ]) {
      test(c[0], () {
        final r = tools.tryUnitConvert(c[0]);
        expect(r, isNotNull, reason: 'no conversion for ${c[0]}');
        expect(r, contains(c[1]));
      });
    }
    test('unknown unit returns null', () {
      expect(tools.tryUnitConvert('5 banana in apfel'), isNull);
    });
  });

  group('dispatcher tryOfflineTool', () {
    test('dispatches math', () => expect(tools.tryOfflineTool('2+2'), contains('4')));
    test('dispatches unit', () => expect(tools.tryOfflineTool('100 km in meilen'), contains('62')));
    test('casual chat returns null', () {
      for (final q in const [
        'Heute war schön', 'Ich habe Hunger', 'Mathe macht Spaß',
      ]) {
        expect(tools.tryOfflineTool(q), isNull, reason: q);
      }
    });
    test('huge input safely rejected', () => expect(tools.tryOfflineTool('x' * 2000), isNull));
  });
}
