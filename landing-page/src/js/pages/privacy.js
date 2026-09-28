import { brandRepository, escapeHtml, raw, t } from "../lib/i18n.js";
import { brand, icon } from "../lib/icons.js";
import { revealOnce } from "../lib/scroll.js";
import { lockHTML, mountLock } from "../components/lock.js";
import { CHEVRON, pageHeroHTML } from "../components/page.js";

function flowRow(row) {
  const tone = row.tone === "cancel" ? "is-off" : row.tone === "warn" ? "is-warn" : "";
  return `<li class="ap-flow ${tone} ap-reveal">
    <span class="ap-flow-icon">${icon(row.icon, { size: 22, stroke: 1.8 })}</span>
    <span class="ap-flow-to">${escapeHtml(row.to)}</span>
    <span class="ap-flow-what">${escapeHtml(row.what)}</span>
    <span class="ap-flow-when">${escapeHtml(row.when)}</span>
  </li>`;
}

export default {
  title: () => t("meta.privacy"),
  render: () => {
    const where = raw("privacy_page.where") || [];
    const flow = raw("privacy_page.flow") || [];
    const no = raw("privacy_page.no") || [];
    return `<div class="ap ap-sub-page">
      ${pageHeroHTML({ eyebrow: t("privacy_page.eyebrow"), title: t("privacy_page.title"), lede: t("privacy_page.lede"), top: lockHTML(t("privacy_page.lock_label"), "ap-lock") })}
      <section class="ap-sec" aria-labelledby="where-title">
        <h2 class="ap-h2 ap-reveal" id="where-title">${escapeHtml(t("privacy_page.where_title"))}</h2>
        <ul class="ap-cards">${where.map((item) => `<li class="ap-card ap-reveal"><span class="ap-card-icon">${icon(item.icon, { size: 30, stroke: 1.6 })}</span><h3>${escapeHtml(item.title)}</h3><p>${escapeHtml(item.text)}</p></li>`).join("")}</ul>
      </section>
      <section class="ap-sec" aria-labelledby="flow-title">
        <h2 class="ap-h2 ap-reveal" id="flow-title">${escapeHtml(t("privacy_page.flow_title"))}</h2>
        <p class="ap-sub ap-reveal">${escapeHtml(t("privacy_page.flow_lede"))}</p>
        <ul class="ap-flows">${flow.map(flowRow).join("")}</ul>
      </section>
      <section class="ap-sec ap-big-number" aria-labelledby="lock-title">
        <h2 class="ap-h2 ap-reveal" id="lock-title">${escapeHtml(t("privacy_page.lock_title"))}</h2>
        <p class="ap-sub ap-reveal">${escapeHtml(t("privacy_page.lock_text"))}</p>
        <div class="ap-stat ap-reveal">
          <p class="ap-number">${escapeHtml(t("privacy_page.lock_number"))}</p>
          <p class="ap-number-label">${escapeHtml(t("privacy_page.lock_number_label"))}</p>
        </div>
      </section>
      <section class="ap-sec" aria-labelledby="no-title">
        <h2 class="ap-h2 ap-reveal" id="no-title">${escapeHtml(t("privacy_page.no_title"))}</h2>
        <ul class="ap-nolist ap-reveal">${no.map((item) => `<li>${icon("ban", { size: 22, stroke: 1.8 })}<span>${escapeHtml(item)}</span></li>`).join("")}</ul>
      </section>
      <section class="ap-cta" aria-labelledby="open-title">
        <h2 class="ap-cta-title ap-reveal" id="open-title">${escapeHtml(t("privacy_page.open_title"))}</h2>
        <p class="ap-sub ap-reveal">${escapeHtml(t("privacy_page.open_text"))}</p>
        <div class="ap-cta-row ap-reveal"><a class="ap-btn" href="${brandRepository}" target="_blank" rel="noopener">${brand("github", { size: 18 })}<span>${escapeHtml(t("privacy_page.open_link"))}</span></a><a class="ap-link" href="/datenschutz">${escapeHtml(t("privacy_page.legal_link"))}${CHEVRON}</a></div>
      </section>
    </div>`;
  },
  mount(root) {
    const cleanups = [revealOnce(root, ".ap-reveal"), mountLock(root)];
    return () => cleanups.forEach((fn) => fn && fn());
  },
};
