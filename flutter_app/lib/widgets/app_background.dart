// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

class AppBackground extends StatefulWidget {
  final Widget child;
  final bool keepCenterClear;

  const AppBackground({
    super.key,
    required this.child,
    this.keepCenterClear = false,
  });

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller1;
  late AnimationController _controller2;
  late AnimationController _controller3;
  late AnimationController _dotGridController;


  static const Color _blue = Color(0xFF9580E8);
  static const Color _blueLight = Color(0xFFB7A6F6);
  static const Color _purple = Color(0xFF7353CD);
  static const Color _purpleLight = Color(0xFFD5CFFF);
  static const Color _emerald = Color(0xFF3AB78E);
  static const Color _emeraldLight = Color(0xFF8FE0C0);

  static const Color _darkBg = Color(0xFF14131A);
  static const Color _lightBg = Color(0xFFFBFAFF);

  @override
  void initState() {
    super.initState();

    _controller1 = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _controller2 = AnimationController(
      duration: const Duration(seconds: 25),
      vsync: this,
    )..repeat();

    _controller3 = AnimationController(
      duration: const Duration(seconds: 22),
      vsync: this,
    )..repeat();


    _dotGridController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
      value: 0,
    );
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    _dotGridController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final orbOpacity = isDark ? 0.20 : 0.40;

    return Stack(
      children: [

        Container(color: isDark ? _darkBg : _lightBg),


        RepaintBoundary(
          child: AnimatedBuilder(
          animation: Listenable.merge([_controller1, _controller2, _controller3]),
          builder: (context, child) {
            final clear = widget.keepCenterClear;
            return CustomPaint(
              painter: _OrbsPainter(
                orbs: [

                  _OrbData(
                    size: clear ? 500 : 650,
                    anchorTopRight: false,
                    anchorBottomLeft: false,
                    anchorBottomRight: false,
                    anchorCenter: false,
                    baseOffset: const Offset(0, 0),
                    colors: [_blueLight, _blue],
                    t: _controller1.value,
                    phaseOffset: 0,
                    motionScale: clear ? 0.4 : 1.0,
                    sizeRatio: 0.4,
                  ),

                  _OrbData(
                    size: clear ? 550 : 700,
                    anchorTopRight: true,
                    baseOffset: const Offset(80, -180),
                    colors: [_purpleLight, _purple],
                    t: _controller2.value,
                    phaseOffset: math.pi / 2,
                    motionScale: clear ? 0.4 : 1.0,
                    sizeRatio: 0.5,
                  ),

                  _OrbData(
                    size: clear ? 400 : 550,
                    anchorCenter: !clear,
                    anchorBottomLeft: clear,
                    baseOffset: clear ? const Offset(60, 100) : const Offset(0, 200),
                    colors: [_emeraldLight, _emerald],
                    t: _controller3.value,
                    phaseOffset: math.pi,
                    motionScale: clear ? 0.4 : 1.0,
                    sizeRatio: 0.6,
                  ),
                ],
                opacity: orbOpacity,
              ),
              size: Size.infinite,
            );
          },
          ),
        ),


        AnimatedBuilder(
          animation: _dotGridController,
          builder: (context, child) {
            return CustomPaint(
              painter: _DotGridPainter(
                t: _dotGridController.value,
                isDark: isDark,
              ),
              size: Size.infinite,
            );
          },
        ),


        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.4,
              colors: [
                Colors.transparent,
                (isDark ? _darkBg : _lightBg).withValues(alpha: 0.8),
              ],
              stops: const [0.3, 1.0],
            ),
          ),
        ),

        widget.child,
      ],
    );
  }
}

class _OrbData {
  final double size;
  final Offset baseOffset;
  final bool anchorTopRight;
  final bool anchorBottomLeft;
  final bool anchorBottomRight;
  final bool anchorCenter;
  final List<Color> colors;
  final double t;
  final double phaseOffset;
  final double motionScale;
  final double sizeRatio;

  _OrbData({
    required this.size,
    required this.baseOffset,
    this.anchorTopRight = false,
    this.anchorBottomLeft = false,
    this.anchorBottomRight = false,
    this.anchorCenter = false,
    required this.colors,
    required this.t,
    required this.phaseOffset,
    this.motionScale = 1.0,
    this.sizeRatio = 0.4,
  });
}

class _OrbsPainter extends CustomPainter {
  final List<_OrbData> orbs;
  final double opacity;

  _OrbsPainter({
    required this.orbs,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final orb in orbs) {
      final angle = orb.t * 2 * math.pi;
      final m = orb.motionScale;

      final dx = (math.sin(angle + orb.phaseOffset) * 60 +
          math.sin(angle * 0.7 + orb.phaseOffset) * 30) * m;
      final dy = (math.cos(angle * 1.3 + orb.phaseOffset) * 40 +
          math.cos(angle * 0.5 + orb.phaseOffset) * 20) * m;
      final scale = 1.0 + math.sin(angle * 0.8 + orb.phaseOffset) * 0.15;

      final scaledSize = orb.size * scale;
      final radius = scaledSize / 2;

      Offset center;
      if (orb.anchorTopRight) {
        center = Offset(
          size.width + orb.baseOffset.dx + dx,
          orb.baseOffset.dy + radius + dy,
        );
      } else if (orb.anchorBottomLeft) {
        center = Offset(
          orb.baseOffset.dx + radius + dx,
          size.height + orb.baseOffset.dy + dy,
        );
      } else if (orb.anchorBottomRight) {
        center = Offset(
          size.width + orb.baseOffset.dx + dx,
          size.height + orb.baseOffset.dy + dy,
        );
      } else if (orb.anchorCenter) {
        center = Offset(
          size.width / 2 + dx,
          size.height / 2 + dy,
        );
      } else {

        center = Offset(
          size.width * orb.sizeRatio * 0.3 + orb.baseOffset.dx + dx,
          size.height * orb.sizeRatio * 0.3 + orb.baseOffset.dy + dy,
        );
      }

      final gradient = RadialGradient(
        colors: [
          orb.colors[0].withValues(alpha: opacity),
          orb.colors[0].withValues(alpha: opacity * 0.7),
          orb.colors[1].withValues(alpha: opacity * 0.3),
          orb.colors[1].withValues(alpha: 0),
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      );

      final paint = Paint()
        ..shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: radius),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal,
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ? 20 : 50);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbsPainter oldDelegate) {

    for (int i = 0; i < orbs.length; i++) {
      if ((orbs[i].t - oldDelegate.orbs[i].t).abs() > 0.005) return true;
    }
    return false;
  }
}

class _DotGridPainter extends CustomPainter {
  final double t;
  final bool isDark;

  _DotGridPainter({required this.t, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 32.0;
    final offsetX = -t * spacing;
    final offsetY = -t * spacing;

    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.04 : 0.06)
      ..style = PaintingStyle.fill;

    for (double x = offsetX; x < size.width + spacing; x += spacing) {
      for (double y = offsetY; y < size.height + spacing; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.isDark != isDark;
}
