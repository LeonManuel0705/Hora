const LOADER_FX = '<i class="tinte-sync"><svg viewBox="38.5 63.4 12 12"><path d="M41.7 68.8A2.9 2.9 0 0 1 46.8 67.6M46.8 67.6l.1 -1.6M46.8 67.6l-1.6 .1M47.3 70A2.9 2.9 0 0 1 42.2 71.2M42.2 71.2l-.1 1.6M42.2 71.2l1.6 -.1"/></svg></i>'
  + [51.5, 55.5, 59.5].map((x) => `<i class="tinte-dot"><svg viewBox="${x - 6} 63.4 12 12"><circle cx="${x}" cy="69.4" r="1.1"/></svg></i>`).join("")
  + '<i class="tinte-fill"><svg viewBox="40 72 40 12"><rect x="41" y="76" width="38" height="4.2" rx="2.1"/></svg></i>';

let uid = 0;
const r2 = n => Math.round(n * 100) / 100;
const rnd = (a, b) => a + Math.random() * (b - a);
const TAU = Math.PI * 2;

function eyes(x1, x2, y, s = 1) {
  const rx = 3.9 * s, ry = 4.9 * s;
  const one = x => `<g class="t-eye" data-cx="${x}" data-cy="${y}"><ellipse cx="${x}" cy="${y}" rx="${r2(rx)}" ry="${r2(ry)}"/><circle class="t-white" cx="${r2(x + 1.3 * s)}" cy="${r2(y - 1.8 * s)}" r="${r2(1.55 * s)}"/><circle class="t-white" cx="${r2(x - 1.3 * s)}" cy="${r2(y + 2 * s)}" r="${r2(.75 * s)}"/></g>`;
  const arc = (x, up) => `M${r2(x - 4 * s)} ${r2(y + (up ? 1.4 : .6) * s)}q${r2(4 * s)} ${r2((up ? -5 : 3.8) * s)} ${r2(8 * s)} 0`;
  return `<g class="t-look">${one(x1)}${one(x2)}<path class="t-eye-happy" d="${arc(x1, 1)}"/><path class="t-eye-happy" d="${arc(x2, 1)}"/><path class="t-eye-closed" d="${arc(x1, 0)}"/><path class="t-eye-closed" d="${arc(x2, 0)}"/></g>`;
}
function blush(x1, x2, y, s = 1) {
  return `<ellipse class="t-blush" cx="${x1}" cy="${y}" rx="${r2(4.6 * s)}" ry="${r2(2.7 * s)}"/><ellipse class="t-blush" cx="${x2}" cy="${y}" rx="${r2(4.6 * s)}" ry="${r2(2.7 * s)}"/>`;
}
const SPARK = "M0 -7C.9 -1.6 1.6 -.9 7 0C1.6 .9 .9 1.6 0 7C-.9 1.6 -1.6 .9 -7 0C-1.6 -.9 -.9 -1.6 0 -7Z";
const ITEM = {
  pencil: `<rect class="t-apri" x="-1.7" y="-8" width="3.4" height="11" rx=".9"/><path class="t-cream" d="M-1.7 3h3.4l-1.7 3.2z"/><path class="t-ink-f" d="M-.65 5.1h1.3l-.65 1.1z"/><rect class="t-rose" x="-1.7" y="-9.8" width="3.4" height="2.2" rx=".7"/>`,
  mail: `<rect class="t-env" x="-6.5" y="-4.6" width="13" height="9.2" rx="1.6"/><path class="t-ink-s t-thin" d="M-5.6 -3.6L0 .9 5.6 -3.6"/>`
};

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
    t = Math.min(1, Math.max(0, t));
    return ((ay * t + by) * t + cy) * t;
  };
}
const inout = bezier(.42, 0, .58, 1), ease = bezier(.25, .1, .25, 1), linear = x => x;
const burstOut = bezier(.15, .7, .3, 1), gravity = x => x * x;

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
  let l = "", r = "";
  for (let i = 0; i < fr.length; i++) {
    const q = fr[i];
    l += (i ? "L" : "M") + (q.p[0] + q.n[0] * q.w).toFixed(2) + " " + (q.p[1] + q.n[1] * q.w).toFixed(2);
  }
  for (let i = fr.length - 1; i >= 0; i--) {
    const q = fr[i];
    r += "L" + (q.p[0] - q.n[0] * q.w).toFixed(2) + " " + (q.p[1] - q.n[1] * q.w).toFixed(2);
  }
  return l + r + "Z";
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
    + (side ? suckerPos(fr, side).map(([x, y, r]) => `<circle class="t-sucker" data-s="${name}" cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${r.toFixed(2)}"/>`).join("") : "");
}
const MIR = p => p.map(([x, y]) => [r2(120 - x), y]);
const lerpPose = (a, b, u) => a.map((p, i) => [p[0] + (b[i][0] - p[0]) * u, p[1] + (b[i][1] - p[1]) * u]);
function seg(keys, phase) {
  let k = 0;
  while (k < keys.length - 2 && phase >= keys[k + 1]) k++;
  const span = keys[k + 1] - keys[k] || 1;
  return [k, Math.min(1, Math.max(0, (phase - keys[k]) / span))];
}
function trackPose(keys, poses, phase) { const [k, u] = seg(keys, phase); return lerpPose(poses[k], poses[k + 1], inout(u)); }
function trackNum(keys, vals, phase, fn = ease) { const [k, u] = seg(keys, phase); return vals[k] + (vals[k + 1] - vals[k]) * fn(u); }

