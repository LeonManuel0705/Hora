// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';

import 'package:app/web_ui/ui_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scriptJson keeps a title from closing the script block', () {
    const value = {'titel': '</script><script>alert(1)</script> & <!-- \u2028\u2029'};
    final json = UiServer.scriptJson(value);
    for (final char in ['<', '>', '&', '\u2028', '\u2029']) {
      expect(json.contains(char), isFalse, reason: 'U+${char.codeUnitAt(0).toRadixString(16)}');
    }
    expect(jsonDecode(json), value);
  });

  test('scriptJson writes JSON escapes, not the characters', () {
    expect(UiServer.scriptJson('<>&\u2028\u2029'), r'"\u003c\u003e\u0026\u2028\u2029"');
  });
}
