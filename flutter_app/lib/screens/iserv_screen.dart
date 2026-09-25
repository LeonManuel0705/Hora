// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/iserv_provider.dart';
import '../models/iserv.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/iserv_webview_login.dart';

class IServScreen extends StatefulWidget {
  const IServScreen({super.key});

  @override
  State<IServScreen> createState() => _IServScreenState();
}

class _IServScreenState extends State<IServScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IServProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showLoginDialog() {
    final urlController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : null,
        title: const Text('Mit IServ verbinden'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gib deine IServ-URL und Anmeldedaten ein, oder nutze den WebView-Login.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'IServ URL',
                  hintText: 'z.B. gymnasium.iserv.de',
                  prefixIcon: Icon(Icons.public),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Benutzername',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _directLogin(
                  dialogContext,
                  urlController.text.trim(),
                  usernameController.text.trim(),
                  passwordController.text,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => _directLogin(
              dialogContext,
              urlController.text.trim(),
              usernameController.text.trim(),
              passwordController.text,
            ),
            child: const Text('Direkt anmelden'),
          ),
          ElevatedButton(
            onPressed: () => _startWebViewLogin(dialogContext, urlController.text.trim()),
            child: const Text('WebView Login'),
          ),
        ],
      ),
    ).then((_) {
      urlController.dispose();
      usernameController.dispose();
      passwordController.dispose();
    });
  }

  Future<void> _directLogin(BuildContext dialogContext, String url, String username, String password) async {
    if (url.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte alle Felder ausfüllen'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(dialogContext);

    final provider = context.read<IServProvider>();
    final result = await provider.connect(
      username: username,
      password: password,
      iservUrl: url,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erfolgreich mit IServ verbunden'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Anmeldung fehlgeschlagen'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startWebViewLogin(BuildContext dialogContext, String url) {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte IServ-URL eingeben'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pop(dialogContext);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => IServWebViewLogin(
          iservUrl: url,
          onLoginSuccess: (cookies, username) async {
            final provider = routeContext.read<IServProvider>();
            Navigator.of(routeContext).pop();

            final result = await provider.connectWithWebViewCookies(
              iservUrl: url,
              cookies: cookies,
              username: username,
            );

            if (!mounted) return;

            if (result['success'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Erfolgreich mit IServ verbunden'),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result['error'] ?? 'Anmeldung fehlgeschlagen'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          onCancel: () {
            Navigator.of(routeContext).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: AppTheme.gradientText('IServ', fontSize: 36),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          Consumer<IServProvider>(
            builder: (context, provider, child) {
              if (!provider.isConnected) return const SizedBox();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: provider.isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    onPressed: provider.isSyncing ? null : () => provider.syncData(),
                    tooltip: 'Aktualisieren',
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: AppTheme.error),
                    onPressed: () => _showDisconnectDialog(provider),
                    tooltip: 'Trennen',
                  ),
                ],
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Nachrichten'),
            Tab(text: 'Aufgaben'),
            Tab(text: 'Termine'),
            Tab(text: 'Vertretung'),
          ],
        ),
      ),
      body: Consumer<IServProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.isConnected) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!provider.isConnected && provider.username == null) {
            return _NotConnectedView(onConnect: _showLoginDialog);
          }

          return Column(
            children: [
              if (provider.error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppTheme.error.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          provider.error!,
                          style: const TextStyle(color: AppTheme.error, fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () => provider.syncData(),
                        child: const Text('Erneut'),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _NotificationsTab(notifications: provider.notifications),
                    _ExercisesTab(exercises: provider.exercises),
                    _EventsTab(events: provider.events),
                    const _VertretungsplanTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<IServProvider>(
        builder: (context, provider, child) {
          if (provider.isConnected) return const SizedBox();
          return FloatingActionButton.extended(
            heroTag: 'fab_iserv_connect',
            onPressed: _showLoginDialog,
            backgroundColor: AppTheme.primaryColor,
            icon: const Icon(Icons.login),
            label: const Text('Verbinden'),
          );
        },
      ),
    );
  }

  void _showDisconnectDialog(IServProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Von IServ trennen?'),
        content: const Text('Deine Anmeldedaten werden gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.disconnect();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Trennen'),
          ),
        ],
      ),
    );
  }
}

class _NotConnectedView extends StatelessWidget {
  final VoidCallback onConnect;