const T = {
  g1: [[40, 64], [36, 76], [28, 87], [18, 92], [11, 89], [11, 84], [15, 83.5]],
  g1b: [[40, 64], [36.5, 76], [29, 87.5], [19, 92.5], [12, 90.5], [11.5, 85.5], [15.5, 85]],
  g2: [[50, 68], [48, 81], [43, 93], [35, 99], [29, 98], [29.5, 94.5], [32.5, 94.8]],
  g2b: [[50, 68], [48.5, 81], [44, 93], [36, 99.5], [30, 99], [30, 95.5], [33, 95.8]],
  g1sq: [[40, 64], [35.5, 74], [29, 82], [22, 86], [17.5, 84], [18, 80], [21.5, 80.5]],
  g1up: [[40, 64], [39, 77], [37, 90], [34, 101], [30.5, 105], [28.5, 102], [30.5, 99.5]],
  g1pk: [[40, 64], [32, 71], [22, 76], [13, 75], [8.5, 70], [11, 66], [15, 67.5]],
  g1ld: [[40, 64], [35, 77], [25, 89], [14, 94.5], [7, 92.5], [7.5, 87.5], [11.5, 87.5]],
  g2sq: [[50, 68], [47.5, 78], [43, 86], [37, 90], [32.5, 88.5], [33, 85], [36, 85.5]],
  g2up: [[50, 68], [50, 82], [49, 95], [47, 106], [44, 110], [42, 107.5], [44, 105]],
  g2pk: [[50, 68], [45, 78], [38, 84], [30, 86], [25.5, 83], [27, 79], [30.5, 80]],
  g2ld: [[50, 68], [47.5, 82], [41, 95], [32, 101], [26, 100], [26.5, 96], [29.5, 96.5]],
  g2tap: [[50, 68], [48, 81], [43, 92.5], [35.5, 97], [30, 94], [31, 90], [34, 91]],
  g1n: [[40, 64], [37, 76], [33, 87], [31, 96], [33.5, 101], [37.5, 100], [36.5, 96.5]],
  g1nb: [[40, 64], [36, 76], [31, 86.5], [28.5, 95.5], [30.5, 100.5], [34.5, 100.5], [34, 97]],
  g2n: [[50, 68], [49, 80], [47, 91], [46.5, 100], [49, 104.5], [52.5, 103], [51, 100]],
  g2nb: [[50, 68], [48.5, 80], [46, 91], [45, 100], [47, 104.8], [50.8, 103.8], [49.6, 100.6]],
  hl: [[39, 58], [31, 58.5], [25.5, 54], [23.5, 47.5], [25.5, 43]],
  hrb: [[81, 58], [90, 55], [97, 48], [100, 40], [97.5, 35.5]],
  hrc: [[81, 58], [90, 54.5], [98, 47.5], [102.5, 40.5], [102, 35]],
  hlup: [[39, 58], [31, 51], [27, 41], [26.5, 31], [30, 25]],
  hlwv: [[39, 58], [30, 52], [24.5, 43], [22, 33], [24, 26.5]],
  hlcard: [[44, 66], [38, 66], [34.5, 70], [36, 75], [40, 76.5]],
  hrn: [[81, 58], [88, 62], [91, 68], [89, 73], [85, 73.5]]
};
const P = {
  g3: MIR(T.g2), g3b: MIR(T.g2b), g4: MIR(T.g1), g4b: MIR(T.g1b), hr: MIR(T.hl), g3tap: MIR(T.g2tap),
  g3n: MIR(T.g2n), g3nb: MIR(T.g2nb), g4n: MIR(T.g1n), g4nb: MIR(T.g1nb), hlrest: MIR(T.hrn), hrcard: MIR(T.hlcard)
};
const CHEER = (() => {
  const seq = (a, sq, up, pk, ld) => [a, a, sq, up, pk, ld, a, a];
  const s1 = seq(T.g1, T.g1sq, T.g1up, T.g1pk, T.g1ld), s2 = seq(T.g2, T.g2sq, T.g2up, T.g2pk, T.g2ld);
  const hs = [T.hl, T.hl, T.hlup, T.hlwv, T.hlup, T.hlwv, T.hlup, T.hl, T.hl];
  return { kt: [0, .06, .13, .28, .40, .53, .61, 1], hk: [0, .08, .2, .3, .4, .5, .6, .68, 1], g1: s1, g2: s2, g3: s2.map(MIR), g4: s1.map(MIR), hl: hs, hr: hs.map(MIR) };
})();
const MANTLE = "M32 50C32 29 44 16 60 16C76 16 88 29 88 50C88 62 77 71 60 71C43 71 32 62 32 50Z";

