import {
  data, flags, esc, icon, now, pinnedTime, toMin, clock, hm, startOfDay, addDays, isoDate, parseDate, dayDiff, minutesOf,
  weekType, abWeeks, isoWeek, subject, hueVar, glue, lessonsFor, activeLessons, nextSchoolDay, relativeDay, inDays, duration, shortDate,
  longDate, eventsOn, nextDeparture, schoolDeparture, weatherAt, rainFrom, hourIcon, hasWeather, storage, changesFor,
  WEEKDAYS, WEEKDAYS_SHORT, MONTHS, MONTHS_SHORT, BRAND } from "./core.js";
import { animates, travels, rich, level, flipKeyed, exitInPlace, enterInPlace, setDigits, pop, crossfade, swapText, breath, chalkCheck, bezier, token, ms } from "./motion.js";
import { renderScene, playIntro, classifyEvent, pickProps } from "./desk.js";
import { toast, openPage, registerSearch, typing, shortcutsEnabled, overlayOpen, placeNear, clampSheet, parseNote, cleanTitle, syncTime } from "./shell.js";
import { tasks as taskApi, deadlines as deadlineApi, notes as noteApi } from "./api.js";

const $ = (id) => document.getElementById(id);
const DAY_START = data.blocks?.length ? Math.min(...data.blocks.map((block) => toMin(block.start))) : 480;
const DAY_END = data.blocks?.length ? Math.max(...data.blocks.map((block) => toMin(block.end))) : 900;
const SPAN = DAY_END - DAY_START;
const cap = (text) => text.charAt(0).toUpperCase() + text.slice(1);
const clamp = (value, low = 0, high = 1) => Math.min(high, Math.max(low, value));
const widow = (text) => text.replace(/ (\S{1,12})$/, "\u00a0$1");
const nb = (text) => String(text).replace(/ /g, " ");

const state = {
  tasks: flags.empty ? [] : data.tasks.map((task) => ({ ...task })),
  deadlines: flags.empty ? [] : data.deadlines.map((item) => ({ ...item })),
  deleted: [],
  doneOpen: false,
  day: null,
  pending: new Set(),
  settleTimer: 0,
  lastCheck: 0,
  pointerInside: false,
  lateSignature: "",
  celebrationDue: false,
};

function computeDay(date) {
  const nowMin = minutesOf(date);
  const lessons = lessonsFor(date);
  const active = activeLessons(lessons);
  const base = { date, nowMin, lessons, active, changes: changesFor(date) };
  if (!active.length) return { ...base, kind: "free", school: nextSchoolDay(date) };
  const first = active[0];
  const last = active[active.length - 1];
  const current = active.find((lesson) => nowMin >= lesson.startMin && nowMin < lesson.endMin);
  if (current) return { ...base, kind: "lesson", lesson: current, next: active.find((lesson) => lesson.startMin >= current.endMin), last };
  if (nowMin < first.startMin) {
    return { ...base, kind: first.startMin - nowMin > 60 ? "morning" : "soon", lesson: first, next: active[1], last };
  }
  const upcoming = active.find((lesson) => lesson.startMin > nowMin);
  if (upcoming) return { ...base, kind: "break", lesson: upcoming, next: active.find((lesson) => lesson.startMin > upcoming.startMin), last };
  if (nowMin - last.endMin <= 30) return { ...base, kind: "afterSoon", last };
  return { ...base, kind: "evening", last, school: nextSchoolDay(date) };
}

const inSchool = (day) => ["lesson", "break", "soon", "morning"].includes(day.kind);
const todayIso = () => isoDate(state.day.date);
const isTodayTask = (task) => !task.date || task.date <= todayIso();
const todayTasks = () => state.tasks.filter(isTodayTask);
const openTasks = () => todayTasks().filter((task) => !task.done);
const doneTasks = () => todayTasks().filter((task) => task.done);
const upcomingTasks = () => state.tasks.filter((task) => !isTodayTask(task) && !task.done);
const deadlineById = (id) => state.deadlines.find((item) => item.id === id);
const byPriority = (a, b) => Number(!!b.priority) - Number(!!a.priority);
const rowFor = (id) => document.querySelector(`#taskList .task[data-id="${CSS.escape(id)}"], #doneList .task[data-id="${CSS.escape(id)}"]`);
const label = (key) => subject(key).label;
const isTest = (item) => item.kind === "Test" || item.kind === "Klausur";

function testOnDate(iso, block) {
  return state.deadlines.find((item) => isTest(item) && item.date === iso && (!block || item.block === block));
}

function spoken(min) {
  if (min < 60) return `${min} ${min === 1 ? "Minute" : "Minuten"}`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  const hours = `${h} ${h === 1 ? "Stunde" : "Stunden"}`;
  return m ? `${hours} ${m} ${m === 1 ? "Minute" : "Minuten"}` : hours;
}

function effort(min) {
  if (min < 60) return `${min} Min.`;
  const halves = Math.round(min / 30);
  const hours = Math.floor(halves / 2);
  return `${hours}${halves % 2 ? "½" : ""} Std.`;
}

function weatherWord(item) {
  if (item.rain >= 50) return `Regen, ${item.rain} %`;
  if (item.rain >= 30) return `Niesel, ${item.rain} %`;
  return "trocken";
}

function weatherPhrase(fromHour) {
  const rain = rainFrom(fromHour);
  if (rain == null) return fromHour >= 17 ? "den Abend über trocken" : "bis zum Abend trocken";
  if (rain <= fromHour) return `Regen um ${fromHour} Uhr`;
  return `trocken bis ${rain} Uhr`;
}

const weatherButton = (text, tail = "") => `<span class="glue"><button type="button" class="inline-action" data-open-weather popovertarget="weatherSheet">${text}</button>${tail}</span>`;

function overdueText(diff, target) {
  if (diff === -1) return "seit gestern überfällig";
  if (diff > -7) return `seit ${-diff} Tagen überfällig`;
  return `seit ${WEEKDAYS_SHORT[target.getDay()]}., ${target.getDate()}.${target.getMonth() + 1}. überfällig`;
}

function changeLine(day) {
  const cancelled = day.lessons.filter((lesson) => lesson.cancelled);
  const moved = day.lessons.filter((lesson) => lesson.movedFrom);
  const lines = [];
  if (cancelled.length) {
    const end = day.active.length ? day.active[day.active.length - 1].end : null;
    lines.push(`${cancelled.map((lesson) => `${lesson.block}.`).join(" und ")} Block entfällt${end ? `, Schluss um ${hm(end)}` : ""}`);
  }
  moved.forEach((lesson) => lines.push(`${lesson.block}. Block heute in ${lesson.room} statt ${lesson.movedFrom}`));
  if (!lines.length) return "";
  return `<p class="today-change">${icon("calendar-x-2")}<span>${esc(lines.join(". "))}.</span></p>`;
}

function lessonMeta(lesson, prefix = "") {
  const room = lesson.movedFrom ? `<b>${esc(lesson.room)}</b> statt ${esc(lesson.movedFrom)}` : `<b>${esc(lesson.room)}</b>`;
  return `${prefix}${room}, ${esc(lesson.teacher)}`;
}

function timeLine(parts) {
  if (parts.plain != null) return `<p class="today-time is-plain">${parts.plain}</p>`;
  const value = parts.value != null ? `<span class="today-count digits" data-digits="${esc(parts.value)}">${esc(parts.value)}</span>` : "";
  return `<p class="today-time"><span class="today-time-visual" aria-hidden="true"><span class="today-time-lead">${esc(parts.lead)}</span>${value}${parts.unit ? `<span class="today-time-unit">${esc(parts.unit)}</span>` : ""}${parts.tail ? `<span class="today-time-tail">${esc(parts.tail)}</span>` : ""}</span><span class="visually-hidden" data-sr-time></span></p>`;
}

function reachableBus(day) {
  const fromMin = Math.max(day.last.endMin, day.nowMin);
  const bus = nextDeparture(fromMin);
  if (!bus) return null;
  const earlier = nextDeparture(day.last.endMin);
  const missed = earlier && earlier.time !== bus.time ? earlier.time : null;
  return { ...bus, missed };
}

function morningBus(day) {
  if (day.kind !== "morning" && day.kind !== "soon") return null;
  const bus = schoolDeparture(day.lesson.startMin, day.nowMin);
  if (!bus) return null;
  const leave = bus.leave - day.nowMin;
  return leave <= 10 || bus.late ? { ...bus, leaveIn: Math.max(0, leave) } : null;
}

