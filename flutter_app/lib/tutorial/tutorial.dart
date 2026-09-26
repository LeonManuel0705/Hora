// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brand.dart';
import '../providers/app_provider.dart';
import 'tinte.dart';

enum _Wait { none, dialog, created }

enum _Tail { left, right, top, bottom }

class _Step {
  const _Step(
    this.id, {
    required this.text,
    this.mode,
    this.target,
    this.primary = 'Weiter',
    this.secondary,
    this.onSecondary,
    this.done = false,
    this.wait = _Wait.none,
    this.dim = true,
    this.dot = false,
    this.back = '',
    this.page,
    this.tabletOnly = false,
  });

  final String id;
  final String Function(bool phone) text;
  final TinteMode Function(bool phone)? mode;
  final String? Function(bool phone)? target;
  final String primary;
  final String? secondary;
  final String? onSecondary;
  final bool done;
  final _Wait wait;
  final bool dim;
  final bool dot;
  final String? back;
  final int? page;
  final bool tabletOnly;
}

TinteMode _point(bool _) => TinteMode.point;

final _steps = <_Step>[
  _Step(
    'hello',
    mode: (_) => TinteMode.hello,
    text: (_) => 'Hi, ich bin Tinte! Ich zeige dir in einer Minute, wo in ${Brand.name} was ist. Unterwegs legen wir zusammen deine erste Aufgabe an.',
    primary: 'Los geht’s',
    secondary: 'Später',
    onSecondary: 'skip',
  ),
  _Step(
    'nav',
    dot: true,
    mode: _point,
    target: (_) => 'nav',
    back: null,
    text: (phone) => phone
        ? 'Unten findest du die wichtigsten Bereiche. Ein Tipp, und du bist da.'
        : 'Links findest du alle Bereiche von ${Brand.name}. Ein Tipp, und du bist da.',
  ),
  _Step(
    'home',
    dot: true,
    mode: _point,
    target: (_) => 'nav-0',
    text: (phone) => '${phone ? 'In der Übersicht' : 'Im Dashboard'} siehst du deinen Tag auf einen Blick: Termine, Aufgaben für heute und anstehende Deadlines.',
  ),
  _Step(
    'tasks',
    dot: true,
    mode: _point,
    target: (_) => 'nav-1',
    text: (_) => 'Unter Aufgaben sammelst du alles, was ansteht. Komm, wir legen gleich deine erste an!',
    primary: 'Zeig’s mir',
    secondary: 'Überspringen',
    onSecondary: 'calendar',
  ),
  _Step(
    'task-new',
    page: 1,
    mode: _point,
    target: (_) => 'tasks-add',
    text: (_) => 'Tipp auf „Neu“.',
    wait: _Wait.dialog,
    secondary: 'Überspringen',
    onSecondary: 'calendar',
  ),
  _Step(
    'task-form',
    page: 1,
    mode: (_) => TinteMode.watch,
    target: (_) => 'task-dialog',
    dim: false,
    text: (phone) => phone
        ? 'Titel eintippen, dann auf „Speichern“.'
        : 'Schreib rein, was du erledigen willst, zum Beispiel „Vokabeln lernen“, und tipp auf „Speichern“.',
    wait: _Wait.created,
    secondary: 'Überspringen',
    onSecondary: 'calendar',
  ),
  _Step(
    'task-done',
    page: 1,
    mode: (_) => TinteMode.cheer,
    back: null,
    text: (_) => 'Geschafft, deine erste Aufgabe steht! Ist sie erledigt, hakst du sie mit einem Tipp ab.',
  ),
  _Step(
    'calendar',
    dot: true,
    mode: _point,
    target: (_) => 'nav-2',
    back: 'tasks',
    text: (_) => 'Im Kalender stehen deine Termine, Ferien und Feiertage.',
  ),
  _Step(
    'school',
    dot: true,
    mode: _point,
    target: (_) => 'nav-3',
    text: (_) => 'Unter Schule liegen Stundenplan, Fächer, Hausaufgaben, Tests, Klausuren und Noten.',
  ),
  _Step(
    'more',
    dot: true,
    mode: (phone) => phone ? TinteMode.point : TinteMode.present,
    target: (phone) => phone ? 'nav-more' : 'nav',
    text: (phone) => phone
        ? 'Unter „Mehr“ findest du alles Weitere: E-Mail, Notizen, Pomodoro, Training, Fahrplan und die Einstellungen. Dort kannst du mich jederzeit wieder rufen.'
        : 'Dazu gibt es Training, Review, Notizen, Lesezeichen, E-Mail, Fahrplan, Pomodoro, IServ und den Assistenten.',
  ),
  _Step(
    'settings',
    dot: true,
    tabletOnly: true,
    mode: _point,
    target: (_) => 'nav-10',
    text: (_) => 'In den Einstellungen passt du ${Brand.name} an dich an. Dort kannst du mich auch jederzeit wieder rufen.',
  ),
  _Step(
    'bye',
    mode: (_) => TinteMode.present,
    text: (_) => 'Das war’s schon! Viel Spaß mit ${Brand.name}.',
    primary: 'Fertig',
    done: true,
  ),
];

