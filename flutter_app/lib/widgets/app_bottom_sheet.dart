// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/platform_utils.dart';
import 'page_fade_in.dart';

class AppBottomSheet extends StatelessWidget {
  final String? title;
  final Widget child;
  final List<Widget>? actions;
  final bool showHandle;
  final bool showCloseButton;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  const AppBottomSheet({
    super.key,
    this.title,
    required this.child,
    this.actions,
    this.showHandle = true,
    this.showCloseButton = true,
    this.initialChildSize = 0.6,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.9,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    List<Widget>? actions,
    bool showHandle = true,
    bool showCloseButton = true,
    double initialChildSize = 0.6,
    double minChildSize = 0.25,
    double maxChildSize = 0.9,
    bool isScrollControlled = true,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      backgroundColor: Colors.transparent,
      builder: (context) => AppBottomSheet(
        title: title,
        actions: actions,
        showHandle: showHandle,
        showCloseButton: showCloseButton,
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      expand: false,
      builder: (context, scrollController) {
        final sheetContainer = Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: shouldUseBlur ? 0.7 : 0.85)
                : Colors.white.withValues(alpha: shouldUseBlur ? 0.85 : 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1.5,
              ),
              left: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1.5,
              ),
              right: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1.5,
              ),
            ),
          ),
          child: Column(
            children: [
              if (showHandle) _buildHandle(),
              if (title != null || showCloseButton) _buildHeader(context, isDark),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: PageFadeIn(
                    delay: const Duration(milliseconds: 150),
                    child: child,
                  ),
                ),
              ),
              if (actions != null) _buildActions(context, isDark),
            ],
          ),
        );

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: shouldUseBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: sheetContainer,
                )
              : sheetContainer,
        );
      },
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppPalette.ring.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        showHandle ? 0 : 16,
        showCloseButton ? 8 : 16,
        8,
      ),
      child: Row(
        children: [
          if (title != null)
            Expanded(
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (showCloseButton)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: actions!.map((action) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: action,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class AppActionSheet extends StatelessWidget {
  final String? title;
  final List<AppActionItem> actions;

  const AppActionSheet({
    super.key,
    this.title,
    required this.actions,
  });

  static Future<void> show({
    required BuildContext context,
    String? title,
    required List<AppActionItem> actions,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => AppActionSheet(
        title: title,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final actionSheetContainer = Container(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: shouldUseBlur ? 0.7 : 0.85)
            : Colors.white.withValues(alpha: shouldUseBlur ? 0.85 : 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppPalette.ring.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
          ],
          ...actions.map((action) => _buildActionTile(context, action, isDark)),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: shouldUseBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: actionSheetContainer,
            )
          : actionSheetContainer,
    );
  }

  Widget _buildActionTile(BuildContext context, AppActionItem action, bool isDark) {
    final color = action.isDestructive ? AppTheme.error : action.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.8),
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (color ?? AppTheme.primary).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            action.icon,
            color: color ?? AppTheme.primary,
          ),
        ),
        title: Text(
          action.label,
          style: TextStyle(
            color: action.isDestructive ? AppTheme.error : null,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: action.subtitle != null ? Text(action.subtitle!) : null,
        onTap: () {
          Navigator.pop(context);
          action.onTap();
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class AppActionItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final bool isDestructive;

  const AppActionItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.color,
    this.isDestructive = false,
  });
}