function heroNow(day) {
  const change = inSchool(day) ? changeLine(day) : "";
  const title = (text) => `<h2 class="today-title" id="todayTitle">${esc(text)}</h2>`;
  const busNow = morningBus(day);
  if (busNow) {
    const arrival = busNow.late ? `, <span class="today-late">an ${busNow.arrive}, ${busNow.lateBy}\u00a0Min. nach Beginn</span>` : "";
    const missed = busNow.missed ? `<p class="today-meta is-quiet">Der Bus um ${esc(busNow.missed)} ${day.nowMin >= toMin(busNow.missed) ? "ist schon weg" : "ist nicht mehr zu schaffen"}.</p>` : "";
    const parts = busNow.leaveIn > 0
      ? { lead: "Los in", value: String(busNow.leaveIn), unit: "Min.", tail: "", sr: `Los in ${spoken(busNow.leaveIn)}, Abfahrt ${busNow.time}.` }
      : { lead: "Jetzt los", value: null, unit: "", tail: "", sr: `Jetzt los, Abfahrt ${busNow.time}.` };
    return {
      html: `${change}${title(`${busNow.mode} ${busNow.line} um ${busNow.time}`)}<p class="today-meta">ab <b>${esc(busNow.from)}</b>, ${busNow.walk}\u00a0Min. zu Fuß${arrival}</p>${missed}`,
      parts,
    };
  }
  if (day.kind === "lesson") {
    const lesson = day.lesson;
    const left = lesson.endMin - day.nowMin;
    return {
      html: `${change}${title(label(lesson.subject))}<p class="today-meta">${lessonMeta(lesson, `${lesson.block}. Block, `)}</p>`,
      parts: { lead: "noch", value: String(left), unit: "Min.", tail: `bis ${hm(lesson.end)}`, sr: `Noch ${spoken(left)} bis ${hm(lesson.end)}.` },
    };
  }
  if (day.kind === "break" || day.kind === "soon" || day.kind === "morning") {
    const lesson = day.lesson;
    const wait = lesson.startMin - day.nowMin;
    const meta = `<p class="today-meta">${lessonMeta(lesson, `${lesson.block}. Block, `)}</p>`;
    let parts;
    if (day.kind === "break") parts = { lead: "Pause, noch", value: String(wait), unit: "Min.", tail: `bis ${hm(lesson.start)}`, sr: `Pause, noch ${spoken(wait)} bis ${hm(lesson.start)}.` };
    else if (day.kind === "soon") parts = { lead: "Beginn in", value: String(wait), unit: "Min.", tail: `um ${hm(lesson.start)}`, sr: `Beginn in ${spoken(wait)} um ${hm(lesson.start)}.` };
    else parts = { lead: "Beginn um", value: hm(lesson.start), unit: "Uhr,", tail: `in ${duration(wait)}`, sr: `Beginn um ${hm(lesson.start)} Uhr, in ${spoken(wait)}.` };
    return { html: `${change}${title(label(lesson.subject))}${meta}`, parts };
  }
  if (day.kind === "afterSoon") {
    const bus = reachableBus(day);
    if (bus) {
      const departs = toMin(bus.time) + bus.delay;
      const leave = departs - bus.walk - day.nowMin;
      const delay = bus.delay ? `, heute ${bus.delay} Min. später` : "";
      const missed = bus.missed ? `<p class="today-meta is-quiet">Der Bus um ${esc(bus.missed)} ${day.nowMin >= toMin(bus.missed) ? "ist schon weg" : "ist nicht mehr zu schaffen"}.</p>` : "";
      const parts = leave > 0
        ? { lead: "Los in", value: String(leave), unit: "Min.", tail: "", sr: `Los in ${spoken(leave)}, Abfahrt ${clock(departs)}.` }
        : { lead: "Jetzt los", value: null, unit: "", tail: "", sr: `Jetzt los, Abfahrt ${clock(departs)}.` };
      return {
        html: `${title(`${bus.mode} ${bus.line} um ${bus.time}`)}<p class="today-meta">ab <b>${esc(bus.from)}</b>, ${bus.walk} Min. zu Fuß${delay}</p>${missed}`,
        parts,
      };
    }
  }
  const school = day.school || nextSchoolDay(day.date);
  if (!school) {
    return { html: `${title("Kein Unterricht")}<p class="today-meta">In den nächsten zehn Tagen steht nichts im Stundenplan.</p>`, parts: { plain: "" } };
  }
  const first = school.lessons[0];
  const lastLesson = school.lessons[school.lessons.length - 1];
  const when = cap(relativeDay(school.offset, school.date));
  const test = testOnDate(isoDate(school.date));
  const testText = test ? `, <span class="today-flagline">${esc(subject(test.subject).name.replace(/ LK$/, ""))}-${esc(test.kind)} im ${test.block}. Block</span>` : "";
  const weekNote = school.offset > 1 && abWeeks() ? `, ${weekType(school.date)}-Woche` : "";
  const count = school.lessons.length;
  return {
    html: `${title(label(first.subject))}<p class="today-meta">${esc(when)}, ${first.block}. Block um ${hm(first.start)}, <b>${esc(first.room)}</b></p>`,
    parts: { plain: `${count} ${count === 1 ? "Block" : "Blöcke"} bis ${hm(lastLesson.end)}${weekNote}${testText}` },
  };
}

function nextBlock(labelText, main, meta) {
  return `<p class="today-next-line"><span class="today-next-label">${labelText}</span><span class="today-next-main">${main}</span></p><p class="today-next-meta">${meta}</p>`;
}

function heroNext(day) {
  const busNow = morningBus(day);
  if (busNow) {
    const lesson = day.lesson;
    return nextBlock("Danach", esc(label(lesson.subject)), `<b>${esc(lesson.room)}</b>, ${hm(lesson.start)}`);
  }
  if (inSchool(day)) {
    const next = day.next;
    if (next) {
      const room = next.movedFrom ? `<b>${esc(next.room)}</b> statt ${esc(next.movedFrom)}` : `<b>${esc(next.room)}</b>`;
      return nextBlock("Danach", esc(label(next.subject)), `${room}, ${hm(next.start)}`);
    }
    const last = day.active[day.active.length - 1];
    const bus = nextDeparture(last.endMin);
    return nextBlock("Danach", "Schulschluss", `um ${hm(last.end)}${bus ? `, ${esc(bus.mode)} ${esc(bus.line)} um <b>${esc(bus.time)}</b>` : ""}`);
  }
  const later = eventsOn(day.date).filter((event) => event.start && toMin(event.start) > day.nowMin);
  if (later.length) {
    const event = later[0];
    return nextBlock(day.kind === "afterSoon" ? "Danach" : "Heute noch", esc(event.title), `<b>${esc(event.start)}</b>, ${esc(event.place)}`);
  }
  const lateTask = (task) => !!task.dueTime && day.nowMin >= toMin(task.dueTime);
  const evening = (task) => /heute abend/i.test(task.anchor || "");
  const open = openTasks().sort((a, b) => Number(lateTask(a)) - Number(lateTask(b)) || Number(evening(b)) - Number(evening(a)) || byPriority(a, b));
  if (open.length && day.nowMin >= 13 * 60) {
    const task = open[0];
    const note = task.deadline ? linkPhrase(task, day.date) : "";
    return nextBlock(day.kind === "evening" ? "Heute Abend noch" : "Heute noch", glue(esc(task.title)), `etwa ${effort(task.minutes || 20)}${note ? `, ${glue(esc(note))}` : ""}`);
  }
  const upcoming = state.deadlines
    .map((item) => ({ ...item, diff: dayDiff(day.date, item.date) }))
    .filter((item) => item.diff >= 1 && !item.pinned)
    .sort((a, b) => a.diff - b.diff || Number(isTest(b)) - Number(isTest(a)))[0];
  if (upcoming) {
    const target = parseDate(upcoming.date);
    const labelText = { Test: "Nächster Test", Klausur: "Nächste Klausur", Referat: "Nächstes Referat", Hausaufgabe: "Nächste Hausaufgabe" }[upcoming.kind] || "Nächste Abgabe";
    const block = upcoming.block ? ` im ${upcoming.block}. Block` : "";
    return nextBlock(labelText, esc(label(upcoming.subject)), `<b>${esc(cap(relativeDay(upcoming.diff, target)))}</b>${block}, ${esc(glue(upcoming.title))}`);
  }
  return nextBlock("Heute noch", "nichts geplant", "Kalender und IServ sind abgeglichen");
}

function heroAfter(day) {
  const pieces = [];
  if (day.kind === "lesson" || day.kind === "break") {
    const last = day.active[day.active.length - 1];
    const bus = nextDeparture(last.endMin);
    if (bus) {
      const delay = bus.delay ? `, heute ${bus.delay} Min. später` : "";
      const hour = Math.floor(toMin(bus.time) / 60);
      const late = delay ? delay.replace(/^, /, "") : "";
      const weather = hasWeather() ? weatherButton(weatherPhrase(hour), ".") : "";
      const tail = weather ? `${late ? ` ${late},` : ""} ${weather}` : late ? ` ${late}.` : "";
      pieces.push(`Heimweg mit dem <span class="glue"><button type="button" class="inline-action" data-page-action="vbb">${esc(bus.mode)} ${esc(bus.line)} um ${esc(bus.time)}</button>${tail ? "," : "."}</span>${tail}`);
    }
    const evening = eventsOn(day.date).filter((event) => event.start && toMin(event.start) >= last.endMin);
    if (evening.length) pieces.push(`Danach ${evening.map((event) => `${esc(event.start)} ${esc(event.title)}`).join(" und ")}.`);
  } else if (day.kind === "soon" || day.kind === "morning") {
    const first = day.active[0];
    const bus = morningBus(day) ? null : schoolDeparture(first.startMin, day.nowMin);
    const hour = Math.max(6, Math.floor(day.nowMin / 60));
    const current = weatherAt(hour);
    if (bus) {
      const leave = bus.leave - day.nowMin;
      const when = leave <= 15 ? `los in ${leave}\u00a0Minuten` : `los um ${clock(bus.leave)}`;
      pieces.push(`Zur Schule mit dem <span class="glue"><button type="button" class="inline-action" data-page-action="vbb">${esc(bus.mode)} ${esc(bus.line)} um ${esc(bus.time)}</button>,</span> ${when}.`);
    }
    const last = day.active[day.active.length - 1];
    pieces.push(current ? `Draußen ${weatherButton(`${current.temp}°, ${weatherPhrase(hour)}`, ".")} Schluss um ${hm(last.end)}.` : `Schluss um ${hm(last.end)}.`);
  } else {
    const later = eventsOn(day.date).filter((event) => event.start && toMin(event.start) > day.nowMin);
    const outdoor = hasWeather() ? later.find((event) => event.place && !/discord|online|zoom/i.test(event.place)) : null;
    if (outdoor) {
      const item = weatherAt(Math.floor(toMin(outdoor.start) / 60));
      pieces.push(`${esc(outdoor.title)} um ${esc(outdoor.start)}: ${weatherButton(weatherWord(item), ".")}`);
    }
    const rest = later.filter((event) => event !== outdoor && event !== later[0]);
    if (rest.length) pieces.push(`Später ${rest.map((event) => `${esc(event.start)} ${esc(event.title)}`).join(" und ")}.`);
    const morning = data.weather.tomorrowMorning;
    const school = day.school;
    if (!outdoor && day.nowMin >= 17 * 60 && morning && school?.offset === 1) {
      const bus = schoolDeparture(school.lessons[0].startMin, 0);
      pieces.push(`Morgen früh ${weatherButton(`${morning.temp}°, ${morning.rain >= 40 ? "Regen" : "trocken"}`, bus ? "," : ".")}${bus ? ` ${esc(bus.mode)} ${esc(bus.line)} um ${esc(bus.time)}.` : ""}`);
    } else if (!outdoor && day.nowMin < 22 * 60 && hasWeather()) {
      const hour = Math.max(7, Math.floor(day.nowMin / 60));
      pieces.push(`Wetter: ${weatherButton(weatherPhrase(hour), ".")}`);
    }
  }
  return pieces.map((piece) => `<span class="after-piece">${piece}</span>`).join(" ");
}

function timeInline(parts) {
  if (parts.plain != null) return parts.plain;
  const value = parts.value != null ? `<span class="today-count digits" data-digits="${esc(parts.value)}">${esc(parts.value)}</span>` : "";
  return `<span class="today-time-visual" aria-hidden="true">${esc(parts.lead)} ${value}${parts.unit ? ` ${esc(parts.unit)}` : ""}</span><span class="visually-hidden" data-sr-time></span>`;
}

