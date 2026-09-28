// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class WebTabGuard {
  WebTabGuard._();

  static final WebTabGuard instance = WebTabGuard._();
  static const _name = 'app-database';
  static const _handover = Duration(milliseconds: 400);

  final ValueNotifier<bool> lost = ValueNotifier(false);
  final Completer<void> _hold = Completer<void>();
  Future<void>? _claiming;

  Future<void> claim() => _claiming ??= _claim();

  Future<void> _claim() async {
    if (!(web.window.navigator as JSObject).has('locks')) return;
    final locks = web.window.navigator.locks;
    var elsewhere = false;
    try {
      final snapshot = await locks.query().toDart;
      elsewhere = snapshot.held.toDart.any((lock) => lock.name == _name);
    } catch (_) {}
    final granted = Completer<void>();
    JSPromise<JSAny?> keep(web.Lock? lock) {
      if (!granted.isCompleted) granted.complete();
      return _hold.future.toJS;
    }

    try {
      locks.request(_name, web.LockOptions(steal: true), keep.toJS).toDart.then(
            (_) {},
            onError: (Object _) => lost.value = true,
          );
    } catch (_) {
      return;
    }
    await granted.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    if (elsewhere) await Future<void>.delayed(_handover);
  }
}
