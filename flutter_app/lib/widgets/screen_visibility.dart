// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'package:flutter/widgets.dart';

class ScreenVisibility extends InheritedWidget {
  const ScreenVisibility({super.key, required this.visible, required super.child});

  final bool visible;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScreenVisibility>()?.visible ?? true;

  @override
  bool updateShouldNotify(ScreenVisibility oldWidget) => visible != oldWidget.visible;
}

class VisibilityLease extends StatefulWidget {
  const VisibilityLease({super.key, required this.onShow, required this.onHide, required this.child});

  final VoidCallback onShow;
  final VoidCallback onHide;
  final Widget child;

  @override
  State<VisibilityLease> createState() => _VisibilityLeaseState();
}

class _VisibilityLeaseState extends State<VisibilityLease> {
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ScreenVisibility.of(context);
    if (visible && !_shown) {
      _shown = true;
      widget.onShow();
    } else if (!visible && _shown) {
      _shown = false;
      widget.onHide();
    }
  }

  @override
  void dispose() {
    if (_shown) widget.onHide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