function confetti() {
  const cols = ["lav-s", "mint", "rose", "apri", "mint-s", "lav-h"];
  let out = "";
  for (let i = 0; i < 22; i++) {
    const c = cols[i % cols.length];
    const data = `data-cx="${r2(rnd(-50, 50))}" data-cy="${r2(rnd(-34, -6))}" data-fall="${r2(rnd(18, 30))}" data-cr="${Math.round(rnd(-360, 360))}" data-d="${r2(rnd(0, .08))}"`;
    out += i % 3 === 0
      ? `<circle class="t-confetti t-${c}" ${data} cx="0" cy="0" r="1.9" opacity="0"/>`
      : `<rect class="t-confetti t-${c}" ${data} x="-2.1" y="-1.2" width="4.2" height="2.4" rx=".6" opacity="0"/>`;
  }
  return `<g>${out}</g>`;
}

function tinteFace(st) {
  const brows = st === "think"
    ? `<path class="t-brow" d="M45.4 39.4q5 -1.2 9.8 1.2"/><path class="t-brow" d="M64.8 40.6q5 -2.4 9.8 -1.2"/>`
    : `<path class="t-brow" d="M44.6 38.2q5.2 -3.4 10.4 -1"/><path class="t-brow" d="M65 37.2q5.2 -2.4 10.4 1"/>`;
  const mouth = st === "think"
    ? `<path class="t-mouth" d="M55 57.4q5 2.2 10 0"/><ellipse class="t-rose" cx="63.4" cy="59" rx="1.7" ry="1.3"/>`
    : `<path class="t-mouth" d="M53.6 56.6q6.4 5.6 12.8 0"/><path class="t-mouth-open" d="M53.4 56.2q6.6 10 13.2 0z"/>`;
  return `<g class="t-brows">${brows}</g>` + eyes(50, 70, 47, 1.05) + blush(42.5, 77.5, 55.5, 1) + mouth;
}

const SLEEP_FX = ["M3.2 5.6h5.2L3.2 10.6h5.2", "M3.2 5.6h5.2L3.2 10.6h5.2", "M2.4 2.8h7.2L2.4 10.6h7.2"].map((d) => `<i class="tinte-z"><svg viewBox="0 0 12 12"><path d="${d}"/></svg></i>`).join("");
const SEATED = { g1: T.g1, g2: T.g2, g3: P.g3, g4: P.g4, hl: T.hl, hr: P.hr };
const STATES = { ruhe: "idle", geschafft: "cheer", laedt: "think", schlaeft: "sleep" };

