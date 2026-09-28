const data = JSON.parse(document.getElementById("content").textContent);
const dict = { de: data.i18n_de || {}, en: data.i18n_en || {} };
const listeners = new Set();

export const brandName = data.company?.name || "";
export const brandRepository = data.company?.repository || "";
export const brandWebsite = data.company?.website || "";
export const brandHost = data.company?.websiteHost || "";
export const contactMail = data.company?.email || "";

function stored() {
  try {
    const value = localStorage.getItem("lang");
    return value === "de" || value === "en" ? value : null;
  } catch {
    return null;
  }
}

let lang = stored() || "de";
document.documentElement.lang = lang;

function lookup(source, key) {
  let value = source;
  for (const part of key.split(".")) value = value?.[part];
  return value;
}

export function getLang() {
  return lang;
}

export function raw(key) {
  const value = lookup(dict[lang], key);
  return value !== undefined ? value : lookup(dict.de, key);
}

export function t(key, vars) {
  let value = raw(key);
  if (typeof value !== "string") return value === undefined ? key : value;
  if (vars) value = value.replace(/\{(\w+)\}/g, (match, name) => (vars[name] !== undefined ? vars[name] : match));
  return value;
}

export const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

export function rich(key, vars) {
  return escapeHtml(t(key, vars)).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
}

export function setLang(next) {
  if (next === lang || !dict[next]) return;
  lang = next;
  document.documentElement.lang = next;
  try {
    localStorage.setItem("lang", next);
  } catch {}
  listeners.forEach((fn) => fn(next));
}

export function onLang(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function applyStatic(root = document) {
  root.querySelectorAll("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  root.querySelectorAll("[data-i18n-aria]").forEach((el) => {
    el.setAttribute("aria-label", t(el.dataset.i18nAria));
  });
}

export function numberFormat(value, options) {
  return new Intl.NumberFormat(lang === "de" ? "de-DE" : "en-GB", options).format(value);
}
