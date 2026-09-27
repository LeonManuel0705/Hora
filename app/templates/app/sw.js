const VERSION = {{ version | tojson }};
const SHELL = `app-shell-${VERSION}`;
const PAGES = `app-pages-${VERSION}`;
const ASSETS = {{ assets | tojson }};
const ASSET_PATHS = new Set(ASSETS);
const PAGE_PATHS = new Set({{ pages | tojson }});
const BRAND = {{ brand_name | tojson }};

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(SHELL)
      .then((cache) => Promise.allSettled(ASSETS.map((path) => cache.add(path))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.filter((name) => name !== SHELL && name !== PAGES).map((name) => caches.delete(name))))
      .then(() => self.clients.claim()),
  );
});

const keep = (response) => response.ok && response.type === "basic" && !response.redirected;

async function remember(cacheName, path, response) {
  const cache = await caches.open(cacheName);
  await cache.put(path, response);
}

async function recall(cacheName, path) {
  const cache = await caches.open(cacheName);
  return cache.match(path);
}

function unreachable() {
  const name = BRAND.replace(/[&<>"']/g, "");
  const html = `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${name}</title></head>`
    + `<body style="margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;color-scheme:light dark;background:light-dark(#F8F6EE,#0F1410);color:light-dark(#2E3A2F,#EDEBE4);font:16px/1.5 system-ui,sans-serif;text-align:center">`
    + `<main><h1 style="font-size:22px;margin:0 0 8px">${name} ist gerade nicht erreichbar</h1>`
    + `<p style="margin:0">Sobald der Rechner mit ${name} wieder läuft, geht es hier weiter.</p></main></body></html>`;
  return new Response(html, { status: 503, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
}

async function page(event, url) {
  try {
    const response = await fetch(event.request);
    if (keep(response)) event.waitUntil(remember(PAGES, url.pathname, response.clone()));
    return response;
  } catch {
    const cached = await recall(PAGES, url.pathname);
    if (!cached) return unreachable();
    const headers = new Headers(cached.headers);
    headers.delete("Content-Length");
    const html = (await cached.text()).replace("<html ", '<html data-offline="1" ');
    return new Response(html, { status: 200, headers });
  }
}

async function asset(event, url) {
  try {
    const response = await fetch(event.request);
    if (keep(response)) event.waitUntil(remember(SHELL, url.pathname, response.clone()));
    return response;
  } catch {
    return (await recall(SHELL, url.pathname)) || Response.error();
  }
}

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  if (event.request.mode === "navigate" && PAGE_PATHS.has(url.pathname)) {
    event.respondWith(page(event, url));
  } else if (ASSET_PATHS.has(url.pathname)) {
    event.respondWith(asset(event, url));
  }
});
