// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:app/services/assistant/local_model/basic_mode.dart';
import 'package:app/services/assistant/local_model/model_installer.dart';
import 'package:app/services/assistant/local_model/model_manifest.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _model = ModelManifest.standard;

InstallState _state(InstallStage stage) => InstallState(stage, model: _model);

void main() {
  group('remembered choice', () {
    test('is off until someone opens the assistant without the model', () async {
      SharedPreferences.setMockInitialValues({});
      final mode = BasicMode();
      expect(mode.value, isNull);
      await mode.load();
      expect(mode.value, isFalse);

      await mode.choose(true);
      final later = BasicMode();
      await later.load();
      expect(later.value, isTrue);
    });

    test('a choice made while loading is not overwritten by the stored value', () async {
      SharedPreferences.setMockInitialValues({BasicMode.key: true});
      final mode = BasicMode();
      final loading = mode.load();
      await mode.choose(false);
      await loading;
      expect(mode.value, isFalse);
    });

    test('an installed model clears it and removing the model does not set it again', () async {
      SharedPreferences.setMockInitialValues({BasicMode.key: true});
      final installed = ValueNotifier(false);
      final mode = BasicMode();
      await mode.load();
      mode.follow(installed, () => installed.value);
      expect(mode.value, isTrue);

      installed.value = true;
      await Future<void>.delayed(Duration.zero);
      expect(mode.value, isFalse);
      expect((await SharedPreferences.getInstance()).getBool(BasicMode.key), isNull);

      installed.value = false;
      await Future<void>.delayed(Duration.zero);
      expect(mode.value, isFalse);
    });
  });

  group('page for a visit', () {
    test('waits until the choice and the install state are known', () {
      final session = AssistantSession();
      expect(session.page(_state(InstallStage.offer), basicMode: null, acceptedUnsupported: false), AssistantPage.waiting);
      expect(session.page(_state(InstallStage.checking), basicMode: false, acceptedUnsupported: false),
          AssistantPage.waiting);
      expect(session.page(_state(InstallStage.offer), basicMode: false, acceptedUnsupported: false),
          AssistantPage.install);
    });

    test('a remembered choice opens the chat without the model and stays there while the model loads', () {
      final session = AssistantSession();
      expect(session.page(_state(InstallStage.offer), basicMode: true, acceptedUnsupported: false), AssistantPage.basic);
      for (final stage in [InstallStage.downloading, InstallStage.failed, InstallStage.starting, InstallStage.ready]) {
        expect(session.page(_state(stage), basicMode: false, acceptedUnsupported: false), AssistantPage.basic);
      }
    });

    test('the install screen and the chat without the model can be switched both ways', () {
      final session = AssistantSession();
      expect(session.page(_state(InstallStage.downloading), basicMode: false, acceptedUnsupported: false),
          AssistantPage.install);
      session.withoutModel();
      expect(session.page(_state(InstallStage.downloading), basicMode: true, acceptedUnsupported: false),
          AssistantPage.basic);
      session.backToInstall();
      expect(session.page(_state(InstallStage.downloading), basicMode: true, acceptedUnsupported: false),
          AssistantPage.install);
    });

    test('an installed model always opens the model chat', () {
      final session = AssistantSession()..withoutModel();
      expect(session.page(_state(InstallStage.installed), basicMode: true, acceptedUnsupported: false),
          AssistantPage.model);
    });

    test('a model that just finished opens its ready screen on a new visit', () {
      final session = AssistantSession();
      expect(session.page(_state(InstallStage.ready), basicMode: true, acceptedUnsupported: false),
          AssistantPage.install);
    });

    test('unsupported phones keep their own way to the basic chat', () {
      const unsupported = InstallState(InstallStage.unsupported, unsupported: ModelUnsupportedReason.memory);
      expect(AssistantSession().page(unsupported, basicMode: true, acceptedUnsupported: false), AssistantPage.install);
      expect(AssistantSession().page(unsupported, basicMode: false, acceptedUnsupported: true), AssistantPage.basicOnly);
    });
  });
}