function heroCopy(day) {
  const change = inSchool(day) ? changeLine(day) : "";
  const title = (text) => `<h2 class="today-title" id="todayTitle">${esc(text)}</h2>`;
  const eyebrow = (text) => `<p class="today-eyebrow">${text}</p>`;
  const place = (lesson) => (lesson.movedFrom ? `<b>${esc(lesson.room)}</b> statt ${esc(lesson.movedFrom)}` : `<b>${esc(lesson.room)}</b>`);
  const upNext = (lesson) => `Danach <b>${esc(label(lesson.subject))}</b>, ${esc(lesson.room)}, ${hm(lesson.start)}`;
  const closing = (last) => `Danach Schulschluss um <b>${hm(last.end)}</b>`;
  const tomorrow = (school) => {
    if (!school) return "In den nächsten zehn Tagen steht nichts im Stundenplan";
    const first = school.lessons[0];
    return `${esc(cap(relativeDay(school.offset, school.date)))} <b>${esc(label(first.subject))}</b> um ${hm(first.start)}`;
  };
  if (day.kind === "lesson") {
    const lesson = day.lesson;
    const left = lesson.endMin - day.nowMin;
    return {
      head: `${eyebrow(`Jetzt, ${lesson.block}. Block`)}${change}${title(label(lesson.subject))}`,
      meta: `${place(lesson)}, ${esc(lesson.teacher)}, `,
      parts: { lead: "noch", value: String(left), unit: "Min.", sr: `Noch ${spoken(left)} bis ${hm(lesson.end)}.` },
      next: day.next ? upNext(day.next) : closing(day.last),
    };
  }
  if (day.kind === "break" || day.kind === "soon" || day.kind === "morning") {
    const lesson = day.lesson;
    const wait = lesson.startMin - day.nowMin;
    const head = day.kind === "break" ? `Pause bis ${hm(lesson.start)}` : day.kind === "soon" ? `Gleich, ${lesson.block}. Block` : `Heute ab ${hm(lesson.start)}`;
    const parts = day.kind === "morning"
      ? { plain: `in ${duration(wait)}` }
      : { lead: "in", value: String(wait), unit: "Min.", sr: `Beginn in ${spoken(wait)} um ${hm(lesson.start)}.` };
    return {
      head: `${eyebrow(head)}${change}${title(label(lesson.subject))}`,
      meta: `${place(lesson)}, ${esc(lesson.teacher)}, `,
      parts,
      next: day.next ? upNext(day.next) : closing(day.last),
    };
  }
  const later = eventsOn(day.date).filter((event) => event.start && toMin(event.end || event.start) > day.nowMin);
  const school = day.school || nextSchoolDay(day.date);
  const open = openTasks();
  const workload = open.length ? `${open.length} ${open.length === 1 ? "Aufgabe" : "Aufgaben"} offen, etwa ${effort(open.reduce((sum, task) => sum + (task.minutes || 0), 0))}` : "Alle Aufgaben erledigt";
  if (day.kind === "free") {
    const weekend = [0, 6].includes(day.date.getDay());
    const event = later[0];
    return {
      head: `${eyebrow(weekend ? "Wochenende" : "Heute frei")}${title(event ? event.title : "Kein Unterricht")}`,
      meta: event ? `<b>${esc(event.start)}</b>${event.place ? `, ${esc(event.place)}` : ""}` : workload,
      parts: { plain: "" },
      next: tomorrow(school),
    };
  }
  const evening = day.nowMin >= 17 * 60;
  if (later.length) {
    const [event, second] = later;
    const started = toMin(event.start) <= day.nowMin;
    return {
      head: `${eyebrow(started ? "Jetzt" : evening ? "Heute Abend" : "Heute Nachmittag")}${title(event.title)}`,
      meta: `<b>${esc(event.start)}</b>${event.end ? ` bis ${esc(event.end)}` : ""}${event.place ? `, ${esc(event.place)}` : ""}`,
      parts: { plain: "" },
      next: second ? `Danach <b>${esc(second.title)}</b> um ${esc(second.start)}` : tomorrow(school),
    };
  }
  return {
    head: `${eyebrow(day.kind === "afterSoon" ? `Schule vorbei um ${hm(day.last.end)}` : evening ? "Heute Abend" : "Heute Nachmittag")}${title("Feierabend")}`,
    meta: workload,
    parts: { plain: "" },
    next: tomorrow(school),
  };
}

const PREVIEW = {
  gym: ["Gym", "Fitnessstudio", "training"],
  fussball: ["Fußballtraining", "Sportplatz", "training"],
  basketball: ["Basketball", "Sporthalle", "training"],
  tennis: ["Tennis", "Tennisclub", "training"],
  laufen: ["Laufen", "Stadtpark", "training"],
  schwimmen: ["Schwimmtraining", "Hallenbad", "training"],
  tanzen: ["Tanztraining", "Tanzschule", "training"],
  sport: ["Training", "Sporthalle", "training"],
  call: ["Referat-Treffen", "Discord", "school"],
  treffen: ["Abikasse-Treffen", "R101", "school"],
  kino: ["Kino mit Ben", "Stadtkino", "private"],
  fahrstunde: ["Fahrstunde", "Fahrschule", "private"],
  wandertag: ["Wandertag Q3", "Treffpunkt Bahnhof", "school"],
  geburtstag: ["Geburtstag von Lea", "bei Lea", "private"],
};

function previewEvents(day) {
  const preset = PREVIEW[flags.scene];
  if (!preset) return [];
  const start = Math.min(day.nowMin + 60, 22 * 60);
  return [{ id: "preview", date: isoDate(day.date), start: clock(start), end: clock(start + 90), title: preset[0], place: preset[1], kind: preset[2] }];
}

function eventTip(event, nowMin) {
  if (!event.start) return `${event.title}, ganzer Tag`;
  if (toMin(event.start) <= nowMin) return `${event.title} läuft${event.end ? ` bis ${event.end}` : ""}`;
  return `${event.title} um ${event.start}${event.place ? `, ${event.place}` : ""}`;
}

function sceneModel(day) {
  const open = openTasks();
  const total = todayTasks().length;
  const preview = !!flags.scene;
  const later = (preview ? previewEvents(day) : eventsOn(day.date)).filter((event) => !event.start || toMin(event.end || event.start) > day.nowMin);
  const deadlines = state.deadlines.map((item) => ({ ...item, diff: dayDiff(day.date, item.date) }));
  const test = deadlines.filter((item) => isTest(item) && item.diff >= 0 && item.diff <= 4).sort((a, b) => a.diff - b.diff)[0];
  const talk = deadlines.some((item) => item.kind === "Referat" && item.diff >= 0 && item.diff <= 21) && open.some((task) => /referat|folie/i.test(task.title));
  const due = deadlines.filter((item) => !isTest(item) && !item.pinned && item.diff >= -7 && item.diff <= 3 && item.status !== "abgegeben").length;
  const hour = day.nowMin / 60;
  const time = hour < 5 || hour >= 21 ? "night" : hour < 7.5 ? "dawn" : hour < 17.5 ? "day" : "dusk";
  const bloom = total > 0 && !open.length;
  const lampOn = (!!test && test.diff <= 1) || time === "dusk" || time === "night";
  const candidates = [];
  let call = false;
  later.forEach((event) => {
    const key = classifyEvent(event);
    if (!key) return;
    const until = event.start ? Math.max(0, toMin(event.start) - day.nowMin) : 0;
    if (key === "phones" && until <= 180) call = true;
    candidates.push({ key, tip: eventTip(event, day.nowMin), rank: until <= 180 ? 1 : 3, order: until });
  });
  const testText = test ? `${subject(test.subject).name.replace(/ LK$/, "")}-${test.kind} ${relativeDay(test.diff, parseDate(test.date))}` : "";
  if (test && !preview) candidates.push({ key: "cards", tip: testText, rank: test.diff <= 1 ? 2 : 4, order: test.diff });
  if (flags.scene === "test") candidates.push({ key: "cards", tip: "Mathe-Test morgen", rank: 0, order: 0 });
  const reading = open.find((task) => /lesen|lektüre|kapitel|korrektur/i.test(task.title));
  if (reading && !preview) candidates.push({ key: "book", tip: reading.title, rank: 5, order: 0 });
  if (flags.scene === "lesen") candidates.push({ key: "book", tip: "Seminararbeit: Kapitel 3 gegenlesen", rank: 0, order: 0 });
  if (!day.active.length && !preview) candidates.push({ key: "football", tip: "Heute frei", rank: 6, order: 0 });
  const props = pickProps(candidates);
  const bits = [open.length ? `${open.length} ${open.length === 1 ? "offene Aufgabe" : "offene Aufgaben"}` : bloom ? "alles erledigt" : "nichts offen", ...props.map((prop) => prop.tip).filter(Boolean)];
  return {
    time,
    minute: day.nowMin,
    books: Math.min(4, open.length),
    papers: open.length > 4,
    screen: call ? "call" : !open.length ? "closed" : talk ? "slides" : "text",
    lamp: lampOn || !!test,
    lampOn,
    notes: Math.min(3, due),
    bloom,
    props,
    label: `Schreibtisch: ${bits.join(", ")}`,
  };
}

function refreshScene() {
  if (state.day) renderScene($("scene"), sceneModel(state.day));
}

function applyTime(node, parts) {
  const digits = node.querySelector(".today-count");
  if (digits) setDigits(digits, digits.dataset.digits, -1);
  const sr = node.querySelector("[data-sr-time]");
  if (sr) sr.textContent = parts.sr || "";
}

function renderHero(day, previous) {
  const nowNode = $("todayNow");
  const nextNode = $("todayNext");
  const copy = heroCopy(day);
  const now = { parts: copy.parts };
  const html = `${copy.head}<p class="today-meta">${copy.meta}${timeInline(copy.parts)}</p>`;
  const shape = html.replace(/data-digits="[^"]*"[^<]*/, "");
  const changedFocus = previous && (previous.kind !== day.kind || previous.lesson?.block !== day.lesson?.block);
  if (nowNode.dataset.shape !== shape) {
    nowNode.dataset.shape = shape;
    if (changedFocus && animates()) {
      swapText(nowNode, html);
      setTimeout(() => applyTime(nowNode, now.parts), 160);
    } else {
      nowNode.innerHTML = html;
    }
  } else {
    const count = nowNode.querySelector(".today-count");
    if (count) count.dataset.digits = now.parts.value;
  }
  applyTime(nowNode, now.parts);
  const nextHtml = copy.next;
  if (nextNode.dataset.html !== nextHtml) {
    nextNode.dataset.html = nextHtml;
    if (changedFocus && animates()) swapText(nextNode, nextHtml);
    else nextNode.innerHTML = nextHtml;
  }
  const after = "";
  const afterNode = $("todayAfter");
  afterNode.hidden = !after;
  if (afterNode.dataset.html !== after) {
    afterNode.dataset.html = after;
    afterNode.innerHTML = after;
  }
  if (changedFocus) breath($("trackNow"));
}

