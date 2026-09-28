export const root = document.documentElement;
export const params = new URLSearchParams(location.search);
export const data = JSON.parse(document.getElementById("appData")?.textContent || "null");
export const BRAND = root.dataset.brand || self.BRAND_NAME || "";
export const BRAND_NAMES = [BRAND, ...(root.dataset.brandPrevious || "").split(",").map((name) => name.trim()).filter(Boolean)];

export const variant = {
  key: root.dataset.variant,
  motion: root.dataset.motion,
  palette: root.dataset.palette,
  themeMode: root.dataset.themeMode,
};

export const flags = {
  empty: params.has("leer"),
  offline: params.has("offline") || root.dataset.offline === "1",
  change: params.has("aenderung"),
  cold: params.has("kalt"),
  warm: params.has("warm"),
  clean: params.has("clean"),
  scene: params.get("szene"),
  lite: params.has("lite"),
};

export const WEEKDAYS = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];
export const WEEKDAYS_SHORT = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"];
export const MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
export const MONTHS_SHORT = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sept", "Okt", "Nov", "Dez"];

export const platform = {
  mac: /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent),
  electron: /Electron/.test(navigator.userAgent),
  touch: matchMedia("(hover: none)").matches,
};

export const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

export function safeMarkup(markup, allowed = ["B", "BR", "STRONG", "EM"]) {
  const template = document.createElement("template");
  template.innerHTML = String(markup ?? "");
  const copy = (from, into) => {
    from.childNodes.forEach((node) => {
      if (node.nodeType === Node.TEXT_NODE) into.append(node.textContent);
      else if (node.nodeType !== Node.ELEMENT_NODE) return;
      else if (allowed.includes(node.tagName)) into.append(copy(node, document.createElement(node.tagName.toLowerCase())));
      else copy(node, into);
    });
    return into;
  };
  return copy(template.content, document.createDocumentFragment());
}

export const icon = (name, cls = "") => `<svg class="icon ${cls}" aria-hidden="true"><use href="#i-${name}"/></svg>`;

export { tinte } from "./tinte.js";

export const toMin = (hhmm) => {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
};

