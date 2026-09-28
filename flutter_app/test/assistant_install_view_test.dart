// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:app/screens/assistant_install_view.dart';
import 'package:app/services/assistant/local_model/model_downloader.dart';
import 'package:app/services/assistant/local_model/model_installer.dart';
import 'package:app/services/assistant/local_model/model_manifest.dart';
import 'package:app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _model = ModelManifest.standard;

void main() {
  var discards = 0;

  Future<void> show(WidgetTester tester, InstallState state) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: AssistantInstallView(
          state: state,
          onInstall: () {},
          onCancel: () {},
          onRetry: () {},
          onOpen: () {},
          onBasic: () {},
          onRemove: () {},
          onDiscard: () => discards++,
          onLater: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => discards = 0);

  group('discarding a partial download', () {
    testWidgets('is offered next to Fortsetzen and not for a fresh install', (tester) async {
      await show(tester, const InstallState(InstallStage.offer, model: _model, freeBytes: 41000000000));
      expect(find.text('Download verwerfen'), findsNothing);

      await show(tester, const InstallState(InstallStage.offer, model: _model, partialBytes: 1200000000));
      expect(find.text('Fortsetzen'), findsOneWidget);
      await tester.tap(find.text('Download verwerfen'));
      expect(discards, 1);
    });

    testWidgets('is offered while the download runs and after it failed', (tester) async {
      await show(
        tester,
        const InstallState(
          InstallStage.downloading,
          model: _model,
          progress: DownloadProgress(received: 800000000, total: 3106738272, bytesPerSecond: 6000000),
        ),
      );
      expect(find.text('Abbrechen'), findsOneWidget);
      expect(find.text('Download verwerfen'), findsOneWidget);

      await show(
        tester,
        const InstallState(InstallStage.failed, model: _model, problem: InstallProblem.storage, partialBytes: 900000000),
      );
      expect(find.text('Download verwerfen'), findsOneWidget);
    });

    testWidgets('is not offered once the model is complete', (tester) async {
      await show(
        tester,
        const InstallState(InstallStage.failed, model: _model, problem: InstallProblem.loadFailed),
      );
      expect(find.text('Download verwerfen'), findsNothing);
      expect(find.text('Sprachmodell entfernen'), findsOneWidget);
    });
  });

  testWidgets('a pause for mobile data says so and promises to go on in the WLAN', (tester) async {
    await show(
      tester,
      const InstallState(
        InstallStage.offer,
        model: _model,
        partialBytes: 500000000,
        onMobileData: true,
        notice: InstallNotice.pausedForMobileData,
      ),
    );
    expect(find.textContaining('mobile Daten nutzt'), findsOneWidget);
    expect(find.textContaining('Hotspot'), findsNothing);
  });
}