function trackModel(day) {
  if (["free", "evening"].includes(day.kind)) {
    const school = day.school;
    if (!school) return { mode: "empty", lessons: [], date: day.date };
    return { mode: "preview", lessons: lessonsFor(school.date), date: school.date, offset: school.offset };
  }
  return { mode: "today", lessons: day.lessons, date: day.date };
}

function segmentState(day, model, lesson) {
  if (lesson.cancelled) return "is-cancelled";
  if (model.mode === "preview") return lesson === activeLessons(model.lessons)[0] ? "is-next" : "";
  if (lesson.endMin <= day.nowMin) return "is-done";
  if (day.kind === "lesson" && lesson.block === day.lesson.block) return "is-now";
  if (["break", "soon", "morning"].includes(day.kind) && lesson.block === day.lesson.block) return "is-next";
  if (day.kind === "lesson" && day.next && lesson.block === day.next.block) return "is-next";
  return "";
}

const stateWords = { "is-done": "vorbei", "is-now": "läuft", "is-next": "als Nächstes", "is-cancelled": "entfällt" };

function renderTrack(day) {
  const track = $("track");
  const model = trackModel(day);
  const byBlock = new Map(model.lessons.map((lesson) => [lesson.block, lesson]));
  const signature = `${model.mode}|${isoDate(model.date)}|${model.lessons.map((lesson) => `${lesson.block}${lesson.subject}${lesson.cancelled ? "x" : ""}${lesson.room}`).join()}`;
  track.setAttribute("aria-label", model.mode === "preview" ? `Blöcke am ${longDate(model.date)}` : "Blöcke heute");
  if (track.dataset.signature !== signature) {
    track.dataset.signature = signature;
    const caption = model.mode === "preview" ? `<span class="track-caption" aria-hidden="true">Blöcke ${esc(relativeDay(model.offset, model.date))}</span>` : "";
    track.innerHTML = data.blocks.map((block) => {
      const start = toMin(block.start);
      const left = ((start - DAY_START) / SPAN) * 100;
      const width = ((toMin(block.end) - start) / SPAN) * 100;
      const lesson = byBlock.get(block.n);
      const time = `${hm(block.start)}–${hm(block.end)}`;
      const place = `style="left:${left.toFixed(3)}%;width:${width.toFixed(3)}%"`;
      if (!lesson) {
        return `<div class="segment is-free" role="button" aria-disabled="true" data-block="${block.n}" tabindex="-1" ${place} aria-label="${block.n}. Block, ${hm(block.start)} bis ${hm(block.end)}, frei">
          <span class="segment-time"><span class="segment-clock">${time}</span></span><span class="segment-label"><span class="label-full">Frei</span><span class="label-short">frei</span></span></div>`;
      }
      const info = subject(lesson.subject);
      const test = testOnDate(isoDate(model.date), block.n);
      const tip = `${block.n}. Block, ${time}: <b>${esc(info.name)}</b> in ${esc(lesson.room)}, ${esc(lesson.teacher)}${test ? `<br>${esc(test.kind)}: ${esc(test.title)}` : ""}${lesson.cancelled ? "<br>Entfällt" : ""}`;
      return `<div class="segment" role="button" data-block="${block.n}" tabindex="-1" data-tip="${esc(tip)}" data-tip-side="below" data-page-action="school" ${place}>
        <span class="segment-fill" aria-hidden="true"></span>
        <svg class="segment-outline" aria-hidden="true" focusable="false"><rect pathLength="1"/></svg>
        <span class="segment-time"><span class="segment-done-icon">${icon("check")}</span><span class="segment-clock">${time}</span></span>
        <span class="segment-label"><span class="label-full">${esc(info.label)}</span><span class="label-short">${esc(info.short)}</span><small>${esc(lesson.room)}</small></span>
        ${test ? `<span class="segment-flag">${esc(test.kind)}</span>` : ""}
      </div>`;
    }).join("") + `<span class="track-now" id="trackNow" aria-hidden="true" hidden><span class="track-now-label"></span></span>${caption}`;
  }
  let focusTarget = null;
  track.querySelectorAll(".segment[data-block]").forEach((node) => {
    const lesson = byBlock.get(Number(node.dataset.block));
    if (!lesson) return;
    const cls = segmentState(day, model, lesson);
    ["is-done", "is-now", "is-next", "is-cancelled"].forEach((name) => node.classList.toggle(name, name === cls));
    const progress = cls === "is-now" ? (day.nowMin - lesson.startMin) / (lesson.endMin - lesson.startMin) : 0;
    node.style.setProperty("--p", progress.toFixed(4));
    const test = testOnDate(isoDate(model.date), lesson.block);
    const status = stateWords[cls];
    node.setAttribute("aria-label", `${lesson.block}. Block, ${hm(lesson.start)} bis ${hm(lesson.end)}, ${subject(lesson.subject).name}, ${lesson.room}, ${lesson.teacher}${test ? `, ${test.kind}` : ""}${status ? `, ${status}` : ""}`);
    if (!focusTarget && (cls === "is-now" || cls === "is-next")) focusTarget = node;
  });
  const segments = [...track.querySelectorAll(".segment")];
  const active = segments.find((node) => node.tabIndex === 0);
  if (!active || !track.contains(document.activeElement)) {
    const pick = focusTarget || segments.find((node) => !node.classList.contains("is-free")) || segments[0];
    segments.forEach((node) => (node.tabIndex = node === pick ? 0 : -1));
  }
  placeMarker(day, model);
}

function markerFor(day, model) {
  if (model.mode !== "today" || !day.active.length) return null;
  if (day.kind === "morning" || day.kind === "soon") return { x: 0, gap: true };
  if (day.nowMin > DAY_END + 30) return null;
  return { x: clamp((day.nowMin - DAY_START) / SPAN), gap: day.kind !== "lesson" };
}

function setMarker(marker, x, minute) {
  marker.style.setProperty("--x", x.toFixed(4));
  marker.classList.toggle("is-start", x < 0.045);
  marker.classList.toggle("is-end", x > 0.955);
  marker.querySelector(".track-now-label").textContent = clock(Math.round(minute));
}

function placeMarker(day, model) {
  const marker = $("trackNow");
  if (!marker) return;
  const spot = markerFor(day, model);
  marker.hidden = !spot;
  if (!spot) return;
  marker.classList.toggle("is-gap", spot.gap);
  if (!sweep) setMarker(marker, spot.x, day.nowMin);
}

let sweep = null;
const sweepCurve = bezier(0.65, 0, 0.35, 1);

function sweepTrack(day, { from, duration, delay = 0, arrive = true }) {
  const model = trackModel(day);
  const spot = markerFor(day, model);
  if (!spot || day.kind === "morning" || day.kind === "soon") return;
  const track = $("track");
  const marker = $("trackNow");
  const target = day.nowMin;
  const start = clamp(from, DAY_START, target);
  if (target - start < 3) return;
  sweep?.finish();
  const lessonsByBlock = new Map(model.lessons.map((lesson) => [lesson.block, lesson]));
  const segments = [...track.querySelectorAll(".segment[data-block]")]
    .map((node) => ({ node, lesson: lessonsByBlock.get(Number(node.dataset.block)) }))
    .filter((item) => item.lesson && !item.lesson.cancelled);
  const passing = segments.filter(({ lesson }) => lesson.endMin > start && lesson.endMin <= target);
  const current = segments.find(({ node }) => node.classList.contains("is-now"));
  const lightsUp = current && current.lesson.startMin > start;
  track.classList.add("is-sweeping", "is-live");
  passing.forEach(({ node }) => node.classList.remove("is-done"));
  if (lightsUp) current.node.classList.remove("is-now");
  let finished = false;
  let frame = 0;
  const apply = (minute) => {
    setMarker(marker, clamp((minute - DAY_START) / SPAN), minute);
    passing.forEach(({ node, lesson }) => {
      if (minute >= lesson.endMin && !node.classList.contains("is-done")) {
        node.classList.add("is-done");
        if (rich()) node.animate([{ scale: 1 }, { scale: 1.03 }, { scale: 1 }], { duration: 260, easing: token("--ease-out") });
      }
    });
    if (current) {
      const { lesson, node } = current;
      if (lightsUp && minute >= lesson.startMin) node.classList.add("is-now");
      node.style.setProperty("--p", clamp((minute - lesson.startMin) / (lesson.endMin - lesson.startMin)).toFixed(4));
    }
  };
  const stopEvents = ["pointerdown", "keydown", "wheel", "touchstart"];
  const finish = () => {
    if (finished) return;
    finished = true;
    cancelAnimationFrame(frame);
    stopEvents.forEach((type) => removeEventListener(type, finish, true));
    apply(target);
    track.classList.remove("is-sweeping");
    sweep = null;
    if (arrive) breath(marker);
  };
  apply(start);
  stopEvents.forEach((type) => addEventListener(type, finish, { capture: true, passive: true }));
  let origin = null;
  const step = (time) => {
    if (finished) return;
    if (origin === null) origin = time + delay;
    const progress = clamp((time - origin) / duration);
    apply(start + sweepCurve(progress) * (target - start));
    if (progress < 1) frame = requestAnimationFrame(step);
    else finish();
  };
  frame = requestAnimationFrame(step);
  sweep = { finish };
}

function layoutTrack({ outline = true } = {}) {
  if (!travels()) return;
  const segments = [...$("track").querySelectorAll(".segment")];
  const curve = token("--ease-out");
  segments.forEach((node, index) => node.animate([{ opacity: 0.35, scale: 0.96 }, { opacity: 1, scale: 1 }], { duration: 240, delay: 40 + index * 40, easing: curve, fill: "backwards" }));
  const marker = $("trackNow");
  if (marker && !marker.hidden) marker.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, delay: 60, easing: curve, fill: "backwards" });
  const next = $("track").querySelector(".segment.is-next .segment-outline rect");
  if (outline && next) next.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { duration: 320, delay: 60 + segments.length * 40 + 80, easing: curve, fill: "backwards" });
}