export const clock = (min) => `${Math.floor(min / 60)}:${String(min % 60).padStart(2, "0")}`;
export const hm = (value) => String(value).replace(/^0(\d)/, "$1");
export const startOfDay = (date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());
export const addDays = (date, n) => new Date(date.getFullYear(), date.getMonth(), date.getDate() + n);
export const isoDate = (date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
export const parseDate = (iso) => {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
};
export const dayDiff = (from, iso) => Math.round((parseDate(iso) - startOfDay(from)) / 864e5);
export const minutesOf = (date) => date.getHours() * 60 + date.getMinutes();

export function now() {
  const date = new Date();
  const pinnedDay = params.get("datum");
  if (pinnedDay && /^\d{4}-\d{2}-\d{2}$/.test(pinnedDay)) {
    const [y, m, d] = pinnedDay.split("-").map(Number);
    date.setFullYear(y, m - 1, d);
  }
  const tag = Number(params.get("tag"));
  if (tag >= 1 && tag <= 7) date.setDate(date.getDate() + (tag - (date.getDay() || 7)));
  const t = params.get("t");
  if (t && /^\d{1,2}:\d{2}$/.test(t)) {
    const [h, m] = t.split(":").map(Number);
    date.setHours(h, m, 0, 0);
  }
  return date;
}

export const pinnedTime = () => params.has("t");

export function weekType(date) {
  if (!abWeeks()) return "A";
  const monday = addDays(startOfDay(date), 1 - (date.getDay() || 7));
  const days = Math.round((monday - parseDate(data.abReference)) / 864e5);
  return Math.floor(days / 7) % 2 === 0 ? "A" : "B";
}

export function isoWeek(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  return Math.ceil(((d - yearStart) / 864e5 + 1) / 7);
}

export const glue = (text) => String(text)
  .replace(/(^|[\s(])(S\.|Nr\.|Seite|Unit|Kapitel|Aufgaben?|Folien?|KW) (?=\d)/g, "$1$2\u00a0")
  .replace(/(\d+\.?) (?=Block|Min\.|Std\.|Tag|Woche|Aufgabe|Uhr|bis \d)/g, "$1\u00a0")
  .replace(/(?<=^|\s)(vor|nach|für|seit|bis|um|am|im|ab|zum|zur|dem|der|den|die|das) (?=\S)/gi, "$1\u00a0");
export const subject = (key) => data.subjects[key] || { name: key || "Ohne Fach", label: key || "Ohne Fach", short: key ? String(key).slice(0, 3) : "–", hue: "slate" };
export const hueVar = (key) => `var(--hue-${subject(key).hue})`;
export const blockOf = (n) => data.blocks.find((block) => block.n === n);

export function changesFor(date) {
  if (!flags.change) return [];
  return data.changes.filter((change) => change.date === isoDate(date));
}

export function holidayOn(date) {
  const iso = isoDate(date);
  return (data?.holidays || []).find((item) => item.date <= iso && (item.endDate || item.date) >= iso) || null;
}

export function lessonsFor(date) {
  const dow = date.getDay();
  if (dow === 0 || dow === 6 || holidayOn(date)) return [];
  const changes = changesFor(date);
  return (data.timetable[weekType(date)][String(dow)] || []).map((lesson) => {
    const block = blockOf(lesson.block);
    const change = changes.find((item) => item.block === lesson.block);
    return {
      ...lesson,
      start: block.start,
      end: block.end,
      startMin: toMin(block.start),
      endMin: toMin(block.end),
      cancelled: change?.type === "entfall",
      movedFrom: change?.type === "raum" ? lesson.room : null,
      room: change?.type === "raum" ? change.room : lesson.room,
      changeNote: change?.note || null,
    };
  });
}

export const activeLessons = (lessons) => lessons.filter((lesson) => !lesson.cancelled);

export function nextSchoolDay(from) {
  for (let i = 1; i <= 10; i += 1) {
    const date = addDays(startOfDay(from), i);
    const lessons = activeLessons(lessonsFor(date));
    if (lessons.length) return { date, lessons, offset: i };
  }
  return null;
}

export function relativeDay(offset, date) {
  if (offset === 0) return "heute";
  if (offset === 1) return "morgen";
  if (offset === 2) return "übermorgen";
  if (offset === -1) return "gestern";
  if (offset > 0 && offset < 7) return `am ${WEEKDAYS[date.getDay()]}`;
  return `am ${date.getDate()}.\u00a0${MONTHS[date.getMonth()]}`;
}

export function inDays(offset) {
  if (offset === 0) return "heute";
  if (offset === 1) return "morgen";
  if (offset < 14) return `in ${offset}\u00a0Tagen`;
  const weeks = Math.round(offset / 7);
  return `in ${weeks}\u00a0Wochen`;
}

export function duration(min) {
  if (min < 60) return `${min}\u00a0Min.`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h}\u00a0Std. ${m}\u00a0Min.` : `${h}\u00a0Std.`;
}

export const shortDate = (date) => `${WEEKDAYS_SHORT[date.getDay()]}., ${date.getDate()}.${date.getMonth() + 1}.`;
export const longDate = (date) => `${WEEKDAYS[date.getDay()]}, ${date.getDate()}. ${MONTHS[date.getMonth()]}`;

export const eventsOn = (date) =>
  (flags.empty ? [] : data.events)
    .filter((event) => event.date === isoDate(date))
    .sort((a, b) => (a.start || "00:00").localeCompare(b.start || "00:00"));

export function nextDeparture(afterMin) {
  const transit = data.transit;
  const walk = transit.walkMinutes || 0;
  for (const time of transit.departures) {
    if (toMin(time) >= afterMin + walk) {
      return { time, delay: transit.delays?.[time] || 0, line: transit.line, mode: transit.mode, from: transit.from, walk };
    }
  }
  return null;
}

export function schoolDeparture(startMin, nowMin) {
  const route = data.transit.toSchool;
  if (!route) return null;
  const options = route.departures.map((time) => ({ time, min: toMin(time) }));
  const fits = options.filter((item) => item.min + route.rideMinutes + route.bufferMinutes <= startMin);
  const reachable = fits.filter((item) => item.min - route.walkMinutes >= nowMin);
  const pick = reachable.length ? reachable[reachable.length - 1] : options.find((item) => item.min - route.walkMinutes >= nowMin);
  if (!pick) return null;
  const late = pick.min + route.rideMinutes + route.bufferMinutes > startMin;
  const missed = late && fits.length ? fits[fits.length - 1].time : null;
  return {
    time: pick.time,
    walk: route.walkMinutes,
    leave: pick.min - route.walkMinutes,
    arrive: clock(pick.min + route.rideMinutes),
    lateBy: Math.max(0, pick.min + route.rideMinutes - startMin),
    missed,
    late,
    line: route.line,
    mode: route.mode,
    from: route.from,
  };
}

const weatherHours = () => data?.weather?.hours || [];

export const hasWeather = () => weatherHours().length > 0;

export function weatherAt(hour) {
  const hours = weatherHours();
  return hours.find((item) => item.h === hour) || hours[hours.length - 1] || null;
}

export function rainFrom(hour) {
  const rainy = weatherHours().find((item) => item.h >= hour && item.rain >= 40);
  return rainy ? rainy.h : null;
}

export function hourIcon(item) {
  if (item.rain >= 50) return "cloud-rain";
  if (item.rain >= 30) return "cloud-drizzle";
  if (item.h >= 20 || item.h < 7) return "cloud-moon";
  if (item.h >= 12 && item.h <= 14) return "cloud-sun";
  return "cloud";
}

const SERVER_KEYS = new Set([
  "app-timetable-edits", "app-block-times", "app-ab-swap", "app-ab-weeks", "app-subjects", "app-teachers", "app-rooms",
  "app-settings", "app-motion", "app-theme-choice", "app-single-keys", "app-task-filter", "app-cal-view",
]);

const serverValues = (() => {
  try {
    const seed = JSON.parse(document.getElementById("appStore")?.textContent || "{}");
    return new Map(Object.entries(seed && typeof seed === "object" ? seed : {}));
  } catch {
    return new Map();
  }
})();

const writes = new Map();

function persist(key, value) {
  const body = value === undefined ? undefined : JSON.stringify(value);
  const previous = writes.get(key) || Promise.resolve();
  const next = previous.then(() => fetch(`/api/ui/store/${encodeURIComponent(key)}`, {
    method: value === undefined ? "DELETE" : "PUT",
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body,
    credentials: "same-origin",
    keepalive: true,
  })).then((response) => {
    if (!response.ok) throw new Error(String(response.status));
  }).catch(() => {
    window.dispatchEvent(new CustomEvent("app:save-failed", { detail: { key } }));
  });
  writes.set(key, next);
  return next;
}

export const storage = {
  get(key) {
    if (SERVER_KEYS.has(key)) {
      return serverValues.has(key) ? JSON.parse(JSON.stringify(serverValues.get(key))) : null;
    }
    try {
      return JSON.parse(localStorage.getItem(key));
    } catch {
      return null;
    }
  },
  set(key, value) {
    if (SERVER_KEYS.has(key)) {
      serverValues.set(key, JSON.parse(JSON.stringify(value)));
      persist(key, value);
      return;
    }
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch {}
  },
  remove(key) {
    if (SERVER_KEYS.has(key)) {
      serverValues.delete(key);
      persist(key, undefined);
      return;
    }
    try {
      localStorage.removeItem(key);
    } catch {}
  },
  keys() {
    return [...serverValues.keys()];
  },
};

export const LOCAL_KEYS = {
  lessons: "app-timetable-edits",
  blocks: "app-block-times",
  abSwap: "app-ab-swap",
  motion: "app-motion",
  subjects: "app-subjects",
  teachers: "app-teachers",
  rooms: "app-rooms",
  abWeeks: "app-ab-weeks",
  prefs: "app-settings",
};

export const abWeeks = () => storage.get(LOCAL_KEYS.abWeeks) !== false;
export const gradeScale = () => ((storage.get(LOCAL_KEYS.prefs)?.school?.grade ?? 12) >= 11 ? "points" : "grades");

export const HUES = ["rose", "ochre", "olive", "moss", "jade", "teal", "lake", "slate", "iris", "orchid", "brick", "plum"];
export const COURSE_TYPES = ["LK", "GK", "SK"];
export const NO_TEACHER = "ohne Lehrkraft";
export const MAX_BLOCKS = 8;
export const activeSubjectKeys = () => Object.keys(data?.subjects || {}).filter((key) => !data.subjects[key].retired);

const clone = (value) => JSON.parse(JSON.stringify(value));
const isClock = (value) => typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
const objectOf = (key) => {
  const value = storage.get(key);
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
};
const listOf = (value) => (Array.isArray(value) ? value.filter((item) => typeof item === "string") : []);
const plainName = (text) => String(text || "").replace(/\s+(LK|GK)$/, "");

export const slug = (text) => String(text).toLowerCase()
  .replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss")
  .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
export const teacherId = (text) => `t-${slug(text)}`;
export const teacherLabel = (teacher) => [teacher?.title, teacher?.name].filter(Boolean).join(" ");

export const schoolDefaults = data?.timetable && data?.blocks && data?.subjects
  ? {
    blocks: clone(data.blocks),
    timetable: clone(data.timetable),
    abReference: data.abReference,
    subjects: clone(data.subjects),
    courses: clone(data.courses || data.page?.courses || {}),
  }
  : null;

export const motionDefault = root.dataset.motion;

function eachEntry(timetable, visit) {
  Object.values(timetable || {}).forEach((days) => Object.values(days || {}).forEach((entries) => (entries || []).forEach(visit)));
}

export function defaultTeacher(key) {
  let found = "";
  eachEntry(schoolDefaults?.timetable, (entry) => {
    if (!found && entry.subject === key && entry.teacher) found = entry.teacher;
  });
  return found;
}

function defaultRoom(key) {
  const counts = new Map();
  eachEntry(schoolDefaults.timetable, (entry) => {
    if (entry.subject === key && entry.room) counts.set(entry.room, (counts.get(entry.room) || 0) + 1);
  });
  return [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || "";
}

function defaultType(key, info) {
  const type = schoolDefaults.courses[key]?.type;
  if (COURSE_TYPES.includes(type)) return type;
  return /\sLK$/.test(info.label || info.name || "") ? "LK" : "GK";
}

function resolveTeachers() {
  const saved = objectOf(LOCAL_KEYS.teachers);
  const items = saved.items && typeof saved.items === "object" ? saved.items : {};
  const removed = new Set(listOf(saved.removed));
  const list = new Map();
  eachEntry(schoolDefaults.timetable, (entry) => {
    if (!entry.teacher) return;
    const id = teacherId(entry.teacher);
    if (list.has(id) || removed.has(id)) return;
    const match = /^(Frau|Herr)\s+(.+)$/.exec(entry.teacher);
    list.set(id, { id, title: match ? match[1] : "", name: match ? match[2] : entry.teacher, custom: false });
  });
  Object.entries(items).forEach(([id, value]) => {
    if (removed.has(id) || !value || typeof value.name !== "string" || !value.name.trim()) return;
    const base = list.get(id);
    if (!base && !value.custom) return;
    list.set(id, { id, title: ["Frau", "Herr"].includes(value.title) ? value.title : "", name: value.name.trim().slice(0, 40), custom: base ? base.custom : true });
  });
  return [...list.values()].map((teacher) => ({ ...teacher, label: teacherLabel(teacher) }));
}

function resolveSubjects(teachers) {
  const saved = objectOf(LOCAL_KEYS.subjects);
  const items = saved.items && typeof saved.items === "object" ? saved.items : {};
  const removed = new Set(listOf(saved.removed));
  const byId = new Map(teachers.map((teacher) => [teacher.id, teacher]));
  const result = {};
  const make = (base, own) => {
    const type = COURSE_TYPES.includes(own.type) ? own.type : base.type;
    const name = typeof own.name === "string" ? own.name.trim().slice(0, 32) : "";
    const suffix = type === "LK" ? " LK" : "";
    const renamed = !!name || type !== base.type;
    const teacher = byId.get(typeof own.teacher === "string" ? own.teacher : base.teacher) || null;
    return {
      name: renamed ? `${name || plainName(base.name)}${suffix}` : base.name,
      label: renamed ? `${name || plainName(base.label)}${suffix}` : base.label,
      short: typeof own.short === "string" && own.short.trim() ? own.short.trim().slice(0, 4) : base.short,
      hue: HUES.includes(own.hue) ? own.hue : base.hue,
      type,
      teacherId: teacher ? teacher.id : "",
      teacher: teacher ? teacher.label : "",
      room: typeof own.room === "string" ? own.room.trim().slice(0, 12) : base.room,
      custom: base.custom,
      ...(base.retired ? { retired: true } : {}),
    };
  };
  Object.entries(schoolDefaults.subjects).forEach(([key, info]) => {
    const teacher = defaultTeacher(key);
    result[key] = make({ ...info, type: defaultType(key, info), teacher: teacher ? teacherId(teacher) : "", room: defaultRoom(key), custom: false, retired: removed.has(key) }, items[key] || {});
  });
  Object.entries(items).forEach(([key, own]) => {
    if (result[key] || removed.has(key) || schoolDefaults.subjects[key] || !own?.custom) return;
    const name = typeof own.name === "string" ? own.name.trim() : "";
    if (!name || !HUES.includes(own.hue)) return;
    result[key] = make({ name, label: name, short: name.slice(0, 3), hue: own.hue, type: "GK", teacher: "", room: "", custom: true }, own);
  });
  return result;
}

function resolveRooms() {
  const saved = objectOf(LOCAL_KEYS.rooms);
  const removed = new Set(listOf(saved.removed));
  const rooms = new Set();
  eachEntry(schoolDefaults.timetable, (entry) => entry.room && rooms.add(entry.room));
  listOf(saved.added).forEach((room) => room.trim() && rooms.add(room.trim().slice(0, 12)));
  return [...rooms].filter((room) => !removed.has(room)).sort((a, b) => a.localeCompare(b, "de", { numeric: true }));
}

function blockTimesValid(blocks) {
  const ordered = [...blocks].sort((a, b) => a.n - b.n);
  return ordered.every((block, index) => isClock(block.start) && isClock(block.end)
    && toMin(block.start) < toMin(block.end)
    && (!index || toMin(ordered[index - 1].end) <= toMin(block.start)));
}

function savedBlocks() {
  const fresh = () => schoolDefaults.blocks.map((block) => ({ ...block }));
  const saved = storage.get(LOCAL_KEYS.blocks);
  if (Array.isArray(saved)) {
    const merged = schoolDefaults.blocks.map((block) => {
      const own = saved.find((item) => item && item.n === block.n);
      return own && isClock(own.start) && isClock(own.end) ? { ...block, start: own.start, end: own.end } : { ...block };
    });
    return blockTimesValid(merged) ? merged : fresh();
  }
  if (saved?.v !== 2 || !Array.isArray(saved.blocks) || !saved.blocks.length || saved.blocks.length > MAX_BLOCKS) return fresh();
  const list = [...saved.blocks].sort((a, b) => a?.n - b?.n).map((item, index) => ({ ...(schoolDefaults.blocks.find((block) => block.n === index + 1) || {}), n: index + 1, start: item?.start, end: item?.end }));
  return list.every((block, index) => saved.blocks.some((item) => item?.n === index + 1)) && blockTimesValid(list) ? list : fresh();
}

export function saveBlocks(blocks) {
  const list = blocks.map(({ n, start, end }) => ({ n, start, end }));
  const same = list.length === schoolDefaults.blocks.length && list.every((block, index) => block.start === schoolDefaults.blocks[index].start && block.end === schoolDefaults.blocks[index].end);
  if (same) {
    storage.remove(LOCAL_KEYS.blocks);
  } else {
    storage.set(LOCAL_KEYS.blocks, { v: 2, blocks: list });
  }
}

export function applySchoolEdits() {
  if (!schoolDefaults) return;
  const teachers = resolveTeachers();
  const subjects = resolveSubjects(teachers);
  const byId = new Map(teachers.map((teacher) => [teacher.id, teacher]));
  const teacherFor = (key, own = "") => byId.get(own)?.label || subjects[key]?.teacher || NO_TEACHER;
  const active = (key) => !!subjects[key] && !subjects[key].retired;
  data.teachers = teachers;
  data.subjects = subjects;
  data.rooms = resolveRooms();
  const courses = Object.fromEntries(Object.entries(subjects).map(([key, info]) => [key, { ...(schoolDefaults.courses[key] || {}), type: info.type }]));
  data.courses = courses;
  if (data.page?.courses) data.page.courses = courses;
  data.blocks = savedBlocks();
  const known = new Set(data.blocks.map((block) => block.n));
  const timetable = {};
  Object.entries(schoolDefaults.timetable).forEach(([week, days]) => {
    timetable[week] = {};
    Object.entries(days).forEach(([dow, entries]) => {
      timetable[week][dow] = entries.filter((entry) => active(entry.subject) && known.has(entry.block)).map((entry) => ({ ...entry, teacher: teacherFor(entry.subject) }));
    });
  });
  const edits = storage.get(LOCAL_KEYS.lessons);
  if (edits && typeof edits === "object" && !Array.isArray(edits)) {
    Object.entries(edits).forEach(([key, value]) => {
      const match = /^([AB]):([1-5]):(\d{1,2})$/.exec(key);
      if (!match || !known.has(Number(match[3]))) return;
      if (value !== null && !(value && typeof value === "object" && active(value.subject))) return;
      const [, week, dow] = match;
      const block = Number(match[3]);
      const day = (timetable[week]?.[dow] || []).filter((entry) => entry.block !== block);
      if (value) {
        const own = typeof value.teacher === "string" && byId.has(value.teacher) ? value.teacher : "";
        day.push({ block, subject: value.subject, room: String(value.room || "").trim().slice(0, 12), teacher: teacherFor(value.subject, own) });
      }
      timetable[week] ||= {};
      timetable[week][dow] = day.sort((a, b) => a.block - b.block);
    });
  }
  data.timetable = timetable;
  data.abReference = storage.get(LOCAL_KEYS.abSwap) === true
    ? isoDate(addDays(parseDate(schoolDefaults.abReference), 7))
    : schoolDefaults.abReference;
}

function hideRetired() {
  const gone = (item) => !!item?.subject && !!data.subjects[item.subject]?.retired;
  if (!Object.values(data.subjects).some((info) => info.retired)) return;
  if (Array.isArray(data.deadlines)) data.deadlines = data.deadlines.filter((item) => !gone(item));
  if (Array.isArray(data.page?.exams)) data.page.exams = data.page.exams.filter((item) => !gone(item));
}

function reanchor(items) {
  if (!Array.isArray(items)) return;
  items.forEach((item) => {
    if (!item?.block || !item.subject || !/^\d{4}-\d{2}-\d{2}$/.test(item.date || "")) return;
    const date = parseDate(item.date);
    if (date.getDay() === 0 || date.getDay() === 6) return;
    const entries = data.timetable[weekType(date)]?.[String(date.getDay())] || [];
    if (entries.some((entry) => entry.block === item.block && entry.subject === item.subject)) return;
    const moved = entries.find((entry) => entry.subject === item.subject);
    if (moved) item.block = moved.block;
    else delete item.block;
  });
}

if (schoolDefaults) {
  applySchoolEdits();
  hideRetired();
  const edits = storage.get(LOCAL_KEYS.lessons);
  const moved = (edits && Object.keys(edits).length) || storage.get(LOCAL_KEYS.abSwap) === true || Object.keys(objectOf(LOCAL_KEYS.subjects)).length || storage.get(LOCAL_KEYS.blocks) != null || !abWeeks();
  if (moved) [data.deadlines, data.page?.exams].forEach(reanchor);
}

if (storage.get(LOCAL_KEYS.motion) === "minimal") {
  root.dataset.motion = "minimal";
  variant.motion = "minimal";
}
