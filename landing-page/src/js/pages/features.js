import { escapeHtml, raw, t } from "../lib/i18n.js";
import { brand, icon } from "../lib/icons.js";
import { revealOnce } from "../lib/scroll.js";
import { tinte } from "../lib/tinte.js";
import { macHTML } from "../components/device.js";
import { CHEVRON, pageHeroHTML, zoomHTML } from "../components/page.js";

const HUES = { sand: "#E7C694", salbei: "#A3B690", slate: "#6295D4", iris: "#B7A6F6", plum: "#AC7DC0", lake: "#4FBADE" };

const SHOTS = {
  stundenplan: ["plan", [336, 84, 620, 501], 700],
  noten: ["noten", [980, 28, 372, 456], 420],
  aufgaben: ["aufgaben", [316, 14, 660, 600], 700],
  iserv: ["plan", [976, 64, 380, 382], 440],
  fahrplan: ["bus", [976, 64, 380, 560], 420],
  kalender: ["kalender", [316, 220, 660, 540], 700],
};

function feature(area, i) {
  const [screen, region, max] = SHOTS[area.id] || SHOTS.stundenplan;
  const facts = (area.facts || []).map((fact) => `<li>${escapeHtml(fact)}</li>`).join("");
  return `<article class="ap-feature${i % 2 ? " is-flipped" : ""}" style="--hue: ${HUES[area.hue] || HUES.sand}" aria-labelledby="feature-${area.id}">
    <div class="ap-feature-copy">
      <p class="ap-feature-eyebrow ap-reveal">${escapeHtml(area.title)}</p>
      <h2 class="ap-feature-title ap-reveal" id="feature-${area.id}">${escapeHtml(t(`features_page.heads.${area.id}`))}</h2>
      <p class="ap-feature-text ap-reveal">${escapeHtml(area.text)}</p>
      <ul class="ap-facts ap-reveal">${facts}</ul>
      <p class="ap-devices ap-reveal">${escapeHtml(t(`home_features.devices_${area.devices}`))}</p>
    </div>
    ${area.id === "tinte" ? `<div class="ap-feature-tinte ap-reveal">${tinte("ruhe", 280, t("start.tile_tinte_label"))}</div>` : zoomHTML(screen, region, t(`features_page.shots.${area.id}`), { max })}
  </article>`;
}

function state(value) {
  const label = t(`features_page.${value === "yes" ? "yes" : value === "partial" ? "partial" : "no"}`);
  if (value === "yes") return `<span class="ap-state is-yes">${icon("check", { size: 20, stroke: 2.6 })}<span class="sr-only">${escapeHtml(label)}</span></span>`;
  if (value === "partial") return `<span class="ap-state is-partial">${escapeHtml(label)}</span>`;
  return `<span class="ap-state is-no" aria-label="${escapeHtml(label)}">–</span>`;
}

function matrix() {
  const groups = raw("features_page.groups") || [];
  const head = `<thead><tr>
    <th scope="col"><span class="sr-only">${escapeHtml(t("features_page.col_feature"))}</span></th>
    <th scope="col"><span class="ap-col">${icon("monitor", { size: 28, stroke: 1.6 })}<span>${escapeHtml(t("features_page.col_desk"))}</span></span></th>
    <th scope="col"><span class="ap-col">${brand("android", { size: 28 })}<span>${escapeHtml(t("features_page.col_android"))}</span></span></th>
    <th scope="col"><span class="ap-col">${brand("apple", { size: 28 })}<span>${escapeHtml(t("features_page.col_ios"))}</span></span></th>
  </tr></thead>`;
  const body = groups.map((group) => `<tbody>
    <tr class="ap-table-group"><th colspan="4" scope="colgroup">${escapeHtml(group.title)}</th></tr>
    ${group.rows.map((row) => `<tr>
      <th scope="row"><span class="ap-table-name">${escapeHtml(row.name)}</span>${row.note ? `<span class="ap-table-note">${escapeHtml(row.note)}</span>` : ""}</th>
      <td>${state(row.d)}</td><td>${state(row.a)}</td><td>${state(row.i)}</td>
    </tr>`).join("")}
  </tbody>`).join("");
  return `<table class="ap-table ap-reveal"><caption class="sr-only">${escapeHtml(t("features_page.matrix_title"))}</caption>${head}${body}</table>`;
}

export default {
  title: () => t("meta.features"),
  render: () => {
    const areas = raw("home_features.areas") || [];
    const items = raw("features_page.new_items") || [];
    return `<div class="ap ap-sub-page">
      ${pageHeroHTML({ eyebrow: t("features_page.eyebrow"), title: t("features_page.hero_title"), lede: t("features_page.hero_lede") })}
      <div class="ap-page-device ap-reveal">${macHTML([{ id: "plan", alt: t("features_page.hero_alt") }], { eager: true })}</div>
      <section class="ap-features" aria-label="${escapeHtml(t("features_page.eyebrow"))}">${areas.map(feature).join("")}</section>
      <section class="ap-matrix" aria-labelledby="matrix-title">
        <h2 class="ap-h2 ap-reveal" id="matrix-title">${escapeHtml(t("features_page.matrix_title"))}</h2>
        ${matrix()}
        <p class="ap-note ap-reveal">${escapeHtml(t("features_page.ios_note"))}</p>
      </section>
      <section class="ap-news" aria-labelledby="news-title">
        <h2 class="ap-h2 ap-reveal" id="news-title">${escapeHtml(t("features_page.new_title"))}</h2>
        <p class="ap-sub ap-reveal">${escapeHtml(t("features_page.new_lede"))}</p>
        <ul class="ap-cards">${items.map((item) => `<li class="ap-card ap-reveal"><h3>${escapeHtml(item.title)}</h3><p>${escapeHtml(item.text)}</p></li>`).join("")}</ul>
      </section>
      <section class="ap-cta" aria-labelledby="cta-title">
        <h2 class="ap-cta-title ap-reveal" id="cta-title">${escapeHtml(t("features_page.cta_title"))}</h2>
        <p class="ap-sub ap-reveal">${escapeHtml(t("features_page.cta_text"))}</p>
        <div class="ap-cta-row ap-reveal"><a class="ap-btn" href="/download">${escapeHtml(t("download_page.get"))}</a><a class="ap-link" href="/privacy-philosophy">${escapeHtml(t("start.privacy_link"))}${CHEVRON}</a></div>
      </section>
    </div>`;
  },
  mount: (root) => revealOnce(root, ".ap-reveal"),
};