  const _NotConnectedView({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 120),
            child: Center(
              child: GlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        size: 48,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Mit IServ verbinden',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Text(
                        'Verbinde dich mit deinem IServ-Konto um Nachrichten, Aufgaben und Termine zu sehen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: onConnect,
                      icon: const Icon(Icons.login),
                      label: const Text('Anmelden'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationsTab extends StatelessWidget {
  final List<IServNotification> notifications;

  const _NotificationsTab({required this.notifications});

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return const _EmptyTabView(
        icon: Icons.notifications_outlined,
        message: 'Keine Nachrichten',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final notification = notifications[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            borderRadius: 16,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: notification.read
                      ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : const Color(0xFFF4F4F5))
                      : AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  notification.read
                      ? Icons.mail_outlined
                      : Icons.mail,
                  color: notification.read
                      ? (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)
                      : AppTheme.primary,
                ),
              ),
              title: Text(
                notification.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: notification.read
                      ? FontWeight.normal
                      : FontWeight.bold,
                ),
              ),
              subtitle: notification.message != null
                  ? Text(
                      notification.message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: Text(
                _formatDate(notification.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return 'vor ${diff.inMinutes} Min.';
    } else if (diff.inHours < 24) {
      return 'vor ${diff.inHours} Std.';
    } else if (diff.inDays < 7) {
      return 'vor ${diff.inDays} Tagen';
    } else {
      return '${date.day}.${date.month}.';
    }
  }
}

class _ExercisesTab extends StatelessWidget {
  final List<IServExercise> exercises;

  const _ExercisesTab({required this.exercises});

  @override
  Widget build(BuildContext context) {
    if (exercises.isEmpty) {
      return const _EmptyTabView(
        icon: Icons.assignment_outlined,
        message: 'Keine Aufgaben',
      );
    }

    final openExercises = exercises.where((e) => e.status == 'open').toList();
    final completedExercises = exercises.where((e) => e.status != 'open').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (openExercises.isNotEmpty) ...[
          Text(
            'Offen (${openExercises.length})',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          ...openExercises.map((e) => _ExerciseCard(exercise: e)),
        ],
        if (completedExercises.isNotEmpty) ...[
          const SizedBox(height: 24),
          Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Text(
              'Erledigt (${completedExercises.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            );
          }),
          const SizedBox(height: 12),
          ...completedExercises.map((e) => _ExerciseCard(exercise: e)),
        ],
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final IServExercise exercise;

  const _ExerciseCard({required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (exercise.isOverdue)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Überfällig',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (exercise.course != null) ...[
                  if (exercise.isOverdue) const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      exercise.course!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              exercise.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (exercise.description != null) ...[
              const SizedBox(height: 4),
              Text(
                exercise.description!,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (exercise.dueDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: exercise.isOverdue
                        ? AppTheme.error
                        : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Fällig: ${_formatDate(exercise.dueDate!)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: exercise.isOverdue
                          ? AppTheme.error
                          : (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
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

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }
}

class _EventsTab extends StatelessWidget {
  final List<IServEvent> events;

  const _EventsTab({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const _EmptyTabView(
        icon: Icons.event_outlined,
        message: 'Keine Termine',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            borderRadius: 16,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (event.startTime != null) ...[
                      Text(
                        '${event.startTime!.day}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                      ),
                      Text(
                        _monthAbbr(event.startTime!.month),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (event.startTime != null)
                    Text(
                      event.allDay
                          ? 'Ganztägig'
                          : '${event.startTime!.hour}:${event.startTime!.minute.toString().padLeft(2, '0')} Uhr',
                      style: const TextStyle(fontSize: 13),
                    ),
                  if (event.location != null)
                    Text(
                      event.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _monthAbbr(int month) {
    const months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    return months[month - 1];
  }
}

class _EmptyTabView extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyTabView({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VertretungsplanTab extends StatefulWidget {
  const _VertretungsplanTab();

  @override
  State<_VertretungsplanTab> createState() => _VertretungsplanTabState();
}

class _VertretungsplanTabState extends State<_VertretungsplanTab> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVertretungsplan();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _loadVertretungsplan() {
    context.read<IServProvider>().fetchVertretungsplan();
  }

  String _formatCacheTime(DateTime? cachedAt) {
    if (cachedAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(cachedAt);

    if (diff.inMinutes < 1) {
      return 'gerade eben';
    } else if (diff.inMinutes < 60) {
      return 'vor ${diff.inMinutes} Min.';
    } else if (diff.inHours < 24) {
      return 'vor ${diff.inHours} Std.';
    } else {
      return '${cachedAt.day}.${cachedAt.month}. ${cachedAt.hour}:${cachedAt.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<IServProvider>(
      builder: (context, provider, child) {
        if (provider.isVertretungsplanLoading && provider.vertretungsplanFiles.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.vertretungsplanError != null && provider.vertretungsplanFiles.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: GlassCard(
                borderRadius: 16,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: AppTheme.error.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      provider.vertretungsplanError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadVertretungsplan,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Erneut versuchen'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (provider.vertretungsplanFiles.isEmpty) {
          return const _EmptyTabView(
            icon: Icons.calendar_today_outlined,
            message: 'Kein Vertretungsplan verfügbar',
          );
        }

        return Column(
          children: [
            if (provider.isVertretungsplanFromCache)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.orange.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline-Modus${provider.vertretungsplanCachedAt != null ? ' (${_formatCacheTime(provider.vertretungsplanCachedAt)})' : ''}',
                        style: const TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: provider.isVertretungsplanLoading ? null : _loadVertretungsplan,
                      child: provider.isVertretungsplanLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Aktualisieren'),
                    ),
                  ],
                ),
              ),

            if (provider.vertretungsplanFiles.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: AppTheme.darkSurface,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _currentPage > 0
                          ? () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      'Seite ${_currentPage + 1} von ${provider.vertretungsplanFiles.length}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    IconButton(
                      onPressed: _currentPage < provider.vertretungsplanFiles.length - 1
                          ? () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: provider.vertretungsplanFiles.length,
                itemBuilder: (context, index) {
                  final file = provider.vertretungsplanFiles[index];
                  return _buildImageContent(file);
                },
              ),
            ),

            SafeArea(
              top: false,
              child: Container(
              padding: const EdgeInsets.all(12),
              color: AppTheme.darkSurface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: provider.isVertretungsplanLoading ? null : _loadVertretungsplan,
                    icon: provider.isVertretungsplanLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    tooltip: 'Aktualisieren',
                  ),
                ],
              ),
            ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImageContent(Map<String, dynamic> file) {
    final data = file['data'] as String?;

    if (data == null || data.isEmpty) {
      return const _EmptyTabView(
        icon: Icons.image_not_supported_outlined,
        message: 'Bild konnte nicht geladen werden',
      );
    }

    try {
      final bytes = base64Decode(data);

      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const _EmptyTabView(
                icon: Icons.broken_image_outlined,
                message: 'Bild konnte nicht angezeigt werden',
              );
            },
          ),
        ),
      );
    } catch (e) {
      return const _EmptyTabView(
        icon: Icons.error_outline,
        message: 'Fehler beim Dekodieren des Bildes',
      );
    }
  }
}
