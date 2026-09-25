// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/platform_utils.dart';

class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool useGlassmorphism;
  final Color? backgroundColor;
  final double borderRadius;
  final bool hasShadow;
  final double blurSigma;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.useGlassmorphism = false,
    this.backgroundColor,
    this.borderRadius = 16,
    this.hasShadow = true,
    this.blurSigma = 10,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.useGlassmorphism) {
      _shimmerController.repeat();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;

    if (widget.useGlassmorphism) {
      return _buildGlassCard(context, isDark);
    }

    Widget cardContent = Container(
      padding: widget.padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? defaultColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: widget.hasShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: widget.child,
    );

    if (widget.onTap != null || widget.onLongPress != null) {
      cardContent = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: cardContent,
        ),
      );
    }

    return Container(
      margin: widget.margin,
      child: cardContent,
    );
  }

  Widget _buildGlassCard(BuildContext context, bool isDark) {
    Widget innerContent = AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            return Stack(
              children: [
                Container(
                  padding: widget.padding ?? const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                    boxShadow: widget.hasShadow
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: widget.child,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      child: Transform.translate(
                        offset: Offset(
                          -200 + (_shimmerController.value * 600),
                          -50,
                        ),
                        child: Transform.rotate(
                          angle: 0.5,
                          child: Container(
                            width: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: isDark ? 0.04 : 0.12),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: shouldUseBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: widget.blurSigma, sigmaY: widget.blurSigma),
              child: innerContent,
            )
          : innerContent,
    );

    if (widget.onTap != null || widget.onLongPress != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: content,
        ),
      );
    }

    return Container(margin: widget.margin, child: content);
  }
}

class AppGradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final List<Color>? gradientColors;
  final double borderRadius;

  const AppGradientCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.gradientColors,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ?? AppTheme.primaryGradient;

    Widget cardContent = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      cardContent = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: cardContent,
        ),
      );
    }

    return Container(
      margin: margin,
      child: cardContent,
    );
  }
}
