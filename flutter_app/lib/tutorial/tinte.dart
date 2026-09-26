// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

typedef _Pts = List<Offset>;

const double _tau = math.pi * 2;
const Curve _inout = Cubic(.42, 0, .58, 1);
const Curve _burstOut = Cubic(.15, .7, .3, 1);
const Curve _springOut = Cubic(.34, 1.56, .64, 1);

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _ease(Curve curve, double t) => curve.transform(_clamp(t, 0, 1));

_Pts _p(List<List<double>> list) => [for (final e in list) Offset(e[0], e[1])];
_Pts _mir(_Pts pts) => [for (final o in pts) Offset(120 - o.dx, o.dy)];
_Pts _lerpPose(_Pts a, _Pts b, double u) => [for (var i = 0; i < a.length; i++) Offset.lerp(a[i], b[i], u)!];
_Pts _scalePose(_Pts pts, Offset c, double k) => [for (final o in pts) c + (o - c) * k];

final _g1 = _p([[40, 64], [37, 76], [33, 87], [31, 96], [33.5, 101], [37.5, 100], [36.5, 96.5]]);
final _g1b = _p([[40, 64], [36, 76], [31, 86.5], [28.5, 95.5], [30.5, 100.5], [34.5, 100.5], [34, 97]]);
final _g2 = _p([[50, 68], [49, 80], [47, 91], [46.5, 100], [49, 104.5], [52.5, 103], [51, 100]]);
final _g2b = _p([[50, 68], [48.5, 80], [46, 91], [45, 100], [47, 104.8], [50.8, 103.8], [49.6, 100.6]]);
final _hl = _p([[39, 58], [31, 58.5], [25.5, 54], [23.5, 47.5], [25.5, 43]]);
final _hlUp = _p([[39, 58], [31, 51], [27, 41], [26.5, 31], [30, 25]]);
final _hlWave = _p([[39, 58], [30, 52], [24.5, 43], [22, 33], [24, 26.5]]);
final _hlTada = _p([[39, 58], [30, 53], [21.5, 49.5], [14, 50], [9.5, 54]]);
final _hr = _mir(_hl);
final _hrUp = _mir(_hlUp);
final _hrWave = _mir(_hlWave);
final _hrTada = _mir(_hlTada);

final _hanging = <(String, _Pts, _Pts, double, int)>[
  ('g1', _g1, _g1b, 4.2, 0),
  ('g2', _g2, _g2b, 3.8, 1),
  ('g3', _mir(_g2), _mir(_g2b), 4, 3),
  ('g4', _mir(_g1), _mir(_g1b), 4.4, 4),
];
const _armRoot = Offset(60, 66);
const _pivot = Offset(60, 56);
const _widths = {'g1': (9.0, 2.0, 1), 'g2': (9.5, 2.0, 1), 'g3': (9.5, 2.0, -1), 'g4': (9.0, 2.0, -1), 'hl': (7.5, 2.4, 0), 'hr': (7.5, 2.4, 0)};

const int _ribs = 30;

_Pts _spline(_Pts pts, int n) {
  final segs = pts.length - 1;
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1) * segs;
    final k = math.min(t.floor(), segs - 1);
    final u = t - k;
    final p0 = pts[math.max(k - 1, 0)], p1 = pts[k], p2 = pts[k + 1], p3 = pts[math.min(k + 2, segs)];
    double f(double a0, double a1, double a2, double a3) =>
        .5 * (2 * a1 + (a2 - a0) * u + (2 * a0 - 5 * a1 + 4 * a2 - a3) * u * u + (3 * a1 - a0 - 3 * a2 + a3) * u * u * u);
    out.add(Offset(f(p0.dx, p1.dx, p2.dx, p3.dx), f(p0.dy, p1.dy, p2.dy, p3.dy)));
  }
  return out;
}

class _Rib {
  const _Rib(this.p, this.n, this.w);
  final Offset p;
  final Offset n;
  final double w;
}

List<_Rib> _frame(_Pts pts, double w0, double w1) {
  final c = _spline(pts, _ribs);
  final out = <_Rib>[];
  for (var i = 0; i < _ribs; i++) {
    final a = c[math.max(i - 1, 0)], b = c[math.min(i + 1, _ribs - 1)];
    final d = b - a;
    final len = d.distance == 0 ? 1.0 : d.distance;
    out.add(_Rib(c[i], Offset(-d.dy / len, d.dx / len), (w0 + (w1 - w0) * math.pow(i / (_ribs - 1), .8)) / 2));
  }
  return out;
}

Path _outline(List<_Rib> fr) {
  final path = Path();
  for (var i = 0; i < fr.length; i++) {
    final o = fr[i].p + fr[i].n * fr[i].w;
    i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
  }
  for (var i = fr.length - 1; i >= 0; i--) {
    final o = fr[i].p - fr[i].n * fr[i].w;
    path.lineTo(o.dx, o.dy);
  }
  return path..close();
}

