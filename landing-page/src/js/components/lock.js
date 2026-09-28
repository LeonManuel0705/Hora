import { escapeHtml } from "../lib/i18n.js";
import { reducedMotion } from "../lib/motion.js";

const DOTS = [
  ["#E7C694", -58, -30], ["#A3B690", 60, -26], ["#B7A6F6", -66, 22],
  ["#C1657E", 64, 26], ["#4FBADE", -30, 58], ["#E88F86", 34, 60],
];

export function lockHTML(label, cls = "") {
  const dots = DOTS.map(([color, x, y]) => `<circle class="lk-dot" cx="80" cy="95" r="4.2" fill="${color}" data-x="${x}" data-y="${y}"/>`).join("");
  return `<div class="lk ${cls}" data-lock role="img" aria-label="${escapeHtml(label)}">
    <svg viewBox="0 0 160 160" focusable="false" aria-hidden="true">
      <defs>
        <linearGradient id="lk-body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FBFBFD"/><stop offset="1" stop-color="#C4C4C9"/></linearGradient>
        <linearGradient id="lk-steel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#8E8E93"/><stop offset="0.5" stop-color="#EDEDF0"/><stop offset="1" stop-color="#8E8E93"/></linearGradient>
      </defs>
      <circle class="lk-ring" cx="80" cy="97" r="44"/>
      <g class="lk-dots">${dots}</g>
      <path class="lk-shackle" d="M61 78V60a19 19 0 0 1 38 0v18"/>
      <g class="lk-body-group">
        <rect class="lk-body" x="48" y="72" width="64" height="52" rx="13"/>
        <rect class="lk-shine" x="52" y="75" width="56" height="10" rx="5"/>
        <circle class="lk-hole" cx="80" cy="95" r="6.5"/>
        <rect class="lk-hole" x="77.2" y="97" width="5.6" height="12" rx="2.8"/>
      </g>
    </svg>
  </div>`;
}

function play(lock) {
  const ease = "cubic-bezier(0.28, 0.11, 0.32, 1)";
  const dots = [...lock.querySelectorAll(".lk-dot")];
  dots.forEach((dot, i) => {
    const from = `translate(${dot.dataset.x}px, ${dot.dataset.y}px) scale(1)`;
    dot.animate([
      { transform: from, opacity: 0 },
      { transform: from, opacity: 1, offset: 0.2 },
      { transform: "translate(0, 0) scale(0.2)", opacity: 0 },
    ], { duration: 760, delay: 80 + i * 45, easing: "cubic-bezier(0.55, 0, 0.75, 0.3)", fill: "both" });
  });
  lock.querySelector(".lk-shackle").animate([
    { transform: "translate(0, -17px) rotate(-26deg)" },
    { transform: "translate(0, -17px) rotate(0deg)", offset: 0.5, easing: "cubic-bezier(0.55, 0, 0.9, 0.55)" },
    { transform: "translate(0, 3px) rotate(0deg)", offset: 0.82, easing: ease },
    { transform: "translate(0, 0) rotate(0deg)" },
  ], { duration: 720, delay: 560, easing: ease, fill: "both" });
  lock.querySelector(".lk-body-group").animate([
    { transform: "scale(1, 1)" },
    { transform: "scale(1.045, 0.95)", offset: 0.35 },
    { transform: "scale(1, 1)" },
  ], { duration: 320, delay: 1150, easing: ease });
  lock.querySelector(".lk-ring").animate([
    { transform: "scale(1)", opacity: 0.55 },
    { transform: "scale(1.75)", opacity: 0 },
  ], { duration: 900, delay: 1160, easing: "cubic-bezier(0.2, 0.7, 0.3, 1)", fill: "forwards" });
  for (const hole of lock.querySelectorAll(".lk-hole")) {
    hole.animate([{ fill: "#1D1D1F" }, { fill: "#E7C694" }], { duration: 420, delay: 1180, easing: ease, fill: "both" });
  }
}

export function mountLock(root) {
  const locks = [...root.querySelectorAll("[data-lock]")];
  if (!locks.length) return () => {};
  if (reducedMotion() || !("IntersectionObserver" in window) || !Element.prototype.animate) {
    locks.forEach((lock) => lock.classList.add("is-closed"));
    return () => {};
  }
  locks.forEach((lock) => lock.classList.add("is-armed"));
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      io.unobserve(entry.target);
      entry.target.classList.replace("is-armed", "is-closed");
      play(entry.target);
    }
  }, { threshold: 0.7 });
  locks.forEach((lock) => io.observe(lock));
  return () => io.disconnect();
}
