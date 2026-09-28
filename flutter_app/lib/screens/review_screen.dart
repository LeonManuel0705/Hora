// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../theme.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/glass_card.dart';
import '../widgets/page_fade_in.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _dailyAchievedController = TextEditingController();
  final _dailyGoodController = TextEditingController();
  final _dailyBetterController = TextEditingController();
  final _dailyFocusController = TextEditingController();
  final _dailyGratefulController = TextEditingController();
  int _dailyEnergy = 5;

  final _weeklyHighlightsController = TextEditingController();
  final _weeklyProgressController = TextEditingController();
  final _weeklyChallengesController = TextEditingController();
  final _weeklyLearningsController = TextEditingController();
  final _weeklyGoalsController = TextEditingController();

  final List<ReviewEntry> _dailyReviews = [];
  final List<WeeklyReviewEntry> _weeklyReviews = [];

  bool _isSaving = false;
  Map<String, dynamic>? _weeklyStats;
  late final DatabaseService _db;

  @override
  void initState() {
    super.initState();
    _db = DatabaseService();
    _tabController = TabController(length: 3, vsync: this);
    _loadReviews();
    _loadWeeklyStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dailyAchievedController.dispose();
    _dailyGoodController.dispose();
    _dailyBetterController.dispose();
    _dailyFocusController.dispose();
    _dailyGratefulController.dispose();
    _weeklyHighlightsController.dispose();
    _weeklyProgressController.dispose();
    _weeklyChallengesController.dispose();
    _weeklyLearningsController.dispose();
    _weeklyGoalsController.dispose();
    super.dispose();
  }

  void _checkTodayReview() {
    final today = DateTime.now();
    final todayReview = _dailyReviews.where((r) =>
        r.date.year == today.year &&
        r.date.month == today.month &&
        r.date.day == today.day).firstOrNull;

    if (todayReview != null) {
      _dailyAchievedController.text = todayReview.achieved;
      _dailyGoodController.text = todayReview.good;
      _dailyBetterController.text = todayReview.better;
      _dailyFocusController.text = todayReview.focus;
      _dailyGratefulController.text = todayReview.grateful;
      _dailyEnergy = todayReview.energy;
    }
  }

  Future<void> _loadReviews() async {
    final dailyMaps = await _db.getDailyReviews();
    final weeklyMaps = await _db.getWeeklyReviews();
    if (!mounted) return;

    setState(() {
      _dailyReviews.clear();
      _dailyReviews.addAll(dailyMaps.map((m) => ReviewEntry(
        id: m['id'] as String,
        date: DateTime.parse(m['date'] as String),
        achieved: m['achieved'] as String? ?? '',
        good: m['good'] as String? ?? '',
        better: m['better'] as String? ?? '',
        focus: m['focus'] as String? ?? '',
        grateful: m['grateful'] as String? ?? '',
        energy: m['energy'] as int? ?? 5,
      )));

      _weeklyReviews.clear();
      _weeklyReviews.addAll(weeklyMaps.map((m) => WeeklyReviewEntry(
        id: m['id'] as String,
        weekStart: DateTime.parse(m['week_start'] as String),
        weekNumber: m['week_number'] as int,
        highlights: m['highlights'] as String? ?? '',
        progress: m['progress'] as String? ?? '',
        challenges: m['challenges'] as String? ?? '',
        learnings: m['learnings'] as String? ?? '',
        goals: m['goals'] as String? ?? '',
      )));
    });

    _checkTodayReview();
    _checkThisWeekReview();
  }

  Future<void> _loadWeeklyStats() async {
    try {
      final stats = await _db.getWeeklyStats();
      if (mounted) {
        setState(() => _weeklyStats = stats);
      }
    } catch (_) {}
  }

  void _checkThisWeekReview() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final thisWeekReview = _weeklyReviews.where((r) =>
        r.weekStart.year == weekStart.year &&
        r.weekStart.month == weekStart.month &&
        r.weekStart.day == weekStart.day).firstOrNull;

    if (thisWeekReview != null) {
      _weeklyHighlightsController.text = thisWeekReview.highlights;
      _weeklyProgressController.text = thisWeekReview.progress;
      _weeklyChallengesController.text = thisWeekReview.challenges;
      _weeklyLearningsController.text = thisWeekReview.learnings;
      _weeklyGoalsController.text = thisWeekReview.goals;
    }
  }

  Future<void> _saveDailyReview() async {
    if (_dailyAchievedController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte fülle mindestens das erste Feld aus')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final today = DateTime.now();
      final existingIndex = _dailyReviews.indexWhere((r) =>
          r.date.year == today.year &&
          r.date.month == today.month &&
          r.date.day == today.day);

      final review = ReviewEntry(
        id: existingIndex >= 0 ? _dailyReviews[existingIndex].id : DateTime.now().millisecondsSinceEpoch.toString(),
        date: today,
        achieved: _dailyAchievedController.text,
        good: _dailyGoodController.text,
        better: _dailyBetterController.text,
        focus: _dailyFocusController.text,
        grateful: _dailyGratefulController.text,
        energy: _dailyEnergy,
      );

      if (existingIndex >= 0) {
        _dailyReviews[existingIndex] = review;
      } else {
        _dailyReviews.insert(0, review);
      }

      await _db.insertDailyReview({
        'id': review.id,
        'date': review.date.toIso8601String(),
        'achieved': review.achieved,
        'good': review.good,
        'better': review.better,
        'focus': review.focus,
        'grateful': review.grateful,
        'energy': review.energy,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tages-Review gespeichert!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveWeeklyReview() async {
    if (_weeklyHighlightsController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte fülle mindestens das erste Feld aus')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekNum = _getWeekNumber(now);

      final existingIndex = _weeklyReviews.indexWhere((r) =>
          r.weekStart.year == weekStart.year &&
          r.weekStart.month == weekStart.month &&
          r.weekStart.day == weekStart.day);

      final review = WeeklyReviewEntry(
        id: existingIndex >= 0 ? _weeklyReviews[existingIndex].id : DateTime.now().millisecondsSinceEpoch.toString(),
        weekStart: weekStart,
        weekNumber: weekNum,
        highlights: _weeklyHighlightsController.text,
        progress: _weeklyProgressController.text,
        challenges: _weeklyChallengesController.text,
        learnings: _weeklyLearningsController.text,
        goals: _weeklyGoalsController.text,
      );

      if (existingIndex >= 0) {
        _weeklyReviews[existingIndex] = review;
      } else {
        _weeklyReviews.insert(0, review);
      }

      await _db.insertWeeklyReview({
        'id': review.id,
        'week_start': review.weekStart.toIso8601String(),
        'week_number': review.weekNumber,
        'highlights': review.highlights,
        'progress': review.progress,
        'challenges': review.challenges,
        'learnings': review.learnings,
        'goals': review.goals,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wochen-Review gespeichert!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  int _getWeekNumber(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    final thursday = day.add(Duration(days: 4 - day.weekday));
    final dayOfYear = thursday.difference(DateTime.utc(thursday.year, 1, 1)).inDays + 1;
    return (dayOfYear - 1) ~/ 7 + 1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageFadeIn(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppTheme.gradientText('Review', fontSize: 36),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GlassCard(
              padding: const EdgeInsets.all(4),
              borderRadius: 100,
              enableTapScale: false,
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(100),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(100),
                tabs: const [
                  Tab(text: 'Heute'),
                  Tab(text: 'W\u00f6chentlich'),
                  Tab(text: 'Verlauf'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDailyReview(isDark),
                _buildWeeklyReview(isDark),
                _buildHistory(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyReview(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedListItem(
            index: 0,
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.wb_sunny, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tages-Review',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.lightText,
                          ),
                        ),
                        Text(
                          DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(DateTime.now()),
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          AnimatedListItem(
            index: 1,
            child: GlassCard(
              tint: AppPalette.sage,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildQuestionField(
                    isDark: isDark,
                    icon: Icons.check_circle_outline,
                    question: 'Was hast du heute erreicht?',
                    hint: 'Deine Erfolge und erledigten Aufgaben...',
                    controller: _dailyAchievedController,
                    color: AppPalette.sage,
                  ),
                  const SizedBox(height: 16),
                  _buildQuestionField(
                    isDark: isDark,
                    icon: Icons.thumb_up_outlined,
                    question: 'Was lief heute gut?',
                    hint: 'Positive Momente und Erfahrungen...',
                    controller: _dailyGoodController,
                    color: AppPalette.sage,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          AnimatedListItem(
            index: 2,
            child: GlassCard(
              tint: AppPalette.terracotta,
              padding: const EdgeInsets.all(16),
              child: _buildQuestionField(
                isDark: isDark,
                icon: Icons.trending_up,
                question: 'Was kann morgen besser werden?',
                hint: 'Verbesserungsm\u00f6glichkeiten...',
                controller: _dailyBetterController,
                color: AppPalette.terracotta,
              ),
            ),
          ),
          const SizedBox(height: 12),

          AnimatedListItem(
            index: 3,
            child: GlassCard(
              tint: AppPalette.iris,
              padding: const EdgeInsets.all(16),
              child: _buildQuestionField(
                isDark: isDark,
                icon: Icons.track_changes,
                question: 'Worauf fokussierst du dich morgen?',
                hint: 'Dein Hauptfokus f\u00fcr morgen...',
                controller: _dailyFocusController,
                color: AppPalette.iris,
              ),
            ),
          ),
          const SizedBox(height: 12),

          AnimatedListItem(
            index: 4,
            child: GlassCard(
              tint: AppPalette.amber,
              padding: const EdgeInsets.all(16),
              child: _buildQuestionField(
                isDark: isDark,
                icon: Icons.favorite_outline,
                question: 'Wof\u00fcr bist du heute dankbar?',
                hint: 'Dinge, die du sch\u00e4tzt...',
                controller: _dailyGratefulController,
                color: AppPalette.amber,
              ),
            ),
          ),
          const SizedBox(height: 16),

          AnimatedListItem(index: 5, child: _buildEnergySlider(isDark)),
          const SizedBox(height: 24),

          _buildSaveButton(_saveDailyReview),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildWeeklyReview(bool isDark) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedListItem(
            index: 0,
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.date_range, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wochen-Review',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.lightText,
                          ),
                        ),
                        Text(
                          'KW ${_getWeekNumber(now)} (${DateFormat('d. MMM', 'de_DE').format(weekStart)} - ${DateFormat('d. MMM', 'de_DE').format(weekEnd)})',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_weeklyStats != null) AnimatedListItem(index: 1, child: _buildWeeklyStatsCard(isDark)),

          const SizedBox(height: 12),

          AnimatedListItem(
            index: 2,
            child: GlassCard(
              tint: AppPalette.amber,
              padding: const EdgeInsets.all(16),
              child: _buildQuestionField(
                isDark: isDark,
                icon: Icons.star_outline,
                question: 'Was waren deine Highlights dieser Woche?',
                hint: 'Die besten Momente...',
                controller: _weeklyHighlightsController,
                color: AppPalette.amber,
              ),
            ),
          ),
          const SizedBox(height: 12),

          AnimatedListItem(
            index: 3,
            child: GlassCard(
              tint: AppPalette.sage,
              padding: const EdgeInsets.all(16),
              child: _buildQuestionField(
                isDark: isDark,
                icon: Icons.trending_up,
                question: 'Welche Fortschritte hast du gemacht?',
                hint: 'Deine Erfolge und Entwicklungen...',
                controller: _weeklyProgressController,
                color: AppPalette.sage,
              ),
            ),
          ),
          const SizedBox(height: 12),

          AnimatedListItem(
            index: 4,
            child: GlassCard(
              tint: AppPalette.terracotta,
              padding: const EdgeInsets.all(16),
              child: _buildQuestionField(
                isDark: isDark,
                icon: Icons.warning_amber_outlined,
                question: 'Was waren deine gr\u00f6\u00dften Herausforderungen?',
                hint: 'Schwierigkeiten und Hindernisse...',
                controller: _weeklyChallengesController,
                color: AppPalette.terracotta,
              ),
            ),
          ),
          const SizedBox(height: 12),

          AnimatedListItem(
            index: 5,
            child: GlassCard(
              tint: AppPalette.iris,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildQuestionField(
                    isDark: isDark,
                    icon: Icons.lightbulb_outline,
                    question: 'Was hast du diese Woche gelernt?',
                    hint: 'Neue Erkenntnisse und Einsichten...',
                    controller: _weeklyLearningsController,
                    color: AppPalette.iris,
                  ),
                  const SizedBox(height: 16),
                  _buildQuestionField(
                    isDark: isDark,
                    icon: Icons.flag_outlined,
                    question: 'Was sind deine Ziele f\u00fcr n\u00e4chste Woche?',
                    hint: 'Deine Vorhaben und Pl\u00e4ne...',
                    controller: _weeklyGoalsController,
                    color: AppPalette.iris,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _buildSaveButton(_saveWeeklyReview),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildHistory(bool isDark) {
    final allReviews = <dynamic>[..._dailyReviews, ..._weeklyReviews];
    allReviews.sort((a, b) {
      final dateA = a is ReviewEntry ? a.date : (a as WeeklyReviewEntry).weekStart;
      final dateB = b is ReviewEntry ? b.date : (b as WeeklyReviewEntry).weekStart;
      return dateB.compareTo(dateA);
    });

    if (allReviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'Noch keine Reviews',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Schreibe dein erstes Review!',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: allReviews.length,
      itemBuilder: (context, index) {
        final review = allReviews[index];
        return AnimatedListItem(
          index: index,
          child: review is ReviewEntry
              ? _buildDailyReviewCard(review, isDark)
              : _buildWeeklyReviewCard(review as WeeklyReviewEntry, isDark),
        );
      },
    );
  }

  Widget _buildDailyReviewCard(ReviewEntry review, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 16,
        onTap: () => _showDailyReviewDetails(review),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.wb_sunny, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(review.date),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppTheme.lightText,
                    ),
                  ),
                  Text(
                    'Tages-Review',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _getEnergyColor(review.energy).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, size: 16, color: _getEnergyColor(review.energy)),
                  const SizedBox(width: 4),
                  Text(
                    '${review.energy}/10',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _getEnergyColor(review.energy),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyReviewCard(WeeklyReviewEntry review, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 16,
        onTap: () => _showWeeklyReviewDetails(review),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.date_range, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KW ${review.weekNumber}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppTheme.lightText,
                    ),
                  ),
                  Text(
                    'Wochen-Review',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionField({
    required bool isDark,
    required IconData icon,
    required String question,
    required String hint,
    required TextEditingController controller,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              question,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.lightText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnergySlider(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt, size: 20, color: AppTheme.warning),
            const SizedBox(width: 8),
            Text(
              'Energie-Level',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.lightText,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _getEnergyColor(_dailyEnergy).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_dailyEnergy/10',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _getEnergyColor(_dailyEnergy),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GlassCard(
          borderRadius: 16,
          enableTapScale: false,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _getEnergyColor(_dailyEnergy),
                  inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
                  thumbColor: _getEnergyColor(_dailyEnergy),
                  overlayColor: _getEnergyColor(_dailyEnergy).withValues(alpha: 0.2),
                  trackHeight: 8,
                ),
                child: Slider(
                  value: _dailyEnergy.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (value) => setState(() => _dailyEnergy = value.round()),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ersch\u00f6pft',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  Text(
                    'Voller Energie',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyStatsCard(bool isDark) {
    final tasksCompleted = _weeklyStats!['tasks_completed'] as int;
    final tasksTotal = _weeklyStats!['tasks_total'] as int;
    final pomodoroSessions = _weeklyStats!['pomodoro_sessions'] as int;
    final pomodoroMinutes = _weeklyStats!['pomodoro_minutes'] as int;
    final pomodoroByDay = _weeklyStats!['pomodoro_by_day'] as List<Map<String, dynamic>>;

    final pomodoroHours = pomodoroMinutes ~/ 60;
    final pomodoroMins = pomodoroMinutes % 60;
    final focusTimeStr = pomodoroHours > 0
        ? '${pomodoroHours}h ${pomodoroMins}min'
        : '${pomodoroMins}min';

    final completionRate = tasksTotal > 0
        ? '${(tasksCompleted / tasksTotal * 100).round()}%'
        : '-';

    String bestDay = '-';
    if (pomodoroByDay.isNotEmpty) {
      final best = pomodoroByDay.reduce((a, b) =>
        (a['count'] as int) >= (b['count'] as int) ? a : b);
      try {
        final date = DateTime.parse(best['day'] as String);
        bestDay = DateFormat('EEEE', 'de_DE').format(date);
      } catch (_) {}
    }

    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final thisWeekDailyReviews = _dailyReviews.where((r) =>
        r.date.isAfter(weekStart.subtract(const Duration(days: 1)))).toList();
    final avgEnergy = thisWeekDailyReviews.isNotEmpty
        ? (thisWeekDailyReviews.map((r) => r.energy).reduce((a, b) => a + b) / thisWeekDailyReviews.length).toStringAsFixed(1)
        : '-';

    return GlassCard(
      borderRadius: 16,
      tint: AppTheme.primaryColor,
      enableTapScale: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 20, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                'Wochen-Statistik',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.lightText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  borderRadius: 12,
                  tint: AppTheme.success,
                  enableTapScale: false,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: _buildStatItem(
                    Icons.check_circle_outline, '$tasksCompleted/$tasksTotal',
                    'Aufgaben', AppTheme.success, isDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassCard(
                  borderRadius: 12,
                  tint: AppTheme.warning,
                  enableTapScale: false,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: _buildStatItem(
                    Icons.percent, completionRate,
                    'Quote', AppTheme.warning, isDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  borderRadius: 12,
                  tint: AppTheme.pomodoroColor,
                  enableTapScale: false,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: _buildStatItem(
                    Icons.local_fire_department, '$pomodoroSessions',
                    'Pomodoros', AppTheme.pomodoroColor, isDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassCard(
                  borderRadius: 12,
                  tint: AppTheme.info,
                  enableTapScale: false,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: _buildStatItem(
                    Icons.timer, focusTimeStr,
                    'Fokuszeit', AppTheme.info, isDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  borderRadius: 12,
                  tint: AppTheme.warning,
                  enableTapScale: false,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: _buildStatItem(
                    Icons.bolt, avgEnergy,
                    '\u00d8 Energie', AppTheme.warning, isDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassCard(
                  borderRadius: 12,
                  tint: AppTheme.primaryColor,
                  enableTapScale: false,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: _buildStatItem(
                    Icons.star, bestDay,
                    'Bester Tag', AppTheme.primaryColor, isDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, Color color, bool isDark) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppTheme.lightText,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton(VoidCallback onSave) {
    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _isSaving ? null : onSave,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.save, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Speichern',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getEnergyColor(int energy) {
    if (energy <= 3) return AppTheme.danger;
    if (energy <= 6) return AppTheme.warning;
    return AppTheme.success;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    if (diff < 7) return 'Vor $diff Tagen';

    return DateFormat('d. MMMM yyyy', 'de_DE').format(date);
  }

  void _showDailyReviewDetails(ReviewEntry review) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppPalette.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.wb_sunny, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(review.date),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.lightText,
                        ),
                      ),
                      Text(
                        'Tages-Review',
                        style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getEnergyColor(review.energy).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, size: 18, color: _getEnergyColor(review.energy)),
                      const SizedBox(width: 4),
                      Text(
                        '${review.energy}/10',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getEnergyColor(review.energy),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (review.achieved.isNotEmpty)
              _buildDetailSection('Was erreicht', review.achieved, Icons.check_circle_outline, AppTheme.success, isDark),
            if (review.good.isNotEmpty)
              _buildDetailSection('Was gut lief', review.good, Icons.thumb_up_outlined, AppTheme.info, isDark),
            if (review.better.isNotEmpty)
              _buildDetailSection('Was besser werden kann', review.better, Icons.trending_up, AppTheme.warning, isDark),
            if (review.focus.isNotEmpty)
              _buildDetailSection('Fokus morgen', review.focus, Icons.track_changes, AppTheme.primaryColor, isDark),
            if (review.grateful.isNotEmpty)
              _buildDetailSection('Dankbar für', review.grateful, Icons.favorite_outline, AppTheme.danger, isDark),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Review löschen'),
                    content: const Text('Möchtest du dieses Tages-Review wirklich löschen?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Abbrechen'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  Navigator.pop(context);
                  _db.deleteDailyReview(review.id);
                  setState(() => _dailyReviews.remove(review));
                }
              },
              icon: const Icon(Icons.delete, color: AppTheme.danger),
              label: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      ),
    );
  }

  void _showWeeklyReviewDetails(WeeklyReviewEntry review) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppPalette.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.date_range, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KW ${review.weekNumber}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.lightText,
                        ),
                      ),
                      Text(
                        'Wochen-Review',
                        style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (review.highlights.isNotEmpty)
              _buildDetailSection('Highlights', review.highlights, Icons.star_outline, AppTheme.warning, isDark),
            if (review.progress.isNotEmpty)
              _buildDetailSection('Fortschritt', review.progress, Icons.trending_up, AppTheme.success, isDark),
            if (review.challenges.isNotEmpty)
              _buildDetailSection('Herausforderungen', review.challenges, Icons.warning_amber_outlined, AppTheme.danger, isDark),
            if (review.learnings.isNotEmpty)
              _buildDetailSection('Learnings', review.learnings, Icons.lightbulb_outline, AppTheme.info, isDark),
            if (review.goals.isNotEmpty)
              _buildDetailSection('Ziele nächste Woche', review.goals, Icons.flag_outlined, AppTheme.primaryColor, isDark),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Review löschen'),
                    content: const Text('Möchtest du dieses Wochen-Review wirklich löschen?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Abbrechen'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  Navigator.pop(context);
                  _db.deleteWeeklyReview(review.id);
                  setState(() => _weeklyReviews.remove(review));
                }
              },
              icon: const Icon(Icons.delete, color: AppTheme.danger),
              label: const Text('Löschen', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, String content, IconData icon, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GlassCard(
            borderRadius: 16,
            tint: color,
            enableTapScale: false,
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                content,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewEntry {
  final String id;
  final DateTime date;
  final String achieved;
  final String good;
  final String better;
  final String focus;
  final String grateful;
  final int energy;

  ReviewEntry({
    required this.id,
    required this.date,
    required this.achieved,
    required this.good,
    required this.better,
    required this.focus,
    required this.grateful,
    required this.energy,
  });
}

class WeeklyReviewEntry {
  final String id;
  final DateTime weekStart;
  final int weekNumber;
  final String highlights;
  final String progress;
  final String challenges;
  final String learnings;
  final String goals;

  WeeklyReviewEntry({
    required this.id,
    required this.weekStart,
    required this.weekNumber,
    required this.highlights,
    required this.progress,
    required this.challenges,
    required this.learnings,
    required this.goals,
  });
}
