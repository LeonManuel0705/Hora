import { data, flags, esc, icon, tinte, now, isoDate, parseDate, addDays, startOfDay, dayDiff, shortDate, subject, hueVar, minutesOf, platform, root, WEEKDAYS, WEEKDAYS_SHORT, MONTHS_SHORT, BRAND } from "../core.js";
import { animates, travels, flipKeyed, enterInPlace, exitInPlace, token, ms } from "../motion.js";
import { toast, typing, shortcutsEnabled, overlayOpen, registerSearch, syncTime } from "../shell.js";

const $ = (id) => document.getElementById(id);
const pad = (value) => String(value).padStart(2, "0");
const clockOf = (date) => `${date.getHours()}:${pad(date.getMinutes())}`;
const fold = (text) => String(text ?? "").normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
const clip = (text, size = 44) => (text.length > size ? `${text.slice(0, size - 1).trimEnd()}…` : text);

const FOLDERS = [
  { key: "inbox", label: "Posteingang", where: "im Posteingang" },
  { key: "sent", label: "Gesendet", where: "in Gesendet" },
  { key: "drafts", label: "Entwürfe", where: "in Entwürfe" },
  { key: "archive", label: "Archiv", where: "im Archiv" },
  { key: "trash", label: "Papierkorb", where: "im Papierkorb" },
];
const FOLDER = Object.fromEntries(FOLDERS.map((folder) => [folder.key, folder]));
const STAFF = new Set(["teacher", "leadership"]);
const FILTERS = {
  unread: { test: (mail) => !mail.read && mail.direction !== "out", empty: "Keine ungelesenen Mails" },
  files: { test: (mail) => mail.attachments.length > 0, empty: "Keine Mails mit Anhang" },
  staff: { test: (mail) => STAFF.has(mail.peer.role), empty: "Keine Mails von Lehrkräften" },
};
const MOVES = {
  archive: ["Archiviert", "archive"],
  trash: ["In den Papierkorb gelegt", "trash-2"],
  inbox: ["In den Posteingang verschoben", "inbox"],
};

const pendingDeletes = new Map();

async function mailRequest(method, url, body) {
  const response = await fetch(url, {
    method,
    headers: body === undefined ? {} : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
    credentials: "same-origin",
    keepalive: method !== "GET",
  });
  let payload = {};
  try {
    payload = await response.json();
  } catch {}
  if (!response.ok || payload.success === false) throw new Error(payload.error || "");
  return payload;
}

const mailQuery = (mail) => new URLSearchParams({ account: mail.account, id: mail.uid });

function deleteOnServer(mail) {
  clearTimeout(pendingDeletes.get(mail.id));
  pendingDeletes.delete(mail.id);
  if (!mail.account || !mail.uid) return;
  mailRequest("DELETE", `/api/ui/mail/message?${mailQuery(mail)}`).catch(() => {
    toast(`„${esc(clip(mail.subject || "ohne Betreff"))}“ ließ sich im Postfach nicht löschen.`, { icon: "circle-alert" });
  });
}

addEventListener("pagehide", () => {
  pendingDeletes.forEach((timer, id) => {
    clearTimeout(timer);
    const mail = state.mails.find((item) => item.id === id);
    if (mail?.folder === "trash") deleteOnServer(mail);
  });
});

const state = {
  accounts: [],
  mails: [],
  folder: "inbox",
  filters: new Set(),
  query: "",
  mode: null,
  openId: null,
  draft: null,
  loading: false,
  closing: false,
  closeTicket: 0,
  invoker: null,
  invokerRow: null,
  waiting: new Set(),
  added: new Set(),
  cleared: 0,
};

const sheetQuery = matchMedia("(max-width: 1100px)");
const phoneQuery = matchMedia("(max-width: 759px)");
const isSheet = () => sheetQuery.matches;

function load() {
  const base = now().getTime();
  state.mails = (data.page?.messages || []).map((mail) => ({
    ...mail,
    at: mail.ago != null ? new Date(base - mail.ago * 60000) : new Date(mail.received),
    attachments: mail.attachments || [],
    read: !!mail.read,
    flagged: !!mail.flagged,
  }));
  if (flags.empty) state.mails = state.mails.filter((mail) => mail.folder !== "inbox");
}

const arrived = (mail) => !state.waiting.has(mail.id);
const byId = (id) => state.mails.find((mail) => mail.id === id);
const outgoing = (mail) => mail.direction === "out";
const isUnread = (mail) => !mail.read && !outgoing(mail);
const newestFirst = (a, b) => b.at - a.at;
const inFolder = (key) => state.mails.filter((mail) => mail.folder === key && arrived(mail));
const inboxUnread = () => inFolder("inbox").filter(isUnread).length;
const rowOf = (id) => (id ? document.querySelector(`#mailGroups .mail-row[data-id="${CSS.escape(id)}"]`) : null);

const peerHue = (peer) => (peer.subject ? hueVar(peer.subject) : peer.hue ? `var(--hue-${peer.hue})` : "var(--ink-muted)");
const detailOf = (peer) => (peer.subject ? subject(peer.subject).label : peer.detail || "");
const initialOf = (peer) => (String(peer.name || "").replace(/^(Frau|Herr)\s+/, "").trim().charAt(0) || "?").toUpperCase();
const peerText = (mail) => (outgoing(mail) ? (mail.to ? `An ${mail.to}` : "Ohne Empfänger") : mail.peer.name);
const keyHint = (key) => (key && shortcutsEnabled() && !platform.touch ? ` (${key})` : "");

const queryWords = () => fold(state.query).split(/\s+/).filter(Boolean);

function haystack(mail) {
  return fold([mail.peer.name, detailOf(mail.peer), mail.to, mail.subject, mail.body, ...mail.attachments.map((file) => file.name)].join(" "));
}

function matchesQuery(mail, words = queryWords()) {
  if (!words.length) return true;
  const text = haystack(mail);
  return words.every((word) => text.includes(word));
}

const matchesFilters = (mail) => [...state.filters].every((key) => FILTERS[key].test(mail));

function visibleMails() {
  const words = queryWords();
  return inFolder(state.folder)
    .filter((mail) => matchesQuery(mail, words) && (matchesFilters(mail) || mail.id === state.openId))
    .sort(newestFirst);
}

const dayOffset = (date) => dayDiff(startOfDay(now()), isoDate(date));

function timeLabel(mail) {
  return dayOffset(mail.at) >= -6 ? clockOf(mail.at) : `${mail.at.getDate()}.${mail.at.getMonth() + 1}.`;
}

function whenText(date) {
  const diff = dayOffset(date);
  if (diff >= 0) return `heute, ${clockOf(date)}`;
  if (diff === -1) return `gestern, ${clockOf(date)}`;
  return `${shortDate(date)}, ${clockOf(date)}`;
}

function bucketOf(mail) {
  const diff = dayOffset(mail.at);
  if (diff >= 0) return "today";
  if (diff === -1) return "yesterday";
  if (diff >= -6) return `day-${isoDate(mail.at)}`;
  return "older";
}

function groupLabel(bucket) {
  const base = startOfDay(now());
  if (bucket === "today") return { title: "Heute", meta: shortDate(base) };
  if (bucket === "yesterday") return { title: "Gestern", meta: shortDate(addDays(base, -1)) };
  if (bucket === "older") return { title: "Älter" };
  const date = parseDate(bucket.slice(4));
  return { title: WEEKDAYS[date.getDay()], meta: `${date.getDate()}.${date.getMonth() + 1}.` };
}

function highlight(text) {
  const source = String(text ?? "");
  const words = queryWords().filter((word) => word.length > 1);
  const folded = fold(source);
  if (!words.length || folded.length !== source.length) return esc(source);
  const ranges = [];
  words.forEach((word) => {
    for (let index = folded.indexOf(word); index >= 0; index = folded.indexOf(word, index + word.length)) ranges.push([index, index + word.length]);
  });
  if (!ranges.length) return esc(source);
  ranges.sort((a, b) => a[0] - b[0]);
  let html = "";
  let cursor = 0;
  ranges.forEach(([start, end]) => {
    if (end <= cursor) return;
    const from = Math.max(start, cursor);
    html += `${esc(source.slice(cursor, from))}<mark class="mail-hit">${esc(source.slice(from, end))}</mark>`;
    cursor = end;
  });
  return html + esc(source.slice(cursor));
}

