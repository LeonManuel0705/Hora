import {
  data, flags, params, esc, icon, tinte, now, pinnedTime, toMin, clock, hm, startOfDay, addDays, isoDate, parseDate, dayDiff, minutesOf,
  weekType, abWeeks, isoWeek, subject, hueVar, blockOf, lessonsFor, inDays, duration, shortDate, longDate, storage,
  WEEKDAYS, WEEKDAYS_SHORT, MONTHS, MONTHS_SHORT, BRAND } from "../core.js";
import { animates, travels, flipKeyed, exitInPlace, crossfade, token, ms } from "../motion.js";
import { toast, parseNote, cleanTitle, typing, shortcutsEnabled, overlayOpen, registerSearch, syncTime, pageUrl } from "../shell.js";
import { events as eventApi, debounced } from "../api.js";

const saveText = debounced(700, (key, id, changes) => eventApi.update(id, changes));

const $ = (id) => document.getElementById(id);
const extra = data.page || {};
const VIEWS = ["woche", "monat", "liste"];
const DUE_KINDS = ["Test", "Klausur", "Abgabe", "Referat"];
const LIST_DAYS = 14;
const NARROW = 440;
const FLOATING = matchMedia("(max-width: 1279px)");
const tasksLink = () => `href="${esc(pageUrl("tasks"))}" data-page="tasks"`;
const KINDS = {
  school: { label: "Schule", icon: "graduation-cap" },
  training: { label: "Training", icon: "dumbbell" },
  private: { label: "Privat", icon: "user" },
};
const NAV_WORDS = {
  woche: ["Vorherige Woche", "Nächste Woche"],
  monat: ["Vorheriger Monat", "Nächster Monat"],
  liste: ["Zwei Wochen zurück", "Zwei Wochen weiter"],
};
const ONLINE = /discord|zoom|teams|videocall|video|online|jitsi|webex|meet|https?:/i;
const TRAINING_WORDS = /\b(gym|training|schwimm\w*|laufen|joggen|fu(ß|ss)ball|tennis|kletter\w*|sport|yoga|workout|volleyball|basketball|handball|tanzen|radtour)\b/i;
const PRIVATE_WORDS = /\b(nachhilfe|arzt|zahnarzt|geburtstag|kino|party|essen|friseur|fahrstunde|konzert)\b/i;
const SCHOOL_WORDS = /\b(schule|referat\w*|abikasse|abiball|klausur|test|elternabend|konferenz|infoabend|kurs\w*|lerngruppe|projektwoche|wandertag|exkursion|studien\w*|uni|hpi)\b/i;
const WEEKDAY_WORDS = /\b(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\b/i;
const WEEKDAY_INDEX = { sonntag: 0, montag: 1, dienstag: 2, mittwoch: 3, donnerstag: 4, freitag: 5, samstag: 6 };

const holidays = (extra.holidays || []).map((item) => ({ ...item, endDate: item.endDate || item.date }));
const deadlines = flags.empty ? [] : data.deadlines.filter((item) => DUE_KINDS.includes(item.kind) && item.status !== "abgegeben");
const prepTasks = (id) => [...(data.tasks || []), ...(data.taskPool || [])].filter((task) => task.deadline === id && !task.done);

function initialView() {
  const asked = params.get("ansicht");
  if (VIEWS.includes(asked)) return asked;
  const saved = storage.get("app-cal-view");
  return VIEWS.includes(saved) ? saved : "woche";
}

const state = {
  view: initialView(),
  anchor: startOfDay(now()),
  focus: isoDate(now()),
  picked: false,
  events: [],
  loading: false,
  selected: null,
  narrow: false,
  fresh: null,
};

function load() {
  const notes = extra.notes || {};
  const seen = new Set();
  const source = flags.empty ? [] : [...data.events, ...(extra.events || [])];
  state.events = source
    .filter((item) => {
      const key = `${item.title}|${item.date}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .map((item) => ({ ...item, kind: KINDS[item.kind] ? item.kind : "private", notes: item.notes || notes[item.id] || "", synced: !!item.synced }));
}

const todayIso = () => isoDate(now());
const nowMin = () => minutesOf(now());
const mondayOf = (date) => addDays(startOfDay(date), 1 - (date.getDay() || 7));
const isTest = (item) => item.kind === "Test" || item.kind === "Klausur";
const covers = (item, iso) => item.date <= iso && iso <= (item.endDate || item.date);
const kindVar = (kind) => `var(--kind-${kind})`;
const startOf = (item) => toMin(item.start);
const endOf = (item) => (item.end ? Math.max(toMin(item.end), startOf(item) + 15) : startOf(item) + 60);
const holidaysOn = (iso) => holidays.filter((item) => covers(item, iso));
const lessonsOn = (date) => (holidaysOn(isoDate(date)).length ? [] : lessonsFor(date));
const visibleEvents = () => state.events.filter((item) => !state.loading || !item.synced);
const eventsAt = (iso) => visibleEvents().filter((item) => covers(item, iso));
const timedAt = (iso) => eventsAt(iso).filter((item) => item.start && item.date === iso).sort((a, b) => startOf(a) - startOf(b));
const allDayAt = (iso) => eventsAt(iso).filter((item) => !item.start);
const dueAt = (iso) => deadlines.filter((item) => item.date === iso).sort((a, b) => Number(isTest(b)) - Number(isTest(a)));
const plural = (count, one, many) => `${count} ${count === 1 ? one : many}`;
const monthShort = (index) => `${MONTHS_SHORT[index]}${MONTHS_SHORT[index].length < MONTHS[index].length ? "." : ""}`;
const subjectName = (key) => subject(key).name.replace(/ LK$/, "");

function isPast(item) {
  const today = todayIso();
  const last = item.endDate || item.date;
  if (last < today) return true;
  if (item.date !== today || !item.start) return false;
  return endOf(item) <= nowMin();
}

function timeText(item) {
  if (!item.start) return "ganztägig";
  return item.end ? `${hm(item.start)} bis ${hm(item.end)}` : `ab ${hm(item.start)}`;
}

function dueTime(item) {
  const block = item.block ? blockOf(item.block) : null;
  return block ? `${block.n}. Block, ${hm(block.start)} bis ${hm(block.end)}` : "ganztägig";
}

function findEntry(id) {
  const event = state.events.find((item) => item.id === id);
  if (event) return { type: "event", item: event };
  const due = deadlines.find((item) => item.id === id);
  if (due) return { type: "due", item: due };
  const holiday = holidays.find((item) => item.id === id);
  return holiday ? { type: "holiday", item: holiday } : null;
}

function period(view = state.view, anchor = state.anchor) {
  if (view === "woche") {
    const start = mondayOf(anchor);
    return { start, end: addDays(start, 6) };
  }
  if (view === "monat") {
    return { start: new Date(anchor.getFullYear(), anchor.getMonth(), 1), end: new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0) };
  }
  const start = startOfDay(anchor);
  return { start, end: addDays(start, LIST_DAYS - 1) };
}

const inPeriod = (iso, span = period()) => iso >= isoDate(span.start) && iso <= isoDate(span.end);

function schoolLine(date) {
  const iso = isoDate(date);
  const free = holidaysOn(iso)[0];
  if (free) return free.type === "ferien" ? free.title : `${free.title}, schulfrei`;
  const lessons = lessonsFor(date);
  if (!lessons.length) return "";
  const active = lessons.filter((lesson) => !lesson.cancelled);
  const cancelled = lessons.filter((lesson) => lesson.cancelled);
  if (!active.length) return "Unterricht entfällt";
  const hours = active[0].startMin === 480 ? `Schule bis ${hm(active[active.length - 1].end)}` : `Schule ${hm(active[0].start)} bis ${hm(active[active.length - 1].end)}`;
  return cancelled.length ? `${cancelled.map((lesson) => `${lesson.block}.`).join(" und ")} Block entfällt, ${hours}` : hours;
}

function countLine() {
  if (state.loading) return "Termine werden geladen";
  const today = todayIso();
  const monday = mondayOf(now());
  const week = Array.from({ length: 7 }, (_, index) => isoDate(addDays(monday, index)));
  const todayCount = eventsAt(today).length;
  const weekCount = visibleEvents().filter((item) => week.some((iso) => covers(item, iso))).length;
  if (!todayCount && !weekCount) return "Diese Woche keine Termine";
  const first = todayCount ? `${plural(todayCount, "Termin", "Termine")} heute` : "Heute keine Termine";
  return `${first}, ${weekCount} diese Woche`;
}

function rangeText() {
  const span = period();
  const { start, end } = span;
  const year = now().getFullYear();
  if (state.view === "monat") return { text: `${MONTHS[start.getMonth()]} ${start.getFullYear()}`, meta: monthMeta(span) };
  const sameMonth = start.getMonth() === end.getMonth();
  const tail = end.getFullYear() !== year ? ` ${end.getFullYear()}` : "";
  const text = sameMonth
    ? `${start.getDate()}. bis ${end.getDate()}. ${MONTHS[end.getMonth()]}${tail}`
    : `${start.getDate()}. ${monthShort(start.getMonth())} bis ${end.getDate()}. ${monthShort(end.getMonth())}${tail}`;
  if (state.view === "woche") {
    const ferien = holidays.find((item) => item.type === "ferien" && item.date <= isoDate(end) && item.endDate >= isoDate(start));
    return { text, meta: [`KW ${isoWeek(start)}`, ferien ? ferien.title : abWeeks() ? `${weekType(start)}-Woche` : ""].filter(Boolean).join(", ") };
  }
  const count = listEntries(span).reduce((sum, group) => sum + group.items.filter((entry) => entry.type === "event").length, 0);
  return { text, meta: count ? plural(count, "Termin", "Termine") : "" };
}

function monthMeta(span) {
  const first = isoDate(span.start);
  const last = isoDate(span.end);
  const events = visibleEvents().filter((item) => item.date <= last && (item.endDate || item.date) >= first).length;
  const tests = deadlines.filter((item) => isTest(item) && item.date >= first && item.date <= last).length;
  return [events ? plural(events, "Termin", "Termine") : "", tests ? plural(tests, "Test", "Tests") : ""].filter(Boolean).join(", ");
}

function hourRange(days) {
  let first = days.some((date) => lessonsOn(date).length) ? 480 : 600;
  let last = 1020;
  const today = todayIso();
  days.forEach((date) => {
    const iso = isoDate(date);
    lessonsOn(date).forEach((lesson) => {
      first = Math.min(first, lesson.startMin);
      last = Math.max(last, lesson.endMin);
    });
    state.events.filter((item) => item.start && item.date === iso).forEach((item) => {
      first = Math.min(first, startOf(item));
      last = Math.max(last, endOf(item));
    });
    const minute = nowMin();
    if (iso === today && minute >= 360 && minute <= 1380) {
      first = Math.min(first, minute - 20);
      last = Math.max(last, minute + 20);
    }
  });
  const start = Math.max(0, Math.floor(first / 60) * 60);
  const end = Math.min(1440, Math.ceil(last / 60) * 60);
  return { start, end, hours: (end - start) / 60 };
}

function layoutLanes(items) {
  const sorted = items.map((item) => ({ item, s: startOf(item), e: endOf(item), lane: 0, lanes: 1, indent: 0 })).sort((a, b) => a.s - b.s || b.e - a.e);
  let group = [];
  let groupEnd = -1;
  const settle = () => {
    const staggered = group.every((entry, index) => index === 0 || entry.s - group[index - 1].s >= 30);
    if (staggered) {
      group.forEach((entry, index) => {
        const under = group.slice(0, index).filter((other) => other.e > entry.s);
        entry.indent = under.length ? Math.min(3, Math.max(...under.map((other) => other.indent)) + 1) : 0;
      });
      return;
    }
    const lanes = [];
    group.forEach((entry) => {
      let lane = lanes.findIndex((end) => end <= entry.s);
      if (lane < 0) {
        lane = lanes.length;
        lanes.push(entry.e);
      } else {
        lanes[lane] = entry.e;
      }
      entry.lane = lane;
    });
    group.forEach((entry) => (entry.lanes = lanes.length));
  };
  sorted.forEach((entry) => {
    if (group.length && entry.s >= groupEnd) {
      settle();
      group = [];
    }
    group.push(entry);
    groupEnd = group.length === 1 ? entry.e : Math.max(groupEnd, entry.e);
  });
  if (group.length) settle();
  return sorted;
}

function dueLabel(item, { long = false } = {}) {
  const name = subject(item.subject);
  if (long) return `${item.kind} ${subjectName(item.subject)}: ${item.title}`;
  return `<span class="label-full">${esc(name.label)}</span><span class="label-short">${esc(name.short)}</span>`;
}

function dueIcon(item) {
  if (isTest(item)) return "nx-test";
  if (item.kind === "Referat") return "users";
  return "list-checks";
}

function dueTone(item) {
  const overdue = item.date < todayIso();
  if (overdue) return " is-overdue";
  return isTest(item) ? " is-test" : " is-due";
}

function chipHtml(entry, isos) {
  const { item, type } = entry;
  const from = state.narrow ? 0 : isos.indexOf(entry.from);
  const to = state.narrow ? 0 : isos.indexOf(entry.to);
  const column = state.narrow ? "2 / -1" : `${from + 2} / span ${to - from + 1}`;
  const selected = state.selected === item.id ? " is-selected" : "";
  const order = `data-order="${entry.from}|0|${type === "holiday" ? "0" : type === "due" ? "1" : "2"}"`;
  if (type === "holiday") {
    const days = dayDiff(parseDate(item.date), item.endDate) + 1;
    const label = `${item.title}, ${days > 1 ? `${shortDate(parseDate(item.date))} bis ${shortDate(parseDate(item.endDate))}` : longDate(parseDate(item.date))}`;
    const tip = state.narrow ? "" : ` data-tip="${esc(`<b>${esc(item.title)}</b>${days > 1 ? `<br>${esc(shortDate(parseDate(item.date)))} bis ${esc(shortDate(parseDate(item.endDate)))}` : ""}`)}"`;
    return `<button type="button" class="cw-chip is-holiday${selected}" style="grid-column:${column}" data-id="${esc(item.id)}" data-key="chip:${esc(item.id)}"${tip} ${order} aria-label="${esc(label)}">${icon("sun")}<span class="cw-chip-text">${esc(item.title)}</span></button>`;
  }
  if (type === "due") {
    const overdue = item.date < todayIso();
    const label = `${dueLabel(item, { long: true })}, ${dueTime(item)}${overdue ? ", überfällig" : ""}`;
    const text = state.narrow ? `<span class="cw-chip-text">${esc(item.kind)} ${esc(subjectName(item.subject))}: ${esc(item.title)}</span>` : `<span class="cw-chip-text">${dueLabel(item)}</span>`;
    return `<button type="button" class="cw-chip${dueTone(item)}${selected}" style="grid-column:${column};--hue:${hueVar(item.subject)}" data-id="${esc(item.id)}" data-key="chip:${esc(item.id)}" data-tip="${esc(`<b>${esc(item.kind)} ${esc(subjectName(item.subject))}</b>: ${esc(item.title)}${item.block ? `, ${item.block}. Block` : ""}${overdue ? "<br>überfällig" : ""}`)}" ${order} aria-label="${esc(label)}">${icon(dueIcon(item))}${text}</button>`;
  }
  const past = isPast(item) ? " is-past" : "";
  const tip = state.narrow ? "" : ` data-tip="${esc(`<b>${esc(item.title)}</b><br>ganztägig${item.place ? `, ${esc(item.place)}` : ""}`)}"`;
  return `<button type="button" class="cw-chip is-event${past}${selected}" style="grid-column:${column};--k:${kindVar(item.kind)}" data-id="${esc(item.id)}" data-key="chip:${esc(item.id)}" data-flip="chip:${esc(item.id)}"${tip} ${order} aria-label="${esc(`${item.title}, ganztägig${item.place ? `, ${item.place}` : ""}`)}"><span class="cw-chip-text" data-title-of="${esc(item.id)}">${esc(item.title)}</span></button>`;
}

function allDayEntries(isos) {
  const first = isos[0];
  const last = isos[isos.length - 1];
  const clip = (item) => ({ from: item.date < first ? first : item.date, to: (item.endDate || item.date) > last ? last : item.endDate || item.date });
  return [
    ...holidays.filter((item) => item.date <= last && item.endDate >= first).map((item) => ({ type: "holiday", item, ...clip(item) })),
    ...deadlines.filter((item) => item.date >= first && item.date <= last).sort((a, b) => Number(isTest(b)) - Number(isTest(a))).map((item) => ({ type: "due", item, from: item.date, to: item.date })),
    ...visibleEvents().filter((item) => !item.start && item.date <= last && (item.endDate || item.date) >= first).map((item) => ({ type: "event", item, ...clip(item) })),
  ];
}

function dayHead(date) {
  const iso = isoDate(date);
  const today = iso === todayIso();
  const focus = iso === state.focus;
  const count = eventsAt(iso).length;
  const tests = dueAt(iso).filter(isTest).length;
  const weekend = date.getDay() === 0 || date.getDay() === 6;
  const label = `${longDate(date)}${today ? ", heute" : ""}, ${count ? plural(count, "Termin", "Termine") : "keine Termine"}${tests ? `, ${plural(tests, "Test", "Tests")}` : ""}`;
  const shown = focus && (state.picked || state.narrow);
  const dots = state.narrow ? `<span class="cw-dots" aria-hidden="true">${dotsFor(iso, 3)}</span>` : "";
  return `<button type="button" class="cw-day${today ? " is-today" : ""}${shown ? " is-focus" : ""}${weekend ? " is-weekend" : ""}" data-day="${iso}" data-key="day:${iso}" tabindex="${focus ? 0 : -1}" aria-pressed="${shown}" aria-label="${esc(label)}"${today ? ' aria-current="date"' : ""}>
    <span class="cw-dow" aria-hidden="true">${WEEKDAYS_SHORT[date.getDay()]}</span><span class="cw-num" aria-hidden="true">${date.getDate()}</span>${dots}
  </button>`;
}

function dotsFor(iso, limit) {
  const dots = [
    ...dueAt(iso).map((item) => `<i class="cal-dot${item.date < todayIso() || isTest(item) ? " is-urgent" : ""}" style="--k:${hueVar(item.subject)}"></i>`),
    ...eventsAt(iso).sort((a, b) => (a.start || "").localeCompare(b.start || "")).map((item) => `<i class="cal-dot is-event" style="--k:${kindVar(item.kind)}"></i>`),
  ];
  return dots.slice(0, limit).join("");
}

function lessonBand(lesson, date, pos, len) {
  const info = subject(lesson.subject);
  const iso = isoDate(date);
  const test = deadlines.find((item) => isTest(item) && item.date === iso && item.block === lesson.block);
  const tip = `${lesson.block}. Block, ${hm(lesson.start)} bis ${hm(lesson.end)}: <b>${esc(info.name)}</b> in ${esc(lesson.room)}${lesson.movedFrom ? ` statt ${esc(lesson.movedFrom)}` : ""}, ${esc(lesson.teacher)}${test ? `<br>${esc(test.kind)}: ${esc(test.title)}` : ""}${lesson.cancelled ? "<br>Entfällt" : ""}`;
  const room = lesson.cancelled ? "entfällt" : `${esc(lesson.room)}${state.narrow ? `, ${esc(lesson.teacher)}` : ""}`;
  return `<div class="cw-lesson${lesson.cancelled ? " is-cancelled" : ""}${lesson.movedFrom ? " is-moved" : ""}" style="--top:${pos(lesson.startMin)};--len:${len(lesson.startMin, lesson.endMin)};--hue:${hueVar(lesson.subject)}" data-tip="${esc(tip)}" aria-hidden="true">
    <span class="cw-lesson-label"><span class="label-full">${esc(info.label)}</span><span class="label-short">${esc(info.short)}</span></span>
    <span class="cw-lesson-room">${room}</span>${test ? `<span class="cw-lesson-flag">${esc(test.kind)}</span>` : ""}
  </div>`;
}

function eventCard(entry, pos, len) {
  const { item, s, e } = entry;
  const size = e - s < 50 ? "is-short" : e - s < 90 ? "is-medium" : "";
  const label = `${item.title}, ${timeText(item)}${item.place ? `, ${item.place}` : ""}, ${KINDS[item.kind].label}`;
  const detail = state.narrow ? `${timeText(item)}${item.place ? `, ${esc(item.place)}` : ""}` : hm(item.start);
  const place = !state.narrow && !size && item.place ? `<span class="ev-place">${esc(item.place)}</span>` : "";
  const tip = state.narrow ? "" : ` data-tip="${esc(`<b>${esc(item.title)}</b><br>${esc(timeText(item))}${item.place ? `, ${esc(item.place)}` : ""}`)}"`;
  const classes = ["ev", isPast(item) ? "is-past" : "", state.narrow ? "is-wrap" : size || "is-tall", entry.indent ? "is-stacked" : "", state.selected === item.id ? "is-selected" : ""].filter(Boolean).join(" ");
  return `<button type="button" class="${classes}" data-id="${esc(item.id)}" data-key="ev:${esc(item.id)}" data-flip="ev:${esc(item.id)}" data-order="${item.date}|1|${item.start}" style="--top:${pos(s)};--len:${len(s, e)};--lane:${entry.lane};--lanes:${entry.lanes};--indent:${entry.indent};--k:${kindVar(item.kind)}"${tip} aria-label="${esc(label)}">
    <span class="ev-title" data-title-of="${esc(item.id)}">${esc(item.title)}</span><span class="ev-time">${detail}</span>${place}
  </button>`;
}

function schoolSummary(date, lessons) {
  const line = schoolLine(date);
  if (!lessons.length) return line || "Kein Unterricht";
  const names = lessons.filter((lesson) => !lesson.cancelled).map((lesson) => `${lesson.block}. Block ${subject(lesson.subject).name}`).join(", ");
  return `${line}. ${names}`;
}

function weekColumn(date, range) {
  const iso = isoDate(date);
  const today = iso === todayIso();
  const pos = (minute) => ((minute - range.start) / 60).toFixed(4);
  const len = (from, to) => ((to - from) / 60).toFixed(4);
  const lessons = lessonsOn(date);
  const events = layoutLanes(timedAt(iso));
  const minute = nowMin();
  const line = today && minute >= range.start && minute <= range.end ? `<div class="cw-now" style="--top:${pos(minute)}" aria-hidden="true"></div>` : "";
  const weekend = date.getDay() === 0 || date.getDay() === 6;
  return `<div class="cw-col${today ? " is-today" : ""}${weekend ? " is-weekend" : ""}" data-day="${iso}" role="group" aria-label="${esc(longDate(date))}${today ? ", heute" : ""}">
    <p class="visually-hidden">${esc(schoolSummary(date, lessons))}</p>
    ${lessons.map((lesson) => lessonBand(lesson, date, pos, len)).join("")}
    ${events.map((entry) => eventCard(entry, pos, len)).join("")}${line}
  </div>`;
}

function loadingHtml(inline = false) {
  return `<div class="loading-card cal-loading${inline ? " is-inline" : ""}" role="status">${tinte("laedt", 96)}<div><p class="empty-title">Hole Termine aus dem Google-Kalender</p><p class="empty-text">Dauert nur einen Moment.</p></div></div>`;
}

function nextEntryAfter(iso) {
  const candidates = [
    ...visibleEvents().filter((item) => item.date > iso),
    ...deadlines.filter((item) => item.date > iso),
  ].sort((a, b) => a.date.localeCompare(b.date));
  return candidates[0] || null;
}

function emptyHtml(title, span) {
  const next = nextEntryAfter(isoDate(span.end));
  const hour = minutesOf(now()) / 60;
  const kind = hour >= 21 || hour < 5 ? "schlaeft" : "ruhe";
  const action = next
    ? `<button type="button" class="empty-action" data-jump="${next.date}">Nächster Termin am ${esc(shortDate(parseDate(next.date)))}${icon("chevron-right")}</button>`
    : `<p class="empty-text">Neue Termine legst du oben an.</p>`;
  return `<div class="empty-state cal-empty">${tinte(kind)}<p class="empty-title">${esc(title)}</p>${action}</div>`;
}

function renderWeek() {
  const span = period();
  const days = Array.from({ length: 7 }, (_, index) => addDays(span.start, index));
  const isos = days.map(isoDate);
  const range = hourRange(days);
  const shownDays = state.narrow ? days.filter((date) => isoDate(date) === state.focus) : days;
  const entries = allDayEntries(isos).filter((entry) => !state.narrow || (entry.from <= state.focus && entry.to >= state.focus));
  const busy = isos.some((iso) => eventsAt(iso).length || dueAt(iso).length);
  const head = `<div class="cw-head" role="group" aria-label="Tage der Woche"><span class="cw-gutter" aria-hidden="true"></span>${days.map(dayHead).join("")}</div>`;
  const allDay = entries.length ? `<div class="cw-allday" role="group" aria-label="Ganztägig">${entries.map((entry) => chipHtml(entry, isos)).join("")}</div>` : "";
  if (!busy && !state.loading) {
    const ferien = holidays.find((item) => item.type === "ferien" && item.date <= isos[6] && item.endDate >= isos[0]);
    return `<div class="cw is-empty${state.narrow ? " is-narrow" : ""}">${head}${allDay}${emptyHtml(ferien ? `${ferien.title}, keine Termine.` : "Keine Termine in dieser Woche.", span)}</div>`;
  }
  const minute = nowMin();
  const todayShown = shownDays.some((date) => isoDate(date) === todayIso()) && minute >= range.start && minute <= range.end;
  const hours = Array.from({ length: range.hours + 1 }, (_, index) => range.start + index * 60);
  const labels = hours.map((value, index) => `<li style="--i:${index}"${todayShown && Math.abs(value - minute) < 20 ? ' class="is-covered"' : ""}>${clock(value === 1440 ? 0 : value)}</li>`).join("");
  const nowLabel = todayShown ? `<li class="cw-now-label" style="--i:${((minute - range.start) / 60).toFixed(4)}">${clock(minute)}</li>` : "";
  return `<div class="cw${state.narrow ? " is-narrow" : ""}" style="--hours:${range.hours}">
    ${state.loading ? loadingHtml() : ""}${head}${allDay}
    <div class="cw-body">
      <ol class="cw-hours" aria-hidden="true">${labels}${nowLabel}</ol>
      ${shownDays.map((date) => weekColumn(date, range)).join("")}
    </div>
  </div>`;
}

function monthItems(iso, date) {
  const items = [];
  holidaysOn(iso).forEach((item) => {
    if (item.type === "feiertag" || item.date === iso || date.getDay() === 1) items.push({ type: "holiday", item });
  });
  dueAt(iso).forEach((item) => items.push({ type: "due", item }));
  allDayAt(iso).forEach((item) => items.push({ type: "event", item }));
  timedAt(iso).forEach((item) => items.push({ type: "event", item }));
  return items;
}

function monthItemHtml({ type, item }) {
  if (type === "holiday") return `<span class="cm-item is-holiday" data-tip="${esc(`<b>${esc(item.title)}</b>`)}">${esc(item.title)}</span>`;
  if (type === "due") {
    const tip = `<b>${esc(item.kind)} ${esc(subjectName(item.subject))}</b>: ${esc(item.title)}${item.block ? `, ${item.block}. Block` : ""}`;
    return `<span class="cm-item${dueTone(item)}" data-item="${esc(item.id)}" data-tip="${esc(tip)}" style="--hue:${hueVar(item.subject)}">${icon(dueIcon(item))}<span class="cm-text">${esc(subject(item.subject).label)}</span></span>`;
  }
  const tip = `<b>${esc(item.title)}</b><br>${esc(timeText(item))}${item.place ? `, ${esc(item.place)}` : ""}`;
  return `<span class="cm-item is-event${isPast(item) ? " is-past" : ""}${state.selected === item.id ? " is-selected" : ""}" data-item="${esc(item.id)}" data-flip="cm:${esc(item.id)}" data-tip="${esc(tip)}" style="--k:${kindVar(item.kind)}"><i class="cal-dot"></i>${item.start ? `<span class="cm-time">${hm(item.start)}</span>` : ""}<span class="cm-text" data-title-of="${esc(item.id)}">${esc(item.title)}</span></span>`;
}

function monthLabel(date, iso, items) {
  const parts = [longDate(date)];
  if (iso === todayIso()) parts.push("heute");
  holidaysOn(iso).forEach((item) => parts.push(item.title));
  const events = eventsAt(iso);
  const due = dueAt(iso);
  due.forEach((item) => parts.push(`${item.kind} ${subjectName(item.subject)}`));
  if (events.length) parts.push(`${plural(events.length, "Termin", "Termine")}: ${events.map((item) => `${item.start ? `${hm(item.start)} ` : ""}${item.title}`).join(", ")}`);
  else if (!due.length && !items.length) parts.push("keine Termine");
  return parts.join(", ");
}

function renderMonth() {
  const span = period();
  const start = mondayOf(span.start);
  const weeks = Math.ceil((dayDiff(start, isoDate(span.end)) + 1) / 7);
  const month = span.start.getMonth();
  const limit = 3;
  let rows = "";
  for (let week = 0; week < weeks; week += 1) {
    let cells = "";
    for (let day = 0; day < 7; day += 1) {
      const date = addDays(start, week * 7 + day);
      const iso = isoDate(date);
      const items = monthItems(iso, date);
      const today = iso === todayIso();
      const focus = iso === state.focus;
      const free = holidaysOn(iso).length > 0;
      const outside = date.getMonth() !== month;
      const shown = state.narrow
        ? `<span class="cm-dots">${dotsFor(iso, 3)}</span>`
        : `<span class="cm-items">${(items.length > limit ? items.slice(0, limit - 1) : items).map(monthItemHtml).join("")}${items.length > limit ? `<span class="cm-more">${items.length - limit + 1} weitere</span>` : ""}</span>`;
      cells += `<td class="cm-cell${outside ? " is-outside" : ""}${free ? " is-free" : ""}${day >= 5 ? " is-weekend" : ""}">
        <button type="button" class="cm-day${today ? " is-today" : ""}${focus && state.picked ? " is-focus" : ""}" data-day="${iso}" data-key="day:${iso}" data-order="${iso}" tabindex="${focus ? 0 : -1}" aria-pressed="${focus && state.picked}" aria-label="${esc(monthLabel(date, iso, items))}"${today ? ' aria-current="date"' : ""}>
          <span class="cm-num" aria-hidden="true">${date.getDate()}</span>
          <span class="cm-body" aria-hidden="true">${shown}</span>
        </button>
      </td>`;
    }
    rows += `<tr>${cells}</tr>`;
  }
  const head = [1, 2, 3, 4, 5, 6, 0].map((dow) => `<th scope="col" abbr="${WEEKDAYS[dow]}">${WEEKDAYS_SHORT[dow]}</th>`).join("");
  return `<div class="cm-wrap">${state.loading ? loadingHtml() : ""}<table class="cm${state.narrow ? " is-narrow" : ""}" aria-label="${MONTHS[month]} ${span.start.getFullYear()}"><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table></div>`;
}

function listEntries(span) {
  const groups = [];
  const first = isoDate(span.start);
  for (let index = 0; index < LIST_DAYS; index += 1) {
    const date = addDays(span.start, index);
    const iso = isoDate(date);
    const items = [
      ...holidaysOn(iso).filter((item) => item.date === iso || iso === first).map((item) => ({ type: "holiday", item })),
      ...dueAt(iso).map((item) => ({ type: "due", item })),
      ...eventsAt(iso).filter((item) => !item.start && (item.date === iso || iso === first)).map((item) => ({ type: "event", item })),
      ...timedAt(iso).map((item) => ({ type: "event", item })),
    ];
    if (items.length) groups.push({ date, iso, items });
  }
  return groups;
}

function groupTitle(date) {
  const diff = dayDiff(startOfDay(now()), isoDate(date));
  const meta = `${date.getDate()}.${date.getMonth() + 1}.`;
  if (diff === 0) return { title: "Heute", meta: shortDate(date) };
  if (diff === 1) return { title: "Morgen", meta: shortDate(date) };
  if (diff === -1) return { title: "Gestern", meta: shortDate(date) };
  return { title: WEEKDAYS[date.getDay()], meta };
}

function listRow({ type, item }) {
  const selected = state.selected === item.id ? " is-selected" : "";
  const base = `data-id="${esc(item.id)}" data-key="row:${esc(item.id)}" data-flip="row:${esc(item.id)}" data-order="${item.date}"`;
  if (type === "holiday") {
    const days = dayDiff(parseDate(item.date), item.endDate) + 1;
    const meta = days > 1 ? `bis ${shortDate(parseDate(item.endDate))}, ${plural(days, "Tag", "Tage")}` : "schulfrei";
    return `<li><button type="button" class="cl-row is-holiday${selected}" ${base}>
      <span class="cl-time"><span class="cl-icon">${icon("sun")}</span></span>
      <span class="cl-main"><span class="cl-title">${esc(item.title)}</span><span class="cl-meta">${esc(meta)}</span></span>${icon("chevron-right", "chev-end")}
    </button></li>`;
  }
  if (type === "due") {
    const block = item.block ? blockOf(item.block) : null;
    const overdue = item.date < todayIso();
    const lesson = item.block ? lessonsFor(parseDate(item.date)).find((entry) => entry.block === item.block) : null;
    const meta = [`<i class="subject-dot" style="--hue:${hueVar(item.subject)}"></i>${esc(subject(item.subject).label)}`, block ? `${block.n}. Block` : "", lesson ? esc(lesson.room) : "", overdue ? `<span class="cl-urgent">überfällig</span>` : ""].filter(Boolean).join(", ");
    return `<li><button type="button" class="cl-row is-due${isTest(item) ? " is-test" : ""}${selected}" ${base}>
      <span class="cl-time">${block ? `<b>${hm(block.start)}</b><small>${hm(block.end)}</small>` : `<span class="cl-icon">${icon(dueIcon(item))}</span>`}</span>
      <span class="cl-main"><span class="cl-title">${isTest(item) ? icon("nx-test") : ""}${esc(item.kind)}: ${esc(item.title)}</span><span class="cl-meta">${meta}</span></span>${icon("chevron-right", "chev-end")}
    </button></li>`;
  }
  const meta = `<i class="cal-dot" style="--k:${kindVar(item.kind)}"></i>${esc(KINDS[item.kind].label)}${item.place ? `, ${esc(item.place)}` : ""}`;
  return `<li><button type="button" class="cl-row is-event${isPast(item) ? " is-past" : ""}${selected}" ${base} style="--k:${kindVar(item.kind)}">
    <span class="cl-time">${item.start ? `<b>${hm(item.start)}</b>${item.end ? `<small>${hm(item.end)}</small>` : ""}` : `<small>ganztägig</small>`}</span>
    <span class="cl-main"><span class="cl-title" data-title-of="${esc(item.id)}">${esc(item.title)}</span><span class="cl-meta">${meta}</span></span>${icon("chevron-right", "chev-end")}
  </button></li>`;
}

function renderList() {
  const span = period();
  const groups = listEntries(span);
  const loading = state.loading ? loadingHtml(true) : "";
  if (!groups.length) return loading + (state.loading ? "" : emptyHtml(`Keine Termine bis ${shortDate(span.end)}`, span));
  return `${loading}<div class="cl">${groups.map((group) => {
    const label = groupTitle(group.date);
    const school = schoolLine(group.date);
    return `<section class="cl-group" aria-labelledby="cl-${group.iso}">
      <h3 class="group-head" id="cl-${group.iso}" data-flip="head:${group.iso}"><span>${esc(label.title)}</span><small>${esc(label.meta)}</small>${school ? `<small class="group-effort">${esc(school)}</small>` : ""}</h3>
      <ul class="cl-rows">${group.items.map(listRow).join("")}</ul>
    </section>`;
  }).join("")}</div>`;
}

function viewHtml() {
  if (state.view === "monat") return renderMonth();
  if (state.view === "liste") return renderList();
  return renderWeek();
}

function agendaItem({ type, item }) {
  const selected = state.selected === item.id ? " is-selected" : "";
  if (type === "holiday") {
    return `<li><button type="button" class="cal-agenda-item is-holiday${selected}" data-id="${esc(item.id)}" data-key="ag:${esc(item.id)}"><span class="cal-agenda-time">${icon("sun")}</span><span class="cal-agenda-main"><span class="cal-agenda-title">${esc(item.title)}</span></span></button></li>`;
  }
  if (type === "due") {
    const block = item.block ? blockOf(item.block) : null;
    return `<li><button type="button" class="cal-agenda-item is-due${isTest(item) ? " is-test" : ""}${selected}" data-id="${esc(item.id)}" data-key="ag:${esc(item.id)}"><span class="cal-agenda-time">${block ? hm(block.start) : icon(dueIcon(item))}</span><span class="cal-agenda-main"><span class="cal-agenda-title">${esc(item.kind)} ${esc(subjectName(item.subject))}</span><span class="cal-agenda-meta">${esc(item.title)}</span></span></button></li>`;
  }
  return `<li><button type="button" class="cal-agenda-item${isPast(item) ? " is-past" : ""}${selected}" data-id="${esc(item.id)}" data-key="ag:${esc(item.id)}" style="--k:${kindVar(item.kind)}"><span class="cal-agenda-time">${item.start ? hm(item.start) : "ganztägig"}</span><span class="cal-agenda-main"><span class="cal-agenda-title"><i class="cal-dot"></i><span data-title-of="${esc(item.id)}">${esc(item.title)}</span></span>${item.place ? `<span class="cal-agenda-meta">${esc(item.place)}</span>` : ""}</span></button></li>`;
}

function nextTest() {
  const today = todayIso();
  return deadlines.filter((item) => isTest(item) && item.date >= today).sort((a, b) => a.date.localeCompare(b.date))[0] || null;
}

function renderOverview() {
  const iso = state.picked ? state.focus : todayIso();
  const date = parseDate(iso);
  const diff = dayDiff(startOfDay(now()), iso);
  const near = Math.abs(diff) <= 1;
  const title = diff === 0 ? "Heute" : diff === 1 ? "Morgen" : diff === -1 ? "Gestern" : longDate(date);
  const meta = [near ? shortDate(date) : "", schoolLine(date)].filter(Boolean).join(", ");
  const items = [
    ...holidaysOn(iso).map((item) => ({ type: "holiday", item })),
    ...dueAt(iso).map((item) => ({ type: "due", item })),
    ...allDayAt(iso).map((item) => ({ type: "event", item })),
    ...timedAt(iso).map((item) => ({ type: "event", item })),
  ];
  const agenda = state.loading && !items.length
    ? `<p class="cal-agenda-empty">Termine werden geladen.</p>`
    : items.length ? `<ol class="cal-agenda">${items.map(agendaItem).join("")}</ol>` : `<p class="cal-agenda-empty">${diff === 0 ? "Heute stehen keine Termine an." : "Keine Termine an diesem Tag."}</p>`;
  const back = diff !== 0 ? `<button type="button" class="text-button cal-back" data-back-today>${icon("calendar-days")}Zurück zu heute</button>` : "";
  const test = nextTest();
  let testHtml = "";
  if (test) {
    const block = test.block ? `, ${test.block}. Block` : "";
    const open = prepTasks(test.id).length;
    testHtml = `<div class="cal-next">
      <h3 class="cal-next-label">Nächster Test</h3>
      <button type="button" class="cal-next-card${state.selected === test.id ? " is-selected" : ""}" data-id="${esc(test.id)}" data-key="next:${esc(test.id)}">
        <span class="cal-next-title"><i class="subject-dot" style="--hue:${hueVar(test.subject)}"></i>${esc(subjectName(test.subject))}</span>
        <span class="cal-next-topic">${esc(test.title)}</span>
        <span class="cal-next-when">${esc(shortDate(parseDate(test.date)))}${block}, ${esc(inDays(dayDiff(startOfDay(now()), test.date)))}</span>
      </button>
      ${open ? `<a class="cal-next-prep" ${tasksLink()}>${plural(open, "Aufgabe", "Aufgaben")} zur Vorbereitung offen${icon("chevron-right")}</a>` : ""}
    </div>`;
  }
  $("calOverview").innerHTML = `<div class="cal-overview-body"><div class="cal-overview-day"><h2 class="side-title" id="calOverviewTitle">${esc(title)}</h2>
    ${meta ? `<p class="side-meta">${esc(meta)}</p>` : ""}${agenda}${back}</div>${testHtml}</div>`;
}

function routeLink(place) {
  if (!place || ONLINE.test(place)) return "";
  return `<a class="cal-route" id="calRoute" href="${esc(pageUrl("vbb", `/fahrplan?nach=${encodeURIComponent(place)}`))}" data-page="vbb">${icon("route")}Route planen</a>`;
}

function whenNote(item) {
  if (!item.start) return "";
  if (!item.end) return `Ab ${hm(item.start)}, Ende offen`;
  return duration(endOf(item) - startOf(item)).replace(/\u00a0/g, " ");
}

function normalizeTime(value) {
  const match = value.trim().match(/^(\d{1,2})(?:[:.]?(\d{2}))?(?:\s*uhr)?$/i);
  if (!match) return undefined;
  const hours = Number(match[1]);
  const minutes = Number(match[2] || 0);
  if (hours > 23 || minutes > 59) return undefined;
  return `${pad(hours)}:${pad(minutes)}`;
}

function panelHead(markClass, markIcon, title, { editable = false, deletable = false, style = "" } = {}) {
  const heading = editable
    ? `<textarea class="panel-title" id="calPanelTitle" rows="1" aria-label="Titel">${esc(title)}</textarea>`
    : `<h2 class="panel-title is-static" id="calPanelTitle">${esc(title)}</h2>`;
  return `<div class="panel-head">
    <span class="cal-mark ${markClass}"${style}>${icon(markIcon)}</span>
    ${heading}
    <div class="panel-tools">
      ${deletable ? `<button class="icon-button is-danger" type="button" data-panel-delete aria-label="Termin löschen" data-tip="Löschen">${icon("trash-2")}</button>` : ""}
      <button class="icon-button" type="button" data-panel-close aria-label="Details schließen" data-tip="Schließen">${icon("x")}</button>
    </div>
  </div>`;
}

function panelEvent(item) {
  const locked = item.synced ? " disabled" : "";
  return `${panelHead("is-event", KINDS[item.kind].icon, item.title, { editable: !item.synced, deletable: !item.synced, style: ` style="--k:${kindVar(item.kind)}"` })}
    <div class="panel-fields">
      <div class="field">
        <span class="field-label" id="calTimeLabel">Zeit</span>
        <div class="cal-when" role="group" aria-labelledby="calTimeLabel">
          <button type="button" class="pill cal-date-pill" data-date-pick${locked} aria-label="Datum ändern, ${esc(longDate(parseDate(item.date)))}">${icon("calendar-days")}<span id="calDateText">${esc(shortDate(parseDate(item.date)))}</span></button>
          <input class="date-proxy" type="date" id="calPanelDate" value="${esc(item.date)}" tabindex="-1" aria-hidden="true">
          <span class="cal-when-times">
            <input class="field-control cal-time" id="calPanelStart"${locked} value="${item.start ? hm(item.start) : ""}" placeholder="ganztägig" inputmode="numeric" maxlength="5" autocomplete="off" aria-label="Beginn, zum Beispiel 16:30" aria-describedby="calWhenNote">
            <span class="cal-when-to" aria-hidden="true">bis</span>
            <input class="field-control cal-time" id="calPanelEnd" value="${item.end ? hm(item.end) : ""}" placeholder="offen" inputmode="numeric" maxlength="5" autocomplete="off" aria-label="Ende, zum Beispiel 17:45"${item.start && !item.synced ? "" : " disabled"}>
          </span>
        </div>
        <p class="cal-when-note" id="calWhenNote" aria-live="polite">${esc(whenNote(item))}</p>
      </div>
      <div class="field">
        <label class="field-label" for="calPanelPlace">Ort</label>
        <input class="field-control" id="calPanelPlace"${locked} value="${esc(item.place || "")}" placeholder="Wo findet es statt?" autocomplete="off">
        <div class="cal-route-slot" id="calRouteSlot">${routeLink(item.place)}</div>
      </div>
      <div class="field">
        <span class="field-label" id="calKindLabel">Art</span>
        <div class="field-body" role="group" aria-labelledby="calKindLabel">${Object.entries(KINDS).map(([key, kind]) => `<button type="button" class="pill cal-kind" data-kind="${key}"${locked} aria-pressed="${item.kind === key}" style="--k:${kindVar(key)}"><i class="cal-dot"></i>${kind.label}</button>`).join("")}</div>
      </div>
      <label class="field"><span class="field-label">Notizen</span><textarea class="field-control" id="calPanelNotes"${locked} rows="3" placeholder="Was du mitbringen oder vorbereiten willst">${esc(item.notes || "")}</textarea></label>
      <p class="panel-source">${icon("calendar-days")}${item.synced ? `Aus ${esc(item.source || "einem verbundenen Kalender")}, dort änderbar` : `Eigener Termin in ${BRAND}`}</p>
    </div>`;
}

function panelDue(item) {
  const date = parseDate(item.date);
  const lesson = item.block ? lessonsFor(date).find((entry) => entry.block === item.block) : null;
  const open = prepTasks(item.id);
  const overdue = item.date < todayIso();
  const tone = overdue || isTest(item) ? " is-urgent" : "";
  const facts = [
    ["Art", `<i class="subject-dot" style="--hue:${hueVar(item.subject)}"></i>${esc(item.kind)}, ${esc(subject(item.subject).name)}`],
    ["Zeit", `${esc(longDate(date))}${item.block ? `<br>${esc(dueTime(item))}` : ""}${overdue ? `<br><b class="cal-urgent">überfällig seit ${esc(shortDate(date))}</b>` : ""}`],
    lesson ? ["Raum", `${esc(lesson.room)}, ${esc(lesson.teacher)}`] : null,
    item.detail ? ["Hinweis", esc(item.detail)] : null,
    open.length ? ["Vorbereitung", `<a class="cal-link" ${tasksLink()}>${plural(open.length, "Aufgabe", "Aufgaben")} offen${icon("chevron-right")}</a>`] : null,
  ];
  return `${panelHead(`is-due${tone}`, dueIcon(item), item.title)}
    ${factsHtml(facts)}
    <p class="panel-source">${icon("graduation-cap")}Unter Schule eingetragen</p>`;
}

function factsHtml(facts) {
  return `<dl class="cal-facts">${facts.filter(Boolean).map(([label, value]) => `<div><dt>${label}</dt><dd>${value}</dd></div>`).join("")}</dl>`;
}

function panelHoliday(item) {
  const days = dayDiff(parseDate(item.date), item.endDate) + 1;
  const when = days > 1 ? `${shortDate(parseDate(item.date))} bis ${shortDate(parseDate(item.endDate))}, ${plural(days, "Tag", "Tage")}` : longDate(parseDate(item.date));
  return `${panelHead("is-holiday", "sun", item.title)}
    ${factsHtml([["Zeit", esc(when)], ["Schule", "unterrichtsfrei"]])}
    <p class="panel-source">${icon("calendar-days")}${item.type === "ferien" ? "Schulferien" : "Feiertage"} ${esc(extra.region || "")}</p>`;
}

function renderPanel() {
  const entry = findEntry(state.selected);
  const panel = $("calPanel");
  if (!entry) return;
  panel.setAttribute("aria-label", entry.item.title);
  panel.innerHTML = entry.type === "event" ? panelEvent(entry.item) : entry.type === "due" ? panelDue(entry.item) : panelHoliday(entry.item);
}

function markSelected() {
  document.querySelectorAll("#calView [data-id], #calView [data-item], #calOverview [data-id]").forEach((node) => {
    node.classList.toggle("is-selected", (node.dataset.id || node.dataset.item) === state.selected);
  });
}

function openItem(id, { keyboard = false, reveal = false } = {}) {
  const entry = findEntry(id);
  if (!entry) return;
  if (reveal && !inPeriod(entry.item.date)) {
    revealDate(entry.item.date);
    render({ fade: true });
  }
  const opening = state.selected == null;
  state.selected = id;
  renderPanel();
  const panel = $("calPanel");
  panel.hidden = false;
  $("calendarPage").classList.add("has-panel");
  syncOverview();
  markSelected();
  if (opening && animates()) {
    const sheet = matchMedia("(max-width: 1100px)").matches;
    const frames = travels()
      ? [{ opacity: 0, transform: sheet ? "translateY(16px)" : "translateX(12px)" }, { opacity: 1, transform: "none" }]
      : [{ opacity: 0 }, { opacity: 1 }];
    panel.animate(frames, { duration: sheet ? ms("--dur-sheet-in") || 240 : 240, easing: token("--ease-out") });
  }
  if (keyboard) panel.focus({ preventScroll: true });
}

function closePanel({ refocus = false } = {}) {
  const id = state.selected;
  state.selected = null;
  $("calPanel").hidden = true;
  $("calendarPage").classList.remove("has-panel");
  syncOverview();
  markSelected();
  if (refocus && id) {
    const date = findEntry(id)?.item.date;
    const target = document.querySelector(`#calView [data-id="${CSS.escape(id)}"], #calOverview [data-id="${CSS.escape(id)}"]`) || (date && document.querySelector(`#calView [data-key="day:${date}"]`));
    target?.focus({ preventScroll: true });
  }
}

function syncOverview() {
  $("calOverview").hidden = state.selected != null && !FLOATING.matches;
}

function holdFocus(paint) {
  const active = document.activeElement;
  const key = active?.closest?.("[data-key]")?.dataset.key;
  paint();
  if (!key || active.isConnected) return;
  document.querySelector(`[data-key="${CSS.escape(key)}"]`)?.focus({ preventScroll: true });
}

function renderChrome() {
  $("calViews").querySelectorAll("[data-view]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.view === state.view)));
  const range = rangeText();
  $("calRangeText").textContent = range.text;
  $("calRangeMeta").textContent = range.meta;
  const [back, forward] = NAV_WORDS[state.view];
  $("calPrev").setAttribute("aria-label", back);
  $("calPrev").dataset.tip = back;
  $("calNext").setAttribute("aria-label", forward);
  $("calNext").dataset.tip = forward;
  $("calCount").textContent = countLine();
  $("calToday").setAttribute("aria-label", `Heute, ${longDate(now())}`);
}

function slideIn(direction) {
  const view = $("calView");
  if (!animates()) return;
  const frames = travels()
    ? [{ opacity: 0, transform: `translateX(${direction * 20}px)` }, { opacity: 1, transform: "none" }]
    : [{ opacity: 0 }, { opacity: 1 }];
  view.animate(frames, { duration: travels() ? 280 : 150, easing: token("--ease-out") });
}

function fitTitles() {
  document.querySelectorAll("#calView .ev.is-tall").forEach((card) => {
    const title = card.querySelector(".ev-title");
    card.classList.remove("is-clip", "is-cramped");
    card.classList.toggle("is-clip", title.scrollHeight > title.clientHeight + 1 || title.scrollWidth > title.clientWidth + 1);
    card.classList.toggle("is-cramped", card.scrollHeight > card.clientHeight + 1);
  });
}

function popFresh() {
  if (!state.fresh) return;
  const id = state.fresh;
  state.fresh = null;
  document.querySelectorAll(`#calView [data-id="${CSS.escape(id)}"], #calView [data-item="${CSS.escape(id)}"]`).forEach((node) => {
    node.classList.add("is-new");
    node.addEventListener("animationend", () => node.classList.remove("is-new"), { once: true });
    if (!animates()) return;
    const frames = travels() ? [{ opacity: 0, transform: "scale(0.92)" }, { opacity: 1, transform: "none" }] : [{ opacity: 0 }, { opacity: 1 }];
    node.animate(frames, { duration: travels() ? ms("--spring-tactile-dur") : 150, easing: travels() ? token("--spring-tactile") : "ease-out" });
  });
}

function render({ slide = 0, fade = false, flip = false } = {}) {
  const paint = () => holdFocus(() => {
    const view = $("calView");
    view.dataset.view = state.view;
    view.innerHTML = viewHtml();
    fitTitles();
    renderOverview();
  });
  if (flip) flipKeyed("#calView [data-flip]", paint);
  else paint();
  renderChrome();
  markSelected();
  if (slide) slideIn(slide);
  else if (fade) crossfade($("calView"), 160);
  popFresh();
}

function announce() {
  const range = rangeText();
  const live = $("liveStatus");
  if (live) live.textContent = `${range.text}${range.meta ? `, ${range.meta}` : ""}`;
}

function revealDate(iso) {
  const date = parseDate(iso);
  if (!inPeriod(iso)) {
    if (state.view === "liste") {
      const offset = dayDiff(startOfDay(now()), iso);
      state.anchor = offset >= 0 && offset < LIST_DAYS ? startOfDay(now()) : date;
    } else {
      state.anchor = date;
    }
  }
  state.focus = iso;
}

function keepFocusInView(paint) {
  const inside = $("calView").contains(document.activeElement);
  paint();
  if (inside && !$("calView").contains(document.activeElement)) $("calView").querySelector('[tabindex="0"], [data-id]')?.focus({ preventScroll: true });
}

function step(direction) {
  const focus = parseDate(state.focus);
  if (state.view === "woche") {
    state.anchor = addDays(mondayOf(state.anchor), 7 * direction);
    state.focus = isoDate(addDays(focus, 7 * direction));
  } else if (state.view === "monat") {
    const month = new Date(state.anchor.getFullYear(), state.anchor.getMonth() + direction, 1);
    const last = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
    state.anchor = month;
    state.focus = isoDate(new Date(month.getFullYear(), month.getMonth(), Math.min(focus.getDate(), last)));
  } else {
    state.anchor = addDays(startOfDay(state.anchor), LIST_DAYS * direction);
    state.focus = isoDate(state.anchor);
  }
  if (!state.picked && inPeriod(todayIso())) state.focus = todayIso();
  keepFocusInView(() => render({ slide: direction }));
  announce();
}

function goToday() {
  const today = todayIso();
  const span = period();
  const direction = today < isoDate(span.start) ? -1 : today > isoDate(span.end) ? 1 : 0;
  state.anchor = startOfDay(now());
  state.focus = today;
  state.picked = false;
  keepFocusInView(() => render({ slide: direction, fade: !direction }));
  announce();
}

function setView(view) {
  if (!VIEWS.includes(view) || view === state.view) return;
  state.view = view;
  storage.set("app-cal-view", view);
  state.anchor = parseDate(state.focus);
  keepFocusInView(() => render({ fade: true }));
  announce();
}

function focusDay(iso, { keyboard = false } = {}) {
  const span = period();
  const direction = iso < isoDate(span.start) ? -1 : iso > isoDate(span.end) ? 1 : 0;
  state.focus = iso;
  state.picked = true;
  if (direction) state.anchor = parseDate(iso);
  render({ slide: direction, fade: !direction && state.narrow && state.view === "woche" });
  if (keyboard) document.querySelector(`#calView [data-key="day:${iso}"]`)?.focus({ preventScroll: true });
  if (direction) announce();
}

function onDayKeys(event) {
  const button = event.target.closest?.(".cw-day, .cm-day");
  if (!button || event.altKey || event.ctrlKey || event.metaKey) return false;
  const date = parseDate(button.dataset.day);
  const month = state.view === "monat";
  const dow = date.getDay() || 7;
  const moves = {
    ArrowLeft: () => addDays(date, -1),
    ArrowRight: () => addDays(date, 1),
    ArrowUp: month ? () => addDays(date, -7) : null,
    ArrowDown: month ? () => addDays(date, 7) : null,
    Home: () => addDays(date, 1 - dow),
    End: () => addDays(date, 7 - dow),
    PageUp: month ? () => new Date(date.getFullYear(), date.getMonth() - 1, Math.min(date.getDate(), new Date(date.getFullYear(), date.getMonth(), 0).getDate())) : () => addDays(date, -7),
    PageDown: month ? () => new Date(date.getFullYear(), date.getMonth() + 1, Math.min(date.getDate(), new Date(date.getFullYear(), date.getMonth() + 2, 0).getDate())) : () => addDays(date, 7),
  };
  const move = moves[event.key];
  if (!move) return false;
  event.preventDefault();
  focusDay(isoDate(move()), { keyboard: true });
  return true;
}

function orderedTargets() {
  const view = $("calView");
  if (state.view === "monat") return [...view.querySelectorAll(".cm-day")].filter((node) => node.querySelector(".cm-item, .cal-dot"));
  return [...view.querySelectorAll("[data-id]")].sort((a, b) => (a.dataset.order || "").localeCompare(b.dataset.order || ""));
}

function moveItemFocus(direction) {
  const targets = orderedTargets();
  if (!targets.length) return;
  const current = targets.indexOf(document.activeElement);
  const next = current < 0 ? (direction > 0 ? 0 : targets.length - 1) : Math.min(targets.length - 1, Math.max(0, current + direction));
  const target = targets[next];
  if (state.view === "monat" && target.dataset.day !== state.focus) {
    focusDay(target.dataset.day, { keyboard: true });
    return;
  }
  target.focus({ preventScroll: true });
  target.scrollIntoView({ block: "nearest" });
}

const PAGE_NOISE = /\b(S\.|Seite|Nr\.|Nummer|Aufgabe|Aufg\.|Unit|Kapitel)\s*\d+[a-z]?(\s*(f\.|ff\.|bis\s*\d+))?/gi;
const TIME_RANGE = /(?:\bvon\s+)?\b([01]?\d|2[0-3])(?:[:.]([0-5]\d))?\s*(?:uhr\s*)?(?:-|–|bis)\s*([01]?\d|2[0-3])(?:[:.]([0-5]\d))?(?:\s*uhr)?\b/i;
const TIME_SINGLE = [
  /(?:\b(?:um|ab|gegen)\s+)?\b([01]?\d|2[0-3])[:.]([0-5]\d)(?:\s*uhr)?\b/i,
  /\b(?:um|ab|gegen)\s+([01]?\d|2[0-3])(?:\s*uhr)?\b/i,
  /\b([01]?\d|2[0-3])\s*uhr\b/i,
];
const pad = (value) => String(value).padStart(2, "0");
const hhmm = (minute) => `${pad(Math.floor(minute / 60))}:${pad(minute % 60)}`;

function cut(text, phrase) {
  if (!phrase) return text;
  const index = text.toLowerCase().indexOf(phrase.toLowerCase());
  return index < 0 ? text : `${text.slice(0, index)} ${text.slice(index + phrase.length)}`;
}

function parseTime(text) {
  const clean = text.replace(PAGE_NOISE, (match) => " ".repeat(match.length));
  const range = clean.match(TIME_RANGE);
  if (range && (range[2] || range[4] || /uhr|von/i.test(range[0]))) {
    const start = `${pad(range[1])}:${range[2] || "00"}`;
    const end = `${pad(range[3])}:${range[4] || "00"}`;
    if (toMin(end) > toMin(start)) return { start, end, phrase: text.substr(range.index, range[0].length) };
  }
  for (const pattern of TIME_SINGLE) {
    const match = clean.match(pattern);
    if (match) {
      const start = `${pad(match[1])}:${match[2] || "00"}`;
      return { start, end: null, phrase: text.substr(match.index, match[0].length) };
    }
  }
  return null;
}

function defaultDay() {
  return state.picked ? state.focus : todayIso();
}

function parseEntry(text) {
  const info = parseNote(text);
  let date = info.date || null;
  const later = !date && text.match(/(?:^|\s)((?:(?:bis|für|am|ab)\s+)?übermorgen)(?=$|[\s.,;!?])/i);
  if (later) {
    date = isoDate(addDays(startOfDay(now()), 2));
    info.phrases.date = later[1];
  }
  if (!date) {
    const weekday = text.match(WEEKDAY_WORDS);
    if (weekday) {
      const base = startOfDay(now());
      const offset = (WEEKDAY_INDEX[weekday[1].toLowerCase()] - base.getDay() + 7) % 7 || 7;
      date = isoDate(addDays(base, offset));
      info.phrases.date = weekday[0];
    }
  }
  const time = parseTime(cut(text, info.phrases.date));
  let start = time?.start || null;
  let end = time?.end || null;
  if (!start && info.block) {
    const block = blockOf(info.block);
    start = block.start;
    end = block.end;
  }
  if (start && !end) end = hhmm(Math.min(1439, toMin(start) + 60));
  const title = cleanTitle(cut(text, time?.phrase), info).replace(/\s+(um|am|von|ab)$/i, "").trim();
  let kind = "private";
  if (TRAINING_WORDS.test(text)) kind = "training";
  else if (PRIVATE_WORDS.test(text)) kind = "private";
  else if (SCHOOL_WORDS.test(text) || info.subject) kind = "school";
  return { title, date: date || defaultDay(), start, end, kind };
}

function renderQuickChips() {
  const text = $("calQuickInput").value;
  const chips = [];
  if (text.trim()) {
    const entry = parseEntry(text);
    chips.push(`<span class="chip">${icon("calendar-days")}${esc(shortDate(parseDate(entry.date)))}</span>`);
    chips.push(`<span class="chip">${icon("clock")}${entry.start ? `${hm(entry.start)} bis ${hm(entry.end)}` : "ganztägig"}</span>`);
    chips.push(`<span class="chip cal-kind-chip" style="--k:${kindVar(entry.kind)}"><i class="cal-dot"></i>${KINDS[entry.kind].label}</span>`);
  }
  const host = $("calQuickChips");
  const markup = chips.join("");
  if (host.dataset.markup !== markup) {
    host.dataset.markup = markup;
    host.innerHTML = markup;
  }
  $("calQuick").classList.toggle("has-chips", chips.length > 0);
}

function createEvent(text) {
  const entry = parseEntry(text);
  if (!entry.title) return;
  const item = { id: `neu-${Date.now()}`, date: entry.date, start: entry.start, end: entry.end, title: entry.title, place: "", kind: entry.kind, notes: "", synced: false };
  state.events.push(item);
  eventApi.create(item);
  const before = period();
  revealDate(item.date);
  const after = period();
  const direction = isoDate(after.start) > isoDate(before.start) ? 1 : isoDate(after.start) < isoDate(before.start) ? -1 : 0;
  state.fresh = item.id;
  render({ slide: direction });
  if (direction) announce();
  toast(`Angelegt: „${esc(item.title)}“, ${esc(shortDate(parseDate(item.date)))}${item.start ? `, ${hm(item.start)}` : ""}`, {
    icon: "check",
    action: { label: "Rückgängig", undo: true, run: () => removeEvent(item.id, { silent: true }) },
  });
}

function removeEvent(id, { silent = false } = {}) {
  const index = state.events.findIndex((item) => item.id === id);
  if (index < 0) return;
  if (state.events[index].synced) {
    toast(`Dieser Termin kommt aus ${esc(state.events[index].source || "einem verbundenen Kalender")}. Lösch ihn dort.`, { icon: "calendar-days" });
    return;
  }
  const [item] = state.events.splice(index, 1);
  eventApi.remove(id);
  const nodes = [...document.querySelectorAll(`#calView [data-id="${CSS.escape(id)}"], #calView [data-item="${CSS.escape(id)}"], #calOverview [data-id="${CSS.escape(id)}"]`)];
  const hadFocus = nodes.some((node) => node.contains(document.activeElement)) || $("calPanel").contains(document.activeElement);
  if (state.selected === id) closePanel();
  Promise.all(nodes.map((node) => exitInPlace(node))).then(() => {
    render({ flip: true });
    if (hadFocus) $("calQuickInput").focus({ preventScroll: true });
  });
  if (silent) return;
  toast(`Gelöscht: „${esc(item.title)}“`, {
    icon: "trash-2",
    action: { label: "Rückgängig", undo: true, run: () => {
      state.events.splice(Math.min(index, state.events.length), 0, item);
      eventApi.restore(item);
      revealDate(item.date);
      state.fresh = item.id;
      render();
    } },
  });
}

function updateEvent(changes, { flip = true } = {}) {
  const item = state.events.find((entry) => entry.id === state.selected);
  if (!item || item.synced) return null;
  Object.assign(item, changes);
  eventApi.update(item.id, changes);
  if (changes.date && !inPeriod(changes.date)) {
    revealDate(changes.date);
    render({ fade: true });
  } else {
    render({ flip });
  }
  return item;
}

function bindPanel() {
  const panel = $("calPanel");
  panel.addEventListener("click", (event) => {
    if (event.target.closest("[data-panel-close]")) closePanel({ refocus: true });
    else if (event.target.closest("[data-panel-delete]")) removeEvent(state.selected);
    else if (event.target.closest("[data-date-pick]")) {
      const input = $("calPanelDate");
      try { input.showPicker(); } catch { input.focus(); }
    } else if (event.target.closest("[data-kind]")) {
      const key = event.target.closest("[data-kind]").dataset.kind;
      updateEvent({ kind: key });
      panel.querySelectorAll("[data-kind]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.kind === key)));
      const mark = panel.querySelector(".cal-mark");
      if (mark) {
        mark.style.setProperty("--k", kindVar(key));
        mark.innerHTML = icon(KINDS[key].icon);
      }
    }
  });
  panel.addEventListener("change", (event) => {
    const item = state.events.find((entry) => entry.id === state.selected);
    if (!item) return;
    const target = event.target;
    if (target.id === "calPanelDate" && target.value) {
      updateEvent({ date: target.value });
      $("calDateText").textContent = shortDate(parseDate(item.date));
      panel.querySelector("[data-date-pick]").setAttribute("aria-label", `Datum ändern, ${longDate(parseDate(item.date))}`);
      panel.querySelector("[data-date-pick]").focus({ preventScroll: true });
    }
    if (target.id === "calPanelStart") {
      const value = target.value.trim() ? normalizeTime(target.value) : null;
      if (value === undefined) {
        target.value = item.start ? hm(item.start) : "";
      } else {
        const span = item.start && item.end ? toMin(item.end) - toMin(item.start) : 60;
        const end = value ? hhmm(Math.min(1439, toMin(value) + span)) : null;
        updateEvent({ start: value, end });
        target.value = value ? hm(value) : "";
        $("calPanelEnd").value = end ? hm(end) : "";
        $("calPanelEnd").disabled = !value;
      }
    }
    if (target.id === "calPanelEnd") {
      const value = target.value.trim() ? normalizeTime(target.value) : null;
      if (value === undefined || (value && item.start && toMin(value) <= toMin(item.start))) {
        target.value = item.end ? hm(item.end) : "";
      } else {
        updateEvent({ end: value });
        target.value = value ? hm(value) : "";
      }
    }
    const note = $("calWhenNote");
    if (note) note.textContent = whenNote(item);
  });
  panel.addEventListener("input", (event) => {
    const item = state.events.find((entry) => entry.id === state.selected);
    if (!item || item.synced) return;
    const target = event.target;
    if (target.id === "calPanelNotes") {
      item.notes = target.value;
      saveText(`${item.id}:notes`, item.id, { notes: item.notes });
    }
    if (target.id === "calPanelPlace") {
      item.place = target.value;
      $("calRouteSlot").innerHTML = routeLink(item.place.trim());
      saveText(`${item.id}:place`, item.id, { place: item.place.trim() });
    }
    if (target.id === "calPanelTitle") {
      item.title = target.value.replace(/\s+/g, " ").trimStart();
      if (item.title.trim()) saveText(`${item.id}:title`, item.id, { title: item.title.trim() });
      document.querySelectorAll(`[data-title-of="${CSS.escape(item.id)}"]`).forEach((node) => (node.textContent = item.title));
      panel.setAttribute("aria-label", item.title);
    }
  });
  panel.addEventListener("focusout", (event) => {
    if (event.target.id === "calPanelTitle" || event.target.id === "calPanelPlace") render();
  });
  panel.addEventListener("keydown", (event) => {
    if (["calPanelTitle", "calPanelPlace", "calPanelStart", "calPanelEnd"].includes(event.target.id) && event.key === "Enter") {
      event.preventDefault();
      event.target.blur();
    }
  });
}

async function startSync({ first = false } = {}) {
  if (state.loading) return;
  state.loading = true;
  const button = $("calSync");
  button.classList.add("is-spinning");
  button.setAttribute("aria-busy", "true");
  render();
  const start = isoDate(addDays(startOfDay(now()), -42));
  const end = isoDate(addDays(startOfDay(now()), 120));
  let fresh = null;
  try {
    const response = await fetch(`/api/ui/events/synced?start=${start}&end=${end}`, { credentials: "same-origin" });
    const payload = await response.json();
    if (response.ok && payload.success) fresh = payload.events || [];
  } catch {}
  const finish = () => {
    state.loading = false;
    button.classList.remove("is-spinning");
    button.removeAttribute("aria-busy");
    if (fresh) {
      const own = state.events.filter((item) => !item.synced);
      const seen = new Set(own.map((item) => `${item.title}|${item.date}|${item.start || ""}`));
      const synced = fresh.filter((item) => !seen.has(`${item.title}|${item.date}|${item.start || ""}`))
        .map((item) => ({ ...item, kind: KINDS[item.kind] ? item.kind : "private", notes: item.notes || "", synced: true }));
      state.events = [...own, ...synced];
    } else if (!first) {
      toast("Die verbundenen Kalender sind gerade nicht erreichbar.", { icon: "wifi-off" });
    }
    render();
    revealSynced();
  };
  const card = document.querySelector("#calView .cal-loading");
  if (card) exitInPlace(card).then(finish);
  else finish();
}

function revealSynced() {
  if (!animates()) return;
  const nodes = [...document.querySelectorAll("#calView .ev, #calView .cw-chip.is-event, #calView .cm-item.is-event, #calView .cal-dot.is-event, #calView .cl-row.is-event, #calOverview .cal-agenda-item")];
  const move = travels();
  nodes.slice(0, 32).forEach((node, index) => {
    node.animate(
      move ? [{ opacity: 0, transform: "translateY(6px)" }, { opacity: 1, transform: "none" }] : [{ opacity: 0 }, { opacity: 1 }],
      { duration: move ? ms("--dur-enter") || 320 : 150, delay: move ? Math.min(index, 14) * (ms("--stagger") || 40) : 0, easing: token("--ease-out"), fill: "backwards" },
    );
  });
}

function measure() {
  const width = $("calStage").getBoundingClientRect().width;
  return width > 0 && width < NARROW;
}

function scheduleTick() {
  if (pinnedTime()) return;
  const date = new Date();
  const wait = (60 - date.getSeconds()) * 1000 - date.getMilliseconds() + 50;
  setTimeout(() => {
    if (!document.hidden && !state.loading) render();
    scheduleTick();
  }, wait);
}

function bind() {
  const view = $("calView");
  view.addEventListener("click", (event) => {
    const jump = event.target.closest("[data-jump]");
    if (jump) {
      focusDay(jump.dataset.jump);
      return;
    }
    const item = event.target.closest("[data-item]");
    if (item) {
      const id = item.dataset.item;
      if (state.selected === id) closePanel();
      else openItem(id);
      return;
    }
    const day = event.target.closest(".cw-day, .cm-day");
    if (day) {
      focusDay(day.dataset.day, { keyboard: event.detail === 0 });
      return;
    }
    const target = event.target.closest("[data-id]");
    if (!target) return;
    if (state.selected === target.dataset.id) closePanel();
    else openItem(target.dataset.id, { keyboard: event.detail === 0 });
  });
  view.addEventListener("keydown", (event) => {
    if (onDayKeys(event)) event.stopPropagation();
  });
  $("calOverview").addEventListener("click", (event) => {
    if (event.target.closest("[data-back-today]")) {
      goToday();
      return;
    }
    const target = event.target.closest("[data-id]");
    if (!target) return;
    openItem(target.dataset.id, { keyboard: event.detail === 0, reveal: true });
  });
  $("calViews").addEventListener("click", (event) => {
    const button = event.target.closest("[data-view]");
    if (button) setView(button.dataset.view);
  });
  $("calPrev").addEventListener("click", () => step(-1));
  $("calNext").addEventListener("click", () => step(1));
  $("calToday").addEventListener("click", goToday);
  $("calSync").addEventListener("click", () => startSync());
  $("calNew").addEventListener("click", () => $("calQuickInput").focus());
  $("calQuickInput").addEventListener("input", renderQuickChips);
  $("calQuickInput").addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.target.value = "";
      renderQuickChips();
      event.target.blur();
    }
  });
  $("calQuick").addEventListener("submit", (event) => {
    event.preventDefault();
    const input = $("calQuickInput");
    if (!input.value.trim()) return;
    createEvent(input.value);
    input.value = "";
    renderQuickChips();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && state.selected && !overlayOpen()) {
      closePanel({ refocus: true });
      return;
    }
    if (typing(event.target) || event.ctrlKey || event.metaKey || event.altKey || overlayOpen()) return;
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      if (event.target.closest?.(".cw-day, .cm-day, .cal-panel")) return;
      event.preventDefault();
      step(event.key === "ArrowLeft" ? -1 : 1);
      return;
    }
    if (!shortcutsEnabled()) return;
    const key = event.key.toLowerCase();
    if (key === "j" || key === "k") {
      event.preventDefault();
      moveItemFocus(key === "j" ? 1 : -1);
    } else if (key === "t") {
      event.preventDefault();
      goToday();
    } else if (key === "w" || key === "m" || key === "l") {
      event.preventDefault();
      setView({ w: "woche", m: "monat", l: "liste" }[key]);
    }
  });
  new ResizeObserver(() => {
    const narrow = measure();
    if (narrow === state.narrow) return;
    state.narrow = narrow;
    render();
  }).observe($("calStage"));
  registerSearch(() => {
    const query = $("paletteInput")?.value.trim();
    if (!query) return [];
    return state.events.map((item) => ({
      group: "Termine",
      label: item.title,
      icon: "calendar-clock",
      keywords: `${item.place || ""} ${KINDS[item.kind].label}`,
      hint: `${shortDate(parseDate(item.date))}${item.start ? `, ${hm(item.start)}` : ""}`,
      run: () => openItem(item.id, { reveal: true }),
    }));
  });
  bindPanel();
}

function syncPlaceholder(query) {
  $("calQuickInput").placeholder = query.matches ? "Neuer Termin: „Gym morgen 16:30“" : "Neuer Termin, zum Beispiel „Gym morgen 16:30“";
}

export function init() {
  if (!$("calendarPage")) return;
  load();
  state.narrow = measure();
  const small = matchMedia("(max-width: 640px)");
  syncPlaceholder(small);
  small.addEventListener("change", syncPlaceholder);
  FLOATING.addEventListener("change", syncOverview);
  bind();
  render();
  startSync({ first: true });
  scheduleTick();
}
