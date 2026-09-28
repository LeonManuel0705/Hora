// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:io';

import 'package:app/screens/assistant_screen.dart';
import 'package:app/services/assistant/local_model/basic_mode.dart';
import 'package:app/services/assistant/local_model/local_assistant.dart';
import 'package:app/services/assistant/local_model/model_downloader.dart';
import 'package:app/services/assistant/local_model/model_installer.dart';
import 'package:app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant_install_fakes.dart';
import 'assistant_model_fakes.dart';

void main() {
  late Directory dir;
  late FakeInstallHost host;
  late ModelInstaller installer;
  late LocalAssistant local;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 4)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester tester, {Key? key}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: AssistantScreen(key: key, assistant: local)),
    ));
    await settle(tester);
  }

  Future<bool?> storedChoice() async => (await SharedPreferences.getInstance()).getBool(BasicMode.key);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> prepare(WidgetTester tester) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('assistant_screen_test');
      host = FakeInstallHost(dir.path);
      installer = ModelInstaller(host, reserveBytes: 100);
      local = LocalAssistant.forTest(installer, RuntimeHarness().runtime());
      await installer.refresh();
    });
    addTearDown(() async {
      tester.view.reset();
      await tester.runAsync(() async {
        installer.dispose();
        await host.changes.close();
        if (await dir.exists()) await dir.delete(recursive: true);
      });
    });
  }

  testWidgets('the install screen can open the assistant without the model and remembers it', (tester) async {
    await prepare(tester);
    await open(tester);
    expect(find.text('Assistent installieren'), findsOneWidget);

    await tester.tap(find.text('Ohne KI öffnen'));
    await settle(tester);
    expect(find.text('Frag mich was'), findsOneWidget);
    expect(find.textContaining('Ohne KI: Rechnen, Formeln, Daten und Lehrplan.'), findsOneWidget);
    expect(await tester.runAsync(storedChoice), isTrue);

    await open(tester, key: UniqueKey());
    expect(find.text('Frag mich was'), findsOneWidget);
    expect(find.text('Assistent installieren'), findsNothing);
  });

  testWidgets('the chat without the model leads back to the install and follows the download', (tester) async {
    SharedPreferences.setMockInitialValues({BasicMode.key: true});
    await prepare(tester);
    await open(tester);
    expect(find.text('Frag mich was'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Installieren'));
    await settle(tester);
    expect(find.text('Assistent installieren'), findsOneWidget);
    expect(await tester.runAsync(storedChoice), isTrue);

    await tester.tap(find.text('Installieren'));
    await settle(tester);
    expect(installer.state.stage, InstallStage.downloading);
    expect(await tester.runAsync(storedChoice), isNull);

    host.transfers.single.onProgress(const DownloadProgress(received: 450, total: 1000, bytesPerSecond: 100));
    await tester.pump();
    await tester.tap(find.text('Ohne KI öffnen'));
    await settle(tester);
    expect(find.text('Frag mich was'), findsOneWidget);
    expect(find.text('Sprachmodell wird geladen · 45 %'), findsOneWidget);
    expect(await tester.runAsync(storedChoice), isTrue);

    await tester.tap(find.text('Sprachmodell wird geladen · 45 %'));
    await settle(tester);
    expect(find.text('Assistent wird installiert'), findsOneWidget);
    await tester.tap(find.text('Ohne KI öffnen'));
    await settle(tester);

    await tester.runAsync(() => host.transfers.single.finish());
    await settle(tester);
    expect(installer.state.stage, InstallStage.ready);
    expect(find.text('Das Sprachmodell ist bereit.'), findsOneWidget);
    expect(await tester.runAsync(storedChoice), isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Öffnen'));
    await settle(tester);
    expect(installer.state.stage, InstallStage.installed);
    expect(find.text('auf dem Gerät'), findsOneWidget);
  });

  testWidgets('removing the model shows the install screen again, not the chat without the model', (tester) async {
    await prepare(tester);
    await open(tester);
    await tester.tap(find.text('Installieren'));
    await settle(tester);
    await tester.runAsync(() => host.transfers.single.finish());
    await settle(tester);
    installer.open();
    await settle(tester);
    expect(find.text('auf dem Gerät'), findsOneWidget);

    await tester.runAsync(installer.remove);
    await settle(tester);
    expect(find.text('Assistent installieren'), findsOneWidget);
    expect(await tester.runAsync(storedChoice), isNull);
  });
}
