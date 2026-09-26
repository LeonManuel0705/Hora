// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/tutorial/tinte.dart';
import 'package:app/tutorial/tutorial.dart';

void main() {
  group('TinteRig', () {
    test('runs every motion without throwing', () {
      final rig = TinteRig(size: 120, random: math.Random(1))..origin = const Offset(100, 100);
      for (final mode in TinteMode.values) {
        if (mode == TinteMode.bye) continue;
        rig.setMode(mode, target: const Offset(20, 160));
        for (var i = 0; i < 120; i++) {
          rig.step(1 / 30);
        }
      }
      rig.moving = true;
      rig.velocity = const Offset(600, -200);
      for (var i = 0; i < 30; i++) {
        rig.step(1 / 30);
      }
      rig.say('Hallo, ich bin Tinte');
      rig.excite();
      for (var i = 0; i < 30; i++) {
        rig.step(1 / 30);
      }
    });

    test('says goodbye and disappears', () async {
      final rig = TinteRig(size: 96, random: math.Random(2));
      var done = false;
      rig.bye().then((_) => done = true);
      for (var i = 0; i < 4 * 30 && !done; i++) {
        rig.step(1 / 30);
        await Future<void>.delayed(Duration.zero);
      }
      expect(done, isTrue);
      expect(rig.gone, isTrue);
    });

    test('returns to floating after the somersault', () {
      final rig = TinteRig(random: math.Random(3));
      rig.setMode(TinteMode.cheer);
      for (var i = 0; i < 3 * 30; i++) {
        rig.step(1 / 30);
      }
      expect(rig.mode, TinteMode.float);
    });

    test('points with the arm on the side of the target', () {
      final rig = TinteRig(size: 100, random: math.Random(4))..origin = const Offset(200, 200);
      rig.setMode(TinteMode.point, target: const Offset(20, 240));
      expect(rig.side, -1);
      rig.setMode(TinteMode.point, target: const Offset(520, 240));
      expect(rig.side, 1);
    });
  });

  group('Tutorial', () {
    Widget app() => MaterialApp(
          navigatorObservers: [Tutorial.observer],
          builder: (context, child) => TutorialHost(child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('Inhalt')),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  height: 64,
                  child: Row(
                    key: Tutorial.key('nav'),
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final id in ['nav-0', 'nav-1', 'nav-3', 'nav-2', 'nav-more'])
                        SizedBox(key: Tutorial.key(id), width: 56, height: 56),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('greets, walks on and remembers a skip', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      Tutorial.start();
      await settle(tester);
      expect(Tutorial.running, isTrue);
      expect(find.text('Los geht’s'), findsOneWidget);
      expect(find.byType(TinteView), findsOneWidget);

      await tester.tap(find.text('Los geht’s'));
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp('Unten findest du')), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Tutorial beenden'));
      await settle(tester);
      expect(Tutorial.running, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(Tutorial.prefsKey), 'skipped');
    });

    testWidgets('does not start again once it ran', (tester) async {
      SharedPreferences.setMockInitialValues({Tutorial.prefsKey: 'done'});
      await tester.pumpWidget(app());
      await Tutorial.startIfNew();
      await settle(tester);
      expect(Tutorial.running, isFalse);
    });

    testWidgets('stays still with reduced motion', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
        child: app(),
      ));
      Tutorial.start();
      await settle(tester);
      expect(find.text('Los geht’s'), findsOneWidget);
      await tester.tap(find.text('Später'));
      await settle(tester);
      expect(Tutorial.running, isFalse);
    });
  });
}