class Tutorial {
  Tutorial._();

  static const prefsKey = 'tour_state';
  static final Map<String, GlobalKey> _keys = {};
  static final NavigatorObserver observer = _DialogObserver();
  static void Function(int index)? navigate;
  static _TutorialHostState? _host;

  static GlobalKey key(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tutorial-$id'));

  static bool get running => _host?._run != null;

  static void start() => _host?._start();

  static Future<void> startIfNew() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(prefsKey) != null) return;
    final dialogs = (observer as _DialogObserver).dialogs;
    while (dialogs.value > 0) {
      final closed = Completer<void>();
      void listener() {
        if (dialogs.value == 0 && !closed.isCompleted) closed.complete();
      }

      dialogs.addListener(listener);
      await closed.future;
      dialogs.removeListener(listener);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    start();
  }
}

class _DialogObserver extends NavigatorObserver {
  final ValueNotifier<int> dialogs = ValueNotifier(0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) dialogs.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) dialogs.value = math.max(0, dialogs.value - 1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => didPop(route, previousRoute);
}

class TutorialHost extends StatefulWidget {
  const TutorialHost({super.key, required this.child});

  final Widget child;

  @override
  State<TutorialHost> createState() => _TutorialHostState();
}

class _Run {
  _Run(this.rig, this.phone);

  final TinteRig rig;
  final bool phone;
  _Step? step;
  int token = 0;
  bool ending = false;
  String? lastTask;
}

class _Placement {
  const _Placement(this.guide, this.bubble, this.width, this.tail, {this.showBubble = true, this.docked = false});

  final Offset guide;
  final Offset bubble;
  final double width;
  final _Tail tail;
  final bool showBubble;
  final bool docked;
}

class _TutorialHostState extends State<TutorialHost> with TickerProviderStateMixin {
  _Run? _run;
  Rect? _target;
  late final AnimationController _spot = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _typing = AnimationController(vsync: this);
  late final AnimationController _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Rect _spotFrom = Rect.zero;
  Rect _spotTo = Rect.zero;
  double _spotRadius = 14;
  bool _dim = true;
  bool _interactive = false;
  bool _bubbleShown = false;
  _Placement? _placement;
  String _text = '';
  _Placement? _shownPlacement;
  String _shownText = '';
  _Step? _shownStep;
  Offset _pos = const Offset(-1000, -1000);
  Offset _from = Offset.zero;
  Offset _via = Offset.zero;
  Offset _to = Offset.zero;
  Offset _lastPos = Offset.zero;
  Duration _lastMoveTick = Duration.zero;
  Timer? _tracker;
  bool _guideGone = false;
  VoidCallback? _stopWaiting;

  @override
  void initState() {
    super.initState();
    Tutorial._host = this;
    _move.addListener(_onMove);
  }

  @override
  void dispose() {
    if (Tutorial._host == this) Tutorial._host = null;
    _tracker?.cancel();
    _stopWaiting?.call();
    _spot.dispose();
    _pulse.dispose();
    _move.dispose();
    _typing.dispose();
    _nudge.dispose();
    _run?.rig.dispose();
    super.dispose();
  }

  bool get _still => MediaQuery.of(context).disableAnimations;

  List<_Step> _visible(bool phone) => [for (final s in _steps) if (!(phone && s.tabletOnly)) s];