function drawTinte(id, st) {
  const night = st === "sleep";
  const seated = armSvg("g1", T.g1, 9, 2, 1) + armSvg("g2", T.g2, 9.5, 2, 1) + armSvg("g3", P.g3, 9.5, 2, -1) + armSvg("g4", P.g4, 9, 2, -1);
  const hands = armSvg("hl", T.hl, 7.5, 2.4, 0) + armSvg("hr", P.hr, 7.5, 2.4, 0);
  let arms = seated + hands, front = "", cap = "", after = "";
  if (st === "idle") front = `<g data-pencil style="transform:translate(25.5px,42.5px) rotate(-20deg)">${ITEM.pencil}</g>`;
  if (st === "cheer") {
    after = confetti() + [[10, 40, "l", 0], [110, 34, "t", .08], [112, 84, "l", .16], [8, 86, "t", .12]]
      .map(([x, y, c, d]) => `<g transform="translate(${x} ${y})"><path class="t-spark t-${c}" data-spark="${d}" d="${SPARK}"/></g>`).join("");
  }
  if (st === "think") {
    arms = seated;
    front = `<rect class="t-card" x="36" y="61" width="48" height="24" rx="5"/>`
      + `<g transform="translate(73 69.4) scale(.62)">${ITEM.mail}</g>`
      + `<rect class="t-track" x="41" y="76" width="38" height="4.2" rx="2.1"/>`
      + armSvg("hlc", T.hlcard, 7, 2.2, 0) + armSvg("hrc", P.hrcard, 7, 2.2, 0);
  }
  if (night) {
    arms = armSvg("g1", T.g1n, 9, 2, 1) + armSvg("g2", T.g2n, 9.5, 2, 1) + armSvg("g3", P.g3n, 9.5, 2, -1) + armSvg("g4", P.g4n, 9, 2, -1)
      + armSvg("hl", P.hlrest, 7.5, 2.4, 0) + armSvg("hr", T.hrn, 7.5, 2.4, 0);
    cap = `<path class="t-cap" d="M38 31C39.5 17 51 8 64.5 8.6C78 9.2 88 17.5 94.5 31.5C90.5 28.8 86.5 27.3 82.5 27.6C82 29 81.6 30 81.4 31Z"/>`
      + `<path class="t-band" d="M36.5 32C43 26.6 77 26.6 83.5 32C84.6 33.2 83.6 35.2 82 34.6C74.5 31.2 45.5 31.2 38 34.6C36.4 35.2 35.4 33.2 36.5 32Z"/>`
      + `<circle class="t-pom" cx="96" cy="33.5" r="4.3"/>`;
  }
  return `<defs><clipPath id="tinte-mt${id}"><path d="${MANTLE}"/></clipPath></defs>`
    + (night ? "" : `<ellipse class="t-shadow" cx="60" cy="103.5" rx="46" ry="4.2"/>`)
    + `<g class="t-pokewrap"><g class="t-body">${arms}`
    + `<g class="t-mantle"><path class="t-lav" d="${MANTLE}"/>`
    + `<g clip-path="url(#tinte-mt${id})"><ellipse class="t-lav-s" cx="60" cy="71" rx="32" ry="10" opacity=".55"/></g>`
    + `<ellipse class="t-lav-h" cx="46" cy="29" rx="8.5" ry="4.5" transform="rotate(-30 46 29)" opacity=".85"/>`
    + `<circle class="t-mint" cx="72" cy="27" r="2.4"/><circle class="t-mint" cx="78" cy="36" r="1.6"/><circle class="t-mint" cx="43" cy="42" r="1.3"/>`
    + cap + tinteFace(st) + `</g>${front}</g></g>${after}`;
}

const px = (n) => `${n.toFixed(2)}px`;
let lastPointer = 0;

