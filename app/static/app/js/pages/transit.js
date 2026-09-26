import { data, esc, icon, tinte, now, params } from "../core.js";
import { animates, travels, enterInPlace, token } from "../motion.js";
import { toast } from "../shell.js";

const $ = (id) => document.getElementById(id);

const CATEGORY = {
  fern: { label: "Fernverkehr", icon: "train-front" },
  fernbus: { label: "Fernbus", icon: "bus" },
  regio: { label: "Regionalzug", icon: "train-front" },
  sbahn: { label: "S-Bahn", icon: "train-front" },
  ubahn: { label: "U-Bahn", icon: "train-front-tunnel" },
  tram: { label: "Tram", icon: "tram-front" },
  bus: { label: "Bus", icon: "bus" },
  faehre: { label: "Fähre", icon: "ship" },
  fuss: { label: "Fußweg", icon: "footprints" },
  rad: { label: "Rad", icon: "footprints" },
  sonst: { label: "Verkehrsmittel", icon: "train-front" },
};
const MODE_ORDER = ["fern", "regio", "sbahn", "ubahn", "tram", "bus", "faehre", "fernbus"];
const ROOM = /^(raum\s*)?[a-z]?\d{2,3}[a-z]?$/i;

const places = data.page?.places || {};
const state = {
  from: places.home ? { ...places.home } : null,
  to: null,
  when: "now",
  journeys: [],
  searching: false,
  error: "",
  expanded: -1,
  live: true,
  board: { stop: places.home?.stop || null, name: places.home?.detail || "", departures: [], error: "", at: null },
  suggest: { input: null, items: [], index: -1, timer: 0, ticket: 0 },
};

const clockOf = (iso) => {
  const date = new Date(iso);
  return `${date.getHours()}:${String(date.getMinutes()).padStart(2, "0")}`;
};
const delayOf = (time, planned) => (time && planned ? Math.round((new Date(time) - new Date(planned)) / 60000) : 0);
const untilOf = (iso) => Math.round((new Date(iso) - now()) / 60000);
const stationName = (name) => (name || "").replace(/,?\s*Hauptbahnhof\b/, " Hbf");
const durationText = (minutes) => (minutes < 60 ? `${minutes} Min.` : `${Math.floor(minutes / 60)} Std.${minutes % 60 ? ` ${minutes % 60} Min.` : ""}`);

function untilText(iso) {
  const minutes = untilOf(iso);
  if (minutes <= 0) return "jetzt";
  if (minutes < 60) return `in ${minutes} Min.`;
  return `um ${clockOf(iso)}`;
}

async function api(action, query) {
  const response = await fetch(`/api/ui/transit/${action}?${new URLSearchParams(query)}`);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || "Fahrplan gerade nicht erreichbar");
  return body;
}

function setLive(ok) {
  state.live = ok;
  const node = $("liveState");
  node.classList.toggle("is-off", !ok);
  node.querySelector("span").textContent = ok ? "Live, deutschlandweit" : "Gerade keine Live-Daten";
}

function lineBadge(leg) {
  const info = CATEGORY[leg.category] || CATEGORY.sonst;
  if (leg.category === "fuss") return `<span class="line is-walk">${icon("footprints")}${leg.minutes} Min.</span>`;
  return `<span class="line" data-cat="${esc(leg.category)}">${icon(info.icon)}${esc(leg.line || info.label)}</span>`;
}

function timeHtml(time, planned) {
  const delay = delayOf(time, planned);
  if (delay > 0) return `<s aria-hidden="true">${clockOf(planned)}</s><b class="is-late" aria-label="${clockOf(time)}, ${delay} Minuten später">${clockOf(time)}</b>`;
  return `<b>${clockOf(time || planned)}</b>`;
}

function rides(journey) {
  return journey.legs.filter((leg) => leg.category !== "fuss" && leg.category !== "rad");
}

function transferWarnings(journey) {
  const list = rides(journey);
  const warnings = [];
  for (let index = 1; index < list.length; index += 1) {
    const gap = Math.round((new Date(list[index].from.time) - new Date(list[index - 1].to.time)) / 60000);
    if (gap < 4) warnings.push({ at: list[index].from.name, gap });
  }
  return warnings;
}

function nearHint() {
  const place = state.from?.lat != null ? state.from : places.home;
  return place?.lat != null ? `${place.lat},${place.lon}` : "";
}