List<(Offset, double)> _suckers(List<_Rib> fr, int side) => [
      for (final t in const [.36, .54, .7])
        () {
          final q = fr[(t * (_ribs - 1)).round()];
          return (q.p + q.n * (side * q.w * .32), q.w * .42);
        }(),
    ];

Path _mantlePath() => Path()
  ..moveTo(32, 50)
  ..cubicTo(32, 29, 44, 16, 60, 16)
  ..cubicTo(76, 16, 88, 29, 88, 50)
  ..cubicTo(88, 62, 77, 71, 60, 71)
  ..cubicTo(43, 71, 32, 62, 32, 50)
  ..close();

Path _sparkPath() => Path()
  ..moveTo(0, -7)
  ..cubicTo(.9, -1.6, 1.6, -.9, 7, 0)
  ..cubicTo(1.6, .9, .9, 1.6, 0, 7)
  ..cubicTo(-.9, 1.6, -1.6, .9, -7, 0)
  ..cubicTo(-1.6, -.9, -.9, -1.6, 0, -7)
  ..close();

enum TinteMode { float, hello, point, watch, cheer, present, bye }

class TintePalette {
  const TintePalette({
    required this.lav,
    required this.lavShade,
    required this.lavHigh,
    required this.mint,
    required this.mintShade,
    required this.rose,
    required this.ink,
    required this.apricot,
    required this.inkCloud,
    required this.inkSoft,
    required this.bubble,
  });

  final Color lav, lavShade, lavHigh, mint, mintShade, rose, ink, apricot, inkCloud, inkSoft, bubble;

  static const light = TintePalette(
    lav: Color(0xFFB7A6F6),
    lavShade: Color(0xFF9F8CEF),
    lavHigh: Color(0xFFDAD1FC),
    mint: Color(0xFF8FE0C0),
    mintShade: Color(0xFF62C9A1),
    rose: Color(0xFFF2A5C4),
    ink: Color(0xFF2A2150),
    apricot: Color(0xFFF5B07E),
    inkCloud: Color(0xFF3D2E7C),
    inkSoft: Color(0xFF6A58BF),
    bubble: Color(0xFF9580E8),
  );

  static const dark = TintePalette(
    lav: Color(0xFFAE9CF5),
    lavShade: Color(0xFF9380EA),
    lavHigh: Color(0xFFCFC4FB),
    mint: Color(0xFF8FE0C0),
    mintShade: Color(0xFF62C9A1),
    rose: Color(0xFFF2A5C4),
    ink: Color(0xFF2A2150),
    apricot: Color(0xFFF5B07E),
    inkCloud: Color(0xFF9D89F0),
    inkSoft: Color(0xFFC9BEFA),
    bubble: Color(0xFFCFC4FB),
  );

  List<Color> get confetti => [lavShade, mint, rose, apricot, mintShade, lavHigh];
}

class _Confetto {
  _Confetto(math.Random r, this.index)
      : cx = -54 + r.nextDouble() * 108,
        cy = -40 + r.nextDouble() * 32,
        fall = 22 + r.nextDouble() * 14,
        spin = -360 + r.nextDouble() * 720,
        delay = r.nextDouble() * .1;
  final int index;
  final double cx, cy, fall, spin, delay;
  Offset pos = Offset.zero;
  double angle = 0, scale = 0, opacity = 0;
}

class _Blob {
  const _Blob(this.dx, this.dy, this.r, this.kind);
  final double dx, dy, r;
  final int kind;
}

const _blobs = [
  _Blob(0, 0, 22, 0), _Blob(-17, -9, 14, 0), _Blob(17, -10, 15, 1), _Blob(-19, 10, 13, 0), _Blob(18, 11, 14, 0),
  _Blob(0, -22, 12, 1), _Blob(-5, 19, 13, 0), _Blob(28, -1, 9, 0), _Blob(-29, 0, 9, 1),
  _Blob(-11, -7, 3.2, 2), _Blob(10, -12, 2.4, 2), _Blob(5, 8, 2, 2),
];

class _Bubble {
  _Bubble(this.origin, this.size, this.drift, this.born);
  final Offset origin;
  final double size, drift, born;
}

class TinteRig extends ChangeNotifier {
  TinteRig({this.size = 120, math.Random? random}) : _rnd = random ?? math.Random() {
    _ph = List.generate(10, (_) => _rnd.nextDouble() * _tau);
    t = _rnd.nextDouble() * 20;
    _nextBlink = t + .8 + _rnd.nextDouble() * 2.2;
    _confetti = List.generate(22, (i) => _Confetto(_rnd, i));
    _pose(frozen: false);
  }