function previewOf(mail) {
  const flat = String(mail.body || "").replace(/\s+/g, " ").trim();
  const words = queryWords().filter((word) => word.length > 1);
  if (words.length) {
    const folded = fold(flat);
    const hits = words.map((word) => folded.indexOf(word)).filter((index) => index >= 0);
    const first = hits.length ? Math.min(...hits) : -1;
    if (first > 56) {
      const cut = flat.lastIndexOf(" ", first - 20);
      return `…${flat.slice(cut > 0 ? cut + 1 : first - 20, first + 220)}`;
    }
  }
  return flat.slice(0, 240);
}

function avatarHtml(peer, extra = "") {
  return `<span class="mail-avatar${extra}" style="--hue:${peerHue(peer)}" aria-hidden="true">${esc(initialOf(peer))}<i class="mail-dot"></i></span>`;
}

function marksInner(mail) {
  const files = mail.attachments.length ? `<span class="mail-mark">${icon("paperclip")}</span>` : "";
  const flag = mail.flagged ? `<span class="mail-mark is-flag">${icon("flag")}</span>` : "";
  return files + flag;
}

function rowActs(mail) {
  if (mail.folder === "trash") return [["restore", "undo-2", "Wiederherstellen"], ["destroy", "trash-2", "Endgültig löschen"]];
  if (mail.folder === "drafts") return [["destroy", "trash-2", "Entwurf verwerfen"]];
  if (mail.account?.endsWith("@iserv")) return [];
  return mail.folder === "inbox" ? [["delete", "trash-2", "Löschen"]] : [];
}

function actionsHtml(mail) {
  const title = esc(mail.subject || "ohne Betreff");
  return `<div class="mail-actions">${rowActs(mail).map(([act, name, label]) => `<button class="icon-button" type="button" data-act="${act}" tabindex="-1" aria-label="${esc(label)}: ${title}" data-tip="${esc(label)}">${icon(name)}</button>`).join("")}</div>`;
}

function ariaFor(mail) {
  const parts = [`${peerText(mail)}: ${mail.subject || "ohne Betreff"}`];
  if (mail.folder === "drafts") parts.push("Entwurf");
  if (isUnread(mail)) parts.push("ungelesen");
  if (mail.attachments.length) parts.push(mail.attachments.length === 1 ? "1 Anhang" : `${mail.attachments.length} Anhänge`);
  if (mail.flagged) parts.push("markiert");
  parts.push(whenText(mail.at));
  return parts.join(", ");
}

function rowHtml(mail) {
  const draft = mail.folder === "drafts";
  const detail = draft ? "Entwurf" : detailOf(mail.peer);
  const selected = mail.id === state.openId;
  const classes = ["row", "mail-row", "is-interactive", isUnread(mail) && "is-unread", selected && "is-selected", draft && "is-draft"].filter(Boolean).join(" ");
  return `<li class="${classes}" data-id="${esc(mail.id)}" tabindex="-1">
    ${avatarHtml(mail.peer)}
    <div class="row-main">
      <p class="mail-top"><span class="mail-from">${highlight(peerText(mail))}</span>${detail ? `<span class="mail-role">${esc(detail)}</span>` : ""}<time class="mail-time" datetime="${esc(mail.at.toISOString())}">${esc(timeLabel(mail))}</time></p>
      <p class="mail-line"><button type="button" class="row-open mail-open" aria-label="${esc(ariaFor(mail))}"${selected ? ' aria-current="true"' : ""}>${highlight(mail.subject || "(ohne Betreff)")}</button><span class="mail-marks" aria-hidden="true">${marksInner(mail)}</span></p>
      <p class="mail-preview">${highlight(previewOf(mail)) || "&nbsp;"}</p>
    </div>
    ${actionsHtml(mail)}
  </li>`;
}


function lateHour() {
  const hour = minutesOf(now()) / 60;
  return hour >= 21 || hour < 5;
}

function loadingHtml() {
  return `<div class="loading-card" role="status" data-flip="mail-loading">${tinte("laedt", 96)}<div><p class="empty-title">Hole neue Mails</p><p class="empty-text">Dauert nur einen Moment.</p></div></div>`;
}

function emptyHtml() {
  const folder = FOLDER[state.folder];
  const words = queryWords();
  if (words.length) {
    const elsewhere = FOLDERS.filter((item) => item.key !== state.folder)
      .map((item) => ({ item, count: inFolder(item.key).filter((mail) => matchesQuery(mail, words)).length }))
      .find((entry) => entry.count);
    const action = elsewhere
      ? `<p class="empty-text">${elsewhere.count === 1 ? "1 Treffer" : `${elsewhere.count} Treffer`} ${elsewhere.item.where}.</p><button type="button" class="empty-action" data-empty="folder" data-folder="${elsewhere.item.key}">${esc(elsewhere.item.label)} ansehen${icon("chevron-right")}</button>`
      : `<button type="button" class="empty-action" data-empty="search">Suche leeren${icon("x")}</button>`;
    return `<div class="empty-state" data-flip="mail-empty">${tinte("ruhe")}<p class="empty-title">Nichts gefunden für „${esc(state.query.trim())}“ ${folder.where}.</p>${action}</div>`;
  }
  if (state.filters.size) {
    const title = state.filters.size === 1 ? FILTERS[[...state.filters][0]].empty : "Keine Mails für diese Filter";
    return `<div class="empty-state" data-flip="mail-empty">${tinte("ruhe")}<p class="empty-title">${esc(title)} ${folder.where}.</p><button type="button" class="empty-action" data-empty="filters">${state.filters.size === 1 ? "Filter entfernen" : "Alle Filter entfernen"}${icon("x")}</button></div>`;
  }
  const copy = {
    inbox: state.cleared ? ["Posteingang leer.", "Alles gelesen und einsortiert."] : state.accounts.length ? ["Keine Mails im Posteingang.", "Neue Mails landen hier."] : ["Noch kein Postfach verbunden.", "Verbinde IServ in den Einstellungen oder füge ein Postfach hinzu."],
    sent: ["Keine gesendeten Mails.", "Was du abschickst, steht hier."],
    drafts: ["Keine Entwürfe.", "Angefangene Mails landen hier, wenn du sie schließt."],
    archive: ["Das Archiv ist leer.", "Archivierte Mails landen hier."],
    trash: ["Der Papierkorb ist leer.", "Gelöschte Mails liegen hier, bis du sie endgültig löschst."],
  }[state.folder];
  const kind = state.folder !== "inbox" ? "ruhe" : lateHour() ? "schlaeft" : "geschafft";
  const action = state.folder === "sent" || state.folder === "drafts"
    ? `<button type="button" class="empty-action" data-empty="compose">Neue Mail schreiben${icon("chevron-right")}</button>`
    : state.folder === "inbox" && !state.accounts.length && !state.loading
      ? `<a class="empty-action" href="/hub/klassisch/email">Postfach hinzufügen${icon("chevron-right")}</a>`
      : "";
  return `<div class="empty-state" data-flip="mail-empty">${tinte(kind)}<p class="empty-title">${copy[0]}</p><p class="empty-text">${copy[1]}</p>${action}</div>`;
}

function groupsHtml() {
  const list = visibleMails();
  const loading = state.loading ? loadingHtml() : "";
  if (!list.length) {
    const quiet = state.loading && !queryWords().length && !state.filters.size;
    return loading + (quiet ? "" : emptyHtml());
  }
  const groups = new Map();
  list.forEach((mail) => {
    const bucket = bucketOf(mail);
    if (!groups.has(bucket)) groups.set(bucket, []);
    groups.get(bucket).push(mail);
  });
  return loading + [...groups.entries()].map(([bucket, mails]) => {
    const label = groupLabel(bucket);
    return `<section class="mail-group" data-group="${bucket}">
      <h2 class="group-head" data-flip="head:${bucket}"><span>${esc(label.title)}</span>${label.meta ? `<small>${esc(label.meta)}</small>` : ""}</h2>
      <ul class="rows">${mails.map(rowHtml).join("")}</ul>
    </section>`;
  }).join("");
}

function holdFocus(paint) {
  const active = document.activeElement;
  const row = active?.closest?.("#mailGroups .mail-row");
  const id = row?.dataset.id;
  const onButton = !!active?.classList?.contains("mail-open");
  paint();
  if (!id || row.isConnected || (document.activeElement && document.activeElement !== document.body)) return;
  const fresh = rowOf(id);
  if (fresh) (onButton ? fresh.querySelector(".mail-open") : fresh).focus({ preventScroll: true });
}

