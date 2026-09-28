import { brandName, escapeHtml, getLang, raw, t } from "../lib/i18n.js";
import { icon } from "../lib/icons.js";
import { reducedMotion } from "../lib/motion.js";
import { tinte } from "../lib/tinte.js";
import { iphoneHTML } from "./device.js";

const EASE = "cubic-bezier(0.16, 1, 0.3, 1)";
const SPRING = "cubic-bezier(0.34, 1.45, 0.64, 1)";
const NAV = [
  { id: "home", old: 0, now: 0, glyph: "house" },
  { id: "tasks", old: 1, now: 1, glyph: "tasks" },
  { id: "pomodoro", old: 2, glyph: "timer" },
  { id: "calendar", old: 3, now: 2, glyph: "calendar" },
  { id: "transit", old: 4, now: 4, glyph: "train" },
  { id: "school", old: 5, now: 3, glyph: "school" },
  { id: "training", old: 6, glyph: "dumbbell" },
  { id: "projects", old: 7, glyph: "projects" },
  { id: "knowledge", old: 8, glyph: "idea" },
  { id: "bookmarks", old: 9, glyph: "bookmark" },
  { id: "mail", old: 10, now: 5, glyph: "mail" },
  { id: "review", old: 11, glyph: "activity" },
  { id: "mousepad", old: 12, glyph: "notebook" },
  { id: "assistant", old: 13, glyph: "message-circle" },
  { id: "settings", old: 14, glyph: "settings" },
];
const HOURS = [
  { hour: 13, rain: 0, glyph: "sun" },
  { hour: 14, rain: 0, glyph: "sun" },
  { hour: 15, rain: 10, glyph: "cloud-sun" },
  { hour: 16, rain: 30, glyph: "cloud-sun" },
  { hour: 17, rain: 60, glyph: "cloud-rain" },
  { hour: 18, rain: 70, glyph: "cloud-rain" },
];
const SECURITY = ["login", "mail", "iserv", "assistant", "desktop", "web"];
const LIBS = { old: 19, gone: [2, 5, 8, 11, 15] };
const CARRY = [["tasks", "tasks"], ["calendar", "events"], ["school", "grades"], ["key", "logins"]];

const s = (key) => escapeHtml(t(`start.scene.${key}`));
const locale = () => (getLang() === "de" ? "de-DE" : "en-IE");

function mark(cls = "sc-mark") {
  return `<svg class="${cls}" viewBox="14 18 72 66" aria-hidden="true" focusable="false"><circle cx="40" cy="44" r="26" fill="#E7C694"/><rect x="44" y="42" width="42" height="42" rx="12" fill="#A3B690"/><path d="M44 69.69V54A12 12 0 0 1 56 42H65.92A26 26 0 0 1 44 69.69Z" fill="#2E3A2F"/></svg>`;
}

function navScene() {
  const labels = raw("start.scene.nav") || {};
  const kept = NAV.filter((row) => row.now !== undefined).sort((a, b) => a.now - b.now);
  const gone = NAV.filter((row) => row.now === undefined);
  const row = (item) => {
    const label = item.id === "home" ? t("start.scene.nav_home") : labels[item.id];
    const old = item.id === "home" ? ` data-old-label="${escapeHtml(t("start.scene.nav_home_old"))}"` : "";
    return `<li class="sc-nav-row${item.id === "home" ? " is-current" : ""}" data-old="${item.old}"${item.now === undefined ? " hidden" : ""}>${icon(item.glyph, { size: 17 })}<span${old}>${escapeHtml(label || "")}</span></li>`;
  };
  return `<div class="sc sc-nav" data-scene="nav" role="img" aria-label="${s("nav_alt")}">
    <div class="sc-app sc-side">
      <p class="sc-side-brand">${mark()}<span>${escapeHtml(brandName)}</span></p>
      <ul class="sc-nav-list">${kept.map(row).join("")}${gone.map(row).join("")}<li class="sc-nav-row sc-nav-more" data-more>${icon("more", { size: 17 })}<span>${s("nav_more")}</span>${icon("chevron-down", { size: 15, cls: "sc-nav-chev" })}</li></ul>
    </div>
  </div>`;
}

