// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

(function () {
  'use strict';

  const TAU = Math.PI * 2;
  const r2 = n => Math.round(n * 100) / 100;
  const rnd = (a, b) => a + Math.random() * (b - a);
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const px = n => n.toFixed(2) + 'px';
  let uid = 0;

  function bezier(x1, y1, x2, y2) {
    const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
    const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    return x => {
      let t = x;
      for (let i = 0; i < 6; i++) {
        const d = (3 * ax * t + 2 * bx) * t + cx;
        if (Math.abs(d) < 1e-6) break;
        t -= (((ax * t + bx) * t + cx) * t - x) / d;
      }
      t = clamp(t, 0, 1);
      return ((ay * t + by) * t + cy) * t;
    };
  }
  const inout = bezier(.42, 0, .58, 1);
  const burstOut = bezier(.15, .7, .3, 1);
  const springOut = bezier(.34, 1.56, .64, 1);
  const gravity = x => x * x;

  const TN = 30;
  function spline(pts, n) {
    const segs = pts.length - 1, out = [];
    for (let i = 0; i < n; i++) {
      const t = i / (n - 1) * segs, k = Math.min(Math.floor(t), segs - 1), u = t - k;
      const p0 = pts[Math.max(k - 1, 0)], p1 = pts[k], p2 = pts[k + 1], p3 = pts[Math.min(k + 2, segs)];
      const f = j => .5 * (2 * p1[j] + (p2[j] - p0[j]) * u + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * u * u + (3 * p1[j] - p0[j] - 3 * p2[j] + p3[j]) * u * u * u);
      out.push([f(0), f(1)]);
    }
    return out;
  }
  function frame(pts, w0, w1) {
    const c = spline(pts, TN), out = [];
    for (let i = 0; i < TN; i++) {
      const a = c[Math.max(i - 1, 0)], b = c[Math.min(i + 1, TN - 1)];
      let dx = b[0] - a[0], dy = b[1] - a[1];
      const len = Math.hypot(dx, dy) || 1;
      dx /= len; dy /= len;
      out.push({ p: c[i], n: [-dy, dx], w: (w0 + (w1 - w0) * Math.pow(i / (TN - 1), .8)) / 2 });
    }
    return out;
  }
  function outline(fr) {
    let l = '', r = '';
    for (let i = 0; i < fr.length; i++) {
      const q = fr[i];
      l += (i ? 'L' : 'M') + (q.p[0] + q.n[0] * q.w).toFixed(2) + ' ' + (q.p[1] + q.n[1] * q.w).toFixed(2);
    }
    for (let i = fr.length - 1; i >= 0; i--) {
      const q = fr[i];
      r += 'L' + (q.p[0] - q.n[0] * q.w).toFixed(2) + ' ' + (q.p[1] - q.n[1] * q.w).toFixed(2);
    }
    return l + r + 'Z';
  }
  const SUCK = [.36, .54, .7];
  function suckerPos(fr, side) {
    return SUCK.map(t => {
      const q = fr[Math.round(t * (TN - 1))], s = side * q.w * .32;
      return [q.p[0] + q.n[0] * s, q.p[1] + q.n[1] * s, q.w * .42];
    });
  }
  function armSvg(name, pts, w0, w1, side) {
    const fr = frame(pts, w0, w1);
    return `<path class="t-lav" data-arm="${name}" data-w0="${w0}" data-w1="${w1}" data-side="${side}" d="${outline(fr)}"/>`
      + (side ? suckerPos(fr, side).map(([x, y, r]) => `<circle class="t-sucker" data-s="${name}" cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${r.toFixed(2)}"/>`).join('') : '');
  }

  const MIR = p => p.map(([x, y]) => [r2(120 - x), y]);
  const lerpPose = (a, b, u) => a.map((p, i) => [p[0] + (b[i][0] - p[0]) * u, p[1] + (b[i][1] - p[1]) * u]);
  const scalePose = (pts, cx, cy, k) => pts.map(([x, y]) => [cx + (x - cx) * k, cy + (y - cy) * k]);

  const T = {
    g1: [[40, 64], [37, 76], [33, 87], [31, 96], [33.5, 101], [37.5, 100], [36.5, 96.5]],
    g1b: [[40, 64], [36, 76], [31, 86.5], [28.5, 95.5], [30.5, 100.5], [34.5, 100.5], [34, 97]],
    g2: [[50, 68], [49, 80], [47, 91], [46.5, 100], [49, 104.5], [52.5, 103], [51, 100]],
    g2b: [[50, 68], [48.5, 80], [46, 91], [45, 100], [47, 104.8], [50.8, 103.8], [49.6, 100.6]],
    hl: [[39, 58], [31, 58.5], [25.5, 54], [23.5, 47.5], [25.5, 43]],
    hlup: [[39, 58], [31, 51], [27, 41], [26.5, 31], [30, 25]],
    hlwv: [[39, 58], [30, 52], [24.5, 43], [22, 33], [24, 26.5]],
    hlta: [[39, 58], [30, 53], [21.5, 49.5], [14, 50], [9.5, 54]]
  };
  const P = {
    g3: MIR(T.g2), g3b: MIR(T.g2b), g4: MIR(T.g1), g4b: MIR(T.g1b),
    hr: MIR(T.hl), hrup: MIR(T.hlup), hrwv: MIR(T.hlwv), hrta: MIR(T.hlta)
  };
  const HANGING = [['g1', T.g1, T.g1b, 4.2, 0], ['g2', T.g2, T.g2b, 3.8, 1.6], ['g3', P.g3, P.g3b, 4, 3.1], ['g4', P.g4, P.g4b, 4.4, 4.7]];
  const ARM_ROOT = [60, 66];

  const MANTLE = 'M32 50C32 29 44 16 60 16C76 16 88 29 88 50C88 62 77 71 60 71C43 71 32 62 32 50Z';
  const SPARK = 'M0 -7C.9 -1.6 1.6 -.9 7 0C1.6 .9 .9 1.6 0 7C-.9 1.6 -1.6 .9 -7 0C-1.6 -.9 -.9 -1.6 0 -7Z';
  const PIVOT = [60, 56];

  function eyes(x1, x2, y, s) {
    const rx = 3.9 * s, ry = 4.9 * s;
    const one = x => `<g class="t-eye" data-cx="${x}" data-cy="${y}"><ellipse cx="${x}" cy="${y}" rx="${r2(rx)}" ry="${r2(ry)}"/><circle class="t-white" cx="${r2(x + 1.3 * s)}" cy="${r2(y - 1.8 * s)}" r="${r2(1.55 * s)}"/><circle class="t-white" cx="${r2(x - 1.3 * s)}" cy="${r2(y + 2 * s)}" r="${r2(.75 * s)}"/></g>`;
    const arc = (x, up) => `M${r2(x - 4 * s)} ${r2(y + (up ? 1.4 : .6) * s)}q${r2(4 * s)} ${r2((up ? -5 : 3.8) * s)} ${r2(8 * s)} 0`;
    return `<g class="t-look">${one(x1)}${one(x2)}<path class="t-eye-happy" d="${arc(x1, 1)}"/><path class="t-eye-happy" d="${arc(x2, 1)}"/><path class="t-eye-closed" d="${arc(x1, 0)}"/><path class="t-eye-closed" d="${arc(x2, 0)}"/></g>`;
  }

  function confetti() {
    const cols = ['t-lav-s', 't-mint', 't-rose', 't-apri', 't-mint-s', 't-lav-h'];
    let out = '';
    for (let i = 0; i < 22; i++) {
      const c = cols[i % cols.length];
      const data = `data-cx="${r2(rnd(-54, 54))}" data-cy="${r2(rnd(-40, -8))}" data-fall="${r2(rnd(22, 36))}" data-cr="${Math.round(rnd(-360, 360))}" data-d="${r2(rnd(0, .1))}"`;
      out += i % 3 === 0
        ? `<circle class="t-confetti ${c}" ${data} cx="0" cy="0" r="1.9" opacity="0"/>`
        : `<rect class="t-confetti ${c}" ${data} x="-2.1" y="-1.2" width="4.2" height="2.4" rx=".6" opacity="0"/>`;
    }
    return out;
  }

  function inkCloud() {
    const blobs = [[0, 0, 22], [-17, -9, 14], [17, -10, 15], [-19, 10, 13], [18, 11, 14], [0, -22, 12], [-5, 19, 13], [28, -1, 9], [-29, 0, 9]];
    return blobs.map(([dx, dy, r], i) => `<circle class="${i % 3 === 2 ? 't-ink-soft' : 't-ink-cloud'}" data-dx="${dx}" data-dy="${dy}" data-r="${r}" cx="60" cy="54" r="0" opacity="0"/>`).join('')
      + [[-11, -7, 3.2], [10, -12, 2.4], [5, 8, 2]].map(([dx, dy, r]) => `<circle class="t-ink-shine" data-dx="${dx}" data-dy="${dy}" data-r="${r}" cx="60" cy="54" r="0" opacity="0"/>`).join('');
  }

  function guideSvg(id) {
    const arms = HANGING.map(([name, pose], i) => armSvg(name, pose, i === 1 || i === 2 ? 9.5 : 9, 2, i < 2 ? 1 : -1)).join('')
      + armSvg('hl', T.hl, 7.5, 2.4, 0) + armSvg('hr', P.hr, 7.5, 2.4, 0);
    const face = `<g class="t-brows"><path class="t-brow" d="M44.8 38.4q5.1 -3.5 10.2 0"/><path class="t-brow" d="M65 38.4q5.1 -3.5 10.2 0"/></g>`
      + eyes(50, 70, 47, 1.05)
      + `<ellipse class="t-blush" cx="42.5" cy="55.5" rx="4.6" ry="2.7"/><ellipse class="t-blush" cx="77.5" cy="55.5" rx="4.6" ry="2.7"/>`
      + `<path class="t-mouth" d="M53.6 56.6q6.4 5.6 12.8 0"/><path class="t-mouth-open" d="M53.4 56.2q6.6 10 13.2 0z"/>`
      + `<g class="t-talk"><ellipse class="t-ink-f" cx="60" cy="59.4" rx="3.4" ry="2.9"/><ellipse class="t-rose" cx="60" cy="60.9" rx="2" ry="1.1"/></g>`;
    const sparks = [[8, 36, 't-l'], [112, 30, 't-t'], [114, 80, 't-l'], [6, 84, 't-t']]
      .map(([x, y, c], i) => `<g transform="translate(${x} ${y})"><path class="t-spark ${c}" data-spark="${i * .05}" d="${SPARK}"/></g>`).join('');
    const tips = `<g class="t-tip" data-hand="hl"><path class="t-spark t-t" d="${SPARK}"/></g><g class="t-tip" data-hand="hr"><path class="t-spark t-l" d="${SPARK}"/></g>`;
    return `<svg class="tinte-art" viewBox="0 0 120 120" focusable="false">`
      + `<defs><clipPath id="tinte-guide-${id}"><path d="${MANTLE}"/></clipPath></defs>`
      + `<g class="t-wrap"><g class="t-body">${arms}`
      + `<g class="t-mantle"><path class="t-lav" d="${MANTLE}"/>`
      + `<g clip-path="url(#tinte-guide-${id})"><ellipse class="t-lav-s" cx="60" cy="71" rx="32" ry="10" opacity=".55"/></g>`
      + `<ellipse class="t-lav-h" cx="46" cy="29" rx="8.5" ry="4.5" transform="rotate(-30 46 29)" opacity=".85"/>`
      + `<circle class="t-mint" cx="72" cy="27" r="2.4"/><circle class="t-mint" cx="78" cy="36" r="1.6"/><circle class="t-mint" cx="43" cy="42" r="1.3"/>`
      + face + `</g></g></g>`
      + `<g class="t-ink">${inkCloud()}</g>`
      + `<g class="t-fx">${confetti()}${sparks}${tips}</g>`
      + `</svg>`;
  }

  const weakDevice = () => new URLSearchParams(location.search).has('lite')
    || !!(navigator.connection && navigator.connection.saveData)
    || (navigator.hardwareConcurrency || 8) <= 2
    || (navigator.deviceMemory || 8) <= 2;
  const motionAllowed = () => !matchMedia('(prefers-reduced-motion: reduce)').matches && !weakDevice();

  const STEP = 1 / 30;
  const GUIDES = new Set();
  let running = false, paused = false, lastFrame = 0, acc = 0;
  let pointerX = -1, pointerY = -1, pointerAt = -1e9;

  function wake() {
    if (running || paused || !GUIDES.size || document.visibilityState !== 'visible') return;
    running = true;
    lastFrame = performance.now();
    acc = 0;
    requestAnimationFrame(loop);
  }

  function loop(now) {
    if (!GUIDES.size || paused || document.visibilityState !== 'visible') {
      running = false;
      return;
    }
    const raw = Math.min(.1, Math.max(0, (now - lastFrame) / 1000));
    lastFrame = now;
    acc += raw;
    const tick = acc >= STEP - .004;
    const dt = Math.min(.1, acc);
    if (tick) acc = 0;
    let busy = false;
    for (const g of GUIDES) busy = g.frame(now, tick ? dt : 0) || busy;
    if (busy) requestAnimationFrame(loop);
    else running = false;
  }

  document.addEventListener('visibilitychange', wake);
  addEventListener('blur', () => { paused = true; });
  addEventListener('focus', () => { paused = false; wake(); });
  addEventListener('pointermove', e => {
    pointerX = e.clientX;
    pointerY = e.clientY;
    pointerAt = performance.now();
  }, { passive: true });

  let bubbleLayer = null;
  function bubble(x, y, size) {
    if (!bubbleLayer || !bubbleLayer.isConnected) {
      bubbleLayer = document.createElement('div');
      bubbleLayer.className = 'tinte-bubbles';
      bubbleLayer.setAttribute('aria-hidden', 'true');
      document.body.appendChild(bubbleLayer);
    }
    if (bubbleLayer.childElementCount > 16) return;
    const b = document.createElement('i');
    const s = size * rnd(.05, .09);
    b.style.cssText = `left:${px(x - s / 2)};top:${px(y - s / 2)};width:${px(s)};height:${px(s)};--drift:${px(rnd(-10, 10))}`;
    b.addEventListener('animationend', () => b.remove());
    bubbleLayer.appendChild(b);
  }

  class Guide {
    constructor(options) {
      const opts = options || {};
      this.size = opts.size || 128;
      const el = document.createElement('div');
      el.className = 'tinte-guide';
      el.setAttribute('aria-hidden', 'true');
      el.style.width = el.style.height = px(this.size);
      el.innerHTML = guideSvg(++uid);
      (opts.parent || document.body).appendChild(el);
      this.el = el;
      this.svg = el.firstElementChild;
      const q = s => this.svg.querySelector(s), qa = s => [...this.svg.querySelectorAll(s)];
      this.arms = {};
      for (const a of qa('[data-arm]')) {
        const name = a.dataset.arm;
        this.arms[name] = { el: a, w0: +a.dataset.w0, w1: +a.dataset.w1, side: +a.dataset.side, suck: qa(`[data-s="${name}"]`) };
      }
      this.wrap = q('.t-wrap');
      this.mantle = q('.t-mantle');
      this.brows = q('.t-brows');
      this.lookEl = q('.t-look');
      this.eyes = qa('.t-eye').map(e => ({ el: e, cx: +e.dataset.cx, cy: +e.dataset.cy }));
      this.happy = qa('.t-eye-happy');
      this.closed = qa('.t-eye-closed');
      this.smile = q('.t-mouth');
      this.open = q('.t-mouth-open');
      this.talkEl = q('.t-talk');
      this.conf = qa('.t-confetti').map(c => ({ el: c, cx: +c.dataset.cx, cy: +c.dataset.cy, fall: +c.dataset.fall, cr: +c.dataset.cr, d: +c.dataset.d }));
      this.sparks = qa('[data-spark]').map(s => ({ el: s, d: +s.dataset.spark }));
      this.tips = qa('.t-tip').map(g => ({ el: g, hand: g.dataset.hand }));
      this.ink = qa('.t-ink circle').map(c => ({ el: c, dx: +c.dataset.dx, dy: +c.dataset.dy, r: +c.dataset.r }));
      this.ph = Array.from({ length: 10 }, () => rnd(0, TAU));
      this.t = rnd(0, 20);
      this.mode = 'float';
      this.modeT = 0;
      this.opts = {};
      this.cur = {};
      this.from = null;
      this.blendT0 = 0;
      this.x = -1000;
      this.y = -1000;
      this.move = null;
      this.vel = [0, 0];
      this.lookX = 0;
      this.lookY = 0;
      this.nextGlance = 0;
      this.glance = [0, 0];
      this.talkUntil = -1;
      this.hopT = -9;
      this.joyUntil = -1;
      this.side = -1;
      this.alpha = 1;
      this.appearT = -9;
      this.nextBlink = rnd(.8, 3);
      this.blinkT = -1;
      this.lastBubble = 0;
      this.done = null;
      this.held = false;
      this.still = !motionAllowed();
      this.el.classList.toggle('is-static', this.still);
      this.el.addEventListener('click', () => this.excite());
      GUIDES.add(this);
      this.render();
      wake();
    }

    place(x, y) {
      this.x = x;
      this.y = y;
      this.move = null;
      this.el.style.transform = `translate3d(${px(x)},${px(y)},0)`;
    }

    moveTo(x, y, options) {
      const opts = options || {};
      if (this.move) this.move.resolve();
      if (this.still || this.x < -500) {
        this.place(x, y);
        this.render();
        return Promise.resolve();
      }
      const dx = x - this.x, dy = y - this.y, dist = Math.hypot(dx, dy);
      if (dist < 2) return Promise.resolve();
      const bend = opts.bend === undefined ? .18 : opts.bend;
      const side = dx >= 0 ? -1 : 1;
      const cx = (this.x + x) / 2 + (-dy / (dist || 1)) * dist * bend * side;
      const cy = (this.y + y) / 2 + (dx / (dist || 1)) * dist * bend * side;
      return new Promise(resolve => {
        this.move = { x0: this.x, y0: this.y, x1: x, y1: y, cx, cy, t0: performance.now(), dur: clamp(420 + dist * .7, 520, 1200), resolve, px: this.x, py: this.y };
        wake();
      });
    }

    setMode(mode, options) {
      if (this.done && mode !== 'bye') {
        this.done();
        this.done = null;
      }
      this.from = Object.assign({}, this.cur);
      this.blendT0 = this.t;
      this.mode = mode;
      this.modeT = 0;
      this.opts = options || {};
      if (mode === 'point' || mode === 'watch') this.pickSide();
      if (this.still) this.render();
      wake();
      if (mode === 'bye') {
        this.alpha = 1;
        if (this.still) {
          this.el.classList.add('is-gone');
          return new Promise(resolve => setTimeout(resolve, 260));
        }
        return new Promise(resolve => { this.done = resolve; });
      }
      return Promise.resolve();
    }

    target(x, y) {
      this.opts.x = x;
      this.opts.y = y;
      this.pickSide();
      if (this.still) this.render();
    }

    pickSide() {
      if (this.opts.x === undefined) return;
      const dx = this.opts.x - (this.x + this.size / 2);
      if (Math.abs(dx) > this.size * .15) this.side = dx < 0 ? -1 : 1;
    }

    appear() {
      this.alpha = 1;
      this.el.classList.remove('is-gone');
      if (this.still) return Promise.resolve();
      this.appearT = this.t;
      for (let i = 0; i < 5; i++) setTimeout(() => this.puff(), 80 + i * 90);
      wake();
      return new Promise(resolve => setTimeout(resolve, 650));
    }

    say(text) {
      if (this.still) return;
      this.talkUntil = this.t + clamp(.4 + String(text || '').length / 34, .8, 4.2);
      wake();
    }

    hush() {
      this.talkUntil = -1;
    }

    hold(on) {
      this.held = !!on;
      if (!on) wake();
    }

    excite() {
      if (this.still || this.t - this.hopT < .35) return;
      this.hopT = this.t;
      this.joyUntil = Math.max(this.joyUntil, this.t + .75);
      wake();
    }

    lookAt(x, y) {
      this.opts.lookX = x;
      this.opts.lookY = y;
    }

    puff() {
      const s = this.size, r = this.el.getBoundingClientRect();
      bubble(r.left + s * rnd(.25, .75), r.top + s * rnd(.5, .85), s);
    }

    destroy() {
      if (this.move) this.move.resolve();
      if (this.done) this.done();
      GUIDES.delete(this);
      this.el.remove();
      if (!GUIDES.size && bubbleLayer) {
        bubbleLayer.remove();
        bubbleLayer = null;
      }
    }

    frame(now, dt) {
      if (this.move) {
        const m = this.move, k = clamp((now - m.t0) / m.dur, 0, 1), u = inout(k), v = 1 - u;
        const x = v * v * m.x0 + 2 * v * u * m.cx + u * u * m.x1;
        const y = v * v * m.y0 + 2 * v * u * m.cy + u * u * m.y1;
        const step = Math.max(1, now - (m.last || m.t0));
        this.vel = [(x - m.px) / step * 1000, (y - m.py) / step * 1000];
        m.px = x;
        m.py = y;
        m.last = now;
        this.x = x;
        this.y = y;
        this.el.style.transform = `translate3d(${px(x)},${px(y)},0)`;
        if (now - this.lastBubble > 70 && Math.hypot(this.vel[0], this.vel[1]) > 160) {
          this.lastBubble = now;
          const sp = Math.hypot(this.vel[0], this.vel[1]) || 1, s = this.size, r = this.el.getBoundingClientRect();
          bubble(r.left + s / 2 - this.vel[0] / sp * s * .36 + rnd(-6, 6), r.top + s * .52 - this.vel[1] / sp * s * .36 + rnd(-6, 6), s);
        }
        if (k >= 1) {
          this.move = null;
          this.vel = [0, 0];
          m.resolve();
        }
      }
      if (dt && !this.held) this.step(dt);
      return !this.still && (!!this.move || this.el.isConnected);
    }

    render() {
      const saved = this.t;
      if (this.still) {
        const sample = { hello: .9, point: .45, watch: .2, cheer: 1.3, present: .7, float: 0, bye: 0 }[this.mode] || 0;
        this.from = null;
        this.modeT = sample;
        this.pose(saved, true);
        return;
      }
      this.pose(saved, false);
    }

    step(dt) {
      this.t += dt;
      this.modeT += dt;
      this.pose(this.t, false);
    }

    pose(t, frozen) {
      const mt = this.modeT, ph = this.ph;
      const arms = {};
      for (const [name, a, b, per, off] of HANGING) {
        const k = frozen ? .5 : .5 + .5 * Math.sin(TAU * t / per + off);
        arms[name] = frozen ? lerpPose(a, b, k) : this.wob(lerpPose(a, b, k), t, 1.1, per * 1.2, ph[off | 0]);
      }
      let hl = frozen ? T.hl : this.wob(T.hl, t, 1.1, 3.1, ph[8]);
      let hr = frozen ? P.hr : this.wob(P.hr, t, 1.1, 3.5, ph[9]);
      let tx = 0, ty = frozen ? 0 : -2.4 * Math.sin(TAU * t / 3.4 + ph[0]), rot = 0, sx = 1, sy = 1, scale = 1;
      let mRot = frozen ? 0 : 2.2 * Math.sin(TAU * t / 5.7 + ph[1]), breath = frozen ? 0 : .014 * Math.sin(TAU * t / 3.2 + ph[5]);
      let joy = t < this.joyUntil ? 1 : 0, brow = frozen ? 0 : -.5 * Math.max(0, Math.sin(TAU * t / 7.3 + ph[3]));
      let look = null, wink = 0, opacity = this.alpha;
      const mode = this.mode, o = this.opts;
      const cx = this.x + this.size / 2, cy = this.y + this.size * .44;
      const dir = (x, y) => {
        const a = Math.atan2(y - cy, x - cx);
        return [Math.cos(a), Math.sin(a), a];
      };

      if (mode === 'hello' || (mode === 'bye' && mt < 1.35)) {
        const wave = lerpPose(P.hrup, P.hrwv, .5 + .5 * Math.sin(TAU * mt / .52));
        hr = frozen ? P.hrwv : wave;
        joy = 1;
        brow = -1.8;
        mRot += -3;
        if (mode === 'hello' && mt > 2.5 && !frozen) this.setMode('float');
      }

      if (mode === 'point' && o.x !== undefined) {
        const [dx, dy, a] = dir(o.x, o.y);
        const tap = (mt % 1.3) / 1.3, ext = frozen ? 1 : 1 + .11 * (tap < .24 ? Math.sin(Math.PI * tap / .24) : 0);
        const arm = this.pointArm(this.side, a, ext, t, frozen);
        if (this.side < 0) hl = arm; else hr = arm;
        mRot += 6 * dx;
        tx += 2 * dx;
        look = [dx, dy];
        brow = -1;
      }

      if (mode === 'watch') {
        const tx0 = o.lookX !== undefined ? o.lookX : o.x, ty0 = o.lookY !== undefined ? o.lookY : o.y;
        if (tx0 !== undefined) {
          const [dx, dy] = dir(tx0, ty0);
          look = [dx, dy];
          const cycle = mt % 7, e = cycle > 4.6 && cycle < 6.2 ? inout(clamp(Math.min(cycle - 4.6, 6.2 - cycle) / .3, 0, 1)) : 0;
          if (e > 0 && o.x !== undefined) {
            const [, , pa] = dir(o.x, o.y);
            const arm = this.pointArm(this.side, pa, 1, t, frozen);
            if (this.side < 0) hl = lerpPose(hl, arm, e); else hr = lerpPose(hr, arm, e);
          }
        }
        const nod = mt % 3.4;
        if (nod < .5 && !frozen) {
          ty += 2.4 * Math.sin(Math.PI * nod / .5);
          brow -= 1.2 * Math.sin(Math.PI * nod / .5);
        }
      }

      if (mode === 'present') {
        hl = frozen ? T.hlta : this.wob(T.hlta, t, .7, 2.9, ph[2]);
        hr = frozen ? P.hrta : this.wob(P.hrta, t, .7, 3.3, ph[6]);
        if (mt < 1) joy = 1;
        if (mt < .45 && !frozen) ty -= 4 * Math.sin(Math.PI * mt / .45);
        brow = -1.6;
        for (const tip of this.tips) {
          const pts = tip.hand === 'hl' ? hl : hr, p = pts[pts.length - 1];
          const k = frozen ? 0 : clamp((mt - .2) / .5, 0, 1);
          const s = k > 0 && k < 1 ? Math.sin(Math.PI * k) * .9 : 0;
          tip.el.style.transform = `translate(${px(p[0] + (tip.hand === 'hl' ? -3 : 3))},${px(p[1] - 4)}) rotate(${(k * 90).toFixed(1)}deg) scale(${s.toFixed(3)})`;
        }
      } else {
        for (const tip of this.tips) tip.el.style.transform = 'scale(0)';
      }

      if (mode === 'cheer') {
        const u = mt;
        if (u < .18) {
          const k = inout(u / .18);
          sy = 1 - .12 * k;
          sx = 1 + .09 * k;
          ty += 3 * k;
          for (const n in arms) arms[n] = scalePose(arms[n], ARM_ROOT[0], ARM_ROOT[1], 1 - .25 * k);
        } else if (u < .84) {
          const k = (u - .18) / .66, e = inout(k), s = Math.sin(Math.PI * k);
          rot = -360 * e;
          ty += -26 * s;
          for (const n in arms) arms[n] = scalePose(arms[n], ARM_ROOT[0], ARM_ROOT[1], 1 + .3 * s);
          hl = T.hlup;
          hr = P.hrup;
          joy = 1;
          brow = -2.4;
        } else if (u < 1.08) {
          const k = (u - .84) / .24, s = Math.sin(Math.PI * k);
          ty += 5 * s;
          sy = 1 - .07 * s;
          sx = 1 + .06 * s;
          hl = T.hlup;
          hr = P.hrup;
          joy = 1;
          brow = -2.4;
        } else {
          const w = u - 1.08;
          hl = lerpPose(T.hlup, T.hlwv, .5 + .5 * Math.sin(TAU * w / .5));
          hr = lerpPose(P.hrup, P.hrwv, .5 + .5 * Math.sin(TAU * w / .5 + Math.PI));
          ty += -2.6 * Math.abs(Math.sin(TAU * w / 1.1));
          joy = 1;
          brow = -2;
          if (u > 2.6 && !frozen) {
            this.joyUntil = this.t + .5;
            this.setMode('float');
          }
        }
        if (frozen) {
          hl = T.hlup;
          hr = P.hrup;
          joy = 1;
        }
        this.burst(frozen ? -1 : u - .4);
      } else {
        this.burst(-1);
      }

      if (mode === 'bye') {
        if (mt >= 1.35 && mt < 1.8) {
          wink = 1;
          joy = 0;
          mRot += 4 * Math.sin(Math.PI * (mt - 1.35) / .45);
          hr = lerpPose(P.hrwv, P.hr, inout((mt - 1.35) / .45));
        }
        if (mt >= 1.8 && mt < 1.95) {
          const k = (mt - 1.8) / .15;
          sy = 1 - .12 * k;
          sx = 1 + .1 * k;
        }
        if (mt >= 1.95) {
          const k = clamp((mt - 1.95) / .22, 0, 1);
          scale = 1 - .85 * inout(k);
          ty -= 8 * k;
          opacity = 1 - k;
        }
        this.inkPuff(mt - 1.9);
        if (mt > 3.6) {
          this.alpha = 0;
          this.el.classList.add('is-gone');
          if (this.done) {
            const d = this.done;
            this.done = null;
            d();
          }
        }
      } else {
        this.inkPuff(-1);
      }

      if (this.move && !frozen) {
        const sp = Math.hypot(this.vel[0], this.vel[1]), s = clamp(sp / 700, 0, 1);
        if (sp > 1) {
          const ux = this.vel[0] / sp, uy = this.vel[1] / sp, pulse = Math.max(0, Math.sin(TAU * t / .46));
          for (const n in arms) {
            const pts = scalePose(arms[n], ARM_ROOT[0], ARM_ROOT[1], 1 - .16 * pulse * s);
            const last = pts.length - 1;
            arms[n] = pts.map((p, i) => {
              const w = Math.pow(i / last, 1.25);
              return [p[0] - ux * 14 * s * w, p[1] - uy * 14 * s * w];
            });
          }
          rot += clamp(ux * 16 * s, -16, 16);
          breath += .03 * s * pulse;
          look = [ux, uy];
        }
      }

      if (this.appearT > -9) {
        const k = clamp((t - this.appearT) / .6, 0, 1);
        scale *= .35 + .65 * springOut(k);
        ty += 16 * (1 - inout(k));
        opacity *= clamp(k / .25, 0, 1);
        if (k >= 1) this.appearT = -9;
      }

      const hop = t - this.hopT;
      if (hop >= 0 && hop < .45 && !frozen) {
        ty -= 7 * Math.sin(Math.PI * hop / .45);
        sy *= 1 + .04 * Math.sin(Math.PI * hop / .45);
      }

      if (!look && o.lookX !== undefined && mode !== 'watch') {
        const [dx, dy] = dir(o.lookX, o.lookY);
        look = [dx, dy];
      }
      if (!look && !frozen && performance.now() - pointerAt < 2500 && pointerX >= 0) {
        const dx = pointerX - cx, dy = pointerY - cy, d = Math.hypot(dx, dy) || 1, k = Math.min(1, d / 260);
        look = [dx / d * k, dy / d * k];
      }
      if (!look && !frozen) {
        if (t > this.nextGlance) {
          this.glance = [rnd(-.9, .9), rnd(-.7, .5)];
          this.nextGlance = t + rnd(1.2, 3.4);
        }
        look = this.glance;
      }
      look = look || [0, 0];
      const lx = look[0] * 2.4, ly = look[1] * 1.9;
      if (frozen) {
        this.lookX = lx;
        this.lookY = ly;
      } else {
        const f = Math.min(1, .28 + (this.move ? .3 : 0));
        this.lookX += (lx - this.lookX) * f;
        this.lookY += (ly - this.lookY) * f;
      }

      let mouth = 0;
      if (!frozen && t < this.talkUntil) {
        const n = .55 * Math.sin(TAU * t * 6.1) + .3 * Math.sin(TAU * t * 9.3 + 1.3) + .15 * Math.sin(TAU * t * 2.7 + .4);
        const gap = (t * 1.3) % 1 > .86;
        mouth = gap ? 0 : clamp(.2 + .8 * Math.max(0, n), 0, 1);
        brow -= .8 * mouth;
      }

      for (const [name] of HANGING) this.setArm(name, arms[name]);
      this.setArm('hl', hl);
      this.setArm('hr', hr);
      this.wrap.style.transform = `translate(${px(PIVOT[0] + tx)},${px(PIVOT[1] + ty)}) rotate(${rot.toFixed(2)}deg) scale(${(sx * scale).toFixed(4)},${(sy * scale).toFixed(4)}) translate(${px(-PIVOT[0])},${px(-PIVOT[1])})`;
      this.mantle.style.transform = `translate(60px,71px) rotate(${mRot.toFixed(2)}deg) scale(${(1 - breath * .6).toFixed(4)},${(1 + breath).toFixed(4)}) translate(-60px,-71px)`;
      this.brows.style.transform = `translate(0px,${px(brow)})`;
      this.lookEl.style.transform = `translate(${px(this.lookX)},${px(this.lookY)})`;
      this.el.style.opacity = opacity.toFixed(3);
      this.face(t, joy, wink, mouth, frozen);
    }

    face(t, joy, wink, mouth, frozen) {
      let blink = 1;
      if (!frozen && !joy) {
        if (this.blinkT < 0 && t > this.nextBlink) {
          this.blinkT = t;
          this.dbl = Math.random() < .2;
        }
        if (this.blinkT >= 0) {
          const u = (t - this.blinkT) / .15, end = this.dbl ? 2.4 : 1;
          if (u >= end) {
            this.blinkT = -1;
            this.nextBlink = t + rnd(2.2, 5.5);
          } else {
            const v = u >= 1.4 ? u - 1.4 : u;
            if (v < 1) blink = 1 - .9 * Math.sin(Math.PI * v);
          }
        }
      }
      this.eyes.forEach((e, i) => {
        const shut = wink && i === 1;
        e.el.style.opacity = shut ? '0' : (1 - joy).toFixed(3);
        e.el.style.transform = `translate(${e.cx}px,${e.cy}px) scale(1,${blink.toFixed(3)}) translate(${-e.cx}px,${-e.cy}px)`;
      });
      this.happy.forEach(h => { h.style.opacity = joy.toFixed(3); });
      this.closed.forEach((c, i) => { c.style.opacity = wink && i === 1 ? '1' : '0'; });
      const talking = mouth > 0 || (!frozen && t < this.talkUntil);
      this.smile.style.opacity = talking ? '0' : (1 - joy).toFixed(3);
      this.open.style.opacity = talking ? '0' : (wink ? '1' : joy.toFixed(3));
      this.talkEl.style.opacity = talking ? '1' : '0';
      this.talkEl.style.transform = `translate(60px,56.6px) scale(1,${Math.max(.12, mouth).toFixed(3)}) translate(-60px,-56.6px)`;
    }

    burst(u) {
      const on = u >= 0 && u < 2.2;
      if (!on && !this.bursting) return;
      this.bursting = on;
      for (const c of this.conf) {
        const q = on ? clamp((u - c.d) / 1.9, 0, 1) : 0;
        if (!on || q <= 0) {
          c.el.style.opacity = '0';
          continue;
        }
        const b = burstOut(clamp(q / .2, 0, 1)), g = gravity(clamp((q - .12) / .88, 0, 1));
        const r = c.cr * clamp(q / .6, 0, 1);
        c.el.style.transform = `translate(${px(60 + c.cx * (b + .15 * g))},${px(40 + c.cy * b + c.fall * g)}) rotate(${r.toFixed(1)}deg) scale(${clamp(.4 + q * 4, .4, 1).toFixed(3)})`;
        c.el.style.opacity = (q < .62 ? 1 : clamp(1 - (q - .62) / .3, 0, 1)).toFixed(3);
      }
      for (const s of this.sparks) {
        const q = on ? clamp((u - s.d) / .5, 0, 1) : 0;
        const sc = q > 0 && q < 1 ? Math.sin(Math.PI * q) * 1.15 : 0;
        s.el.style.transform = `rotate(${(q * 90).toFixed(1)}deg) scale(${sc.toFixed(3)})`;
      }
    }

    inkPuff(u) {
      const on = u >= 0 && u < 1.65;
      if (!on && !this.inking) return;
      this.inking = on;
      for (const b of this.ink) {
        if (!on) {
          b.el.setAttribute('r', '0');
          b.el.setAttribute('opacity', '0');
          continue;
        }
        const grow = burstOut(clamp(u / .32, 0, 1)), fade = clamp((u - .7) / .9, 0, 1);
        b.el.setAttribute('cx', (60 + b.dx * (.4 + .6 * grow) + b.dx * .15 * fade).toFixed(2));
        b.el.setAttribute('cy', (54 + b.dy * (.4 + .6 * grow) - 10 * fade).toFixed(2));
        b.el.setAttribute('r', (b.r * (.3 + .7 * grow) * (1 + .25 * fade)).toFixed(2));
        b.el.setAttribute('opacity', ((1 - fade) * (u < .06 ? u / .06 : 1)).toFixed(3));
      }
    }

    pointArm(side, ang, ext, t, frozen) {
      const S = side < 0 ? [39, 58] : [81, 58];
      const dx = Math.cos(ang), dy = Math.sin(ang);
      let nx = -dy, ny = dx;
      if (ny > 0) {
        nx = -nx;
        ny = -ny;
      }
      const L = 34 * ext, pts = [];
      for (let i = 0; i <= 4; i++) {
        const u = i / 4, bend = 3.4 * Math.sin(Math.PI * u);
        pts.push([S[0] + dx * L * u + nx * bend, S[1] + dy * L * u + ny * bend]);
      }
      const tip = pts[4];
      pts[4] = [tip[0] + nx * 2.4 - dx * 1.4, tip[1] + ny * 2.4 - dy * 1.4];
      return frozen ? pts : this.wob(pts, t, .45, 2.6, this.ph[4]);
    }

    wob(pts, t, amp, per, ph) {
      const n = pts.length - 1;
      return pts.map((p, i) => {
        if (!i) return p;
        const w = Math.pow(i / n, 1.4);
        return [p[0] + amp * w * Math.sin(TAU * t / per + ph - i * .8), p[1] + amp * .7 * w * Math.cos(TAU * t / (per * 1.13) + ph - i * .7)];
      });
    }

    setArm(name, pts) {
      const a = this.arms[name];
      if (!a) return;
      if (this.from && this.from[name] && this.from[name].length === pts.length) {
        const k = clamp((this.t - this.blendT0) / .34, 0, 1);
        if (k < 1) pts = lerpPose(this.from[name], pts, inout(k));
        else delete this.from[name];
      }
      this.cur[name] = pts;
      const fr = frame(pts, a.w0, a.w1);
      a.el.setAttribute('d', outline(fr));
      if (a.suck.length) suckerPos(fr, a.side).forEach(([x, y, r], i) => {
        const c = a.suck[i];
        c.setAttribute('cx', x.toFixed(2));
        c.setAttribute('cy', y.toFixed(2));
        c.setAttribute('r', r.toFixed(2));
      });
    }
  }

  self.AppTinte = {
    guide: options => new Guide(options),
    motionAllowed
  };
})();
