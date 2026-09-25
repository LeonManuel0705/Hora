// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import '../theme.dart';

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final VoidCallback? onActionTap;
  final String? actionLabel;
  final IconData? actionIcon;
  final EdgeInsetsGeometry? padding;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onActionTap,
    this.actionLabel,
    this.actionIcon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null)
            action!
          else if (onActionTap != null)
            TextButton.icon(
              onPressed: onActionTap,
              icon: actionIcon != null
                  ? Icon(actionIcon, size: 18)
                  : const SizedBox(),
              label: Text(actionLabel ?? 'Mehr'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class AppCollapsibleSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry? padding;

  const AppCollapsibleSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.initiallyExpanded = true,
    this.padding,
  });

  @override
  State<AppCollapsibleSection> createState() => _AppCollapsibleSectionState();
}

class _AppCollapsibleSectionState extends State<AppCollapsibleSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: widget.child,
          secondChild: const SizedBox(width: double.infinity),
          crossFadeState: _isExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}