  final double size;
  final math.Random _rnd;
  late final List<double> _ph;
  late final List<_Confetto> _confetti;

  bool still = false;
  Offset origin = const Offset(-1000, -1000);
  Offset velocity = Offset.zero;
  bool moving = false;

  TinteMode mode = TinteMode.float;
  double t = 0;
  double modeT = 0;
  Offset? target;
  Offset? lookTarget;
  int side = -1;
  double _talkUntil = -1;
  double _hopT = -9;
  double _joyUntil = -1;
  double _appearT = -9;
  double alpha = 1;
  Completer<void>? _bye;
  double _nextBlink = 0;
  double _blinkT = -1;
  bool _double = false;
  double _nextGlance = 0;
  Offset _glance = Offset.zero;
  Map<String, _Pts>? _from;
  double _blendT0 = 0;
  double _lastBubble = -1;
  final List<_Bubble> _bubbles = [];

  final Map<String, _Pts> _arms = {};
  Offset look = Offset.zero;
  double wrapTx = 0, wrapTy = 0, rot = 0, sx = 1, sy = 1, scale = 1, opacity = 1;
  double mantleRot = 0, breath = 0, brow = 0, blink = 1, joy = 0, mouth = 0;
  bool wink = false, talking = false;
  double burstU = -1, inkU = -1, tipK = -1;
  bool get gone => alpha <= 0;

  Offset get center => origin + Offset(size / 2, size * .44);

  void setMode(TinteMode next, {Offset? target}) {
    if (_bye != null && next != TinteMode.bye) {
      _bye!.complete();
      _bye = null;
    }
    _from = Map.of(_arms);
    _blendT0 = t;
    mode = next;
    modeT = 0;
    this.target = target;
    if (next != TinteMode.watch) lookTarget = null;
    _pickSide();
    if (still) _pose(frozen: true);
    notifyListeners();
  }

  void aim(Offset point) {
    target = point;
    _pickSide();
    if (still) {
      _pose(frozen: true);
      notifyListeners();
    }
  }

  void _pickSide() {
    final tg = target;
    if (tg == null) return;
    final dx = tg.dx - (origin.dx + size / 2);
    if (dx.abs() > size * .15) side = dx < 0 ? -1 : 1;
  }

  Future<void> bye() {
    alpha = 1;
    setMode(TinteMode.bye);
    if (still) {
      alpha = 0;
      notifyListeners();
      return Future<void>.delayed(const Duration(milliseconds: 220));
    }
    _bye = Completer<void>();
    return _bye!.future;
  }

  void appear() {
    alpha = 1;
    if (still) {
      notifyListeners();
      return;
    }
    _appearT = t;
    for (var i = 0; i < 5; i++) {
      _spawnBubble(origin + Offset(size * (.25 + _rnd.nextDouble() * .5), size * (.5 + _rnd.nextDouble() * .35)), delay: i * .09);
    }
  }

  void say(String text) {
    if (still) return;
    _talkUntil = t + _clamp(.4 + text.length / 34, .8, 4.2);
  }

  void hush() => _talkUntil = -1;

  void excite() {
    if (still || t - _hopT < .35) return;
    _hopT = t;
    _joyUntil = math.max(_joyUntil, t + .75);
  }

  void freeze() {
    _from = null;
    _pose(frozen: true);
    notifyListeners();
  }

  void step(double dt) {
    t += dt;
    modeT += dt;
    if (moving && velocity.distance > 160 && t - _lastBubble > .07) {
      _lastBubble = t;
      final dir = velocity / velocity.distance;
      _spawnBubble(origin + Offset(size / 2, size * .52) - dir * (size * .36) + Offset(_rnd.nextDouble() * 12 - 6, _rnd.nextDouble() * 12 - 6));
    }
    _bubbles.removeWhere((b) => t - b.born > .95);
    _pose(frozen: false);
    notifyListeners();
  }

  void _spawnBubble(Offset at, {double delay = 0}) {
    if (_bubbles.length > 16) return;
    _bubbles.add(_Bubble(at, size * (.05 + _rnd.nextDouble() * .04), _rnd.nextDouble() * 20 - 10, t + delay));
  }

  _Pts _wob(_Pts pts, double time, double amp, double per, double ph) {
    final n = pts.length - 1;
    return [
      for (var i = 0; i < pts.length; i++)
        i == 0
            ? pts[i]
            : () {
                final w = math.pow(i / n, 1.4).toDouble();
                return pts[i] +
                    Offset(amp * w * math.sin(_tau * time / per + ph - i * .8), amp * .7 * w * math.cos(_tau * time / (per * 1.13) + ph - i * .7));
              }(),
    ];
  }