function linkPhrase(task, date) {
  const item = task.deadline ? deadlineById(task.deadline) : null;
  if (!item) return "";
  const diff = dayDiff(date, item.date);
  if (diff === 0 && item.kind === "Hausaufgabe") return "";
  const target = parseDate(item.date);
  const when = item.pinned ? "" : diff === 1 ? " morgen" : diff < 7 ? ` am ${WEEKDAYS[target.getDay()]}` : ` am ${target.getDate()}.${target.getMonth() + 1}.`;
  const noun = { Test: "den Test", Klausur: "die Klausur", Referat: "das Referat", Abgabe: item.pinned ? "die Seminararbeit" : "die Abgabe", Hausaufgabe: "die Hausaufgabe" }[item.kind] || "die Abgabe";
  return `für ${noun}${when}`;
}

function renderHeader(day) {
  const date = day.date;
  $("headDate").textContent = longDate(date);
  $("headWeek").textContent = abWeeks() ? `${weekType(date)}-Woche, KW ${isoWeek(date)}` : `KW ${isoWeek(date)}`;
  document.title = `${longDate(date)} · ${BRAND}`;
}

function taskMeta(task, date) {
  const info = task.subject ? subject(task.subject) : null;
  const parts = [];
  if (info) parts.push(`<span class="subject"><i class="subject-dot" style="--hue:${hueVar(task.subject)}"></i>${esc(info.label)}</span>`);
  if (task.done) {
    parts.push(`erledigt um ${esc(task.doneAt || task.anchor?.replace(/^erledigt um /, "") || "")}`);
    return parts.join(", ");
  }
  const late = task.dueTime && state.day && state.day.nowMin >= toMin(task.dueTime) && isoDate(state.day.date) === todayIso();
  if (late) parts.push(`<span class="row-note is-urgent">seit ${esc(task.dueTime)} fällig</span>`);
  else if (task.anchor) parts.push(glue(esc(task.anchor)));
  return parts.join(", ");
}

function taskRow(task, date) {
  const title = esc(task.title);
  const meta = taskMeta(task, date);
  return `<li class="row task is-interactive${task.done ? " is-done" : ""}" data-id="${esc(task.id)}" tabindex="-1">
    <button class="check" type="button" role="checkbox" aria-checked="${task.done}" aria-label="${title}">${icon("check")}</button>
    <div class="row-main">
      <p class="row-title"><span>${widow(glue(title))}</span></p>
      ${meta ? `<p class="row-meta">${meta}</p>` : ""}
    </div>
    <div class="row-trailing">
      ${task.done ? "" : `<div class="row-actions">
        <button class="icon-button" type="button" data-act="later" aria-label="Auf morgen verschieben: ${title}" data-tip="Auf morgen">${icon("calendar-plus")}</button>
        <button class="icon-button" type="button" data-act="delete" aria-label="Löschen: ${title}" data-tip="Löschen">${icon("trash-2")}</button>
      </div>
      <button class="icon-button row-menu-button" type="button" data-act="menu" aria-label="Aktionen für ${title}" aria-haspopup="menu" aria-controls="rowMenu">${icon("ellipsis")}</button>`}
      ${task.priority && !task.done ? `<span class="flag" data-tip="Wichtig" role="img" aria-label="Wichtig">${icon("flag")}</span>` : ""}
    </div>
  </li>`;
}

function deletedRow(entry) {
  const title = esc(entry.task.title);
  return `<li class="row task is-deleted" data-deleted="${esc(entry.task.id)}">
    <span class="deleted-mark" aria-hidden="true">${icon("trash-2")}</span>
    <div class="row-main">
      <p class="row-title"><span>${widow(glue(title))}</span></p>
      <p class="row-meta">gelöscht um ${esc(entry.at)}</p>
    </div>
    <div class="row-trailing"><button class="text-button restore-button" type="button" data-restore="${esc(entry.task.id)}" aria-label="Wiederherstellen: ${title}">${icon("undo-2")}<span>Wiederherstellen</span></button></div>
  </li>`;
}

function allDoneLine() {
  return `<li class="empty-line all-done" data-flip="tasks-done"><span class="all-done-mark" aria-hidden="true"></span><span class="all-done-text">Alles für heute erledigt.<small>Die nächste Abgabe steht unter Fällig.</small></span></li>`;
}

function renderTaskMeta() {
  const done = doneTasks();
  const filed = done.filter((task) => !state.pending.has(task.id));
  const total = todayTasks().length;
  const meta = $("tasksMeta");
  if (!total) {
    meta.replaceChildren();
  } else {
    if (!$("doneDigits")) meta.innerHTML = `<span class="digits" id="doneDigits"></span><span id="tasksMetaRest"></span>`;
    setDigits($("doneDigits"), done.length, 1);
    $("tasksMetaRest").textContent = ` von ${total} erledigt`;
  }
  const toggle = $("doneToggle");
  const hidden = !filed.length && !state.deleted.length;
  toggle.hidden = hidden;
  const parts = [];
  if (filed.length) parts.push(`${filed.length} erledigt`);
  if (state.deleted.length) parts.push(`${state.deleted.length} gelöscht`);
  $("doneLabel").textContent = parts.join(", ");
  toggle.setAttribute("aria-expanded", String(state.doneOpen && !hidden));
  refreshScene();
}

function renderTasks() {
  const date = state.day.date;
  const list = $("taskList");
  const open = todayTasks().filter((task) => !task.done || state.pending.has(task.id)).sort(byPriority);
  if (!todayTasks().length) {
    list.innerHTML = `<li class="empty-line" data-flip="tasks-empty">Für heute ist nichts offen.<small>Neue Aufgaben legst du hier an.</small></li>`;
  } else if (!open.length) {
    if (!list.querySelector(".all-done")) {
      list.innerHTML = allDoneLine();
      if (!state.celebrationDue) chalkCheck(list.querySelector(".all-done-mark"));
    }
  } else {
    list.innerHTML = open.slice(0, 5).map((task) => taskRow(task, date)).join("");
    if (open.length > 5) list.insertAdjacentHTML("beforeend", `<li class="row is-interactive more-row" data-more-tasks data-flip="tasks-more" tabindex="-1"><span></span><button type="button" class="row-link more-link">${open.length - 5} weitere Aufgaben</button>${icon("chevron-right", "chev-end")}</li>`);
  }
  const doneList = $("doneList");
  const filed = doneTasks().filter((task) => !state.pending.has(task.id));
  doneList.hidden = !(state.doneOpen && (filed.length || state.deleted.length));
  doneList.innerHTML = filed.map((task) => taskRow(task, date)).join("") + state.deleted.map(deletedRow).join("");
  renderTaskMeta();
  state.lateSignature = lateSignature();
}

function lateSignature() {
  if (!state.day) return "";
  return openTasks().filter((task) => task.dueTime && state.day.nowMin >= toMin(task.dueTime)).map((task) => task.id).join();
}

function leaf(target, date, cls) {
  const other = target.getMonth() !== date.getMonth() || target.getFullYear() !== date.getFullYear();
  const top = other ? MONTHS_SHORT[target.getMonth()] : WEEKDAYS_SHORT[target.getDay()];
  return `<div class="leaf ${cls}${other ? " is-month" : ""}" aria-hidden="true"><span class="leaf-day">${top}</span><span class="leaf-date">${target.getDate()}</span></div>`;
}

function dueMeta(item, date) {
  const target = parseDate(item.date);
  const diff = dayDiff(date, item.date);
  const linked = item.source === "task" ? [] : state.tasks.filter((task) => task.deadline === item.id);
  const open = linked.filter((task) => !task.done).length;
  const prepared = linked.length > 0 && open === 0;
  const subjectText = item.subject ? `<span class="subject"><i class="subject-dot" style="--hue:${hueVar(item.subject)}"></i>${esc(label(item.subject))}</span>` : "";
  if (item.pinned) {
    const progress = item.progress;
    const bar = progress
      ? `<span class="units" aria-hidden="true" style="--hue:${hueVar(item.subject)}">${Array.from({ length: progress.total }, (_, index) => `<i${index < progress.done ? ' class="is-on"' : ""}></i>`).join("")}</span>`
      : "";
    const text = progress ? `, ${progress.unit}\u00a0${progress.done}\u00a0von\u00a0${progress.total}` : "";
    return { html: `${subjectText}, ${inDays(diff)}${text}${bar}`, prepared, diff };
  }
  const kind = `<span class="kind${isTest(item) ? " is-test" : ""}">${isTest(item) ? icon("nx-test") : ""}${esc(item.kind)}</span>`;
  let when;
  if (diff < 0) when = `<span class="due-when is-urgent">${overdueText(diff, target)}</span>`;
  else if (diff <= 1) when = `<span class="due-when${prepared ? "" : " is-urgent"}">${cap(relativeDay(diff, target))}</span>`;
  else when = `<span class="due-when">${inDays(diff)}</span>`;
  const prep = prepared ? `, <span class="row-note is-ready">${icon("check")}vorbereitet</span>` : "";
  return { html: `${kind} ${subjectText}${subjectText ? ", " : ""}${when}${prep}`, prepared, diff };
}

function dueRow(item, date) {
  const target = parseDate(item.date);
  const meta = dueMeta(item, date);
  const leafClass = meta.diff < 0 ? "is-overdue" : meta.diff <= 1 && !meta.prepared && !item.pinned ? "is-soon" : "";
  const page = item.source === "task" ? "tasks" : "school";
  return `<li class="row due is-interactive" data-id="${esc(item.id)}" tabindex="-1">
    ${leaf(target, date, leafClass)}
    <div class="row-main">
      <p class="row-title"><a class="row-link" href="${page === "tasks" ? "/hub/tasks" : "/hub/school"}" data-page-action="${page}">${widow(glue(esc(item.title)))}</a></p>
      <p class="row-meta">${meta.html}</p>
    </div>
    ${icon("chevron-right", "chev-end")}
  </li>`;
}

function dueItems(date) {
  const linked = new Set(state.tasks.map((task) => task.deadline).filter(Boolean));
  const deadlines = state.deadlines.map((item) => ({ ...item, source: "deadline", diff: dayDiff(date, item.date) }));
  const own = upcomingTasks().map((task) => ({
    id: task.id, kind: "Aufgabe", title: task.title, subject: task.subject, date: task.date, block: task.block, source: "task", diff: dayDiff(date, task.date),
  }));
  const overdue = deadlines.filter((item) => item.diff < 0 && item.status !== "abgegeben").sort((a, b) => a.diff - b.diff);
  const soon = [
    ...deadlines.filter((item) => item.diff >= 0 && item.diff <= 14 && !item.pinned && !(item.diff === 0 && linked.has(item.id))),
    ...own.filter((item) => item.diff <= 14),
  ].sort((a, b) => a.diff - b.diff || Number(isTest(b)) - Number(isTest(a)));
  const pinned = deadlines.filter((item) => item.pinned && item.diff >= 0);
  return { overdue, soon, pinned };
}

