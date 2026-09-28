import { brandName, escapeHtml, getLang, raw, t } from "../lib/i18n.js";
import { reducedMotion } from "../lib/motion.js";
import { detectPlatform, megabytes, PLATFORMS } from "../lib/platform.js";
import { clamp, onScroll, revealOnce, wordReveal } from "../lib/scroll.js";
import { tinte } from "../lib/tinte.js";
import { macHTML, showScreen } from "../components/device.js";
import { mountDownloads, platformMark } from "../components/downloads.js";
import { cta, SHORT } from "../components/cta.js";
import { galleryHTML, mountGallery } from "../components/gallery.js";
import { mountScenes, SCENES } from "../components/scenes.js";
import { lockHTML, mountLock } from "../components/lock.js";
import { CHEVRON } from "../components/page.js";

const keepHyphens = (text) => escapeHtml(text).replace(/(\S+-\S+)/g, '<span class="nw">$1</span>');

const words = (text) => escapeHtml(text).split(/\s+/).map((word) => `<span class="w">${word}</span>`).join(" ");

function hero() {
  const { button, note } = cta();
  return `<section class="ap-hero" aria-labelledby="ap-hero-title">
    <div class="ap-hero-copy" data-hero-copy>
      <h1 class="ap-hero-head" id="ap-hero-title"><span class="ap-hero-name">${escapeHtml(t("start.intro"))}</span><span class="ap-hero-title">${escapeHtml(t("start.title"))}</span></h1>
      <p class="ap-hero-lede">${escapeHtml(t("start.lede"))}</p>
      <div class="ap-hero-cta">${button}<a class="ap-link" href="#tag">${escapeHtml(t("start.more"))}${CHEVRON}</a></div>
      <p class="ap-hero-note">${escapeHtml(note)}</p>
    </div>
    <div class="ap-hero-device" data-hero-device>${macHTML([{ id: "heute", alt: t("start.hero_alt") }], { eager: true })}</div>
  </section>`;
}

function statement() {
  return `<section class="ap-statement" data-statement aria-label="${escapeHtml(brandName)}">
    <div class="ap-statement-pin"><p class="ap-words" data-words>${words(t("start.statement"))}</p></div>
  </section>`;
}

function showcase() {
  const steps = raw("start.steps") || [];
  const items = steps.map((step, i) => `<li class="ap-step${i === 0 ? " is-active" : ""}" data-step="${step.id}">
      <p class="ap-step-label">${escapeHtml(step.label)}</p>
      <h3 class="ap-step-title">${keepHyphens(step.title)}</h3>
      <p class="ap-step-text">${escapeHtml(step.text)}</p>
      <img class="ap-step-shot" src="/screens/${step.id}.webp" width="2880" height="1800" alt="" loading="lazy" decoding="async">
    </li>`).join("");
  return `<section class="ap-show" id="tag" aria-labelledby="ap-show-title">
    <h2 class="ap-h2 ap-show-title ap-reveal" id="ap-show-title">${escapeHtml(t("start.show_title"))}</h2>
    <div class="ap-show-body">
      <ol class="ap-steps">${items}</ol>
      <div class="ap-show-stage"><div class="ap-show-sticky" data-show-device>${macHTML(steps.map((step) => ({ id: step.id, alt: step.alt })))}</div></div>
    </div>
  </section>`;
}

function highlights() {
  const cards = (raw("start.cards") || []).map((card) => ({ ...card, visual: SCENES[card.id]?.() || "" }));
  return `<section class="ap-high" aria-labelledby="ap-high-title">
    <h2 class="ap-h2 ap-high-title ap-reveal" id="ap-high-title">${escapeHtml(t("start.high_title"))}</h2>
    ${galleryHTML({ id: "highlights", label: t("start.high_label"), cards })}
  </section>`;
}

function agent() {
  const chat = raw("start.chat") || [];
  const day = raw("start.day") || [];
  const bubbles = chat.map((message, i) => `<li class="ap-msg is-${message.from}" data-msg="${i}"${message.mood ? ` data-mood="${message.mood}"` : ""}><p>${escapeHtml(message.text)}</p></li>`).join("");
  const moments = day.map((moment) => `<li class="ap-moment ap-reveal">
      <div class="ap-moment-tinte">${tinte(moment.mood, 132, "", { still: true })}</div>
      <p class="ap-moment-time">${escapeHtml(moment.time)}</p>
      <p class="ap-moment-text">${escapeHtml(moment.text)}</p>
    </li>`).join("");
  return `<section class="ap-agent" id="tinte" aria-labelledby="ap-agent-title">
    <div class="ap-agent-head">
      <p class="ap-eyebrow ap-reveal">${escapeHtml(t("start.agent_eyebrow"))}</p>
      <h2 class="ap-h2 ap-reveal" id="ap-agent-title">${escapeHtml(t("start.agent_title"))}</h2>
      <p class="ap-sub ap-reveal">${escapeHtml(t("start.agent_text"))}</p>
    </div>
    <div class="ap-agent-stage ap-reveal">
      <div class="ap-agent-avatar" data-avatar>${tinte("ruhe", 280, t("start.tile_tinte_label"))}</div>
      <div class="ap-chat" data-chat>
        <div class="ap-chat-head">
          <span class="ap-chat-face" aria-hidden="true">${tinte("ruhe", 40, "", { still: true })}</span>
          <div><p class="ap-chat-name">${escapeHtml(t("start.agent_name"))}</p><p class="ap-chat-role">${escapeHtml(t("start.agent_role"))}</p></div>
          <p class="ap-chat-time">${escapeHtml(t("start.agent_time"))}</p>
        </div>
        <ol class="ap-chat-list" role="log" aria-label="${escapeHtml(t("start.agent_label"))}">${bubbles}<li class="ap-msg is-tinte is-typing" data-typing aria-hidden="true"><p><i></i><i></i><i></i></p></li></ol>
        <div class="ap-chat-input" aria-hidden="true"><span>${escapeHtml(t("start.agent_input"))}</span><i></i></div>
      </div>
    </div>
    <h3 class="ap-agent-day-title ap-reveal">${escapeHtml(t("start.day_title"))}</h3>
    <ol class="ap-moments">${moments}</ol>
  </section>`;
}