function render({ flip = false } = {}) {
  const paint = () => holdFocus(() => {
    $("mailGroups").innerHTML = groupsHtml();
  });
  if (flip) flipKeyed("#mailGroups .mail-row, #mailGroups .group-head, #mailGroups .empty-state, #mailGroups .loading-card", paint);
  else paint();
  renderCounts();
  renderDates();
}

function renderCounts() {
  renderHead();
  renderFolders();
  renderFilters();
  renderSearchMeta();
  syncNav();
}

function renderHead() {
  const unread = inboxUnread();
  $("mailCount").textContent = state.waiting.size ? "" : unread ? `${unread} ungelesen` : "alles gelesen";
}

function renderFolders({ flip = false } = {}) {
  const paint = () => {
    $("mailFolders").querySelectorAll("[data-folder]").forEach((button) => {
      const key = button.dataset.folder;
      const folder = FOLDER[key];
      const active = key === state.folder;
      const count = key === "inbox" ? inboxUnread() : key === "drafts" ? inFolder("drafts").length : 0;
      const suffix = !count ? "" : key === "inbox" ? `, ${count} ungelesen` : `, ${count} ${count === 1 ? "Entwurf" : "Entwürfe"}`;
      button.setAttribute("aria-pressed", String(active));
      button.setAttribute("aria-label", `${folder.label}${suffix}`);
      button.querySelector(".seg-count").textContent = count ? String(count) : "";
      button.dataset.tip = folder.label;
    });
  };
  if (flip) flipKeyed("#mailFolders [data-folder]", paint, { duration: 240 });
  else paint();
}

function renderFilters() {
  $("mailFilters").querySelectorAll("[data-filter]").forEach((button) => {
    button.setAttribute("aria-pressed", String(state.filters.has(button.dataset.filter)));
  });
}

function renderSearchMeta() {
  const has = !!state.query.trim();
  $("mailSearchClear").hidden = !has;
  $("mailSearchHint").hidden = has || !shortcutsEnabled() || platform.touch;
  $("mailSearch").placeholder = `${FOLDER[state.folder].label} durchsuchen`;
}

function syncNav() {
  if (state.waiting.size) return;
  const unread = inboxUnread();
  document.querySelectorAll('[data-count="mail"]').forEach((node) => {
    node.textContent = unread ? String(unread) : "";
    if (unread) node.setAttribute("aria-label", `${unread} ungelesen`);
    else node.removeAttribute("aria-label");
  });
}

function renderAlert() {
  if (!flags.offline) return;
  $("mailAlert").hidden = false;
  $("mailAlertText").textContent = `Keine Verbindung zu IServ. ${BRAND} zeigt die Mails vom Stand ${syncTime()} Uhr.`;
}

function linkedExists(linked) {
  if (!linked) return false;
  if (linked.type === "event") return (data.events || []).some((item) => item.id === linked.id);
  if (linked.type === "deadline") return (data.deadlines || []).some((item) => item.id === linked.id);
  return [...(data.tasks || []), ...(data.taskPool || [])].some((item) => item.id === linked.id);
}

function suggestStatus(mail) {
  if (state.added.has(mail.id)) return "added";
  return linkedExists(mail.suggestion?.linked) ? "exists" : "new";
}

const upcoming = (suggestion) => !!suggestion && dayDiff(startOfDay(now()), suggestion.date) >= 0;

function suggestWhen(suggestion) {
  const date = shortDate(parseDate(suggestion.date));
  const extra = suggestion.time ? `, ${suggestion.time}` : suggestion.block ? `, ${suggestion.block}. Block` : "";
  const place = suggestion.place ? `, ${suggestion.place}` : "";
  return suggestion.kind === "event" ? `Termin am ${date}${extra}${place}` : `Frist bis ${date}${extra}`;
}

function leafHtml(iso) {
  const target = parseDate(iso);
  const base = now();
  const other = target.getMonth() !== base.getMonth() || target.getFullYear() !== base.getFullYear();
  const soon = dayDiff(startOfDay(base), iso) <= 1;
  return `<span class="leaf${other ? " is-month" : ""}${soon ? " is-soon" : ""}" aria-hidden="true"><span class="leaf-day">${other ? MONTHS_SHORT[target.getMonth()] : WEEKDAYS_SHORT[target.getDay()]}</span><span class="leaf-date">${target.getDate()}</span></span>`;
}

function suggestHtml(mail) {
  const suggestion = mail.suggestion;
  if (!upcoming(suggestion) || mail.folder === "trash") return "";
  const status = suggestStatus(mail);
  const event = suggestion.kind === "event";
  const done = status === "added" ? (event ? "Im Kalender eingetragen" : "In Aufgaben angelegt") : event ? "Steht schon im Kalender" : "Steht schon in Aufgaben";
  const control = status === "new"
    ? `<button type="button" class="suggest-button" data-suggest>${icon(event ? "calendar-plus" : "list-plus")}${event ? "In den Kalender" : "Als Aufgabe anlegen"}</button>`
    : `<span class="suggest-done" tabindex="-1">${icon("check")}${done}</span>`;
  return `<div class="mail-suggest" data-status="${status}" role="group" aria-label="In der Mail erkannt">
      ${leafHtml(suggestion.date)}
      <div class="mail-suggest-text"><p class="mail-suggest-title">${esc(suggestion.title)}</p><p class="mail-suggest-meta">${esc(suggestWhen(suggestion))}</p></div>
      ${control}
    </div>`;
}

function bodyHtml(mail) {
  const marked = upcoming(mail.suggestion) && mail.suggestion.phrase ? esc(mail.suggestion.phrase) : null;
  const blocks = String(mail.body || "").split(/\n{2,}/).filter((block) => block.trim()).map((block) => {
    let html = esc(block);
    if (marked && html.includes(marked)) html = html.replace(marked, `<span class="mail-detected">${marked}</span>`);
    return `<p>${html.replace(/\n/g, "<br>")}</p>`;
  });
  return blocks.join("") || `<p class="reader-empty">Kein Text.</p>`;
}

function filesHtml(mail) {
  if (!mail.attachments.length) return "";
  return `<ul class="reader-files" aria-label="Anhänge">${mail.attachments.map((file, index) => `<li><button type="button" class="reader-file" data-file="${index}" aria-label="${esc(file.name)} herunterladen, ${esc(file.type)}, ${esc(file.size)}">${icon("file-text")}<span class="reader-file-text"><b>${esc(file.name)}</b><small>${esc(file.type)}, ${esc(file.size)}</small></span>${icon("download", "reader-file-get")}</button></li>`).join("")}</ul>`;
}

function footHtml(mail) {
  if (outgoing(mail) || mail.folder === "trash") return "";
  if (mail.noReply) return `<p class="reader-note">Automatisch verschickt, eine Antwort kommt nicht an.</p>`;
  return `<div class="reader-foot"><button type="button" class="btn btn-quiet reader-reply" data-reader-reply>${icon("reply")}Antworten</button></div>`;
}

function readerTools(mail) {
  if (mail.folder === "trash") return [["restore", "undo-2", "Wiederherstellen"], ["destroy", "trash-2", "Endgültig löschen", "#"]];
  if (mail.folder !== "inbox" || mail.account?.endsWith("@iserv")) return [];
  return [["delete", "trash-2", "Löschen", "#"]];
}

function toolHtml(mail, [act, name, label, key]) {
  if (act === "flag") {
    return `<button class="icon-button reader-flag" type="button" data-reader-act="flag" aria-pressed="${mail.flagged}" aria-label="Markieren" data-tip="${mail.flagged ? "Markierung entfernen" : "Markieren"}">${icon(name)}</button>`;
  }
  const danger = act === "delete" || act === "destroy" ? " is-danger" : "";
  return `<button class="icon-button${danger}" type="button" data-reader-act="${act}" aria-label="${esc(label)}" data-tip="${esc(label + keyHint(key))}">${icon(name)}</button>`;
}

function stepTargets() {
  const rows = [...document.querySelectorAll("#mailGroups .mail-row")];
  const index = rows.findIndex((row) => row.dataset.id === state.openId);
  return {
    prev: index > 0 ? rows[index - 1].dataset.id : null,
    next: index >= 0 && index < rows.length - 1 ? rows[index + 1].dataset.id : null,
  };
}

