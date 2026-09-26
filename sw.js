/**
 * QIX Arcade Game - Progressive Web App Service Worker
 * Provides offline gameplay, instant asset caching, background updates, and resilience.
 */

const CACHE_NAME = 'qix-arcade-v9';

const PRECACHE_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './css/style.css',
  './js/security.js',
  './js/audio.js',
  './js/grid.js',
  './js/qix.js',
  './js/sparx.js',
  './js/player.js',
  './js/progression.js',
  './js/game.js',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable.png',
  './icons/icon.svg',
  './icons/screenshot-desktop.png',
  './icons/screenshot-mobile.png',
  './level-images/manifest.json'
];

// Install: Pre-cache core game files and skip waiting immediately
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      console.log('[ServiceWorker] Pre-caching v5 arcade bundle...');
      await Promise.allSettled(
        PRECACHE_ASSETS.map(async (url) => {
          try {
            const response = await fetch(url, { cache: 'no-cache' });
            if (response.ok) {
              await cache.put(url, response);
            }
          } catch (err) {
            console.warn('[ServiceWorker] Could not pre-cache asset:', url, err);
          }
        })
      );
      return self.skipWaiting();
    })
  );
});

// Activate: Purge all stale caches and claim clients immediately
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('[ServiceWorker] Purging legacy cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Client communication: Force skip waiting on demand
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

// Fetch Strategy:
// - Code & Data (HTML, JS, CSS, JSON): Network-First (always fresh when online, fallback to cache when offline)
// - Google Fonts: Cache-first with background revalidation (opaque response support)
// - Media Assets (Images, Icons): Cache-First / Stale-While-Revalidate with search query tolerance
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  if (!url.protocol.startsWith('http')) return;

  // 1. Google Fonts & CDN assets
  if (url.hostname.includes('fonts.googleapis.com') || url.hostname.includes('fonts.gstatic.com')) {
    event.respondWith(
      caches.open(CACHE_NAME).then(async (cache) => {
        const cachedResponse = await cache.match(event.request);
        if (cachedResponse) return cachedResponse;

        try {
          const networkResponse = await fetch(event.request);
          if (networkResponse && (networkResponse.status === 200 || networkResponse.type === 'opaque')) {
            cache.put(event.request, networkResponse.clone());
          }
          return networkResponse;
        } catch (err) {
          return cachedResponse || Promise.reject(err);
        }
      })
    );
    return;
  }

  // 2. Code & Data requests: Network-First (prevents stale code/manifests while online)
  const isCodeOrData = event.request.mode === 'navigate' ||
                       url.pathname.endsWith('.html') ||
                       url.pathname.endsWith('.js') ||
                       url.pathname.endsWith('.json') ||
                       url.pathname.endsWith('.css');

  if (isCodeOrData) {
    event.respondWith(
      (async () => {
        try {
          // Attempt network fetch with 2s timeout
          const networkPromise = fetch(event.request, { cache: 'no-cache' });
          const timeoutPromise = new Promise((_, reject) =>
            setTimeout(() => reject(new Error('Network timeout')), 2000)
          );

          const networkResponse = await Promise.race([networkPromise, timeoutPromise]);
          if (networkResponse && networkResponse.status === 200) {
            const cache = await caches.open(CACHE_NAME);
            cache.put(event.request, networkResponse.clone());
            return networkResponse;
          }
        } catch (err) {
          // Network failed or offline - fall through to cached version
        }

        // Cache fallback
        const cached = await caches.match(event.request, { ignoreSearch: true });
        if (cached) return cached;

        if (event.request.mode === 'navigate') {
          const fallback = await caches.match('./index.html', { ignoreSearch: true });
          if (fallback) return fallback;
          return caches.match('./', { ignoreSearch: true });
        }

        return Promise.reject(new Error('Offline and not cached'));
      })()
    );
    return;
  }

  // 3. Media Assets (images, icons) - Cache-First with background revalidation
  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cachedResponse = await cache.match(event.request, { ignoreSearch: true });

      const fetchPromise = fetch(event.request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            cache.put(event.request, networkResponse.clone());
          }
          return networkResponse;
        })
        .catch(() => cachedResponse);

      return cachedResponse || fetchPromise;
    })
  );
});
