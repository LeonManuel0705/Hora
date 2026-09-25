// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme.dart';

class ConnectionIndicator extends StatefulWidget {
  final Widget child;

  const ConnectionIndicator({
    super.key,
    required this.child,
  });

  @override
  State<ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<ConnectionIndicator>
    with SingleTickerProviderStateMixin {
  final ConnectivityService _connectivity = ConnectivityService();
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  bool _isOffline = false;
  bool _showBanner = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _connectivity.isOnline.addListener(_onConnectivityChanged);

    _isOffline = !_connectivity.isOnline.value;
    if (_isOffline) {
      _showBanner = true;
      _animationController.forward();
    }
  }

  void _onConnectivityChanged() {
    final isOnline = _connectivity.isOnline.value;

    if (!isOnline && !_isOffline) {

      setState(() {
        _isOffline = true;
        _showBanner = true;
      });
      _animationController.forward();
    } else if (isOnline && _isOffline) {

      setState(() {
        _isOffline = false;
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isOffline) {
          _animationController.reverse().then((_) {
            if (mounted) {
              setState(() => _showBanner = false);
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _connectivity.isOnline.removeListener(_onConnectivityChanged);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        if (_showBanner)
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _slideAnimation.value * 50),
                child: _ConnectionBanner(
                  isOffline: _isOffline,
                ),
              );
            },
          ),

        Expanded(child: widget.child),
      ],
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final bool isOffline;

  const _ConnectionBanner({
    required this.isOffline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isOffline ? AppTheme.warning : AppTheme.success,
        boxShadow: [
          BoxShadow(
            color: (isOffline ? AppTheme.warning : AppTheme.success)
                .withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isOffline ? Icons.wifi_off : Icons.wifi,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              isOffline ? 'Offline-Modus' : 'Wieder online',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineOverlay extends StatelessWidget {
  final String featureName;
  final Widget child;

  const OfflineOverlay({
    super.key,
    required this.featureName,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService().isOnline,
      builder: (context, isOnline, _) {
        if (isOnline) return child;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          children: [
            child,
            Positioned.fill(
              child: Container(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.8),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(32),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkSurface
                          : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wifi_off,
                            size: 48,
                            color: AppTheme.warning,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Offline',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$featureName benötigt eine Internetverbindung.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Bitte stelle eine Verbindung her, um fortzufahren.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService().isOnline,
      builder: (context, isOnline, child) {
        if (isOnline) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.warning.withValues(alpha: 0.5),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off,
                size: 14,
                color: AppTheme.warning,
              ),
              SizedBox(width: 4),
              Text(
                'Offline',
                style: TextStyle(
                  color: AppTheme.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SyncStatusIndicator extends StatelessWidget {
  final int pendingCount;
  final bool isSyncing;

  const SyncStatusIndicator({
    super.key,
    this.pendingCount = 0,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0 && !isSyncing) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSyncing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.info,
              ),
            )
          else
            const Icon(
              Icons.cloud_upload_outlined,
              size: 16,
              color: AppTheme.info,
            ),
          const SizedBox(width: 6),
          Text(
            isSyncing
                ? 'Syncing...'
                : '$pendingCount pending',
            style: const TextStyle(
              color: AppTheme.info,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
