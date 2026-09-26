// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

importScripts('/static/js/brand.js');

const STATIC_CACHE = 'app-static-v10';
const DYNAMIC_CACHE = 'app-dynamic-v10';

const STATIC_ASSETS = [
  '/',
  '/hub',
  '/hub/tasks',
  '/hub/calendar',
  '/hub/email',
  '/hub/school',
  '/hub/review',
  '/hub/training',
  '/hub/settings',
  '/static/css/hub.css',
  '/static/css/loading.css',
  '/static/css/tour.css',
  '/static/js/hub.js',
  '/static/js/offline.js',
  '/static/js/notifications.js',
  '/static/js/tinte.js',
  '/static/js/tour.js',
  '/static/fonts/bricolage-grotesque.woff2',
  '/static/manifest.json',

  '/static/images/icons/icon-192.png',
  '/static/images/icons/icon-512.png',

];

const OFFLINE_PAGES = [
  '/hub',
  '/hub/tasks',
  '/hub/calendar',
  '/hub/school',
  '/hub/review',
  '/hub/training',
  '/hub/settings',
];

self.addEventListener('install', (event) => {
  console.log('[SW] Installing Service Worker...');

  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then((cache) => {
        console.log('[SW] Pre-caching app shell...');

        return Promise.allSettled(
          STATIC_ASSETS.map(url =>
            cache.add(url).catch(err => {
              console.warn(`[SW] Failed to cache: ${url}`, err);
            })
          )
        );
      })
      .then(() => {
        console.log('[SW] App shell cached successfully');
        return self.skipWaiting();
      })
  );
});

self.addEventListener('activate', (event) => {
  console.log('[SW] Activating Service Worker...');

  event.waitUntil(
    caches.keys()
      .then((cacheNames) => {
        return Promise.all(
          cacheNames
            .filter((name) => name !== STATIC_CACHE && name !== DYNAMIC_CACHE)
            .map((name) => {
              console.log('[SW] Deleting old cache:', name);
              return caches.delete(name);
            })
        );
      })
      .then(() => {
        console.log('[SW] Service Worker activated');
        return self.clients.claim();
      })
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== 'GET') {
    return;
  }

  if (url.origin !== location.origin) {

    if (!url.hostname.includes('fonts.googleapis.com') &&
        !url.hostname.includes('fonts.gstatic.com') &&
        !url.hostname.includes('cdnjs.cloudflare.com')) {
      return;
    }
  }

  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request)
        .catch(() => {

          return new Response(
            JSON.stringify({ error: 'offline', message: 'You are offline' }),
            {
              status: 503,
              headers: { 'Content-Type': 'application/json' }
            }
          );
        })
    );
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then((networkResponse) => {
          const responseClone = networkResponse.clone();
          caches.open(DYNAMIC_CACHE)
            .then(cache => cache.put(request, responseClone));
          return networkResponse;
        })
        .catch(() => {
          return caches.match(request).then((cachedResponse) => {
            if (cachedResponse) {
              return cachedResponse;
            }
            return caches.match('/hub');
          });
        })
    );
    return;
  }

  if (isStaticAsset(url.pathname)) {
    event.respondWith(
      fetch(request)
        .then((networkResponse) => {
          const responseClone = networkResponse.clone();
          caches.open(STATIC_CACHE)
            .then(cache => cache.put(request, responseClone));
          return networkResponse;
        })
        .catch(() => caches.match(request))
    );
    return;
  }

  event.respondWith(
    fetch(request)
      .then((networkResponse) => {
        const responseClone = networkResponse.clone();
        caches.open(DYNAMIC_CACHE)
          .then(cache => cache.put(request, responseClone));
        return networkResponse;
      })
      .catch(() => {
        return caches.match(request);
      })
  );
});

function isStaticAsset(pathname) {
  return pathname.startsWith('/static/') ||
         pathname.endsWith('.css') ||
         pathname.endsWith('.js') ||
         pathname.endsWith('.png') ||
         pathname.endsWith('.jpg') ||
         pathname.endsWith('.svg') ||
         pathname.endsWith('.woff') ||
         pathname.endsWith('.woff2') ||
         pathname.endsWith('.ico');
}

function fetchAndCache(request, cacheName) {
  fetch(request)
    .then((response) => {
      if (response.ok) {
        caches.open(cacheName)
          .then(cache => cache.put(request, response));
      }
    })
    .catch(() => {

    });
}

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  if (event.data && event.data.type === 'CACHE_URLS') {
    const urls = (event.data.urls || []).filter(url => {
      try {
        const parsed = new URL(url, location.origin);
        return parsed.origin === location.origin;
      } catch { return false; }
    });
    event.waitUntil(
      caches.open(DYNAMIC_CACHE)
        .then(cache => cache.addAll(urls))
    );
  }

  if (event.data && event.data.type === 'CLEAR_CACHE') {
    event.waitUntil(
      caches.keys()
        .then(names => Promise.all(names.map(name => caches.delete(name))))
        .then(() => {
          console.log('[SW] All caches cleared');
        })
    );
  }
});

self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-data') {
    console.log('[SW] Background sync triggered');

    event.waitUntil(
      self.clients.matchAll()
        .then(clients => {
          clients.forEach(client => {
            client.postMessage({ type: 'SYNC_READY' });
          });
        })
    );
  }
});

self.addEventListener('push', (event) => {
  if (event.data) {
    try {
      const data = event.data.json();
      const title = typeof data.title === 'string' ? data.title.slice(0, 200) : self.BRAND_NAME;
      const body = typeof data.body === 'string' ? data.body.slice(0, 500) : `New notification from ${self.BRAND_NAME}`;
      const ALLOWED_ACTIONS = ['open', 'dismiss', 'view'];
      const actions = Array.isArray(data.actions)
        ? data.actions.filter(a => ALLOWED_ACTIONS.includes(a.action)).slice(0, 3)
        : [];
      const options = {
        body,
        icon: '/static/images/icons/icon-192.png',
        badge: '/static/images/icons/icon-72.png',
        vibrate: [100, 50, 100],
        data: { url: (typeof data.data?.url === 'string' && data.data.url.startsWith('/') && !data.data.url.startsWith('//')) ? data.data.url : '/hub' },
        actions
      };
      event.waitUntil(
        self.registration.showNotification(title, options)
      );
    } catch (e) {
      console.error('[SW] Invalid push data', e);
    }
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  let urlToOpen = event.notification.data?.url || '/hub';
  try {
    if (urlToOpen.startsWith('//') || !urlToOpen.startsWith('/')) {
      const parsed = new URL(urlToOpen, location.origin);
      if (parsed.origin !== location.origin) {
        urlToOpen = '/hub';
      }
    }
  } catch { urlToOpen = '/hub'; }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(clientList => {

        for (const client of clientList) {
          if (client.url.includes('/hub') && 'focus' in client) {
            return client.focus();
          }
        }

        if (self.clients.openWindow) {
          return self.clients.openWindow(urlToOpen);
        }
      })
  );
});

console.log('[SW] Service Worker loaded');