function weatherScene() {
  const hours = HOURS.map((item) => `<li class="sc-hour${item.rain >= 50 ? " is-wet" : ""}">
      <span class="sc-hour-rain">${item.rain ? `${item.rain} %` : ""}</span>
      <span class="sc-hour-bar"><i style="--v:${Math.max(item.rain, 6) / 100}"></i></span>
      ${icon(item.glyph, { size: 17, cls: "sc-hour-glyph" })}
      <span class="sc-hour-time">${item.hour}</span>
    </li>`).join("");
  return `<div class="sc sc-weather" data-scene="weather" role="img" aria-label="${s("weather_alt")}">
    <div class="sc-app sc-today">
      <p class="sc-today-meta">${icon("sunrise", { size: 15 })}${s("weather_meta")}</p>
      <p class="sc-today-line">${s("weather_way")} <span class="sc-line-badge">${s("weather_line")}</span> ${s("weather_time")} <span class="sc-weather-chip" data-pop>${s("weather_dry")}</span></p>
      <ol class="sc-hours">${hours}</ol>
      <p class="sc-today-event" data-pop>${icon("dumbbell", { size: 16 })}<span>${s("weather_event")}</span><span class="sc-rain-chip">${s("weather_rain")}</span></p>
    </div>
  </div>`;
}

function tourScene() {
  const dots = Array.from({ length: 12 }, (_, i) => `<i${i === 0 ? ' class="is-on"' : ""}></i>`).join("");
  return `<div class="sc sc-tour" data-scene="tour" role="img" aria-label="${s("tour_alt")}">
    <div class="sc-tour-mascot">${tinte("ruhe", 170, "", { still: true })}</div>
    <div class="sc-app sc-bubble">
      <p class="sc-bubble-steps"><span class="sc-dots">${dots}</span><span>${s("tour_step")}</span></p>
      <p class="sc-bubble-text">${s("tour_text")}</p>
      <p class="sc-bubble-actions"><span class="sc-btn is-primary">${s("tour_go")}</span><span class="sc-btn">${s("tour_later")}</span></p>
    </div>
  </div>`;
}

function securityScene() {
  const areas = raw("start.scene.security") || {};
  const rows = SECURITY.map((id) => `<li class="sc-check-row"><span class="sc-check">${icon("check", { size: 14, stroke: 3 })}</span>${escapeHtml(areas[id] || "")}</li>`).join("");
  return `<div class="sc sc-shield" data-scene="shield" role="img" aria-label="${s("security_alt")}">
    <div class="sc-app sc-app-night sc-report">
      <div class="sc-report-head">
        <span class="sc-report-glyph">${icon("shield", { size: 22 })}</span>
        <p class="sc-report-title">${s("security_title")}<span>${s("security_version")}</span></p>
        <p class="sc-report-count"><b><i data-tally>30</i>+</b><small>${s("security_fixes")}</small></p>
      </div>
      <ul class="sc-check-list">${rows}</ul>
    </div>
  </div>`;
}