  _Step? _stepById(String id) {
    final run = _run;
    if (run == null) return null;
    for (final s in _visible(run.phone)) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _start() {
    if (_run != null) return;
    final phone = Tutorial._keys['nav']?.currentContext == null || Tutorial._keys['nav-more']?.currentContext != null;
    final rig = TinteRig(size: phone ? 96 : 120);
    setState(() {
      _run = _Run(rig, phone);
      _guideGone = false;
      _bubbleShown = false;
      _pos = const Offset(-1000, -1000);
    });
    _tracker = Timer.periodic(const Duration(milliseconds: 250), (_) => _track());
    _go('hello', first: true);
  }

  Future<void> _go(String id, {bool first = false}) async {
    final run = _run;
    final step = _stepById(id);
    if (run == null || step == null) return;
    final token = ++run.token;
    _stopWaiting?.call();
    _stopWaiting = null;
    setState(() => _bubbleShown = false);
    run.rig.hush();
    if (step.page != null) {
      Tutorial.navigate?.call(step.page!);
      await Future<void>.delayed(Duration(milliseconds: _still ? 60 : 420));
      if (!mounted || token != run.token) return;
    }
    run.step = step;
    final targetId = step.target?.call(run.phone);
    Rect? rect = _rectOf(targetId);
    for (var i = 0; targetId != null && rect == null && i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted || token != run.token) return;
      rect = _rectOf(targetId);
    }
    final text = step.text(run.phone);
    final placement = _place(rect, text, step);
    setState(() {
      _text = text;
      _target = rect;
      _placement = placement;
      _dim = step.dim;
      _interactive = step.wait != _Wait.none;
    });
    _moveSpot(rect, step);
    if (_interactive && !_still) {
      _pulse.repeat();
    } else {
      _pulse.stop();
    }
    run.rig.setMode(TinteMode.float);
    if (first) {
      _placeGuide(placement.guide);
      run.rig.appear();
      await Future<void>.delayed(Duration(milliseconds: _still ? 0 : 620));
    } else {
      await _swimTo(placement.guide);
    }
    if (!mounted || token != run.token) return;
    final mode = step.mode?.call(run.phone) ?? TinteMode.float;
    final aim = rect == null ? null : _aimAt(rect, placement.guide, run.rig.size);
    if ((mode == TinteMode.point || mode == TinteMode.watch) && aim == null) {
      run.rig.setMode(TinteMode.float);
    } else {
      run.rig.setMode(mode, target: aim);
    }
    setState(() {
      _bubbleShown = placement.showBubble;
      _shownPlacement = placement;
      _shownText = text;
      _shownStep = step;
    });
    if (placement.showBubble) {
      _type(text);
      run.rig.say(text);
    }
    _arm(step, token);
  }

  Rect? _rectOf(String? id) {
    if (id == null) return null;
    if (id == 'task-dialog') {
      final parts = [_boxOf('task-dialog-top'), _boxOf(id), _boxOf('task-dialog-save')].whereType<Rect>().toList();
      if (parts.isEmpty) return null;
      return parts.reduce((a, b) => a.expandToInclude(b)).inflate(22);
    }
    return _boxOf(id);
  }

