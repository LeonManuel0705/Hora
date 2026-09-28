import { contactMail, t, raw, escapeHtml } from "../lib/i18n.js";
import { icon } from "../lib/icons.js";
import { reveals } from "../lib/motion.js";

const mailLink = `<a class="prose-link" href="mailto:${contactMail}">${contactMail}</a>`;

function sections(ns) {
  const data = raw(ns) || {};
  const groups = new Map();
  for (const [key, value] of Object.entries(data)) {
    const m = key.match(/^(s\d+)_(.+)$/);
    if (!m) continue;
    if (!groups.has(m[1])) groups.set(m[1], []);
    groups.get(m[1]).push([m[2], value]);
  }
  return groups;
}

function renderSection(ns, id, entries) {
  let html = "";
  let list = [];
  const flush = () => {
    if (list.length) html += `<ul>${list.map((li) => `<li>${escapeHtml(li)}</li>`).join("")}</ul>`;
    list = [];
  };
  const title = entries.find(([k]) => k === "title")?.[1] || "";
  for (let i = 0; i < entries.length; i++) {
    const [key, value] = entries[i];
    if (key === "title") continue;
    if (/^list\d+$/.test(key)) {
      list.push(value);
      continue;
    }
    flush();
    if (/^sub\d+_title$/.test(key)) html += `<h3>${escapeHtml(value)}</h3>`;
    else if (key === "name") html += `<p class="legal-name"><strong>${escapeHtml(value)}</strong></p>`;
    else if (key === "email_label") html += `<p>${escapeHtml(value)} ${mailLink}</p>`;
    else if (key === "link") continue;
    else if (/^p\d+$/.test(key) || /^sub\d+_p\d+$/.test(key)) {
      const link = entries.find(([k]) => k === "link");
      if (link && key === "p1" && ns === "terms" && id === "s6") {
        html += `<p>${escapeHtml(value)} <a class="prose-link" href="/datenschutz">${escapeHtml(link[1])}</a>.</p>`;
      } else {
        html += `<p>${escapeHtml(value)}</p>`;
      }
      if (ns === "terms" && id === "s8" && key === "p1") html += `<p>${mailLink}</p>`;
      if (ns === "privacy_policy" && id === "s7" && key === "p1") html += `<p class="legal-name"><strong>${escapeHtml(t("privacy_policy.s1_name"))}</strong></p><p>${mailLink}</p>`;
    }
  }
  flush();
  return `<section class="legal-section" id="${id}" aria-labelledby="${id}-title"><h2 id="${id}-title">${escapeHtml(title)}</h2>${html}</section>`;
}

function page(ns, other) {
  const groups = sections(ns);
  const toc = [...groups.entries()].map(([id, entries]) => `<li><a href="#${id}">${escapeHtml(entries.find(([k]) => k === "title")?.[1] || id)}</a></li>`).join("");
  const body = [...groups.entries()].map(([id, entries]) => renderSection(ns, id, entries)).join("");
  return `<article class="legal wrap">
    <header class="legal-head" data-reveal>
      <h1>${escapeHtml(t(`${ns}.hero_title`))}</h1>
      <p class="legal-date mono">${escapeHtml(t(`${ns}.hero_date`))}</p>
    </header>
    <div class="legal-grid">
      <nav class="legal-toc" aria-label="${escapeHtml(t("legal.toc"))}" data-reveal style="--i:1">
        <p class="legal-toc-title">${escapeHtml(t("legal.toc"))}</p>
        <ol>${toc}</ol>
        <a class="legal-other" href="${other.href}">${icon("arrow-right", { size: 15 })}<span>${escapeHtml(t(other.key))}</span></a>
      </nav>
      <div class="legal-body" data-reveal="fade" style="--i:1">${body}</div>
    </div>
  </article>`;
}

export const terms = {
  theme: "light",
  title: () => t("meta.terms"),
  render: () => page("terms", { href: "/datenschutz", key: "legal.other_privacy" }),
  mount: (root) => reveals(root),
};

export const privacyPolicy = {
  theme: "light",
  title: () => t("meta.privacy_policy"),
  render: () => page("privacy_policy", { href: "/nutzungsbedingungen", key: "legal.other_terms" }),
  mount: (root) => reveals(root),
};
