// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_installer.dart';

class BasicMode extends ValueNotifier<bool?> {
  BasicMode() : super(null);

  static const key = 'assistant_basic_mode';

  bool _chosen = false;

  Future<void> load() async {
    bool stored;
    try {
      stored = (await SharedPreferences.getInstance()).getBool(key) ?? false;
    } catch (_) {
      stored = false;
    }
    if (!_chosen) value = stored;
  }

  Future<void> choose(bool basic) async {
    _chosen = true;
    value = basic;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (basic) {
        await prefs.setBool(key, true);
      } else {
        await prefs.remove(key);
      }
    } catch (_) {
      return;
    }
  }

  void follow(Listenable source, bool Function() installed) {
    void check() {
      if (installed() && value != false) unawaited(choose(false));
    }

    source.addListener(check);
    check();
  }
}

enum AssistantPage { waiting, install, model, basic, basicOnly }

class AssistantSession {
  bool? _basic;

  AssistantPage page(InstallState state, {required bool? basicMode, required bool acceptedUnsupported}) {
    final stage = state.stage;
    if (stage == InstallStage.installed) return AssistantPage.model;
    if (stage == InstallStage.unsupported) {
      return acceptedUnsupported ? AssistantPage.basicOnly : AssistantPage.install;
    }
    var basic = _basic;
    if (basic == null) {
      if (basicMode == null || stage == InstallStage.checking) return AssistantPage.waiting;
      basic = _basic = basicMode && stage != InstallStage.ready;
    }
    return basic ? AssistantPage.basic : AssistantPage.install;
  }

  void withoutModel() => _basic = true;

  void backToInstall() => _basic = false;
}
