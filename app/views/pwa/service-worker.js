// Tu Do service worker: makes the app installable and shows a friendly page when
// there is no connection. Pages are always fetched from the network (the data is
// personal and changes often), so nothing private is cached.
const CACHE = "tudo-offline-v3"
const OFFLINE_URL = "/offline.html"
const STATIC = [OFFLINE_URL, "/tudo-icon-192.png"]

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(STATIC)))
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
  )
  self.clients.claim()
})

// Page navigations: network first; offline → the cached "Sem ligação" page.
self.addEventListener("fetch", (event) => {
  if (event.request.mode !== "navigate") return
  event.respondWith(fetch(event.request).catch(() => caches.match(OFFLINE_URL)))
})