function readerHtml(mail) {
  const detail = detailOf(mail.peer);
  const steps = stepTargets();
  const meta = outgoing(mail) ? `gesendet ${whenText(mail.at)}` : `an ${mail.to}, ${whenText(mail.at)}`;
  const closeTip = platform.touch ? "Schließen" : "Schließen (Esc)";
  return `<div class="reader-bar">
      <div class="reader-tools" role="group" aria-label="Aktionen">${readerTools(mail).map((tool) => toolHtml(mail, tool)).join("")}</div>
      <div class="reader-nav" role="group" aria-label="Blättern">
        <button class="icon-button" type="button" data-reader-step="-1" aria-label="Vorherige Mail" data-tip="Vorherige Mail"${steps.prev ? "" : " disabled"}>${icon("chevron-up")}</button>
        <button class="icon-button" type="button" data-reader-step="1" aria-label="Nächste Mail" data-tip="Nächste Mail"${steps.next ? "" : " disabled"}>${icon("chevron-down")}</button>
      </div>
      <button class="icon-button reader-close" type="button" data-reader-close aria-label="Mail schließen" data-tip="${closeTip}">${icon("x")}</button>
    </div>
    <div class="reader-body">
      <h2 class="reader-subject" id="readerTitle" tabindex="-1">${esc(mail.subject || "(ohne Betreff)")}</h2>
      <div class="reader-from">
        ${avatarHtml(mail.peer, " is-lg")}
        <div class="reader-who">
          <p class="reader-name"><span>${esc(outgoing(mail) ? `An ${mail.peer.name}` : mail.peer.name)}</span>${detail ? `<span class="mail-role">${esc(detail)}</span>` : ""}</p>
          <p class="reader-meta">${esc(meta)}</p>
        </div>
      </div>
      ${suggestHtml(mail)}
      <div class="reader-paper">${bodyHtml(mail)}</div>
      ${filesHtml(mail)}
      ${footHtml(mail)}
    </div>`;
}

function composeHtml(draft) {
  const contacts = (data.page?.contacts || []).map((contact) => `<option value="${esc(contact.name)}">${esc(contact.detail || "")}</option>`).join("");
  const keys = platform.mac
    ? `<kbd aria-label="Befehlstaste">${icon("command")}</kbd><kbd aria-label="Eingabetaste">${icon("corner-down-left")}</kbd>`
    : "<kbd>Strg</kbd><kbd>Enter</kbd>";
  const title = draft.replyTo ? "Antwort" : draft.id ? "Entwurf" : "Neue Mail";
  return `<div class="reader-bar">
      <h2 class="compose-title" id="readerTitle" tabindex="-1">${title}</h2>
      <button class="icon-button is-danger" type="button" data-compose-discard aria-label="Entwurf verwerfen" data-tip="Verwerfen">${icon("trash-2")}</button>
      <button class="icon-button" type="button" data-reader-close aria-label="Schließen, der Entwurf bleibt gespeichert" data-tip="Schließen, bleibt als Entwurf">${icon("x")}</button>
    </div>
    <form class="compose" id="composeForm" novalidate autocomplete="off">
      <label class="field"><span class="field-label">An</span><input class="field-control" id="composeTo" name="to" list="mailContacts" value="${esc(draft.to)}" autocomplete="off" placeholder="Lehrkraft, Gruppe oder Name"></label>
      <p class="compose-error" id="composeToError" hidden>Empfänger fehlt.</p>
      <label class="field"><span class="field-label">Betreff</span><input class="field-control" id="composeSubject" name="subject" value="${esc(draft.subject)}" enterkeyhint="next"></label>
      <label class="field"><span class="field-label">Nachricht</span><textarea class="field-control compose-text" id="composeBody" name="body" rows="9">${esc(draft.body)}</textarea></label>
      <div class="compose-actions">
        ${platform.touch ? "" : `<p class="sheet-hint compose-hint">${keys} sendet</p>`}
        <button class="btn btn-primary compose-send" type="button" data-compose-send>${icon("send")}Senden</button>
      </div>
      <datalist id="mailContacts">${contacts}</datalist>
    </form>`;
}

function markSelected() {
  document.querySelectorAll("#mailGroups .mail-row").forEach((row) => {
    const selected = row.dataset.id === state.openId;
    row.classList.toggle("is-selected", selected);
    const button = row.querySelector(".mail-open");
    if (!button) return;
    if (selected) button.setAttribute("aria-current", "true");
    else button.removeAttribute("aria-current");
  });
}

function renderReader() {
  const reader = $("mailReader");
  if (state.mode === "compose") {
    reader.innerHTML = composeHtml(state.draft);
    return;
  }
  const mail = byId(state.openId);
  if (mail) reader.innerHTML = readerHtml(mail);
}

function applySheet() {
  const open = !!state.mode;
  const sheet = open && isSheet();
  const reader = $("mailReader");
  reader.setAttribute("role", sheet ? "dialog" : "region");
  if (sheet) reader.setAttribute("aria-modal", "true");
  else reader.removeAttribute("aria-modal");
  $("mailScrim").hidden = !sheet;
  root.classList.toggle("is-mail-sheet", sheet);
  [$("mailHead"), $("mailMain"), $("mailDates")].forEach((node) => {
    node.inert = sheet;
  });
  $("mailDates").hidden = open && !isSheet();
}

const awayTransform = () => (phoneQuery.matches ? "translateY(100%)" : "translateX(calc(100% + 24px))");

function animateIn() {
  if (!animates()) return;
  const reader = $("mailReader");
  const easing = token("--ease-out");
  if (!isSheet()) {
    reader.animate(travels() ? [{ opacity: 0, transform: "translateX(12px)" }, { opacity: 1, transform: "none" }] : [{ opacity: 0 }, { opacity: 1 }], { duration: 240, easing });
    return;
  }
  $("mailScrim").animate([{ opacity: 0 }, { opacity: 1 }], { duration: 220, easing });
  if (travels()) reader.animate([{ transform: awayTransform() }, { transform: "none" }], { duration: ms("--dur-sheet-in") || 380, easing: token("--ease-drawer") || easing });
  else reader.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 150, easing });
}

function animateOut(from) {
  if (!animates()) return Promise.resolve();
  const easing = token("--ease-out");
  $("mailScrim").animate([{ opacity: 1 }, { opacity: 0 }], { duration: 220, easing, fill: "forwards" });
  const frames = travels() ? [{ transform: from || "none" }, { transform: awayTransform() }] : [{ opacity: 1 }, { opacity: 0 }];
  return $("mailReader").animate(frames, { duration: travels() ? 280 : 150, easing, fill: "forwards" }).finished.then(() => {}, () => {});
}