function renderDue() {
  const date = state.day.date;
  const list = $("dueList");
  const { overdue, soon, pinned } = dueItems(date);
  const horizon = addDays(startOfDay(date), 14);
  $("dueMeta").textContent = `bis ${shortDate(horizon)}`;
  if (!overdue.length && !soon.length && !pinned.length) {
    const stand = flags.offline ? ` (Stand ${syncTime()} Uhr)` : "";
    list.innerHTML = `<li class="empty-line" data-flip="due-empty">Bis ${longDate(horizon)} keine Abgaben${stand}.<small>Tests und Hausaufgaben kommen automatisch aus IServ.</small></li>`;
    return;
  }
  let html = overdue.map((item) => dueRow(item, date)).join("");
  html += soon.slice(0, 4).map((item) => dueRow(item, date)).join("");
  if (soon.length > 4) html += `<li class="row is-interactive more-row" data-flip="due-more" tabindex="-1"><span></span><a class="row-link more-link" href="/hub/school" data-page-action="school">${soon.length - 4} weitere bis ${shortDate(horizon)}</a>${icon("chevron-right", "chev-end")}</li>`;
  if (pinned.length) {
    html += `<li class="group-label" data-flip="due-longterm"><h3>Langfristig</h3></li>`;
    html += pinned.map((item) => dueRow(item, date)).join("");
  }
  list.innerHTML = html;
}

function weekStart(day) {
  const date = day.date;
  const monday = addDays(startOfDay(date), 1 - (date.getDay() || 7));
  const dow = date.getDay();
  const afterFriday = dow === 5 && ["afterSoon", "evening"].includes(day.kind);
  if (dow === 0 || dow === 6 || afterFriday) return { monday: addDays(monday, 7), next: true };
  return { monday, next: false };
}

function renderWeek(day) {
  const { monday, next } = weekStart(day);
  const today = isoDate(day.date);
  const friday = addDays(monday, 4);
  $("weekTitle").textContent = next ? "Nächste Woche" : "Diese Woche";
  const long = monday.getMonth() === friday.getMonth()
    ? `${monday.getDate()}. bis ${friday.getDate()}. ${MONTHS[friday.getMonth()]}`
    : `${monday.getDate()}. ${MONTHS[monday.getMonth()]} bis ${friday.getDate()}. ${MONTHS[friday.getMonth()]}`;
  const short = `${monday.getDate()}.${monday.getMonth() === friday.getMonth() ? "" : `${monday.getMonth() + 1}.`}–${friday.getDate()}.${friday.getMonth() + 1}.`;
  $("weekMeta").innerHTML = `${abWeeks() ? `${weekType(monday)}-Woche, ` : ""}<span class="range-long">${esc(long)}</span><span class="range-short">${esc(short)}</span>`;
  const cells = [];
  for (let i = 0; i < 5; i += 1) {
    const date = addDays(monday, i);
    const iso = isoDate(date);
    const lessons = lessonsFor(date);
    const active = activeLessons(lessons);
    const byBlock = new Map(lessons.map((lesson) => [lesson.block, lesson]));
    const isToday = iso === today;
    const past = iso < today || (isToday && ["afterSoon", "evening"].includes(day.kind));
    const bar = data.blocks.map((block) => {
      const lesson = byBlock.get(block.n);
      return lesson && !lesson.cancelled ? `<i style="--hue:${hueVar(lesson.subject)}"></i>` : `<i class="is-free"></i>`;
    }).join("");
    const line = active.length
      ? `${active.length} ${active.length === 1 ? "Block" : "Blöcke"}, ${active[0].startMin === DAY_START ? "" : `${hm(active[0].start)} `}bis ${hm(active[active.length - 1].end)}`
      : "Unterrichtsfrei";
    const overdueHere = state.deadlines.filter((item) => item.date === iso && iso < today && item.status !== "abgegeben");
    const markers = [];
    if (past && !isToday) {
      overdueHere.forEach((item) => markers.push({ order: 0, text: `${item.kind} ${subject(item.subject).name.replace(/ LK$/, "")}, überfällig`, html: `<p class="marker is-overdue">${icon("triangle-alert")}<span>${esc(item.kind)} ${esc(subject(item.subject).name.replace(/ LK$/, ""))}, überfällig</span></p>` }));
    } else {
      state.deadlines.filter((item) => item.date === iso && !item.pinned).forEach((item) => {
        const name = subject(item.subject).name.replace(/ LK$/, "");
        const block = item.block ? `, ${item.block}. Block` : "";
        const test = isTest(item);
        const text = `${item.kind} ${name}${block}`;
        markers.push({ order: test ? 0 : 1, text, html: `<p class="marker${test ? " is-test" : ""}">${icon(test ? "nx-test" : "list-checks")}<span>${esc(text)}</span></p>` });
      });
      state.tasks.filter((task) => task.date === iso && !task.done && iso > today).forEach((task) => {
        markers.push({ order: 1, text: task.title, html: `<p class="marker">${icon("check")}<span>${esc(task.title)}</span></p>` });
      });
      eventsOn(date).forEach((event) => {
        const text = `${event.start ? `${event.start} ` : ""}${event.title}`;
        markers.push({ order: 2, text, html: `<p class="marker">${icon("calendar-clock")}<span>${esc(text)}</span></p>` });
      });
    }
    markers.sort((a, b) => a.order - b.order);
    const shown = markers.slice(0, 2).map((marker) => marker.html).join("");
    const rest = markers.length - 2;
    const extra = rest > 0 ? `<p class="marker-more">und ${rest} ${rest === 1 ? "weiterer Eintrag" : "weitere Einträge"}</p>` : "";
    let headExtra = "";
    if (isToday && !past) headExtra = `<span class="today-tag">heute</span>`;
    else if (past && overdueHere.length) headExtra = `<i class="day-alert" aria-hidden="true"></i>`;
    else if (past) headExtra = icon("check", "day-check");
    const subjects = active.map((lesson) => subject(lesson.subject).name).join(", ");
    const aria = `${longDate(date)}${isToday ? ", heute" : ""}, ${line}${subjects ? `: ${subjects}` : ""}${markers.length ? `. ${markers.map((marker) => marker.text).join(". ")}` : ""}`;
    const classes = ["day", isToday ? "is-today" : "", past && !isToday ? "is-past" : "", past && overdueHere.length ? "has-alert" : ""].filter(Boolean).join(" ");
    cells.push(`<li><button type="button" class="${classes}" data-page-action="calendar" style="--d:${i}" aria-label="${esc(aria)}">
      <span class="day-head"><span class="day-name">${WEEKDAYS_SHORT[date.getDay()]}</span><em>${date.getDate()}.</em>${headExtra}</span>
      <span class="day-bar" aria-hidden="true">${bar}</span>
      <span class="day-body">${past && !isToday ? "" : `<span class="day-line">${esc(line)}</span>`}${shown}${extra}</span>
    </button></li>`);
  }
  const strip = $("weekStrip");
  const html = cells.join("");
  if (strip.dataset.html !== html) {
    strip.dataset.html = html;
    strip.innerHTML = html;
  }
}

function renderWeather() {
  const place = data.weather?.place || "";
  $("weatherTitle").textContent = place ? `Wetter in ${place}` : "Wetter";
  if (!hasWeather()) {
    $("weatherSummary").textContent = place ? `Für ${place} liegt gerade keine Vorhersage vor.` : "Leg in den Einstellungen unter Orte fest, für welchen Ort du das Wetter sehen willst.";
    $("weatherHours").innerHTML = "";
    return;
  }
  const date = now();
  const hour = date.getHours();
  const current = weatherAt(Math.max(6, Math.min(23, hour)));
  const day = state.day;
  const bus = day && (day.kind === "lesson" || day.kind === "break") ? nextDeparture(day.last.endMin) : day?.kind === "afterSoon" ? reachableBus(day) : null;
  const rain = rainFrom(hour);
  const wind = data.weather.wind == null ? "" : `, Wind ${data.weather.wind} km/h`;
  let summary = `Jetzt <b>${current.temp}°</b>, ${current.rain >= 30 ? "Niesel" : hour >= 12 && hour <= 14 ? "heiter bis wolkig" : "bedeckt"}${wind}.`;
  if (bus) {
    const busHour = Math.floor(toMin(bus.time) / 60);
    summary += rain == null || rain > busHour ? ` Heimweg um ${bus.time} noch trocken.` : ` Zum Heimweg um ${bus.time} Regen, Jacke einpacken.`;
  }
  if (rain != null) {
    const info = weatherAt(rain);
    summary += ` Ab ${rain} Uhr ${info.rain >= 50 ? "Regen" : "Niesel"} mit ${info.rain} % Wahrscheinlichkeit.`;
  }
  $("weatherSummary").innerHTML = summary;
  const start = Math.max(6, Math.min(hour, 16));
  $("weatherHours").innerHTML = Array.from({ length: 8 }, (_, index) => {
    const item = weatherAt(start + index);
    const spokenRain = item.rain ? `, Regen ${item.rain} Prozent` : ", trocken";
    return `<li class="hour${item.h === hour ? " is-now" : ""}${item.rain >= 30 ? " is-rain" : ""}" style="--d:${index}" aria-label="${item.h === hour ? "Jetzt" : `${item.h} Uhr`}, ${item.temp} Grad${spokenRain}">
      <span class="hour-time" aria-hidden="true">${item.h === hour ? "Jetzt" : `${item.h} Uhr`}</span>${icon(hourIcon(item))}<b aria-hidden="true">${item.temp}°</b><span class="hour-rain" aria-hidden="true">${item.rain ? `${item.rain} %` : ""}</span>
    </li>`;
  }).join("");
  pop([...$("weatherHours").children]);
}

function interactiveRows() {
  const lists = [$("taskList"), $("dueList")];
  if (!$("doneList").hidden) lists.splice(1, 0, $("doneList"));
  return lists.flatMap((list) => [...list.querySelectorAll(".row.is-interactive")]);
}

function focusRow(row) {
  if (!row) return;
  row.focus({ preventScroll: true });
  row.scrollIntoView({ block: "nearest" });
}

function focusTaskAt(index) {
  const rows = [...$("taskList").querySelectorAll(".task")];
  const target = rows[index] || rows[rows.length - 1];
  (target?.querySelector(".check") || $("addTask")).focus({ preventScroll: true });
}

const FLIP_SELECTOR = "#taskList > li, #addTask, #doneToggle, #doneList > li, #dueSection > .section-head, #dueList > li, #weekSection";