  _Pts _pointArm(int side, double ang, double ext, double time, bool frozen) {
    final s = side < 0 ? const Offset(39, 58) : const Offset(81, 58);
    final d = Offset(math.cos(ang), math.sin(ang));
    var n = Offset(-d.dy, d.dx);
    if (n.dy > 0) n = -n;
    final len = 34 * ext;
    final pts = [
      for (var i = 0; i <= 4; i++) s + d * (len * i / 4) + n * (3.4 * math.sin(math.pi * i / 4)),
    ];
    pts[4] = pts[4] + n * 2.4 - d * 1.4;
    return frozen ? pts : _wob(pts, time, .45, 2.6, _ph[4]);
  }

  void _pose({required bool frozen}) {
    final time = t, mt = modeT, ph = _ph;
    final pose = <String, _Pts>{};
    for (final (name, a, b, per, off) in _hanging) {
      final k = frozen ? .5 : .5 + .5 * math.sin(_tau * time / per + off);
      pose[name] = frozen ? _lerpPose(a, b, k) : _wob(_lerpPose(a, b, k), time, 1.1, per * 1.2, ph[off]);
    }
    var hl = frozen ? _hl : _wob(_hl, time, 1.1, 3.1, ph[8]);
    var hr = frozen ? _hr : _wob(_hr, time, 1.1, 3.5, ph[9]);
    var tx = 0.0, ty = frozen ? 0.0 : -2.4 * math.sin(_tau * time / 3.4 + ph[0]);
    var r = 0.0, scx = 1.0, scy = 1.0, sc = 1.0;
    var mRot = frozen ? 0.0 : 2.2 * math.sin(_tau * time / 5.7 + ph[1]);
    var br = frozen ? 0.0 : .014 * math.sin(_tau * time / 3.2 + ph[5]);
    var j = time < _joyUntil ? 1.0 : 0.0;
    var bw = frozen ? 0.0 : -.5 * math.max(0, math.sin(_tau * time / 7.3 + ph[3]));
    Offset? lk;
    var wk = false;
    var op = alpha;
    final c = center;
    (double, double, double) dir(Offset p) {
      final a = math.atan2(p.dy - c.dy, p.dx - c.dx);
      return (math.cos(a), math.sin(a), a);
    }

    if (mode == TinteMode.hello || (mode == TinteMode.bye && mt < 1.35)) {
      hr = frozen ? _hrWave : _lerpPose(_hrUp, _hrWave, .5 + .5 * math.sin(_tau * mt / .52));
      j = 1;
      bw = -1.8;
      mRot -= 3;
      if (mode == TinteMode.hello && mt > 2.5 && !frozen) setMode(TinteMode.float);
    }

    if (mode == TinteMode.point && target != null) {
      final (dx, dy, a) = dir(target!);
      final tap = (mt % 1.3) / 1.3;
      final ext = frozen ? 1.0 : 1 + .11 * (tap < .24 ? math.sin(math.pi * tap / .24) : 0);
      final arm = _pointArm(side, a, ext, time, frozen);
      if (side < 0) {
        hl = arm;
      } else {
        hr = arm;
      }
      mRot += 6 * dx;
      tx += 2 * dx;
      lk = Offset(dx, dy);
      bw = -1;
    }

    if (mode == TinteMode.watch) {
      final focus = lookTarget ?? target;
      if (focus != null) {
        final (dx, dy, _) = dir(focus);
        lk = Offset(dx, dy);
        final cycle = mt % 7;
        final e = cycle > 4.6 && cycle < 6.2 ? _ease(_inout, math.min(cycle - 4.6, 6.2 - cycle) / .3) : 0.0;
        if (e > 0 && target != null) {
          final (_, _, pa) = dir(target!);
          final arm = _pointArm(side, pa, 1, time, frozen);
          if (side < 0) {
            hl = _lerpPose(hl, arm, e);
          } else {
            hr = _lerpPose(hr, arm, e);
          }
        }
      }
      final nod = mt % 3.4;
      if (nod < .5 && !frozen) {
        ty += 2.4 * math.sin(math.pi * nod / .5);
        bw -= 1.2 * math.sin(math.pi * nod / .5);
      }
    }

    if (mode == TinteMode.present) {
      hl = frozen ? _hlTada : _wob(_hlTada, time, .7, 2.9, ph[2]);
      hr = frozen ? _hrTada : _wob(_hrTada, time, .7, 3.3, ph[6]);
      if (mt < 1) j = 1;
      if (mt < .45 && !frozen) ty -= 4 * math.sin(math.pi * mt / .45);
      bw = -1.6;
      tipK = frozen ? -1 : _clamp((mt - .2) / .5, 0, 1);
    } else {
      tipK = -1;
    }

    if (mode == TinteMode.cheer) {
      final u = mt;
      if (u < .18) {
        final k = _ease(_inout, u / .18);
        scy = 1 - .12 * k;
        scx = 1 + .09 * k;
        ty += 3 * k;
        for (final key in pose.keys.toList()) {
          pose[key] = _scalePose(pose[key]!, _armRoot, 1 - .25 * k);
        }
      } else if (u < .84) {
        final k = (u - .18) / .66, s = math.sin(math.pi * k);
        r = -360 * _ease(_inout, k);
        ty += -26 * s;
        for (final key in pose.keys.toList()) {
          pose[key] = _scalePose(pose[key]!, _armRoot, 1 + .3 * s);
        }
        hl = _hlUp;
        hr = _hrUp;
        j = 1;
        bw = -2.4;
      } else if (u < 1.08) {
        final s = math.sin(math.pi * (u - .84) / .24);
        ty += 5 * s;
        scy = 1 - .07 * s;
        scx = 1 + .06 * s;
        hl = _hlUp;
        hr = _hrUp;
        j = 1;
        bw = -2.4;
      } else {
        final w = u - 1.08;
        hl = _lerpPose(_hlUp, _hlWave, .5 + .5 * math.sin(_tau * w / .5));
        hr = _lerpPose(_hrUp, _hrWave, .5 + .5 * math.sin(_tau * w / .5 + math.pi));
        ty += -2.6 * math.sin(_tau * w / 1.1).abs();
        j = 1;
        bw = -2;
        if (u > 2.6 && !frozen) {
          _joyUntil = t + .5;
          setMode(TinteMode.float);
          return;
        }
      }
      if (frozen) {
        hl = _hlUp;
        hr = _hrUp;
        j = 1;
      }
      burstU = frozen ? -1 : u - .4;
    } else {
      burstU = -1;
    }
    _burst();

    if (mode == TinteMode.bye) {
      if (mt >= 1.35 && mt < 1.8) {
        wk = true;
        j = 0;
        mRot += 4 * math.sin(math.pi * (mt - 1.35) / .45);
        hr = _lerpPose(_hrWave, _hr, _ease(_inout, (mt - 1.35) / .45));
      }
      if (mt >= 1.8 && mt < 1.95) {
        final k = (mt - 1.8) / .15;
        scy = 1 - .12 * k;
        scx = 1 + .1 * k;
      }
      if (mt >= 1.95) {
        final k = _clamp((mt - 1.95) / .22, 0, 1);
        sc = 1 - .85 * _ease(_inout, k);
        ty -= 8 * k;
        op = 1 - k;
      }
      inkU = mt - 1.9;
      if (mt > 3.6) {
        alpha = 0;
        op = 0;
        final done = _bye;
        _bye = null;
        done?.complete();
      }
    } else {
      inkU = -1;
    }

    if (moving && !frozen) {
      final sp = velocity.distance, s = _clamp(sp / 700, 0, 1);
      if (sp > 1) {
        final u = velocity / sp, pulse = math.max(0.0, math.sin(_tau * time / .46));
        for (final key in pose.keys.toList()) {
          final pts = _scalePose(pose[key]!, _armRoot, 1 - .16 * pulse * s);
          final last = pts.length - 1;
          pose[key] = [for (var i = 0; i < pts.length; i++) pts[i] - u * (14 * s * math.pow(i / last, 1.25))];
        }
        r += _clamp(u.dx * 16 * s, -16, 16);
        br += .03 * s * pulse;
        lk = u;
      }
    }

    if (_appearT > -9) {
      final k = _clamp((time - _appearT) / .6, 0, 1);
      sc *= .35 + .65 * _ease(_springOut, k);
      ty += 16 * (1 - _ease(_inout, k));
      op *= _clamp(k / .25, 0, 1);
      if (k >= 1) _appearT = -9;
    }

    final hop = time - _hopT;
    if (hop >= 0 && hop < .45 && !frozen) {
      ty -= 7 * math.sin(math.pi * hop / .45);
      scy *= 1 + .04 * math.sin(math.pi * hop / .45);
    }

    if (lk == null && lookTarget != null && mode != TinteMode.watch) {
      final (dx, dy, _) = dir(lookTarget!);
      lk = Offset(dx, dy);
    }
    if (lk == null && !frozen) {
      if (time > _nextGlance) {
        _glance = Offset(-.9 + _rnd.nextDouble() * 1.8, -.7 + _rnd.nextDouble() * 1.2);
        _nextGlance = time + 1.2 + _rnd.nextDouble() * 2.2;
      }
      lk = _glance;
    }
    final goal = Offset((lk ?? Offset.zero).dx * 2.4, (lk ?? Offset.zero).dy * 1.9);
    look = frozen ? goal : look + (goal - look) * math.min(1.0, .28 + (moving ? .3 : 0));

    var m = 0.0;
    final isTalking = !frozen && time < _talkUntil;
    if (isTalking) {
      final n = .55 * math.sin(_tau * time * 6.1) + .3 * math.sin(_tau * time * 9.3 + 1.3) + .15 * math.sin(_tau * time * 2.7 + .4);
      final gap = (time * 1.3) % 1 > .86;
      m = gap ? 0 : _clamp(.2 + .8 * math.max(0, n), 0, 1);
      bw -= .8 * m;
    }

    var bl = 1.0;
    if (!frozen && j == 0) {
      if (_blinkT < 0 && time > _nextBlink) {
        _blinkT = time;
        _double = _rnd.nextDouble() < .2;
      }
      if (_blinkT >= 0) {
        final u = (time - _blinkT) / .15, end = _double ? 2.4 : 1.0;
        if (u >= end) {
          _blinkT = -1;
          _nextBlink = time + 2.2 + _rnd.nextDouble() * 3.3;
        } else {
          final v = u >= 1.4 ? u - 1.4 : u;
          if (v < 1) bl = 1 - .9 * math.sin(math.pi * v);
        }
      }
    }

    for (final (name, _, _, _, _) in _hanging) {
      _arms[name] = _blend(name, pose[name]!);
    }
    _arms['hl'] = _blend('hl', hl);
    _arms['hr'] = _blend('hr', hr);
    wrapTx = tx;
    wrapTy = ty;
    rot = r;
    sx = scx;
    sy = scy;
    scale = sc;
    opacity = op;
    mantleRot = mRot;
    breath = br;
    brow = bw;
    blink = bl;
    joy = j;
    wink = wk;
    mouth = m;
    talking = isTalking;
  }