function showReader(opening) {
  const reader = $("mailReader");
  reader.hidden = false;
  $("emailPage").classList.add("has-reader");
  applySheet();
  if (opening) {
    animateIn();
    return;
  }
  if (!animates()) return;
  const body = reader.querySelector(".reader-body, .compose");
  body?.animate(travels() ? [{ opacity: 0, translate: "0 var(--lift-sm)" }, { opacity: 1, translate: "0 0" }] : [{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: token("--ease-out") });
}

function cancelClosing() {
  if (!state.closing) return;
  state.closing = false;
  state.closeTicket += 1;
  $("mailReader").getAnimations().forEach((animation) => animation.cancel());
  $("mailScrim").getAnimations().forEach((animation) => animation.cancel());
  $("mailReader").style.transform = "";
}

function rememberInvoker() {
  const active = document.activeElement;
  if (!active || active === document.body || $("mailReader").contains(active)) return;
  state.invoker = active;
  state.invokerRow = active.closest(".mail-row")?.dataset.id || null;
}

function openReader(id) {
  const mail = byId(id);
  if (!mail) return;
  if (mail.folder === "drafts") {
    openCompose(mail);
    return;
  }
  cancelClosing();
  const committed = state.mode === "compose" ? commitDraft({ tell: true }) : null;
  const opening = !state.mode;
  if (opening) rememberInvoker();
  state.mode = "read";
  state.openId = id;
  if (isUnread(mail)) setRead(id, true, { silent: true });
  if (mail.partial) loadBody(mail);
  markSelected();
  renderReader();
  showReader(opening);
  $("mailReader").scrollTop = 0;
  if (isSheet()) $("readerTitle")?.focus({ preventScroll: true });
  if (committed) render();
  announce(`${peerText(mail)}: ${mail.subject}`);
}

function closeReader({ refocus = false, from = null } = {}) {
  if (!state.mode || state.closing) return;
  const id = state.openId;
  const sheet = isSheet();
  const reader = $("mailReader");
  const returnFocus = refocus || sheet || reader.contains(document.activeElement);
  const replied = state.draft?.replyTo || null;
  state.mode = null;
  state.openId = null;
  state.draft = null;
  markSelected();
  const finish = () => {
    const invoker = state.invoker;
    const invokerRow = state.invokerRow;
    state.invoker = null;
    state.invokerRow = null;
    state.closing = false;
    reader.getAnimations().forEach((animation) => animation.cancel());
    $("mailScrim").getAnimations().forEach((animation) => animation.cancel());
    reader.style.transform = "";
    reader.hidden = true;
    reader.innerHTML = "";
    $("emailPage").classList.remove("has-reader");
    applySheet();
    if (!sheet) enterInPlace($("mailDates"));
    if (!returnFocus) return;
    const usable = (node) => node?.isConnected && !node.closest("[inert], [hidden]") && node.getClientRects().length > 0;
    const target = [rowOf(id), rowOf(replied), invoker, rowOf(invokerRow), document.querySelector("#mailGroups .mail-row"), $("mailSearch")]
      .map((node) => (node?.classList?.contains("mail-row") ? node.querySelector(".mail-open") : node))
      .find(usable);
    target?.focus({ preventScroll: true });
  };
  if (sheet && animates()) {
    state.closing = true;
    const ticket = ++state.closeTicket;
    animateOut(from).then(() => {
      if (ticket === state.closeTicket) finish();
    });
  } else {
    finish();
  }
}

function requestClose(options = {}) {
  if (state.mode === "compose") closeCompose(options);
  else closeReader({ refocus: true, ...options });
}

function bindDrag() {
  const reader = $("mailReader");
  let drag = null;
  reader.addEventListener("pointerdown", (event) => {
    if (!state.mode || !phoneQuery.matches || !travels() || event.button !== 0) return;
    if (!event.target.closest(".reader-bar") || event.target.closest("button, input, textarea, select, a")) return;
    drag = { id: event.pointerId, y: event.clientY, t: performance.now(), dy: 0 };
    reader.setPointerCapture(event.pointerId);
  });
  reader.addEventListener("pointermove", (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    drag.dy = Math.max(0, event.clientY - drag.y);
    reader.style.transform = drag.dy ? `translateY(${drag.dy}px)` : "";
  });
  const end = (event) => {
    if (!drag || event.pointerId !== drag.id) return;
    const { dy, t } = drag;
    drag = null;
    const speed = dy / Math.max(1, performance.now() - t);
    if (dy > 120 || (dy > 24 && speed > 0.6)) {
      requestClose({ from: `translateY(${dy}px)` });
      return;
    }
    reader.style.transform = "";
    if (dy) reader.animate([{ transform: `translateY(${dy}px)` }, { transform: "none" }], { duration: 260, easing: token("--ease-out") });
  };
  reader.addEventListener("pointerup", end);
  reader.addEventListener("pointercancel", end);
}

function trapTab(event) {
  if (!state.mode || !isSheet()) return;
  const reader = $("mailReader");
  const nodes = [...reader.querySelectorAll("button:not([disabled]), input, textarea, select, a[href]")].filter((node) => node.getClientRects().length);
  if (!nodes.length) return;
  const active = document.activeElement;
  if (!reader.contains(active)) {
    event.preventDefault();
    (event.shiftKey ? nodes[nodes.length - 1] : nodes[0]).focus();
    return;
  }
  const ahead = event.shiftKey
    ? nodes.some((node) => node.compareDocumentPosition(active) & Node.DOCUMENT_POSITION_FOLLOWING)
    : nodes.some((node) => active.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING);
  if (ahead) return;
  event.preventDefault();
  (event.shiftKey ? nodes[nodes.length - 1] : nodes[0]).focus();
}

function neighbourId(id) {
  const rows = [...document.querySelectorAll("#mailGroups .mail-row")];
  const index = rows.findIndex((row) => row.dataset.id === id);
  if (index < 0) return null;
  return (rows[index + 1] || rows[index - 1])?.dataset.id || null;
}

function focusRow(row) {
  if (!row) return;
  row.focus({ preventScroll: true });
  row.scrollIntoView({ block: "nearest" });
}

function moveMail(id, target) {
  const mail = byId(id);
  if (!mail || mail.folder === target) return;
  const origin = mail.folder;
  const row = rowOf(id);
  const reading = state.mode === "read" && state.openId === id;
  const hadFocus = !!row && (row === document.activeElement || row.contains(document.activeElement));
  const next = neighbourId(id);
  mail.folder = target;
  if (target === "trash") {
    mail.origin = origin;
    clearTimeout(pendingDeletes.get(id));
    pendingDeletes.set(id, setTimeout(() => {
      if (mail.folder === "trash") deleteOnServer(mail);
    }, 12000));
  } else if (origin === "trash") {
    clearTimeout(pendingDeletes.get(id));
    pendingDeletes.delete(id);
  }
  const tidied = origin === "inbox" && target !== "inbox";
  if (tidied) state.cleared += 1;
  const [verb, symbol] = origin === "trash" ? ["Wiederhergestellt", "undo-2"] : MOVES[target] || ["Verschoben", "inbox"];
  if (reading) {
    if (next) openReader(next);
    else closeReader({ refocus: true });
  }
  toast(`${verb}: „${esc(clip(mail.subject || "ohne Betreff"))}“`, {
    icon: symbol,
    action: {
      label: "Rückgängig",
      undo: true,
      run: () => {
        mail.folder = origin;
        if (target === "trash") {
          clearTimeout(pendingDeletes.get(id));
          pendingDeletes.delete(id);
        }
        if (tidied) state.cleared = Math.max(0, state.cleared - 1);
        render({ flip: true });
        enterInPlace(rowOf(id));
      },
    },
  });
  renderCounts();
  exitInPlace(row).then(() => {
    if (row) row.dataset.flip = "leaving";
    render({ flip: true });
    if ((hadFocus || reading) && next && !isSheet()) focusRow(rowOf(next));
  });
}

function destroyMail(id) {
  const index = state.mails.findIndex((mail) => mail.id === id);
  if (index < 0) return;
  const mail = state.mails[index];
  const row = rowOf(id);
  const next = neighbourId(id);
  const reading = state.mode === "read" && state.openId === id;
  state.mails.splice(index, 1);
  if (mail.folder === "trash" && mail.account) {
    deleteOnServer(mail);
    toast(`Endgültig gelöscht: „${esc(clip(mail.subject || "ohne Betreff"))}“`, { icon: "trash-2" });
    if (reading) {
      if (next) openReader(next);
      else closeReader({ refocus: true });
    }
    renderCounts();
    exitInPlace(row).then(() => {
      if (row) row.dataset.flip = "leaving";
      render({ flip: true });
    });
    return;
  }
  if (state.mode === "compose" && state.draft?.id === id) {
    state.draft = null;
    closeReader();
  }
  if (reading) {
    if (next) openReader(next);
    else closeReader({ refocus: true });
  }
  toast(`${mail.folder === "drafts" ? "Entwurf verworfen" : "Endgültig gelöscht"}: „${esc(clip(mail.subject || "ohne Betreff"))}“`, {
    icon: "trash-2",
    action: {
      label: "Rückgängig",
      undo: true,
      run: () => {
        state.mails.splice(Math.min(index, state.mails.length), 0, mail);
        render({ flip: true });
        enterInPlace(rowOf(id));
      },
    },
  });
  renderCounts();
  exitInPlace(row).then(() => {
    if (row) row.dataset.flip = "leaving";
    render({ flip: true });
  });
}

function patchRow(mail) {
  const row = rowOf(mail.id);
  if (!row) return;
  row.classList.toggle("is-unread", isUnread(mail));
  row.querySelector(".mail-open")?.setAttribute("aria-label", ariaFor(mail));
  row.querySelector(".mail-marks").innerHTML = marksInner(mail);
  const actions = row.querySelector(".mail-actions");
  if (actions) actions.outerHTML = actionsHtml(mail);
}

function setRead(id, read, { silent = false } = {}) {
  const mail = byId(id);
  if (!mail || outgoing(mail) || mail.read === read) return;
  mail.read = read;
  patchRow(mail);
  renderCounts();
  if (!silent) announce(read ? "Als gelesen markiert" : "Als ungelesen markiert");
}

function markUnread(id) {
  const reading = state.mode === "read" && state.openId === id;
  setRead(id, false, { silent: reading });
  if (!reading) return;
  closeReader({ refocus: true });
  toast("Als ungelesen markiert.", { icon: "mail" });
}

function popIn(node) {
  if (!node || !animates()) return;
  node.animate(
    travels() ? [{ opacity: 0, transform: "scale(0.4)" }, { opacity: 1, transform: "none" }] : [{ opacity: 0 }, { opacity: 1 }],
    { duration: travels() ? ms("--spring-tactile-dur") || 340 : 150, easing: travels() ? token("--spring-tactile") : "ease-out" },
  );
}

function toggleFlag(id) {
  const mail = byId(id);
  if (!mail) return;
  mail.flagged = !mail.flagged;
  patchRow(mail);
  if (mail.flagged) popIn(rowOf(id)?.querySelector(".mail-mark.is-flag"));
  if (state.mode === "read" && state.openId === id) {
    const button = $("mailReader").querySelector(".reader-flag");
    if (button) {
      button.setAttribute("aria-pressed", String(mail.flagged));
      button.dataset.tip = mail.flagged ? "Markierung entfernen" : "Markieren";
      if (mail.flagged) popIn(button.querySelector(".icon"));
    }
  }
  announce(mail.flagged ? "Markiert" : "Markierung entfernt");
}

function runAct(id, act) {
  const mail = byId(id);
  if (!mail) return;
  if (act === "archive") moveMail(id, "archive");
  else if (act === "inbox") moveMail(id, "inbox");
  else if (act === "delete") moveMail(id, "trash");
  else if (act === "restore") moveMail(id, mail.origin || "inbox");
  else if (act === "destroy") destroyMail(id);
  else if (act === "read") setRead(id, true);
  else if (act === "unread") markUnread(id);
  else if (act === "flag") toggleFlag(id);
}

function refreshSuggest(mail, { focus = false, pop = false } = {}) {
  if (state.mode !== "read" || state.openId !== mail.id) return;
  const box = $("mailReader").querySelector(".mail-suggest");
  if (!box) return;
  box.outerHTML = suggestHtml(mail);
  const fresh = $("mailReader").querySelector(".mail-suggest .suggest-done, .mail-suggest .suggest-button");
  if (pop) popIn(fresh);
  if (focus) fresh?.focus({ preventScroll: true });
}

function acceptSuggestion(id) {
  const mail = byId(id);
  const suggestion = mail?.suggestion;
  if (!suggestion || suggestStatus(mail) !== "new") return;
  state.added.add(id);
  refreshSuggest(mail, { focus: true, pop: true });
  renderDates();
  const event = suggestion.kind === "event";
  const date = shortDate(parseDate(suggestion.date));
  toast(event ? `Im Kalender: „${esc(suggestion.title)}“, ${esc(date)}` : `Aufgabe angelegt: „${esc(suggestion.title)}“, bis ${esc(date)}`, {
    icon: event ? "calendar-check" : "check",
    action: {
      label: "Rückgängig",
      undo: true,
      run: () => {
        state.added.delete(id);
        refreshSuggest(mail);
        renderDates();
      },
    },
  });
}

function openFile(mail, index) {
  const file = mail.attachments[index];
  if (file) toast(`„${esc(file.name)}“ liegt jetzt in Downloads.`, { icon: "download" });
}

function contactFor(name) {
  const clean = String(name || "").trim();
  const known = state.mails.find((mail) => fold(mail.peer.name) === fold(clean))?.peer;
  if (known) return known;
  const contact = (data.page?.contacts || []).find((item) => fold(item.name) === fold(clean));
  if (contact) return { name: contact.name, role: contact.role, subject: contact.subject, hue: contact.hue, detail: contact.role === "student" ? contact.detail : undefined };
  return { name: clean || "Ohne Empfänger", role: "other" };
}

function readDraftFields() {
  if (state.mode !== "compose" || !state.draft) return;
  state.draft.to = $("composeTo")?.value ?? state.draft.to;
  state.draft.subject = $("composeSubject")?.value ?? state.draft.subject;
  state.draft.body = $("composeBody")?.value ?? state.draft.body;
}

function commitDraft({ tell = false } = {}) {
  readDraftFields();
  const draft = state.draft;
  if (!draft) return null;
  let mail = draft.id ? byId(draft.id) : null;
  if (!draft.to.trim() && !draft.subject.trim() && !draft.body.trim()) {
    if (mail) state.mails = state.mails.filter((item) => item.id !== mail.id);
    return null;
  }
  const changed = !mail || mail.to !== draft.to.trim() || mail.subject !== draft.subject.trim() || mail.body !== draft.body;
  if (!mail) {
    mail = { id: `draft-${Date.now()}`, folder: "drafts", direction: "out", read: true, flagged: false, attachments: [] };
    state.mails.push(mail);
    draft.id = mail.id;
  }
  if (changed) Object.assign(mail, { peer: contactFor(draft.to), to: draft.to.trim(), subject: draft.subject.trim(), body: draft.body, at: now() });
  if (tell && changed) toast("Als Entwurf gespeichert.", { icon: "file-pen-line" });
  return mail;
}

function openCompose(source = null) {
  if (state.mode === "compose" && !source) {
    ($("composeTo")?.value ? $("composeBody") : $("composeTo"))?.focus();
    return;
  }
  cancelClosing();
  const committed = state.mode === "compose" ? commitDraft({ tell: true }) : null;
  const opening = !state.mode;
  if (opening) rememberInvoker();
  const draftMail = source?.folder === "drafts" ? source : null;
  state.mode = "compose";
  state.openId = draftMail?.id || null;
  state.draft = {
    id: draftMail?.id || null,
    to: source?.to ?? "",
    subject: source?.subject ?? "",
    body: source?.body ?? "",
    replyTo: source?.replyTo ?? null,
    account: source?.account ?? null,
  };
  markSelected();
  renderReader();
  showReader(opening);
  $("mailReader").scrollTop = 0;
  const field = state.draft.to ? $("composeBody") : $("composeTo");
  field?.focus({ preventScroll: true });
  if (field && field === $("composeBody")) field.setSelectionRange(field.value.length, field.value.length);
  if (committed) render();
}

function closeCompose(options = {}) {
  commitDraft({ tell: true });
  closeReader({ refocus: true, ...options });
  render({ flip: true });
}

const pendingSends = new Map();

function transmit(mail, snapshot) {
  pendingSends.delete(mail.id);
  mailRequest("POST", "/api/ui/mail/send", { account: mail.account, to: mail.to, subject: mail.subject, body: mail.body }).catch((error) => {
    state.mails = state.mails.filter((item) => item.id !== mail.id);
    render({ flip: true });
    openCompose({ to: snapshot.to, subject: snapshot.subject, body: snapshot.body, replyTo: snapshot.replyTo, account: snapshot.account });
    toast(`Nicht gesendet${error.message ? `: ${esc(error.message)}` : ""}. Die Mail liegt wieder im Entwurf.`, { icon: "circle-alert" });
  });
}

addEventListener("pagehide", () => {
  pendingSends.forEach(({ timer, mail, snapshot }) => {
    clearTimeout(timer);
    transmit(mail, snapshot);
  });
});

function sendCompose() {
  readDraftFields();
  const draft = state.draft;
  if (!draft) return;
  const to = draft.to.trim();
  if (!to) {
    $("composeToError").hidden = false;
    $("composeTo").setAttribute("aria-invalid", "true");
    $("composeTo").setAttribute("aria-describedby", "composeToError");
    $("composeTo").focus();
    return;
  }
  const account = draft.account || state.accounts.find((item) => item.kind !== "iserv")?.email || state.accounts[0]?.email;
  if (!account) {
    toast("Zum Senden fehlt ein verbundenes Postfach.", { icon: "circle-alert" });
    return;
  }
  const snapshot = { ...draft, account };
  const saved = draft.id ? byId(draft.id) : null;
  if (saved) state.mails = state.mails.filter((item) => item.id !== saved.id);
  const mail = {
    id: `sent-${Date.now()}`,
    folder: "sent",
    direction: "out",
    read: true,
    flagged: false,
    attachments: [],
    peer: contactFor(to),
    account,
    to,
    subject: draft.subject.trim() || "(ohne Betreff)",
    body: draft.body,
    at: now(),
  };
  state.mails.push(mail);
  closeReader({ refocus: true });
  render({ flip: true });
  const timer = setTimeout(() => transmit(mail, snapshot), 9500);
  pendingSends.set(mail.id, { timer, mail, snapshot });
  toast(`Wird gesendet an ${esc(to)} …`, {
    icon: "send",
    action: {
      label: "Rückgängig",
      undo: true,
      run: () => {
        const pending = pendingSends.get(mail.id);
        if (!pending) return;
        clearTimeout(pending.timer);
        pendingSends.delete(mail.id);
        state.mails = state.mails.filter((item) => item.id !== mail.id);
        if (saved) state.mails.push(saved);
        render({ flip: true });
        openCompose(saved ? { ...saved, to: snapshot.to, subject: snapshot.subject, body: snapshot.body, account } : { to: snapshot.to, subject: snapshot.subject, body: snapshot.body, replyTo: snapshot.replyTo, account });
      },
    },
  });
}

function discardCompose() {
  readDraftFields();
  const draft = state.draft;
  if (!draft) return;
  const snapshot = { ...draft };
  const saved = draft.id ? byId(draft.id) : null;
  if (saved) state.mails = state.mails.filter((item) => item.id !== saved.id);
  closeReader({ refocus: true });
  render({ flip: true });
  if (!saved && !snapshot.to.trim() && !snapshot.subject.trim() && !snapshot.body.trim()) return;
  toast("Entwurf verworfen.", {
    icon: "trash-2",
    action: {
      label: "Rückgängig",
      undo: true,
      run: () => {
        if (saved) state.mails.push(saved);
        render({ flip: true });
        openCompose(saved ? { ...saved, to: snapshot.to, subject: snapshot.subject, body: snapshot.body } : { to: snapshot.to, subject: snapshot.subject, body: snapshot.body, replyTo: snapshot.replyTo });
      },
    },
  });
}

function reply(mail) {
  const subjectLine = /^(re|aw):/i.test(mail.subject) ? mail.subject : `Re: ${mail.subject}`;
  openCompose({ to: mail.peer.detail || mail.peer.name, subject: subjectLine, body: "", replyTo: mail.id, account: mail.account });
}

async function loadBody(mail) {
  try {
    const result = await mailRequest("GET", `/api/ui/mail/message?${mailQuery(mail)}`);
    mail.body = result.body || mail.body;
    mail.partial = false;
    if (state.mode === "read" && state.openId === mail.id) renderReader();
  } catch {
    if (state.mode === "read" && state.openId === mail.id) toast("Die ganze Mail ließ sich gerade nicht laden.", { icon: "wifi-off" });
  }
}

function dateRowHtml(mail) {
  const suggestion = mail.suggestion;
  const added = suggestStatus(mail) === "added";
  const kind = suggestion.kind === "event" ? "Termin" : "Frist";
  const label = `${suggestion.title}, ${kind} ${shortDate(parseDate(suggestion.date))}, aus der Mail von ${mail.peer.name}${added ? ", eingetragen" : ""}`;
  return `<li><button type="button" class="date-row${added ? " is-added" : ""}" data-open="${esc(mail.id)}" aria-label="${esc(label)}">
      ${leafHtml(suggestion.date)}
      <span class="date-text"><span class="date-title">${esc(suggestion.title)}</span><span class="date-sub">${kind}, ${esc(mail.peer.name)}</span></span>
      ${added ? `<span class="date-state">${icon("check")}</span>` : icon("chevron-right", "date-chev")}
    </button></li>`;
}

function renderDates() {
  const card = $("mailDates");
  const items = state.mails
    .filter((mail) => (mail.folder === "inbox" || mail.folder === "archive") && arrived(mail) && upcoming(mail.suggestion) && suggestStatus(mail) !== "exists")
    .sort((a, b) => a.suggestion.date.localeCompare(b.suggestion.date) || (a.suggestion.time || "").localeCompare(b.suggestion.time || ""));
  const open = items.filter((mail) => suggestStatus(mail) === "new");
  const events = open.filter((mail) => mail.suggestion.kind === "event").length;
  const tasks = open.length - events;
  const parts = [];
  if (events) parts.push(`${events} ${events === 1 ? "Termin" : "Termine"}`);
  if (tasks) parts.push(`${tasks} ${tasks === 1 ? "Frist" : "Fristen"}`);
  card.classList.toggle("is-empty", !items.length);
  if (!items.length) {
    card.innerHTML = "";
    return;
  }
  const meta = open.length ? `${parts.join(" und ")}, noch nicht eingetragen` : "Alles eingetragen.";
  card.innerHTML = `<h2 class="side-title" id="mailDatesTitle">Aus deinen Mails</h2>
    <p class="side-meta">${esc(meta)}</p>
    <ul class="date-list">${items.slice(0, 6).map(dateRowHtml).join("")}</ul>`;
}

function announce(text) {
  const node = $("liveStatus");
  if (!node) return;
  node.textContent = "";
  requestAnimationFrame(() => {
    node.textContent = text;
  });
}

function staggerIn(nodes) {
  if (!animates()) return;
  const gap = ms("--stagger") || 0;
  nodes.filter(Boolean).forEach((node, index) => {
    node.animate(
      travels() ? [{ opacity: 0, translate: "0 var(--lift)" }, { opacity: 1, translate: "0 0" }] : [{ opacity: 0 }, { opacity: 1 }],
      { duration: travels() ? ms("--dur-enter") || 320 : 150, delay: index * gap, easing: token("--ease-out"), fill: "backwards" },
    );
  });
}

async function startSync({ initial = false } = {}) {
  if (state.loading) return;
  state.loading = true;
  $("mailSync").classList.add("is-spinning");
  render({ flip: !initial });
  let result = null;
  try {
    result = await mailRequest("GET", "/api/ui/mail");
  } catch {}
  state.loading = false;
  $("mailSync").classList.remove("is-spinning");
  if (!result) {
    render({ flip: true });
    toast("Die Postfächer sind gerade nicht erreichbar.", { icon: "wifi-off" });
    return;
  }
  state.accounts = result.accounts || [];
  const known = new Set(state.mails.map((mail) => mail.id));
  const local = state.mails.filter((mail) => !mail.account || mail.folder !== "inbox");
  const inbox = (result.messages || []).map((mail) => ({ ...mail, at: new Date(mail.received), attachments: [], read: !!mail.read, flagged: false }))
    .filter((mail) => !local.some((item) => item.id === mail.id));
  state.mails = [...local, ...inbox];
  data.mailUnread = inbox.filter((mail) => !mail.read).length;
  const fresh = inbox.filter((mail) => !known.has(mail.id)).map((mail) => mail.id);
  render({ flip: true });
  if (!initial) staggerIn(fresh.map(rowOf));
  if ((result.failed || []).length) toast(`Nicht erreichbar: ${esc(result.failed.join(", "))}`, { icon: "wifi-off" });
  else if (!initial) announce(fresh.length ? `${fresh.length} neue ${fresh.length === 1 ? "Mail" : "Mails"}` : "Keine neuen Mails");
}

let announceTimer = 0;

function setQuery(value, { focus = false } = {}) {
  state.query = value;
  const input = $("mailSearch");
  if (input.value !== value) input.value = value;
  render();
  clearTimeout(announceTimer);
  if (value.trim()) {
    announceTimer = setTimeout(() => {
      const count = visibleMails().length;
      announce(count ? `${count} Treffer` : "Keine Treffer");
    }, 500);
  }
  if (focus) input.focus();
}

function setFolder(key, { keepReader = false } = {}) {
  if (!FOLDER[key] || key === state.folder) return;
  if (state.mode === "read" && !keepReader) closeReader();
  state.folder = key;
  renderFolders({ flip: true });
  const label = $("mailFolders").querySelector(`[data-folder="${key}"] .folder-label`);
  if (animates() && label) label.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: token("--ease-out") });
  render();
  if (animates()) $("mailGroups").animate([{ opacity: 0 }, { opacity: 1 }], { duration: 160, easing: token("--ease-out") });
}

