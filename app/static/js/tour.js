// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

(function () {
  'use strict';

  const KEY = 'app-tour';
  const brand = () => self.BRAND_NAME || '';
  const q = s => document.querySelector(s);
  const narrow = () => matchMedia('(max-width: 768px)').matches;
  const still = () => !(self.AppTinte && self.AppTinte.motionAllowed());
  const navItem = s => q(`.sidebar-nav .nav-item[data-section="${s}"]`);
  const shown = el => {
    if (!el) return false;
    const r = el.getBoundingClientRect();
    return r.width > 2 && r.height > 2;
  };
  const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const MORE = ['pomodoro', 'vbb', 'training', 'bookmarks', 'review', 'assistant'];

  function navList() {
    return narrow() ? q('.sidebar') : q('.sidebar-nav');
  }

  function newestTask() {
    const title = run && run.title;
    if (!title) return null;
    const items = [...document.querySelectorAll('#taskList .task-item-full')]
      .filter(el => el.querySelector('.task-title')?.textContent.trim() === title);
    items.sort((a, b) => (Number(b.dataset.id) || 0) - (Number(a.dataset.id) || 0));
    return items[0] || null;
  }

  const STEPS = [
    {
      id: 'hello', mode: 'hello',
      text: () => `Hi, ich bin Tinte! Ich zeige dir in einer Minute, wo in ${brand()} was ist. Unterwegs legen wir zusammen deine erste Aufgabe an.`,
      primary: 'Los geht’s', secondary: 'Später', onSecondary: 'skip'
    },
    {
      id: 'nav', dot: true, mode: 'point', target: navList, back: null,
      text: () => narrow()
        ? `Unten findest du alle Bereiche von ${brand()}. Ein Tipp, und du bist da.`
        : `Links findest du alle Bereiche von ${brand()}. Ein Klick, und du bist da.`
    },
    {
      id: 'home', dot: true, mode: 'point', target: () => navItem('dashboard'),
      text: 'Im Dashboard siehst du deinen Tag auf einen Blick: nächster Termin, heutige Aufgaben, Fristen und das Wetter.'
    },
    {
      id: 'tasks', dot: true, mode: 'point', target: () => navItem('tasks'),
      text: 'Unter Aufgaben sammelst du alles, was ansteht. Komm, wir legen gleich deine erste an!',
      primary: 'Zeig’s mir', secondary: 'Überspringen', onSecondary: 'calendar'
    },
    {
      id: 'task-new', page: '/hub/tasks', mode: 'point', target: () => q('.page-actions .btn-primary'),
      text: 'Tipp auf „Neue Aufgabe“.', wait: 'modal', secondary: 'Überspringen', onSecondary: 'calendar'
    },
    {
      id: 'task-form', page: '/hub/tasks', mode: 'watch', target: () => q('#addTaskModal .modal-content'), dim: false,
      text: 'Schreib rein, was du erledigen willst, zum Beispiel „Vokabeln lernen“, und tipp auf „Speichern“.',
      short: 'Titel eintippen, dann auf „Speichern“.',
      wait: 'created', secondary: 'Überspringen', onSecondary: 'calendar'
    },
    {
      id: 'task-done', page: '/hub/tasks', mode: 'cheer', target: newestTask,
      text: 'Geschafft, deine erste Aufgabe steht! Ist sie erledigt, hakst du sie mit einem Klick ab.',
      back: null
    },
    {
      id: 'calendar', dot: true, mode: 'point', target: () => navItem('calendar'), back: 'tasks',
      text: 'Im Kalender stehen deine Termine, Ferien und Feiertage. Google- und CalDAV-Kalender kannst du verbinden.'
    },
    {
      id: 'school', dot: true, mode: 'point', target: () => navItem('school'),
      text: 'Unter Schule liegen Stundenplan, Fächer, Hausaufgaben, Klausuren und Noten.'
    },
    {
      id: 'email', dot: true, mode: 'point', target: () => navItem('email'),
      text: 'Hier liest du deine E-Mails, sobald du dein Postfach verbunden hast.'
    },
    {
      id: 'more', dot: true, mode: 'present', target: navList, rings: () => MORE.map(navItem),
      text: 'Dazu gibt es Pomodoro, Fahrplan, Training, Lesezeichen, Review und den Assistenten. Stöber einfach mal rein.'
    },
    {
      id: 'settings', dot: true, mode: 'point', target: () => navItem('settings'),
      text: () => `In den Einstellungen passt du ${brand()} an dich an. Dort kannst du mich auch jederzeit wieder rufen.`
    },
    {
      id: 'bye', mode: 'present',
      text: () => `Das war’s schon! Viel Spaß mit ${brand()}.`,
      primary: 'Fertig', onPrimary: 'done'
    }
  ];
  const DOTS = STEPS.filter(s => s.dot).map(s => s.id);
  const DOT_OF = { 'task-new': 'tasks', 'task-form': 'tasks', 'task-done': 'tasks' };
  const indexOf = id => STEPS.findIndex(s => s.id === id);

  let run = null;

  function save(id) {
    try {
      localStorage.setItem(KEY, JSON.stringify({ id, at: Date.now(), title: run && run.title }));
    } catch (_) {}
  }

  function load() {
    try {
      const data = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (data && indexOf(data.id) >= 0 && Date.now() - data.at < 30 * 60 * 1000) return data;
    } catch (_) {}
    return null;
  }

  function forget() {
    try {
      localStorage.removeItem(KEY);
    } catch (_) {}
  }

  function persist(state) {
    return fetch('/api/hub/tour', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ state })
    }).catch(() => {});
  }

  function make(tag, cls, parent) {
    const el = document.createElement(tag);
    el.className = cls;
    (parent || document.body).appendChild(el);
    return el;
  }

  function buildUi() {
    const scrim = make('div', 'tour-scrim');
    const spot = make('div', 'tour-spot');
    const rings = make('div', 'tour-rings');
    const bubble = make('div', 'tour-bubble');
    bubble.setAttribute('role', 'dialog');
    bubble.setAttribute('aria-modal', 'false');
    bubble.setAttribute('aria-labelledby', 'tourText');
    bubble.tabIndex = -1;
    bubble.innerHTML = '<button type="button" class="tour-close" data-act="close" aria-label="Tutorial beenden"><svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button>'
      + '<p class="tour-text" id="tourText"><span class="tour-sr"></span><span class="tour-type" aria-hidden="true"><span class="tour-typed"></span><span class="tour-rest"></span></span></p>'
      + '<div class="tour-foot"><div class="tour-dots" aria-hidden="true">' + DOTS.map(() => '<i></i>').join('') + '</div>'
      + '<div class="tour-actions"><button type="button" class="tour-btn tour-btn-ghost" data-act="secondary"></button><button type="button" class="tour-btn tour-btn-primary" data-act="primary"></button></div></div>';
    const measure = bubble.cloneNode(true);
    measure.className = 'tour-bubble tour-measure';
    measure.removeAttribute('role');
    measure.removeAttribute('aria-labelledby');
    measure.setAttribute('aria-hidden', 'true');
    measure.querySelector('.tour-text').removeAttribute('id');
    document.body.appendChild(measure);
    const size = narrow() ? 96 : 124;
    const guide = self.AppTinte.guide({ size });
    return { scrim, spot, rings, bubble, measure, guide, size };
  }

  function start(fromId, resumed) {
    if (run) return;
    if (!self.AppTinte) return;
    run = { ui: buildUi(), step: null, token: 0, offs: [], title: resumed && resumed.title };
    const { scrim, bubble } = run.ui;
    bubble.addEventListener('click', onBubbleClick);
    scrim.addEventListener('click', () => {
      run.ui.guide.excite();
      bubble.classList.remove('is-nudged');
      void bubble.offsetWidth;
      bubble.classList.add('is-nudged');
    });
    on(document, 'keydown', onKey, true);
    on(window, 'resize', relayout);
    on(window, 'scroll', relayout, true);
    on(document, 'submit', e => {
      if (e.target && e.target.id === 'addTaskForm') {
        const title = q('#taskTitle');
        run.title = title ? title.value.trim() : '';
      }
    }, true);
    document.documentElement.classList.add('tour-on');
    run.tracker = setInterval(track, 250);
    if (resumed) setTimeout(() => go(fromId, { first: true }), 450);
    else go(fromId || 'hello', { first: true });
  }

  function on(target, type, fn, opts) {
    target.addEventListener(type, fn, opts);
    run.offs.push(() => target.removeEventListener(type, fn, opts));
  }

  function clearWaits() {
    if (!run) return;
    for (const off of run.stepOffs || []) off();
    run.stepOffs = [];
  }

  function onStep(target, type, fn, opts) {
    target.addEventListener(type, fn, opts);
    run.stepOffs.push(() => target.removeEventListener(type, fn, opts));
  }

  function observe(el, fn) {
    if (!el) return;
    const mo = new MutationObserver(fn);
    mo.observe(el, { attributes: true, attributeFilter: ['class'] });
    run.stepOffs.push(() => mo.disconnect());
  }

  async function go(id, options) {
    if (!run) return;
    const opts = options || {};
    const step = STEPS[indexOf(id)];
    if (!step) return;
    const token = ++run.token;
    clearWaits();
    save(step.id);
    if (step.page && location.pathname !== step.page) {
      hideBubble();
      run.ui.guide.excite();
      await wait(still() ? 0 : 260);
      location.href = step.page;
      return;
    }
    run.step = step;
    hideBubble();
    clearRings();
    let target = step.target ? step.target() : null;
    if (step.id === 'task-done' && !shown(target)) {
      for (let i = 0; i < 12 && !shown(target); i++) {
        await wait(120);
        target = step.target();
      }
      if (token !== run.token) return;
    }
    if (!shown(target)) target = null;
    if (target && clipped(target)) {
      target.scrollIntoView({ block: target.closest('.sidebar') ? 'nearest' : 'center', behavior: still() ? 'auto' : 'smooth' });
      await wait(still() ? 0 : 380);
      if (token !== run.token) return;
    }
    run.target = target;
    run.rect = target ? rectOf(target) : null;
    fillBubble(step, run.ui.measure);
    const spots = place(step, target);
    setSpot(step, target);
    const { guide } = run.ui;
    guide.setMode('float');
    if (opts.first) {
      guide.place(spots.gx, spots.gy);
      await guide.appear();
    } else {
      await guide.moveTo(spots.gx, spots.gy);
    }
    if (token !== run.token) return;
    const aim = target ? aimAt(target, spots) : null;
    if (step.mode === 'point' && aim) guide.setMode('point', aim);
    else if (step.mode === 'watch') guide.setMode('watch', aim || {});
    else if (step.mode === 'cheer') guide.setMode('cheer');
    else if (step.mode === 'present') guide.setMode('present');
    else if (step.mode === 'hello') guide.setMode('hello');
    if (step.rings) showRings(step.rings());
    showBubble(step, spots);
    arm(step);
  }

  function clipped(el) {
    const r = el.getBoundingClientRect();
    if (r.top < 8 || r.bottom > innerHeight - 8 || r.left < 0 || r.right > innerWidth) return true;
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const cs = getComputedStyle(p);
      if (!/(auto|scroll|hidden)/.test(cs.overflowY + ' ' + cs.overflowX)) continue;
      const pr = p.getBoundingClientRect();
      if (r.top < pr.top - 1 || r.bottom > pr.bottom + 1 || r.left < pr.left - 1 || r.right > pr.right + 1) return true;
    }
    return false;
  }

  function rectOf(el) {
    const r = el.getBoundingClientRect();
    return [r.left, r.top, r.width, r.height];
  }

  function track() {
    if (!run || !run.step || !run.target || run.ending) return;
    if (!run.target.isConnected) return;
    const now = rectOf(run.target), before = run.rect;
    if (before && now.every((v, i) => Math.abs(v - before[i]) < 1.5)) return;
    run.rect = now;
    if (before) relayout(true);
  }

  function aimAt(target, spots) {
    const r = target.getBoundingClientRect(), s = run.ui.size;
    const cx = spots.gx + s / 2, cy = spots.gy + s * .44;
    return { x: clamp(cx, r.left + 6, r.right - 6), y: clamp(cy, r.top + 6, r.bottom - 6) };
  }

  function arm(step) {
    run.stepOffs = run.stepOffs || [];
    if (step.wait === 'modal') {
      const modal = q('#addTaskModal');
      const check = () => {
        if (modal && modal.classList.contains('active')) go('task-form');
      };
      observe(modal, check);
      check();
    }
    if (step.wait === 'created') {
      const modal = q('#addTaskModal'), input = q('#taskTitle');
      let created = false;
      onStep(document, 'app:task-created', () => {
        created = true;
        go('task-done');
      });
      observe(modal, () => {
        if (modal.classList.contains('active')) return;
        setTimeout(() => {
          if (!created && run && run.step && run.step.id === 'task-form') go('task-new');
        }, 320);
      });
      if (input) {
        let last = 0;
        onStep(input, 'input', () => {
          const now = performance.now();
          const r = input.getBoundingClientRect();
          run.ui.guide.lookAt(r.left + Math.min(r.width - 12, 14 + input.value.length * 7.5), r.top + r.height / 2);
          if (now - last > 900) {
            last = now;
            run.ui.guide.excite();
          }
        });
        if (document.activeElement !== input) setTimeout(() => input.focus({ preventScroll: true }), 60);
        const r = input.getBoundingClientRect();
        run.ui.guide.lookAt(r.left + 24, r.top + r.height / 2);
      }
    }
  }

  function place(step, target) {
    const W = innerWidth, H = innerHeight, m = 12, gap = 14, s = run.ui.size;
    const b = run.ui.measure;
    b.style.width = '';
    b.classList.remove('is-docked');
    const bw = b.offsetWidth, bh = b.offsetHeight;
    const fits = (x, y, w, h) => x >= m - .5 && y >= m - .5 && x + w <= W - m + .5 && y + h <= H - m + .5;
    const overlaps = (x, y, w, h, r) => r && x < r.right && x + w > r.left && y < r.bottom && y + h > r.top;
    if (!target) {
      const left = narrow() ? 0 : (q('.sidebar')?.getBoundingClientRect().right || 0);
      const row = s + 8 + bw <= W - left - 2 * m;
      if (row) {
        const x0 = left + (W - left - (s + 8 + bw)) / 2, y0 = H * .34;
        return { gx: x0, gy: y0 - s * .1, bx: x0 + s + 8, by: y0, tail: 'left' };
      }
      const x0 = (W - bw) / 2;
      return { gx: (W - s) / 2, gy: H * .22, bx: x0, by: H * .22 + s + 6, tail: 'top' };
    }
    const r = target.getBoundingClientRect();
    const tries = [];
    const midY = clamp(r.top + r.height / 2, m + s / 2, H - m - s / 2);
    const midX = clamp(r.left + r.width / 2, m + s / 2, W - m - s / 2);
    tries.push(() => {
      const gx = r.right + gap, gy = midY - s * .46;
      return { gx, gy, bx: gx + s + 6, by: clamp(gy + s * .12 - bh * .3, m, H - m - bh), tail: 'left' };
    });
    tries.push(() => {
      const gx = r.left - gap - s, gy = midY - s * .46;
      return { gx, gy, bx: gx - 6 - bw, by: clamp(gy + s * .12 - bh * .3, m, H - m - bh), tail: 'right' };
    });
    tries.push(() => {
      const gx = r.right + gap, gy = clamp(r.top, m, H - m - s - 6 - bh);
      return { gx, gy, bx: gx, by: gy + s + 6, tail: 'top' };
    });
    tries.push(() => {
      const gx = r.left - gap - Math.max(s, bw), gy = clamp(r.top, m, H - m - s - 6 - bh);
      return { gx: gx + Math.max(0, bw - s), gy, bx: gx, by: gy + s + 6, tail: 'top' };
    });
    tries.push(() => {
      const gy = r.bottom + gap, gx = midX - s / 2;
      const bx = gx + s + 6 + bw <= W - m ? gx + s + 6 : gx - 6 - bw;
      return { gx, gy, bx, by: gy + s * .12, tail: bx > gx ? 'left' : 'right' };
    });
    tries.push(() => {
      const gy = r.top - gap - s, gx = midX - s / 2;
      const bx = gx + s + 6 + bw <= W - m ? gx + s + 6 : gx - 6 - bw;
      return { gx, gy, bx, by: gy + s * .12, tail: bx > gx ? 'left' : 'right' };
    });
    tries.push(() => {
      const gx = midX - s / 2, gy = r.bottom + gap;
      return { gx, gy, bx: clamp(r.left + r.width / 2 - bw / 2, m, W - m - bw), by: gy + s + 6, tail: 'top' };
    });
    tries.push(() => {
      const gy = r.top - gap - s, gx = midX - s / 2;
      return { gx, gy, bx: clamp(r.left + r.width / 2 - bw / 2, m, W - m - bw), by: gy - 6 - bh, tail: 'bottom' };
    });
    for (const t of tries) {
      const p = t();
      if (fits(p.gx, p.gy, s, s) && fits(p.bx, p.by, bw, bh) && !overlaps(p.bx, p.by, bw, bh, r) && !overlaps(p.gx + s * .2, p.gy + s * .2, s * .6, s * .6, r)) return p;
    }
    for (const right of [true, false]) {
      const avail = right ? W - m - (r.right + gap) : r.left - gap - m;
      if (avail < 220) continue;
      const width = Math.min(bw, avail);
      b.style.width = width + 'px';
      const h2 = b.offsetHeight;
      const gy = clamp(r.top, m, H - m - s - 6 - h2);
      const gx = right ? r.right + gap : r.left - gap - s, bx = right ? r.right + gap : r.left - gap - width;
      if (fits(gx, gy, s, s) && fits(bx, gy + s + 6, width, h2)) return { gx, gy, bx, by: gy + s + 6, tail: 'top', width };
    }
    const dw = W - 2 * m - s - 6;
    b.style.width = dw + 'px';
    b.classList.add('is-docked');
    const dh = b.offsetHeight, need = Math.max(s, dh);
    const above = r.top - gap - m, below = H - r.bottom - gap - m;
    if (above >= need || below >= need) {
      const top = above >= need;
      const y0 = top ? r.top - gap - need : r.bottom + gap;
      return { gx: W - m - s, gy: y0 + (need - s) / 2, bx: m, by: y0 + (need - dh) / 2, tail: 'right', width: dw, docked: true };
    }
    b.style.width = '';
    b.classList.remove('is-docked');
    const p = tries[4]();
    return {
      gx: clamp(p.gx, m, W - m - s), gy: clamp(p.gy, m, H - m - s),
      bx: clamp(p.bx, m, W - m - bw), by: clamp(p.by, m, H - m - bh), tail: p.tail
    };
  }

  function setSpot(step, target) {
    const { spot, scrim } = run.ui;
    const dim = step.dim !== false;
    const interactive = !!step.wait;
    scrim.classList.toggle('is-open', !interactive);
    spot.classList.toggle('is-off', !dim);
    spot.classList.toggle('is-ring', dim && interactive);
    if (!target) {
      const W = innerWidth, H = innerHeight;
      Object.assign(spot.style, { left: W / 2 + 'px', top: H / 2 + 'px', width: '0px', height: '0px', borderRadius: '50%' });
      return;
    }
    const r = target.getBoundingClientRect(), pad = 6;
    const radius = parseFloat(getComputedStyle(target).borderTopLeftRadius) || 10;
    Object.assign(spot.style, {
      left: (r.left - pad) + 'px', top: (r.top - pad) + 'px',
      width: (r.width + pad * 2) + 'px', height: (r.height + pad * 2) + 'px',
      borderRadius: Math.min(radius + pad, 26) + 'px'
    });
  }

  function showRings(items) {
    clearRings();
    items.filter(shown).forEach((el, i) => {
      const r = el.getBoundingClientRect(), ring = make('i', 'tour-ring', run.ui.rings);
      Object.assign(ring.style, { left: (r.left - 3) + 'px', top: (r.top - 3) + 'px', width: (r.width + 6) + 'px', height: (r.height + 6) + 'px', animationDelay: (180 + i * 110) + 'ms' });
    });
  }

  function clearRings() {
    if (run) run.ui.rings.textContent = '';
  }

  function fillBubble(step, bubble) {
    const source = narrow() && step.short ? step.short : step.text;
    const text = typeof source === 'function' ? source() : source;
    run.text = text;
    bubble.querySelector('.tour-sr').textContent = text;
    bubble.querySelector('.tour-typed').textContent = text;
    bubble.querySelector('.tour-rest').textContent = '';
    const current = DOT_OF[step.id] || step.id;
    bubble.querySelectorAll('.tour-dots i').forEach((dot, i) => {
      const at = DOTS.indexOf(current);
      dot.className = i < at ? 'is-past' : i === at ? 'is-now' : '';
    });
    bubble.querySelector('.tour-dots').hidden = !(step.dot || DOT_OF[step.id]);
    const primary = bubble.querySelector('[data-act=primary]'), secondary = bubble.querySelector('[data-act=secondary]');
    const back = backOf(step);
    primary.hidden = !!step.wait;
    primary.textContent = step.primary || 'Weiter';
    secondary.hidden = !(step.secondary || back);
    secondary.textContent = step.secondary || 'Zurück';
    bubble.classList.toggle('is-waiting', !!step.wait);
  }

  function backOf(step) {
    if (step.back !== undefined) return step.back;
    const i = indexOf(step.id);
    if (i <= 0) return null;
    const prev = STEPS[i - 1];
    return prev.page || prev.wait ? null : prev.id;
  }

  function dress(bubble, spots) {
    bubble.style.width = spots.width ? spots.width + 'px' : '';
    bubble.classList.toggle('is-docked', !!spots.docked);
    Object.assign(bubble.style, { left: spots.bx + 'px', top: spots.by + 'px' });
  }

  function showBubble(step, spots) {
    const { bubble, guide } = run.ui;
    fillBubble(step, bubble);
    dress(bubble, spots);
    bubble.dataset.tail = spots.tail;
    const s = run.ui.size;
    if (spots.tail === 'left' || spots.tail === 'right') {
      bubble.style.setProperty('--tail', clamp(spots.gy + s * .5 - spots.by, 18, bubble.offsetHeight - 18) + 'px');
    } else {
      bubble.style.setProperty('--tail', clamp(spots.gx + s * .5 - spots.bx, 22, bubble.offsetWidth - 22) + 'px');
    }
    bubble.classList.add('is-shown');
    type(run.text);
    guide.say(run.text);
    if (!step.wait) {
      setTimeout(() => {
        if (run && run.step === step) bubble.focus({ preventScroll: true });
      }, 40);
    }
  }

  function hideBubble() {
    if (!run) return;
    run.ui.bubble.classList.remove('is-shown', 'is-nudged');
    run.ui.guide.hush();
    cancelAnimationFrame(run.typing || 0);
  }

  function type(text) {
    const typed = run.ui.bubble.querySelector('.tour-typed'), rest = run.ui.bubble.querySelector('.tour-rest');
    if (still()) {
      typed.textContent = text;
      rest.textContent = '';
      return;
    }
    const t0 = performance.now(), rate = 60;
    let shown = -1;
    const tick = now => {
      if (!run) return;
      const n = Math.min(text.length, Math.floor((now - t0) / 1000 * rate));
      if (n !== shown) {
        shown = n;
        typed.textContent = text.slice(0, n);
        rest.textContent = text.slice(n);
      }
      if (n < text.length) run.typing = requestAnimationFrame(tick);
    };
    typed.textContent = '';
    rest.textContent = text;
    run.typing = requestAnimationFrame(tick);
  }

  function onBubbleClick(e) {
    const btn = e.target.closest('[data-act]');
    if (!btn || !run || !run.step) return;
    const act = btn.dataset.act, step = run.step;
    if (act === 'close') return end('skipped');
    if (act === 'primary') return next(step);
    if (act === 'secondary') {
      if (step.onSecondary === 'skip') return end('skipped');
      if (step.onSecondary) return go(step.onSecondary);
      const back = backOf(step);
      if (back) go(back);
    }
  }

  function next(step) {
    if (step.onPrimary === 'done') return end('done');
    const i = indexOf(step.id);
    const following = STEPS[i + 1];
    if (following) go(following.id);
  }

  function onKey(e) {
    if (!run || !run.step) return;
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || e.target.isContentEditable;
    if (e.key === 'Escape') {
      if (run.step.wait === 'created' && q('#addTaskModal.active')) return;
      e.preventDefault();
      end('skipped');
      return;
    }
    if (typing || run.step.wait) return;
    if (e.key === 'Enter' && (e.target === run.ui.bubble || e.target === document.body)) {
      e.preventDefault();
      next(run.step);
    } else if (e.key === 'ArrowRight') {
      e.preventDefault();
      next(run.step);
    } else if (e.key === 'ArrowLeft') {
      const back = backOf(run.step);
      if (back) {
        e.preventDefault();
        go(back);
      }
    }
  }

  let relayoutQueued = false;
  function relayout(smooth) {
    if (!run || relayoutQueued) return;
    relayoutQueued = true;
    requestAnimationFrame(() => {
      relayoutQueued = false;
      if (!run || !run.step || run.ending) return;
      const step = run.step, target = run.target && run.target.isConnected ? run.target : null;
      const spots = place(step, target);
      setSpot(step, target);
      if (smooth === true) run.ui.guide.moveTo(spots.gx, spots.gy);
      else run.ui.guide.place(spots.gx, spots.gy);
      if (target) {
        const aim = aimAt(target, spots);
        run.ui.guide.target(aim.x, aim.y);
      }
      dress(run.ui.bubble, spots);
      if (step.rings) showRings(step.rings());
    });
  }

  async function end(state) {
    if (!run || run.ending) return;
    run.ending = true;
    run.token++;
    forget();
    persist(state);
    clearWaits();
    hideBubble();
    clearRings();
    const { scrim, spot, guide } = run.ui;
    scrim.classList.remove('is-open');
    spot.classList.add('is-off');
    if (state === 'done') await guide.setMode('bye');
    else {
      guide.el.classList.add('is-gone');
      await wait(still() ? 0 : 280);
    }
    teardown();
  }

  function teardown() {
    if (!run) return;
    clearInterval(run.tracker);
    for (const off of run.offs) off();
    clearWaits();
    const { scrim, spot, rings, bubble, measure, guide } = run.ui;
    guide.destroy();
    for (const el of [scrim, spot, rings, bubble, measure]) el.remove();
    document.documentElement.classList.remove('tour-on');
    run = null;
  }

  function resume(saved) {
    const step = STEPS[indexOf(saved.id)];
    if (step.page && location.pathname !== step.page) {
      start('calendar', saved);
      return;
    }
    const id = step.id === 'task-form' || step.id === 'task-done' ? 'task-new' : step.id;
    start(id, saved);
  }

  function boot() {
    document.addEventListener('click', e => {
      const trigger = e.target.closest && e.target.closest('[data-tour-start]');
      if (!trigger) return;
      e.preventDefault();
      forget();
      start('hello');
    });
    const saved = load();
    if (saved) {
      resume(saved);
      return;
    }
    if (new URLSearchParams(location.search).get('tour') === '1') {
      start('hello');
      return;
    }
    if (document.body.dataset.tourAuto === '1' && location.pathname === '/hub') {
      setTimeout(() => {
        if (!run && !load()) start('hello');
      }, 1200);
    }
  }

  self.AppTour = {
    start: () => {
      forget();
      start('hello');
    },
    stop: () => end('skipped')
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