function holdFocus(paint) {
  const active = document.activeElement;
  const row = active?.closest?.("#taskList .row[data-id], #doneList .row[data-id], #dueList .row[data-id]");
  const part = !row || active === row ? "" : active.matches(".check") ? ".check" : active.matches(".row-link") ? ".row-link" : active.dataset.act ? `[data-act="${active.dataset.act}"]` : "";
  const list = row?.parentElement.id;
  paint();
  if (!row || row.isConnected || (document.activeElement && document.activeElement !== document.body)) return;
  const fresh = $(list).querySelector(`.row[data-id="${CSS.escape(row.dataset.id)}"]`);
  if (fresh) ((part && fresh.querySelector(part)) || fresh).focus({ preventScroll: true });
}

function settleLists({ exclude = null } = {}) {
  [exclude].flat().filter(Boolean).forEach((node) => {
    node.dataset.flip = "leaving";
  });
  flipKeyed(FLIP_SELECTOR, () => holdFocus(() => {
    renderTasks();
    renderDue();
    renderWeek(state.day);
  }));
}

const SETTLE_IDLE = 800;
const TOUCH_IDLE = 3000;
const settleDwell = () => Math.max(250, ms("--spring-tactile-dur") * 0.8);
const touchLike = (via) => via === "touch" || via === "pen";

function scheduleSettle(delay) {
  clearTimeout(state.settleTimer);
  state.settleTimer = setTimeout(settlePending, delay);
}

function settleSoon() {
  if (state.pending.size) scheduleSettle(Math.max(0, state.lastCheck + settleDwell() - performance.now()));
}

function planSettle(via) {
  clearTimeout(state.settleTimer);
  if (!openTasks().length) scheduleSettle(SETTLE_IDLE);
  else if (touchLike(via)) scheduleSettle(TOUCH_IDLE);
}

function listInUse() {
  const active = document.activeElement;
  return state.pointerInside || ($("taskList").contains(active) && active.matches(":focus-visible"));
}

const resumeHover = () => document.documentElement.classList.remove("is-hover-paused");

function pauseHover() {
  document.documentElement.classList.add("is-hover-paused");
  addEventListener("pointermove", resumeHover, { once: true, capture: true });
  addEventListener("pointerdown", resumeHover, { once: true, capture: true });
}

async function settlePending() {
  clearTimeout(state.settleTimer);
  if (!state.pending.size || (openTasks().length && listInUse())) return;
  const ids = new Set(state.pending);
  state.pending.clear();
  const section = $("tasksSection");
  const started = performance.now();
  section.classList.add("is-settling");
  const list = $("taskList");
  const order = [...list.querySelectorAll(".task")].map((row) => row.dataset.id);
  const inList = (id) => list.querySelector(`.task[data-id="${CSS.escape(id)}"]`);
  const leaving = [...ids].map(inList).filter(Boolean);
  const active = document.activeElement;
  const held = leaving.find((row) => row.contains(active));
  await Promise.all(leaving.map(exitInPlace));
  pauseHover();
  settleLists({ exclude: leaving });
  setTimeout(() => section.classList.remove("is-settling"), Math.max(250 - (performance.now() - started), travels() ? 260 : 0));
  if (travels()) $("doneToggle")?.animate([{ scale: 1 }, { scale: rich() ? 1.04 : 1.02 }, { scale: 1 }], { duration: 320, easing: token("--ease-out") });
  const lost = !document.activeElement || document.activeElement === document.body;
  if (held && lost) {
    const at = order.indexOf(held.dataset.id);
    const stays = (id) => !ids.has(id) && inList(id);
    const next = order.slice(at + 1).find(stays) || order.slice(0, at).reverse().find(stays);
    const target = next && inList(next);
    if (active === held) focusRow(target || $("dueList").querySelector(".row.is-interactive"));
    else (target?.querySelector(".check") || $("addTask")).focus({ preventScroll: true });
  }
  celebrateIfDone();
}

function celebrateIfDone() {
  if (!todayTasks().length || openTasks().length || state.pending.size) return;
  const today = todayIso();
  const mark = $("taskList").querySelector(".all-done-mark");
  if (!state.celebrationDue) return;
  state.celebrationDue = false;
  storage.set("app-celebrated", today);
  chalkCheck(mark, { play: true });
  const status = $("liveStatus");
  if (status) status.textContent = "Alles für heute erledigt.";
  const box = $("tasksSection").getBoundingClientRect();
  if (box.bottom < 80 || box.top > innerHeight - 80) toast("Alles für heute erledigt.", { icon: "circle-check" });
}

function toggleTask(id, { restoreFocus = false, via = "keyboard" } = {}) {
  const task = state.tasks.find((item) => item.id === id);
  if (!task) return;
  const row = rowFor(id);
  task.done = !task.done;
  task.doneAt = task.done ? clock(minutesOf(now())) : null;
  taskApi.done(id, task.done);
  if (row) {
    row.classList.toggle("is-done", task.done);
    row.querySelector(".check").setAttribute("aria-checked", String(task.done));
  }
  renderTaskMeta();
  state.celebrationDue = task.done && !openTasks().length && storage.get("app-celebrated") !== todayIso();
  if (task.done) {
    toast(`Erledigt: „${esc(task.title)}“`, {
      icon: "check",
      action: { label: "Rückgängig", undo: true, run: () => toggleTask(id, { restoreFocus: true }) },
      returnFocus: () => focusTaskAt(0),
    });
    state.pending.add(id);
    state.lastCheck = performance.now();
    if (via === "mouse") state.pointerInside = true;
    planSettle(via);
    return;
  }
  if (state.pending.delete(id)) {
    if (touchLike(via)) planSettle(via);
    else settleSoon();
    renderTaskMeta();
    return;
  }
  settleLists();
  const back = rowFor(id);
  enterInPlace(back);
  if (restoreFocus) back?.querySelector(".check")?.focus({ preventScroll: true });
}

function removeTask(id, kind, { refocus = false } = {}) {
  const index = state.tasks.findIndex((item) => item.id === id);
  if (index < 0) return;
  const task = state.tasks[index];
  const row = rowFor(id);
  const rowIndex = row ? [...$("taskList").querySelectorAll(".task")].indexOf(row) : -1;
  const hadFocus = refocus || row?.contains(document.activeElement) || document.activeElement === row;
  if (kind === "later") {
    task.date = isoDate(addDays(state.day.date, 1));
    taskApi.update(id, { date: task.date, someday: false });
  } else {
    state.tasks.splice(index, 1);
    state.deleted.push({ task, index, at: clock(minutesOf(now())) });
    taskApi.remove(id);
  }
  const finish = () => {
    settleLists({ exclude: row });
    if (hadFocus) focusTaskAt(Math.max(0, rowIndex));
  };
  exitInPlace(row).then(finish);
  toast(kind === "later" ? `Auf morgen verschoben: „${esc(task.title)}“` : `Gelöscht: „${esc(task.title)}“`, {
    icon: kind === "later" ? "calendar-plus" : "trash-2",
    action: { label: "Rückgängig", undo: true, run: () => restoreTask(id, kind) },
    returnFocus: () => focusTaskAt(0),
  });
}

function restoreTask(id, kind) {
  if (kind === "later") {
    const task = state.tasks.find((item) => item.id === id);
    if (task) {
      delete task.date;
      taskApi.update(id, { date: null, someday: false });
    }
  } else {
    const at = state.deleted.findIndex((entry) => entry.task.id === id);
    if (at < 0) return;
    const [entry] = state.deleted.splice(at, 1);
    state.tasks.splice(Math.min(entry.index, state.tasks.length), 0, entry.task);
    taskApi.restore(entry.task);
  }
  settleLists();
  const back = rowFor(id);
  enterInPlace(back);
  back?.querySelector(".check")?.focus({ preventScroll: true });
}

function createTask({ title, subjectKey, date, block, minutes = 20 }) {
  const task = { id: `new-${Date.now()}`, title, subject: subjectKey, anchor: block ? `vor dem ${block}. Block` : "", minutes, done: false };
  if (date && date > todayIso()) task.date = date;
  if (block) task.block = block;
  state.tasks.push(task);
  taskApi.create(task);
  document.dispatchEvent(new CustomEvent("app:task-created", { detail: { id: task.id, title: task.title } }));
  settleLists();
  const row = rowFor(task.id) || document.querySelector(`#dueList .due[data-id="${CSS.escape(task.id)}"]`);
  enterInPlace(row);
  return task;
}

function revealItem(id) {
  const row = rowFor(id) || document.querySelector(`#dueList .due[data-id="${CSS.escape(id)}"]`);
  if (row) {
    focusRow(row);
    row.classList.add("is-flash");
    setTimeout(() => row.classList.remove("is-flash"), 900);
  }
}

function openAddRow() {
  const button = $("addTask");
  if (!button || button.hidden) return;
  const row = document.createElement("div");
  row.className = "add-row";
  row.id = "addTaskInput";
  row.innerHTML = `<span class="plus">${icon("plus")}</span><input class="add-input" aria-label="Neue Aufgabe für heute" placeholder="z. B. Vokabeln Unit 3 wiederholen …">`;
  button.hidden = true;
  button.after(row);
  const input = row.querySelector("input");
  input.focus();
  const close = () => {
    row.remove();
    button.hidden = false;
  };
  input.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.stopPropagation();
      close();
      button.focus();
    }
    if (event.key === "Enter" && input.value.trim()) {
      const info = parseNote(input.value);
      const task = createTask({ title: cleanTitle(input.value.trim(), info), subjectKey: info.subject, date: info.date, block: info.block });
      input.value = "";
      const status = $("liveStatus");
      if (status) status.textContent = task.date ? `Aufgabe für ${shortDate(parseDate(task.date))} angelegt.` : "Aufgabe angelegt.";
    }
  });
  input.addEventListener("blur", () => setTimeout(() => {
    if (!input.value.trim() && row.isConnected) close();
  }, 150));
}

let menuInvoker = null;

function openRowMenu(button) {
  const menu = $("rowMenu");
  const row = button.closest(".task");
  if (!menu || !row) return;
  menuInvoker = button;
  menu.dataset.id = row.dataset.id;
  menu.showPopover();
  placeNear(menu, button, "right");
  clampSheet(menu);
  menu.querySelector("[role='menuitem']")?.focus();
}

function bindRowMenu() {
  const menu = $("rowMenu");
  if (!menu) return;
  menu.addEventListener("keydown", (event) => {
    const items = [...menu.querySelectorAll("[role='menuitem']")];
    const index = items.indexOf(document.activeElement);
    let next = null;
    if (event.key === "ArrowDown") next = items[(index + 1) % items.length];
    else if (event.key === "ArrowUp") next = items[(index - 1 + items.length) % items.length];
    else if (event.key === "Home") next = items[0];
    else if (event.key === "End") next = items[items.length - 1];
    else if (event.key === "Tab") menu.hidePopover();
    if (next) {
      event.preventDefault();
      next.focus();
    }
  });
  menu.addEventListener("toggle", (event) => {
    if (event.newState === "closed" && document.activeElement === document.body) menuInvoker?.focus();
  });
}

