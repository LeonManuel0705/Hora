import { escapeHtml } from "../lib/i18n.js";

export function macHTML(screens, { eager = false } = {}) {
  const shots = screens.map((screen, i) => `<img class="mac-shot${i === 0 ? " is-on" : ""}" data-screen="${screen.id}" src="/screens/${screen.id}.webp" width="2880" height="1800" alt="${escapeHtml(screen.alt)}"${i === 0 ? "" : ' aria-hidden="true"'} decoding="async"${eager && i === 0 ? ' fetchpriority="high"' : ' loading="lazy"'}>`).join("");
  return `<figure class="mac">
    <div class="mac-lid">
      <span class="mac-cam" aria-hidden="true"></span>
      <div class="mac-screen">${shots}</div>
    </div>
    <div class="mac-base" aria-hidden="true"><span class="mac-groove"></span></div>
  </figure>`;
}

export function iphoneHTML(src, alt, { dark = false } = {}) {
  return `<figure class="iphone${dark ? " is-dark" : ""}">
    <div class="iphone-body">
      <div class="iphone-screen"><img src="${src}" width="1170" height="2532" alt="${escapeHtml(alt)}" loading="lazy" decoding="async"><img class="iphone-tabbar" src="${src}" width="1170" height="2532" alt="" loading="lazy" decoding="async"></div>
      <span class="iphone-island" aria-hidden="true"></span>
    </div>
  </figure>`;
}

export function showScreen(root, id) {
  let found = false;
  for (const shot of root.querySelectorAll(".mac-shot")) {
    const on = shot.dataset.screen === id;
    found ||= on;
    shot.classList.toggle("is-on", on);
    if (on) shot.removeAttribute("aria-hidden");
    else shot.setAttribute("aria-hidden", "true");
  }
  return found;
}
