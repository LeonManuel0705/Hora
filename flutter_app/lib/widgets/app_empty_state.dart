// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import '../theme.dart';

class AppEmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isCompact;
  final Color? iconColor;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.isCompact = false,
    this.iconColor,
  });

  @override
  State<AppEmptyState> createState() => _AppEmptyStateState();

  static Widget noTasks({VoidCallback? onAdd}) {
    return AppEmptyState(
      icon: Icons.task_alt,
      title: 'Keine Aufgaben',
      message: 'Füge deine erste Aufgabe hinzu',
      actionLabel: onAdd != null ? 'Aufgabe hinzufügen' : null,
      onAction: onAdd,
    );
  }

  static Widget noEvents({VoidCallback? onAdd}) {
    return AppEmptyState(
      icon: Icons.event,
      title: 'Keine Termine',
      message: 'Erstelle einen neuen Termin',
      actionLabel: onAdd != null ? 'Termin hinzufügen' : null,
      onAction: onAdd,
    );
  }

  static Widget noResults() {
    return const AppEmptyState(
      icon: Icons.search_off,
      title: 'Keine Ergebnisse',
      message: 'Versuche eine andere Suche',
      isCompact: true,
    );
  }

  static Widget offline() {
    return const AppEmptyState(
      icon: Icons.cloud_off,
      title: 'Offline',
      message: 'Du bist offline. Einige Funktionen sind eingeschränkt.',
      isCompact: true,
    );
  }

  static Widget error({String? message, VoidCallback? onRetry}) {
    return AppEmptyState(
      icon: Icons.error_outline,
      title: 'Fehler',
      message: message ?? 'Etwas ist schief gelaufen',
      actionLabel: onRetry != null ? 'Erneut versuchen' : null,
      onAction: onRetry,
      iconColor: AppTheme.error,
    );
  }

  static Widget loading({String? message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message),
          ],
        ],
      ),
    );
  }
}

class _AppEmptyStateState extends State<AppEmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.iconColor ?? (isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.1));

    if (widget.isCompact) {
      return _buildCompact(context, color, isDark);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _floatAnimation,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _floatAnimation.value),
                child: child,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 64,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.message != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (widget.onAction != null && widget.actionLabel != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: widget.onAction,
                icon: const Icon(Icons.add),
                label: Text(widget.actionLabel!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _floatAnimation,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _floatAnimation.value),
              child: child,
            ),
            child: Icon(
              widget.icon,
              size: 48,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            ),
            textAlign: TextAlign.center,
          ),
          if (widget.onAction != null && widget.actionLabel != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onAction,
              child: Text(widget.actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
