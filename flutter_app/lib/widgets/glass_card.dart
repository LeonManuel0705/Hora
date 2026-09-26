// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';

import '../theme.dart';

BoxDecoration appSurface(bool isDark, double radius, {Color? tint, bool border = true, Gradient? gradient, BoxBorder? customBorder}) {
  final base = isDark ? AppPalette.surfaceDark : AppPalette.surface;
  return BoxDecoration(
    color: gradient == null ? (tint == null ? base : Color.alphaBlend(tint.withValues(alpha: isDark ? .10 : .07), base)) : null,
    gradient: gradient,
    borderRadius: BorderRadius.circular(radius > 20 ? 20 : radius),
    border: customBorder ?? (border ? Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line) : null),
  );
}

class GlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final double blurSigma;
  final Color? tint;
  final bool hasBorder;
  final bool hasShadow;
  final bool enableTapScale;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 20,
    this.blurSigma = 0,
    this.tint,
    this.hasBorder = true,
    this.hasShadow = false,
    this.enableTapScale = true,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(duration: const Duration(milliseconds: 110), vsync: this);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.borderRadius > 20 ? 20 : widget.borderRadius);
    final hasTap = widget.onTap != null || widget.onLongPress != null;

    Widget content = Container(
      padding: widget.padding ?? const EdgeInsets.all(16),
      decoration: appSurface(isDark, widget.borderRadius, tint: widget.tint, border: widget.hasBorder),
      child: widget.child,
    );

    if (hasTap) {
      content = Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: widget.enableTapScale ? (_) => _press.forward() : null,
          onTapUp: widget.enableTapScale ? (_) => _press.reverse() : null,
          onTapCancel: widget.enableTapScale ? () => _press.reverse() : null,
          borderRadius: radius,
          child: content,
        ),
      );
      if (widget.enableTapScale) {
        content = AnimatedBuilder(
          animation: _press,
          builder: (context, child) => Transform.scale(scale: 1 - .03 * Curves.easeOut.transform(_press.value), child: child),
          child: content,
        );
      }
    }

    return Container(margin: widget.margin, child: content);
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurSigma;
  final Color? tint;
  final BoxBorder? border;
  final Gradient? gradient;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.blurSigma = 0,
    this.tint,
    this.border,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: padding,
      decoration: appSurface(isDark, borderRadius, tint: tint, gradient: gradient, customBorder: border),
      child: child,
    );
  }
}