  Rect? _boxOf(String id) {
    final object = Tutorial._keys[id]?.currentContext?.findRenderObject();
    final host = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize || host is! RenderBox) return null;
    final origin = object.localToGlobal(Offset.zero, ancestor: host);
    final rect = origin & object.size;
    if (rect.width < 2 || rect.height < 2) return null;
    return rect;
  }

  Offset _aimAt(Rect r, Offset guide, double size) {
    final c = guide + Offset(size / 2, size * .44);
    return Offset(c.dx.clamp(r.left + 6, math.max(r.left + 6, r.right - 6)), c.dy.clamp(r.top + 6, math.max(r.top + 6, r.bottom - 6)));
  }

  void _arm(_Step step, int token) {
    final run = _run!;
    if (step.wait == _Wait.dialog) {
      final dialogs = (Tutorial.observer as _DialogObserver).dialogs;
      void listener() {
        if (dialogs.value > 0 && run.token == token) _go('task-form');
      }

      dialogs.addListener(listener);
      _stopWaiting = () => dialogs.removeListener(listener);
      if (dialogs.value > 0) _go('task-form');
    }
    if (step.wait == _Wait.created) {
      final provider = context.read<AppProvider>();
      final dialogs = (Tutorial.observer as _DialogObserver).dialogs;
      final before = provider.lastAddedTaskId;
      var created = false;
      void onProvider() {
        if (created || run.token != token) return;
        if (provider.lastAddedTaskId != null && provider.lastAddedTaskId != before) {
          created = true;
          _go('task-done');
        }
      }

      void onDialogs() {
        if (dialogs.value > 0 || run.token != token) return;
        Future<void>.delayed(const Duration(milliseconds: 320), () {
          if (!created && _run == run && run.token == token) _go('task-new');
        });
      }

      provider.addListener(onProvider);
      dialogs.addListener(onDialogs);
      _stopWaiting = () {
        provider.removeListener(onProvider);
        dialogs.removeListener(onDialogs);
      };
    }
  }

  void _track() {
    final run = _run;
    final step = run?.step;
    if (run == null || step == null || run.ending || _placement == null || _move.isAnimating) return;
    final rect = _rectOf(step.target?.call(run.phone));
    final old = _target;
    if (rect == null || old == null) return;
    if ((rect.left - old.left).abs() + (rect.top - old.top).abs() + (rect.width - old.width).abs() + (rect.height - old.height).abs() < 3) return;
    final placement = _place(rect, _text, step);
    setState(() {
      _target = rect;
      _placement = placement;
      _shownPlacement = placement;
      _bubbleShown = placement.showBubble;
    });
    _moveSpot(rect, step);
    _swimTo(placement.guide).then((_) {
      if (_run == run && run.step == step && run.rig.target != null) run.rig.aim(_aimAt(rect, placement.guide, run.rig.size));
    });
  }

  void _moveSpot(Rect? rect, _Step step) {
    final size = MediaQuery.of(context).size;
    final next = rect == null ? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0) : rect.inflate(6);
    _spotFrom = _spotAnimated;
    _spotTo = next;
    _spotRadius = rect == null ? 0 : math.min(26, math.min(rect.height, rect.width) / 2 + 6);
    if (_spotFrom == Rect.zero || _still) {
      _spotFrom = next;
      _spot.value = 1;
    } else {
      _spot.forward(from: 0);
    }
  }

  Rect get _spotAnimated {
    final k = Curves.easeOutCubic.transform(_spot.value);
    return Rect.lerp(_spotFrom, _spotTo, k) ?? _spotTo;
  }

  void _placeGuide(Offset at) {
    _move.stop();
    _pos = at;
    final rig = _run?.rig;
    if (rig != null) {
      rig.origin = at;
      rig.moving = false;
      rig.velocity = Offset.zero;
    }
    setState(() {});
  }

  Future<void> _swimTo(Offset to) async {
    final rig = _run?.rig;
    if (rig == null) return;
    final dist = (to - _pos).distance;
    if (_still || _pos.dx < -500) {
      _placeGuide(to);
      return;
    }
    if (dist < 2) return;
    _from = _pos;
    _to = to;
    final d = to - _pos;
    final side = d.dx >= 0 ? -1.0 : 1.0;
    _via = (_pos + to) / 2 + Offset(-d.dy / dist, d.dx / dist) * (dist * .18 * side);
    _lastPos = _pos;
    _lastMoveTick = Duration.zero;
    rig.moving = true;
    _move.duration = Duration(milliseconds: (420 + dist * .7).clamp(520, 1200).round());
    await _move.forward(from: 0).orCancel.catchError((_) {});
    rig.moving = false;
    rig.velocity = Offset.zero;
  }

  void _onMove() {
    final rig = _run?.rig;
    if (rig == null) return;
    final u = Curves.easeInOut.transform(_move.value), v = 1 - u;
    final p = _from * (v * v) + _via * (2 * v * u) + _to * (u * u);
    final now = _move.lastElapsedDuration ?? Duration.zero;
    final dt = (now - _lastMoveTick).inMicroseconds / 1e6;
    if (dt > 0) rig.velocity = (p - _lastPos) / dt;
    _lastMoveTick = now;
    _lastPos = p;
    _pos = p;
    rig.origin = p;
    setState(() {});
  }

  void _type(String text) {
    if (_still) {
      _typing.value = 1;
      return;
    }
    _typing.duration = Duration(milliseconds: (text.length / 60 * 1000).round());
    _typing.forward(from: 0);
  }

  _Placement _place(Rect? r, String text, _Step step) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final phone = _run!.phone;
    final s = _run!.rig.size;
    const m = 12.0, gap = 14.0;
    final top = media.padding.top + 8, bottom = size.height - media.padding.bottom - 8;
    final w = size.width;
    final bw = math.min(phone ? 320.0 : 340.0, w - 24);
    final bh = _bubbleHeight(text, bw, step);
    bool fits(Offset o, double ww, double hh) => o.dx >= m - .5 && o.dy >= top - .5 && o.dx + ww <= w - m + .5 && o.dy + hh <= bottom + .5;
    bool hits(Offset o, double ww, double hh) => r != null && o.dx < r.right && o.dx + ww > r.left && o.dy < r.bottom && o.dy + hh > r.top;
    if (r == null) {
      final sidebar = _rectOf('nav');
      final left = phone || sidebar == null ? 0.0 : sidebar.right;
      if (s + 8 + bw <= w - left - 2 * m) {
        final x0 = left + (w - left - (s + 8 + bw)) / 2, y0 = size.height * .34;
        return _Placement(Offset(x0, y0 - s * .1), Offset(x0 + s + 8, y0), bw, _Tail.left);
      }
      final y0 = math.max(top, size.height * .2);
      return _Placement(Offset((w - s) / 2, y0), Offset((w - bw) / 2, y0 + s + 6), bw, _Tail.top);
    }
    final midY = (r.center.dy).clamp(top + s / 2, math.max(top + s / 2, bottom - s / 2));
    final midX = (r.center.dx).clamp(m + s / 2, math.max(m + s / 2, w - m - s / 2));
    final tries = <_Placement Function()>[
      () {
        final g = Offset(r.right + gap, midY - s * .46);
        return _Placement(g, Offset(g.dx + s + 6, (g.dy + s * .12 - bh * .3).clamp(top, math.max(top, bottom - bh))), bw, _Tail.left);
      },
      () {
        final g = Offset(r.left - gap - s, midY - s * .46);
        return _Placement(g, Offset(g.dx - 6 - bw, (g.dy + s * .12 - bh * .3).clamp(top, math.max(top, bottom - bh))), bw, _Tail.right);
      },
      () {
        final g = Offset(midX - s / 2, r.bottom + gap);
        final bx = g.dx + s + 6 + bw <= w - m ? g.dx + s + 6 : g.dx - 6 - bw;
        return _Placement(g, Offset(bx, g.dy + s * .12), bw, bx > g.dx ? _Tail.left : _Tail.right);
      },
      () {
        final g = Offset(midX - s / 2, r.top - gap - s);
        final bx = g.dx + s + 6 + bw <= w - m ? g.dx + s + 6 : g.dx - 6 - bw;
        return _Placement(g, Offset(bx, g.dy + s * .12), bw, bx > g.dx ? _Tail.left : _Tail.right);
      },
      () {
        final g = Offset(midX - s / 2, r.bottom + gap);
        return _Placement(g, Offset((r.center.dx - bw / 2).clamp(m, math.max(m, w - m - bw)), g.dy + s + 6), bw, _Tail.top);
      },
      () {
        final g = Offset(midX - s / 2, r.top - gap - s);
        return _Placement(g, Offset((r.center.dx - bw / 2).clamp(m, math.max(m, w - m - bw)), g.dy - 6 - bh), bw, _Tail.bottom);
      },
    ];
    for (final make in tries) {
      final p = make();
      if (fits(p.guide, s, s) && fits(p.bubble, bw, bh) && !hits(p.bubble, bw, bh) && !hits(p.guide + Offset(s * .2, s * .2), s * .6, s * .6)) return p;
    }
    for (final right in [true, false]) {
      final avail = right ? w - m - (r.right + gap) : r.left - gap - m;
      if (avail < 220) continue;
      final width = math.min(bw, avail);
      final h2 = _bubbleHeight(text, width, step);
      final gy = r.top.clamp(top, math.max(top, bottom - s - 6 - h2)).toDouble();
      final p = _Placement(
        Offset(right ? r.right + gap : r.left - gap - s, gy),
        Offset(right ? r.right + gap : r.left - gap - width, gy + s + 6),
        width,
        _Tail.top,
      );
      if (fits(p.guide, s, s) && fits(p.bubble, width, h2)) return p;
    }
    const dockGap = 6.0;
    final dw = w - 2 * m - s - 6;
    final dh = _bubbleHeight(text, dw, step, docked: true);
    final need = math.max(s, dh);
    final above = r.top - dockGap - top, below = bottom - r.bottom - dockGap;
    if (above >= need || below >= need) {
      final y0 = above >= need ? r.top - dockGap - need : r.bottom + dockGap;
      return _Placement(Offset(w - m - s, y0 + (need - s) / 2), Offset(m, y0 + (need - dh) / 2), dw, _Tail.right, docked: true);
    }
    if (step.wait != _Wait.none) {
      return _Placement(Offset(w - m - s, math.max(top, r.top - s * .62)), Offset(m, top), bw, _Tail.right, showBubble: false);
    }
    final p = tries[2]();
    return _Placement(
      Offset(p.guide.dx.clamp(m, w - m - s), p.guide.dy.clamp(top, math.max(top, bottom - s))),
      Offset(p.bubble.dx.clamp(m, math.max(m, w - m - bw)), p.bubble.dy.clamp(top, math.max(top, bottom - bh))),
      bw,
      p.tail,
    );
  }

  TextStyle _textStyle(BuildContext context) {
    final phone = _run?.phone ?? true;
    return (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(fontSize: phone ? 14.5 : 15, height: 1.5, fontWeight: FontWeight.w500, letterSpacing: -.05);
  }

  TextStyle _buttonStyle(BuildContext context) =>
      (Theme.of(context).textTheme.labelLarge ?? const TextStyle()).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1);

  double _bubbleHeight(String text, double width, _Step step, {bool docked = false}) {
    final padX = docked ? 14.0 : 18.0;
    final inner = width - padX * 2;
    final painter = TextPainter(text: TextSpan(text: text, style: _textStyle(context)), textDirection: TextDirection.ltr)..layout(maxWidth: inner - 26);
    final foot = _footWidth(step, docked);
    final rows = foot > inner ? 2 : 1;
    return (docked ? 12 : 16) + painter.height + (docked ? 10 : 14) + rows * 34 + (rows - 1) * 8 + (docked ? 10 : 14);
  }

  double _footWidth(_Step step, bool docked) {
    double label(String t) => (TextPainter(text: TextSpan(text: t, style: _buttonStyle(context)), textDirection: TextDirection.ltr)..layout()).width + 28;
    final dots = docked ? 0.0 : _dotCount * 6 + (_dotCount - 1) * 5 + 10 + 12;
    final back = _backOf(step);
    final buttons = (step.wait == _Wait.none ? label(step.primary) : 0.0) + (step.secondary != null ? label(step.secondary!) + 6 : (back != null ? label('Zurück') + 6 : 0.0));
    return dots + buttons;
  }

  int get _dotCount => _run == null ? 0 : _visible(_run!.phone).where((s) => s.dot).length;

  String? _backOf(_Step step) {
    if (step.back != '') return step.back;
    final list = _visible(_run!.phone);
    final i = list.indexOf(step);
    if (i <= 0) return null;
    final prev = list[i - 1];
    return prev.page != null || prev.wait != _Wait.none ? null : prev.id;
  }

  void _primary() {
    final run = _run;
    final step = run?.step;
    if (run == null || step == null || run.ending) return;
    if (step.done) {
      _end('done');
      return;
    }
    final list = _visible(run.phone);
    final i = list.indexOf(step);
    if (i >= 0 && i + 1 < list.length) _go(list[i + 1].id);
  }

  void _secondary() {
    final run = _run;
    final step = run?.step;
    if (run == null || step == null || run.ending) return;
    if (step.onSecondary == 'skip') {
      _end('skipped');
    } else if (step.onSecondary != null) {
      _go(step.onSecondary!);
    } else {
      final back = _backOf(step);
      if (back != null) _go(back);
    }
  }

  void _tapScrim() {
    _run?.rig.excite();
    _nudge.forward(from: 0);
  }

  Future<void> _end(String state) async {
    final run = _run;
    if (run == null || run.ending) return;
    run.ending = true;
    run.token++;
    _stopWaiting?.call();
    _stopWaiting = null;
    _tracker?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Tutorial.prefsKey, state);
    if (!mounted) return;
    setState(() {
      _bubbleShown = false;
      _dim = false;
      _interactive = true;
    });
    _pulse.stop();
    if (state == 'done') {
      await run.rig.bye();
    } else {
      setState(() => _guideGone = true);
      await Future<void>.delayed(Duration(milliseconds: _still ? 0 : 280));
    }
    if (!mounted) return;
    setState(() {
      _run = null;
      _target = null;
      _placement = null;
      _shownPlacement = null;
      _shownStep = null;
      _spotFrom = Rect.zero;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => run.rig.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return Stack(
      children: [
        widget.child,
        if (run != null)
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: Stack(children: _layer(context, run)),
            ),
          ),
      ],
    );
  }

  List<Widget> _layer(BuildContext context, _Run run) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ring = dark ? const Color(0xFFB7A6F6) : const Color(0xFF9580E8);
    final placement = _shownPlacement;
    return [
      Positioned.fill(
        child: IgnorePointer(
          ignoring: _interactive,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tapScrim,
            child: AnimatedOpacity(
              opacity: _dim ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: AnimatedBuilder(
                animation: Listenable.merge([_spot, _pulse]),
                builder: (context, _) => CustomPaint(
                  painter: _ScrimPainter(
                    hole: _spotAnimated,
                    radius: _spotRadius,
                    dim: dark ? const Color(0x9E04030A) : const Color(0x66181428),
                    ring: ring,
                    pulse: _interactive && _pulse.isAnimating ? _pulse.value : -1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: TinteBubblesPainter(run.rig, dark ? TintePalette.dark.bubble : TintePalette.light.bubble)),
        ),
      ),
      Positioned(
        left: _pos.dx,
        top: _pos.dy,
        child: AnimatedOpacity(
          opacity: _guideGone ? 0 : 1,
          duration: const Duration(milliseconds: 260),
          child: TinteView(rig: run.rig, onTap: run.rig.excite),
        ),
      ),
      if (placement != null)
        Positioned(
          left: placement.bubble.dx,
          top: placement.bubble.dy,
          width: placement.width,
          child: _bubble(context, run, placement, dark),
        ),
    ];
  }

  Widget _bubble(BuildContext context, _Run run, _Placement placement, bool dark) {
    final step = _shownStep;
    if (step == null) return const SizedBox.shrink();
    final docked = placement.docked;
    final surface = dark ? const Color(0xFF1D1C24) : Colors.white;
    final border = dark ? Colors.white.withValues(alpha: .08) : Colors.black.withValues(alpha: .06);
    final text = dark ? const Color(0xFFECECF3) : const Color(0xFF1D1C24);
    final muted = dark ? const Color(0xFFC7C6D1) : const Color(0xFF575665);
    const primary = Color(0xFF7353CD);
    final s = run.rig.size;
    final tailAt = switch (placement.tail) {
      _Tail.left || _Tail.right => (placement.guide.dy + s * .5 - placement.bubble.dy),
      _Tail.top || _Tail.bottom => (placement.guide.dx + s * .5 - placement.bubble.dx),
    };
    final back = _backOf(step);
    final list = _visible(run.phone);
    final dots = [for (final st in list) if (st.dot) st.id];
    final current = step.page == 1 && step.id != 'tasks' ? 'tasks' : step.id;
    final at = dots.indexOf(current);
    final style = _textStyle(context);
    return IgnorePointer(
      ignoring: !_bubbleShown,
      child: AnimatedOpacity(
        opacity: _bubbleShown ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: AnimatedSlide(
          offset: _bubbleShown ? Offset.zero : const Offset(0, .04),
          duration: const Duration(milliseconds: 300),
          curve: const Cubic(.34, 1.4, .64, 1),
          child: AnimatedBuilder(
            animation: _nudge,
            builder: (context, child) {
              final v = _nudge.value;
              final dx = v == 0 || v == 1 ? 0.0 : math.sin(v * math.pi * 3) * 5 * (1 - v);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Semantics(
              container: true,
              liveRegion: true,
              label: _shownText,
              child: CustomPaint(
                painter: _BubblePainter(surface, border, placement.tail, tailAt),
                child: Padding(
                  padding: docked ? const EdgeInsets.fromLTRB(14, 12, 14, 10) : const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ExcludeSemantics(
                              child: AnimatedBuilder(
                                animation: _typing,
                                builder: (context, _) {
                                  final n = (_shownText.length * _typing.value).floor().clamp(0, _shownText.length);
                                  return Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: _shownText.substring(0, n)),
                                      TextSpan(text: _shownText.substring(n), style: const TextStyle(color: Colors.transparent)),
                                    ]),
                                    style: style.copyWith(color: text),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Semantics(
                            button: true,
                            label: 'Tutorial beenden',
                            child: InkResponse(
                              onTap: () => _end('skipped'),
                              radius: 18,
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: Icon(Icons.close_rounded, size: 16, color: muted),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: docked ? 10 : 14),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 8,
                        spacing: 12,
                        children: [
                          if (!docked)
                            Visibility(
                              visible: step.dot || step.page == 1,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < dots.length; i++)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                      margin: EdgeInsets.only(right: i == dots.length - 1 ? 0 : 5),
                                      width: i == at ? 16 : 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(3),
                                        color: i == at
                                            ? (dark ? const Color(0xFF9580E8) : primary)
                                            : i < at
                                                ? (dark ? const Color(0xFFB7A6F6) : const Color(0xFF9580E8)).withValues(alpha: .55)
                                                : (dark ? Colors.white.withValues(alpha: .12) : Colors.black.withValues(alpha: .1)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (step.secondary != null || back != null)
                                _pill(step.secondary ?? 'Zurück', muted, Colors.transparent, _secondary),
                              if (step.wait == _Wait.none) ...[
                                const SizedBox(width: 6),
                                _pill(step.primary, dark ? const Color(0xFF14131A) : Colors.white, dark ? const Color(0xFF9580E8) : primary, _primary),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color fg, Color bg, VoidCallback onTap) {
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10.5),
          child: Text(label, style: _buttonStyle(context).copyWith(color: fg)),
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.hole, required this.radius, required this.dim, required this.ring, required this.pulse});

  final Rect hole;
  final double radius;
  final Color dim;
  final Color ring;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final cut = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cut);
    canvas.drawPath(path, Paint()..color = dim);
    if (hole.width < 1) return;
    canvas.drawRRect(
      cut.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring.withValues(alpha: .9),
    );
    if (pulse >= 0) {
      final k = pulse < .7 ? pulse / .7 : 1.0;
      canvas.drawRRect(
        cut.inflate(3 + 10 * Curves.easeOutCubic.transform(k)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ring.withValues(alpha: .95 * (1 - k)),
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole || old.radius != radius || old.dim != dim || old.ring != ring || old.pulse != pulse;
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.fill, this.border, this.tail, this.tailAt);

  final Color fill;
  final Color border;
  final _Tail tail;
  final double tailAt;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 18.0, t = 8.0;
    final body = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(r)));
    final along = tail == _Tail.left || tail == _Tail.right ? size.height : size.width;
    final at = tailAt.clamp(r + t, math.max(r + t, along - r - t)).toDouble();
    final nub = Path();
    switch (tail) {
      case _Tail.left:
        nub..moveTo(0, at - t)..lineTo(-t, at)..lineTo(0, at + t);
      case _Tail.right:
        nub..moveTo(size.width, at - t)..lineTo(size.width + t, at)..lineTo(size.width, at + t);
      case _Tail.top:
        nub..moveTo(at - t, 0)..lineTo(at, -t)..lineTo(at + t, 0);
      case _Tail.bottom:
        nub..moveTo(at - t, size.height)..lineTo(at, size.height + t)..lineTo(at + t, size.height);
    }
    nub.close();
    final shape = Path.combine(PathOperation.union, body, nub);
    canvas.drawShadow(shape, Colors.black.withValues(alpha: .5), 10, false);
    canvas.drawPath(shape, Paint()..color = fill);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.fill != fill || old.border != border || old.tail != tail || old.tailAt != tailAt;
}