class Rig {
  constructor(svg) {
    this.svg = svg;
    this.st = svg.dataset.st;
    this.t = this.st === "cheer" ? 0 : rnd(0, 30);
    this.visible = false;
    this.arms = {};
    for (const el of svg.querySelectorAll("[data-arm]")) {
      const name = el.dataset.arm;
      this.arms[name] = { el, w0: +el.dataset.w0, w1: +el.dataset.w1, side: +el.dataset.side, suck: [...svg.querySelectorAll(`[data-s="${name}"]`)] };
    }
    this.body = svg.querySelector(".t-body");
    this.shadow = svg.querySelector(".t-shadow");
    this.mantle = svg.querySelector(".t-mantle");
    this.brows = svg.querySelector(".t-brows");
    this.look = svg.querySelector(".t-look");
    this.pencil = svg.querySelector("[data-pencil]");
    this.eyes = [...svg.querySelectorAll(".t-eye")].map(el => ({ el, cx: +el.dataset.cx, cy: +el.dataset.cy }));
    this.normal = [...svg.querySelectorAll(".t-eye, .t-mouth")];
    this.happy = [...svg.querySelectorAll(".t-eye-happy, .t-mouth-open")];
    this.conf = [...svg.querySelectorAll(".t-confetti")].map(el => ({ el, cx: +el.dataset.cx, cy: +el.dataset.cy, fall: +el.dataset.fall, cr: +el.dataset.cr, d: +el.dataset.d }));
    this.sparks = [...svg.querySelectorAll("[data-spark]")].map(el => ({ el, d: +el.dataset.spark }));
    this.ph = Array.from({ length: 10 }, () => rnd(0, TAU));
    this.next = { blink: rnd(.8, 3), twirl: rnd(1.5, 4), wave: rnd(2.5, 6), glance: rnd(.5, 2) };
    this.ev = { blink: -1, twirl: -1, wave: -1 };
    this.lastBlink = 1;
    this.mode = this.st;
    this.still = false;
    this.visible = false;
  }
  hold(on) {
    if (this.still === on) return;
    this.still = on;
    this.svg.parentElement.classList.toggle("is-still", on);
  }
  step(dt) {
    this.t += dt;
    if (this.mode === "cheer" && this.t >= 3.6) {
      this.mode = "idle";
      this.settle = this.t;
    }
    if (this.mode === "idle") this.idle(this.t);
    else if (this.mode === "cheer") this.cheer(this.t);
    else if (this.mode === "think") this.think(this.t);
    else this.sleep(this.t);
  }
  setArm(name, pts) {
    const a = this.arms[name];
    if (!a) return;
    if (this.settle !== undefined && SEATED[name]) pts = lerpPose(SEATED[name], pts, this.settleK);
    const fr = frame(pts, a.w0, a.w1);
    a.el.setAttribute("d", outline(fr));
    if (a.suck.length) suckerPos(fr, a.side).forEach(([x, y, r], i) => {
      const c = a.suck[i];
      c.setAttribute("cx", x.toFixed(2));
      c.setAttribute("cy", y.toFixed(2));
      c.setAttribute("r", r.toFixed(2));
    });
  }
  wob(pts, t, amp, per, ph) {
    const n = pts.length - 1;
    return pts.map((p, i) => {
      if (!i) return p;
      const w = Math.pow(i / n, 1.4);
      return [p[0] + amp * w * Math.sin(TAU * t / per + ph - i * .8), p[1] + amp * .7 * w * Math.cos(TAU * t / (per * 1.13) + ph - i * .7)];
    });
  }
  blink(t) {
    if (this.ev.blink < 0 && t > this.next.blink) { this.ev.blink = t; this.dbl = Math.random() < .2; }
    let s = 1;
    if (this.ev.blink >= 0) {
      const u = (t - this.ev.blink) / .15, end = this.dbl ? 2.4 : 1;
      if (u >= end) { this.ev.blink = -1; this.next.blink = t + rnd(2.2, 6); }
      else { const v = u >= 1.4 ? u - 1.4 : u; if (v < 1) s = 1 - .9 * Math.sin(Math.PI * v); }
    }
    if (s !== this.lastBlink) {
      this.lastBlink = s;
      for (const e of this.eyes) e.el.style.transform = `translate(${e.cx}px,${e.cy}px) scale(1,${s.toFixed(3)}) translate(${-e.cx}px,${-e.cy}px)`;
    }
  }
  react() {
    if (this.t - (this.lastReact ?? -9) < .6) return;
    this.lastReact = this.t;
    this.joy = this.t;
    if (this.ev.wave >= 0) this.ev.wave = Math.min(this.ev.wave, this.t - .4);
    else this.ev.wave = this.t;
    if (this.ev.twirl < 0) this.next.twirl = Math.min(this.next.twirl, this.t + .45);
  }
  joyful(t) {
    const u = this.joy === undefined ? 9 : t - this.joy;
    const v = u < .12 ? u / .12 : u > 1.05 ? Math.max(0, 1 - (u - 1.05) / .15) : 1;
    if (v === this.lastJoy) return v;
    this.lastJoy = v;
    for (const el of this.normal) el.style.opacity = v ? (1 - v).toFixed(3) : "";
    for (const el of this.happy) el.style.opacity = v ? v.toFixed(3) : "";
    return v;
  }
  wander(t) {
    if (performance.now() - lastPointer < 1800 || t < this.next.glance) return;
    this.look.style.transform = `translate(${rnd(-2.2, 2.2).toFixed(2)}px,${rnd(-1.6, 1.2).toFixed(2)}px)`;
    this.next.glance = t + rnd(1.2, 3.6);
  }
  mantleTo(rot, br) {
    this.mantle.style.transform = `translate(60px,71px) rotate(${rot.toFixed(2)}deg) scale(${(1 - br * .6).toFixed(4)},${(1 + br).toFixed(4)}) translate(-60px,-71px)`;
  }
  idle(t) {
    const k = this.settle === undefined ? 1 : inout(Math.min(1, (t - this.settle) / .6));
    this.settleK = k;
    const ph = this.ph, curl = (a, b, per, p) => lerpPose(a, b, .5 + .5 * Math.sin(TAU * t / per + p));
    this.setArm("g1", this.wob(curl(T.g1, T.g1b, 6.1, ph[0]), t, 1.6, 3.4, ph[1]));
    this.setArm("g2", this.wob(curl(T.g2, T.g2b, 5.3, ph[2]), t, 1.5, 3.9, ph[3]));
    this.setArm("g3", this.wob(curl(P.g3, P.g3b, 5.7, ph[4]), t, 1.5, 3.6, ph[5]));
    this.setArm("g4", this.wob(curl(P.g4, P.g4b, 6.6, ph[6]), t, 1.6, 4.3, ph[7]));
    const hl = this.wob(T.hl, t, 1.4, 3.1, ph[8]);
    this.setArm("hl", hl);
    if (this.ev.twirl < 0 && t > this.next.twirl) this.ev.twirl = t;
    let spin = 0;
    if (this.ev.twirl >= 0) {
      const u = t - this.ev.twirl;
      if (u >= 1) { this.ev.twirl = -1; this.next.twirl = t + rnd(4, 9); }
      else spin = 720 * inout(u);
    }
    const tip = hl[hl.length - 1], ang = -20 + 16 * Math.sin(TAU * t / 2.3 + ph[2]) + spin;
    if (this.pencil) this.pencil.style.transform = `translate(${px(tip[0])},${px(tip[1] - .5)}) rotate(${ang.toFixed(1)}deg)`;
    if (this.ev.wave < 0 && t > this.next.wave) this.ev.wave = t;
    let e = 0, wave = null;
    if (this.ev.wave >= 0) {
      const u = t - this.ev.wave, D = 2.4;
      if (u >= D) { this.ev.wave = -1; this.next.wave = t + rnd(5, 11); }
      else {
        e = u < .4 ? inout(u / .4) : u > D - .5 ? inout((D - u) / .5) : 1;
        wave = lerpPose(T.hrb, T.hrc, .5 + .5 * Math.sin(TAU * (u - .4) / .56));
      }
    }
    const hr = this.wob(P.hr, t, 1.4, 3.5, ph[9]);
    this.setArm("hr", wave ? lerpPose(hr, wave, e) : hr);
    const joy = this.joyful(t);
    this.brows.style.transform = `translate(0px,${px(k * (-1.7 * Math.max(e, joy * 1.3) - .5 * Math.max(0, Math.sin(TAU * t / 7.3 + ph[3]))))})`;
    this.mantleTo(k * 2.4 * Math.sin(TAU * t / 5.7 + ph[0]), k * .014 * Math.sin(TAU * t / 3.2 + ph[5]));
    this.blink(t);
    this.wander(t);
    if (k === 1) this.settle = undefined;
  }
  cheer(t) {
    const ph = (t % 3.6) / 3.6, C = CHEER;
    for (const k of ["g1", "g2", "g3", "g4"]) this.setArm(k, trackPose(C.kt, C[k], ph));
    this.setArm("hl", trackPose(C.hk, C.hl, ph));
    this.setArm("hr", trackPose(C.hk, C.hr, ph));
    const J = [0, .06, .13, .28, .40, .53, .61, .68, 1];
    const ty = trackNum(J, [0, 0, 2, -22, -26, 0, 0, 0, 0], ph);
    const sx = trackNum(J, [1, 1, 1.06, .96, 1, 1.08, .98, 1, 1], ph), sy = trackNum(J, [1, 1, .93, 1.05, 1, .92, 1.02, 1, 1], ph);
    this.body.style.transform = `translate(0px,${px(ty)}) translate(60px,101px) scale(${sx.toFixed(4)},${sy.toFixed(4)}) translate(-60px,-101px)`;
    const S = [0, .06, .28, .40, .53, 1];
    const ss = trackNum(S, [1, 1, .62, .62, 1, 1], ph);
    this.shadow.style.transform = `translate(60px,103.5px) scale(${ss.toFixed(3)}) translate(-60px,-103.5px)`;
    this.shadow.style.opacity = trackNum(S, [1, 1, .55, .55, 1, 1], ph).toFixed(3);
    const hv = trackNum([0, .09, .13, .60, .66, 1], [0, 0, 1, 1, 0, 0], ph, linear);
    for (const el of this.normal) el.style.opacity = (1 - hv).toFixed(3);
    for (const el of this.happy) el.style.opacity = hv.toFixed(3);
    this.brows.style.transform = `translate(0px,${px(trackNum([0, .09, .14, .60, .66, 1], [0, 0, -2.6, -2.6, 0, 0], ph))})`;
    for (const c of this.conf) {
      const q = ((ph - c.d / 3.6) % 1 + 1) % 1;
      const b = trackNum([0, .24, .35, 1], [0, 0, 1, 1], q, burstOut), g = trackNum([0, .35, .6, 1], [0, 0, 1, 1], q, gravity);
      const sc = trackNum([0, .24, .3, 1], [.4, .4, 1, 1], q), r = trackNum([0, .24, .6, 1], [0, 0, c.cr, c.cr], q, linear);
      c.el.style.transform = `translate(${px(60 + c.cx * (b + .15 * g))},${px(24 + c.cy * b + c.fall * g)}) rotate(${r.toFixed(1)}deg) scale(${sc.toFixed(3)})`;
      c.el.style.opacity = trackNum([0, .24, .27, .5, .6, 1], [0, 0, 1, 1, 0, 0], q, linear).toFixed(3);
    }
    for (const s of this.sparks) {
      const q = ((ph - s.d / 3.6) % 1 + 1) % 1;
      const sc = trackNum([0, .24, .34, .52, 1], [0, 0, 1.15, 0, 0], q), r = trackNum([0, .24, .34, .52, 1], [0, 0, 45, 90, 90], q);
      s.el.style.transform = `rotate(${r.toFixed(1)}deg) scale(${sc.toFixed(3)})`;
    }
  }
  think(t) {
    this.setArm("g2", trackPose([0, .5, 1], [T.g2, T.g2tap, T.g2], (t % .7) / .7));
    this.setArm("g3", trackPose([0, .5, 1], [P.g3, P.g3tap, P.g3], ((t + .35) % .7) / .7));
    this.blink(t);
  }
  sleep(t) {
    const ph = this.ph, sway = (a, b, per, p) => lerpPose(a, b, .5 + .5 * Math.sin(TAU * t / per + p));
    this.setArm("g1", this.wob(sway(T.g1n, T.g1nb, 4.4, 0), t, .7, 5.1, ph[1]));
    this.setArm("g2", this.wob(sway(T.g2n, T.g2nb, 4.4, 1.6), t, .7, 5.6, ph[2]));
    this.setArm("g3", this.wob(sway(P.g3n, P.g3nb, 4.4, 3.1), t, .7, 5.3, ph[3]));
    this.setArm("g4", this.wob(sway(P.g4n, P.g4nb, 4.4, 4.7), t, .7, 5.9, ph[4]));
    this.setArm("hl", this.wob(P.hlrest, t, .5, 4.8, ph[5]));
    this.setArm("hr", this.wob(T.hrn, t, .5, 5.2, ph[6]));
    this.mantleTo(1.4 * Math.sin(TAU * t / 6.3 + ph[0]), .02 * Math.sin(TAU * t / 4.4 + 1.2));
  }
}

