import { data, flags, icon, esc, safeMarkup, root, subject, hueVar, now, addDays, startOfDay, isoDate, shortDate, clock, minutesOf, pinnedTime, platform, storage, BRAND } from "./core.js";
import { animates, travels, rich } from "./motion.js";
import { tasks as taskApi, deadlines as deadlineApi, notes as noteApi } from "./api.js";

const $ = (id) => document.getElementById(id);

const pageNames = {
  home: "Übersicht", tasks: "Aufgaben", calendar: "Kalender", school: "Schule", vbb: "Fahrplan", email: "E-Mail",
  assistant: "Assistent", pomodoro: "Pomodoro", training: "Training",
  bookmarks: "Lesezeichen", review: "Review", settings: "Einstellungen",
};

const pageIcons = {
  home: "house", tasks: "list-checks", calendar: "calendar-days", school: "graduation-cap", vbb: "train-front", email: "mail",
  assistant: "message-circle", pomodoro: "timer", training: "dumbbell",
  bookmarks: "bookmark", review: "activity", settings: "settings",
};

const keyGlyphs = {
  mod: platform.mac ? { svg: "command", label: "Befehlstaste" } : { text: "Strg" },
  shift: platform.mac ? { svg: "arrow-big-up", label: "Umschalttaste" } : { text: "Umschalt" },
  enter: platform.mac ? { svg: "corner-down-left", label: "Eingabetaste" } : { text: "Enter" },
  alt: platform.mac ? { text: "⌥" } : { text: "Alt" },
};

export const modWord = platform.mac ? "⌘" : "Strg+";

function renderKeys(scope = document) {
  scope.querySelectorAll("kbd[data-key]").forEach((node) => {
    const glyph = keyGlyphs[node.dataset.key];
    if (!glyph) return;
    if (glyph.svg) {
      node.innerHTML = icon(glyph.svg);
      node.setAttribute("aria-label", glyph.label);
    } else {
      node.textContent = glyph.text;
    }
  });
  document.querySelectorAll("[data-electron-only]").forEach((node) => (node.hidden = !platform.electron));
}

export const shortcutsEnabled = () => storage.get("app-single-keys") !== false;

function syncShortcutToggle() {
  const toggle = $("singleKeys");
  if (toggle) toggle.checked = shortcutsEnabled();
  document.querySelectorAll("[data-single-key]").forEach((node) => node.classList.toggle("is-off", !shortcutsEnabled()));
}

$("singleKeys")?.addEventListener("change", (event) => {
  storage.set("app-single-keys", event.target.checked);
  syncShortcutToggle();
});

let undoAction = null;
let undoTimer;

function setUndo(run) {
  undoAction = run;
  clearTimeout(undoTimer);
  if (run) undoTimer = setTimeout(() => (undoAction = null), 60000);
}

function toastArea() {
  const host = $("toasts");
  if (!host || !host.children.length) return null;
  return host.getBoundingClientRect();
}

function syncToastSpace() {
  const area = toastArea();
  root.style.setProperty("--toast-space", area ? `${Math.ceil(area.height) + 16}px` : "0px");
}

export function keepFocusClear(target = document.activeElement) {
  const area = toastArea();
  if (!area || !target || target === document.body || target.closest?.(".toast") || !target.matches?.(":focus-visible")) return;
  const box = target.getBoundingClientRect();
  const crosses = box.right > area.left && box.left < area.right && box.bottom > area.top - 8 && box.top < area.bottom;
  if (crosses) scrollBy({ top: box.bottom - area.top + 16, behavior: travels() ? "smooth" : "auto" });
}

document.addEventListener("focusin", (event) => requestAnimationFrame(() => keepFocusClear(event.target)));

function runUndo() {
  if (!undoAction) return false;
  const run = undoAction;
  setUndo(null);
  run();
  return true;
}

