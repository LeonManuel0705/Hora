// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

const APP = new URL("./", self.location).pathname;
const SCOPE = "/hub";
const WAIT = 20000;
const REDIRECTS = new Set([301, 302, 303, 307, 308]);

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

const inScope = (path) => path === SCOPE || path.startsWith(`${SCOPE}/`);

async function hosts() {
  const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
  return windows
    .filter((client) => client.frameType !== "nested" && new URL(client.url).pathname.startsWith(APP))
    .sort((a, b) => Number(b.focused) - Number(a.focused) || Number(b.visibilityState === "visible") - Number(a.visibilityState === "visible"));
}

function ask(client, message) {
  return new Promise((resolve) => {
    const channel = new MessageChannel();
    const timer = setTimeout(() => resolve(null), WAIT);
    channel.port1.onmessage = (event) => {
      clearTimeout(timer);
      resolve(event.data);
    };
    client.postMessage(message, [channel.port2]);
  });
}

function answer(reply) {
  const headers = new Headers(reply.headers || {});
  if (REDIRECTS.has(reply.status)) return Response.redirect(new URL(headers.get("Location") || SCOPE, self.location.origin).href, reply.status);
  const empty = reply.status === 204 || reply.status === 304 || reply.body === null || reply.body === undefined;
  return new Response(empty ? null : reply.body, { status: reply.status, headers });
}

function unavailable(navigate) {
  if (!navigate) {
    return new Response(JSON.stringify({ success: false, error: "Gerade nicht erreichbar" }), {
      status: 503,
      headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
    });
  }
  const page = '<!doctype html><html lang="de"><meta charset="utf-8"><meta http-equiv="refresh" content="2">'
    + '<meta name="viewport" content="width=device-width, initial-scale=1"><title>Einen Moment</title>'
    + '<body style="margin:0;min-height:100vh;display:grid;place-items:center;font:16px/1.5 system-ui,sans-serif;color-scheme:light dark">'
    + "<p>Einen Moment, gleich geht es weiter.</p></body></html>";
  return new Response(page, {
    status: 503,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'self'",
    },
  });
}

function sender(request) {
  if (!request.referrer || !request.referrer.startsWith(`${self.location.origin}/`)) return null;
  return new URL(request.referrer).pathname;
}

async function relay(request, navigate) {
  const url = new URL(request.url);
  const message = {
    type: "hub-request",
    navigate,
    method: request.method,
    path: url.pathname,
    query: url.search,
    from: sender(request),
    body: request.method === "GET" || request.method === "HEAD" ? null : await request.text(),
    contentType: request.headers.get("Content-Type"),
  };
  for (const client of await hosts()) {
    const reply = await ask(client, message);
    if (reply && !reply.busy) return answer(reply);
  }
  return unavailable(navigate);
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (request.mode === "navigate") {
    if (!inScope(url.pathname)) return;
    if (request.destination !== "iframe") {
      event.respondWith(Response.redirect(new URL(APP, self.location.origin).href, 302));
      return;
    }
    event.respondWith(relay(request, true));
    return;
  }
  if (url.pathname.startsWith("/static/") || url.pathname.startsWith("/api/")) event.respondWith(relay(request, false));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    hosts().then(([client]) => (client ? client.focus() : self.clients.openWindow(APP))),
  );
});