const STEP = 1 / 30;
const SETTLE_AFTER = 25000;
const rigs = new Set();
let booted = false, running = false, lastFrame = 0, acc = 0, lastInput = performance.now();
let pointerX = -1, pointerY = -1, eyesQueued = false, observer = null;

const weakDevice = () => new URLSearchParams(location.search).has("lite")
  || !!navigator.connection?.saveData
  || (navigator.hardwareConcurrency || 8) <= 2
  || (navigator.deviceMemory || 8) <= 2;
const motionAllowed = () => !matchMedia("(prefers-reduced-motion: reduce)").matches
  && document.documentElement.dataset.motion !== "minimal"
  && !weakDevice();
const awake = () => document.visibilityState === "visible" && document.hasFocus();
const wants = (rig) => rig.visible && (rig.mode === "think" || rig.mode === "cheer" || performance.now() - lastInput < SETTLE_AFTER);

function holdAll() {
  for (const rig of rigs) rig.hold(true);
}

function drop(rig) {
  rigs.delete(rig);
  observer.unobserve(rig.svg);
}

function wake() {
  if (running || !awake()) return;
  for (const rig of rigs) {
    if (!wants(rig)) continue;
    running = true;
    lastFrame = performance.now();
    acc = 0;
    requestAnimationFrame(loop);
    return;
  }
}