export function toast(message, options = {}) {
  const host = $("toasts");
  const node = document.createElement("div");
  node.className = "toast";
  node.setAttribute("role", "status");
  node.innerHTML = `${icon(options.icon || "check")}<span class="toast-text"></span>`;
  node.querySelector(".toast-text").append(safeMarkup(message));
  const hold = options.action ? 10000 : options.duration || 5000;
  const action = options.action;
  if (action) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "toast-action";
    button.innerHTML = `${esc(action.label)}${action.undo ? `<span class="toast-key" aria-hidden="true">${modWord}Z</span>` : ""}`;
    if (action.undo) button.setAttribute("aria-keyshortcuts", platform.mac ? "Meta+Z" : "Control+Z");
    button.addEventListener("click", () => {
      if (undoAction === action.run) setUndo(null);
      action.run();
      dismiss();
    });
    node.append(button);
    setUndo(action.undo ? action.run : null);
  }
  host.replaceChildren(node);
  syncToastSpace();
  requestAnimationFrame(() => keepFocusClear());
  let timer = setTimeout(dismiss, hold);
  let inside = 0;
  const pause = () => {
    inside += 1;
    clearTimeout(timer);
  };
  const resume = () => {
    inside = Math.max(0, inside - 1);
    if (!inside) timer = setTimeout(dismiss, hold);
  };
  node.addEventListener("pointerenter", pause);
  node.addEventListener("pointerleave", resume);
  node.addEventListener("focusin", pause);
  node.addEventListener("focusout", resume);
  function dismiss() {
    clearTimeout(timer);
    if (!node.isConnected) return;
    if (action && undoAction === action.run) setUndo(null);
    const hadFocus = node.contains(document.activeElement);
    const finish = () => {
      node.remove();
      syncToastSpace();
      if (hadFocus) options.returnFocus?.();
    };
    if (!animates()) {
      finish();
      return;
    }
    node.classList.add("is-leaving");
    node.addEventListener("animationend", finish, { once: true });
  }
  return { node, dismiss };
}

const ROUTES = { home: "/hub", tasks: "/hub/tasks", calendar: "/hub/calendar", school: "/hub/school", vbb: "/hub/vbb", email: "/hub/email", settings: "/hub/settings" };
const CARRIED = ["variante", "theme", "datum", "t", "clean"];

export function pageUrl(page, href = ROUTES[page]) {
  const url = new URL(href, location.href);
  const current = new URLSearchParams(location.search);
  CARRIED.forEach((key) => {
    if (current.has(key) && !url.searchParams.has(key)) url.searchParams.set(key, current.get(key));
  });
  return `${url.pathname}${url.search}${url.hash}`;
}

export function openPage(page) {
  location.assign(ROUTES[page] ? pageUrl(page) : `/hub/${page}`);
}

const tooltip = $("tooltip");
let tooltipWarm = false;
let warmTimer;
let showTimer;
let hideTimer;
let tipTarget = null;

