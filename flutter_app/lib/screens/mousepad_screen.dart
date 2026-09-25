// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/page_fade_in.dart';

class MousepadScreen extends StatefulWidget {
  const MousepadScreen({super.key});

  @override
  State<MousepadScreen> createState() => _MousepadScreenState();
}

class _MousepadScreenState extends State<MousepadScreen> {
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DrawingProvider>().loadDrawings();
    });
  }

  Future<void> _saveDrawing() async {
    final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final drawingProvider = context.read<DrawingProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final imageData = byteData.buffer.asUint8List();

      if (!mounted) return;

      final name = await _showSaveDialog();
      if (name != null && name.isNotEmpty) {
        await drawingProvider.saveDrawing(name, imageData);
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Zeichnung gespeichert')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving drawing: $e');
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Fehler beim Speichern. Bitte versuche es erneut.')),
        );
      }
    }
  }

  Future<String?> _showSaveDialog() async {
    final controller = TextEditingController(
      text: 'Zeichnung ${DateTime.now().toString().substring(0, 16)}',
    );

    final isDarkDialog = Theme.of(context).brightness == Brightness.dark;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkDialog ? AppTheme.darkCard : null,
        title: const Text('Zeichnung speichern'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  void _showGallery() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _GallerySheet(
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : null,
      appBar: AppBar(
        title: AppTheme.gradientText('Zeichnen', fontSize: 36),
        backgroundColor: isDark ? AppTheme.darkSurface : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _showGallery,
            tooltip: 'Galerie',
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveDrawing,
            tooltip: 'Speichern',
          ),
        ],
      ),
      body: PageFadeIn(
        child: Column(
          children: [

            Expanded(
              child: RepaintBoundary(
              key: _canvasKey,
              child: Consumer<DrawingProvider>(
                builder: (context, provider, child) {
                  return GestureDetector(
                    onPanStart: (details) {
                      provider.startStroke(details.localPosition);
                    },
                    onPanUpdate: (details) {
                      provider.addPoint(details.localPosition);
                    },
                    onPanEnd: (details) {
                      provider.endStroke();
                    },
                    child: GlassCard(
                      borderRadius: 16,
                      padding: EdgeInsets.zero,
                      hasShadow: false,
                      child: CustomPaint(
                        painter: _DrawingPainter(
                          strokes: provider.getAllStrokes(),
                          backgroundType: provider.backgroundType,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

            _DrawingToolbar(),
          ],
        ),
      ),
    );
  }
}

class _DrawingToolbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, provider, child) {
        return GlassCard(
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hasShadow: false,
          child: SafeArea(
            top: false,
            child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ToolButton(
                          icon: Icons.edit,
                          label: 'Stift',
                          isSelected: provider.currentTool == DrawingTool.pen,
                          onTap: () => provider.setTool(DrawingTool.pen),
                        ),
                        _ToolButton(
                          icon: Icons.format_color_fill,
                          label: 'Marker',
                          isSelected: provider.currentTool == DrawingTool.highlighter,
                          onTap: () => provider.setTool(DrawingTool.highlighter),
                        ),
                        _ToolButton(
                          icon: Icons.auto_fix_normal,
                          label: 'Radierer',
                          isSelected: provider.currentTool == DrawingTool.eraser,
                          onTap: () => provider.setTool(DrawingTool.eraser),
                        ),
                        _ToolButton(
                          icon: Icons.undo,
                          label: 'Zurück',
                          isSelected: false,
                          enabled: provider.canUndo,
                          onTap: provider.canUndo ? () => provider.undo() : null,
                        ),
                        _ToolButton(
                          icon: Icons.delete_outline,
                          label: 'Löschen',
                          isSelected: false,
                          onTap: () => _showClearDialog(context, provider),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (provider.currentTool != DrawingTool.eraser)
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: DrawingProvider.availableColors.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final color = DrawingProvider.availableColors[index];
                            final isSelected = provider.currentColor == color;
                            return GestureDetector(
                              onTap: () => provider.setColor(color),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primary
                                        : Colors.white24,
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.line_weight, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: provider.strokeWidth,
                            min: 1,
                            max: 20,
                            divisions: 19,
                            activeColor: AppTheme.primary,
                            onChanged: (value) => provider.setStrokeWidth(value),
                          ),
                        ),
                        Text(
                          '${provider.strokeWidth.toInt()}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
      },
    );
  }

  void _showClearDialog(BuildContext context, DrawingProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Zeichnung löschen?'),
        content: const Text('Die aktuelle Zeichnung wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : Colors.white24,
                ),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? AppTheme.primary : Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? AppTheme.primary : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final String backgroundType;

  _DrawingPainter({
    required this.strokes,
    required this.backgroundType,
  });

  @override
  void paint(Canvas canvas, Size size) {

    _drawBackground(canvas, size);

    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;

      final paint = Paint()
        ..color = stroke.tool == DrawingTool.highlighter
            ? stroke.color.withValues(alpha: 0.4)
            : stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.tool == DrawingTool.eraser
            ? BlendMode.clear
            : BlendMode.srcOver;

      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    switch (backgroundType) {
      case 'lines':
        for (double y = 40; y < size.height; y += 40) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        break;
      case 'grid':
        for (double y = 40; y < size.height; y += 40) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
        }
        for (double x = 40; x < size.width; x += 40) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
        }
        break;
      case 'dots':
        final dotPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;
        for (double y = 20; y < size.height; y += 20) {
          for (double x = 20; x < size.width; x += 20) {
            canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return strokes != oldDelegate.strokes ||
           backgroundType != oldDelegate.backgroundType;
  }
}

class _GallerySheet extends StatelessWidget {
  final ScrollController scrollController;

  const _GallerySheet({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    'Gespeicherte Zeichnungen',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: provider.drawings.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.brush_outlined,
                            size: 64,
                            color: Colors.white24,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Keine Zeichnungen gespeichert',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: provider.drawings.length,
                      itemBuilder: (context, index) {
                        final drawing = provider.drawings[index];
                        return _DrawingCard(drawing: drawing);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DrawingCard extends StatelessWidget {
  final dynamic drawing;

  const _DrawingCard({required this.drawing});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {

        Navigator.pop(context);
      },
      onLongPress: () => _showDeleteDialog(context),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                ),
                child: Image.memory(
                  drawing.imageData,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drawing.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(drawing.createdAt),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Zeichnung löschen?'),
        content: Text('"${drawing.name}" wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<DrawingProvider>().deleteDrawing(drawing.id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}