function free() {
  return `<section class="ap-free" aria-labelledby="ap-free-title">
    <p class="ap-free-count" data-count role="img" aria-label="${escapeHtml(t("start.free_label"))}">0,00 €</p>
    <p class="ap-free-lesson ap-reveal">${escapeHtml(t("start.free_lesson"))}</p>
    <h2 class="ap-free-title ap-reveal" id="ap-free-title">${escapeHtml(t("start.free_title"))}</h2>
    <p class="ap-free-text ap-reveal">${escapeHtml(t("start.free_text"))}</p>
  </section>`;
}

function privacy() {
  return `<section class="ap-privacy" aria-labelledby="ap-privacy-title">
    ${lockHTML(t("start.lock_label"), "ap-lock")}
    <h2 class="ap-h2 ap-reveal" id="ap-privacy-title">${escapeHtml(t("start.privacy_title"))}</h2>
    <p class="ap-sub ap-reveal">${escapeHtml(t("start.privacy_text"))}</p>
    <a class="ap-link ap-reveal" href="/privacy-philosophy">${escapeHtml(t("start.privacy_link"))}${CHEVRON}</a>
  </section>`;
}

function getHora() {
  const mine = detectPlatform();
  const platforms = ["macos", "windows", "linux", "android", "ios"].map((id) => {
    const p = PLATFORMS[id];
    const pwa = p.kind === "pwa";
    const meta = pwa ? t("start.cta_web") : `${megabytes(p.bytes)} MB`;
    const attrs = pwa ? `href="${p.href}"` : `href="${p.href}" download data-download="${id}"`;
    return `<li><a class="ap-platform${id === mine ? " is-yours" : ""}" ${attrs}>
      <span class="ap-platform-mark">${platformMark(id, 30)}</span>
      <span class="ap-platform-name">${escapeHtml(SHORT[id])}</span>
      <span class="ap-platform-meta">${escapeHtml(meta)}</span>
    </a></li>`;
  }).join("");
  const { button } = cta();
  return `<section class="ap-get" id="laden" aria-labelledby="ap-get-title">
    <h2 class="ap-get-title ap-reveal" id="ap-get-title">${escapeHtml(t("start.get_title"))}</h2>
    <p class="ap-sub ap-reveal">${escapeHtml(t("start.get_text"))}</p>
    <ul class="ap-platforms ap-reveal">${platforms}</ul>
    <div class="ap-get-cta ap-reveal">${button}<a class="ap-link" href="/download">${escapeHtml(t("start.get_all"))}${CHEVRON}</a></div>
    <p class="ap-fine">${escapeHtml(t("start.fine"))}</p>
    <p class="ap-fine ap-footnote">${escapeHtml(t("start.footnote_agent"))}</p>
    <p class="ap-fine ap-footnote">${escapeHtml(t("start.footnote"))}</p>
  </section>`;
}

function mountHero(root) {
  const section = root.querySelector(".ap-hero");
  const copy = root.querySelector("[data-hero-copy]");
  const device = root.querySelector("[data-hero-device]");
  requestAnimationFrame(() => requestAnimationFrame(() => section.classList.add("is-ready")));
  if (reducedMotion()) return () => {};
  return onScroll(section, (box, vh) => {
    const p = clamp(-box.top / (vh * 0.75));
    copy.style.opacity = String(clamp(1 - p * 1.35));
    copy.style.translate = `0 ${(-p * 70).toFixed(1)}px`;
    device.style.scale = String((1 + p * 0.07).toFixed(4));
  }, "0%");
}

