// Service worker EDL IA — stratégie "réseau d'abord" pour toujours servir
// la dernière version quand on est en ligne, avec repli sur le cache hors ligne.
const CACHE = 'edl-cache-v1';

self.addEventListener('install', event => {
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const isDoc = req.mode === 'navigate' || req.destination === 'document';
  const isSameOrigin = new URL(req.url).origin === self.location.origin;

  if (isDoc || isSameOrigin) {
    // Réseau d'abord : on récupère la dernière version, on met à jour le cache,
    // et on retombe sur le cache seulement si le réseau échoue (hors ligne).
    event.respondWith(
      fetch(req)
        .then(res => {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match(req).then(r => r || caches.match('./')))
    );
  }
});
