'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "dbc366684edf156e2c425ffc44806b63",
"version.json": "24e4bbe9402792e9a9933ddfedc792b4",
"index.html": "48f7810e87969786e7620d14277d754c",
"/": "48f7810e87969786e7620d14277d754c",
"main.dart.js": "6c33e86770ea2085c6c2fa2046c8b01b",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "5d59e1b512979e23c50337daeb83db1e",
"icons/Icon-192.png": "df6d8eead08acd4783faa0fe364a26ec",
"icons/Icon-maskable-192.png": "df6d8eead08acd4783faa0fe364a26ec",
"icons/Icon-maskable-512.png": "4058f24f3fe5802f3768e41c4d79741a",
"icons/Icon-512.png": "4058f24f3fe5802f3768e41c4d79741a",
"manifest.json": "6311f5aa03e3e9a3183652fa4076cd2a",
"assets/NOTICES": "9f442e67bdb887f60b8b6f4c31c76e2d",
"assets/FontManifest.json": "2607f5c02c25da446f037fef77ced341",
"assets/AssetManifest.bin.json": "e87f76eb8ac35f5d170184eafa3be95e",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/flutter_inappwebview_web/assets/web/web_support.js": "509ae636cfdd93e49b5a6eaf0f06d79f",
"assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.css": "5a8d0222407e388155d7d1395a75d5b9",
"assets/packages/flutter_inappwebview/assets/t_rex_runner/t-rex.html": "16911fcc170c8af1c5457940bd0bf055",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/AssetManifest.bin": "8f3db282b511da380f7f52dd5529fbac",
"assets/fonts/MaterialIcons-Regular.otf": "7a200469eb46aa599231cede4ff1244b",
"assets/assets/ui/static/app/css/tokens.css": "43d506b6aa53f74828b0675ace477e66",
"assets/assets/ui/static/app/css/app.css": "3ff7bc9313e59d10096e8cca48d4a52e",
"assets/assets/ui/static/app/css/pages/email.css": "02d4f5371c932fbf4d78b672295b7bfa",
"assets/assets/ui/static/app/css/pages/transit.css": "4b4deb98ca8f8b780268cfc2bc9cb876",
"assets/assets/ui/static/app/css/pages/settings.css": "1bdbf738b25fe22fb3fa23af156206df",
"assets/assets/ui/static/app/css/pages/school.css": "7a626b3c386cae8632b65b05c9cc029c",
"assets/assets/ui/static/app/css/pages/calendar.css": "b3f48d9427b9529060456d5a0a116204",
"assets/assets/ui/static/app/js/shell.js": "d67c4b258b380f49c03dd6a0f2a46c85",
"assets/assets/ui/static/app/js/core.js": "140635507412975a1fadca47d7d48c57",
"assets/assets/ui/static/app/js/desk.js": "0d61f73578f0ea7148e2fa87562b19e9",
"assets/assets/ui/static/app/js/home.js": "74da34ba132e10edb250aa687fbc2663",
"assets/assets/ui/static/app/js/tasks.js": "3241ed0607311e45f484df239ec5a5db",
"assets/assets/ui/static/app/js/main.js": "f1ce658226a95adde06373777ab1cc91",
"assets/assets/ui/static/app/js/tinte.js": "5f672d9b1c0957798e312ff4b2253a37",
"assets/assets/ui/static/app/js/motion.js": "56a8cb44f59e297e8a806c97a4924565",
"assets/assets/ui/static/app/js/api.js": "558e17ec1849b9d872505a446d9a31bf",
"assets/assets/ui/static/app/js/pages/school.js": "574c4e91d46ed36d3beff5d328ce54f3",
"assets/assets/ui/static/app/js/pages/transit.js": "0e5d8306be0ff602fdc6efe6aee16088",
"assets/assets/ui/static/app/js/pages/calendar.js": "4775bf96f7b18956190fe35b20549c9c",
"assets/assets/ui/static/app/js/pages/settings.js": "7f9dbe0c075b8f8b49e76b4477b506eb",
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
"assets/assets/ui/pages/home.html": "41168499fc44699135004ecd414680bb",
"assets/assets/ui/pages/calendar.html": "63dc9d2ccf2490508b1c3871fd2e82a3",
"assets/assets/ui/pages/school.html": "fcd7b1dc1744463092ea87c9533ea898",
"assets/assets/ui/pages/tasks.html": "e4231e46978e6a55c12248b0edb53c31",
"assets/assets/ui/pages/email.html": "a0f6ab8563170c20637956de0c4cc23a",
"assets/assets/ui/pages/vbb.html": "96f501fbe3849225b06f91f92a3ab468",
"assets/assets/ui/pages/settings.html": "832e52d0f77bcb54b179c8f196404525",
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
