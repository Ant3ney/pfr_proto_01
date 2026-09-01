// The Netlify build replaces this token with a hash of the exported game files.
const CACHE_VERSION = '__PFR_CACHE_VERSION__';
const CACHE_PREFIX = 'pfr-web-assets-';
const CACHE_NAME = `${CACHE_PREFIX}${CACHE_VERSION}`;
const CACHEABLE_FILES = new Set([
	'index.js',
	'index.pck',
	'index.wasm',
	'index.audio.worklet.js',
	'index.audio.position.worklet.js',
]);

self.addEventListener('install', (event) => {
	// Activate immediately so the first visit can cache the game download that is
	// already about to happen, instead of waiting for another page load.
	event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		const cacheNames = await caches.keys();
		await Promise.all(cacheNames
			.filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME)
			.map((name) => caches.delete(name)));
		await self.clients.claim();
	})());
});

self.addEventListener('fetch', (event) => {
	const request = event.request;
	if (request.method !== 'GET') {
		return;
	}

	const url = new URL(request.url);
	if (url.origin !== self.location.origin) {
		return;
	}

	const fileName = url.pathname.slice(url.pathname.lastIndexOf('/') + 1);
	if (!CACHEABLE_FILES.has(fileName)) {
		// In particular, never cache navigation or index.html here. This ensures a
		// new deployment's HTML and embedded build version are checked every visit.
		return;
	}

	event.respondWith((async () => {
		const cache = await caches.open(CACHE_NAME);
		const cachedResponse = await cache.match(request);
		if (cachedResponse) {
			return cachedResponse;
		}

		const networkResponse = await fetch(request);
		if (networkResponse.ok) {
			const cacheWrite = cache.put(request, networkResponse.clone()).catch((error) => {
				// Storage quota and private-browsing policies can reject large entries.
				// The network response must still reach Godot when caching is unavailable.
				console.warn('[PFR cache] Could not persist asset:', fileName, error);
			});
			event.waitUntil(cacheWrite);
		}
		return networkResponse;
	})());
});
