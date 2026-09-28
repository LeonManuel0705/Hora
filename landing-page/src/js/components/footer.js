import { brandName, brandRepository, contactMail, escapeHtml, t } from "../lib/i18n.js";

export function footerHTML() {
  const link = (href, key) => `<li><a href="${href}">${escapeHtml(t(key))}</a></li>`;
  return `<div class="footer-sign wrap">
    <a class="brand brand-footer" href="/" aria-label="${escapeHtml(brandName)}">
      <svg class="brand-mark" viewBox="14 18 72 66" aria-hidden="true" focusable="false">
        <circle class="bm-sun" cx="40" cy="44" r="26" />
        <rect class="bm-tile" x="44" y="42" width="42" height="42" rx="12" />
        <path class="bm-overlap" d="M44 69.69V54A12 12 0 0 1 56 42H65.92A26 26 0 0 1 44 69.69Z" />
      </svg>
      <span class="brand-word">${escapeHtml(brandName)}</span>
    </a>
    <p class="footer-sign-line">${escapeHtml(t("footer.sign"))} <span data-version="full">${escapeHtml(t("footer.version"))}</span></p>
    <nav class="footer-sign-nav" aria-label="${escapeHtml(t("footer.nav_label"))}">
      <ul>
        ${link("/features", "nav.features")}
        ${link("/privacy-philosophy", "nav.privacy")}
        ${link("/download", "nav.download_long")}
        ${link("/about", "nav.about")}
        <li><a href="${brandRepository}" rel="noopener" target="_blank">${escapeHtml(t("footer.source"))}</a></li>
        <li><a href="mailto:${contactMail}">${escapeHtml(t("footer.contact"))}</a></li>
        ${link("/nutzungsbedingungen", "footer.terms")}
        ${link("/datenschutz", "footer.privacy_policy")}
      </ul>
      <button class="lang-toggle lang-toggle-wide" type="button" data-lang-toggle>${escapeHtml(t(`lang.name_${t("lang.other")}`))}</button>
    </nav>
  </div>`;
}