function sizeScene() {
  const fmt = new Intl.NumberFormat(locale(), { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  const bricks = (keep) => Array.from({ length: LIBS.old }, (_, i) => (keep || !LIBS.gone.includes(i) ? "<i></i>" : "<i data-gone hidden></i>")).join("");
  const row = (age, name, visual, value) => `<div class="sc-download-row is-${age}"><span class="sc-download-name">${name}</span>${visual}<span class="sc-download-mb">${value}</span></div>`;
  const now = `${escapeHtml(brandName)} 0.5`;
  return `<div class="sc sc-size" data-scene="size" role="img" aria-label="${s("size_alt")}">
    <div class="sc-app sc-download">
      <p class="sc-download-title">${icon("laptop", { size: 17 })}${s("size_title")}</p>
      <p class="sc-download-label">${s("size_weight")}</p>
      ${row("old", s("size_old"), '<span class="sc-download-bar"><i></i></span>', `${fmt.format(39.4)} MB`)}
      ${row("new", now, '<span class="sc-download-bar"><i></i></span>', `<b data-from="39.4" data-to="24">${fmt.format(24)}</b> MB`)}
      <p class="sc-download-label">${s("size_libs")}</p>
      ${row("old", s("size_old"), `<span class="sc-libs">${bricks(true)}</span>`, LIBS.old)}
      ${row("new", now, `<span class="sc-libs" data-libs>${bricks(false)}</span>`, `<b data-libs-count>${LIBS.old - LIBS.gone.length}</b>`)}
    </div>
  </div>`;
}

function guardScene() {
  return `<div class="sc sc-guard" data-scene="guard" role="img" aria-label="${s("guard_alt")}">
    <div class="sc-guard-mascot">${tinte("geschafft", 118, "", { still: true })}</div>
    <div class="sc-app sc-actions">
      <div class="sc-action is-done"><span class="sc-action-glyph">${icon("tasks", { size: 18 })}</span><p>${s("guard_done")}<span>${s("guard_task")}</span></p><span class="sc-check is-big">${icon("check", { size: 16, stroke: 3 })}</span></div>
      <div class="sc-action is-denied"><span class="sc-action-glyph">${icon("circle-check", { size: 18 })}</span><p>${s("guard_check")}<span>${s("guard_yours")}</span></p><span class="sc-deny">${icon("ban", { size: 18 })}</span></div>
      <div class="sc-action is-denied"><span class="sc-action-glyph">${icon("trash", { size: 18 })}</span><p>${s("guard_delete")}<span>${s("guard_never")}</span></p><span class="sc-deny">${icon("ban", { size: 18 })}</span></div>
    </div>
  </div>`;
}

function moveScene() {
  const chips = CARRY.map(([glyph, key]) => `<li>${icon(glyph, { size: 15 })}${s(`move_${key}`)}</li>`).join("");
  return `<div class="sc sc-move" data-scene="move" role="img" aria-label="${s("move_alt")}">
    <div class="sc-move-from"><span class="sc-move-old">N</span><span class="sc-move-caption">${s("move_from")}</span></div>
    <svg class="sc-move-path" viewBox="0 0 200 60" preserveAspectRatio="none" aria-hidden="true" focusable="false"><path d="M4 56 C 60 -8, 140 -8, 196 56"/></svg>
    <div class="sc-move-to"><span class="sc-move-icon">${mark("sc-move-mark")}</span><span class="sc-move-caption">${escapeHtml(brandName)} 0.5</span></div>
    <ul class="sc-move-chips">${chips}</ul>
    <p class="sc-move-done">${icon("circle-check", { size: 17 })}${s("move_done")}</p>
  </div>`;
}

function phoneScene() {
  return `<div class="sc sc-phones" data-scene="phones" role="img" aria-label="${escapeHtml(t("start.card_alt_phones"))}">${iphoneHTML("/screens/phone-aufgaben.webp", "")}${iphoneHTML("/screens/phone-heute.webp", "")}${iphoneHTML("/screens/phone-abend.webp", "", { dark: true })}</div>`;
}

function calendarScene() {
  const days = raw("start.scene.days") || [];
  const cells = [];
  const first = new Date(2026, 9, 1);
  const lead = (first.getDay() + 6) % 7;
  for (let i = 0; i < 35; i++) {
    const date = new Date(2026, 9, 1 - lead + i);
    const inMonth = date.getMonth() === 9;
    const holiday = inMonth && date.getDate() === 3;
    cells.push(`<span class="sc-date${inMonth ? "" : " is-out"}${holiday ? " is-holiday" : ""}">${date.getDate()}</span>`);
  }
  return `<div class="sc sc-cal" data-scene="cal" role="img" aria-label="${s("cal_alt")}">
    <div class="sc-app sc-month">
      <p class="sc-month-head"><b>${s("cal_month")}</b>${s("cal_year")}<span class="sc-month-chip">${icon("pin", { size: 14 })}${s("cal_states")}</span></p>
      <div class="sc-month-dows">${days.map((day) => `<span>${escapeHtml(day)}</span>`).join("")}</div>
      <div class="sc-month-weeks">
        <div class="sc-month-bands"><span class="sc-band" style="grid-area: 4 / 1 / 5 / 8"></span><span class="sc-band" style="grid-area: 5 / 1 / 6 / 6"></span></div>
        <div class="sc-month-days">${cells.join("")}</div>
      </div>
      <p class="sc-month-legend"><i></i>${s("cal_break")}<i class="is-holiday"></i>${s("cal_holiday")}</p>
    </div>
  </div>`;
}

export const SCENES = {
  theme: navScene,
  weather: weatherScene,
  tour: tourScene,
  security: securityScene,
  size: sizeScene,
  tinte: guardScene,
  move: moveScene,
  phone: phoneScene,
  holidays: calendarScene,
};

function hidden(el, from) {
  Object.assign(el.style, from);
}

function enter(el, from, options) {
  for (const key of Object.keys(from)) el.style[key] = "";
  return el.animate([from, {}], { fill: "backwards", easing: EASE, duration: 620, ...options });
}

function countTo(el, from, to, duration, decimals = 0) {
  const fmt = new Intl.NumberFormat(locale(), { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  const start = performance.now();
  const step = (now) => {
    const p = Math.min(1, (now - start) / duration);
    el.textContent = fmt.format(from + (to - from) * (1 - Math.pow(1 - p, 3)));
    if (p < 1) requestAnimationFrame(step);
  };
  el.textContent = fmt.format(from);
  requestAnimationFrame(step);
}

const RISE = { opacity: "0", transform: "translateY(18px) scale(0.97)" };
const POP = { opacity: "0", transform: "scale(0.6)" };
const STAMP = { opacity: "0", transform: "scale(1.5) rotate(-10deg)" };

const PLAYERS = {
  nav: {
    prepare(scene) {
      const list = scene.querySelector(".sc-nav-list");
      const rows = [...list.querySelectorAll("[data-old]")].sort((a, b) => a.dataset.old - b.dataset.old);
      rows.forEach((row) => {
        row.hidden = false;
        list.insertBefore(row, list.querySelector("[data-more]"));
      });
      const label = list.querySelector("[data-old-label]");
      label.dataset.newLabel = label.textContent;
      label.textContent = label.dataset.oldLabel;
      list.querySelector("[data-more]").hidden = true;
    },
    play(scene, later) {
      const list = scene.querySelector(".sc-nav-list");
      const rows = [...list.querySelectorAll("[data-old]")];
      const gone = rows.filter((row) => !NAV[row.dataset.old].hasOwnProperty("now"));
      gone.forEach((row, i) => row.animate([{}, { opacity: 0, transform: "translateX(-14px) scale(0.96)" }], { duration: 260, delay: 120 + i * 45, easing: "cubic-bezier(0.5, 0, 0.75, 0)", fill: "forwards" }));
      later(120 + gone.length * 45 + 240, () => {
        const kept = rows.filter((row) => !gone.includes(row));
        const before = new Map(kept.map((row) => [row, row.getBoundingClientRect().top]));
        gone.forEach((row) => {
          row.getAnimations().forEach((anim) => anim.cancel());
          row.hidden = true;
        });
        kept.sort((a, b) => NAV[a.dataset.old].now - NAV[b.dataset.old].now).forEach((row) => list.insertBefore(row, list.querySelector("[data-more]")));
        const label = list.querySelector("[data-old-label]");
        label.textContent = label.dataset.newLabel;
        const more = list.querySelector("[data-more]");
        more.hidden = false;
        kept.forEach((row, i) => {
          const dy = before.get(row) - row.getBoundingClientRect().top;
          if (dy) row.animate([{ transform: `translateY(${dy}px)` }, {}], { duration: 620, delay: i * 30, easing: SPRING });
        });
        label.animate([{ opacity: 0.2, transform: "translateY(6px)" }, {}], { duration: 420, easing: EASE });
        enter(more, RISE, { delay: 260, duration: 520 });
      });
    },
  },
  weather: {
    prepare(scene) {
      scene.querySelectorAll(".sc-hour-bar i").forEach((bar) => hidden(bar, { transform: "scaleY(0)" }));
      scene.querySelectorAll(".sc-hour-rain").forEach((el) => hidden(el, { opacity: "0" }));
      scene.querySelectorAll("[data-pop]").forEach((el) => hidden(el, POP));
    },
    play(scene) {
      scene.querySelectorAll(".sc-hour-bar i").forEach((bar, i) => enter(bar, { transform: "scaleY(0)" }, { delay: 150 + i * 90, duration: 760 }));
      scene.querySelectorAll(".sc-hour-rain").forEach((el, i) => enter(el, { opacity: "0" }, { delay: 520 + i * 90, duration: 300 }));
      const [chip, event] = scene.querySelectorAll("[data-pop]");
      enter(chip, POP, { delay: 820, duration: 560, easing: SPRING });
      enter(event, RISE, { delay: 1080, duration: 560 });
    },
  },
  tour: {
    prepare(scene) {
      hidden(scene.querySelector(".sc-tour-mascot"), { opacity: "0", transform: "translateY(40px) scale(0.86)" });
      hidden(scene.querySelector(".sc-bubble"), POP);
      scene.querySelectorAll(".sc-dots i").forEach((dot) => hidden(dot, { opacity: "0", transform: "scale(0)" }));
    },
    play(scene) {
      enter(scene.querySelector(".sc-tour-mascot"), { opacity: "0", transform: "translateY(40px) scale(0.86)" }, { duration: 760, easing: SPRING });
      enter(scene.querySelector(".sc-bubble"), POP, { delay: 260, duration: 620, easing: SPRING });
      scene.querySelectorAll(".sc-dots i").forEach((dot, i) => enter(dot, { opacity: "0", transform: "scale(0)" }, { delay: 620 + i * 40, duration: 380, easing: SPRING }));
    },
  },
  shield: {
    prepare(scene) {
      scene.querySelectorAll(".sc-check-row").forEach((row) => hidden(row, { opacity: "0", transform: "translateY(12px)" }));
      scene.querySelectorAll(".sc-check").forEach((check) => hidden(check, { opacity: "0", transform: "scale(1.4) rotate(-8deg)" }));
      scene.querySelector("[data-tally]").textContent = "0";
    },
    play(scene) {
      const rows = scene.querySelectorAll(".sc-check-row");
      rows.forEach((row, i) => {
        enter(row, { opacity: "0", transform: "translateY(12px)" }, { delay: 120 + i * 110, duration: 520 });
        enter(row.querySelector(".sc-check"), { opacity: "0", transform: "scale(1.4) rotate(-8deg)" }, { delay: 300 + i * 110, duration: 460, easing: SPRING });
      });
      countTo(scene.querySelector("[data-tally]"), 0, 30, 120 + rows.length * 110 + 400);
    },
  },
  size: {
    prepare(scene) {
      hidden(scene.querySelector(".is-new .sc-download-bar i"), { transform: "scaleX(1)" });
      scene.querySelectorAll("[data-gone]").forEach((brick) => (brick.hidden = false));
      scene.querySelector("[data-libs-count]").textContent = LIBS.old;
    },
    play(scene, later) {
      enter(scene.querySelector(".is-new .sc-download-bar i"), { transform: "scaleX(1)" }, { delay: 300, duration: 1150 });
      const number = scene.querySelector("[data-from]");
      later(300, () => countTo(number, Number(number.dataset.from), Number(number.dataset.to), 1150, 1));
      const gone = [...scene.querySelectorAll("[data-gone]")];
      const kept = [...scene.querySelectorAll("[data-libs] i:not([data-gone])")];
      gone.forEach((brick, i) => brick.animate([{}, { opacity: 0, transform: `translateY(30px) rotate(${i % 2 ? 26 : -26}deg) scale(0.7)` }], { delay: 1300 + i * 90, duration: 540, easing: "cubic-bezier(0.5, 0, 0.75, 0)", fill: "forwards" }));
      const count = scene.querySelector("[data-libs-count]");
      gone.forEach((_, i) => later(1300 + i * 90 + 260, () => (count.textContent = LIBS.old - i - 1)));
      later(1300 + gone.length * 90 + 480, () => {
        const before = new Map(kept.map((brick) => [brick, brick.getBoundingClientRect().left]));
        gone.forEach((brick) => {
          brick.getAnimations().forEach((anim) => anim.cancel());
          brick.hidden = true;
        });
        kept.forEach((brick, i) => {
          const dx = before.get(brick) - brick.getBoundingClientRect().left;
          if (dx) brick.animate([{ transform: `translateX(${dx}px)` }, {}], { duration: 600, delay: i * 16, easing: SPRING });
        });
      });
    },
  },
  guard: {
    prepare(scene) {
      hidden(scene.querySelector(".sc-guard-mascot"), { opacity: "0", transform: "translateY(30px) scale(0.9)" });
      scene.querySelectorAll(".sc-action").forEach((row) => hidden(row, RISE));
      scene.querySelectorAll(".sc-check.is-big, .sc-deny").forEach((mark) => hidden(mark, STAMP));
    },
    play(scene) {
      const [done, ...denied] = scene.querySelectorAll(".sc-action");
      enter(scene.querySelector(".sc-guard-mascot"), { opacity: "0", transform: "translateY(30px) scale(0.9)" }, { duration: 700, easing: SPRING });
      enter(done, RISE, { delay: 220 });
      enter(scene.querySelector(".sc-check.is-big"), STAMP, { delay: 620, duration: 480, easing: SPRING });
      const stamps = denied.map((row, i) => {
        enter(row, RISE, { delay: 900 + i * 160 });
        return enter(row.querySelector(".sc-deny"), STAMP, { delay: 1220 + i * 160, duration: 460, easing: SPRING });
      });
      stamps.at(-1)?.finished.then(() => {
        denied.forEach((row) => row.animate([{}, { transform: "translateX(-7px)" }, { transform: "translateX(6px)" }, { transform: "translateX(-3px)" }, {}], { duration: 440, easing: "ease-in-out" }));
      }, () => {});
    },
  },
  move: {
    prepare(scene) {
      scene.querySelectorAll(".sc-move-chips li").forEach((chip) => hidden(chip, { opacity: "0" }));
      hidden(scene.querySelector(".sc-move-done"), RISE);
    },
    play(scene, later) {
      const from = scene.querySelector(".sc-move-old").getBoundingClientRect();
      const chips = [...scene.querySelectorAll(".sc-move-chips li")];
      chips.forEach((chip, i) => {
        chip.style.opacity = "";
        const box = chip.getBoundingClientRect();
        const dx = from.left + from.width / 2 - (box.left + box.width / 2);
        const dy = from.top + from.height / 2 - (box.top + box.height / 2);
        chip.animate([
          { opacity: 0, transform: `translate(${dx}px, ${dy}px) scale(0.4)` },
          { opacity: 1, transform: `translate(${dx * 0.55}px, ${dy * 0.55 - 70}px) scale(0.9)`, offset: 0.5 },
          { opacity: 1, transform: "none" },
        ], { delay: 200 + i * 150, duration: 900, easing: EASE, fill: "backwards" });
      });
      later(200 + chips.length * 150 + 700, () => {
        scene.querySelector(".sc-move-icon").animate([{}, { transform: "scale(1.12, 0.9)" }, { transform: "scale(0.96, 1.05)" }, {}], { duration: 480, easing: "ease-out" });
        enter(scene.querySelector(".sc-move-done"), RISE, { delay: 180, duration: 520 });
      });
    },
  },
  phones: {
    prepare(scene) {
      scene.querySelectorAll(".iphone").forEach((phone) => hidden(phone, { opacity: "0", translate: "0 90px" }));
    },
    play(scene) {
      scene.querySelectorAll(".iphone").forEach((phone, i) => enter(phone, { opacity: "0", translate: "0 90px" }, { delay: [140, 0, 280][i], duration: 900, easing: SPRING }));
    },
  },
  cal: {
    prepare(scene) {
      scene.querySelectorAll(".sc-band").forEach((band) => hidden(band, { transform: "scaleX(0)" }));
      scene.querySelectorAll(".sc-month-legend, .sc-date.is-holiday").forEach((el) => hidden(el, { opacity: "0" }));
    },
    play(scene) {
      scene.querySelectorAll(".sc-band").forEach((band, i) => enter(band, { transform: "scaleX(0)" }, { delay: 250 + i * 420, duration: 700 }));
      enter(scene.querySelector(".sc-month-legend"), { opacity: "0" }, { delay: 900, duration: 480 });
      scene.querySelectorAll(".sc-date.is-holiday").forEach((el) => enter(el, POP, { delay: 1300, duration: 500, easing: SPRING }));
    },
  },
};

export function mountScenes(root) {
  const scenes = [...root.querySelectorAll("[data-scene]")];
  if (!scenes.length || reducedMotion() || !("IntersectionObserver" in window)) return () => {};
  const timers = [];
  const later = (ms, fn) => timers.push(setTimeout(fn, ms));
  const byCard = new Map();
  scenes.forEach((scene) => {
    const player = PLAYERS[scene.dataset.scene];
    const card = scene.closest(".hl-card");
    if (!player || !card) return;
    player.prepare(scene);
    byCard.set(card, () => player.play(scene, later));
  });
  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      io.unobserve(entry.target);
      byCard.get(entry.target)?.();
    });
  }, { threshold: 0.6 });
  byCard.forEach((_, card) => io.observe(card));
  return () => {
    io.disconnect();
    timers.forEach(clearTimeout);
  };
}