function journeySummary(journey) {
  const count = journey.transfers;
  return `${durationText(journey.minutes)}, ${count === 0 ? "direkt" : count === 1 ? "1 Umstieg" : `${count} Umstiege`}`;
}

function ticketBadge(journey) {
  return journey.ticket === "fern" ? `<span class="badge is-fern">${icon("ticket")}Fernverkehr, eigenes Ticket</span>` : "";
}

function ticketNote(journey) {
  if (journey.ticket === "deutschland") return `<p class="j-ticket">${icon("ticket")}Geht mit dem Deutschlandticket.</p>`;
  if (journey.ticket === "fern") return `<p class="j-ticket is-fern">${icon("ticket")}Mit Fernverkehr, dafür reicht das Deutschlandticket nicht.</p>`;
  return "";
}

function legsHtml(journey) {
  const parts = [];
  journey.legs.forEach((leg, index) => {
    if (leg.category === "fuss") {
      if (leg.minutes < 1) return;
      parts.push(`<li class="leg is-walk"><span class="leg-rail" aria-hidden="true"></span><p>${icon("footprints")}${leg.minutes} Min. zu Fuß${leg.distance ? `, ${leg.distance} m` : ""}${index === journey.legs.length - 1 ? ` bis ${esc(leg.to.name)}` : ""}</p></li>`);
      return;
    }
    const stops = leg.stops ? `, ${leg.stops} ${leg.stops === 1 ? "Halt" : "Halte"}` : "";
    parts.push(`<li class="leg" data-cat="${esc(leg.category)}">
      <span class="leg-rail" aria-hidden="true"></span>
      <p class="leg-stop"><span class="leg-time">${timeHtml(leg.from.time, leg.from.planned)}</span><span class="leg-name">${esc(leg.from.name)}</span>${leg.from.track ? `<span class="leg-track">Gl. ${esc(leg.from.track)}</span>` : ""}</p>
      <p class="leg-ride">${lineBadge(leg)}<span>${leg.headsign ? `Richtung ${esc(leg.headsign)}` : esc((CATEGORY[leg.category] || CATEGORY.sonst).label)}${stops}, ${durationText(leg.minutes)}</span>${leg.cancelled ? `<span class="badge is-fern">fällt aus</span>` : ""}</p>
      <p class="leg-stop"><span class="leg-time">${timeHtml(leg.to.time, leg.to.planned)}</span><span class="leg-name">${esc(leg.to.name)}</span>${leg.to.track ? `<span class="leg-track">Gl. ${esc(leg.to.track)}</span>` : ""}</p>
    </li>`);
  });
  const warnings = transferWarnings(journey).map((item) => `<p class="leg-warning">Umstieg in ${esc(item.at)} knapp, ${Math.max(0, item.gap)} Min.</p>`).join("");
  return `${warnings}<ol class="legs">${parts.join("")}</ol>${ticketNote(journey)}`;
}

function plannedAt(time, ride, side) {
  if (!ride?.[side].planned || !ride[side].time) return time;
  return new Date(new Date(time) - (new Date(ride[side].time) - new Date(ride[side].planned))).toISOString();
}

function journeyHtml(journey, index) {
  const list = rides(journey);
  const leave = journey.start;
  const open = state.expanded === index;
  return `<li class="journey${open ? " is-open" : ""}${journey.cancelled ? " is-cancelled" : ""}" data-index="${index}">
    <button class="journey-main" type="button" aria-expanded="${open}" aria-controls="journey-${index}">
      <span class="j-times">${timeHtml(journey.start, plannedAt(journey.start, list[0], "from"))}<span class="j-arrow" aria-hidden="true">${icon("arrow-right")}</span>${timeHtml(journey.end, plannedAt(journey.end, list.at(-1), "to"))}</span>
      <span class="j-until">${journey.realtime ? `<i class="live-dot" aria-hidden="true"></i><span class="visually-hidden">Echtzeit, </span>` : ""}${untilText(leave)}</span>
      <span class="j-legs">${journey.legs.filter((leg) => leg.category !== "fuss" || leg.minutes >= 3).map(lineBadge).join('<span class="j-sep" aria-hidden="true"></span>')}<span class="j-meta">${journeySummary(journey)}</span></span>
      <span class="j-extra">${transferWarnings(journey).length ? `<span class="badge is-fern">Umstieg knapp</span>` : ""}${ticketBadge(journey)}</span>
    </button>
    <div class="j-detail" id="journey-${index}"${open ? "" : " hidden"}>${legsHtml(journey)}</div>
  </li>`;
}

