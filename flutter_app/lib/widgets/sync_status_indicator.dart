// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme.dart';

class SyncStatusIndicator extends StatelessWidget {
  final bool isSyncing;
  final DateTime? lastSync;
  final String? error;
  final VoidCallback? onTap;
  final bool showLabel;
  final bool compact;

  const SyncStatusIndicator({
    super.key,
    this.isSyncing = false,
    this.lastSync,
    this.error,
    this.onTap,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final connectivity = ConnectivityService();

    return ValueListenableBuilder<bool>(
      valueListenable: connectivity.isOnline,
      builder: (context, isOnline, child) {
        if (!isOnline) {
          return _buildOfflineIndicator(context);
        }

        if (error != null) {
          return _buildErrorIndicator(context);
        }

        if (isSyncing) {
          return _buildSyncingIndicator(context);
        }

        return _buildSyncedIndicator(context);
      },
    );
  }

  Widget _buildOfflineIndicator(BuildContext context) {
    if (compact) {
      return _buildCompactIndicator(
        context,
        icon: Icons.cloud_off,
        color: AppTheme.warning,
        tooltip: 'Offline',
      );
    }

    return _buildExpandedIndicator(
      context,
      icon: Icons.cloud_off,
      color: AppTheme.warning,
      label: 'Offline',
      sublabel: 'Änderungen werden synchronisiert, wenn online',
    );
  }

  Widget _buildErrorIndicator(BuildContext context) {
    if (compact) {
      return _buildCompactIndicator(
        context,
        icon: Icons.sync_problem,
        color: AppTheme.error,
        tooltip: 'Sync-Fehler',
      );
    }

    return _buildExpandedIndicator(
      context,
      icon: Icons.sync_problem,
      color: AppTheme.error,
      label: 'Sync-Fehler',
      sublabel: error,
    );
  }

  Widget _buildSyncingIndicator(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
      );
    }

    return _buildExpandedIndicator(
      context,
      icon: Icons.sync,
      color: AppTheme.primary,
      label: 'Synchronisiere...',
      isAnimated: true,
    );
  }

  Widget _buildSyncedIndicator(BuildContext context) {
    if (compact) {
      return _buildCompactIndicator(
        context,
        icon: Icons.cloud_done,
        color: AppTheme.success,
        tooltip: _getLastSyncLabel(),
      );
    }

    return _buildExpandedIndicator(
      context,
      icon: Icons.cloud_done,
      color: AppTheme.success,
      label: 'Synchronisiert',
      sublabel: _getLastSyncLabel(),
    );
  }

  Widget _buildCompactIndicator(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  Widget _buildExpandedIndicator(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    String? sublabel,
    bool isAnimated = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAnimated)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              Icon(icon, color: color, size: 20),
            if (showLabel) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getLastSyncLabel() {
    if (lastSync == null) return 'Noch nie synchronisiert';

    final diff = DateTime.now().difference(lastSync!);
    if (diff.inMinutes < 1) return 'Gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    return '${lastSync!.day}.${lastSync!.month}. ${lastSync!.hour}:${lastSync!.minute.toString().padLeft(2, '0')}';
  }
}

class OfflineBanner extends StatelessWidget {
  final String? message;
  final VoidCallback? onDismiss;

  const OfflineBanner({
    super.key,
    this.message,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final connectivity = ConnectivityService();

    return ValueListenableBuilder<bool>(
      valueListenable: connectivity.isOnline,
      builder: (context, isOnline, child) {
        if (isOnline) return const SizedBox.shrink();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 40,
          color: AppPalette.ochre,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                message ?? 'Du bist offline',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (onDismiss != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class SyncButton extends StatelessWidget {
  final bool isSyncing;
  final VoidCallback? onSync;
  final bool showLabel;

  const SyncButton({
    super.key,
    this.isSyncing = false,
    this.onSync,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    if (showLabel) {
      return TextButton.icon(
        onPressed: isSyncing ? null : onSync,
        icon: isSyncing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync),
        label: Text(isSyncing ? 'Synchronisiere...' : 'Synchronisieren'),
      );
    }

    return IconButton(
      onPressed: isSyncing ? null : onSync,
      icon: isSyncing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      tooltip: 'Synchronisieren',
    );
  }
}
