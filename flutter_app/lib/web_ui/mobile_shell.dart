// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show buildClassicHome, showWelcomeSetup;
import '../providers/app_provider.dart';
import '../providers/iserv_provider.dart';
import '../screens/assistant_screen.dart';
import '../screens/bookmarks_screen.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/review_screen.dart';
import '../screens/training_screen.dart';
import '../services/holiday_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import 'ui_api.dart';
import 'ui_server.dart';
import 'ui_weather.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _NativePage {
  const _NativePage(this.title, this.build, {this.reload = false});

  final String title;
  final Widget Function() build;
  final bool reload;
}

class _MobileShellState extends State<MobileShell> with WidgetsBindingObserver implements UiHost {
  static final _native = <String, _NativePage>{
    'assistant': _NativePage('Assistent', () => const AssistantScreen(), reload: true),
    'pomodoro': _NativePage('Pomodoro', () => const PomodoroScreen(), reload: true),
    'training': _NativePage('Training', () => const TrainingScreen()),
    'bookmarks': _NativePage('Lesezeichen', () => const BookmarksScreen()),
    'review': _NativePage('Review', () => const ReviewScreen()),
  };

  final UiServer _server = UiServer.instance;
  InAppWebViewController? _controller;
  URLRequest? _initial;
  EdgeInsets _insets = EdgeInsets.zero;
  bool _keyboard = false;
  bool _shown = false;
  bool? _pageDark;
  DateTime? _pausedAt;
  String _pausedDay = '';
  Timer? _changeTimer;
  final Set<String> _changes = {};
  bool _setupRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _changeTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    if (Platform.isAndroid) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    await _server.start(host: this);
    unawaited(UiWeather.instance.refresh());
    final start = kDebugMode ? (await SharedPreferences.getInstance()).getString('ui_debug_page') : null;
    if (!mounted) return;
    setState(() => _initial = URLRequest(url: WebUri.uri(_server.entry(start != null && start.startsWith('/hub') ? start : '/hub'))));
  }

  bool get _dark => _pageDark ?? Theme.of(context).brightness == Brightness.dark;

  (EdgeInsets, bool) _currentInsets() {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    return (EdgeInsets.only(top: media.viewPadding.top, bottom: keyboard ? 0 : media.viewPadding.bottom), keyboard);
  }

  String _insetScript(EdgeInsets insets, bool keyboard) {
    String px(double value) => '${value.toStringAsFixed(1)}px';
    return 'document.documentElement.toggleAttribute("data-keyboard",$keyboard);'
        'document.documentElement.style.setProperty("--safe-top","${px(insets.top)}");'
        'document.documentElement.style.setProperty("--safe-bottom","${px(insets.bottom)}");'
        'document.documentElement.style.setProperty("--safe-left","0px");'
        'document.documentElement.style.setProperty("--safe-right","0px");';
  }

  String get _startScript => '''
(function () {
  var root = document.documentElement;
  root.dataset.shell = "${Platform.isIOS ? 'ios' : 'android'}";
  ${_insetScript(_insets, _keyboard)}
  var permission = "${NotificationService().permissionGranted ? 'granted' : 'default'}";
  function bridge(name, value) {
    if (!window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) return Promise.resolve(null);
    return window.flutter_inappwebview.callHandler(name, value);
  }
  function Reminder(title, options) {
    bridge("notify", { title: String(title || ""), body: options && options.body ? String(options.body) : "" });
  }
  Object.defineProperty(Reminder, "permission", { get: function () { return permission; } });
  Reminder.requestPermission = function () {
    return bridge("notifyPermission", true).then(function (value) {
      permission = value || permission;
      return permission;
    });
  };
  window.Notification = Reminder;
  function send() {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler("theme", root.dataset.theme || "light");
      }
    } catch (error) {}
  }
  var modern = !!(window.CSS && CSS.supports("color", "light-dark(#000, #fff)") && CSS.supports("selector(:has(a))") && "popover" in HTMLElement.prototype);
  function check() { bridge("support", modern); }
  new MutationObserver(send).observe(root, { attributes: true, attributeFilter: ["data-theme"] });
  window.addEventListener("flutterInAppWebViewPlatformReady", function () { send(); check(); });
  document.addEventListener("DOMContentLoaded", function () { send(); check(); });
})();
''';

  UnmodifiableListView<UserScript> get _scripts => UnmodifiableListView([
        UserScript(source: _startScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]);

  Future<void> _applyInsets() async {
    final (insets, keyboard) = _currentInsets();
    if (insets == _insets && keyboard == _keyboard) return;
    _insets = insets;
    _keyboard = keyboard;
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.removeAllUserScripts();
      await controller.addUserScripts(userScripts: _scripts.toList());
      await controller.evaluateJavascript(source: _insetScript(insets, keyboard));
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final (insets, keyboard) = _currentInsets();
      _insets = insets;
      _keyboard = keyboard;
    } else {
      unawaited(_applyInsets());
    }
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_applyInsets());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
      _pausedDay = _dayKey();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resume());
    }
  }

  String _dayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> _resume() async {
    final paused = _pausedAt;
    _pausedAt = null;
    final port = _server.port;
    final alive = await _server.ensureAlive();
    unawaited(UiWeather.instance.refresh());
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (!alive && _server.port != port) {
      final current = await controller.getUrl();
      final path = current?.path.startsWith('/hub') == true ? current!.path : '/hub';
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(_server.entry(path))));
      return;
    }
    final long = paused != null && DateTime.now().difference(paused) > const Duration(minutes: 10);
    if (!alive || long || _pausedDay != _dayKey()) await controller.reload();
  }

  SystemUiOverlayStyle get _overlay {
    final dark = _dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
  }

  Future<NavigationActionPolicy> _navigate(InAppWebViewController controller, NavigationAction action) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.CANCEL;
    if (const {'about', 'data', 'blob'}.contains(uri.scheme)) return NavigationActionPolicy.ALLOW;
    if ((uri.host == '127.0.0.1' || uri.host == 'localhost') && uri.port == _server.port) {
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments.first == 'hub') {
        final native = _native[segments[1]];
        if (native != null) {
          unawaited(_openNative(native));
          return NavigationActionPolicy.CANCEL;
        }
        if (segments[1] == 'klassisch') return NavigationActionPolicy.CANCEL;
      }
      return NavigationActionPolicy.ALLOW;
    }
    unawaited(_external(uri));
    return NavigationActionPolicy.CANCEL;
  }

  Future<void> _external(Uri uri) async {
    if (!const {'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openNative(_NativePage page) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Semantics(
          label: page.title,
          explicitChildNodes: true,
          child: Scaffold(
            appBar: AppBar(
              systemOverlayStyle: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            body: SafeArea(top: false, child: page.build()),
          ),
        );
      },
    ));
    if (page.reload && mounted) await _controller?.reload();
  }

  bool _fellBack = false;

  void _fallBack() {
    if (_fellBack || !mounted) return;
    _fellBack = true;
    if (Platform.isAndroid) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values));
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      pageBuilder: (context, _, __) => buildClassicHome(),
      transitionDuration: Duration.zero,
    ));
  }

  Future<void> _afterFirstLoad() async {
    if (_setupRunning || _fellBack) return;
    _setupRunning = true;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (!prefs.containsKey('user_bundesland')) {
      final result = await showWelcomeSetup(context, withDemo: false);
      if (result != null) {
        await prefs.setString('user_bundesland', result.bundesland);
        await prefs.setInt('graduation_year', result.graduationYear);
        try {
          await HolidayService().importHolidays();
        } catch (_) {}
        if (mounted) {
          unawaited(context.read<AppProvider>().loadEvents());
          await _controller?.reload();
        }
      }
    } else {
      unawaited(_importHolidaysIfNeeded());
    }
    unawaited(_checkForUpdates());
  }

  Future<void> _importHolidaysIfNeeded() async {
    try {
      final service = HolidayService();
      if (await service.hasImportedHolidays()) return;
      final events = await service.importHolidays();
      if (events.isNotEmpty && mounted) {
        unawaited(context.read<AppProvider>().loadEvents());
        await _controller?.reload();
      }
    } catch (_) {}
  }

  Future<void> _checkForUpdates() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final info = await UpdateService.checkForUpdate();
    if (info != null && mounted) {
      UpdateService.sendUpdateNotification(info);
      UpdateService.showUpdateDialog(context, info);
    }
  }

  Future<void> _debugScript(InAppWebViewController controller) async {
    final script = (await SharedPreferences.getInstance()).getString('ui_debug_script');
    if (script == null || script.isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await controller.evaluateJavascript(source: script);
  }

  Future<void> _back() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Future<Map<String, Object?>> connectIserv(String url, String user, String password) async {
    final result = await context.read<IServProvider>().connect(username: user, password: password, iservUrl: url);
    return result.cast<String, Object?>();
  }

  @override
  Future<void> disconnectIserv() => context.read<IServProvider>().disconnect();

  @override
  Map<String, Object?> iservStatus() {
    final provider = context.read<IServProvider>();
    return {'connected': provider.isConnected, 'has_credentials': provider.isConnected || provider.username != null};
  }

  @override
  Future<int> changeState(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_bundesland', name);
    final events = await HolidayService().refreshHolidays();
    return events.length;
  }

  @override
  Future<void> themeChoice(String? choice) async {
    final provider = context.read<AppProvider>();
    if (choice == null) {
      await provider.setThemeSwitchMode('system');
      return;
    }
    await provider.setThemeSwitchMode('manual');
    await provider.setThemeMode(choice == 'dark' ? ThemeMode.dark : ThemeMode.light);
  }

  @override
  void dataChanged(String area) {
    _changes.add(area);
    _changeTimer?.cancel();
    _changeTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      final areas = Set<String>.of(_changes);
      _changes.clear();
      if (areas.contains('tasks')) unawaited(provider.loadTasks());
      if (areas.contains('events')) unawaited(provider.loadEvents());
      if (areas.contains('school')) unawaited(provider.loadLessons());
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = _dark;
    final canvas = dark ? AppPalette.canvasDark : AppPalette.canvas;
    final initial = _initial;
    final sides = MediaQuery.of(context).viewPadding;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlay,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_back());
        },
        child: Scaffold(
          backgroundColor: canvas,
          resizeToAvoidBottomInset: Platform.isAndroid,
          body: Stack(
            children: [
              if (initial != null)
                Positioned.fill(
                  left: sides.left,
                  right: sides.right,
                  child: InAppWebView(
                    initialUrlRequest: initial,
                    initialUserScripts: _scripts,
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      supportZoom: false,
                      builtInZoomControls: false,
                      displayZoomControls: false,
                      transparentBackground: true,
                      useShouldOverrideUrlLoading: true,
                      supportMultipleWindows: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      allowFileAccessFromFileURLs: false,
                      allowUniversalAccessFromFileURLs: false,
                      allowFileAccess: false,
                      allowContentAccess: false,
                      allowsBackForwardNavigationGestures: true,
                      allowsLinkPreview: false,
                      disableLongPressContextMenuOnLinks: true,
                      contentInsetAdjustmentBehavior: ScrollViewContentInsetAdjustmentBehavior.NEVER,
                      overScrollMode: OverScrollMode.NEVER,
                      verticalScrollBarEnabled: false,
                      horizontalScrollBarEnabled: false,
                      isInspectable: kDebugMode,
                      mediaPlaybackRequiresUserGesture: true,
                      geolocationEnabled: true,
                      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                      thirdPartyCookiesEnabled: false,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      controller.addJavaScriptHandler(
                        handlerName: 'notifyPermission',
                        callback: (args) async {
                          final service = NotificationService();
                          if (!service.isInitialized) await service.initialize();
                          if (service.permissionGranted) return 'granted';
                          final granted = await service.requestPermissions();
                          return granted ? 'granted' : 'denied';
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'notify',
                        callback: (args) async {
                          final value = args.isNotEmpty && args.first is Map ? args.first as Map : const {};
                          final title = '${value['title'] ?? ''}'.trim();
                          if (title.isEmpty) return false;
                          return NotificationService().showNotification(
                            id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
                            title: title,
                            body: '${value['body'] ?? ''}',
                          );
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'support',
                        callback: (args) {
                          if (args.isNotEmpty && args.first == false) _fallBack();
                          return null;
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'theme',
                        callback: (args) {
                          final dark = args.isNotEmpty && args.first == 'dark';
                          if (mounted && dark != _pageDark) setState(() => _pageDark = dark);
                          return null;
                        },
                      );
                    },
                    shouldOverrideUrlLoading: _navigate,
                    onCreateWindow: (controller, action) async {
                      final uri = action.request.url;
                      if (uri != null) unawaited(_external(uri));
                      return false;
                    },
                    onGeolocationPermissionsShowPrompt: (controller, origin) async =>
                        GeolocationPermissionShowPromptResponse(origin: origin, allow: true, retain: true),
                    onLoadStop: (controller, url) async {
                      if (!_shown && mounted) {
                        setState(() => _shown = true);
                        unawaited(_afterFirstLoad());
                      }
                      if (kDebugMode) await _debugScript(controller);
                    },
                    onReceivedError: (controller, request, error) {
                      if (request.isForMainFrame == true && mounted && !_shown) setState(() => _shown = true);
                    },
                  ),
                ),
              IgnorePointer(
                ignoring: _shown,
                child: AnimatedOpacity(
                  opacity: _shown ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: ColoredBox(color: canvas, child: const SizedBox.expand()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
