import { BRAND, data, esc, icon, tinte } from "../core.js";
import { toast } from "../shell.js";
import { travels } from "../motion.js";

const $ = (id) => document.getElementById(id);
const ENDPOINT = "/api/hub/assistant/install";

const STEPS = { runtime: "Laufzeit", model: "Sprachmodell", verify: "Prüfen", start: "Starten" };
const PHASE_STEP = { runtime: "runtime", resume: "model", model: "model", verify: "verify", start: "start" };
const FIGURE = { idle: "ruhe", resume: "ruhe", paused: "ruhe", error: "ruhe", unsupported: "ruhe", running: "laedt", done: "geschafft" };
const HEAD = {
  idle: "Noch nicht installiert",
  resume: "Noch nicht fertig installiert",
  paused: "Angehalten",
  error: "Installation unterbrochen",
  unsupported: "Nicht verfügbar",
  running: "Wird installiert",
  done: "Bereit",
};

const decimal = new Intl.NumberFormat("de-DE", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const whole = new Intl.NumberFormat("de-DE", { maximumFractionDigits: 0 });

const bytes = (value) => {
  const amount = Math.max(0, value || 0);
  if (amount >= 1e11) return `${whole.format(amount / 1e9)} GB`;
  if (amount >= 1e9) return `${decimal.format(amount / 1e9)} GB`;
  return `${whole.format(Math.max(1, Math.round(amount / 1e6)))} MB`;
};
const speed = (value) => (value >= 1e6 ? `${decimal.format(value / 1e6)} MB/s` : `${whole.format(Math.max(1, value / 1e3))} KB/s`);
const remaining = (seconds) => {
  if (seconds == null) return "";
  if (seconds < 60) return "noch weniger als 1 Min.";
  if (seconds < 3600) return `noch etwa ${Math.round(seconds / 60)} Min.`;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.round((seconds % 3600) / 60);
  return minutes ? `noch etwa ${hours} Std. ${minutes} Min.` : `noch etwa ${hours} Std.`;
};

const ERRORS = {
  offline: () => "Keine Verbindung zum Download-Server. Prüf dein Internet und versuch es noch einmal. Bereits geladene Teile bleiben erhalten.",
  disk_full: (error) => (error.missing ? `Nicht genug Speicherplatz. Es fehlen noch ${bytes(error.missing)}.` : "Nicht genug Speicherplatz auf diesem Gerät. Mach etwas Platz frei und versuch es noch einmal."),
  checksum: () => "Die Datei kam zweimal beschädigt an. Versuch es später noch einmal.",
  http: (error) => `Der Download-Server antwortet mit Fehler ${error.status}. Versuch es später noch einmal.`,
  unsupported: () => "Für dieses Gerät gibt es keine passende Laufzeit.",
  runtime_broken: () => "Die Laufzeit ließ sich auf diesem Computer nicht starten.",
  runtime_libraries: () => "Windows fehlen Bausteine von Microsoft (Visual C++ Runtime). Installier sie über den Link und versuch es danach noch einmal.",
  start_failed: () => "Das Sprachmodell ließ sich nicht starten. Oft fehlt Arbeitsspeicher. Schließ ein paar Programme und versuch es noch einmal.",
  unexpected: () => "Da ist etwas schiefgelaufen. Versuch es noch einmal.",
};

const LINKS = { runtime_libraries: ["https://aka.ms/vs/17/release/vc_redist.x64.exe", "Visual C++ Runtime von Microsoft laden"] };

let status = data?.page?.install || null;
let shown = "";
let figure = "";
let stepsKey = "";
let timer = 0;
let busy = false;

function viewOf(current) {
  const job = current.job || {};
  if (job.state === "running") return "running";
  if (job.state === "error") return "error";
  if (current.installed) return "done";
  if (!current.supported) return "unsupported";
  if (job.state === "cancelled") return "paused";
  if (current.model?.partial > 0) return "resume";
  return "idle";
}

function downloadSize(current) {
  return (current.runtime?.download || 0) + (current.model?.download || 0);
}

function copyFor(view, current) {
  const partial = current.model?.partial || 0;
  const total = current.model?.size || 0;
  switch (view) {
    case "running":
      if (current.job?.phase === "verify" || current.job?.phase === "start") {
        return ["Gleich geschafft", "Das Sprachmodell ist da und wird jetzt zum ersten Mal gestartet."];
      }
      return ["Assistent wird installiert", `Du kannst ${BRAND} solange weiter benutzen. Der Download läuft im Hintergrund weiter, auch wenn du die Seite wechselst.`];
    case "done":
      return ["Fertig", "Der Assistent ist bereit. Er läuft ab jetzt auf diesem Gerät, auch ohne Internet."];
    case "paused":
      return ["Installation angehalten", partial ? `${bytes(partial)} von ${bytes(total)} sind schon da. Beim nächsten Mal geht es an dieser Stelle weiter.` : "Beim nächsten Mal geht es an dieser Stelle weiter."];
    case "resume":
      return ["Installation fortsetzen", `${bytes(partial)} von ${bytes(total)} sind schon da. Der Rest wird an dieser Stelle weitergeladen.`];
    case "error":
      return ["Das hat nicht geklappt", "Bereits geladene Teile bleiben erhalten, du musst also nicht von vorn anfangen."];
    case "unsupported":
      return ["Assistent nicht verfügbar", "Der Assistent braucht eine Laufzeit, die es für dieses Gerät nicht gibt."];
    default:
      return ["Assistent installieren", `Der Assistent läuft komplett auf deinem Computer. Dafür lädt ${BRAND} einmalig ein Sprachmodell herunter, danach funktioniert er auch ohne Internet.`];
  }
}

function memoryNote(current) {
  const memory = current.memory || 0;
  if (!memory || memory >= 7.5e9) return "";
  return `Dein Computer hat ${whole.format(Math.round(memory / 1073741824))} GB Arbeitsspeicher. Der Assistent belegt davon etwa 3 GB, während er antwortet, und kann langsam sein.`;
}

function renderFigure(kind) {
  if (kind === figure) return;
  figure = kind;
  $("aiFigure").innerHTML = tinte(kind, 116);
}

function renderSteps(job) {
  const steps = job.steps || [];
  const active = PHASE_STEP[job.phase] || null;
  const activeIndex = steps.indexOf(active);
  const key = `${steps.join(",")}|${activeIndex}`;
  if (key === stepsKey) return;
  stepsKey = key;
  $("aiSteps").innerHTML = steps
    .map((step, index) => {
      const state = activeIndex < 0 ? "pending" : index < activeIndex ? "done" : index === activeIndex ? "active" : "pending";
      const mark = state === "done" ? icon("check", "is-pop") : `<span class="ai-step-n">${index + 1}</span>`;
      const current = state === "active" ? ' aria-current="step"' : "";
      return `<li class="ai-step is-${state}"${current}><span class="ai-dot">${mark}</span><span class="ai-step-label">${esc(STEPS[step] || step)}</span></li>`;
    })
    .join("");
}

function progressOf(job) {
  if (job.phase === "verify" || job.phase === "start") return 1;
  if (!job.phase_total) return 0;
  return Math.min(1, job.phase_done / job.phase_total);
}

function numbersOf(job) {
  const done = job.phase_done || 0;
  const total = job.phase_total || 0;
  switch (job.phase) {
    case "check":
      return "Speicherplatz wird geprüft";
    case "runtime":
      return `Laufzeit · ${bytes(done)} von ${bytes(total)}`;
    case "resume":
      return `Bereits geladene Teile werden geprüft · ${whole.format(Math.round(progressOf(job) * 100))} %`;
    case "model": {
      const parts = [`${bytes(done)} von ${bytes(total)}`];
      if (job.speed > 0) parts.push(speed(job.speed));
      if (job.eta != null) parts.push(remaining(job.eta));
      return parts.join(" · ");
    }
    case "verify":
      return "Die Datei wird geprüft";
    case "start":
      return "Das Sprachmodell wird geladen";
    default:
      return "";
  }
}

function renderProgress(job) {
  renderSteps(job);
  const value = progressOf(job);
  const bar = $("aiBar");
  bar.style.setProperty("--p", value.toFixed(4));
  bar.setAttribute("aria-valuenow", String(Math.round(value * 100)));
  bar.classList.toggle("is-settling", job.phase === "verify" || job.phase === "start");
  $("aiNumbers").textContent = numbersOf(job);
}

function reveal(node, visible) {
  if (node.hidden === !visible) return;
  node.hidden = !visible;
  if (visible && travels()) {
    node.classList.remove("ai-enter");
    void node.offsetWidth;
    node.classList.add("ai-enter");
  }
}

function render(current) {
  status = current;
  const view = viewOf(current);
  const job = current.job || {};
  const card = $("aiCard");
  card.dataset.state = view;
  $("aiState").textContent = HEAD[view];
  renderFigure(FIGURE[view]);

  const [title, text] = copyFor(view, current);
  $("aiTitle").textContent = title;
  $("aiText").textContent = text;

  const size = downloadSize(current);
  $("aiSize").textContent = size ? bytes(size) : "schon geladen";
  $("aiFree").textContent = current.free == null ? "unbekannt" : `${bytes(current.free)} frei`;
  reveal($("aiFacts"), view === "idle" || view === "resume" || view === "paused" || view === "error");

  reveal($("aiProgress"), view === "running");
  if (view === "running") renderProgress(job);

  const note = view === "idle" || view === "resume" ? memoryNote(current) : "";
  $("aiNote").textContent = note;
  reveal($("aiNote"), !!note);

  const error = view === "error" ? job.error || { code: "unexpected" } : null;
  if (error) $("aiErrorText").textContent = (ERRORS[error.code] || ERRORS.unexpected)(error);
  const link = error && LINKS[error.code];
  const anchor = $("aiErrorLink");
  anchor.hidden = !link;
  if (link) {
    anchor.href = link[0];
    anchor.lastChild.textContent = link[1];
  }
  reveal($("aiError"), !!error);

  const install = $("aiInstall");
  install.hidden = !["idle", "resume", "paused", "error"].includes(view);
  $("aiInstallLabel").textContent = view === "error" ? "Erneut versuchen" : view === "idle" ? "Installieren" : "Fortsetzen";
  install.disabled = busy;
  $("aiCancel").hidden = view !== "running";
  $("aiCancel").disabled = busy;
  reveal($("aiOpen"), view === "done");
  $("aiLater").hidden = view === "running" || view === "done";
  $("aiLater").textContent = view === "unsupported" ? "Zurück" : "Nicht jetzt";

  if (view !== shown) {
    const first = !shown;
    shown = view;
    if (!first) {
      $("aiLive").textContent = `${title}. ${view === "error" ? $("aiErrorText").textContent : ""}`.trim();
      if (view === "done") $("aiOpen").focus({ preventScroll: true });
    }
  }
}

async function request(method, url) {
  const response = await fetch(url, {
    method,
    credentials: "same-origin",
    headers: { Accept: "application/json" },
    cache: "no-store",
  });
  const payload = await response.json().catch(() => null);
  if (!payload || (!response.ok && !payload.status)) throw new Error(`HTTP ${response.status}`);
  return payload.status || payload;
}

function schedule(delay) {
  clearTimeout(timer);
  timer = setTimeout(poll, delay ?? (document.hidden ? 3000 : 600));
}

async function poll() {
  try {
    render(await request("GET", ENDPOINT));
    if (status.job?.state === "running") schedule();
  } catch {
    schedule(3000);
  }
}

async function act(method, url) {
  if (busy) return;
  busy = true;
  render(status);
  try {
    render(await request(method, url));
  } catch {
    toast("Der Assistent antwortet gerade nicht. Versuch es gleich noch einmal.", { icon: "circle-alert" });
  } finally {
    busy = false;
    render(status);
    if (status.job?.state === "running") schedule(300);
  }
}

function leave() {
  const from = document.referrer ? new URL(document.referrer) : null;
  if (from && from.origin === location.origin && from.pathname !== location.pathname && history.length > 1) history.back();
  else location.assign("/hub");
}

export function init() {
  if (!status) {
    poll();
  } else {
    render(status);
    if (status.job?.state === "running") schedule();
  }
  $("aiInstall").addEventListener("click", () => act("POST", ENDPOINT));
  $("aiCancel").addEventListener("click", () => act("POST", `${ENDPOINT}/cancel`));
  $("aiLater").addEventListener("click", leave);
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden && status?.job?.state === "running") schedule(0);
  });
}
