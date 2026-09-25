// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/platform_utils.dart';

class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool isSelected;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double blurSigma;
  final Color? selectedColor;

  const GlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.isSelected = false,
    this.padding,
    this.borderRadius = 12,
    this.blurSigma = 8,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = selectedColor ?? AppTheme.primaryColor;

    final buttonContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: isDark ? 0.25 : 0.2)
                : (isDark
                    ? Colors.white.withValues(alpha: shouldUseBlur ? 0.06 : 0.12)
                    : Colors.white.withValues(alpha: shouldUseBlur ? 0.5 : 0.7)),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: isDark ? 0.5 : 0.4)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.6)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: isSelected
                  ? accentColor
                  : (isDark ? Colors.white : Colors.black87),
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: isSelected
                    ? accentColor
                    : (isDark ? Colors.white70 : Colors.black54),
                size: 20,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: shouldUseBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: buttonContent,
            )
          : buttonContent,
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isSelected;
  final double size;
  final Color? selectedColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.isSelected = false,
    this.size = 40,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = selectedColor ?? AppTheme.primaryColor;

    final iconButtonContent = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: isDark ? 0.25 : 0.2)
                : (isDark
                    ? Colors.white.withValues(alpha: shouldUseBlur ? 0.06 : 0.12)
                    : Colors.white.withValues(alpha: shouldUseBlur ? 0.5 : 0.7)),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.5)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.6)),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: size * 0.5,
            color: isSelected
                ? accentColor
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: shouldUseBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: iconButtonContent,
            )
          : iconButtonContent,
    );
  }
}

class GlassSegmentedButton<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;
  final double borderRadius;

  const GlassSegmentedButton({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final segmentedContent = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: shouldUseBlur ? 0.06 : 0.12)
            : Colors.white.withValues(alpha: shouldUseBlur ? 0.5 : 0.7),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: values.map((value) {
          final isSelected = value == selected;
          return Padding(
            padding: EdgeInsets.only(
              left: values.indexOf(value) > 0 ? 4 : 0,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(value),
                borderRadius: BorderRadius.circular(borderRadius - 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha:
                            isDark ? 0.25 : 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(borderRadius - 4),
                    border: isSelected
                        ? Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.4),
                          )
                        : null,
                  ),
                  child: Text(
                    labelBuilder(value),
                    style: TextStyle(
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white70 : Colors.black54),
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: shouldUseBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: segmentedContent,
            )
          : segmentedContent,
    );
  }
}
