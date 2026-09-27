import { root, variant } from "./core.js";

const reducedQuery = matchMedia("(prefers-reduced-motion: reduce)");

export const reduced = () => reducedQuery.matches;
export const level = () => (reduced() ? "reduced" : variant.motion);
export const animates = () => level() !== "minimal";
export const travels = () => animates() && !reduced();
export const rich = () => level() === "rich";

export const token = (name) => getComputedStyle(root).getPropertyValue(name).trim();
export const ms = (name) => parseFloat(token(name)) || 0;

export function timing(kind) {
  const table = {
    critical: ["--spring-critical-fast", "--spring-critical"],
    criticalSlow: ["--spring-critical-slow", "--spring-critical"],
    tactile: ["--spring-tactile-dur", "--spring-tactile"],
    delight: ["--spring-delight-dur", "--spring-delight"],
    state: ["--dur-state", "--ease-out"],
    fade: ["--dur-crossfade", "--ease-out"],
    exit: ["--dur-exit", "--ease-out"],
  };
  const [duration, easing] = table[kind] || table.critical;
  return { duration: ms(duration), easing: token(easing) || "ease-out", fill: "backwards" };
}

export function bezier(x1, y1, x2, y2) {
  const cx = 3 * x1;
  const bx = 3 * (x2 - x1) - cx;
  const ax = 1 - cx - bx;
  const cy = 3 * y1;
  const by = 3 * (y2 - y1) - cy;
  const ay = 1 - cy - by;
  const sampleX = (t) => ((ax * t + bx) * t + cx) * t;
  const sampleY = (t) => ((ay * t + by) * t + cy) * t;
  const slopeX = (t) => (3 * ax * t + 2 * bx) * t + cx;
  const solve = (x) => {
    let t = x;
    for (let i = 0; i < 8; i += 1) {
      const error = sampleX(t) - x;
      if (Math.abs(error) < 1e-5) return t;
      const slope = slopeX(t);
      if (Math.abs(slope) < 1e-6) break;
      t -= error / slope;
    }
    let low = 0;
    let high = 1;
    t = x;
    while (high - low > 1e-6) {
      const value = sampleX(t);
      if (Math.abs(value - x) < 1e-5) return t;
      if (x > value) low = t;
      else high = t;
      t = (low + high) / 2;
    }
    return t;
  };
  return (x) => (x <= 0 ? 0 : x >= 1 ? 1 : sampleY(solve(x)));
}

export function flip(elements, mutate, kind = "critical") {
  if (!travels()) {
    mutate();
    return;
  }
  const first = new Map();
  elements.forEach((element) => {
    if (element?.isConnected) first.set(element, element.getBoundingClientRect());
  });
  mutate();
  const base = kind === "close" ? { duration: 260, easing: token("--ease-out"), fill: "backwards" } : timing(kind);
  first.forEach((rect, element) => {
    if (!element.isConnected) return;
    const last = element.getBoundingClientRect();
    const dx = rect.left - last.left;
    const dy = rect.top - last.top;
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) return;
    element.getAnimations().forEach((animation) => animation.cancel());
    element.animate([{ translate: `${dx}px ${dy}px` }, { translate: "0 0" }], base);
  });
}

const flipKey = (node) => {
  if (node.dataset.flip) return node.dataset.flip;
  if (node.dataset.id) return `${node.parentElement?.id || ""}:${node.dataset.id}`;
  return node.id || null;
};

export function flipKeyed(selector, mutate, { duration = 260 } = {}) {
  if (!travels()) {
    mutate();
    return;
  }
  const first = new Map();
  document.querySelectorAll(selector).forEach((node) => {
    const key = flipKey(node);
    if (key) first.set(key, node.getBoundingClientRect());
  });
  mutate();
  const easing = token("--ease-out");
  document.querySelectorAll(selector).forEach((node) => {
    const key = flipKey(node);
    const rect = key && first.get(key);
    if (!rect) {
      if (key && node.offsetParent) node.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 160, easing });
      return;
    }
    const last = node.getBoundingClientRect();
    const dx = rect.left - last.left;
    const dy = rect.top - last.top;
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) return;
    node.getAnimations().forEach((animation) => animation.cancel());
    node.animate([{ translate: `${dx}px ${dy}px` }, { translate: "0 0" }], { duration, easing });
  });
}

export function exitInPlace(node) {
  if (!node || !animates()) return Promise.resolve();
  const frames = travels() ? [{ opacity: 1, scale: 1 }, { opacity: 0, scale: 0.98 }] : [{ opacity: 1 }, { opacity: 0 }];
  return node.animate(frames, { duration: 160, easing: token("--ease-out"), fill: "forwards" }).finished.then(() => {}, () => {});
}

export function enterInPlace(node) {
  if (!node || !animates()) return;
  const frames = travels() ? [{ opacity: 0, translate: "0 var(--lift-sm)" }, { opacity: 1, translate: "0 0" }] : [{ opacity: 0 }, { opacity: 1 }];
  node.animate(frames, { duration: travels() ? ms("--dur-enter") : 150, easing: token("--ease-out") });
}

function digitMarkup(char) {
  const holder = document.createElement("span");
  holder.className = "digit";
  const inner = document.createElement("span");
  inner.textContent = char;
  holder.append(inner);
  return holder;
}