function toggleFilter(key) {
  if (!FILTERS[key]) return;
  if (state.filters.has(key)) state.filters.delete(key);
  else state.filters.add(key);
  render({ flip: true });
}

function reveal(mail) {
  if (mail.folder !== state.folder) setFolder(mail.folder, { keepReader: true });
  if (!visibleMails().some((item) => item.id === mail.id)) {
    state.filters.clear();
    setQuery("");
  }
}

function openFrom(id) {
  const mail = byId(id);
  if (!mail) return;
  reveal(mail);
  openReader(mail.id);
  if (!isSheet()) focusRow(rowOf(mail.id));
}

function onEmptyAction(button) {
  const action = button.dataset.empty;
  if (action === "search") setQuery("", { focus: true });
  else if (action === "filters") {
    state.filters.clear();
    render({ flip: true });
  } else if (action === "folder") setFolder(button.dataset.folder);
  else if (action === "compose") openCompose();
}

function targetId() {
  if (state.mode === "read") return state.openId;
  return document.activeElement?.closest?.("#mailGroups .mail-row")?.dataset.id || null;
}

function step(delta) {
  const rows = [...document.querySelectorAll("#mailGroups .mail-row")];
  if (!rows.length) return;
  const current = state.mode === "read" ? state.openId : document.activeElement?.closest?.(".mail-row")?.dataset.id;
  const index = rows.findIndex((row) => row.dataset.id === current);
  const target = index < 0 ? rows[0] : rows[Math.min(rows.length - 1, Math.max(0, index + delta))];
  if (state.mode === "read" && target.dataset.id !== state.openId) openReader(target.dataset.id);
  if (state.mode && isSheet()) return;
  focusRow(target);
}