  _Pts _blend(String name, _Pts pts) {
    final from = _from?[name];
    if (from == null || from.length != pts.length) return pts;
    final k = _clamp((t - _blendT0) / .34, 0, 1);
    if (k >= 1) {
      _from!.remove(name);
      return pts;
    }
    return _lerpPose(from, pts, _ease(_inout, k));
  }

  void _burst() {
    final u = burstU;
    final on = u >= 0 && u < 2.2;
    for (final c in _confetti) {
      final q = on ? _clamp((u - c.delay) / 1.9, 0, 1) : 0.0;
      if (!on || q <= 0) {
        c.opacity = 0;
        continue;
      }
      final b = _ease(_burstOut, q / .2), g = math.pow(_clamp((q - .12) / .88, 0, 1), 2).toDouble();
      c.pos = Offset(60 + c.cx * (b + .15 * g), 40 + c.cy * b + c.fall * g);
      c.angle = c.spin * _clamp(q / .6, 0, 1) * math.pi / 180;
      c.scale = _clamp(.4 + q * 4, .4, 1);
      c.opacity = q < .62 ? 1 : _clamp(1 - (q - .62) / .3, 0, 1);
    }
  }
}

class TintePainter extends CustomPainter {
  TintePainter(this.rig, this.palette) : super(repaint: rig);

