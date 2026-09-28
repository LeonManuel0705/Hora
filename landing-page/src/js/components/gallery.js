import { escapeHtml, t } from "../lib/i18n.js";
import { reducedMotion } from "../lib/motion.js";

const ARROW = '<svg viewBox="0 0 12 20" aria-hidden="true" focusable="false"><path d="M8.5 3.5 2 10l6.5 6.5"/></svg>';

export function galleryHTML({ id, label, cards }) {
  const items = cards.map((card, i) => `<li class="hl-card hl-${card.id}" data-card="${i}">
      <p class="hl-caption"><strong>${escapeHtml(card.lead)}</strong> ${escapeHtml(card.text)}</p>
      <div class="hl-visual">${card.visual}</div>
    </li>`).join("");
  const dots = cards.map((card, i) => `<button type="button" class="hl-dot" data-go="${i}" aria-label="${escapeHtml(t("start.high_dot", { n: i + 1, total: cards.length }))}"${i === 0 ? ' aria-current="true"' : ""}><span></span></button>`).join("");
  return `<div class="hl" data-gallery="${id}">
    <ul class="hl-track" data-track tabindex="0" aria-label="${escapeHtml(label)}">${items}</ul>
    <div class="hl-controls">
      <div class="hl-dots" style="--i: 0"><span class="hl-pill" aria-hidden="true"></span>${dots}</div>
      <div class="hl-arrows">
        <button type="button" class="hl-arrow" data-step="-1" aria-label="${escapeHtml(t("start.high_prev"))}" disabled>${ARROW}</button>
        <button type="button" class="hl-arrow hl-arrow-next" data-step="1" aria-label="${escapeHtml(t("start.high_next"))}">${ARROW}</button>
      </div>
    </div>
  </div>`;
}

export function mountGallery(root) {
  const gallery = root.querySelector("[data-gallery]");
  if (!gallery) return () => {};
  const track = gallery.querySelector("[data-track]");
  const cards = [...track.querySelectorAll(".hl-card")];
  const dots = [...gallery.querySelectorAll(".hl-dot")];
  const rail = gallery.querySelector(".hl-dots");
  const [prev, next] = gallery.querySelectorAll(".hl-arrow");
  let index = 0;
  let frame = 0;
  const offset = (card) => card.offsetLeft - cards[0].offsetLeft;
  const go = (target) => {
    const i = Math.max(0, Math.min(cards.length - 1, target));
    track.scrollTo({ left: offset(cards[i]), behavior: reducedMotion() ? "auto" : "smooth" });
  };
  const sync = () => {
    frame = 0;
    const max = track.scrollWidth - track.clientWidth;
    let nearest = 0;
    let best = Infinity;
    cards.forEach((card, i) => {
      const distance = Math.abs(offset(card) - track.scrollLeft);
      if (distance < best) {
        best = distance;
        nearest = i;
      }
    });
    if (track.scrollLeft >= max - 4) nearest = cards.length - 1;
    if (nearest !== index) {
      index = nearest;
      dots.forEach((dot, i) => (i === index ? dot.setAttribute("aria-current", "true") : dot.removeAttribute("aria-current")));
      rail.style.setProperty("--i", index);
    }
    prev.disabled = track.scrollLeft <= 4;
    next.disabled = track.scrollLeft >= max - 4;
  };
  const onScroll = () => {
    frame ||= requestAnimationFrame(sync);
  };
  const onClick = (event) => {
    const dot = event.target.closest("[data-go]");
    if (dot) return go(Number(dot.dataset.go));
    const arrow = event.target.closest("[data-step]");
    if (arrow) go(index + Number(arrow.dataset.step));
  };
  track.addEventListener("scroll", onScroll, { passive: true });
  gallery.addEventListener("click", onClick);
  sync();
  return () => {
    cancelAnimationFrame(frame);
    track.removeEventListener("scroll", onScroll);
    gallery.removeEventListener("click", onClick);
  };
}
