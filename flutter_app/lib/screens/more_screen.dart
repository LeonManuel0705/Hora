// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui';

import 'package:flutter/material.dart';
import '../brand.dart';
import '../build_info.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_list_item.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _sections = [
    (
      title: 'Alltag',
      items: [
        (index: 1, icon: Icons.task_alt_outlined, label: 'Aufgaben', color: Color(0xFF6366F1)),
        (index: 5, icon: Icons.timer_outlined, label: 'Pomodoro', color: Color(0xFFF97316)),
        (index: 2, icon: Icons.calendar_today_outlined, label: 'Kalender', color: Color(0xFF6366F1)),
        (index: 12, icon: Icons.train_outlined, label: 'Fahrplan', color: Color(0xFFEF4444)),
      ],
    ),
    (
      title: 'Bereiche',
      items: [
        (index: 3, icon: Icons.school_outlined, label: 'Schule', color: Color(0xFF3B82F6)),
        (index: 6, icon: Icons.fitness_center_outlined, label: 'Training', color: Color(0xFFEC4899)),
        (index: 13, icon: Icons.bookmark_outline, label: 'Lesezeichen', color: Color(0xFFFACC15)),
      ],
    ),
    (
      title: 'Tools',
      items: [
        (index: 7, icon: Icons.email_outlined, label: 'E-Mail', color: Color(0xFFEF4444)),
        (index: 8, icon: Icons.show_chart_outlined, label: 'Review', color: Color(0xFF10B981)),
        (index: 9, icon: Icons.smart_toy_outlined, label: 'Assistent', color: Color(0xFF6366F1)),
        (index: 11, icon: Icons.note_outlined, label: 'Notizen', color: Color(0xFFFACC15)),
        (index: 14, icon: Icons.dns_outlined, label: 'IServ', color: Color(0xFF3B82F6)),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int globalIndex = 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        AppTheme.gradientText('Mehr', fontSize: 36),
        const SizedBox(height: 4),
        Text(
          'Alle Funktionen auf einen Blick',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
        ),
        const SizedBox(height: 24),

        for (final section in _sections) ...[
          Text(
            section.title.toUpperCase(),
            style: AppTheme.sectionLabel(isDark),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: [
              for (final item in section.items)
                AnimatedListItem(
                  index: globalIndex++,
                  child: _buildModuleCard(context, isDark, item.index, item.icon, item.label, item.color),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],

        AnimatedListItem(
          index: globalIndex++,
          child: GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _buildSettingsRow(
                  context, isDark,
                  icon: Icons.settings_outlined,
                  label: 'Einstellungen',
                  color: const Color(0xFF71717A),
                  onTap: () => MainScreen.navigateTo(10),
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                ),
                _buildSettingsRow(
                  context, isDark,
                  icon: Icons.info_outline,
                  label: 'Über ${Brand.name}',
                  subtitle: '${BuildInfo.versionName} (Build ${BuildInfo.buildNumber})',
                  color: AppTheme.primaryColor,
                  onTap: () => _showAboutDialog(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModuleCard(BuildContext context, bool isDark, int index, IconData icon, String label, Color color) {
    return GlassCard(
      onTap: () => MainScreen.navigateTo(index),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF18181B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(BuildContext context, bool isDark, {
    required IconData icon,
    required String label,
    String? subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF18181B),
                  )),
                  if (subtitle != null)
                    Text(subtitle, style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    )),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18181B).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: AppTheme.primaryGradient),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.hub, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(Brand.name, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF18181B))),
                  const SizedBox(height: 4),
                  const Text('Dein persönlicher Produktivitäts-Hub', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.lightTextMuted)),
                  const SizedBox(height: 20),
                  _buildInfoChip('Version', '${BuildInfo.versionName} (${BuildInfo.buildNumber})', isDark),
                  const SizedBox(height: 8),
                  _buildInfoChip('Entwickler', 'Leon Manuel Töpper', isDark),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Schließen', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF18181B))),
        ],
      ),
    );
  }
}
