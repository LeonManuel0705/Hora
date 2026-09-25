// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart' if (dart.library.html) '../services/database_service_web.dart';
import '../theme.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/glass_card.dart';
import '../widgets/page_fade_in.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  late TabController _tabController;

  List<Project> _allProjects = [];
  bool _isLoading = true;
  String? _error;

  final _statusFilters = [
    ('all', 'Alle', Icons.folder_copy),
    ('active', 'Aktiv', Icons.play_circle_outline),
    ('paused', 'Pausiert', Icons.pause_circle_outline),
    ('completed', 'Abgeschlossen', Icons.check_circle_outline),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusFilters.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadProjects();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final maps = await _db.getProjectsList();
      _allProjects = maps.map((m) => Project.fromMap(m)).toList();
    } catch (e) {
      _error = 'Fehler beim Laden der Projekte.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Project> get _filteredProjects {
    final filter = _statusFilters[_tabController.index].$1;
    if (filter == 'all') return _allProjects;
    return _allProjects.where((p) => p.status == filter).toList();
  }

  int _countByStatus(String status) {
    if (status == 'all') return _allProjects.length;
    return _allProjects.where((p) => p.status == status).toList().length;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active': return AppTheme.success;
      case 'paused': return AppTheme.warning;
      case 'completed': return AppTheme.info;
      default: return AppTheme.projectsColor;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'active': return 'Aktiv';
      case 'paused': return 'Pausiert';
      case 'completed': return 'Abgeschlossen';
      default: return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active': return Icons.play_circle_outline;
      case 'paused': return Icons.pause_circle_outline;
      case 'completed': return Icons.check_circle_outline;
      default: return Icons.folder;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PageFadeIn(
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildHeader(isDark),
              ),

              _buildFilterTabs(isDark),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.danger)))
                        : RefreshIndicator(
                            onRefresh: _loadProjects,
                            child: _filteredProjects.isEmpty
                                ? _buildEmptyState(isDark)
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                                    itemCount: _filteredProjects.length,
                                    itemBuilder: (context, index) => AnimatedListItem(
                                      index: index,
                                      child: _buildProjectCard(
                                        _filteredProjects[index],
                                        isDark,
                                      ),
                                    ),
                                  ),
                          ),
              ),
            ],
          ),

          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: FloatingActionButton(
              heroTag: 'fab_projects',
              onPressed: () => _showProjectEditor(null),
              backgroundColor: AppTheme.projectsColor,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final activeCount = _countByStatus('active');
    final completedCount = _countByStatus('completed');
    final avgProgress = _allProjects.isEmpty
        ? 0
        : (_allProjects.fold<int>(0, (sum, p) => sum + p.progress) / _allProjects.length).round();

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.projectsColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.folder, color: AppTheme.projectsColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTheme.gradientText('Projekte', fontSize: 36),
                    Text(
                      'Verwalte deine Projekte und Ziele',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMiniStat(isDark, '$activeCount', 'Aktiv', AppTheme.success),
              const SizedBox(width: 12),
              _buildMiniStat(isDark, '$completedCount', 'Fertig', AppTheme.info),
              const SizedBox(width: 12),
              _buildMiniStat(isDark, '$avgProgress%', 'Ø Fortschritt', AppTheme.projectsColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(bool isDark, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCard(
        borderRadius: 9999,
        padding: const EdgeInsets.all(4),
        hasShadow: false,
        enableTapScale: false,
        child: Row(
          children: _statusFilters.asMap().entries.map((entry) {
            final index = entry.key;
            final filter = entry.value;
            final isSelected = _tabController.index == index;
            final count = _countByStatus(filter.$1);

            return Expanded(
              flex: isSelected ? 3 : 1,
              child: GestureDetector(
                onTap: () => _tabController.animateTo(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 12 : 8,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF7353CD) : null,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        filter.$3,
                        size: 18,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white54 : Colors.black54),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${filter.$2} ($count)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Icon(
          Icons.folder_open,
          size: 64,
          color: isDark ? Colors.white24 : Colors.black26,
        ),
        const SizedBox(height: 16),
        Text(
          'Keine Projekte',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tippe auf + um ein Projekt zu erstellen',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _buildProjectCard(Project project, bool isDark) {
    final statusColor = _getStatusColor(project.status);
    final progressColor = project.progress >= 100
        ? AppTheme.success
        : project.progress >= 50
            ? AppTheme.projectsColor
            : AppTheme.warning;

    final progressGradient = project.progress >= 100
        ? [AppTheme.success, AppTheme.success.withValues(alpha: 0.7)]
        : project.progress >= 50
            ? [AppTheme.projectsColor, const Color(0xFF7C3AED)]
            : [AppTheme.warning, AppTheme.warning.withValues(alpha: 0.7)];

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      onTap: () => _showProjectEditor(project),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.folder, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isDark ? Colors.white : AppTheme.lightText,
                      ),
                    ),
                    if (project.goal != null && project.goal!.isNotEmpty)
                      Text(
                        project.goal!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_getStatusIcon(project.status), size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      _getStatusLabel(project.status),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Fortschritt',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        Text(
                          '${project.progress}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: progressColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 8,
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: (project.progress / 100).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: progressGradient),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (project.nextStep != null && project.nextStep!.isNotEmpty || project.deadline != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (project.nextStep != null && project.nextStep!.isNotEmpty) ...[
                  const Icon(Icons.arrow_forward, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      project.nextStep!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (project.deadline != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.event,
                    size: 14,
                    color: project.deadline!.isBefore(DateTime.now())
                        ? AppTheme.danger
                        : (isDark ? Colors.white54 : Colors.black54),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('d. MMM', 'de_DE').format(project.deadline!),
                    style: TextStyle(
                      fontSize: 12,
                      color: project.deadline!.isBefore(DateTime.now())
                          ? AppTheme.danger
                          : (isDark ? Colors.white54 : Colors.black54),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showProjectEditor(Project? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ProjectEditorScreen(
          existing: existing,
          onSave: (project) async {
            await _db.saveProject(project.toMap());
            await _loadProjects();
          },
          onDelete: existing != null ? () async {
            await _db.deleteProject(existing.id);
            await _loadProjects();
          } : null,
        ),
      ),
    );
  }
}

class _ProjectEditorScreen extends StatefulWidget {
  final Project? existing;
  final Future<void> Function(Project) onSave;
  final Future<void> Function()? onDelete;

  const _ProjectEditorScreen({
    required this.existing,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_ProjectEditorScreen> createState() => _ProjectEditorScreenState();
}

class _ProjectEditorScreenState extends State<_ProjectEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _goalController;
  late TextEditingController _nextStepController;
  late TextEditingController _notesController;
  String _status = 'active';
  DateTime? _deadline;
  int _progress = 0;
  bool _isSaving = false;

  final _statusOptions = [
    ('active', 'Aktiv', Icons.play_circle_outline, AppTheme.success),
    ('paused', 'Pausiert', Icons.pause_circle_outline, AppTheme.warning),
    ('completed', 'Abgeschlossen', Icons.check_circle_outline, AppTheme.info),
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _goalController = TextEditingController(text: widget.existing?.goal ?? '');
    _nextStepController = TextEditingController(text: widget.existing?.nextStep ?? '');
    _notesController = TextEditingController(text: widget.existing?.notes ?? '');
    _status = widget.existing?.status ?? 'active';
    _deadline = widget.existing?.deadline;
    _progress = widget.existing?.progress ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    _nextStepController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.existing != null;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Projekt bearbeiten' : 'Neues Projekt',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppTheme.lightText,
          ),
        ),
        actions: [
          if (isEditing && widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: _confirmDelete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSaving
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                : FilledButton.icon(
                    onPressed: _saveProject,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Speichern'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              isDark,
              'Projektname *',
              TextField(
                controller: _nameController,
                decoration: _inputDecoration(isDark, 'z.B. Webseite Redesign'),
                style: TextStyle(color: isDark ? Colors.white : AppTheme.lightText),
              ),
            ),

            _buildSection(
              isDark,
              'Ziel',
              TextField(
                controller: _goalController,
                decoration: _inputDecoration(isDark, 'Was möchtest du erreichen?'),
                style: TextStyle(color: isDark ? Colors.white : AppTheme.lightText),
                maxLines: 2,
              ),
            ),

            _buildSection(
              isDark,
              'Status',
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _statusOptions.map((opt) {
                    final isSelected = _status == opt.$1;
                    return GestureDetector(
                      onTap: () => setState(() => _status = opt.$1),
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? opt.$4.withValues(alpha: 0.2) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? opt.$4 : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(opt.$3, size: 20, color: isSelected ? opt.$4 : (isDark ? Colors.white54 : Colors.black54)),
                            const SizedBox(width: 8),
                            Text(
                              opt.$2,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? opt.$4 : (isDark ? Colors.white70 : Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            _buildSection(
              isDark,
              'Fortschritt: $_progress%',
              Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _progress >= 100
                          ? AppTheme.success
                          : _progress >= 50
                              ? AppTheme.projectsColor
                              : AppTheme.warning,
                      inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                      thumbColor: _progress >= 100
                          ? AppTheme.success
                          : _progress >= 50
                              ? AppTheme.projectsColor
                              : AppTheme.warning,
                      overlayColor: AppTheme.projectsColor.withValues(alpha: 0.2),
                      trackHeight: 8,
                    ),
                    child: Slider(
                      value: _progress.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      onChanged: (value) => setState(() => _progress = value.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [0, 25, 50, 75, 100].map((p) {
                      final isSelected = _progress == p;
                      return GestureDetector(
                        onTap: () => setState(() => _progress = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.projectsColor.withValues(alpha: 0.2)
                                : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1)),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppTheme.projectsColor : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            '$p%',
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppTheme.projectsColor : (isDark ? Colors.white54 : Colors.black54),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            _buildSection(
              isDark,
              'Deadline (optional)',
              GestureDetector(
                onTap: _pickDeadline,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event,
                        color: _deadline != null ? AppTheme.projectsColor : (isDark ? Colors.white54 : Colors.black54),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _deadline != null
                            ? DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(_deadline!)
                            : 'Keine Deadline gesetzt',
                        style: TextStyle(
                          color: _deadline != null
                              ? (isDark ? Colors.white : AppTheme.lightText)
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                      const Spacer(),
                      if (_deadline != null)
                        IconButton(
                          icon: const Icon(Icons.clear, color: AppTheme.danger),
                          onPressed: () => setState(() => _deadline = null),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            _buildSection(
              isDark,
              'Nächster Schritt',
              TextField(
                controller: _nextStepController,
                decoration: _inputDecoration(isDark, 'Was ist der nächste konkrete Schritt?'),
                style: TextStyle(color: isDark ? Colors.white : AppTheme.lightText),
              ),
            ),

            _buildSection(
              isDark,
              'Notizen',
              TextField(
                controller: _notesController,
                decoration: _inputDecoration(isDark, 'Zusätzliche Informationen, Links, Ideen...'),
                style: TextStyle(color: isDark ? Colors.white : AppTheme.lightText),
                maxLines: 4,
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(bool isDark, String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(bool isDark, String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _deadline = picked);
    }
  }

  Future<void> _saveProject() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Projektname eingeben')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final project = Project(
        id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        goal: _goalController.text.isEmpty ? null : _goalController.text,
        status: _status,
        deadline: _deadline,
        nextStep: _nextStepController.text.isEmpty ? null : _nextStepController.text,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        progress: _progress,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await widget.onSave(project);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error saving project: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ein Fehler ist aufgetreten. Bitte versuche es erneut.'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Projekt löschen?'),
        content: const Text('Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              final editorNavigator = Navigator.of(this.context);
              Navigator.pop(context);
              await widget.onDelete?.call();
              if (mounted) editorNavigator.pop();
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}

class Project {
  final String id;
  final String name;
  final String? goal;
  final String status;
  final DateTime? deadline;
  final String? nextStep;
  final String? notes;
  final int progress;
  final DateTime createdAt;
  final DateTime updatedAt;

  Project({
    required this.id,
    required this.name,
    this.goal,
    this.status = 'active',
    this.deadline,
    this.nextStep,
    this.notes,
    this.progress = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'goal': goal,
    'status': status,
    'deadline': deadline?.toIso8601String(),
    'next_step': nextStep,
    'notes': notes,
    'progress': progress,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Project.fromMap(Map<String, dynamic> map) => Project(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    goal: map['goal']?.toString(),
    status: map['status']?.toString() ?? 'active',
    deadline: map['deadline'] != null ? DateTime.tryParse(map['deadline'].toString()) : null,
    nextStep: map['next_step']?.toString(),
    notes: map['notes']?.toString(),
    progress: map['progress'] is int ? map['progress'] : int.tryParse(map['progress']?.toString() ?? '0') ?? 0,
    createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
  );
}