function placeTip(target) {
  tooltip.replaceChildren(safeMarkup(target.dataset.tip));
  tooltip.classList.toggle("on-hero", !!target.closest(".today:not(.is-desk)"));
  const box = target.getBoundingClientRect();
  const width = tooltip.offsetWidth;
  const left = Math.min(Math.max(12, box.left + box.width / 2 - width / 2), innerWidth - width - 12);
  const above = box.top - tooltip.offsetHeight - 8;
  const below = box.bottom + 8;
  const preferBelow = target.dataset.tipSide === "below" && below + tooltip.offsetHeight < innerHeight - 8;
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${preferBelow || above <= 8 ? below : above}px`;
}

function showTip(target, instant = false) {
  if (!target?.dataset.tip) return;
  clearTimeout(showTimer);
  clearTimeout(hideTimer);
  const reveal = () => {
    tipTarget = target;
    tooltip.classList.toggle("is-instant", tooltipWarm || instant);
    placeTip(target);
    tooltip.classList.add("is-on");
    tooltipWarm = true;
    clearTimeout(warmTimer);
  };
  if (tooltipWarm || instant) reveal();
  else showTimer = setTimeout(reveal, 450);
}

function hideTip(delay = 0) {
  clearTimeout(showTimer);
  clearTimeout(hideTimer);
  const hide = () => {
    tooltip.classList.remove("is-on");
    tipTarget = null;
    clearTimeout(warmTimer);
    warmTimer = setTimeout(() => (tooltipWarm = false), 600);
  };
  if (delay) hideTimer = setTimeout(hide, delay);
  else hide();
}

document.addEventListener("pointerover", (event) => {
  if (event.pointerType === "touch") return;
  const target = event.target.closest("[data-tip]");
  if (target && target !== tipTarget) showTip(target);
});
document.addEventListener("pointerout", (event) => {
  const from = event.target.closest("[data-tip]");
  if (!from) return;
  const to = event.relatedTarget;
  if (to && (from.contains(to) || tooltip.contains(to))) return;
  hideTip(120);
});
tooltip?.addEventListener("pointerenter", () => clearTimeout(hideTimer));
tooltip?.addEventListener("pointerleave", (event) => {
  if (tipTarget && tipTarget.contains(event.relatedTarget)) return;
  hideTip(120);
});
document.addEventListener("focusin", (event) => {
  const target = event.target.closest?.("[data-tip]");
  if (target && event.target.matches(":focus-visible")) showTip(target, true);
});
document.addEventListener("focusout", (event) => {
  if (event.target.closest?.("[data-tip]")) hideTip();
});
addEventListener("scroll", () => tooltip.classList.contains("is-on") && hideTip(), { passive: true });

const nav = $("nav");
const indicator = $("navIndicator");
const more = $("navMore");
const drawer = $("navDrawer");

function placeIndicator(instant = false) {
  if (!nav || !indicator) return;
  const sidebar = indicator.parentElement;
  const active = sidebar.querySelector('.nav-item[aria-current="page"]');
  if (!active || !sidebar.offsetWidth) {
    indicator.style.opacity = "0";
    return;
  }
  const hiddenInDrawer = drawer.contains(active) && drawer.hidden;
  const anchor = hiddenInDrawer ? more : active;
  const box = anchor.getBoundingClientRect();
  const frame = sidebar.getBoundingClientRect();
  indicator.classList.toggle("is-instant", instant || !travels());
  indicator.style.opacity = "1";
  indicator.style.setProperty("--indicator-x", `${box.left - frame.left - sidebar.clientLeft}px`);
  indicator.style.setProperty("--indicator-y", `${box.top - frame.top - sidebar.clientTop + sidebar.scrollTop}px`);
  indicator.style.width = `${box.width}px`;
  indicator.style.height = `${box.height}px`;
  if (instant) requestAnimationFrame(() => indicator.classList.remove("is-instant"));
}

function setDrawer(open) {
  more.setAttribute("aria-expanded", String(open));
  drawer.hidden = !open;
  if (open && rich() && travels()) {
    [...drawer.children].forEach((node, index) => node.style.setProperty("--i", index));
    drawer.classList.add("is-entering");
    setTimeout(() => drawer.classList.remove("is-entering"), 600);
  }
  placeIndicator(true);
}

more?.addEventListener("click", () => setDrawer(more.getAttribute("aria-expanded") !== "true"));

document.addEventListener("click", (event) => {
  const link = event.target.closest("a[data-page]");
  if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const page = link.dataset.page;
  const sheet = link.closest("[popover]");
  if (ROUTES[page]) {
    event.preventDefault();
    const own = new URL(link.href, location.href);
    const target = pageUrl(page, own.pathname === ROUTES[page] ? `${own.pathname}${own.search}${own.hash}` : ROUTES[page]);
    if (sheet?.matches(":popover-open")) sheet.hidePopover();
    if (target === `${location.pathname}${location.search}${location.hash}`) return;
    location.assign(target);
    return;
  }
  event.preventDefault();
  if (sheet?.matches(":popover-open")) sheet.hidePopover();
  location.assign(`/hub/${page}`);
});

function renderCounts() {
  const counts = { mail: flags.empty ? 0 : data.mailUnread };
  document.querySelectorAll("[data-count]").forEach((node) => {
    const value = counts[node.dataset.count];
    node.textContent = value || "";
    if (value) node.setAttribute("aria-label", `${value} ungelesen`);
    else node.removeAttribute("aria-label");
  });
}

export function syncTime() {
  return pinnedTime() ? clock(Math.max(0, minutesOf(now()) - 4)) : data.status.lastSync;
}

function renderSync() {
  const time = syncTime();
  const text = flags.offline ? `Offline, Stand ${time} Uhr` : data.status?.iserv ? `IServ, Stand ${time} Uhr` : `Stand ${time} Uhr`;
  const line = $("syncLine");
  if (line) {
    line.classList.toggle("is-offline", flags.offline);
    line.querySelector("span").textContent = text;
    line.querySelector("use").setAttribute("href", flags.offline ? "#i-wifi-off" : "#i-refresh-cw");
  }
  document.querySelectorAll("[data-sync-mirror]").forEach((node) => {
    node.classList.toggle("is-offline", flags.offline);
    node.querySelector("span").textContent = text;
  });
  const head = $("headSync");
  if (head) {
    head.textContent = flags.offline ? `offline, Stand ${time}` : `Stand ${time}`;
    head.classList.toggle("is-offline", flags.offline);
  }
  if (flags.offline) {
    const alert = $("headAlert");
    if (alert) {
      alert.hidden = false;
      $("headAlertText").textContent = `Keine Verbindung zu IServ. ${BRAND} zeigt den Stand von ${time} Uhr. Abhaken und Notizen werden übertragen, sobald IServ wieder erreichbar ist.`;
    }
  }
}

const notifyWords = {
  off: "Erinnerungen aktivieren",
  on: "Erinnerungen an",
  blocked: "Erinnerungen im Browser blockiert",
  unsupported: "Erinnerungen nicht verfügbar",
};

function notifyState() {
  if (!("Notification" in window)) return "unsupported";
  if (Notification.permission === "granted") return "on";
  if (Notification.permission === "denied") return "blocked";
  return "off";
}

function renderNotify() {
  const state = notifyState();
  document.querySelectorAll("[data-notify]").forEach((button) => {
    button.querySelector("[data-notify-text]").textContent = notifyWords[state];
    button.hidden = state !== "off";
  });
}

document.querySelectorAll("[data-notify]").forEach((button) =>
  button.addEventListener("click", async () => {
    if (notifyState() !== "off") return;
    await Notification.requestPermission();
    renderNotify();
    if (notifyState() === "on") toast(`Erinnerungen sind an. ${BRAND} meldet sich vor Tests und Abgaben.`, { icon: "bell" });
  }),
);

let lastInvoker = null;
const invokerSelector = "[popovertarget], [data-open-note], [data-open-weather]";
document.addEventListener("pointerdown", (event) => {
  const trigger = event.target.closest(invokerSelector);
  if (trigger) lastInvoker = trigger;
});
document.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" && event.key !== " ") return;
  const trigger = event.target.closest?.(invokerSelector);
  if (trigger) lastInvoker = trigger;
});

function onScreen(node) {
  if (!node || !node.offsetParent) return false;
  const box = node.getBoundingClientRect();
  return box.width > 0 && box.bottom > 0 && box.top < innerHeight;
}

export function placeNear(sheet, source, align = "right") {
  if (!source || !onScreen(source)) {
    sheet.style.top = "20px";
    sheet.style.right = "20px";
    sheet.style.left = "auto";
    return;
  }
  const box = source.getBoundingClientRect();
  sheet.style.top = `${Math.round(box.bottom + 8)}px`;
  if (align === "right") {
    sheet.style.right = `${Math.max(12, Math.round(innerWidth - box.right))}px`;
    sheet.style.left = "auto";
  } else {
    sheet.style.left = `${Math.max(12, Math.min(Math.round(box.left), innerWidth - sheet.offsetWidth - 12))}px`;
    sheet.style.right = "auto";
  }
}

export function clampSheet(sheet) {
  const top = parseFloat(sheet.style.top) || 20;
  const limit = innerHeight - sheet.offsetHeight - 12;
  if (top > limit) sheet.style.top = `${Math.max(12, Math.round(limit))}px`;
}

const noteSheet = $("noteSheet");
const noteForm = $("noteForm");
const noteInput = $("noteInput");
const noteChips = $("noteChips");
const notePreview = $("notePreview");
const noteSave = $("noteSave");
const segmented = noteForm?.querySelector(".segmented");
let typeTouched = false;
let parsed = { phrases: {} };
let dismissed = new Set();
let lastRecognized = null;

export function openNote({ instant = false, source = null } = {}) {
  if (!noteSheet) return;
  lastInvoker = source || lastInvoker;
  noteSheet.classList.toggle("is-instant", instant);
  if (noteSheet.matches(":popover-open")) {
    noteInput.focus();
    return;
  }
  noteSheet.showPopover();
}

document.querySelectorAll("[data-open-note]").forEach((button) =>
  button.addEventListener("click", () => openNote({ source: button })),
);

noteSheet?.addEventListener("beforetoggle", (event) => {
  if (event.newState !== "open") return;
  const source = [lastInvoker?.closest?.("[data-open-note]"), $("noteButton"), document.querySelector(".topbar [data-open-note]")].find(onScreen);
  placeNear(noteSheet, source, "right");
  noteForm.reset();
  typeTouched = false;
  parsed = { phrases: {} };
  dismissed = new Set();
  lastRecognized = null;
  noteChips.replaceChildren();
  noteChips.dataset.markup = "";
  notePreview.hidden = true;
  syncType();
  noteSave.disabled = true;
});

noteSheet?.addEventListener("toggle", (event) => {
  if (event.newState === "open") {
    clampSheet(noteSheet);
    noteInput.focus();
  } else {
    noteSheet.classList.remove("is-instant");
  }
});

function syncType() {
  const inputs = [...noteForm.querySelectorAll("input[name='type']")];
  const index = inputs.findIndex((input) => input.checked);
  segmented.style.setProperty("--seg", Math.max(index, 0));
}

noteForm?.addEventListener("change", (event) => {
  if (event.target.name === "type") {
    typeTouched = true;
    syncType();
  }
});

const SUBJECT_SYNONYMS = [
  ["mathe", "mathematik"], ["geo", "geografie", "geographie", "erdkunde"], ["pb", "politik", "politische bildung"],
  ["psycho", "psychologie"], ["bio", "biologie"], ["info", "informatik"], ["reli", "religion"], ["franz", "französisch"],
  ["englisch", "english"], ["wat", "wirtschaft"], ["seminarkurs", "seminararbeit", "seminar"], ["deutsch"], ["physik"],
  ["chemie"], ["geschichte"], ["musik"], ["kunst"], ["sport"], ["latein"], ["spanisch"], ["ethik"],
];

const escapeRegex = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function subjectAliases() {
  const list = [];
  Object.entries(data?.subjects || {}).forEach(([key, info]) => {
    if (info.retired) return;
    const plain = (text) => String(text || "").replace(/\s+(LK|GK|SK)$/i, "").trim().toLowerCase();
    const base = plain(info.name);
    const words = new Set([base, plain(info.label), plain(info.short)].filter((word) => word.length >= 2));
    SUBJECT_SYNONYMS.forEach((group) => {
      if (group.some((word) => words.has(word) || base.startsWith(word))) group.forEach((word) => words.add(word));
    });
    words.forEach((word) => list.push([new RegExp(`(?<![\\p{L}\\p{N}])${escapeRegex(word)}(?![\\p{L}\\p{N}])`, "iu"), key, word.length]));
  });
  return list.sort((a, b) => b[2] - a[2]);
}

const weekdayWords = [
  [/^(montag|mo)$/i, 1], [/^(dienstag|di)$/i, 2], [/^(mittwoch|mi)$/i, 3],
  [/^(donnerstag|do)$/i, 4], [/^(freitag|fr)$/i, 5], [/^(samstag|sa)$/i, 6], [/^(sonntag|so)$/i, 0],
];

export function parseNote(text) {
  const result = { phrases: {} };
  const clean = text.replace(/\b(S\.|Seite|Nr\.|Nummer|Aufgabe|Aufg\.|Unit|Kapitel)\s*\d+[a-z]?(\s*(f\.|ff\.|bis\s*\d+))?/gi, (match) => " ".repeat(match.length));
  for (const [pattern, key] of subjectAliases()) {
    if (data?.subjects?.[key] && !data.subjects[key].retired && pattern.test(clean)) {
      result.subject = key;
      break;
    }
  }
  const base = startOfDay(now());
  let date = null;
  let phrase = null;
  const relative = clean.match(/(?<![\p{L}\p{N}])(?:(?:bis|für|am|ab)\s+)?(übermorgen|morgen|heute)(?![\p{L}\p{N}])/iu);
  if (relative) {
    const word = relative[1].toLowerCase();
    date = addDays(base, word === "übermorgen" ? 2 : word === "morgen" ? 1 : 0);
    phrase = relative[0];
  }
  const inDaysMatch = clean.match(/\b(?:bis\s+)?in\s+(\d{1,2})\s+tag(?:en)?\b/i);
  if (!date && inDaysMatch) {
    date = addDays(base, Number(inDaysMatch[1]));
    phrase = inDaysMatch[0];
  }
  const nextWeek = clean.match(/\b(?:bis\s+)?nächste(?:n)?\s+woche\b/i);
  if (!date && nextWeek) {
    date = addDays(base, 8 - (base.getDay() || 7));
    phrase = nextWeek[0];
  }
  const explicit = clean.match(/\b(?:(?:bis|am|zum|ab)\s+)?(\d{1,2})\.(\d{1,2})\.(\d{2,4})?(?!\d)/i);
  if (!date && explicit) {
    const day = Number(explicit[1]);
    const month = Number(explicit[2]) - 1;
    let year = explicit[3] ? Number(explicit[3]) : base.getFullYear();
    if (year < 100) year += 2000;
    const candidate = new Date(year, month, day);
    if (candidate.getMonth() === month && day >= 1) {
      date = candidate < base && !explicit[3] ? new Date(year + 1, month, day) : candidate;
      phrase = explicit[0];
    }
  }
  if (!date) {
    const marker = clean.match(/\b(bis|am|zum|ab)\s+(\S+)/i);
    if (marker) {
      for (const [pattern, dow] of weekdayWords) {
        if (pattern.test(marker[2])) {
          const offset = (dow - base.getDay() + 7) % 7 || 7;
          date = addDays(base, offset);
          phrase = marker[0];
          break;
        }
      }
    }
  }
  if (date) {
    result.date = isoDate(date);
    result.phrases.date = phrase;
  }
  const block = clean.match(/\b(?:(?:im|zum|vor dem|bis zum)\s+)?([1-4])\.\s*block\b/i);
  if (block) {
    result.block = Number(block[1]);
    result.phrases.block = block[0];
  }
  const leadingType = clean.match(/^\s*(hausaufgabe|ha|hausi)\b:?/i);
  if (leadingType || /\b(hausaufgabe|hausi)\b/i.test(clean)) {
    result.type = "homework";
    if (leadingType) result.phrases.type = leadingType[0].trim();
  } else if (/^\s*idee\b/i.test(clean)) {
    result.type = "idea";
    result.phrases.type = clean.match(/^\s*idee\b:?/i)[0].trim();
  }
  return result;
}

function effective() {
  const result = { ...parsed, phrases: { ...parsed.phrases } };
  ["subject", "date", "block"].forEach((kind) => {
    if (!dismissed.has(kind)) return;
    delete result[kind];
    delete result.phrases[kind];
  });
  return result;
}

export function cleanTitle(text, info) {
  let title = text;
  ["date", "block", "type"].forEach((kind) => {
    const phrase = info.phrases?.[kind];
    if (!phrase) return;
    const index = title.toLowerCase().indexOf(phrase.toLowerCase());
    if (index >= 0) title = `${title.slice(0, index)} ${title.slice(index + phrase.length)}`;
  });
  return title.replace(/\s{2,}/g, " ").replace(/^[\s,:;-]+|[\s,:;-]+$/g, "").trim() || text.trim();
}

const chipWords = { subject: "Fach", date: "Datum", block: "Block" };

function chipButton(kind, content, text, extra = "", style = "") {
  return `<button type="button" class="chip${extra}" data-chip="${kind}"${style} aria-label="${chipWords[kind]} ${esc(text)} entfernen">${content}<span class="chip-x" aria-hidden="true">${icon("x")}</span></button>`;
}

function renderChips() {
  const info = effective();
  const chips = [];
  if (info.subject) {
    const label = subject(info.subject).label;
    chips.push(chipButton("subject", esc(label), label, " subject-chip", ` style="--hue:${hueVar(info.subject)}"`));
  }
  if (info.date) {
    const text = shortDate(new Date(`${info.date}T12:00:00`));
    chips.push(chipButton("date", `${icon("calendar-days")}${esc(text)}`, text));
  }
  if (info.block) chips.push(chipButton("block", `${icon("nx-block")}${info.block}. Block`, `${info.block}. Block`));
  const markup = chips.join("");
  if (noteChips.dataset.markup !== markup) {
    noteChips.dataset.markup = markup;
    noteChips.innerHTML = markup;
  }
  const raw = noteInput.value.trim();
  const title = cleanTitle(raw, info);
  const changed = raw && title !== raw;
  notePreview.hidden = !changed;
  if (changed) notePreview.textContent = `Wird gespeichert als „${title}“`;
}

noteChips?.addEventListener("click", (event) => {
  const chip = event.target.closest("[data-chip]");
  if (!chip) return;
  dismissed.add(chip.dataset.chip);
  lastRecognized = null;
  renderChips();
  noteInput.focus();
});

noteInput?.addEventListener("input", () => {
  noteSave.disabled = !noteInput.value.trim();
  if (!noteInput.value.trim()) dismissed = new Set();
  const before = effective();
  parsed = parseNote(noteInput.value);
  const after = effective();
  lastRecognized = ["date", "block", "subject"].find((kind) => after[kind] && after[kind] !== before[kind]) || null;
  renderChips();
  if (!typeTouched && parsed.type) {
    const target = noteForm.querySelector(`input[name='type'][value='${parsed.type}']`);
    if (target && !target.checked) {
      target.checked = true;
      syncType();
    }
  }
});

noteInput?.addEventListener("keydown", (event) => {
  const atEnd = noteInput.selectionStart === noteInput.value.length && noteInput.selectionEnd === noteInput.value.length;
  if (event.key === "Backspace" && lastRecognized && atEnd) {
    event.preventDefault();
    dismissed.add(lastRecognized);
    lastRecognized = null;
    renderChips();
    return;
  }
  if (!["Shift", "Control", "Meta", "Alt"].includes(event.key)) lastRecognized = null;
});

noteForm?.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
    event.preventDefault();
    noteForm.requestSubmit();
  }
});

noteForm?.addEventListener("submit", (event) => {
  event.preventDefault();
  const raw = noteInput.value.trim();
  if (!raw) return;
  const type = noteForm.querySelector("input[name='type']:checked").value;
  const info = effective();
  const details = noteForm.querySelector("textarea[name='details']")?.value.trim() || "";
  const detail = { type, title: cleanTitle(raw, info), subject: info.subject, date: info.date, block: info.block, details };
  noteSheet.hidePopover();
  const handled = !window.dispatchEvent(new CustomEvent("app:note", { detail, cancelable: true }));
  if (!handled) saveNote(detail);
});

let lastSaveWarning = 0;

addEventListener("app:save-failed", () => {
  if (performance.now() - lastSaveWarning < 4000) return;
  lastSaveWarning = performance.now();
  toast("Das hat nicht geklappt. Die Änderung ist noch nicht gespeichert.", { icon: "circle-alert" });
});

function saveNote(detail) {
  const words = { task: "Aufgabe", homework: "Hausaufgabe", note: "Notiz", idea: "Idee" };
  const today = isoDate(now());
  let job;
  if (detail.type === "task" || (detail.type === "homework" && (!detail.date || detail.date === today))) {
    job = taskApi.create({ id: `new-${Date.now()}`, title: detail.title, subject: detail.subject, date: detail.date && detail.date > today ? detail.date : null, minutes: 20, done: false });
  } else if (detail.type === "homework") {
    job = deadlineApi.create({ id: `hw-new-${Date.now()}`, kind: "Hausaufgabe", title: detail.title, subject: detail.subject || null, date: detail.date, detail: detail.details });
  } else {
    job = noteApi.create({ type: detail.type, title: detail.title, details: detail.details });
  }
  job.then(() => toast(`${words[detail.type]} angelegt: „${esc(detail.title)}“`, { icon: "check" })).catch(() => {});
}

const weatherSheet = $("weatherSheet");
weatherSheet?.addEventListener("beforetoggle", (event) => {
  if (event.newState !== "open") return;
  const source = [lastInvoker?.closest?.("[data-open-weather]"), document.querySelector("[data-open-weather]")].find(onScreen);
  placeNear(weatherSheet, source, "left");
  window.dispatchEvent(new CustomEvent("app:weather-open"));
});
weatherSheet?.addEventListener("toggle", (event) => {
  if (event.newState === "open") clampSheet(weatherSheet);
});

export function openWeather(source) {
  lastInvoker = source || lastInvoker;
  if (!weatherSheet.matches(":popover-open")) weatherSheet.showPopover();
}

const variantMenu = $("variantMenu");
variantMenu?.addEventListener("beforetoggle", (event) => {
  if (event.newState !== "open") return;
  const button = document.querySelector(".variant-button");
  const box = button.getBoundingClientRect();
  variantMenu.style.right = `${Math.round(innerWidth - box.right)}px`;
  variantMenu.style.bottom = `${Math.round(innerHeight - box.top + 8)}px`;
  variantMenu.style.top = "auto";
  variantMenu.style.left = "auto";
});

const palette = $("palette");
const paletteInput = $("paletteInput");
const paletteResults = $("paletteResults");
const paletteStatus = $("paletteStatus");
let paletteItems = [];
let paletteIndex = 0;
const searchProviders = [];

export function registerSearch(provider) {
  searchProviders.push(provider);
}

export function setTheme(theme) {
  const mode = theme === "light" || theme === "dark" ? theme : "auto";
  if (mode === "auto") storage.remove("app-theme-choice");
  else storage.set("app-theme-choice", mode);
  const apply = () => {
    root.dataset.theme = mode === "auto" ? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light") : mode;
    root.dataset.themeMode = mode;
  };
  if (travels() && document.startViewTransition) document.startViewTransition(apply);
  else apply();
}

function baseCommands() {
  const theme = root.dataset.theme;
  const single = shortcutsEnabled();
  const noteHint = platform.electron ? `${modWord}${platform.mac ? "⌥" : "Alt+"}N` : single ? "N" : "";
  const commands = [
    { group: "Aktionen", label: "Aufgabe für heute anlegen", icon: "plus", hint: single ? "A" : "", run: () => window.dispatchEvent(new CustomEvent("app:add-task")) },
    { group: "Aktionen", label: "Schnelle Notiz", icon: "pen-tool", hint: noteHint, run: () => openNote({ instant: true }) },
    { group: "Aktionen", label: "Wetter und Heimweg", icon: "cloud", run: () => openWeather(document.querySelector("[data-open-weather]")) },
    { group: "Aktionen", label: theme === "dark" ? "Helle Darstellung" : "Dunkle Darstellung", icon: theme === "dark" ? "sun" : "moon", run: () => setTheme(theme === "dark" ? "light" : "dark") },
    { group: "Aktionen", label: "Tastaturkürzel", icon: "keyboard", hint: single ? "?" : "", run: () => $("shortcuts").showModal() },
  ];
  Object.entries(pageNames).forEach(([key, label]) => {
    if (key === "home") return;
    commands.push({ group: "Seiten", label, icon: pageIcons[key], run: () => openPage(key) });
  });
  return commands;
}

function renderPalette() {
  const query = paletteInput.value.trim().toLowerCase();
  const all = [...baseCommands(), ...searchProviders.flatMap((provider) => provider())];
  const matched = query
    ? all.filter((item) => `${item.label} ${item.keywords || ""}`.toLowerCase().includes(query))
    : all.filter((item) => item.group !== "Aufgaben" && item.group !== "Fällig");
  paletteItems = matched.slice(0, 14);
  paletteIndex = Math.min(paletteIndex, Math.max(paletteItems.length - 1, 0));
  if (paletteStatus) paletteStatus.textContent = query ? (paletteItems.length ? `${paletteItems.length} Treffer` : "Keine Treffer") : "";
  if (!paletteItems.length) {
    paletteResults.innerHTML = `<p class="palette-empty">Nichts gefunden für „${esc(paletteInput.value)}“.</p>`;
    paletteInput.removeAttribute("aria-activedescendant");
    return;
  }
  const groups = [];
  paletteItems.forEach((item, index) => {
    let group = groups[groups.length - 1];
    if (!group || group.name !== item.group) {
      group = { name: item.group, items: [] };
      groups.push(group);
    }
    group.items.push(`<div class="palette-item" role="option" id="pal-${index}" data-index="${index}" aria-selected="${index === paletteIndex}">${icon(item.icon)}<span>${esc(item.label)}</span>${item.hint ? `<small>${esc(item.hint)}</small>` : ""}</div>`);
  });
  paletteResults.innerHTML = groups
    .map((group, index) => `<div role="group" aria-labelledby="pal-group-${index}"><p class="palette-group" id="pal-group-${index}">${esc(group.name)}</p>${group.items.join("")}</div>`)
    .join("");
  paletteInput.setAttribute("aria-activedescendant", `pal-${paletteIndex}`);
  paletteResults.querySelector(`[data-index="${paletteIndex}"]`)?.scrollIntoView({ block: "nearest" });
}

export function openPalette() {
  if (palette.open) return;
  paletteInput.value = "";
  paletteIndex = 0;
  renderPalette();
  palette.showModal();
  paletteInput.focus();
}

function runPalette(index) {
  const item = paletteItems[index];
  if (!item) return;
  palette.close();
  item.run();
}

paletteInput?.addEventListener("input", () => {
  paletteIndex = 0;
  renderPalette();
});

paletteInput?.addEventListener("keydown", (event) => {
  if (!paletteItems.length) return;
  if (event.key === "ArrowDown") {
    event.preventDefault();
    paletteIndex = (paletteIndex + 1) % paletteItems.length;
    renderPalette();
  } else if (event.key === "ArrowUp") {
    event.preventDefault();
    paletteIndex = (paletteIndex - 1 + paletteItems.length) % paletteItems.length;
    renderPalette();
  } else if (event.key === "Enter") {
    event.preventDefault();
    runPalette(paletteIndex);
  }
});

paletteResults?.addEventListener("click", (event) => {
  const item = event.target.closest(".palette-item");
  if (item) runPalette(Number(item.dataset.index));
});

palette?.addEventListener("click", (event) => {
  if (event.target === palette) palette.close();
});

document.querySelectorAll("[data-open-palette]").forEach((button) => button.addEventListener("click", openPalette));

document.querySelectorAll("[data-close-dialog]").forEach((button) => button.addEventListener("click", () => button.closest("dialog").close()));
$("shortcuts")?.addEventListener("click", (event) => {
  if (event.target === $("shortcuts")) $("shortcuts").close();
});

export const typing = (target) => target.closest?.("input, textarea, select, [contenteditable='true']");

export const overlayOpen = () => !!document.querySelector("dialog[open], [popover]:popover-open:not(.variant-menu)");

document.addEventListener("keydown", (event) => {
  const key = event.key.toLowerCase();
  if (event.key === "Escape" && tooltip.classList.contains("is-on")) hideTip();
  if ((event.ctrlKey || event.metaKey) && !event.shiftKey && key === "k") {
    event.preventDefault();
    if (palette.open) palette.close();
    else openPalette();
    return;
  }
  if ((event.ctrlKey || event.metaKey) && ((event.shiftKey && key === "n") || (event.altKey && event.code === "KeyN"))) {
    event.preventDefault();
    openNote({ instant: true, source: $("noteButton") });
    return;
  }
  if ((event.ctrlKey || event.metaKey) && !event.shiftKey && key === "z" && !typing(event.target)) {
    if (runUndo()) event.preventDefault();
    return;
  }
  if (typing(event.target) || event.ctrlKey || event.metaKey || event.altKey) return;
  if (!shortcutsEnabled() || overlayOpen()) return;
  if (event.key === "?") {
    event.preventDefault();
    $("shortcuts").showModal();
  } else if (key === "n" && !event.shiftKey) {
    event.preventDefault();
    openNote({ instant: true, source: $("noteButton") });
  }
});

addEventListener("resize", () => placeIndicator(true));
for (const type of ["pageswap", "pagereveal"]) {
  addEventListener(type, (event) => {
    if (event.viewTransition && !travels()) event.viewTransition.skipTransition();
  });
}

export function initShell() {
  root.classList.toggle("is-touch", matchMedia("(pointer: coarse)").matches || matchMedia("(hover: none)").matches);
  renderKeys();
  syncShortcutToggle();
  renderCounts();
  renderSync();
  renderNotify();
  placeIndicator(true);
  document.fonts?.ready.then(() => placeIndicator(true));
}
