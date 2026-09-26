// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import '../theme.dart';

class AppChipRow extends StatelessWidget {
  final List<String> items;
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  const AppChipRow({
    super.key,
    required this.items,
    this.selected,
    required this.onSelected,
    this.scrollable = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final chips = items.map((item) {
      return _buildChip(context, item, item == selected);
    }).toList();

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: chips),
      );
    }

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(label),
        selectedColor: AppTheme.primary.withValues(alpha: 0.2),
        checkmarkColor: AppTheme.primary,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

class AppFilterChips extends StatelessWidget {
  final List<AppFilterOption> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  const AppFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.scrollable = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final chips = options.map((option) {
      return _buildChip(context, option, selected.contains(option.value));
    }).toList();

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: chips),
      );
    }

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  Widget _buildChip(BuildContext context, AppFilterOption option, bool isSelected) {
    final color = option.color ?? AppTheme.primary;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: option.icon != null
            ? Icon(option.icon, size: 18, color: isSelected ? color : null)
            : null,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(option.label),
            if (option.count != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : AppPalette.ring.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${option.count}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : null,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        selected: isSelected,
        onSelected: (_) {
          final newSelected = Set<String>.from(selected);
          if (isSelected) {
            newSelected.remove(option.value);
          } else {
            newSelected.add(option.value);
          }
          onChanged(newSelected);
        },
        selectedColor: color.withValues(alpha: 0.2),
        checkmarkColor: color,
        labelStyle: TextStyle(
          color: isSelected ? color : null,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

class AppFilterOption {
  final String value;
  final String label;
  final IconData? icon;
  final int? count;
  final Color? color;

  const AppFilterOption({
    required this.value,
    required this.label,
    this.icon,
    this.count,
    this.color,
  });
}

class AppSegmentedControl extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expanded;

  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: List.generate(segments.length, (index) {
          final isSelected = index == selectedIndex;

          Widget segment = GestureDetector(
            onTap: () => onSelected(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                segments[index],
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          );

          if (expanded) {
            segment = Expanded(child: segment);
          }

          return segment;
        }),
      ),
    );
  }
}