  final TinteRig rig;
  final TintePalette palette;

  static final Path _mantle = _mantlePath();
  static final Path _spark = _sparkPath();
  static const _sparks = [(Offset(8, 36), true, 0.0), (Offset(112, 30), false, .05), (Offset(114, 80), true, .1), (Offset(6, 84), false, .15)];

  @override
  void paint(Canvas canvas, Size size) {
    if (rig.opacity <= 0.001 && rig.inkU < 0) return;
    canvas.save();
    canvas.scale(size.width / 120);
    final layer = rig.opacity < .999;
    if (layer) canvas.saveLayer(const Rect.fromLTWH(-60, -60, 240, 240), Paint()..color = Color.fromRGBO(0, 0, 0, rig.opacity));
    _body(canvas);
    if (layer) canvas.restore();
    _ink(canvas);
    _fx(canvas);
    canvas.restore();
  }

  void _body(Canvas canvas) {
    final fill = Paint()..isAntiAlias = true;
    canvas.save();
    canvas.translate(_pivot.dx + rig.wrapTx, _pivot.dy + rig.wrapTy);
    canvas.rotate(rig.rot * math.pi / 180);
    canvas.scale(rig.sx * rig.scale, rig.sy * rig.scale);
    canvas.translate(-_pivot.dx, -_pivot.dy);
    for (final name in const ['g1', 'g2', 'g3', 'g4', 'hl', 'hr']) {
      final pts = rig._arms[name];
      if (pts == null) continue;
      final (w0, w1, side) = _widths[name]!;
      final fr = _frame(pts, w0, w1);
      canvas.drawPath(_outline(fr), fill..color = palette.lav);
      if (side != 0) {
        for (final (c, r) in _suckers(fr, side)) {
          canvas.drawCircle(c, r, fill..color = palette.rose.withValues(alpha: .8));
        }
      }
    }
    canvas.save();
    canvas.translate(60, 71);
    canvas.rotate(rig.mantleRot * math.pi / 180);
    canvas.scale(1 - rig.breath * .6, 1 + rig.breath);
    canvas.translate(-60, -71);
    canvas.drawPath(_mantle, fill..color = palette.lav);
    canvas.save();
    canvas.clipPath(_mantle);
    canvas.drawOval(Rect.fromCenter(center: const Offset(60, 71), width: 64, height: 20), fill..color = palette.lavShade.withValues(alpha: .55));
    canvas.restore();
    canvas.save();
    canvas.translate(46, 29);
    canvas.rotate(-30 * math.pi / 180);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 17, height: 9), fill..color = palette.lavHigh.withValues(alpha: .85));
    canvas.restore();
    fill.color = palette.mint;
    canvas.drawCircle(const Offset(72, 27), 2.4, fill);
    canvas.drawCircle(const Offset(78, 36), 1.6, fill);
    canvas.drawCircle(const Offset(43, 42), 1.3, fill);
    _face(canvas);
    canvas.restore();
    canvas.restore();
  }

  void _face(Canvas canvas) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = palette.ink;
    final fill = Paint()..color = palette.ink;
    canvas.save();
    canvas.translate(0, rig.brow);
    stroke.strokeWidth = 1.9;
    canvas.drawPath(Path()..moveTo(44.8, 38.4)..relativeQuadraticBezierTo(5.1, -3.5, 10.2, 0), stroke);
    canvas.drawPath(Path()..moveTo(65, 38.4)..relativeQuadraticBezierTo(5.1, -3.5, 10.2, 0), stroke);
    canvas.restore();

    canvas.save();
    canvas.translate(rig.look.dx, rig.look.dy);
    const s = 1.05;
    for (var i = 0; i < 2; i++) {
      final x = i == 0 ? 50.0 : 70.0;
      const y = 47.0;
      final shut = rig.wink && i == 1;
      final eyeAlpha = shut ? 0.0 : 1 - rig.joy;
      if (eyeAlpha > 0) {
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(1, rig.blink);
        canvas.translate(-x, -y);
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 7.8 * s, height: 9.8 * s), Paint()..color = palette.ink.withValues(alpha: eyeAlpha));
        final white = Paint()..color = Colors.white.withValues(alpha: eyeAlpha);
        canvas.drawCircle(Offset(x + 1.3 * s, y - 1.8 * s), 1.55 * s, white);
        canvas.drawCircle(Offset(x - 1.3 * s, y + 2 * s), .75 * s, white);
        canvas.restore();
      }
      stroke.strokeWidth = 2.1;
      if (rig.joy > 0) {
        stroke.color = palette.ink.withValues(alpha: rig.joy);
        canvas.drawPath(Path()..moveTo(x - 4 * s, y + 1.4 * s)..relativeQuadraticBezierTo(4 * s, -5 * s, 8 * s, 0), stroke);
      }
      if (shut) {
        stroke.color = palette.ink;
        canvas.drawPath(Path()..moveTo(x - 4 * s, y + .6 * s)..relativeQuadraticBezierTo(4 * s, 3.8 * s, 8 * s, 0), stroke);
      }
    }
    canvas.restore();

    final blush = Paint()..color = palette.rose.withValues(alpha: .62);
    canvas.drawOval(Rect.fromCenter(center: const Offset(42.5, 55.5), width: 9.2, height: 5.4), blush);
    canvas.drawOval(Rect.fromCenter(center: const Offset(77.5, 55.5), width: 9.2, height: 5.4), blush);

    if (rig.talking) {
      canvas.save();
      canvas.translate(60, 56.6);
      canvas.scale(1, math.max(.12, rig.mouth));
      canvas.translate(-60, -56.6);
      canvas.drawOval(Rect.fromCenter(center: const Offset(60, 59.4), width: 6.8, height: 5.8), fill);
      canvas.drawOval(Rect.fromCenter(center: const Offset(60, 60.9), width: 4, height: 2.2), Paint()..color = palette.rose);
      canvas.restore();
      return;
    }
    final open = rig.wink ? 1.0 : rig.joy;
    if (open < 1) {
      stroke
        ..strokeWidth = 2.1
        ..color = palette.ink.withValues(alpha: 1 - open);
      canvas.drawPath(Path()..moveTo(53.6, 56.6)..relativeQuadraticBezierTo(6.4, 5.6, 12.8, 0), stroke);
    }
    if (open > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(53.4, 56.2)
          ..relativeQuadraticBezierTo(6.6, 10, 13.2, 0)
          ..close(),
        Paint()..color = palette.ink.withValues(alpha: open),
      );
    }
  }

  void _ink(Canvas canvas) {
    final u = rig.inkU;
    if (u < 0 || u >= 1.65) return;
    final grow = _ease(_burstOut, u / .32), fade = _clamp((u - .7) / .9, 0, 1);
    final alpha = (1 - fade) * (u < .06 ? u / .06 : 1);
    for (final b in _blobs) {
      final color = switch (b.kind) { 0 => palette.inkCloud, 1 => palette.inkSoft, _ => Colors.white };
      final center = Offset(60 + b.dx * (.4 + .6 * grow) + b.dx * .15 * fade, 54 + b.dy * (.4 + .6 * grow) - 10 * fade);
      canvas.drawCircle(center, b.r * (.3 + .7 * grow) * (1 + .25 * fade), Paint()..color = color.withValues(alpha: alpha));
    }
  }

  void _fx(Canvas canvas) {
    final paint = Paint();
    final colors = palette.confetti;
    for (final c in rig._confetti) {
      if (c.opacity <= 0) continue;
      paint.color = colors[c.index % colors.length].withValues(alpha: c.opacity);
      canvas.save();
      canvas.translate(c.pos.dx, c.pos.dy);
      canvas.rotate(c.angle);
      canvas.scale(c.scale);
      if (c.index % 3 == 0) {
        canvas.drawCircle(Offset.zero, 1.9, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-2.1, -1.2, 4.2, 2.4), const Radius.circular(.6)), paint);
      }
      canvas.restore();
    }
    final u = rig.burstU;
    if (u >= 0 && u < 2.2) {
      for (final (at, lavender, delay) in _sparks) {
        final q = _clamp((u - delay) / .5, 0, 1);
        if (q <= 0 || q >= 1) continue;
        _drawSpark(canvas, at, q * math.pi / 2, math.sin(math.pi * q) * 1.15, lavender ? palette.lavShade : palette.mint);
      }
    }
    final k = rig.tipK;
    if (k > 0 && k < 1) {
      final s = math.sin(math.pi * k) * .9;
      for (final name in const ['hl', 'hr']) {
        final pts = rig._arms[name];
        if (pts == null) continue;
        final tip = pts.last + Offset(name == 'hl' ? -3 : 3, -4);
        final at = Offset(_pivot.dx + rig.wrapTx + (tip.dx - _pivot.dx) * rig.scale, _pivot.dy + rig.wrapTy + (tip.dy - _pivot.dy) * rig.scale);
        _drawSpark(canvas, at, k * math.pi / 2, s, name == 'hl' ? palette.mint : palette.lavShade);
      }
    }
  }

  void _drawSpark(Canvas canvas, Offset at, double angle, double scale, Color color) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    canvas.drawPath(_spark, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(TintePainter oldDelegate) => oldDelegate.rig != rig || oldDelegate.palette != palette;
}

