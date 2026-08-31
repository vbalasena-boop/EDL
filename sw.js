// Service worker Immoscan — "stale-while-revalidate" : on sert instantanément la
// version en cache (ouverture rapide), puis on récupère la dernière version en
// arrière-plan pour la prochaine ouverture. Repli sur le cache hors ligne.
const CACHE = 'edl-cache-v1';

self.addEventListener('install', event => { self.skipWaiting(); });
self.addEventListener('activate', event => { event.waitUntil(self.clients.claim()); });

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const isDoc = req.mode === 'navigate' || req.destination === 'document';
  const isSameOrigin = new URL(req.url).origin === self.location.origin;
  if (!(isDoc || isSameOrigin)) return;

  event.respondWith(
    caches.open(CACHE).then(cache =>
      cache.match(req).then(cached => {
        // Récupération réseau en arrière-plan (met à jour le cache pour la prochaine fois)
        const network = fetch(req)
          .then(res => { if (res && res.ok) cache.put(req, res.clone()).catch(() => {}); return res; })
          .catch(() => cached || cache.match('./'));
        // Réponse instantanée depuis le cache si dispo, sinon on attend le réseau
        return cached || network;
      })
    )
  );
});