function renderResults() {
  const host = $("results");
  if (!state.from || !state.to) {
    host.innerHTML = "";
    return;
  }
  const title = `<h2 class="group-head" id="resultsTitle"><span>Verbindungen</span><small>${esc(state.from.detail || state.from.name)} nach ${esc(state.to.detail || state.to.name)}</small></h2>`;
  if (state.searching) {
    host.innerHTML = `${title}<div class="loading-card" role="status">${tinte("laedt", 96)}<div><p class="empty-title">Suche Verbindungen</p><p class="empty-text">Live-Daten aus ganz Deutschland.</p></div></div>`;
    return;
  }
  if (state.error) {
    host.innerHTML = `${title}<div class="empty-state">${tinte("ruhe", 130)}<p class="empty-title">${esc(state.error)}</p><p class="empty-text">Die Daten kommen von einem freien Dienst, manchmal hakt er kurz.</p><button type="button" class="empty-action" data-retry>Nochmal versuchen${icon("chevron-right")}</button></div>`;
    return;
  }
  if (!state.journeys.length) {
    host.innerHTML = `${title}<div class="empty-state">${tinte("ruhe", 130)}<p class="empty-title">Keine Verbindung gefunden.</p><p class="empty-text">Probier eine andere Uhrzeit oder eine Haltestelle in der Nähe.</p></div>`;
    return;
  }
  host.innerHTML = `${title}<ol class="journeys">${state.journeys.map(journeyHtml).join("")}</ol>`;
}

function queryTime() {
  if (state.when === "now") return now().toISOString();
  const [hours, minutes] = ($("timeInput").value || "").split(":").map(Number);
  const base = now();
  if (Number.isFinite(hours)) base.setHours(hours, minutes || 0, 0, 0);
  return base.toISOString();
}

async function searchJourneys() {
  if (!state.from?.id || !state.to?.id) return;
  state.searching = true;
  state.error = "";
  state.expanded = -1;
  renderResults();
  try {
    const body = await api("verbindungen", { von: state.from.id, nach: state.to.id, zeit: queryTime(), ankunft: state.when === "arrive" ? "1" : "0" });
    state.journeys = body.journeys || [];
    setLive(true);
  } catch (error) {
    state.journeys = [];
    state.error = error.message;
    setLive(false);
  }
  state.searching = false;
  renderResults();
  const list = $("results").querySelector(".journeys");
  if (list && travels()) [...list.children].forEach((node, index) => node.animate([{ opacity: 0, transform: "translateY(6px)" }, { opacity: 1, transform: "none" }], { duration: 260, delay: index * 40, easing: token("--ease-out"), fill: "backwards" }));
}

function lineWord(ride) {
  const label = (CATEGORY[ride.category] || CATEGORY.sonst).label;
  if (!ride.line) return label;
  return ["bus", "tram", "faehre"].includes(ride.category) ? `${label} ${ride.line}` : ride.line;
}

function routeLabel(key) {
  return key === "school" ? { title: "Schulweg", from: places.home, to: places.school, glyph: "graduation-cap" } : { title: "Heimweg", from: places.school, to: places.home, glyph: "house" };
}

function renderRoutes(summaries = {}) {
  $("routeCards").innerHTML = ["school", "home"].filter((key) => places.home && places.school).map((key) => {
    const route = routeLabel(key);
    const summary = summaries[key];
    const next = summary === undefined
      ? `<span class="route-next is-loading">Suche nächste Fahrt</span>`
      : summary
        ? `<span class="route-next"><b>${esc(summary.line)} um ${clockOf(summary.start)}</b><small>${untilOf(summary.start) < 60 ? `${untilText(summary.start)} los` : "Nächste Fahrt"}, an ${clockOf(summary.end)}</small></span>`
        : `<span class="route-next"><small>Gerade keine Fahrt gefunden</small></span>`;
    return `<button class="route-card" type="button" data-route="${key}">
      <span class="route-glyph" aria-hidden="true">${icon(route.glyph)}</span>
      <span class="route-text"><b>${route.title}</b><small>nach ${esc(route.to.detail)}</small></span>
      ${next}
    </button>`;
  }).join("");
}

