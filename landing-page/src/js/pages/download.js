import { brandHost, escapeHtml, raw, t } from "../lib/i18n.js";
import { icon } from "../lib/icons.js";
import { detectPlatform, megabytes, ORDER, PLATFORMS } from "../lib/platform.js";
import { revealOnce } from "../lib/scroll.js";
import { cta } from "../components/cta.js";
import { mountDownloads, platformMark } from "../components/downloads.js";
import { pageHeroHTML } from "../components/page.js";

function tile(id, mine) {
  const p = PLATFORMS[id];
  const pwa = p.kind === "pwa";
  const yours = id === mine;
  const steps = raw(`steps.${id}`) || [];
  const command = `curl -sL https://${brandHost}/install-macos.sh | bash`;
  const action = pwa
    ? `<a class="ap-btn${yours ? "" : " ap-btn-ghost"}" href="${p.href}">${escapeHtml(t("download_page.open"))}</a>`
    : `<a class="ap-btn${yours ? "" : " ap-btn-ghost"}" href="${p.href}" download data-download="${id}">${escapeHtml(t("download_page.get"))}</a>`;
  return `<article class="ap-dl${yours ? " is-yours" : ""} ap-reveal" id="${id}" aria-labelledby="dl-${id}">
    <div class="ap-dl-top">
      <span class="ap-dl-mark">${platformMark(id, 34)}</span>
      ${yours ? `<span class="ap-dl-badge">${escapeHtml(t("download_page.yours"))}</span>` : ""}
    </div>
    <h2 class="ap-dl-name" id="dl-${id}">${escapeHtml(t(`platforms.${id}.name`))}</h2>
    <p class="ap-dl-note">${escapeHtml(t(`platforms.${id}.note`))}</p>
    <p class="ap-dl-meta">${pwa ? escapeHtml(t("start.cta_web")) : `${escapeHtml(p.file)}, ${megabytes(p.bytes)} MB`}</p>
    <div class="ap-dl-action">${action}</div>
    ${p.alt ? `<p class="ap-dl-meta">${escapeHtml(t(`platforms.${id}.alt`))} <a href="${p.alt.href}" download>${escapeHtml(p.alt.file)}, ${megabytes(p.alt.bytes)}&nbsp;MB</a></p>` : ""}
    <ol class="ap-dl-steps">${steps.map((step) => `<li>${escapeHtml(step)}</li>`).join("")}</ol>
    ${id === "macos" ? `<div class="ap-cmd"><p>${escapeHtml(t("steps.macos_terminal"))}</p><div class="ap-cmd-row"><code>${escapeHtml(command)}</code><button type="button" class="ap-copy" data-copy="${escapeHtml(command)}">${icon("copy", { size: 15 })}<span>${escapeHtml(t("steps.copy"))}</span></button></div></div>` : ""}
  </article>`;
}

export default {
  title: () => t("meta.download"),
  render: () => {
    const mine = detectPlatform();
    const ids = [...ORDER];
    if (mine) ids.sort((a, b) => (a === mine ? -1 : b === mine ? 1 : 0));
    const faq = raw("download_page.faq") || [];
    const { button, note } = cta();
    const extra = `<div class="ap-hero-cta ap-reveal">${button}</div>
      <p class="ap-hero-note ap-reveal">${escapeHtml(note)}</p>
      <p class="ap-page-note ap-reveal">${escapeHtml(t("download_page.name_note"))}</p>`;
    return `<div class="ap ap-sub-page">
      ${pageHeroHTML({ eyebrow: t("download_page.eyebrow"), title: t("download_page.hero_title"), lede: t("download_page.lede"), extra })}
      <section class="ap-sec ap-dls" aria-label="${escapeHtml(t("download_page.eyebrow"))}">${ids.map((id) => tile(id, mine)).join("")}</section>
      <section class="ap-sec ap-faqs" aria-labelledby="faq-title">
        <h2 class="ap-h2 ap-reveal" id="faq-title">${escapeHtml(t("download_page.faq_title"))}</h2>
        <div class="ap-faq-list ap-reveal">${faq.map((item) => `<details class="ap-faq"><summary><span>${escapeHtml(item.q)}</span><i class="ap-faq-plus" aria-hidden="true"></i></summary><p>${escapeHtml(item.a)}</p></details>`).join("")}</div>
      </section>
    </div>`;
  },
  mount(root) {
    const cleanups = [revealOnce(root, ".ap-reveal"), mountDownloads(root)];
    return () => cleanups.forEach((fn) => fn && fn());
  },
};