function mountShowcase(root) {
  const steps = [...root.querySelectorAll(".ap-step")];
  const device = root.querySelector("[data-show-device]");
  if (!steps.length || !device) return () => {};
  for (const img of device.querySelectorAll(".mac-shot")) img.loading = "eager";
  const activate = (step) => {
    for (const other of steps) other.classList.toggle("is-active", other === step);
    showScreen(device, step.dataset.step);
  };
  const io = new IntersectionObserver((entries) => {
    for (const entry of entries) if (entry.isIntersecting) activate(entry.target);
  }, { rootMargin: "-48% 0px -48% 0px" });
  steps.forEach((step) => io.observe(step));
  return () => io.disconnect();
}

function mountChat(root) {
  const chat = root.querySelector("[data-chat]");
  const avatar = root.querySelector("[data-avatar]");
  if (!chat || !avatar) return () => {};
  const messages = [...chat.querySelectorAll("[data-msg]")];
  const typing = chat.querySelector("[data-typing]");
  const label = t("start.tile_tinte_label");
  if (reducedMotion() || !("IntersectionObserver" in window)) {
    messages.forEach((message) => message.classList.add("is-in"));
    return () => {};
  }
  const timers = [];
  const at = (ms, fn) => timers.push(setTimeout(fn, ms));
  const ease = getComputedStyle(avatar).getPropertyValue("--ap-ease").trim() || "ease";
  const mood = (kind) => {
    const current = avatar.querySelector(".tinte:not(.is-leaving)");
    if (current?.classList.contains(`is-${kind}`)) return;
    avatar.insertAdjacentHTML("beforeend", tinte(kind, 280, label));
    if (!current) return;
    current.classList.add("is-leaving");
    current.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "scale(0.94)" }], { duration: 480, easing: ease, fill: "forwards" })
      .finished.catch(() => {}).then(() => current.remove());
    avatar.lastElementChild.animate([{ opacity: 0, transform: "scale(1.06)" }, { opacity: 1, transform: "none" }], { duration: 480, easing: ease });
  };
  const show = (message) => message.classList.add("is-in");
  const play = () => {
    let clock = 0;
    messages.forEach((message) => {
      if (message.classList.contains("is-me")) {
        at(clock, () => show(message));
        clock += 700;
        return;
      }
      at(clock, () => {
        typing.classList.add("is-in");
        mood("laedt");
      });
      clock += 1250;
      at(clock, () => {
        typing.classList.remove("is-in");
        show(message);
        mood(message.dataset.mood === "cheer" ? "geschafft" : "ruhe");
      });
      clock += message.dataset.mood === "cheer" ? 1900 : 1300;
      if (message.dataset.mood === "cheer") at(clock - 300, () => mood("ruhe"));
    });
  };
  const io = new IntersectionObserver((entries) => {
    if (!entries.some((entry) => entry.isIntersecting)) return;
    io.disconnect();
    play();
  }, { threshold: 0.45 });
  io.observe(chat);
  return () => {
    io.disconnect();
    timers.forEach(clearTimeout);
  };
}

function mountCounter(root) {
  const el = root.querySelector("[data-count]");
  if (!el) return () => {};
  const locale = getLang() === "de" ? "de-DE" : "en-IE";
  const money = new Intl.NumberFormat(locale, { style: "currency", currency: "EUR" });
  const zero = new Intl.NumberFormat(locale, { style: "currency", currency: "EUR", minimumFractionDigits: 0, maximumFractionDigits: 0 }).format(0);
  el.textContent = money.format(0);
  const land = () => {
    el.textContent = zero;
    el.classList.add("is-zero");
  };
  if (reducedMotion() || !("IntersectionObserver" in window)) {
    land();
    return () => {};
  }
  let frame = 0;
  const peak = 49.99;
  const up = 1150;
  const hold = 160;
  const down = 1500;
  const inOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  const outQuart = (x) => 1 - Math.pow(1 - x, 4);
  const run = (start) => {
    const tick = (now) => {
      const elapsed = now - start;
      let value;
      if (elapsed < up) value = peak * inOut(elapsed / up);
      else if (elapsed < up + hold) value = peak;
      else if (elapsed < up + hold + down) value = peak * (1 - outQuart((elapsed - up - hold) / down));
      else return land();
      el.textContent = money.format(Math.round(value * 100) / 100);
      el.classList.toggle("is-counting", true);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
  };
  const io = new IntersectionObserver((entries) => {
    if (!entries.some((entry) => entry.isIntersecting)) return;
    io.disconnect();
    run(performance.now());
  }, { threshold: 0.6 });
  io.observe(el);
  return () => {
    io.disconnect();
    cancelAnimationFrame(frame);
  };
}

export default {
  title: () => t("meta.home"),
  render: () => `<div class="ap">${hero()}${statement()}${showcase()}${agent()}${highlights()}${free()}${privacy()}${getHora()}</div>`,
  mount(root) {
    const cleanups = [
      mountHero(root),
      wordReveal(root.querySelector("[data-words]"), root.querySelector("[data-statement]")),
      mountShowcase(root),
      revealOnce(root, ".ap-reveal, .hl"),
      mountGallery(root),
      mountScenes(root),
      mountChat(root),
      mountCounter(root),
      mountLock(root),
      mountDownloads(root),
    ];
    return () => cleanups.forEach((fn) => fn && fn());
  },
};
