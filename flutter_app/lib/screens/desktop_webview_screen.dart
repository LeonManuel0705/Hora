// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
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
  late AnimationController _ringController;
  late AnimationController _glowController;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flask.state.addListener(_onStateChange);
    _startPeriodicUpdateCheck();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _textController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _textController.forward();
    });

    _flask.start();
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _flask.state.removeListener(_onStateChange);
    _logoController.dispose();
    _textController.dispose();
    _ringController.dispose();
    _glowController.dispose();
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
    final uri = Uri.tryParse('${_flask.url}/hub');
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
    return AppBackground(
      keepCenterClear: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset(
                  'assets/logo.png',
                  width: 90,
                  height: 90,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 28),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: AppTheme.primaryGradient,
                ).createShader(bounds),
                child: const Text(
                  '${Brand.name} läuft',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  '${Brand.name} wurde in deinem Standard-Browser geöffnet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _openHubInBrowser,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Im Browser öffnen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return AppBackground(
      keepCenterClear: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_logoController, _glowController]),
                builder: (context, child) {
                  final logoScale = Curves.elasticOut.transform(
                    _logoController.value.clamp(0.0, 1.0),
                  );
                  final logoOpacity = Curves.easeIn.transform(
                    (_logoController.value * 2.5).clamp(0.0, 1.0),
                  );
                  final glowIntensity = 0.15 + 0.25 * _glowController.value;

                  return Opacity(
                    opacity: logoOpacity,
                    child: Transform.scale(
                      scale: logoScale,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor
                                  .withValues(alpha: glowIntensity),
                              blurRadius: 50,
                              spreadRadius: 15,
                            ),
                            BoxShadow(
                              color: AppTheme.accentColor
                                  .withValues(alpha: glowIntensity * 0.4),
                              blurRadius: 80,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 100,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 36),

              AnimatedBuilder(
                animation: _textController,
                builder: (context, child) {
                  final opacity = Curves.easeIn.transform(
                    _textController.value,
                  );
                  final slideY = 20.0 * (1.0 - Curves.easeOutCubic.transform(
                    _textController.value,
                  ));

                  return Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(0, slideY),
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: AppTheme.primaryGradient,
                        ).createShader(bounds),
                        child: const Text(
                          Brand.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              AnimatedBuilder(
                animation: Listenable.merge([_textController, _ringController]),
                builder: (context, child) {
                  final opacity = Curves.easeIn.transform(
                    _textController.value,
                  );
                  return Opacity(
                    opacity: opacity,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CustomPaint(
                        painter: _GradientRingPainter(
                          progress: _ringController.value,
                          colors: AppTheme.primaryGradient,
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              AnimatedBuilder(
                animation: _textController,
                builder: (context, child) {
                  final opacity = Curves.easeIn.transform(
                    _textController.value,
                  ) * 0.5;
                  return Opacity(
                    opacity: opacity,
                    child: const Text(
                      'Server wird gestartet...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return AppBackground(
      keepCenterClear: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                      blurRadius: 50,
                      spreadRadius: 15,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: AppTheme.primaryGradient,
                ).createShader(bounds),
                child: const Text(
                  Brand.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _flask.isSettingUp
                          ? Icons.hourglass_top_rounded
                          : Icons.error_outline,
                      color: _flask.isSettingUp
                          ? AppTheme.primaryColor
                          : Colors.redAccent,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    if (_flask.isSettingUp) ...[
                      ValueListenableBuilder<String>(
                        valueListenable: _flask.setupProgress,
                        builder: (context, progress, _) {
                          return Column(
                            children: [
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                progress,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ] else ...[
                      Text(
                        _flask.errorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!_flask.isSettingUp) ...[
                if (_flask.isPythonMissing) ...[
                  // Automatic install is Homebrew-based and macOS-only; other
                  // platforms only get the python.org link + retry.
                  if (Platform.isMacOS) ...[
                    ElevatedButton.icon(
                      onPressed: () async {
                        final future = _flask.setupPython();
                        setState(() {});
                        await future;
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Python automatisch installieren'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                    icon: Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    label: Text(
                      'Von python.org herunterladen',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                ElevatedButton.icon(
                  onPressed: () => _flask.restart(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut versuchen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _flask.isPythonMissing
                        ? Colors.white.withValues(alpha: 0.1)
                        : AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
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
                url: WebUri('${_flask.url}/hub'),
                headers: {'Cache-Control': 'no-cache, no-store'},
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

            if (url.startsWith('http://localhost:${_flask.port}') ||
                url.startsWith('http://127.0.0.1:${_flask.port}')) {
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

class _GradientRingPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  _GradientRingPainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, bgPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final rotation = progress * 2 * math.pi;
    final sweepGradient = SweepGradient(
      colors: [...colors, colors.first.withValues(alpha: 0)],
      stops: const [0.0, 0.35, 0.7, 1.0],
      transform: GradientRotation(rotation),
    );

    final arcPaint = Paint()
      ..shader = sweepGradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, rotation, math.pi * 1.4, false, arcPaint);
  }

  @override
  bool shouldRepaint(_GradientRingPainter old) => old.progress != progress;
}