async function loadRoutes() {
  if (!places.home || !places.school) return;
  const summaries = {};
  await Promise.all(["school", "home"].map(async (key) => {
    const route = routeLabel(key);
    try {
      const body = await api("verbindungen", { von: route.from.id, nach: route.to.id, zeit: now().toISOString(), ankunft: "0" });
      const journey = (body.journeys || []).find((item) => untilOf(item.start) >= 0) || body.journeys?.[0];
      const ride = journey && rides(journey)[0];
      summaries[key] = journey ? { line: ride ? lineWord(ride) : "Zu Fuß", start: journey.start, end: journey.end } : null;
    } catch {
      summaries[key] = null;
    }
  }));
  renderRoutes(summaries);
}

function renderBoard() {
  const board = state.board;
  const rows = board.departures.slice(0, 9).map((item) => {
    const delay = delayOf(item.time, item.planned);
    return `<li class="dep${item.cancelled ? " is-cancelled" : ""}">
      <span class="dep-time"><b>${clockOf(item.planned || item.time)}</b>${item.cancelled ? `<small class="is-late">fällt aus</small>` : delay > 0 ? `<small class="is-late">+${delay}</small>` : item.realtime ? `<small class="is-ontime">pünktlich</small>` : ""}</span>
      ${lineBadge(item)}
      <span class="dep-dir"><span>${esc(stationName(item.direction))}</span><small>${[item.track ? `Gl. ${esc(item.track)}` : "", item.cancelled ? "" : untilText(item.time)].filter(Boolean).join(", ")}</small></span>
    </li>`;
  }).join("");
  const body = board.error
    ? `<p class="board-empty">${esc(board.error)}</p>`
    : board.at == null
      ? `<p class="board-empty">Lade Abfahrten</p>`
      : rows
        ? `<ol class="board-list">${rows}</ol>`
        : `<p class="board-empty">In der nächsten Stunde fährt hier nichts ab.</p>`;
  $("board").innerHTML = `<h2 class="side-title">Abfahrten</h2>
    <p class="side-meta">${esc(board.name)}</p>
    ${body}
    ${board.at ? `<p class="side-hint">Stand ${clockOf(board.at)} Uhr, aktualisiert sich jede Minute.</p>` : ""}`;
}

async function loadBoard() {
  if (!state.board.stop) return;
  try {
    const body = await api("abfahrten", { stop: state.board.stop, n: 14, zeit: now().toISOString() });
    state.board.departures = body.departures || [];
    state.board.name = body.stop || state.board.name;
    state.board.error = "";
    state.board.at = now().toISOString();
    setLive(true);
  } catch (error) {
    state.board.error = error.message;
    setLive(false);
  }
  renderBoard();
}

function placeIcon(item) {
  if (item.kind !== "stop") return icon("map-pin");
  const best = MODE_ORDER.find((mode) => item.modes?.includes(mode));
  return icon((CATEGORY[best] || CATEGORY.bus).icon);
}

function savedPlaces() {
  return Object.values(places).map((place) => ({ id: place.id, name: place.name, area: place.detail, kind: place.stop ? "stop" : "place", saved: true, detail: place.detail, stop: place.stop, lat: place.lat, lon: place.lon }));
}

function openSuggest(input, items, hint = "") {
  const list = $("placeList");
  state.suggest.input = input;
  state.suggest.items = items;
  state.suggest.index = -1;
  if (!items.length) {
    closeSuggest();
    return;
  }
  list.innerHTML = (hint ? `<li class="place-hint" role="presentation">${esc(hint)}</li>` : "") + items.map((item, index) => `<li role="option" id="place-${index}" aria-selected="false" data-index="${index}">
    <span class="place-icon" aria-hidden="true">${item.saved ? icon(item.name === "Schule" ? "graduation-cap" : "house") : placeIcon(item)}</span>
    <span class="place-text"><b>${esc(item.name)}</b>${item.area ? `<small>${esc(item.area)}</small>` : ""}</span>
  </li>`).join("");
  list.dataset.for = input.id;
  list.hidden = false;
  input.setAttribute("aria-expanded", "true");
}

function closeSuggest() {
  const list = $("placeList");
  list.hidden = true;
  ["fromInput", "toInput"].forEach((id) => {
    $(id).setAttribute("aria-expanded", "false");
    $(id).removeAttribute("aria-activedescendant");
  });
  state.suggest.items = [];
  state.suggest.index = -1;
}

