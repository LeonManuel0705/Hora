// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../brand.dart';
import '../build_info.dart';
import '../providers/app_provider.dart';
import '../theme.dart';

class AppDrawer extends StatelessWidget {
  final int currentIndex;
  final Function(int) onNavigate;
  final VoidCallback onClose;

  const AppDrawer({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppPalette.surfaceDark.withValues(alpha: .95),
                  AppPalette.surfaceDark.withValues(alpha: .9),
                  AppPalette.surfaceDark.withValues(alpha: .85),
                ]
              : [
                  const Color(0xF2FFFFFF),
                  AppPalette.surface.withValues(alpha: .9),
                  AppPalette.sunken.withValues(alpha: .85),
                ],
          stops: const [0.0, 0.5, 1.0],
        ),
        border: Border(
          right: BorderSide(
            color: isDark
                ? AppPalette.iris.withValues(alpha: .3)
                : AppPalette.iris.withValues(alpha: .2),
            width: 1.5,
          ),
        ),
      ),
      child: Drawer(
        backgroundColor: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, isDark),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      _NavItem(
                        icon: Icons.dashboard_outlined,
                        selectedIcon: Icons.dashboard,
                        label: 'Dashboard',
                        isSelected: currentIndex == 0,
                        onTap: () => _navigate(context, 0),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),


                      _SectionLabel(label: 'Alltag', isDark: isDark),
                      _NavItem(
                        icon: Icons.task_alt_outlined,
                        selectedIcon: Icons.task_alt,
                        label: 'Aufgaben',
                        isSelected: currentIndex == 1,
                        onTap: () => _navigate(context, 1),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.timer_outlined,
                        selectedIcon: Icons.timer,
                        label: 'Pomodoro',
                        isSelected: currentIndex == 5,
                        onTap: () => _navigate(context, 5),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.calendar_today_outlined,
                        selectedIcon: Icons.calendar_today,
                        label: 'Kalender',
                        isSelected: currentIndex == 2,
                        onTap: () => _navigate(context, 2),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.directions_transit_outlined,
                        selectedIcon: Icons.directions_transit,
                        label: 'Fahrplan',
                        isSelected: currentIndex == 12,
                        onTap: () => _navigate(context, 12),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),


                      _SectionLabel(label: 'Bereiche', isDark: isDark),
                      _NavItem(
                        icon: Icons.school_outlined,
                        selectedIcon: Icons.school,
                        label: 'Schule',
                        isSelected: currentIndex == 3,
                        onTap: () => _navigate(context, 3),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.fitness_center_outlined,
                        selectedIcon: Icons.fitness_center,
                        label: 'Training',
                        isSelected: currentIndex == 6,
                        onTap: () => _navigate(context, 6),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.bookmark_outline,
                        selectedIcon: Icons.bookmark,
                        label: 'Lesezeichen',
                        isSelected: currentIndex == 13,
                        onTap: () => _navigate(context, 13),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),


                      _SectionLabel(label: 'System', isDark: isDark),
                      _NavItem(
                        icon: Icons.email_outlined,
                        selectedIcon: Icons.email,
                        label: 'E-Mail',
                        isSelected: currentIndex == 7,
                        onTap: () => _navigate(context, 7),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.show_chart_outlined,
                        selectedIcon: Icons.show_chart,
                        label: 'Review',
                        isSelected: currentIndex == 8,
                        onTap: () => _navigate(context, 8),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.smart_toy_outlined,
                        selectedIcon: Icons.smart_toy,
                        label: 'Assistent',
                        isSelected: currentIndex == 9,
                        onTap: () => _navigate(context, 9),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.note_outlined,
                        selectedIcon: Icons.note,
                        label: 'Notizen',
                        isSelected: currentIndex == 11,
                        onTap: () => _navigate(context, 11),
                        isDark: isDark,
                      ),
                      _NavItem(
                        icon: Icons.dns_outlined,
                        selectedIcon: Icons.dns,
                        label: 'IServ',
                        isSelected: currentIndex == 14,
                        onTap: () => _navigate(context, 14),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),


                      _NavItem(
                        icon: Icons.settings_outlined,
                        selectedIcon: Icons.settings,
                        label: 'Einstellungen',
                        isSelected: currentIndex == 10,
                        onTap: () => _navigate(context, 10),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _buildFooter(context, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/logo.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: AppTheme.primaryGradient,
                ).createShader(bounds),
                child: const Text(
                  Brand.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${BuildInfo.versionName} (Build ${BuildInfo.buildNumber})',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0x1AFFFFFF) : const Color(0x1A000000),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          Consumer<AppProvider>(
            builder: (context, provider, _) {
              final isDarkMode = provider.themeMode == ThemeMode.dark;
              return Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => provider.toggleTheme(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                          size: 20,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isDarkMode ? 'Dark Mode' : 'Light Mode',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '© Made with ',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 12,
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: AppTheme.primaryGradient,
                ).createShader(bounds),
                child: const Icon(
                  Icons.favorite,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              Text(
                ' by Leon Töpper :-)',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext context, int index) {
    Navigator.pop(context);
    onNavigate(index);
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;

  const _SectionLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(colors: [AppPalette.iris, AppPalette.iris])
                  : null,
              color: isSelected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppPalette.iris.withValues(alpha: .3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  size: 22,
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
