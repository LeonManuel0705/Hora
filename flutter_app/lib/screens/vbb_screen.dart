// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vbb_provider.dart';
import '../models/vbb.dart';
import '../theme.dart';
import '../widgets/page_fade_in.dart';

class VbbScreen extends StatefulWidget {
  const VbbScreen({super.key});

  @override
  State<VbbScreen> createState() => _VbbScreenState();
}

class _VbbScreenState extends State<VbbScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<VbbProvider>();
      await provider.initialize();
      if (!mounted) return;

      final isMobile = MediaQuery.of(context).size.width < 900;
      if (isMobile && provider.fromLocation == null && provider.hasHome) {
        provider.setHomeAsFrom();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showLocationSearch(bool isFrom, {String? initialQuery}) {
    _searchController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _LocationSearchSheet(
          isFrom: isFrom,
          scrollController: scrollController,
          initialQuery: initialQuery,
          onLocationSelected: (location) {
            final provider = context.read<VbbProvider>();
            if (isFrom) {
              provider.setFromLocation(location);
            } else {
              provider.setToLocation(location);
            }
            Navigator.pop(context);
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
        title: AppTheme.gradientText('Fahrplan', fontSize: 36),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(text: 'Routenplaner'),
            Tab(text: 'Abfahrten'),
            Tab(text: 'Tickets'),
          ],
        ),
      ),
      body: PageFadeIn(
        child: Consumer<VbbProvider>(
          builder: (context, provider, child) {
            if (provider.pendingDestination != null && !provider.isLoading && !provider.needsSetup) {
              final dest = provider.pendingDestination!;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  provider.clearPendingDestination();
                  _tabController.animateTo(0);
                  if (provider.hasHome && provider.fromLocation == null) {
                    provider.setHomeAsFrom();
                  }
                  _showLocationSearch(false, initialQuery: dest);
                }
              });
            }

            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.needsSetup) {
              return _SetupWizard(
                provider: provider,
                onComplete: () {
                  provider.refreshKnownLocations();
                },
              );
            }

            return TabBarView(
              controller: _tabController,
              children: [
                _RoutePlannerTab(
                  provider: provider,
                  onFromTap: () => _showLocationSearch(true),
                  onToTap: () => _showLocationSearch(false),
                ),
                _DeparturesTab(
                  provider: provider,
                  onStationTap: () => _showStationSearch(provider),
                ),
                _TicketsTab(provider: provider),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showStationSearch(VbbProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _LocationSearchSheet(
          isFrom: false,
          scrollController: scrollController,
          onLocationSelected: (location) {
            provider.setSelectedStation(location);
            provider.loadDepartures();
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

class _LocationSearchSheet extends StatefulWidget {
  final bool isFrom;
  final ScrollController scrollController;
  final void Function(VbbLocation) onLocationSelected;
  final String? initialQuery;

  const _LocationSearchSheet({
    required this.isFrom,
    required this.scrollController,
    required this.onLocationSelected,
    this.initialQuery,
  });

  @override
  State<_LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<_LocationSearchSheet> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<VbbProvider>().searchLocations(widget.initialQuery!);
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        AppBar(
          title: Text(widget.isFrom ? 'Von' : 'Nach'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Station oder Adresse suchen...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
            ),
            onChanged: (value) {
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                context.read<VbbProvider>().searchLocations(value);
              });
            },
          ),
        ),
        Expanded(
          child: Consumer<VbbProvider>(
            builder: (context, provider, child) {

              if (_searchController.text.isEmpty) {
                return ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Text(
                      'Gespeicherte Orte',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...provider.knownLocations.map((location) => ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getAliasIcon(location.alias),
                          color: AppTheme.primary,
                        ),
                      ),
                      title: Text(location.name),
                      subtitle: Text(location.locationName),
                      onTap: () => widget.onLocationSelected(location.toLocation()),
                    )),
                  ],
                );
              }

              if (provider.isSearching) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.searchResults.isEmpty) {
                return Center(
                  child: Text(
                    provider.isOnline
                        ? 'Keine Ergebnisse'
                        : 'Offline - Suche nicht möglich',
                    style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
                  ),
                );
              }

              return ListView.builder(
                controller: widget.scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: provider.searchResults.length,
                itemBuilder: (context, index) {
                  final location = provider.searchResults[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        location.type == 'station'
                            ? Icons.train
                            : Icons.location_on,
                        color: AppTheme.primary,
                      ),
                    ),
                    title: Text(location.name),
                    subtitle: location.productsDisplay.isNotEmpty
                        ? Text(
                            location.productsDisplay,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    onTap: () => widget.onLocationSelected(location),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getAliasIcon(String alias) {
    switch (alias) {
      case 'home':
        return Icons.home;
      case 'school':
        return Icons.school;
      case 'work':
        return Icons.work;
      case 'gym':
        return Icons.fitness_center;
      default:
        return Icons.place;
    }
  }
}

class _RoutePlannerTab extends StatelessWidget {
  final VbbProvider provider;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;

  const _RoutePlannerTab({
    required this.provider,
    required this.onFromTap,
    required this.onToTap,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      return _buildDesktopLayout(context);
    }
    return _buildMobileLayout(context);
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        if (provider.knownLocations.isNotEmpty || provider.favoriteRoutes.isNotEmpty)
          _buildQuickRoutesBar(context, isDark),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildRoutePlannerCard(context, isDark),
                ),
              ),
              Expanded(
                child: _buildRouteResults(context, provider),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 80;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildRoutePlannerCard(context, isDark),
          ),
        ),

        if (provider.knownLocations.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => provider.planRouteToSchool(),
                      icon: const Icon(Icons.school, size: 18),
                      label: const Text('Zur Schule'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => provider.planRouteHome(),
                      icon: const Icon(Icons.home, size: 18),
                      label: const Text('Nach Hause'),
                    ),
                  ),
                ],
              ),
            ),
          ),

        SliverFillRemaining(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: _buildRouteResults(context, provider),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickRoutesBar(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppPalette.lineDark : AppPalette.line,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bolt,
                  size: 18,
                  color: isDark ? AppTheme.warning : AppTheme.warning,
                ),
                const SizedBox(width: 8),
                Text(
                  'Schnellzugriff',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (provider.knownLocations.any((l) => l.alias == 'home') &&
                            provider.knownLocations.any((l) => l.alias == 'school')) ...[
                          _buildQuickRouteChip(
                            context,
                            icon: Icons.school,
                            label: 'Zur Schule',
                            onTap: () => provider.planRouteToSchool(),
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _buildQuickRouteChip(
                            context,
                            icon: Icons.home,
                            label: 'Nach Hause',
                            onTap: () => provider.planRouteHome(),
                            isDark: isDark,
                          ),
                        ],
                        ...provider.favoriteRoutes.map((route) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _buildQuickRouteChip(
                            context,
                            icon: Icons.route,
                            label: route.name,
                            onTap: () {
                              provider.loadFavoriteRoute(route);
                              provider.searchRoutes();
                            },
                            isDark: isDark,
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }

  Widget _buildQuickRouteChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoutePlannerCard(BuildContext context, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppPalette.lineDark : AppPalette.line,
            ),
          ),
          child: Column(
            children: [

              InkWell(
                onTap: onFromTap,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.trip_origin, color: AppTheme.success, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.fromLocation?.name ?? 'Von...',
                        style: TextStyle(
                          color: provider.fromLocation != null
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white54 : Colors.black38),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  const Expanded(child: Divider()),
                  IconButton(
                    icon: const Icon(Icons.swap_vert),
                    onPressed: () => provider.swapLocations(),
                    tooltip: 'Vertauschen',
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: onToTap,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.location_on, color: AppTheme.primary, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.toLocation?.name ?? 'Nach...',
                        style: TextStyle(
                          color: provider.toLocation != null
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white54 : Colors.black38),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: provider.fromLocation != null && provider.toLocation != null
                      ? () => provider.searchRoutes()
                      : null,
                  icon: provider.isLoadingRoutes
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Verbindung suchen'),
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildRouteResults(BuildContext context, VbbProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final futureJourneys = provider.journeys
        .where((j) => j.departure.isAfter(now.subtract(const Duration(minutes: 1))))
        .toList();

    final Widget child;
    if (provider.isLoadingRoutes) {
      child = const Center(key: ValueKey('vbb_loading'), child: CircularProgressIndicator());
    } else if (provider.error != null) {
      child = Center(
        key: const ValueKey('vbb_error'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => provider.searchRoutes(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Erneut suchen'),
              ),
            ],
          ),
        ),
      );
    } else if (provider.journeys.isEmpty) {
      child = Center(
        key: const ValueKey('vbb_empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              provider.hasSearched ? Icons.search_off : Icons.directions_transit,
              size: 64,
              color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              provider.hasSearched
                  ? 'Keine Verbindungen gefunden'
                  : 'Suche nach Verbindungen',
              style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
            ),
            if (provider.hasSearched) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => provider.searchRoutes(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Erneut suchen'),
              ),
            ],
          ],
        ),
      );
    } else if (futureJourneys.isEmpty) {
      child = Center(
        key: const ValueKey('vbb_past'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'Keine aktuellen Verbindungen',
              style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => provider.searchRoutes(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Neu suchen'),
            ),
          ],
        ),
      );
    } else {
      child = ListView.builder(
        key: const ValueKey('vbb_results'),
        padding: const EdgeInsets.all(16),
        itemCount: futureJourneys.length,
        itemBuilder: (context, index) {
          final journey = futureJourneys[index];
          return _JourneyCard(journey: journey);
        },
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final VbbJourney journey;

  const _JourneyCard({required this.journey});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: journey.hasCancellation
                    ? AppTheme.error.withValues(alpha: 0.4)
                    : journey.hasDelays
                        ? AppTheme.warning.withValues(alpha: 0.3)
                        : isDark ? AppPalette.lineDark : AppPalette.line,
              ),
            ),
            child: InkWell(
              onTap: () => _showJourneyDetails(context, journey),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      children: [
                        Text(
                          journey.departureTime,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward, size: 16),
                        ),
                        Text(
                          journey.arrivalTime,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        if (journey.hasDelays) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: journey.hasCancellation
                                  ? AppTheme.error.withValues(alpha: 0.15)
                                  : AppTheme.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  journey.hasCancellation
                                      ? Icons.cancel
                                      : Icons.warning_amber,
                                  size: 12,
                                  color: journey.hasCancellation
                                      ? AppTheme.error
                                      : AppTheme.warning,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  journey.delayInfo,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: journey.hasCancellation
                                        ? AppTheme.error
                                        : AppTheme.warning,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            journey.durationDisplay,
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        ...journey.legs
                            .where((leg) => !leg.isWalking && leg.line != null)
                            .take(4)
                            .map((leg) => _buildLineBadge(context, leg)),
                        if (journey.transfers > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${journey.transfers} Umstieg${journey.transfers > 1 ? 'e' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (journey.price != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${journey.price!.toStringAsFixed(2).replaceAll('.', ',')} €',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.success : AppPalette.sageInk,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ),
    );
  }

  Widget _buildLineBadge(BuildContext context, VbbLeg leg) {
    Color bgColor;
    switch (leg.mode) {
      case 'suburban':
        bgColor = AppTheme.success;
        break;
      case 'subway':
        bgColor = AppPalette.slate;
        break;
      case 'tram':
        bgColor = AppTheme.danger;
        break;
      case 'bus':
        bgColor = AppPalette.plum;
        break;
      default:
        bgColor = AppPalette.ring;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: leg.cancelled ? AppPalette.ring : bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leg.cancelled)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.cancel, size: 10, color: Colors.white),
                ),
              Text(
                leg.line ?? '',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  decoration: leg.cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
        if (leg.isDelayed && !leg.cancelled)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              leg.delayDisplay,
              style: const TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          )
        else
          const SizedBox(width: 4),
      ],
    );
  }

  void _showJourneyDetails(BuildContext context, VbbJourney journey) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            AppBar(
              title: const Text('Verbindungsdetails'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: journey.legs.length,
                itemBuilder: (context, index) {
                  final leg = journey.legs[index];
                  return _LegDetailCard(leg: leg, isLast: index == journey.legs.length - 1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegDetailCard extends StatelessWidget {
  final VbbLeg leg;
  final bool isLast;

  const _LegDetailCard({
    required this.leg,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (leg.isWalking) {
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: const Icon(Icons.directions_walk, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Fußweg (${(leg.duration ?? 0) ~/ 60} Min.)',
              style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6)),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              alignment: Alignment.center,
              child: Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 60,
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        leg.departureTime,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (leg.isDelayed) ...[
                        const SizedBox(width: 6),
                        Text(
                          leg.delayDisplay,
                          style: const TextStyle(
                            color: AppTheme.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          leg.origin.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (leg.cancelled) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cancel, size: 14, color: AppTheme.error),
                          SizedBox(width: 4),
                          Text(
                            'Fahrt fällt aus',
                            style: TextStyle(
                              color: AppTheme.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildLineBadge(context),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Richtung ${leg.direction ?? ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (leg.platform != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Gleis/Steig ${leg.platform}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        if (isLast)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      leg.arrivalTime,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        leg.destination.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildLineBadge(BuildContext context) {
    Color bgColor;
    switch (leg.mode) {
      case 'suburban':
        bgColor = AppTheme.success;
        break;
      case 'subway':
        bgColor = AppPalette.slate;
        break;
      case 'tram':
        bgColor = AppTheme.danger;
        break;
      case 'bus':
        bgColor = AppPalette.plum;
        break;
      default:
        bgColor = AppPalette.ring;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        leg.line ?? '',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DeparturesTab extends StatelessWidget {
  final VbbProvider provider;
  final VoidCallback onStationTap;

  const _DeparturesTab({
    required this.provider,
    required this.onStationTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [

        Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppPalette.lineDark : AppPalette.line,
                  ),
                ),
                child: InkWell(
                  onTap: onStationTap,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.train, color: AppTheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            provider.selectedStation?.name ?? 'Station auswählen...',
                            style: TextStyle(
                              color: provider.selectedStation != null
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
              ),
          ),
        ),

        Expanded(
          child: _buildDeparturesList(context, provider),
        ),
      ],
    );
  }

  Widget _buildDeparturesList(BuildContext context, VbbProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (provider.selectedStation == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.departure_board,
              size: 64,
              color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'Wähle eine Station',
              style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    if (provider.isLoadingDepartures) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.departures.isEmpty) {
      return Center(
        child: Text(
          provider.isOnline
              ? 'Keine Abfahrten'
              : 'Offline - Abfahrten nicht verfügbar',
          style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
        ),
      );
    }

    final now = DateTime.now();
    final futureDepartures = provider.departures
        .where((d) => d.when.isAfter(now.subtract(const Duration(minutes: 1))))
        .toList();

    if (futureDepartures.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Keine aktuellen Abfahrten',
              style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => provider.loadDepartures(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Aktualisieren'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => provider.loadDepartures(),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 24),
        itemCount: futureDepartures.length,
        itemBuilder: (context, index) {
          final departure = futureDepartures[index];
          return _DepartureCard(departure: departure);
        },
      ),
    );
  }
}

class _DepartureCard extends StatelessWidget {
  final VbbDeparture departure;

  const _DepartureCard({required this.departure});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color lineColor;
    switch (departure.mode) {
      case 'suburban':
        lineColor = AppTheme.success;
        break;
      case 'subway':
        lineColor = AppPalette.slate;
        break;
      case 'tram':
        lineColor = AppTheme.danger;
        break;
      case 'bus':
        lineColor = AppPalette.plum;
        break;
      default:
        lineColor = AppPalette.ring;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppPalette.lineDark : AppPalette.line,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [

                  Container(
                    width: 50,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      departure.line,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          departure.direction,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (departure.platform != null)
                          Text(
                            'Gleis ${departure.platform}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        departure.minutesUntil,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (departure.isDelayed)
                        Text(
                          departure.delayDisplay,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }
}

class _SetupWizard extends StatefulWidget {
  final VbbProvider provider;
  final VoidCallback onComplete;

  const _SetupWizard({
    required this.provider,
    required this.onComplete,
  });

  @override
  State<_SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<_SetupWizard> {
  int _currentStep = 0;
  VbbLocation? _homeLocation;
  VbbLocation? _schoolLocation;
  final _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 80;
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
      children: [
        const SizedBox(height: 32),

        Icon(
          Icons.directions_transit,
          size: 64,
          color: AppTheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Fahrplan Einrichtung',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppPalette.surfaceDark,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Richte deine Orte ein, um schnell Verbindungen zu finden.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white70 : AppPalette.ring,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildProgressDot(context, 0),
            Container(
              width: 40,
              height: 2,
              color: _currentStep >= 2 ? AppTheme.primary : Colors.white24,
            ),
            _buildProgressDot(context, 2),
          ],
        ),
        const SizedBox(height: 32),

        if (_currentStep == 0) _buildHomeIntro(context),
        if (_currentStep == 1) _buildLocationSearch(context, 'Zuhause', true),
        if (_currentStep == 2) _buildSchoolIntro(context),
        if (_currentStep == 3) _buildLocationSearch(context, 'Schule', false),
        if (_currentStep == 4) _buildComplete(context),
      ],
    );
  }

  Widget _buildProgressDot(BuildContext context, int step) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _currentStep >= step;
    final isComplete = step == 0 ? _homeLocation != null : _schoolLocation != null;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isComplete
            ? AppTheme.success
            : isActive
                ? AppTheme.primary
                : Colors.white24,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isComplete
            ? Icons.check
            : step == 0
                ? Icons.home
                : Icons.school,
        color: isDark ? Colors.white : AppPalette.surfaceDark,
        size: 18,
      ),
    );
  }

  Widget _buildHomeIntro(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.home,
                  size: 48,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Wo wohnst du?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppPalette.surfaceDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Suche nach deiner nächsten Haltestelle für den ÖPNV.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : AppPalette.ring,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => setState(() => _currentStep = 1),
            icon: const Icon(Icons.search),
            label: const Text('Haltestelle suchen'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        if (widget.provider.hasHome) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _currentStep = 2),
            child: const Text('Überspringen'),
          ),
        ],
      ],
    );
  }

  Widget _buildSchoolIntro(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.school,
                  size: 48,
                  color: AppTheme.info,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Wo ist deine Schule?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppPalette.surfaceDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Suche nach der nächsten ÖPNV-Haltestelle bei deiner Schule.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : AppPalette.ring,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => setState(() => _currentStep = 3),
            icon: const Icon(Icons.search),
            label: const Text('Schule suchen'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ),
        if (widget.provider.hasSchool) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _currentStep = 4),
            child: const Text('Überspringen'),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationSearch(BuildContext context, String label, bool isHome) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isHome ? 'Nächste Haltestelle suchen...' : 'Haltestelle bei $label suchen...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
          ),
          onChanged: (value) {
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 300), () {
              widget.provider.searchLocations(value);
            });
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 300,
          child: Consumer<VbbProvider>(
            builder: (context, provider, child) {
              if (provider.isSearching) {
                return const Center(child: CircularProgressIndicator());
              }

              if (_searchController.text.length < 2) {
                return Center(
                  child: Text(
                    'Mindestens 2 Zeichen eingeben',
                    style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
                  ),
                );
              }

              if (provider.searchResults.isEmpty) {
                return Center(
                  child: Text(
                    provider.isOnline
                        ? 'Keine Ergebnisse'
                        : 'Offline - Suche nicht möglich',
                    style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
                  ),
                );
              }

              return ListView.builder(
                itemCount: provider.searchResults.length,
                itemBuilder: (context, index) {
                  final location = provider.searchResults[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        location.type == 'station'
                            ? Icons.train
                            : Icons.location_on,
                        color: AppTheme.primary,
                      ),
                    ),
                    title: Text(location.name),
                    subtitle: location.productsDisplay.isNotEmpty
                        ? Text(location.productsDisplay, style: const TextStyle(fontSize: 12))
                        : null,
                    onTap: () async {
                      try {
                        if (isHome) {
                          await widget.provider.addKnownLocation(
                            name: 'Zuhause',
                            alias: 'home',
                            location: location,
                          );
                          _homeLocation = location;
                          _searchController.clear();
                          setState(() => _currentStep = 2);
                        } else {
                          await widget.provider.addKnownLocation(
                            name: 'Schule',
                            alias: 'school',
                            location: location,
                          );
                          _schoolLocation = location;
                          _searchController.clear();
                          setState(() => _currentStep = 4);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Fehler beim Speichern. Bitte versuche es erneut.'),
                              backgroundColor: AppTheme.danger,
                            ),
                          );
                        }
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _currentStep = isHome ? 0 : 2);
          },
          child: const Text('Zurück'),
        ),
      ],
    );
  }

  Widget _buildComplete(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 48,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Alles eingerichtet!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppPalette.surfaceDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Du kannst jetzt schnell Verbindungen zwischen Zuhause und Schule finden.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : AppPalette.ring,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              if (_homeLocation != null || widget.provider.hasHome)
                _buildConfiguredLocation(
                  'Zuhause',
                  _homeLocation?.name ?? widget.provider.homeLocation?.locationName ?? '',
                  Icons.home,
                  AppTheme.primary,
                ),
              const SizedBox(height: 12),
              if (_schoolLocation != null || widget.provider.hasSchool)
                _buildConfiguredLocation(
                  'Schule',
                  _schoolLocation?.name ?? widget.provider.schoolLocation?.locationName ?? '',
                  Icons.school,
                  AppTheme.info,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.onComplete,
            icon: const Icon(Icons.check),
            label: const Text('Fertig'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(16),
              backgroundColor: AppTheme.success,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfiguredLocation(String label, String name, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  name,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: color),
        ],
      ),
    );
  }
}

class _TicketsTab extends StatelessWidget {
  final VbbProvider provider;

  const _TicketsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        if (provider.tickets.isEmpty)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  size: 64,
                  color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  'Noch keine Tickets hinterlegt',
                  style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Speichere deine Tickets, um bei der\nRoutensuche die Abdeckung zu sehen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _showAddTicketSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Ticket hinzufügen'),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: provider.tickets.length,
            itemBuilder: (context, index) {
              final ticket = provider.tickets[index];
              return _TicketCard(
                ticket: ticket,
                isDark: isDark,
                onDelete: () => _confirmDeleteTicket(context, ticket),
                onTap: () => _showTicketDetails(context, ticket),
              );
            },
          ),
        if (provider.tickets.isNotEmpty)
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: FloatingActionButton(
              onPressed: () => _showAddTicketSheet(context),
              backgroundColor: AppTheme.primaryColor,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  void _showAddTicketSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _AddTicketSheet(provider: provider),
      ),
    );
  }

  void _showTicketDetails(BuildContext context, VbbTicket ticket) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.confirmation_number,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.ticketName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppPalette.surfaceDark,
                        ),
                      ),
                      Text(
                        ticket.zoneDisplay,
                        style: TextStyle(
                          color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDetailRow(Icons.schedule, 'Gültigkeit', ticket.validityDisplay, isDark),
            if (ticket.validFrom != null)
              _buildDetailRow(
                Icons.calendar_today,
                'Gültig ab',
                '${ticket.validFrom!.day.toString().padLeft(2, '0')}.${ticket.validFrom!.month.toString().padLeft(2, '0')}.${ticket.validFrom!.year}',
                isDark,
              ),
            if (ticket.autoRenews)
              _buildDetailRow(Icons.autorenew, 'Typ', 'Abo (verlängert sich automatisch)', isDark),
            _buildDetailRow(
              ticket.isValid ? Icons.check_circle : Icons.cancel,
              'Status',
              ticket.isValid ? 'Gültig' : 'Abgelaufen',
              isDark,
              valueColor: ticket.isValid ? AppTheme.success : AppTheme.error,
            ),
            if (ticket.expiresSoon)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: AppTheme.warning, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Ticket läuft bald ab!',
                        style: TextStyle(color: AppTheme.warning, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _confirmDeleteTicket(context, ticket);
                },
                icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                label: const Text('Ticket löschen', style: TextStyle(color: AppTheme.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, bool isDark, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? (isDark ? Colors.white : AppPalette.surfaceDark),
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTicket(BuildContext context, VbbTicket ticket) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
        title: const Text('Ticket löschen?'),
        content: Text('${ticket.ticketName} wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              provider.removeTicket(ticket.id);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final VbbTicket ticket;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _TicketCard({
    required this.ticket,
    required this.isDark,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isExpired = !ticket.isValid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppPalette.surfaceDark : AppPalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isExpired
                    ? AppTheme.error.withValues(alpha: 0.3)
                    : ticket.expiresSoon
                        ? AppTheme.warning.withValues(alpha: 0.3)
                        : isDark ? AppPalette.lineDark : AppPalette.line,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isExpired
                            ? AppTheme.error.withValues(alpha: 0.15)
                            : AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.confirmation_number,
                        color: isExpired ? AppTheme.error : AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ticket.ticketName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: isExpired
                                  ? isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5)
                                  : (isDark ? Colors.white : AppPalette.surfaceDark),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? AppPalette.lineDark : AppPalette.line,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  ticket.zoneDisplay,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ticket.validityDisplay,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (ticket.expiresSoon && !isExpired)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Bald',
                          style: TextStyle(
                            color: AppTheme.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (isExpired)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Abgelaufen',
                          style: TextStyle(
                            color: AppTheme.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.check_circle,
                        color: AppTheme.success,
                        size: 20,
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ),
    );
  }
}

class _AddTicketSheet extends StatefulWidget {
  final VbbProvider provider;

  const _AddTicketSheet({required this.provider});

  @override
  State<_AddTicketSheet> createState() => _AddTicketSheetState();
}

class _AddTicketSheetState extends State<_AddTicketSheet> {
  final _nameController = TextEditingController();
  String _selectedZone = 'all';
  String _ticketType = 'custom';
  DateTime? _validFrom;
  DateTime? _validUntil;
  bool _autoRenews = false;

  static const _zoneOptions = [
    ('all', 'Deutschlandweit (Nahverkehr)'),
    ('AB', 'Berlin AB'),
    ('ABC', 'Berlin ABC'),
    ('BC', 'Berlin BC'),
    ('C', 'Zone C'),
  ];

  static const _quickTickets = [
    ('deutschlandticket', 'Deutschlandticket', 'all', true),
    ('berlin_abo', 'Berlin AB Abo', 'AB', true),
    ('berlin_abc_abo', 'Berlin ABC Abo', 'ABC', true),
    ('semester_ticket', 'Semesterticket', 'ABC', false),
    ('schuelerticket', 'Schülerticket Berlin', 'AB', true),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Ticket hinzufügen',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppPalette.surfaceDark,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Schnellauswahl',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : AppPalette.ring,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickTickets.map((qt) {
              final isSelected = _ticketType == qt.$1;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _ticketType = qt.$1;
                      _nameController.text = qt.$2;
                      _selectedZone = qt.$3;
                      _autoRenews = qt.$4;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withValues(alpha: 0.2)
                          : isDark ? AppPalette.hoverDark : AppPalette.sunken,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor.withValues(alpha: 0.5)
                            : isDark ? AppPalette.lineDark : AppPalette.line,
                      ),
                    ),
                    child: Text(
                      qt.$2,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? AppTheme.primaryColor : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Ticket-Name',
              hintText: 'z.B. Deutschlandticket',
              prefixIcon: const Icon(Icons.confirmation_number_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
            ),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            initialValue: _selectedZone,
            decoration: InputDecoration(
              labelText: 'Tarifzone',
              prefixIcon: const Icon(Icons.map_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
            ),
            dropdownColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : Colors.white,
            items: _zoneOptions.map((z) {
              return DropdownMenuItem(
                value: z.$1,
                child: Text(z.$2),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedZone = value);
              }
            },
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildDatePicker(context,
                  label: 'Gültig ab',
                  value: _validFrom,
                  onPicked: (date) => setState(() => _validFrom = date),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDatePicker(context,
                  label: 'Gültig bis',
                  value: _validUntil,
                  onPicked: (date) => setState(() => _validUntil = date),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? AppPalette.hoverDark : AppPalette.sunken,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? AppPalette.lineDark : AppPalette.line),
                ),
                child: SwitchListTile(
                  title: const Text('Abo (verlängert sich automatisch)', style: TextStyle(fontSize: 14)),
                  value: _autoRenews,
                  onChanged: (value) => setState(() => _autoRenews = value),
                  activeThumbColor: AppTheme.primaryColor,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saveTicket,
              icon: const Icon(Icons.save),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, {
    required String label,
    required DateTime? value,
    required void Function(DateTime) onPicked,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          onPicked(picked);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkCard : AppPalette.sunken,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 16,
              color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value != null
                    ? '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}'
                    : label,
                style: TextStyle(
                  color: value != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.54),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveTicket() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Ticket-Name angeben'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    widget.provider.addTicket(
      ticketType: _ticketType,
      ticketName: name,
      zoneCoverage: _selectedZone,
      validFrom: _validFrom,
      validUntil: _validUntil,
      autoRenews: _autoRenews,
    );

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ticket gespeichert'),
        backgroundColor: AppTheme.success,
      ),
    );
  }
}
