import { BRAND, LOCAL_KEYS, data, dayDiff, hm, isoDate, lessonsFor, minutesOf, startOfDay, storage, subject, toMin } from "./core.js";

const SHOWN_KEY = "app-reminders-shown";
const TICK = 30000;
const GRACE = 5;
const KEEP_DAYS = 3;
const MORNING = 7 * 60;

export const CATEGORY_DEFAULTS = {
  lessons: { on: true, lead: 10 },
  tests: { on: true, lead: 1 },
  homework: { on: true, lead: 1 },
  events: { on: true, lead: 15 },
  tasks: { on: true },
};

export function readPrefs(saved = storage.get(LOCAL_KEYS.prefs)) {
  const notify = saved?.notify || {};
  const categories = Object.fromEntries(
    Object.entries(CATEGORY_DEFAULTS).map(([key, base]) => [key, { ...base, ...(notify.categories?.[key] || {}) }]),
  );
  return {
    enabled: notify.enabled === true,
    sound: notify.sound !== false,
    quiet: { from: notify.quiet?.from || "22:00", to: notify.quiet?.to || "07:00" },
    categories,
  };
}

export function switchRemindersOn() {
  const saved = storage.get(LOCAL_KEYS.prefs) || {};
  if (saved.notify?.enabled === true) return;
  storage.set(LOCAL_KEYS.prefs, { ...saved, notify: { ...(saved.notify || {}), enabled: true } });
  document.dispatchEvent(new CustomEvent("reminders:on"));
}

export function isQuiet(minute, quiet) {
  const from = toMin(quiet.from);
  const to = toMin(quiet.to);
  if (from === to) return false;
  return from < to ? minute >= from && minute < to : minute >= from || minute < to;
}

const dueAt = (minute, target) => minute >= target && minute < target + GRACE;
const whenText = (days) => (days === 0 ? "heute" : days === 1 ? "morgen" : `in ${days} Tagen`);
const capitalized = (text) => text.charAt(0).toUpperCase() + text.slice(1);
const courseOf = (key) => (key ? `, ${subject(key).label}` : "");

function lessonReminders(prefs, day, minute) {
  const lead = Number(prefs.categories.lessons.lead) || CATEGORY_DEFAULTS.lessons.lead;
  return lessonsFor(day)
    .filter((lesson) => !lesson.cancelled && dueAt(minute, lesson.startMin - lead))
    .map((lesson) => ({
      key: `lesson:${isoDate(day)}:${lesson.block}`,
      title: BRAND,
      body: `${subject(lesson.subject).label} um ${hm(lesson.start)}${lesson.room ? ` in ${lesson.room}` : ""}.`,
    }));
}

function deadlineReminders(prefs, day) {
  const reminders = [];
  for (const item of data.deadlines || []) {
    const homework = item.kind === "Hausaufgabe";
    const category = prefs.categories[homework ? "homework" : "tests"];
    const days = dayDiff(day, item.date);
    if (!category.on || days < 0 || days > (Number(category.lead) || 1)) continue;
    if (homework && item.status === "abgegeben") continue;
    reminders.push({
      key: `deadline:${item.id}:${isoDate(day)}`,
      title: `${item.kind}: ${item.title}`,
      body: homework
        ? `Fällig ${whenText(days)}${courseOf(item.subject)}`
        : `${capitalized(whenText(days))}${item.time ? ` um ${hm(item.time)}` : ""}${courseOf(item.subject)}`,
    });
  }
  return reminders;
}

function eventReminders(prefs, day, minute) {
  const lead = Number(prefs.categories.events.lead) || CATEGORY_DEFAULTS.events.lead;
  const today = isoDate(day);
  return (data.events || [])
    .filter((event) => event.date === today && event.start && dueAt(minute, toMin(event.start) - lead))
    .map((event) => ({
      key: `event:${event.id}:${today}`,
      title: event.title,
      body: `Um ${hm(event.start)}${event.place ? ` in ${event.place}` : ""}`,
    }));
}

function taskReminders(day, minute) {
  const today = isoDate(day);
  const open = (data.tasks || []).filter((task) => !task.done && task.date === today);
  const reminders = open
    .filter((task) => task.dueTime && dueAt(minute, toMin(task.dueTime)))
    .map((task) => ({ key: `task:${task.id}:${today}`, title: task.title, body: `Fällig um ${task.dueTime}` }));
  const untimed = open.filter((task) => !task.dueTime);
  if (untimed.length && minute >= MORNING) {
    reminders.push({
      key: `tasks:${today}`,
      title: untimed.length === 1 ? "Heute fällig" : `${untimed.length} Aufgaben heute fällig`,
      body: untimed.slice(0, 3).map((task) => task.title).join(", "),
    });
  }
  return reminders;
}

export function dueReminders(prefs, date) {
  const day = startOfDay(date);
  const minute = minutesOf(date);
  if (!prefs.enabled || isQuiet(minute, prefs.quiet)) return [];
  return [
    ...(prefs.categories.lessons.on ? lessonReminders(prefs, day, minute) : []),
    ...deadlineReminders(prefs, day),
    ...(prefs.categories.events.on ? eventReminders(prefs, day, minute) : []),
    ...(prefs.categories.tasks.on ? taskReminders(day, minute) : []),
  ];
}

function claim(key, stamp) {
  let shown = {};
  try {
    shown = JSON.parse(localStorage.getItem(SHOWN_KEY)) || {};
  } catch {
    shown = {};
  }
  if (shown[key]) return false;
  const oldest = stamp - KEEP_DAYS * 864e5;
  for (const [known, at] of Object.entries(shown)) if (at < oldest) delete shown[known];
  shown[key] = stamp;
  try {
    localStorage.setItem(SHOWN_KEY, JSON.stringify(shown));
  } catch {
    return false;
  }
  return true;
}

function tick() {
  if (!data || Notification.permission !== "granted") return;
  const date = new Date();
  const prefs = readPrefs();
  const icon = document.querySelector('link[rel~="icon"]')?.href;
  for (const reminder of dueReminders(prefs, date)) {
    if (!claim(reminder.key, date.getTime())) continue;
    try {
      new Notification(reminder.title, { body: reminder.body, icon, silent: !prefs.sound });
    } catch {}
  }
}

export function initReminders() {
  if (!("Notification" in window) || !data) return;
  tick();
  setInterval(tick, TICK);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") tick();
  });
}