export function setDigits(node, value, trend = 0) {
  const next = String(value);
  const current = node.dataset.value;
  node.dataset.value = next;
  if (current === next) return;
  if (current == null || current.length !== next.length || !travels()) {
    node.replaceChildren(...[...next].map(digitMarkup));
    if (current != null && animates()) node.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 150, easing: "ease-out" });
    return;
  }
  const direction = trend || (Number(next) < Number(current) ? -1 : 1);
  const slots = [...node.children];
  [...next].forEach((char, index) => {
    const slot = slots[index];
    [...slot.children].slice(0, -1).forEach((child) => child.remove());
    const old = slot.lastElementChild;
    old.getAnimations().forEach((animation) => animation.cancel());
    old.style.position = "";
    old.style.left = "";
    old.removeAttribute("aria-hidden");
    if (old.textContent === char) return;
    const fresh = document.createElement("span");
    fresh.textContent = char;
    slot.append(fresh);
    const travel = direction < 0 ? "-100%" : "100%";
    const back = direction < 0 ? "100%" : "-100%";
    const delay = (next.length - 1 - index) * ms("--stagger-digit");
    const base = { duration: ms("--dur-digit"), easing: token("--spring-critical"), delay };
    old.style.position = "absolute";
    old.style.left = "0";
    old.setAttribute("aria-hidden", "true");
    old.animate([{ translate: "0 0", opacity: 1 }, { translate: `0 ${back}`, opacity: 0 }], { ...base, fill: "forwards" }).finished.then(() => old.remove(), () => old.remove());
    fresh.animate([{ translate: `0 ${travel}`, opacity: 0 }, { translate: "0 0", opacity: 1 }], { ...base, fill: "backwards" });
  });
}

export function pop(nodes) {
  if (!rich() || !travels()) return;
  nodes.forEach((node) => {
    node.classList.add("is-pop");
    node.addEventListener("animationend", () => node.classList.remove("is-pop"), { once: true });
  });
}

export function crossfade(node, duration = 150) {
  if (!animates() || !node) return;
  node.animate([{ opacity: 0 }, { opacity: 1 }], { duration, easing: token("--ease-out") || "ease-out" });
}

export function swapText(node, html) {
  if (!node) return;
  if (node.innerHTML === html) return;
  if (!animates() || !node.innerHTML) {
    node.innerHTML = html;
    return;
  }
  const move = travels();
  const out = node.animate(
    move ? [{ opacity: 1, translate: "0 0" }, { opacity: 0, translate: "0 calc(var(--slide) * -1)" }] : [{ opacity: 1 }, { opacity: 0 }],
    { duration: 140, easing: "ease-out", fill: "forwards" },
  );
  out.finished.then(() => {
    out.cancel();
    node.innerHTML = html;
    node.animate(
      move ? [{ opacity: 0, translate: "0 var(--slide)" }, { opacity: 1, translate: "0 0" }] : [{ opacity: 0 }, { opacity: 1 }],
      { duration: move ? ms("--dur-enter-fade") || 240 : 150, easing: token("--ease-out") },
    );
  }, () => {
    node.innerHTML = html;
  });
}

export function breath(node) {
  if (!travels() || !node) return;
  node.classList.remove("is-breath");
  void node.offsetWidth;
  node.classList.add("is-breath");
  node.addEventListener("animationend", () => node.classList.remove("is-breath"), { once: true });
}

const CHECK_MAIN = "M5 21 Q 12.5 26.5 20 33 Q 36 14.5 59 5";
const CHECK_GRAIN = "M8.5 23.5 Q 14.5 28 20.5 31.6 Q 37 17.2 57 8.2";

export function chalkCheck(host, { play = false } = {}) {
  if (!host) return;
  const dust = play && rich() && travels()
    ? [[61, 3], [64, 9], [55, 1], [66, 4], [58, 11]].map(([x, y], index) => `<circle class="chalk-dust" cx="${x}" cy="${y}" r="${index % 2 ? 1.3 : 1.8}" style="--i:${index}"/>`).join("")
    : "";
  host.innerHTML = `<svg viewBox="0 0 70 40" aria-hidden="true" focusable="false">
    <path class="chalk-grain" d="${CHECK_GRAIN}" pathLength="1"/>
    <path class="chalk-stroke" d="${CHECK_MAIN}" pathLength="1"/>${dust}
  </svg>`;
  if (!play || !animates()) return;
  if (!travels()) {
    host.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 150, easing: "ease-out" });
    return;
  }
  const stroke = host.querySelector(".chalk-stroke");
  const grain = host.querySelector(".chalk-grain");
  const draw = [{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }];
  const curve = token("--ease-out");
  stroke.animate(draw, { duration: 450, easing: curve, fill: "backwards" });
  grain.animate(draw, { duration: 450, delay: 60, easing: curve, fill: "backwards" });
  host.querySelectorAll(".chalk-dust").forEach((dot, index) => {
    dot.animate(
      [{ opacity: 0, translate: "0 0" }, { opacity: 1, offset: 0.35 }, { opacity: 0, translate: `${3 + index}px ${-4 - index}px` }],
      { duration: 700, delay: 380 + index * 30, easing: curve, fill: "backwards" },
    );
  });
}

export function afterIdle(callback) {
  const wait = () => {
    const running = document.getAnimations().filter((animation) => animation.playState === "running");
    if (!running.length) callback();
    else Promise.allSettled(running.map((animation) => animation.finished)).then(() => requestAnimationFrame(wait));
  };
  requestAnimationFrame(wait);
}
