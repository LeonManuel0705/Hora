import { applyStatic, brandName, getLang, onLang, setLang, t } from "./lib/i18n.js";
import { reducedMotion } from "./lib/motion.js";
import { footerHTML } from "./components/footer.js";
import { fillVersion } from "./lib/version.js";
import home from "./pages/home.js";
import features from "./pages/features.js";
import privacy from "./pages/privacy.js";
import download from "./pages/download.js";
import about from "./pages/about.js";
import { terms, privacyPolicy } from "./pages/legal.js";

const routes = {
  "/": home,
  "/features": features,
  "/privacy-philosophy": privacy,
  "/download": download,
  "/about": about,
  "/nutzungsbedingungen": terms,
  "/datenschutz": privacyPolicy,
};

const app = document.getElementById("app");
const header = document.getElementById("site-header");
const footer = document.getElementById("site-footer");
const menu = document.getElementById("mobile-menu");
const menuButton = document.querySelector("[data-menu-open]");
let cleanup = () => {};
let currentPath = null;

const normalize = (path) => {
  const clean = path.replace(/\/index\.html$/, "/").replace(/\/+$/, "") || "/";
  return routes[clean] ? clean : "/";
};

function markNav(path) {
  document.querySelectorAll("[data-nav]").forEach((link) => {
    const on = link.getAttribute("href") === path;
    if (on) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  });
}

function syncLangButtons() {
  const other = getLang() === "de" ? "en" : "de";
  document.querySelectorAll("[data-lang-toggle]").forEach((button) => {
    const wide = button.classList.contains("lang-toggle-wide");
    button.textContent = wide ? t(`lang.name_${other}`) : other.toUpperCase();
    button.setAttribute("aria-label", t("lang.switch"));
    button.setAttribute("lang", other);
  });
}

function renderPage(path, { hash = "", focus = false } = {}) {
  const page = routes[path];
  cleanup();
  document.body.dataset.route = path === "/" ? "home" : path.slice(1);
  document.body.dataset.theme = page.theme || "dark";
  app.innerHTML = page.render();
  footer.innerHTML = footerHTML();
  fillVersion(footer);
  document.title = page.title ? page.title() : brandName;
  markNav(path);
  cleanup = page.mount ? page.mount(app) || (() => {}) : () => {};
  currentPath = path;
  if (hash) {
    const target = document.getElementById(decodeURIComponent(hash.slice(1)));
    if (target) {
      requestAnimationFrame(() => target.scrollIntoView({ block: "center" }));
      target.classList.add("is-target");
    } else scrollTo(0, 0);
  } else scrollTo(0, 0);
  if (focus) app.focus({ preventScroll: true });
}

function navigate(url, { push = true } = {}) {
  const next = new URL(url, location.href);
  const path = normalize(next.pathname);
  if (push) history.pushState({}, "", path + next.hash);
  closeMenu();
  const swap = () => renderPage(path, { hash: next.hash, focus: push });
  if (document.startViewTransition && !reducedMotion() && currentPath !== path) {
    document.startViewTransition(swap);
  } else swap();
}

document.addEventListener("click", (event) => {
  const link = event.target.closest("a[href]");
  if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  if (link.target && link.target !== "_self") return;
  if (link.hasAttribute("download")) return;
  const url = new URL(link.href, location.href);
  if (url.origin !== location.origin) return;
  const path = url.pathname.replace(/\/+$/, "") || "/";
  if (!routes[path]) return;
  event.preventDefault();
  if (path === currentPath && url.hash) {
    history.pushState({}, "", path + url.hash);
    document.getElementById(decodeURIComponent(url.hash.slice(1)))?.scrollIntoView({ behavior: reducedMotion() ? "auto" : "smooth", block: "start" });
    closeMenu();
    return;
  }
  if (path === currentPath && !url.hash) {
    closeMenu();
    scrollTo({ top: 0, behavior: reducedMotion() ? "auto" : "smooth" });
    return;
  }
  navigate(url.href);
});

addEventListener("popstate", () => navigate(location.href, { push: false }));

document.addEventListener("click", (event) => {
  if (!event.target.closest("[data-lang-toggle]")) return;
  setLang(getLang() === "de" ? "en" : "de");
});

onLang(() => {
  applyStatic();
  syncLangButtons();
  const y = scrollY;
  renderPage(currentPath || "/");
  scrollTo(0, y);
});

function openMenu() {
  menu.hidden = false;
  requestAnimationFrame(() => menu.classList.add("is-open"));
  menuButton.setAttribute("aria-expanded", "true");
  document.body.classList.add("menu-open");
  menu.querySelector("a")?.focus({ preventScroll: true });
}

function closeMenu() {
  if (menu.hidden) return;
  menu.classList.remove("is-open");
  menuButton.setAttribute("aria-expanded", "false");
  document.body.classList.remove("menu-open");
  const end = () => { if (!menu.classList.contains("is-open")) menu.hidden = true; };
  if (reducedMotion()) end();
  else setTimeout(end, 260);
}

menuButton.addEventListener("click", () => (menu.hidden ? openMenu() : closeMenu()));
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !menu.hidden) {
    closeMenu();
    menuButton.focus();
  }
});
matchMedia("(min-width: 900px)").addEventListener("change", (e) => { if (e.matches) closeMenu(); });

let headerQueued = false;
function syncHeader() {
  headerQueued = false;
  header.classList.toggle("is-scrolled", scrollY > 8);
}
addEventListener("scroll", () => {
  if (headerQueued) return;
  headerQueued = true;
  requestAnimationFrame(syncHeader);
}, { passive: true });

applyStatic();
syncLangButtons();
renderPage(normalize(location.pathname), { hash: location.hash });
syncHeader();