function onKey(event) {
  if (event.key === "Tab") {
    trapTab(event);
    return;
  }
  if (event.key === "Escape") {
    if (overlayOpen()) return;
    if (state.mode) {
      event.preventDefault();
      requestClose();
    } else if (event.target === $("mailSearch") && state.query) {
      event.preventDefault();
      setQuery("");
    }
    return;
  }
  if (state.mode === "compose") {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      sendCompose();
    }
    return;
  }
  if (typing(event.target) || event.ctrlKey || event.metaKey || event.altKey || overlayOpen()) return;
  const row = event.target.closest?.(".mail-row");
  if (event.key === "Enter" && row && event.target === row) {
    event.preventDefault();
    openReader(row.dataset.id);
    return;
  }
  if ((event.key === "ArrowDown" || event.key === "ArrowUp") && row) {
    event.preventDefault();
    step(event.key === "ArrowDown" ? 1 : -1);
    return;
  }
  if (!shortcutsEnabled()) return;
  const key = event.key.toLowerCase();
  if (key === "j" || key === "k") {
    event.preventDefault();
    step(key === "j" ? 1 : -1);
    return;
  }
  const id = targetId();
  const mail = id ? byId(id) : null;
  if (key === "e" && mail && (mail.folder === "inbox" || mail.folder === "sent")) {
    event.preventDefault();
    moveMail(id, "archive");
  } else if (key === "u" && mail && !outgoing(mail)) {
    event.preventDefault();
    if (mail.read) markUnread(id);
    else setRead(id, true);
  } else if ((event.key === "#" || event.key === "Delete") && mail) {
    event.preventDefault();
    runAct(id, mail.folder === "trash" || mail.folder === "drafts" ? "destroy" : "delete");
  } else if (event.key === "/") {
    event.preventDefault();
    $("mailSearch").focus();
    $("mailSearch").select();
  } else if (key === "c") {
    event.preventDefault();
    openCompose();
  }
}

