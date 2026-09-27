// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../services/flask_server_service.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/app_background.dart';

class DesktopWebViewScreen extends StatefulWidget {
  const DesktopWebViewScreen({super.key});

  @override
  State<DesktopWebViewScreen> createState() => _DesktopWebViewScreenState();
}

class _DesktopWebViewScreenState extends State<DesktopWebViewScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final FlaskServerService _flask = FlaskServerService();
  Timer? _updateCheckTimer;

  // flutter_inappwebview has no Linux implementation, so on Linux the hub is
  // opened in the system browser instead of an embedded WebView.
  bool get _useEmbeddedWebView => !Platform.isLinux;
  bool _openedInBrowser = false;

  late AnimationController _logoController;
  late AnimationController _textController;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flask.state.addListener(_onStateChange);
    _startPeriodicUpdateCheck();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _textController = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );

    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 180), () {
      if (mounted) _textController.forward();
    });

    _flask.confirmLegacyImport = _askLegacyImport;
    _flask.start();
  }

  Future<bool> _askLegacyImport(String previousName) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;
    final colors = _DesktopColors.of(context);
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          'Daten aus $previousName gefunden',
          style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Im Ordner „Dokumente/$previousName“ liegen deine Daten aus der Zeit, '
            'als ${Brand.name} noch $previousName hieß. Soll ${Brand.name} sie übernehmen? '
            'Der alte Ordner bleibt als Sicherung, wie er ist.',
            style: TextStyle(color: colors.soft, fontSize: 15, height: 1.45),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: colors.quietButton,
            child: const Text('Neu anfangen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: colors.primaryButton,
            child: const Text('Übernehmen'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _flask.state.removeListener(_onStateChange);
    _logoController.dispose();
    _textController.dispose();
    _flask.shutdown();
    super.dispose();
  }

  void _startPeriodicUpdateCheck() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _checkForUpdates();
    });
    _updateCheckTimer = Timer.periodic(const Duration(hours: 2), (_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo == null) return;
    await UpdateService.sendUpdateNotification(updateInfo);
    // Show the in-app dialog (with a working download button) — the desktop
    // notification tap path is unreliable, so this is the primary update UX.
    if (mounted) {
      await UpdateService.showUpdateDialog(context, updateInfo);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _flask.shutdown();
    }
  }

  void _onStateChange() {
    if (!mounted) return;
    // On Linux we cannot embed a WebView; open the hub in the browser once the
    // server is up.
    if (!_useEmbeddedWebView && _flask.isReady && !_openedInBrowser) {
      _openedInBrowser = true;
      _openHubInBrowser();
    }
    setState(() {});
  }

  Future<void> _openHubInBrowser() async {
    final uri = Uri.tryParse('${_flask.hubUrl}?token=${_flask.desktopToken}');
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_flask.state.value) {
      case FlaskServerState.idle:
      case FlaskServerState.starting:
        return _buildLoadingScreen();
      case FlaskServerState.error:
        return _buildErrorScreen();
      case FlaskServerState.ready:
      case FlaskServerState.alreadyRunning:
        return _useEmbeddedWebView
            ? _buildWebView()
            : _buildBrowserFallbackScreen();
    }
  }

  Widget _buildBrowserFallbackScreen() {
    return Builder(builder: (context) {
      final c = _DesktopColors.of(context);
      return AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo.png', width: 80, height: 80, fit: BoxFit.contain),
                const SizedBox(height: 20),
                Text(
                  '${Brand.name} läuft',
                  style: TextStyle(color: c.ink, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    '${Brand.name} wurde in deinem Standard-Browser geöffnet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 15, height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _openHubInBrowser,
                  icon: const Icon(Icons.open_in_browser, size: 18),
                  label: const Text('Im Browser öffnen'),
                  style: c.primaryButton,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildLoadingScreen() {
    return Builder(builder: (context) {
      final c = _DesktopColors.of(context);
      return AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    final k = Curves.easeOutCubic.transform(_logoController.value);
                    return Opacity(
                      opacity: k,
                      child: Transform.scale(scale: .96 + .04 * k, child: child),
                    );
                  },
                  child: Image.asset('assets/logo.png', width: 88, height: 88, fit: BoxFit.contain),
                ),
                const SizedBox(height: 20),
                AnimatedBuilder(
                  animation: _textController,
                  builder: (context, child) {
                    final k = Curves.easeOutCubic.transform(_textController.value);
                    return Opacity(
                      opacity: k,
                      child: Transform.translate(offset: Offset(0, 6 * (1 - k)), child: child),
                    );
                  },
                  child: Text(
                    Brand.name,
                    style: TextStyle(color: c.ink, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _textController,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.sage, backgroundColor: c.line),
                      ),
                      const SizedBox(height: 16),
                      Text('Server wird gestartet …', style: TextStyle(color: c.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildErrorScreen() {
    return Builder(builder: (context) {
      final c = _DesktopColors.of(context);
      return AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/logo.png', width: 80, height: 80, fit: BoxFit.contain),
                  const SizedBox(height: 20),
                  Text(
                    Brand.name,
                    style: TextStyle(color: c.ink, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    constraints: const BoxConstraints(maxWidth: 480),
                    decoration: BoxDecoration(
                      color: _flask.isSettingUp ? c.surface : c.urgentSoft,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _flask.isSettingUp ? c.line : c.urgent.withValues(alpha: .35)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _flask.isSettingUp ? Icons.hourglass_top_rounded : Icons.error_outline,
                          color: _flask.isSettingUp ? c.ink : c.urgent,
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        if (_flask.isSettingUp)
                          ValueListenableBuilder<String>(
                            valueListenable: _flask.setupProgress,
                            builder: (context, progress, _) {
                              return Column(
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: c.sage, backgroundColor: c.line),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    progress,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: c.soft, fontSize: 13, height: 1.5),
                                  ),
                                ],
                              );
                            },
                          )
                        else
                          Text(
                            _flask.errorMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.soft, fontSize: 15, height: 1.5),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!_flask.isSettingUp) ...[
                    if (_flask.isPythonMissing) ...[
                      if (Platform.isMacOS) ...[
                        ElevatedButton.icon(
                          onPressed: () async {
                            final future = _flask.setupPython();
                            setState(() {});
                            await future;
                            if (mounted) setState(() {});
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Python automatisch installieren'),
                          style: c.primaryButton,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextButton.icon(
                        onPressed: () {
                          launchUrl(
                            Uri.parse('https://www.python.org/downloads/'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: Icon(Icons.open_in_new, size: 16, color: c.muted),
                        label: Text('Von python.org herunterladen', style: TextStyle(color: c.muted, fontSize: 13)),
                      ),
                      const SizedBox(height: 4),
                    ],
                    ElevatedButton.icon(
                      onPressed: () => _flask.restart(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Erneut versuchen'),
                      style: _flask.isPythonMissing ? c.quietButton : c.primaryButton,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildWebView() {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppPalette.canvasDark : AppPalette.canvas,
      body: InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            cacheEnabled: false,
            cacheMode: CacheMode.LOAD_NO_CACHE,
            supportZoom: false,
            transparentBackground: false,
            useShouldOverrideUrlLoading: true,
            allowFileAccessFromFileURLs: false,
            allowUniversalAccessFromFileURLs: false,
            allowsBackForwardNavigationGestures: false,
          ),
          onWebViewCreated: (controller) async {
            try {
              await InAppWebViewController.clearAllCache();
              await WebStorageManager.instance().deleteAllData();
            } catch (_) {}

            await controller.loadUrl(
              urlRequest: URLRequest(
                url: WebUri(_flask.hubUrl),
                headers: {
                  'Cache-Control': 'no-cache, no-store',
                  'X-Hub-Token': _flask.desktopToken,
                },
              ),
            );

            controller.addJavaScriptHandler(
              handlerName: 'showNativeNotification',
              callback: (args) async {
                if (args.isEmpty) return;
                final data = args[0] as Map<dynamic, dynamic>?;
                final title = data?['title']?.toString() ?? '';
                final body = data?['body']?.toString() ?? '';
                if (title.isNotEmpty) {
                  await NotificationService().showNotification(
                    id: title.hashCode ^ body.hashCode,
                    title: title,
                    body: body,
                  );
                }
              },
            );
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url?.toString() ?? '';

            if (_flask.isHubUrl(url)) {
              return NavigationActionPolicy.ALLOW;
            }

            if (url.startsWith('http://') || url.startsWith('https://')) {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationActionPolicy.CANCEL;
            }

            return NavigationActionPolicy.CANCEL;
          },
          onLoadStop: (controller, url) async {
            await controller.evaluateJavascript(source: '''
              (function() {
                var mc = document.querySelector('.main-content');
                if (mc && mc.style.opacity === '0') {
                  mc.style.transition = 'opacity 0.3s ease-out, transform 0.3s ease-out';
                  mc.style.opacity = '1';
                  mc.style.transform = 'translateY(0)';
                }
              })();
            ''');
          },
          onReceivedError: (controller, request, error) {
            if (mounted) {
              setState(() {});
            }
          },
        ),
    );
  }
}

class _DesktopColors {
  const _DesktopColors(this.dark);

  factory _DesktopColors.of(BuildContext context) => _DesktopColors(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  Color get ink => dark ? AppPalette.inkDark : AppPalette.ink;
  Color get soft => dark ? AppPalette.inkSoftDark : AppPalette.inkSoft;
  Color get muted => dark ? AppPalette.inkMutedDark : AppPalette.inkMuted;
  Color get line => dark ? AppPalette.lineDark : AppPalette.line;
  Color get surface => dark ? AppPalette.surfaceDark : AppPalette.surface;
  Color get sage => dark ? AppPalette.sageDark : AppPalette.sage;
  Color get urgent => dark ? AppPalette.terracottaDark : AppPalette.terracotta;
  Color get urgentSoft => dark ? AppPalette.terracottaSoftDark : AppPalette.terracottaSoft;

  ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: dark ? AppPalette.brandDark : AppPalette.pine,
        foregroundColor: dark ? AppPalette.inkDark : AppPalette.chalk,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: StadiumBorder(side: dark ? const BorderSide(color: Color(0xFF3E5541)) : BorderSide.none),
      );

  ButtonStyle get quietButton => ElevatedButton.styleFrom(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: StadiumBorder(side: BorderSide(color: line)),
      );
}