function bindLists() {
  const taskList = $("taskList");
  taskList.addEventListener("pointerenter", (event) => {
    if (event.pointerType === "mouse") state.pointerInside = true;
  });
  taskList.addEventListener("pointerleave", (event) => {
    if (event.pointerType !== "mouse") return;
    state.pointerInside = false;
    settleSoon();
  });
  taskList.addEventListener("focusout", (event) => {
    if (!taskList.contains(event.relatedTarget)) settleSoon();
  });
  document.addEventListener("pointerdown", (event) => {
    if (!taskList.contains(event.target)) settleSoon();
  }, true);
  taskList.addEventListener("click", (event) => {
    if (event.target.closest("[data-more-tasks]")) {
      openPage("tasks");
      return;
    }
    const row = event.target.closest(".task");
    if (!row) return;
    const id = row.dataset.id;
    if (event.target.closest(".check")) toggleTask(id, { via: event.pointerType || "keyboard" });
    const act = event.target.closest("[data-act]")?.dataset.act;
    if (act === "delete") removeTask(id, "delete");
    if (act === "later") removeTask(id, "later");
    if (act === "menu") openRowMenu(event.target.closest("[data-act]"));
  });
  $("doneList").addEventListener("click", (event) => {
    const restore = event.target.closest("[data-restore]");
    if (restore) {
      restoreTask(restore.dataset.restore, "delete");
      return;
    }
    const row = event.target.closest(".task");
    if (row && event.target.closest(".check")) toggleTask(row.dataset.id, { restoreFocus: true });
  });
  $("doneToggle").addEventListener("click", () => {
    state.doneOpen = !state.doneOpen;
    renderTasks();
    const list = $("doneList");
    if (state.doneOpen && travels()) [...list.children].forEach((node, index) => node.animate([{ opacity: 0, translate: "0 -4px" }, { opacity: 1, translate: "0 0" }], { duration: 240, delay: index * 30, easing: token("--ease-out"), fill: "backwards" }));
  });
  $("addTask").addEventListener("click", openAddRow);
  $("rowMenu")?.addEventListener("click", (event) => {
    const action = event.target.closest("[data-menu-act]")?.dataset.menuAct;
    if (!action) return;
    const menu = $("rowMenu");
    const id = menu.dataset.id;
    menu.hidePopover();
    removeTask(id, action, { refocus: true });
  });
  $("headOverdue")?.addEventListener("click", () => {
    const row = document.querySelector(`#dueList .due[data-id="${CSS.escape($("headOverdue").dataset.id || "")}"]`);
    focusRow(row);
  });
  document.addEventListener("click", (event) => {
    const target = event.target.closest("[data-page-action]");
    if (!target || event.target.closest(".check, [data-act]")) return;
    if (target.matches("a")) event.preventDefault();
    openPage(target.dataset.pageAction);
  });
  document.addEventListener("click", (event) => {
    const row = event.target.closest("#dueList .row.is-interactive");
    if (!row || event.target.closest("a, button")) return;
    row.querySelector(".row-link")?.click();
  });
  $("track").addEventListener("keydown", (event) => {
    const segments = [...$("track").querySelectorAll(".segment")];
    const index = segments.indexOf(event.target.closest(".segment"));
    if (index < 0) return;
    let next = null;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") next = segments[Math.min(segments.length - 1, index + 1)];
    else if (event.key === "ArrowLeft" || event.key === "ArrowUp") next = segments[Math.max(0, index - 1)];
    else if (event.key === "Home") next = segments[0];
    else if (event.key === "End") next = segments[segments.length - 1];
    else if ((event.key === "Enter" || event.key === " ") && event.target.dataset.pageAction) {
      event.preventDefault();
      openPage(event.target.dataset.pageAction);
      return;
    }
    if (!next) return;
    event.preventDefault();
    segments.forEach((node) => (node.tabIndex = node === next ? 0 : -1));
    next.focus();
  });
}

function bindKeys() {
  document.addEventListener("keydown", (event) => {
    if (!shortcutsEnabled() || typing(event.target) || event.ctrlKey || event.metaKey || event.altKey || overlayOpen()) return;
    const key = event.key.toLowerCase();
    const rows = interactiveRows();
    const current = document.activeElement?.closest?.(".row.is-interactive");
    const index = rows.indexOf(current);
    if (key === "j") {
      event.preventDefault();
      focusRow(rows[Math.min(rows.length - 1, index + 1)] || rows[0]);
    } else if (key === "k") {
      event.preventDefault();
      focusRow(rows[Math.max(0, index - 1)] || rows[0]);
    } else if (key === "x" && current?.classList.contains("task") && current.contains(event.target)) {
      event.preventDefault();
      toggleTask(current.dataset.id, { restoreFocus: true });
    } else if (key === "enter" && event.target === current) {
      event.preventDefault();
      current.querySelector(".row-link")?.click();
    } else if (key === "a") {
      event.preventDefault();
      openAddRow();
    }
  });
}

function bindEvents() {
  window.addEventListener("app:add-task", openAddRow);
  window.addEventListener("app:weather-open", renderWeather);
  window.addEventListener("app:note", (event) => {
    event.preventDefault();
    const detail = event.detail;
    const today = todayIso();
    const typeWords = { task: "Aufgabe", homework: "Hausaufgabe", note: "Notiz", idea: "Idee" };
    const when = detail.date && detail.date !== today ? ` für ${shortDate(parseDate(detail.date))}` : "";
    let id = null;
    if (detail.type === "task" || (detail.type === "homework" && (!detail.date || detail.date === today))) {
      id = createTask({ title: detail.title, subjectKey: detail.subject, date: detail.date, block: detail.block }).id;
    } else if (detail.type === "homework") {
      id = `hw-new-${Date.now()}`;
      const item = { id, kind: "Hausaufgabe", title: detail.title, subject: detail.subject || null, date: detail.date, block: detail.block, detail: detail.details || "", status: "offen" };
      state.deadlines.push(item);
      deadlineApi.create(item);
      settleLists();
    } else {
      noteApi.create({ type: detail.type, title: detail.title, details: detail.details });
    }
    toast(`${typeWords[detail.type]}${when} angelegt: „${esc(detail.title)}“`, {
      icon: "check",
      action: id ? { label: "Anzeigen", run: () => revealItem(id) } : null,
    });
  });
  registerSearch(() => [
    ...state.tasks.map((task) => ({
      group: "Aufgaben", label: task.title, icon: task.done ? "circle-check" : "list-checks", keywords: task.subject ? subject(task.subject).name : "",
      hint: task.done ? "erledigt" : task.date && task.date > todayIso() ? shortDate(parseDate(task.date)) : task.subject ? label(task.subject) : "",
      run: () => {
        if (task.done && !state.doneOpen) {
          state.doneOpen = true;
          renderTasks();
        }
        revealItem(task.id);
      },
    })),
    ...state.deadlines.map((item) => ({
      group: "Fällig", label: `${item.kind}: ${item.title}`, icon: isTest(item) ? "nx-test" : "calendar-days", keywords: subject(item.subject).name,
      hint: `${label(item.subject)}, ${shortDate(parseDate(item.date))}`,
      run: () => {
        const row = document.querySelector(`.due[data-id="${CSS.escape(item.id)}"]`);
        if (row) focusRow(row);
        else openPage("school");
      },
    })),
  ]);
}

let lastSeen = storage.get("app-last-seen");

function saveSeen(day) {
  storage.set("app-last-seen", { date: isoDate(day.date), min: day.nowMin });
}

function render(previous) {
  const date = now();
  const day = computeDay(date);
  state.day = day;
  renderHeader(day);
  renderHero(day, previous);
  renderTrack(day);
  const dayChanged = !previous || isoDate(previous.date) !== isoDate(day.date);
  holdFocus(() => {
    if (dayChanged) {
      renderTasks();
      renderDue();
    } else if (lateSignature() !== state.lateSignature) {
      renderTasks();
    }
  });
  renderWeek(day);
  saveSeen(day);
  return day;
}

function scheduleTick() {
  if (pinnedTime()) return;
  const wait = 60000 - (Date.now() % 60000) + 30;
  setTimeout(() => {
    const previous = state.day;
    render(previous);
    scheduleTick();
  }, wait);
}

function heroBuild() {
  if (!travels()) return;
  const parts = [...$("todayNow").children, $("todayNext")].filter((node) => node && !node.classList.contains("today-title"));
  const curve = token("--ease-out");
  parts.forEach((node, index) => node.animate([{ opacity: 0.35, translate: "0 8px" }, { opacity: 1, translate: "0 0" }], { duration: 320, delay: index * 40, easing: curve, fill: "backwards" }));
}

function choreograph(day) {
  const cold = flags.cold || (!flags.warm && (!lastSeen || lastSeen.date !== isoDate(day.date)));
  const model = trackModel(day);
  const motion = level();
  const preview = model.mode !== "today" || day.kind === "morning" || day.kind === "soon";
  if (cold && motion !== "minimal") playIntro($("scene"));
  if (motion === "reduced") {
    if (cold) crossfade($("track"), 150);
    return;
  }
  if (motion === "minimal") {
    if (cold && !preview) sweepTrack(day, { from: DAY_START, duration: 400, arrive: false });
    return;
  }
  if (!cold) {
    if (lastSeen && lastSeen.min < day.nowMin && !pinnedTime() && !preview) sweepTrack(day, { from: lastSeen.min, duration: 450 });
    return;
  }
  if (motion === "rich") heroBuild();
  if (preview) layoutTrack();
  else sweepTrack(day, { from: DAY_START, duration: motion === "rich" ? 1100 : 800, delay: 80 });
}

export function initHome() {
  if (!$("today")) return;
  bindLists();
  bindRowMenu();
  bindKeys();
  bindEvents();
  const day = render(null);
  choreograph(day);
  requestAnimationFrame(() => requestAnimationFrame(() => $("track").classList.add("is-live")));
  scheduleTick();
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      saveSeen(state.day);
      return;
    }
    if (pinnedTime()) return;
    const before = storage.get("app-last-seen");
    const previous = state.day;
    const day = render(previous);
    if (before && before.date === isoDate(day.date) && before.min < day.nowMin && travels()) sweepTrack(day, { from: before.min, duration: 450 });
  });
}
