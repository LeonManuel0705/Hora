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
  var basics = 0;

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
          onWithoutModel: () => basics++,
          onLater: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    discards = 0;
    basics = 0;
  });

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

  group('opening the assistant without the model', () {
    testWidgets('is offered on the offer, while loading and after a failure', (tester) async {
      await show(tester, const InstallState(InstallStage.offer, model: _model, freeBytes: 41000000000));
      await tester.tap(find.text('Ohne KI öffnen'));
      expect(basics, 1);
      expect(find.text('Nicht jetzt'), findsOneWidget);

      await show(
        tester,
        const InstallState(
          InstallStage.downloading,
          model: _model,
          progress: DownloadProgress(received: 800000000, total: 3106738272),
        ),
      );
      expect(find.text('Ohne KI öffnen'), findsOneWidget);

      for (final problem in InstallProblem.values) {
        await show(tester, InstallState(InstallStage.failed, model: _model, problem: problem));
        expect(find.text('Ohne KI öffnen'), findsOneWidget, reason: problem.name);
      }
    });

    testWidgets('is not offered while the model starts, when it is ready or on unsupported phones', (tester) async {
      await show(tester, const InstallState(InstallStage.starting, model: _model));
      expect(find.text('Ohne KI öffnen'), findsNothing);
      await show(tester, const InstallState(InstallStage.ready, model: _model));
      expect(find.text('Ohne KI öffnen'), findsNothing);
      await show(tester, const InstallState(InstallStage.unsupported, unsupported: ModelUnsupportedReason.memory));
      expect(find.text('Ohne KI öffnen'), findsNothing);
      expect(find.text('Einfachen Assistenten öffnen'), findsOneWidget);
    });
  });

  group('banner in the chat without the model', () {
    var opened = 0;

    Future<void> banner(WidgetTester tester, InstallState state) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AssistantModelBanner(state: state, onOpenInstall: () => opened++),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() => opened = 0);

    testWidgets('invites to install and leads back to the install screen', (tester) async {
      await banner(tester, const InstallState(InstallStage.offer, model: _model));
      expect(
        find.text(
          'Ohne KI: Rechnen, Formeln, Daten und Lehrplan. Mit dem Sprachmodell beantwortet der Assistent auch '
          'alles andere.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Installieren'));
      expect(opened, 1);
    });

    testWidgets('shows a paused download with its share and offers to continue', (tester) async {
      await banner(tester, const InstallState(InstallStage.offer, model: _model, partialBytes: 1553369136));
      expect(find.textContaining('zu 50\u00a0% geladen'), findsOneWidget);
      expect(find.text('Fortsetzen'), findsOneWidget);
    });

    testWidgets('shows a running download instead and the whole card leads back', (tester) async {
      await banner(
        tester,
        const InstallState(
          InstallStage.downloading,
          model: _model,
          partialBytes: 400000000,
          progress: DownloadProgress(received: 1398100000, total: 3106738272, bytesPerSecond: 8000000),
        ),
      );
      expect(find.text('Sprachmodell wird geladen · 45\u00a0%'), findsOneWidget);
      expect(find.text('Installieren'), findsNothing);
      await tester.tap(find.text('Sprachmodell wird geladen · 45\u00a0%'));
      expect(opened, 1);
    });

    testWidgets('says when the model is ready', (tester) async {
      await banner(tester, const InstallState(InstallStage.ready, model: _model));
      expect(find.text('Das Sprachmodell ist bereit.'), findsOneWidget);
      await tester.tap(find.text('Öffnen'));
      expect(opened, 1);
    });
  });
}