function loop(now) {
  if (!awake()) {
    running = false;
    holdAll();
    return;
  }
  acc += Math.min(.1, Math.max(0, (now - lastFrame) / 1000));
  lastFrame = now;
  const tick = acc >= STEP - .004;
  const dt = Math.min(.1, acc);
  if (tick) acc = 0;
  let active = false;
  for (const rig of rigs) {
    if (!rig.svg.isConnected) {
      drop(rig);
      continue;
    }
    const on = wants(rig);
    rig.hold(!on);
    if (!on) continue;
    active = true;
    if (tick) rig.step(dt);
  }
  if (active) requestAnimationFrame(loop);
  else running = false;
}

function trackEyes() {
  eyesQueued = false;
  for (const rig of rigs) {
    if (!rig.visible || rig.still || (rig.mode !== "idle" && rig.mode !== "cheer")) continue;
    const box = rig.svg.getBoundingClientRect();
    const dx = pointerX - (box.left + box.width / 2), dy = pointerY - (box.top + box.height * .45);
    const d = Math.hypot(dx, dy) || 1, k = Math.min(1, d / 240);
    rig.look.style.transform = `translate(${(dx / d * k * 2.2).toFixed(2)}px,${(dy / d * k * 1.8).toFixed(2)}px)`;
  }
}