class TinteBubblesPainter extends CustomPainter {
  TinteBubblesPainter(this.rig, this.color) : super(repaint: rig);

  final TinteRig rig;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in rig._bubbles) {
      final k = _clamp((rig.t - b.born) / .95, 0, 1);
      if (rig.t < b.born) continue;
      final e = _ease(const Cubic(.2, .8, .2, 1), k);
      final center = b.origin + Offset(b.drift * e, -28 * e);
      final radius = b.size / 2 * (.45 + .6 * e);
      final alpha = .95 * (1 - k);
      canvas.drawCircle(center, radius, Paint()..color = Colors.white.withValues(alpha: alpha * .35));
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: alpha * .6),
      );
      canvas.drawCircle(center + Offset(-radius * .35, -radius * .35), radius * .22, Paint()..color = Colors.white.withValues(alpha: alpha * .8));
    }
  }

  @override
  bool shouldRepaint(TinteBubblesPainter oldDelegate) => oldDelegate.rig != rig || oldDelegate.color != color;
}

class TinteView extends StatefulWidget {
  const TinteView({super.key, required this.rig, this.onTap});

  final TinteRig rig;
  final VoidCallback? onTap;

  @override
  State<TinteView> createState() => _TinteViewState();
}

class _TinteViewState extends State<TinteView> with SingleTickerProviderStateMixin {
  static const _frame = 1 / 30;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _acc = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    widget.rig.still = still;
    if (still) {
      if (_ticker.isActive) _ticker.stop();
      widget.rig.freeze();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _acc += _clamp(dt, 0, .1);
    if (_acc >= _frame - .004) {
      widget.rig.step(math.min(.1, _acc));
      _acc = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = widget.rig.size;
    return ExcludeSemantics(
      child: GestureDetector(
        onTap: widget.onTap,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            painter: TintePainter(widget.rig, dark ? TintePalette.dark : TintePalette.light),
          ),
        ),
      ),
    );
  }
}