function moveSuggest(step) {
  const { items, input } = state.suggest;
  if (!items.length) return;
  state.suggest.index = (state.suggest.index + step + items.length) % items.length;
  $("placeList").querySelectorAll("[role=option]").forEach((node, index) => node.setAttribute("aria-selected", String(index === state.suggest.index)));
  input.setAttribute("aria-activedescendant", `place-${state.suggest.index}`);
}

function pickPlace(input, item) {
  const detail = item.saved ? item.detail : item.area && !item.name.includes(item.area) ? `${item.name}, ${item.area}` : item.name;
  const place = { id: item.id, name: item.name, detail, stop: item.saved ? item.stop : item.kind === "stop" ? item.id : null, lat: item.lat, lon: item.lon };
  input.value = item.saved ? `${item.name}, ${item.detail}` : detail;
  if (input.id === "fromInput") {
    state.from = place;
    if (place.stop) {
      state.board = { ...state.board, stop: place.stop, name: place.detail, departures: [], at: null, error: "" };
      renderBoard();
      loadBoard();
    }
  } else {
    state.to = place;
  }
  closeSuggest();
}

function scheduleSuggest(input) {
  clearTimeout(state.suggest.timer);
  const text = input.value.trim();
  if (text.length < 2) {
    openSuggest(input, savedPlaces());
    return;
  }
  state.suggest.timer = setTimeout(async () => {
    const ticket = ++state.suggest.ticket;
    try {
      const body = await api("suche", { q: text, nahe: nearHint() });
      if (ticket !== state.suggest.ticket || document.activeElement !== input) return;
      openSuggest(input, body.places || []);
      setLive(true);
    } catch {
      if (ticket === state.suggest.ticket) closeSuggest();
    }
  }, 260);
}

function bindField(input, key) {
  input.addEventListener("focus", () => {
    if (!input.value.trim()) openSuggest(input, savedPlaces());
  });
  input.addEventListener("input", () => {
    state[key] = null;
    scheduleSuggest(input);
  });
  input.addEventListener("keydown", (event) => {
    const open = !$("placeList").hidden && state.suggest.input === input;
    if (event.key === "ArrowDown" && open) {
      event.preventDefault();
      moveSuggest(1);
    } else if (event.key === "ArrowUp" && open) {
      event.preventDefault();
      moveSuggest(-1);
    } else if (event.key === "Enter" && open && state.suggest.items.length) {
      event.preventDefault();
      pickPlace(input, state.suggest.items[Math.max(0, state.suggest.index)]);
      if (key === "from") $("toInput").focus();
      else searchJourneys();
    } else if (event.key === "Escape" && open) {
      event.preventDefault();
      closeSuggest();
    }
  });
  input.addEventListener("blur", () => setTimeout(() => {
    if (state.suggest.input === input && !$("placeList").contains(document.activeElement)) closeSuggest();
  }, 160));
}

