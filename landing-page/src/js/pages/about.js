import { brandName, brandRepository, contactMail, escapeHtml, raw, t } from "../lib/i18n.js";
import { revealOnce } from "../lib/scroll.js";
import { macHTML } from "../components/device.js";
import { CHEVRON, pageHeroHTML } from "../components/page.js";

export default {
  title: () => t("meta.about"),
  render: () => {
    const story = raw("about_page.story") || [];
    const open = raw("about_page.open") || [];
    return `<div class="ap ap-sub-page">
      ${pageHeroHTML({ eyebrow: t("about_page.eyebrow"), title: t("about_page.title"), lede: t("about_page.lede") })}
      <div class="ap-page-device ap-reveal">${macHTML([{ id: "heute", alt: t("about_page.shot_alt") }], { eager: true })}</div>
      <section class="ap-sec ap-story" aria-labelledby="story-title">
        <h2 class="ap-h2 ap-reveal" id="story-title">${escapeHtml(t("about_page.story_title"))}</h2>
        <div class="ap-story-text">${story.map((paragraph) => `<p class="ap-reveal">${escapeHtml(paragraph)}</p>`).join("")}</div>
      </section>
      <section class="ap-sec" aria-labelledby="open-title">
        <h2 class="ap-h2 ap-reveal" id="open-title">${escapeHtml(t("about_page.open_title"))}</h2>
        <ul class="ap-cards">${open.map((item) => `<li class="ap-card ap-reveal"><h3>${escapeHtml(item.title)}</h3><p>${escapeHtml(item.text)}</p></li>`).join("")}</ul>
      </section>
      <section class="ap-cta" aria-labelledby="contact-title">
        <h2 class="ap-cta-title ap-reveal" id="contact-title">${escapeHtml(t("about_page.contact_title"))}</h2>
        <p class="ap-sub ap-reveal">${escapeHtml(t("about_page.contact_text"))}</p>
        <div class="ap-cta-row ap-reveal"><a class="ap-btn" href="mailto:${contactMail}?subject=${encodeURIComponent(brandName)}">${escapeHtml(t("about_page.contact_button"))}</a><a class="ap-link" href="${brandRepository}" target="_blank" rel="noopener">${escapeHtml(t("about_page.code_button"))}${CHEVRON}</a></div>
      </section>
    </div>`;
  },
  mount: (root) => revealOnce(root, ".ap-reveal"),
};