function bindReader() {
  const reader = $("mailReader");
  reader.addEventListener("click", (event) => {
    const target = event.target;
    if (target.closest("[data-reader-close]")) {
      requestClose();
      return;
    }
    if (target.closest("[data-compose-discard]")) {
      discardCompose();
      return;
    }
    if (target.closest("[data-compose-send]")) {
      sendCompose();
      return;
    }
    const stepButton = target.closest("[data-reader-step]");
    if (stepButton) {
      const delta = Number(stepButton.dataset.readerStep);
      step(delta);
      reader.querySelector(`[data-reader-step="${delta}"]:not([disabled])`)?.focus({ preventScroll: true });
      return;
    }
    const mail = byId(state.openId);
    if (!mail || state.mode !== "read") return;
    const act = target.closest("[data-reader-act]")?.dataset.readerAct;
    if (act) {
      runAct(mail.id, act);
      return;
    }
    if (target.closest("[data-suggest]")) {
      acceptSuggestion(mail.id);
      return;
    }
    const file = target.closest("[data-file]");
    if (file) {
      openFile(mail, Number(file.dataset.file));
      return;
    }
    if (target.closest("[data-reader-reply]")) reply(mail);
  });
  reader.addEventListener("submit", (event) => event.preventDefault());
  reader.addEventListener("input", (event) => {
    if (state.mode !== "compose" || !state.draft) return;
    const field = event.target;
    if (field.id === "composeTo") {
      state.draft.to = field.value;
      if (field.value.trim()) {
        $("composeToError").hidden = true;
        field.removeAttribute("aria-invalid");
        field.removeAttribute("aria-describedby");
      }
    } else if (field.id === "composeSubject") state.draft.subject = field.value;
    else if (field.id === "composeBody") state.draft.body = field.value;
  });
  reader.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey && !event.metaKey && !event.ctrlKey && event.target.id === "composeSubject") {
      event.preventDefault();
      $("composeBody")?.focus();
    }
  });
}

function paletteItems() {
  const query = $("paletteInput")?.value.trim() || "";
  if (query.length < 2) return [];
  return state.mails
    .filter((mail) => arrived(mail) && mail.folder !== "trash")
    .sort(newestFirst)
    .map((mail) => ({
      group: "E-Mail",
      label: mail.subject || "(ohne Betreff)",
      keywords: `${peerText(mail)} ${detailOf(mail.peer)} ${mail.body}`,
      icon: mail.folder === "drafts" ? "file-pen-line" : "mail",
      hint: peerText(mail),
      run: () => openFrom(mail.id),
    }));
}

function bind() {
  $("mailGroups").addEventListener("click", (event) => {
    const empty = event.target.closest("[data-empty]");
    if (empty) {
      onEmptyAction(empty);
      return;
    }
    const row = event.target.closest(".mail-row");
    if (!row) return;
    const act = event.target.closest("[data-act]")?.dataset.act;
    if (act) {
      runAct(row.dataset.id, act);
      return;
    }
    openReader(row.dataset.id);
  });
  $("mailFolders").addEventListener("click", (event) => {
    const button = event.target.closest("[data-folder]");
    if (button) setFolder(button.dataset.folder);
  });
  $("mailFilters").addEventListener("click", (event) => {
    const button = event.target.closest("[data-filter]");
    if (button) toggleFilter(button.dataset.filter);
  });
  $("mailSearch").addEventListener("input", (event) => setQuery(event.target.value));
  $("mailSearch").addEventListener("keydown", (event) => {
    if (event.key !== "ArrowDown" && event.key !== "Enter") return;
    const first = document.querySelector("#mailGroups .mail-row");
    if (!first) return;
    event.preventDefault();
    focusRow(first);
  });
  $("mailSearchForm").addEventListener("submit", (event) => event.preventDefault());
  $("mailSearchClear").addEventListener("click", () => setQuery("", { focus: true }));
  $("mailSync").addEventListener("click", () => startSync());
  $("mailCompose").addEventListener("click", () => openCompose());
  $("mailDates").addEventListener("click", (event) => {
    const button = event.target.closest("[data-open]");
    if (button) openFrom(button.dataset.open);
  });
  $("mailScrim").addEventListener("click", () => requestClose());
  bindReader();
  bindDrag();
  document.addEventListener("keydown", onKey);
  sheetQuery.addEventListener("change", () => {
    if (!state.mode) return;
    $("mailReader").style.transform = "";
    applySheet();
  });
}

export function init() {
  if (!$("emailPage")) return;
  load();
  bind();
  renderAlert();
  render();
  registerSearch(paletteItems);
  startSync({ initial: true });
}
