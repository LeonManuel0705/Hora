import { escapeHtml } from "../lib/i18n.js";

export const CHEVRON = '<svg class="ap-chev" viewBox="0 0 8 14" aria-hidden="true" focusable="false"><path d="M1.5 1.5 6.5 7l-5 5.5"/></svg>';

export function pageHeroHTML({ eyebrow, title, lede, top = "", extra = "" }) {
  return `<header class="ap-page-hero">
    ${top}
    <p class="ap-eyebrow ap-reveal">${escapeHtml(eyebrow)}</p>
    <h1 class="ap-page-title ap-reveal">${escapeHtml(title)}</h1>
    ${lede ? `<p class="ap-page-lede ap-reveal">${escapeHtml(lede)}</p>` : ""}
    ${extra}
  </header>`;
}

export function zoomHTML(screen, [x, y, w, h], alt, { max = w * 1.2 } = {}) {
  return `<figure class="ap-zoom ap-reveal" style="--rx: ${x}; --ry: ${y}; --rw: ${w}; --rh: ${h}; --ar: ${w} / ${h}; --max: ${Math.round(max)}px">
    <div class="ap-zoom-frame"><img src="/screens/${screen}.webp" width="2880" height="1800" alt="${escapeHtml(alt)}" loading="lazy" decoding="async"></div>
  </figure>`;
}