function setWhen(mode) {
  state.when = mode;
  $("whenMode").querySelectorAll("[data-when]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.when === mode)));
  const input = $("timeInput");
  input.hidden = mode === "now";
  if (mode !== "now" && !input.value) {
    const date = now();
    input.value = `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
  }
}

function useRoute(key) {
  const route = routeLabel(key);
  state.from = { ...route.from };
  state.to = { ...route.to };
  $("fromInput").value = `${route.from.name}, ${route.from.detail}`;
  $("toInput").value = `${route.to.name}, ${route.to.detail}`;
  setWhen("now");
  searchJourneys();
  $("results").scrollIntoView({ block: "start", behavior: travels() ? "smooth" : "auto" });
}

async function locate() {
  if (!navigator.geolocation) {
    toast("Dein Browser gibt keinen Standort heraus.", { icon: "locate" });
    return;
  }
  navigator.geolocation.getCurrentPosition(async (position) => {
    try {
      const body = await api("naehe", { lat: position.coords.latitude.toFixed(5), lon: position.coords.longitude.toFixed(5) });
      const stop = body.stops?.[0];
      if (!stop) {
        toast("In der Nähe gibt es keine Haltestelle.", { icon: "locate" });
        return;
      }
      pickPlace($("fromInput"), { id: stop.id, name: stop.name, kind: "stop", lat: stop.lat, lon: stop.lon });
      toast(`Nächste Haltestelle: ${esc(stop.name)}`, { icon: "locate" });
    } catch (error) {
      toast(esc(error.message), { icon: "locate" });
    }
  }, () => toast("Standort nicht freigegeben. Du kannst die Haltestelle auch eintippen.", { icon: "locate" }), { maximumAge: 120000, timeout: 10000 });
}

function savedTarget(text) {
  if (places.school && (ROOM.test(text) || /schule|gymnasium|ehg/i.test(text))) return savedPlaces().find((item) => item.id === places.school.id);
  if (places.home && /zuhause|daheim/i.test(text)) return savedPlaces().find((item) => item.id === places.home.id);
  return null;
}

async function resolveTarget(text) {
  const input = $("toInput");
  const saved = savedTarget(text);
  if (saved) {
    pickPlace(input, saved);
    searchJourneys();
    return;
  }
  input.value = text;
  try {
    const body = await api("suche", { q: text, nahe: nearHint() });
    const items = body.places || [];
    const specific = /\d|,/.test(text) || text.trim().split(/\s+/).length > 1;
    if (specific && items.length) {
      pickPlace(input, items[0]);
      searchJourneys();
      return;
    }
    input.focus({ preventScroll: true });
    openSuggest(input, items, items.length ? `Welches „${text}“ meinst du?` : "");
    if (!items.length) toast("Diesen Ort finde ich nicht. Tipp ihn genauer ein.", { icon: "map-pin" });
  } catch {
    setLive(false);
  }
}

function bind() {
  bindField($("fromInput"), "from");
  bindField($("toInput"), "to");
  $("placeList").addEventListener("pointerdown", (event) => event.preventDefault());
  $("placeList").addEventListener("click", (event) => {
    const option = event.target.closest("[role=option]");
    if (!option || !state.suggest.input) return;
    const input = state.suggest.input;
    pickPlace(input, state.suggest.items[Number(option.dataset.index)]);
    if (input.id === "fromInput") $("toInput").focus();
    else searchJourneys();
  });
  $("swapButton").addEventListener("click", () => {
    [state.from, state.to] = [state.to, state.from];
    [$("fromInput").value, $("toInput").value] = [$("toInput").value, $("fromInput").value];
    if (animates()) $("swapButton").animate([{ transform: "rotate(0)" }, { transform: "rotate(180deg)" }], { duration: 320, easing: token("--ease-out") });
    if (state.from?.stop) {
      state.board = { ...state.board, stop: state.from.stop, name: state.from.detail, departures: [], at: null, error: "" };
      loadBoard();
    }
    searchJourneys();
  });
  $("whenMode").addEventListener("click", (event) => {
    const button = event.target.closest("[data-when]");
    if (!button) return;
    setWhen(button.dataset.when);
    if (button.dataset.when !== "now") $("timeInput").focus();
  });
  $("tripSearch").addEventListener("submit", (event) => {
    event.preventDefault();
    if (!state.from || !state.to) {
      ($("fromInput").value && state.from ? $("toInput") : $("fromInput")).focus();
      toast("Wähle Start und Ziel aus den Vorschlägen.", { icon: "map-pin" });
      return;
    }
    searchJourneys();
  });
  $("routeCards").addEventListener("click", (event) => {
    const card = event.target.closest("[data-route]");
    if (card) useRoute(card.dataset.route);
  });
  $("results").addEventListener("click", (event) => {
    if (event.target.closest("[data-retry]")) {
      searchJourneys();
      return;
    }
    const head = event.target.closest(".journey-main");
    if (!head) return;
    const item = head.closest(".journey");
    const index = Number(item.dataset.index);
    state.expanded = state.expanded === index ? -1 : index;
    renderResults();
    const detail = $(`journey-${index}`);
    if (state.expanded === index && detail) enterInPlace(detail);
    $("results").querySelector(`.journey[data-index="${index}"] .journey-main`)?.focus({ preventScroll: true });
  });
  $("locateButton").addEventListener("click", locate);
}

function refreshLoop() {
  setInterval(() => {
    if (document.hidden) return;
    loadBoard();
    loadRoutes();
    if (state.journeys.length) renderResults();
  }, 60000);
}

export function init() {
  bind();
  if (state.from) $("fromInput").value = `${state.from.name}, ${state.from.detail}`;
  renderRoutes();
  renderBoard();
  loadBoard();
  loadRoutes();
  const target = params.get("nach");
  if (target) resolveTarget(target);
  refreshLoop();
}
