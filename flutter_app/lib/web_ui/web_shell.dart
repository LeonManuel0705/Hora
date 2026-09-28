// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../brand.dart';
import '../main.dart' show buildClassicHome;
import '../services/database_service.dart';
import '../services/web_tab_guard.dart';
import '../theme.dart';
import 'ui_api.dart';
import 'ui_bridge.dart';
import 'ui_pages.dart';
import 'ui_shell.dart';
import 'ui_weather.dart';
import 'web_start_script.dart';

Widget buildWebHome() => const WebShell();

extension type _Reply._(JSObject _) implements JSObject {
  external factory _Reply({int status, JSObject headers, JSAny? body, bool busy});
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with WidgetsBindingObserver, UiShellHost<WebShell> {
  static const _scope = '/hub';
  static const _worker = 'hub_worker.js';

  late final UiBridge _bridge = UiBridge(
    api: UiApi(this),
    pages: UiPages(browser: true),
    openNative: _openNative,
    startScript: webStartScript,
  );
  web.HTMLIFrameElement? _frame;
  JSFunction? _workerListener;
  JSFunction? _frameListener;
  bool _shown = false;
  bool _preparing = false;
  bool _fellBack = false;
  bool _elsewhere = false;
  bool? _pageDark;
  int _covered = 0;
  DateTime? _pausedAt;
  String _pausedDay = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WebTabGuard.instance.lost.addListener(_lost);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WebTabGuard.instance.lost.removeListener(_lost);
    _unlisten();
    _frame?.remove();
    _frame = null;
    _flutterInert(false);
    disposeHost();
    super.dispose();
  }

