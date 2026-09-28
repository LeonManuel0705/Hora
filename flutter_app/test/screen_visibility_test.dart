// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:app/widgets/screen_visibility.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screen visibility', () {
    Widget lease(bool? visible, List<String> events) {
      final child = VisibilityLease(
        onShow: () => events.add('show'),
        onHide: () => events.add('hide'),
        child: const SizedBox(),
      );
      return visible == null ? child : ScreenVisibility(visible: visible, child: child);
    }

    testWidgets('a pushed screen counts as visible until it is closed', (tester) async {
      final events = <String>[];
      await tester.pumpWidget(lease(null, events));
      expect(events, ['show']);
      await tester.pumpWidget(const SizedBox());
      expect(events, ['show', 'hide']);
    });

    testWidgets('a tab in the classic layout follows the selected tab', (tester) async {
      final events = <String>[];
      await tester.pumpWidget(lease(false, events));
      expect(events, isEmpty);
      await tester.pumpWidget(lease(true, events));
      expect(events, ['show']);
      await tester.pumpWidget(lease(false, events));
      expect(events, ['show', 'hide']);
      await tester.pumpWidget(const SizedBox());
      expect(events, ['show', 'hide']);
    });
  });
}
