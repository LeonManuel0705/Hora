const serverIds = new Map();
const creations = new Map();
const queues = new Map();

async function send(method, url, body) {
  const response = await fetch(url, {
    method,
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
    keepalive: true,
  });
  let payload = null;
  try {
    payload = await response.json();
  } catch {}
  if (!response.ok || payload?.success === false) throw new Error(payload?.error || `HTTP ${response.status}`);
  return payload;
}

function failed(error) {
  window.dispatchEvent(new CustomEvent("app:save-failed", { detail: { message: error?.message || "" } }));
}

function queue(key, job) {
  const next = (queues.get(key) || Promise.resolve()).catch(() => {}).then(job);
  queues.set(key, next);
  next.catch(failed);
  return next;
}

async function resolved(id) {
  if (creations.has(id)) {
    try {
      await creations.get(id);
    } catch {}
  }
  return serverIds.get(id) || id;
}

function create(key, url, body, pick) {
  const job = send("POST", url, body).then((payload) => {
    const saved = pick(payload);
    serverIds.set(key, String(saved.id));
    return saved;
  });
  creations.set(key, job);
  return queue(key, () => job);
}

const clean = (value) => (value === undefined ? null : value);

function taskBody(task) {
  return {
    title: task.title,
    subject: clean(task.subject),
    date: task.someday ? null : clean(task.date),
    someday: !!task.someday,
    dueTime: clean(task.dueTime),
    minutes: task.minutes || null,
    priority: !!task.priority,
    repeat: clean(task.repeat),
    notes: task.notes || "",
    deadline: clean(task.deadline),
    source: task.source === "iserv" ? "iserv" : "own",
    done: !!task.done,
  };
}

const homeworkRef = (id) => (String(id).startsWith("iserv-") ? String(id).slice(6) : null);

export const tasks = {
  create(task) {
    return create(task.id, "/api/ui/tasks", taskBody(task), (payload) => payload.task);
  },
  update(id, changes) {
    const ref = homeworkRef(id);
    if (ref) {
      const body = {};
      if ("done" in changes) body.status = changes.done ? "abgegeben" : "offen";
      if ("date" in changes && changes.date) body.date = changes.date;
      if ("title" in changes) body.title = changes.title;
      if ("subject" in changes) body.subject = clean(changes.subject);
      return Object.keys(body).length ? deadlines.update(ref, body) : Promise.resolve();
    }
    const body = Object.fromEntries(Object.entries(changes).map(([key, value]) => [key, clean(value)]));
    return queue(id, async () => send("PATCH", `/api/ui/tasks/${encodeURIComponent(await resolved(id))}`, body));
  },
  done(id, done) {
    return tasks.update(id, { done });
  },
  remove(id) {
    const ref = homeworkRef(id);
    if (ref) return deadlines.remove(ref);
    return queue(id, async () => send("DELETE", `/api/ui/tasks/${encodeURIComponent(await resolved(id))}`));
  },
  restore(task) {
    if (homeworkRef(task.id)) return Promise.resolve();
    serverIds.delete(task.id);
    creations.delete(task.id);
    return tasks.create(task);
  },
};

export const deadlines = {
  create(item) {
    return create(item.id, "/api/ui/deadlines", { kind: item.kind, title: item.title, subject: clean(item.subject), date: item.date, detail: item.detail || "" }, (payload) => payload.deadline);
  },
  update(id, changes) {
    return queue(id, async () => send("PATCH", `/api/ui/deadlines/${encodeURIComponent(await resolved(id))}`, changes));
  },
  remove(id) {
    return queue(id, async () => send("DELETE", `/api/ui/deadlines/${encodeURIComponent(await resolved(id))}`));
  },
};

function eventBody(item) {
  return {
    title: item.title,
    date: item.date,
    endDate: clean(item.endDate),
    start: clean(item.start),
    end: clean(item.end),
    place: item.place || "",
    kind: item.kind || "private",
    notes: item.notes || "",
  };
}

export const events = {
  create(item) {
    return create(item.id, "/api/ui/events", eventBody(item), (payload) => payload.event);
  },
  update(id, changes) {
    const body = Object.fromEntries(Object.entries(changes).map(([key, value]) => [key, clean(value)]));
    return queue(id, async () => send("PATCH", `/api/ui/events/${encodeURIComponent(await resolved(id))}`, body));
  },
  remove(id) {
    return queue(id, async () => send("DELETE", `/api/ui/events/${encodeURIComponent(await resolved(id))}`));
  },
  restore(item) {
    serverIds.delete(item.id);
    creations.delete(item.id);
    return events.create(item);
  },
};

export const grades = {
  create(item) {
    return create(item.id, "/api/ui/grades", { subject: item.subject, points: item.points, type: item.type, semester: item.semester, date: item.date, title: item.title || "" }, (payload) => payload.grade);
  },
  remove(id) {
    return queue(id, async () => send("DELETE", `/api/ui/grades/${encodeURIComponent(await resolved(id))}`));
  },
};

export const notes = {
  create(item) {
    return queue(`note-${Date.now()}`, () => send("POST", "/api/ui/notes", { type: item.type, title: item.title, details: item.details || "" }));
  },
};

const flushers = new Set();

addEventListener("pagehide", () => flushers.forEach((flush) => flush()));

export function debounced(delay, run) {
  const waiting = new Map();
  const flush = () => {
    waiting.forEach(({ timer, args }, key) => {
      clearTimeout(timer);
      run(key, ...args);
    });
    waiting.clear();
  };
  flushers.add(flush);
  return (key, ...args) => {
    clearTimeout(waiting.get(key)?.timer);
    const timer = setTimeout(() => {
      waiting.delete(key);
      run(key, ...args);
    }, delay);
    waiting.set(key, { timer, args });
  };
}