  static bool _modern() {
    try {
      final element = globalContext['HTMLElement'] as JSObject?;
      final prototype = element?['prototype'] as JSObject?;
      return web.CSS.supports('color', 'light-dark(#000, #fff)') &&
          web.CSS.supports('selector(:has(a))') &&
          (prototype?.has('popover') ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<void> _boot() async {
    if (!mounted) return;
    if (!_modern()) return _fallBack();
    try {
      await DatabaseService().database;
      if (WebTabGuard.instance.lost.value) return _lost();
      await _register();
    } catch (_) {
      return _fallBack();
    }
    if (!mounted || _elsewhere) return;
    unawaited(UiWeather.instance.refresh());
    _listen();
    if (await askWelcome() && mounted) {
      setState(() => _preparing = true);
      await importWelcomeHolidays().timeout(const Duration(seconds: 12), onTimeout: () {});
      if (!mounted) return;
      setState(() => _preparing = false);
    }
    if (!mounted || _elsewhere) return;
    _createFrame();
  }

  Future<void> _register() async {
    final navigator = web.window.navigator;
    if (!(navigator as JSObject).has('serviceWorker')) throw StateError('Kein Service Worker');
    final registration = await navigator.serviceWorker
        .register(_worker.toJS, web.RegistrationOptions(scope: _scope, updateViaCache: 'none'))
        .toDart
        .timeout(const Duration(seconds: 15));
    if (registration.active != null) return;
    final worker = registration.installing ?? registration.waiting;
    if (worker == null) throw StateError('Kein Service Worker');
    final active = Completer<void>();
    void check() {
      if (active.isCompleted) return;
      if (worker.state == 'activated') active.complete();
      if (worker.state == 'redundant') active.completeError(StateError('Service Worker verworfen'));
    }

    final listener = ((web.Event _) => check()).toJS;
    worker.addEventListener('statechange', listener);
    try {
      check();
      await active.future.timeout(const Duration(seconds: 15));
    } finally {
      worker.removeEventListener('statechange', listener);
    }
  }

  void _listen() {
    final worker = _workerListener = _onWorker.toJS;
    final container = web.window.navigator.serviceWorker;
    container.addEventListener('message', worker);
    container.startMessages();
    final frame = _frameListener = _onFrame.toJS;
    web.window.addEventListener('message', frame);
  }

  void _unlisten() {
    final worker = _workerListener;
    if (worker != null) web.window.navigator.serviceWorker.removeEventListener('message', worker);
    final frame = _frameListener;
    if (frame != null) web.window.removeEventListener('message', frame);
    _workerListener = null;
    _frameListener = null;
  }

  void _onWorker(web.MessageEvent event) {
    final ports = event.ports.toDart;
    if (ports.isEmpty) return;
    final data = event.data.dartify();
    if (data is! Map<Object?, Object?> || data['type'] != 'hub-request') return;
    final port = ports.first;
    if (_elsewhere || !mounted) {
      port.postMessage(_Reply(busy: true));
      return;
    }
    unawaited(_answer(port, UiBridgeRequest.fromMessage(data)));
  }

  Future<void> _answer(web.MessagePort port, UiBridgeRequest request) async {
    final reply = await _bridge.handle(request);
    final body = reply.body;
    port.postMessage(_Reply(
      status: reply.status,
      headers: reply.headers.jsify() as JSObject,
      body: switch (body) {
        final String text => text.toJS,
        final Uint8List bytes => bytes.toJS,
        _ => null,
      },
    ));
  }

  void _onFrame(web.MessageEvent event) {
    final window = _frame?.contentWindow;
    if (window == null || event.origin != web.window.location.origin) return;
    if (!(event.source as JSAny?).strictEquals(window).toDart) return;
    final data = event.data.dartify();
    if (data is! Map<Object?, Object?> || data['source'] != 'hub') return;
    switch (data['type']) {
      case 'theme':
        _theme(data['value'] == 'dark');
      case 'ready':
        _ready();
    }
  }

  void _createFrame() {
    final frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
    frame
      ..id = 'hub-frame'
      ..title = Brand.name
      ..allow = 'geolocation'
      ..src = _scope;
    web.document.body?.append(frame);
    _frame = frame;
    _sync();
  }

  void _ready() {
    if (!_shown) {
      _shown = true;
      unawaited(welcomeOrHolidays());
    }
    _sync();
  }

  void _sync() {
    final frame = _frame;
    if (frame == null) return;
    final visible = _shown && _covered == 0 && !_elsewhere;
    frame.toggleAttribute('data-shown', visible);
    _flutterInert(visible);
    if (!visible) frame.blur();
  }

  static void _flutterInert(bool inert) {
    web.document.querySelector('flutter-view')?.toggleAttribute('inert', inert);
  }

  void _theme(bool dark) {
    if (mounted && dark != _pageDark) setState(() => _pageDark = dark);
    final color = dark ? AppPalette.canvasDark : AppPalette.canvas;
    final css = '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    final root = web.document.documentElement as web.HTMLElement?;
    root?.style.setProperty('--canvas', css);
    root?.style.setProperty('color-scheme', dark ? 'dark' : 'light');
    final metas = web.document.querySelectorAll('meta[name="theme-color"]');
    for (var index = 0; index < metas.length; index++) {
      (metas.item(index) as web.Element?)?.setAttribute('content', css);
    }
  }

  Future<bool> _openNative(String name) async {
    final page = uiNativePages[name];
    if (page == null || !mounted || _elsewhere) return false;
    unawaited(openNativePage(page));
    return true;
  }

  @override
  Future<R?> overPage<R>(Future<R?> Function() show) async {
    _covered++;
    _sync();
    try {
      return await show();
    } finally {
      _covered--;
      if (mounted) _sync();
    }
  }

  @override
  Future<void> reloadPage() async {
    try {
      _frame?.contentWindow?.location.reload();
    } catch (_) {}
  }

  void _fallBack() {
    if (_fellBack || !mounted) return;
    _fellBack = true;
    _unlisten();
    _frame?.remove();
    _frame = null;
    _flutterInert(false);
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      pageBuilder: (context, _, __) => buildClassicHome(),
      transitionDuration: Duration.zero,
    ));
  }

  void _lost() {
    if (!WebTabGuard.instance.lost.value || _elsewhere || !mounted) return;
    _frame?.remove();
    _frame = null;
    _flutterInert(false);
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(DatabaseService().database.then((db) => db.close()).catchError((Object _) {}));
    setState(() => _elsewhere = true);
  }

  String _dayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
      _pausedDay = _dayKey();
    } else if (state == AppLifecycleState.resumed) {
      final paused = _pausedAt;
      _pausedAt = null;
      if (paused == null || _elsewhere || _frame == null) return;
      unawaited(UiWeather.instance.refresh());
      final long = DateTime.now().difference(paused) > const Duration(minutes: 10);
      if (long || _pausedDay != _dayKey()) unawaited(reloadPage());
    }
  }

  Widget _notice(bool dark, {required String title, String? text, Widget? action}) {
    final ink = dark ? AppPalette.inkDark : AppPalette.ink;
    final soft = dark ? AppPalette.inkSoftDark : AppPalette.inkSoft;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', width: 64, height: 64),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 22, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.3),
                ),
                if (text != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, height: 1.4, color: soft),
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 24), action],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _pageDark ?? Theme.of(context).brightness == Brightness.dark;
    final canvas = dark ? AppPalette.canvasDark : AppPalette.canvas;
    final Widget? content;
    if (_elsewhere) {
      content = _notice(
        dark,
        title: '${Brand.name} ist in einem anderen Tab offen',
        text: 'Gespeichert wird immer nur in einem Tab, damit nichts verloren geht.',
        action: FilledButton(
          onPressed: () => web.window.location.reload(),
          style: FilledButton.styleFrom(
            backgroundColor: dark ? AppPalette.brandDark : AppPalette.pine,
            foregroundColor: dark ? AppPalette.inkDark : AppPalette.chalk,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: const StadiumBorder(),
          ),
          child: const Text('Hier weiterarbeiten'),
        ),
      );
    } else if (_preparing) {
      content = _notice(
        dark,
        title: 'Ferien und Feiertage werden geladen',
        action: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: dark ? AppPalette.sageDark : AppPalette.sage,
            backgroundColor: dark ? AppPalette.lineDark : AppPalette.line,
          ),
        ),
      );
    } else {
      content = null;
    }
    return Scaffold(backgroundColor: canvas, body: content ?? const SizedBox.expand());
  }
}
