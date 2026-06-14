'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"assets/assets/fonts/medium.otf": "51fd7406327f2b1dbc8e708e6a9da9a5",
"assets/assets/fonts/regular.otf": "aaeac71d99a345145a126a8c9dd2615f",
"assets/assets/fonts/bold.otf": "644563f48ab5fe8e9082b64b2729b068",
"assets/assets/images/search/alan.webp": "3cad962a08f5e3fb2fa2e272949e436a",
"assets/assets/images/search/dmasiv.webp": "6accc2b2f06626635fc1b40a6a2fa1ca",
"assets/assets/images/search/blues.webp": "5a59b580afb492dcd5e3125293f423dd",
"assets/assets/images/search/country.webp": "5520ede717a5783ba63b7074088b0884",
"assets/assets/images/search/akustik.webp": "9da13f5433cb5dac4cd0b8cc2720e6d9",
"assets/assets/images/search/park.webp": "406f3ff8dff5f21b7bd637e02c5c0162",
"assets/assets/images/search/dance.webp": "7e8dcc0fa570dfa18b1523d466eb22b9",
"assets/assets/images/search/lana.webp": "519e0ecd86dad111d06a8af109abe58a",
"assets/assets/images/search/konser.webp": "19e448d5041f5ff68f4b2eb39eff77d9",
"assets/assets/images/search/metal.webp": "64cac280d515dd66513a39f1f4078582",
"assets/assets/images/search/dj.webp": "cff2593f1073a2cf9df5efd8ca09eb75",
"assets/assets/images/search/rock.webp": "30cfbfea2bb8f3c2c443c9dad8d62819",
"assets/assets/images/search/pop.webp": "4ec3434b3e6ac7bb522ff692bac5d8f3",
"assets/assets/images/search/kpop.webp": "67a0e45061ed50a926bf99d19b355887",
"assets/assets/images/search/today.webp": "1ca5ca003600616b05faef78f6fb6f3f",
"assets/assets/images/search/mars.webp": "a22493a5f65ad5d0a2c5db1d39f86acd",
"assets/assets/images/search/electronic.webp": "019f0086324ac4bc4b214c320531e8ea",
"assets/assets/images/search/rnb.webp": "6a92102df42f50fb8d1ce2af5a4b73a9",
"assets/assets/images/search/hiphop.webp": "f52a9127ad92555204651eff2b9d4e00",
"assets/assets/images/search/indie.webp": "1c12e450d2b68b7d9b3b51dc6277d230",
"assets/assets/images/search/top.webp": "4718405d3960a2cc8cdc384a02ddf5e9",
"assets/assets/images/search/jazz.webp": "ee274c00daa2dbf3c9aa94215abb5ae8",
"assets/assets/images/search/radio.webp": "8023958e5dcfcc23e9703773a8e16b94",
"assets/assets/images/search/klasik.webp": "5714eff0be5a370f2cd16e5a38fa17d5",
"assets/assets/images/search/hits.webp": "544d11176fe58dbc5b65378b6fbf6771",
"assets/assets/4.jpg": "fdecab536f51e09d6bd27f8afb954672",
"assets/assets/3.jpg": "6684a79c99c8bfce994d8f6fc13bf8c3",
"assets/assets/play_store_512.png": "bad4efdec930ad39f2a9da98e5b39263",
"assets/assets/loading.jpg": "6a6b2ad89076fb8d650b4c884d443aae",
"assets/assets/1.jpg": "0429f4b62ab76561aed610555ff1f570",
"assets/assets/logo.jpg": "c227cd544f48c5be4bc32af240f56a27",
"assets/assets/logo.png": "d6be96f0b6e0d8af85b1b4a566d4039c",
"assets/assets/5.jpg": "e2aff547f1a2b1ba34c1e3ece3b4d556",
"assets/assets/2.jpg": "2f2553af3326e3ff230f7c4485c8e960",
"assets/fonts/MaterialIcons-Regular.otf": "a411c39ce77f321aa2f0ef730baf593b",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "d64e64e4b899420072c6422e6ed3488f",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/AssetManifest.json": "77ccbf2f95bbf0047e3162c5209a5060",
"assets/AssetManifest.bin": "4a8dc4ad2419a0bae91683a4a75fd4af",
"assets/FontManifest.json": "6168cb1eccf2911126292f6ecc1bcdfc",
"assets/AssetManifest.bin.json": "cde6f8f9a4ac4cf478c35dd4b6ec4258",
"assets/NOTICES": "8fc0b53e8a848bf3a5bd61d3d85dfa17",
"canvaskit/canvaskit.js": "728b2d477d9b8c14593d4f9b82b484f3",
"canvaskit/canvaskit.js.symbols": "27361387bc24144b46a745f1afe92b50",
"canvaskit/canvaskit.wasm": "a37f2b0af4995714de856e21e882325c",
"canvaskit/chromium/canvaskit.js": "8191e843020c832c9cf8852a4b909d4c",
"canvaskit/chromium/canvaskit.js.symbols": "f7c5e5502d577306fb6d530b1864ff86",
"canvaskit/chromium/canvaskit.wasm": "c054c2c892172308ca5a0bd1d7a7754b",
"canvaskit/skwasm.js": "ea559890a088fe28b4ddf70e17e60052",
"canvaskit/skwasm.js.symbols": "9fe690d47b904d72c7d020bd303adf16",
"canvaskit/skwasm.wasm": "1c93738510f202d9ff44d36a4760126b",
"flutter.js": "83d881c1dbb6d6bcd6b42e274605b69c",
"flutter_bootstrap.js": "5401fd4e4ba093dcd97ab844e8f87d8c",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "5112c730c01b9071ddae45678afeadeb",
"/": "5112c730c01b9071ddae45678afeadeb",
"version.json": "91bfc33a595f3f4f74ba10c533485f54",
"main.dart.js": "977ce45b9c22b92d954a4c66f3557985",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"manifest.json": "492df3fe982711f271d36261e2706113"};
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
