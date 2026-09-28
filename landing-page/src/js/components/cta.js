import { escapeHtml, getLang, t } from "../lib/i18n.js";
import { detectPlatform, megabytes, ORDER, PLATFORMS } from "../lib/platform.js";

export const SHORT = { macos: "Mac", windows: "Windows", linux: "Linux", android: "Android", ios: "iPhone", web: "Browser" };

export function listJoin(items) {
  if (items.length < 2) return items.join("");
  return `${items.slice(0, -1).join(", ")} ${getLang() === "de" ? "und" : "and"} ${items.at(-1)}`;
}

export function cta() {
  const id = detectPlatform();
  const p = PLATFORMS[id];
  if (!p) return { button: `<a class="ap-btn" href="/download">${escapeHtml(t("start.cta_generic"))}</a>`, note: t("start.cta_note_generic") };
  if (p.kind === "pwa") return { button: `<a class="ap-btn" href="${p.href}">${escapeHtml(t("start.cta_web"))}</a>`, note: t("start.cta_note_web") };
  const others = ORDER.filter((other) => other !== id && other !== "web").map((other) => SHORT[other]);
  const note = t("start.cta_note", { platform: SHORT[id], size: megabytes(p.bytes), others: listJoin(others) });
  return { button: `<a class="ap-btn" href="${p.href}" download data-download="${id}">${escapeHtml(t("start.cta"))}</a>`, note };
}
