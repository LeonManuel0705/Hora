import { reducedMotion } from "./motion.js";

const effects = new Set();
let frame = 0;
let listening = false;

function tick() {
  frame = 0;
  const vh = innerHeight;
  for (const effect of effects) if (effect.visible) effect.run(vh);
}

function request() {
  if (!frame) frame = requestAnimationFrame(tick);
}

function listen() {
  if (listening) return;
  listening = true;
  addEventListener("scroll", request, { passive: true });
  addEventListener("resize", request, { passive: true });
}

export const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));

export function onScroll(el, update, margin = "25%") {
  if (!el) return () => {};
  listen();
  const effect = { visible: false, run: (vh) => update(el.getBoundingClientRect(), vh) };
  const io = new IntersectionObserver(([entry]) => {
    effect.visible = entry.isIntersecting;
    if (effect.visible) request();
  }, { rootMargin: `${margin} 0px ${margin} 0px` });
  io.observe(el);
  effects.add(effect);
  request();
  return () => {
    io.disconnect();
    effects.delete(effect);
  };
}

export function wordReveal(el, track = el) {
  if (!el || !track) return () => {};
  const words = [...el.querySelectorAll(".w")];
  if (reducedMotion()) {
    el.classList.add("is-lit");
    return () => {};
  }
  const span = 4;
  const last = new Array(words.length).fill(-1);
  return onScroll(track, (box, vh) => {
    const progress = clamp((vh * 0.15 - box.top) / Math.max(1, box.height - vh * 1.05));
    const lit = progress * (words.length + span);
    for (let i = 0; i < words.length; i++) {
      const a = Math.round(clamp((lit - i) / span) * 100) / 100;
      if (a === last[i]) continue;
      last[i] = a;
      words[i].style.opacity = (0.24 + 0.76 * a).toFixed(2);
    }
  });
}

export function revealOnce(root, selector) {
  const items = [...root.querySelectorAll(selector)];
  if (!items.length) return () => {};
  if (reducedMotion() || !("IntersectionObserver" in window)) {
    items.forEach((item) => item.classList.add("is-in"));
    return () => {};
  }
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-in");
      io.unobserve(entry.target);
    }
  }, { rootMargin: "0px 0px -12% 0px", threshold: 0.15 });
  items.forEach((item) => io.observe(item));
  return () => io.disconnect();
}
