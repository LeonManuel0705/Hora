import { t, raw, escapeHtml } from "../lib/i18n.js";
import { brand, icon, tux } from "../lib/icons.js";
import { reducedMotion } from "../lib/motion.js";
import { megabytes, PLATFORMS } from "../lib/platform.js";
import { tinte } from "../lib/tinte.js";

export function platformMark(id, size = 20) {
  const p = PLATFORMS[id];
  if (!p) return "";
  if (p.mark === "linux") return tux({ size });
  if (p.mark === "globe") return icon("globe", { size });
  return brand(p.mark, { size });
}

let toastEl = null;
let toastTimer = 0;

function closeToast() {
  if (!toastEl) return;
  const el = toastEl;
  toastEl = null;
  clearTimeout(toastTimer);
  el.classList.remove("is-open");
  setTimeout(() => el.remove(), reducedMotion() ? 0 : 320);
}

function openToast(id) {
  closeToast();
  const p = PLATFORMS[id];
  const list = raw(`steps.${id}`);
  const el = document.createElement("div");
  el.className = "dl-toast";
  el.setAttribute("role", "status");
  el.innerHTML = `<div class="dl-toast-tinte">${tinte("geschafft", 104)}</div>
    <div class="dl-toast-body">
      <p class="dl-toast-title">${escapeHtml(t("home_download.done_title"))}</p>
      <p class="dl-toast-file mono">${escapeHtml(p.file)}, ${megabytes(p.bytes)} MB</p>
      ${Array.isArray(list) ? `<ol>${list.map((s) => `<li>${escapeHtml(s)}</li>`).join("")}</ol>` : ""}
    </div>
    <button type="button" class="dl-toast-close" aria-label="${escapeHtml(t("home_download.done_close"))}">${icon("x", { size: 18 })}</button>`;
  document.body.append(el);
  toastEl = el;
  requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add("is-open")));
  el.querySelector(".dl-toast-close").addEventListener("click", closeToast);
  toastTimer = setTimeout(() => {
    const slot = el.querySelector(".dl-toast-tinte");
    if (slot && el.isConnected) slot.innerHTML = tinte("ruhe", 104, t("home_download.tinte_label"));
  }, 4200);
}

export function mountDownloads(root) {
  const onClick = (event) => {
    const copy = event.target.closest("[data-copy]");
    if (copy) {
      navigator.clipboard?.writeText(copy.dataset.copy).then(() => {
        const label = copy.querySelector("span");
        label.textContent = t("steps.copied");
        copy.classList.add("is-done");
        setTimeout(() => {
          label.textContent = t("steps.copy");
          copy.classList.remove("is-done");
        }, 1800);
      }).catch(() => {});
      return;
    }
    const link = event.target.closest("[data-download]");
    if (!link) return;
    openToast(link.dataset.download);
  };
  const onKey = (event) => {
    if (event.key === "Escape") closeToast();
  };
  root.addEventListener("click", onClick);
  document.addEventListener("keydown", onKey);
  return () => {
    root.removeEventListener("click", onClick);
    document.removeEventListener("keydown", onKey);
    closeToast();
  };
}