function activate(root) {
  const list = root.matches("svg.tinte-art") ? [root] : root.querySelectorAll("svg.tinte-art");
  for (const svg of list) {
    if (svg._tinte !== undefined) continue;
    if (svg.dataset.still !== undefined || !motionAllowed()) {
      svg._tinte = null;
      svg.parentElement.classList.add("is-static");
      continue;
    }
    const rig = new Rig(svg);
    svg._tinte = rig;
    rigs.add(rig);
    observer.observe(svg);
  }
}

function poke(svg) {
  const rig = svg._tinte;
  if (!rig) return;
  const wrap = svg.querySelector(".t-pokewrap");
  wrap.classList.remove("t-poke");
  wrap.getBoundingClientRect();
  wrap.classList.add("t-poke");
  rig.react();
}

function boot() {
  if (booted) return;
  booted = true;
  observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      const rig = entry.target._tinte;
      if (!rig) continue;
      rig.visible = entry.isIntersecting;
      if (!rig.visible) rig.hold(true);
    }
    wake();
  }, { rootMargin: "60px" });
  new MutationObserver((records) => {
    for (const record of records) for (const node of record.addedNodes) if (node.nodeType === 1) activate(node);
    for (const rig of rigs) if (!rig.svg.isConnected) drop(rig);
  }).observe(document.documentElement, { childList: true, subtree: true });
  queueMicrotask(() => activate(document.documentElement));
  const input = () => {
    lastInput = performance.now();
    wake();
  };
  addEventListener("pointermove", (event) => {
    pointerX = event.clientX;
    pointerY = event.clientY;
    lastPointer = performance.now();
    input();
    if (rigs.size && !eyesQueued) {
      eyesQueued = true;
      requestAnimationFrame(trackEyes);
    }
  }, { passive: true });
  for (const type of ["pointerdown", "keydown", "wheel", "touchstart", "scroll"]) addEventListener(type, input, { passive: true, capture: true });
  document.addEventListener("visibilitychange", () => (awake() ? wake() : holdAll()));
  addEventListener("focus", wake);
  addEventListener("blur", holdAll);
  document.addEventListener("click", (event) => {
    const svg = event.target.closest?.("svg.tinte-art[data-st=idle]");
    if (svg) poke(svg);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    const svg = event.target.closest?.("svg.tinte-art[data-st=idle]");
    if (!svg) return;
    event.preventDefault();
    poke(svg);
  });
  document.addEventListener("animationend", (event) => {
    if (event.target.classList?.contains("t-poke")) event.target.classList.remove("t-poke");
  });
}

export function tinte(kind, size = 150, label = "Tinte antippen, dann winkt er", { still = false } = {}) {
  boot();
  const st = STATES[kind] || "idle";
  const pokeable = st === "idle" && !still;
  const button = pokeable ? ` role="button" tabindex="0" aria-label="${label}"` : ' aria-hidden="true" focusable="false"';
  return `<span class="tinte is-${kind}${still ? " is-static" : ""}"${pokeable ? "" : ' aria-hidden="true"'}><svg class="tinte-art" data-st="${st}"${still ? " data-still" : ""} viewBox="0 0 120 120" width="${size}" height="${size}"${button}>${drawTinte(++uid, st)}</svg>${st === "think" ? LOADER_FX : st === "sleep" ? SLEEP_FX : ""}</span>`;
}

