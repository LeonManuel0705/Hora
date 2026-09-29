'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "330a03cbb34150be88ff22229d049c41",
"version.json": "fe3bccdb533221de97d9348270c990d9",
"sqlite3-3.3.4.wasm": "0d26505f2d32b5f49616648fe90b9214",
"index.html": "dc41cfdde77f9dbeab299841843ad9fb",
"/": "dc41cfdde77f9dbeab299841843ad9fb",
"main.dart.js": "bb9257fea9bbb20e4db57c646d93dfad",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "5d59e1b512979e23c50337daeb83db1e",
"icons/Icon-192.png": "df6d8eead08acd4783faa0fe364a26ec",
"icons/Icon-maskable-192.png": "df6d8eead08acd4783faa0fe364a26ec",
"icons/Icon-maskable-512.png": "4058f24f3fe5802f3768e41c4d79741a",
"icons/Icon-512.png": "4058f24f3fe5802f3768e41c4d79741a",
"manifest.json": "6311f5aa03e3e9a3183652fa4076cd2a",
"hub_worker.js": "1bc88bf4fdfe5ca0acb8ff0e5b029f6b",
"assets/NOTICES": "afb89164a6f9887fda9947da17072bfc",
"assets/FontManifest.json": "2607f5c02c25da446f037fef77ced341",
"assets/AssetManifest.bin.json": "347467ced09fdb5bb56ef4a24b47c003",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/flutter_inappwebview_web/assets/web/web_support.js": "509ae636cfdd93e49b5a6eaf0f06d79f",
"assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.css": "5a8d0222407e388155d7d1395a75d5b9",
"assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.html": "16911fcc170c8af1c5457940bd0bf055",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/AssetManifest.bin": "48c3845d62238744daa2db24364bfa76",
"assets/fonts/MaterialIcons-Regular.otf": "f4bd904d1f209ec77c320cc260597975",
"assets/assets/ui/static/app/css/tokens.css": "43d506b6aa53f74828b0675ace477e66",
"assets/assets/ui/static/app/css/app.css": "3ff7bc9313e59d10096e8cca48d4a52e",
"assets/assets/ui/static/app/css/pages/assistant.css": "1d373ad9166482ce192d9e9d6f02afe6",
"assets/assets/ui/static/app/css/pages/email.css": "02d4f5371c932fbf4d78b672295b7bfa",
"assets/assets/ui/static/app/css/pages/transit.css": "4b4deb98ca8f8b780268cfc2bc9cb876",
"assets/assets/ui/static/app/css/pages/settings.css": "1bdbf738b25fe22fb3fa23af156206df",
"assets/assets/ui/static/app/css/pages/school.css": "d52ad1844ad7ebd4fffe36c623d4deda",
"assets/assets/ui/static/app/css/pages/calendar.css": "b3f48d9427b9529060456d5a0a116204",
"assets/assets/ui/static/app/js/shell.js": "7b3c25fdec7b56935b50ba4a3f9fb281",
"assets/assets/ui/static/app/js/reminders.js": "287143abc6859887671c14bc3ec2ead3",
"assets/assets/ui/static/app/js/core.js": "cbaa1dba2368189834895bbb27a99314",
"assets/assets/ui/static/app/js/desk.js": "0d61f73578f0ea7148e2fa87562b19e9",
"assets/assets/ui/static/app/js/home.js": "74da34ba132e10edb250aa687fbc2663",
"assets/assets/ui/static/app/js/tasks.js": "3241ed0607311e45f484df239ec5a5db",
"assets/assets/ui/static/app/js/main.js": "50ddb35afc9eeec53386baa14fdecfcc",
"assets/assets/ui/static/app/js/tinte.js": "5f672d9b1c0957798e312ff4b2253a37",
"assets/assets/ui/static/app/js/motion.js": "56a8cb44f59e297e8a806c97a4924565",
"assets/assets/ui/static/app/js/api.js": "558e17ec1849b9d872505a446d9a31bf",
"assets/assets/ui/static/app/js/pages/assistant.js": "2f0586dd632277396893a4cb5ce2d26e",
"assets/assets/ui/static/app/js/pages/school.js": "af167adfbbfe2ecbd98bcda6176df44d",
"assets/assets/ui/static/app/js/pages/transit.js": "0e5d8306be0ff602fdc6efe6aee16088",
"assets/assets/ui/static/app/js/pages/calendar.js": "4775bf96f7b18956190fe35b20549c9c",
"assets/assets/ui/static/app/js/pages/settings.js": "2e6ee8fa2db3f8d47e548462e768b051",
"assets/assets/ui/static/app/js/pages/email.js": "8b140dc4c5b285ac855c6006babb820c",
"assets/assets/ui/static/app/img/hora-favicon.svg": "23673ad52f9ec37234e3af0badb8bca2",
"assets/assets/ui/static/app/img/tinte/geschafft.svg": "9fc59e22434c476ec932054e4e1aa48a",
"assets/assets/ui/static/app/img/tinte/laedt.svg": "6f826af56cc8c1a0cbcddd0e7e3c26f4",
"assets/assets/ui/static/app/img/tinte/ruhe.svg": "3836f1e47467603bd22ddbf9d9aa397b",
"assets/assets/ui/static/app/img/tinte/schlaeft.svg": "3e22a73e1f9e0a5f1f1a3f70a2223700",
"assets/assets/ui/static/css/tour.css": "a8eef6cd5e43f66ce3e2ba827178ff41",
"assets/assets/ui/static/js/tour.js": "e9edd7cbeccba3fdae01ae1a93eafbf0",
"assets/assets/ui/static/js/tinte.js": "8a449def97cf4ad3f20a9f7de11b63f2",
"assets/assets/ui/static/fonts/bricolage-grotesque.woff2": "1c8faed3b10a19e8b8768a35f95cb0e6",
"assets/assets/ui/static/fonts/OFL-Bricolage.txt": "ca124d9da1494f1d3c650b05144c8ceb",
"assets/assets/ui/pages/home.html": "c3dd5e48482e71f4557c8a3608b76b7c",
"assets/assets/ui/pages/calendar.html": "fd97ec1e44d7ccdd8b56ed6f62ed416a",
"assets/assets/ui/pages/school.html": "00048ccfac3063c7c7f95ee92eac1664",
"assets/assets/ui/pages/tasks.html": "d28de10ee0586227f05edb0f4268c577",
"assets/assets/ui/pages/email.html": "e17751bcb71e4f9cf6f834df9ae6c678",
"assets/assets/ui/pages/vbb.html": "85eb9cd859358b66f67237e34715a584",
"assets/assets/ui/pages/settings.html": "209fc712fb303d772833b6ba55c21b31",
"assets/assets/curriculum/epochen.json": "9b015574a2db9633ce0ac6b1213e5ca8",
"assets/assets/curriculum/concepts.json": "e62d35854c2839e3f52db452aae08140",
"assets/assets/curriculum/formeln.json": "322fa521171ff3696d172cd0640a4779",
"assets/assets/curriculum/topics.json": "9326b48f01b3e8666c48fbef14df9824",
"assets/assets/logo.png": "181c7a72e46e7e6574338672e154007a",
"assets/assets/fonts/JetBrainsMono-Regular.ttf": "d09f65145228b709a10fa0a06d522d89",
"assets/assets/fonts/BricolageGrotesque-ExtraBold.ttf": "bba76d296502373613b6928d5773bf76",
"assets/assets/fonts/BricolageGrotesque-Regular.ttf": "d79b9757a8f562a17c6dac29f49b4485",
"assets/assets/fonts/BricolageGrotesque-SemiBold.ttf": "dadcc359467ebb4f6c5e99cdafeba170",
"assets/assets/fonts/InterVariable.ttf": "7c80433dfb0d6e565327d9beeb774bac",
"assets/assets/fonts/BricolageGrotesque-Medium.ttf": "a73c28f9eb504408207b67ce43b0a1f3",
"assets/assets/fonts/BricolageGrotesque-Bold.ttf": "68ea03d7e77f5ca099e59a52679752f7",
"assets/assets/fonts/BricolageGrotesque-Light.ttf": "a97e459d851bed765221fa8a51219448",
"assets/assets/fonts/JetBrainsMono-Medium.ttf": "b41d61d1b5a063fdcb6a7cdeacac57b0",
"assets/assets/nav_selection.json": "3b006d30b3d9d0e6d70f402e209b3d71",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
