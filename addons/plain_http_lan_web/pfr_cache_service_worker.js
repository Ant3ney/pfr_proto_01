// The Netlify build replaces these tokens after exporting the game.
const CACHE_VERSION = '__PFR_CACHE_VERSION__';
const PFR_ASSET_MANIFEST = __PFR_ASSET_MANIFEST__;

const CACHE_PREFIX = 'pfr-web-';
const SHELL_CACHE_PREFIX = `${CACHE_PREFIX}shell-`;
const CHUNK_CACHE_PREFIX = `${CACHE_PREFIX}chunks-`;
const SHELL_CACHE_NAME = `${SHELL_CACHE_PREFIX}${CACHE_VERSION}`;
const STORAGE_PROBE_CACHE_NAME = `${CACHE_PREFIX}probe-${CACHE_VERSION}`;
const CACHEABLE_SHELL_FILES = new Set([
	'index.js',
	'index.audio.worklet.js',
	'index.audio.position.worklet.js',
]);

class PFRAssetError extends Error {
	constructor(code, message, details = {}) {
		super(message);
		this.name = 'PFRAssetError';
		this.code = code;
		Object.assign(this, details);
	}
}

function validateManifest(manifest) {
	if (!manifest || manifest.schemaVersion !== 1 || !Number.isSafeInteger(manifest.chunkSize)
			|| manifest.chunkSize <= 0 || !manifest.assets) {
		throw new Error('[PFR cache] Invalid generated asset manifest.');
	}
	for (const [fileName, asset] of Object.entries(manifest.assets)) {
		const expectedChunks = Math.ceil(asset.size / manifest.chunkSize);
		if (!fileName || !Number.isSafeInteger(asset.size) || asset.size <= 0
				|| asset.chunkSize !== manifest.chunkSize || typeof asset.mimeType !== 'string'
				|| !/^[0-9a-f]{64}$/.test(asset.hash) || !Array.isArray(asset.chunks)
				|| asset.chunks.length !== expectedChunks
				|| asset.chunks.some((digest) => !/^[0-9a-f]{64}$/.test(digest))) {
			throw new Error(`[PFR cache] Invalid manifest entry for ${fileName}.`);
		}
	}
}

validateManifest(PFR_ASSET_MANIFEST);
const RESUMABLE_ASSETS = new Map(Object.entries(PFR_ASSET_MANIFEST.assets));

function assetCacheName(fileName, asset) {
	const safeName = fileName.replace(/[^a-z0-9.-]/gi, '_');
	return `${CHUNK_CACHE_PREFIX}${safeName}-${asset.hash}`;
}

function cacheKey(fileName, asset, suffix) {
	const scope = self.registration && self.registration.scope
		? self.registration.scope
		: `${self.location.origin}/`;
	return new URL(
		`.pfr-cache/${encodeURIComponent(fileName)}/${asset.hash}/${suffix}`,
		scope,
	).href;
}

function completionMarkerKey(fileName, asset) {
	return cacheKey(fileName, asset, 'complete');
}

function chunkBounds(asset, index) {
	const start = index * asset.chunkSize;
	const end = Math.min(start + asset.chunkSize, asset.size) - 1;
	return { start, end, length: end - start + 1 };
}

async function postToClient(clientId, message) {
	try {
		let client = clientId ? await self.clients.get(clientId) : null;
		if (!client) {
			const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
			client = clients[0] || null;
		}
		if (client) {
			client.postMessage({ buildVersion: CACHE_VERSION, ...message });
		}
	} catch (error) {
		console.warn('[PFR cache] Could not report worker activity:', error);
	}
}

function reportActivity(clientId, assetName, loaded, total, source, phase = 'download') {
	void postToClient(clientId, {
		type: 'pfr-download-activity',
		asset: assetName,
		loaded,
		total,
		source,
		phase,
	});
}

function reportFailure(clientId, error, recovered = false) {
	console.error('[PFR cache]', error);
	void postToClient(clientId, {
		type: 'pfr-load-failure',
		code: error.code || 'network-error',
		asset: error.asset || null,
		status: error.status || null,
		message: error.message || String(error),
		recovered,
	});
}

function createStorageState(clientId) {
	return {
		cache: null,
		writable: true,
		reported: false,
		markUnavailable(error) {
			this.writable = false;
			if (this.reported) {
				return;
			}
			this.reported = true;
			console.warn('[PFR cache] Resumable storage is unavailable; continuing from the network.', error);
			void postToClient(clientId, {
				type: 'pfr-storage-fallback',
				code: 'storage-unavailable',
				message: error && error.message ? error.message : String(error),
			});
		},
	};
}

async function openAssetCache(fileName, asset, storage) {
	try {
		storage.cache = await caches.open(assetCacheName(fileName, asset));
	} catch (error) {
		storage.markUnavailable(error);
	}
	return storage.cache;
}

async function sha256Hex(bytes) {
	if (!self.crypto || !self.crypto.subtle) {
		return null;
	}
	const digest = await self.crypto.subtle.digest('SHA-256', bytes);
	return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, '0')).join('');
}

async function deleteCacheEntry(cache, key, storage) {
	if (!cache) {
		return;
	}
	try {
		await cache.delete(key);
	} catch (error) {
		storage.markUnavailable(error);
	}
}

async function getCachedChunk(cache, fileName, asset, index, clientId, storage) {
	if (!cache) {
		return null;
	}
	const key = cacheKey(fileName, asset, `chunk-${index}`);
	let response;
	try {
		response = await cache.match(key);
	} catch (error) {
		storage.markUnavailable(error);
		return null;
	}
	if (!response) {
		await deleteCacheEntry(cache, completionMarkerKey(fileName, asset), storage);
		return null;
	}

	const bounds = chunkBounds(asset, index);
	try {
		if (response.status !== 200
				|| response.headers.get('x-pfr-asset-hash') !== asset.hash
				|| response.headers.get('x-pfr-chunk-index') !== String(index)
				|| response.headers.get('x-pfr-chunk-start') !== String(bounds.start)
				|| response.headers.get('x-pfr-chunk-end') !== String(bounds.end)
				|| response.headers.get('x-pfr-total-size') !== String(asset.size)
				|| response.headers.get('x-pfr-chunk-sha256') !== asset.chunks[index]) {
			throw new PFRAssetError('corrupt-cache', `Saved ${fileName} chunk ${index} has invalid metadata.`, {
				asset: fileName,
			});
		}
		const bytes = new Uint8Array(await response.arrayBuffer());
		if (bytes.byteLength !== bounds.length) {
			throw new PFRAssetError('corrupt-cache', `Saved ${fileName} chunk ${index} is truncated.`, {
				asset: fileName,
			});
		}
		const digest = await sha256Hex(bytes);
		if (digest !== null && digest !== asset.chunks[index]) {
			throw new PFRAssetError('corrupt-cache', `Saved ${fileName} chunk ${index} failed its integrity check.`, {
				asset: fileName,
			});
		}
		return bytes;
	} catch (error) {
		const failure = error instanceof PFRAssetError
			? error
			: new PFRAssetError('corrupt-cache', `Saved ${fileName} chunk ${index} could not be read.`, {
				asset: fileName,
				cause: error,
			});
		await deleteCacheEntry(cache, key, storage);
		await deleteCacheEntry(cache, completionMarkerKey(fileName, asset), storage);
		reportFailure(clientId, failure, true);
		return null;
	}
}

async function storeChunk(cache, fileName, asset, index, bytes, storage) {
	if (!cache || !storage.writable) {
		return false;
	}
	const bounds = chunkBounds(asset, index);
	const headers = new Headers({
		'content-length': String(bounds.length),
		'content-type': asset.mimeType,
		'x-pfr-asset-hash': asset.hash,
		'x-pfr-chunk-index': String(index),
		'x-pfr-chunk-start': String(bounds.start),
		'x-pfr-chunk-end': String(bounds.end),
		'x-pfr-total-size': String(asset.size),
		'x-pfr-chunk-sha256': asset.chunks[index],
	});
	try {
		// Cache Storage rejects 206 responses. Persist a normalized, validated 200.
		await cache.put(
			cacheKey(fileName, asset, `chunk-${index}`),
			new Response(bytes, { status: 200, headers }),
		);
		return true;
	} catch (error) {
		storage.markUnavailable(error);
		return false;
	}
}

async function writeCompletionMarker(cache, fileName, asset, storage, persistedChunks) {
	if (!cache || !storage.writable || !self.crypto || !self.crypto.subtle
			|| persistedChunks.size !== asset.chunks.length) {
		return false;
	}
	const headers = new Headers({
		'content-type': 'application/json',
		'x-pfr-asset-complete': '1',
		'x-pfr-asset-hash': asset.hash,
		'x-pfr-total-size': String(asset.size),
		'x-pfr-chunk-count': String(asset.chunks.length),
	});
	try {
		await cache.put(
			completionMarkerKey(fileName, asset),
			new Response(JSON.stringify({ hash: asset.hash, size: asset.size }), {
				status: 200,
				headers,
			}),
		);
		return true;
	} catch (error) {
		storage.markUnavailable(error);
		return false;
	}
}

async function assetIsReady(fileName, asset) {
	try {
		const cache = await caches.open(assetCacheName(fileName, asset));
		const marker = await cache.match(completionMarkerKey(fileName, asset));
		const markerIsValid = Boolean(marker
			&& marker.status === 200
			&& marker.headers.get('x-pfr-asset-complete') === '1'
			&& marker.headers.get('x-pfr-asset-hash') === asset.hash
			&& marker.headers.get('x-pfr-total-size') === String(asset.size)
			&& marker.headers.get('x-pfr-chunk-count') === String(asset.chunks.length));
		if (!markerIsValid) {
			return false;
		}
		for (let index = 0; index < asset.chunks.length; index += 1) {
			const bounds = chunkBounds(asset, index);
			const chunk = await cache.match(cacheKey(fileName, asset, `chunk-${index}`));
			if (!chunk || chunk.status !== 200
					|| chunk.headers.get('content-length') !== String(bounds.length)
					|| chunk.headers.get('x-pfr-asset-hash') !== asset.hash
					|| chunk.headers.get('x-pfr-chunk-index') !== String(index)
					|| chunk.headers.get('x-pfr-chunk-sha256') !== asset.chunks[index]) {
				await cache.delete(completionMarkerKey(fileName, asset));
				return false;
			}
		}
		return true;
	} catch (error) {
		return false;
	}
}

async function probeCacheStorage() {
	if (!self.crypto || !self.crypto.subtle) {
		return false;
	}
	const key = cacheKey('storage-probe', { hash: CACHE_VERSION }, 'round-trip');
	try {
		const cache = await caches.open(STORAGE_PROBE_CACHE_NAME);
		await cache.put(key, new Response('pfr-cache-probe', { status: 200 }));
		const saved = await cache.match(key);
		if (!saved || await saved.text() !== 'pfr-cache-probe') {
			throw new Error('Cache Storage probe did not round-trip its bytes.');
		}
		if (!await cache.delete(key) || await cache.match(key)) {
			throw new Error('Cache Storage probe could not delete its test entry.');
		}
		if (!await caches.delete(STORAGE_PROBE_CACHE_NAME)) {
			throw new Error('Cache Storage probe could not delete its test cache.');
		}
		return true;
	} catch (error) {
		try {
			await caches.delete(STORAGE_PROBE_CACHE_NAME);
		} catch (_cleanupError) {
			// The failed probe is already authoritative.
		}
		return false;
	}
}

async function queryAssetReadiness(assetNames) {
	const requested = Array.isArray(assetNames)
		? [...new Set(assetNames.filter((name) => RESUMABLE_ASSETS.has(name)))]
		: [...RESUMABLE_ASSETS.keys()];
	const storageAvailable = await probeCacheStorage();
	const readiness = {};
	for (const fileName of requested) {
		readiness[fileName] = storageAvailable
			? await assetIsReady(fileName, RESUMABLE_ASSETS.get(fileName))
			: false;
	}
	return { storageAvailable, assets: readiness };
}

function parseContentRange(headerValue) {
	const match = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(headerValue || '');
	if (!match) {
		return null;
	}
	return {
		start: Number(match[1]),
		end: Number(match[2]),
		total: Number(match[3]),
	};
}

function asAssetError(error, code, message, assetName) {
	if (error instanceof PFRAssetError) {
		return error;
	}
	return new PFRAssetError(code, message, { asset: assetName, cause: error });
}

async function readExactResponse(response, expectedLength, onProgress, state, assetName) {
	if (!response.body) {
		throw new PFRAssetError('stream-interrupted', `${assetName} returned no response body.`, {
			asset: assetName,
		});
	}
	const reader = response.body.getReader();
	state.activeReader = reader;
	const pieces = [];
	let received = 0;
	try {
		while (true) {
			const result = await reader.read();
			if (result.done) {
				break;
			}
			if (result.value) {
				const piece = result.value instanceof Uint8Array
					? result.value
					: new Uint8Array(result.value);
				received += piece.byteLength;
				if (received > expectedLength) {
					throw new PFRAssetError('range-invalid', `${assetName} returned too many bytes for a range.`, {
						asset: assetName,
					});
				}
				pieces.push(piece);
				onProgress(received);
			}
		}
	} catch (error) {
		throw asAssetError(
			error,
			'stream-interrupted',
			`The ${assetName} response stream was interrupted.`,
			assetName,
		);
	} finally {
		if (state.activeReader === reader) {
			state.activeReader = null;
		}
	}

	if (received !== expectedLength) {
		throw new PFRAssetError(
			'range-truncated',
			`${assetName} range was truncated: expected ${expectedLength} bytes, received ${received}.`,
			{ asset: assetName },
		);
	}
	const bytes = new Uint8Array(expectedLength);
	let offset = 0;
	for (const piece of pieces) {
		bytes.set(piece, offset);
		offset += piece.byteLength;
	}
	return bytes;
}

async function fetchRange(request, fileName, asset, index, clientId, state) {
	const bounds = chunkBounds(asset, index);
	const headers = new Headers(request.headers);
	headers.set('range', `bytes=${bounds.start}-${bounds.end}`);
	let response;
	try {
		response = await fetch(new Request(request, { headers, cache: 'no-store' }));
	} catch (error) {
		throw new PFRAssetError('network-error', `Could not download ${fileName}.`, {
			asset: fileName,
			cause: error,
		});
	}

	if (response.status === 200) {
		const contentLength = response.headers.get('content-length');
		if (contentLength !== null && Number(contentLength) !== asset.size) {
			throw new PFRAssetError(
				'range-invalid',
				`${fileName} ignored byte ranges and returned an unexpected full-file size.`,
				{ asset: fileName, status: response.status },
			);
		}
		return { fullResponse: response, bounds };
	}
	if (response.status !== 206) {
		throw new PFRAssetError(
			'http-error',
			`Downloading ${fileName} failed with HTTP ${response.status}.`,
			{ asset: fileName, status: response.status },
		);
	}

	const contentRange = parseContentRange(response.headers.get('content-range'));
	const contentLength = response.headers.get('content-length');
	if (!contentRange || contentRange.start !== bounds.start || contentRange.end !== bounds.end
			|| contentRange.total !== asset.size
			|| (contentLength !== null && Number(contentLength) !== bounds.length)) {
		throw new PFRAssetError('range-invalid', `${fileName} returned an invalid byte range.`, {
			asset: fileName,
			status: response.status,
		});
	}

	const bytes = await readExactResponse(
		response,
		bounds.length,
		(received) => reportActivity(
			clientId,
			fileName,
			bounds.start + received,
			asset.size,
			'network',
		),
		state,
		fileName,
	);
	const digest = await sha256Hex(bytes);
	if (digest !== null && digest !== asset.chunks[index]) {
		throw new PFRAssetError('integrity-failure', `${fileName} chunk ${index} failed its integrity check.`, {
			asset: fileName,
		});
	}
	return { bytes, bounds };
}

function wholeResponseHeaders(asset, sourceHeaders) {
	const headers = new Headers(sourceHeaders || undefined);
	headers.set('content-type', asset.mimeType);
	headers.set('content-length', String(asset.size));
	headers.set('accept-ranges', 'bytes');
	headers.set('x-pfr-asset-hash', asset.hash);
	headers.set('x-pfr-total-size', String(asset.size));
	return headers;
}

function beginWholeFallback(response, cache, fileName, asset, storage, state, skipBytes, source) {
	if (!response.body) {
		throw new PFRAssetError('stream-interrupted', `${fileName} returned no response body.`, {
			asset: fileName,
		});
	}
	state.whole = {
		reader: response.body.getReader(),
		received: 0,
		emitted: skipBytes,
		skip: skipBytes,
		source,
		chunkIndex: 0,
		chunkOffset: 0,
		chunkBuffer: new Uint8Array(chunkBounds(asset, 0).length),
	};
	state.activeReader = state.whole.reader;
}

async function validateWholeFallbackBytes(cache, fileName, asset, storage, state, bytes) {
	const whole = state.whole;
	let sourceOffset = 0;
	while (sourceOffset < bytes.byteLength) {
		if (whole.chunkIndex >= asset.chunks.length) {
			throw new PFRAssetError('range-invalid', `${fileName} full response exceeded its manifest chunks.`, {
				asset: fileName,
			});
		}
		const remaining = whole.chunkBuffer.byteLength - whole.chunkOffset;
		const take = Math.min(remaining, bytes.byteLength - sourceOffset);
		whole.chunkBuffer.set(bytes.subarray(sourceOffset, sourceOffset + take), whole.chunkOffset);
		whole.chunkOffset += take;
		sourceOffset += take;
		if (whole.chunkOffset !== whole.chunkBuffer.byteLength) {
			continue;
		}
		const digest = await sha256Hex(whole.chunkBuffer);
		if (digest === null || digest !== asset.chunks[whole.chunkIndex]) {
			throw new PFRAssetError(
				'integrity-failure',
				`${fileName} chunk ${whole.chunkIndex} failed its integrity check.`,
				{ asset: fileName },
			);
		}
		if (await storeChunk(cache, fileName, asset, whole.chunkIndex, whole.chunkBuffer, storage)) {
			state.persistedChunks.add(whole.chunkIndex);
		}
		whole.chunkIndex += 1;
		whole.chunkOffset = 0;
		if (whole.chunkIndex < asset.chunks.length) {
			whole.chunkBuffer = new Uint8Array(chunkBounds(asset, whole.chunkIndex).length);
		}
	}
}

async function pumpWholeFallback(controller, cache, fileName, asset, storage, state, clientId) {
	const whole = state.whole;
	try {
		while (true) {
			const result = await whole.reader.read();
			if (result.done) {
				if (whole.received !== asset.size || whole.emitted !== asset.size
						|| whole.chunkIndex !== asset.chunks.length || whole.chunkOffset !== 0) {
					throw new PFRAssetError(
						'range-truncated',
						`${fileName} full response was truncated at ${whole.received} of ${asset.size} bytes.`,
						{ asset: fileName },
					);
				}
				await writeCompletionMarker(
					cache,
					fileName,
					asset,
					storage,
					state.persistedChunks,
				);
				state.activeReader = null;
				state.whole = null;
				reportActivity(clientId, fileName, asset.size, asset.size, whole.source, 'complete');
				controller.close();
				return;
			}

			let bytes = result.value instanceof Uint8Array
				? result.value
				: new Uint8Array(result.value);
			whole.received += bytes.byteLength;
			if (whole.received > asset.size) {
				throw new PFRAssetError('range-invalid', `${fileName} full response exceeded its manifest size.`, {
					asset: fileName,
				});
			}
			await validateWholeFallbackBytes(cache, fileName, asset, storage, state, bytes);
			if (whole.skip > 0) {
				const discarded = Math.min(whole.skip, bytes.byteLength);
				whole.skip -= discarded;
				bytes = bytes.subarray(discarded);
			}
			reportActivity(
				clientId,
				fileName,
				Math.max(whole.emitted, whole.received),
				asset.size,
				whole.source,
			);
			if (bytes.byteLength > 0) {
				whole.emitted += bytes.byteLength;
				controller.enqueue(bytes);
				return;
			}
		}
	} catch (error) {
		await deleteCacheEntry(cache, completionMarkerKey(fileName, asset), storage);
		throw asAssetError(
			error,
			'stream-interrupted',
			`The ${fileName} full response stream was interrupted.`,
			fileName,
		);
	}
}

async function handleResumableAsset(request, fileName, asset, clientId) {
	const storage = createStorageState(clientId);
	const cache = await openAssetCache(fileName, asset, storage);
	const state = {
		activeReader: null,
		cancelled: false,
		index: 0,
		persistedChunks: new Set(),
		whole: null,
	};

	const body = new ReadableStream({
		async pull(controller) {
			if (state.cancelled) {
				return;
			}
			try {
				if (state.whole) {
					await pumpWholeFallback(controller, cache, fileName, asset, storage, state, clientId);
					return;
				}
				if (state.index >= asset.chunks.length) {
					await writeCompletionMarker(
						cache,
						fileName,
						asset,
						storage,
						state.persistedChunks,
					);
					reportActivity(clientId, fileName, asset.size, asset.size, 'cache', 'complete');
					controller.close();
					return;
				}

				const index = state.index;
				const bounds = chunkBounds(asset, index);
				let bytes = await getCachedChunk(cache, fileName, asset, index, clientId, storage);
				let source = 'cache';
				if (bytes) {
					state.persistedChunks.add(index);
				}
				if (!bytes) {
					source = 'network';
					const downloaded = await fetchRange(request, fileName, asset, index, clientId, state);
					if (downloaded.fullResponse) {
						void postToClient(clientId, {
							type: 'pfr-range-fallback',
							asset: fileName,
							code: 'range-unsupported',
						});
						beginWholeFallback(
							downloaded.fullResponse,
							cache,
							fileName,
							asset,
							storage,
							state,
							bounds.start,
							'network',
						);
						await pumpWholeFallback(controller, cache, fileName, asset, storage, state, clientId);
						return;
					}
					bytes = downloaded.bytes;
					if (await storeChunk(cache, fileName, asset, index, bytes, storage)) {
						state.persistedChunks.add(index);
					}
				}

				state.index += 1;
				reportActivity(clientId, fileName, bounds.end + 1, asset.size, source);
				controller.enqueue(bytes);
			} catch (error) {
				if (state.cancelled) {
					return;
				}
				const failure = asAssetError(
					error,
					'network-error',
					`Loading ${fileName} failed.`,
					fileName,
				);
				reportFailure(clientId, failure, false);
				controller.error(failure);
			}
		},
		async cancel(reason) {
			state.cancelled = true;
			if (state.activeReader) {
				try {
					await state.activeReader.cancel(reason);
				} catch (error) {
					console.warn('[PFR cache] Could not cancel asset reader:', error);
				}
			}
		},
	});

	return new Response(body, {
		status: 200,
		headers: wholeResponseHeaders(asset),
	});
}

async function handleShellAsset(request, fileName, clientId) {
	let cache = null;
	try {
		cache = await caches.open(SHELL_CACHE_NAME);
		const cached = await cache.match(request);
		if (cached) {
			return cached;
		}
	} catch (error) {
		console.warn('[PFR cache] Shell cache unavailable:', error);
		void postToClient(clientId, {
			type: 'pfr-storage-fallback',
			code: 'storage-unavailable',
			message: error.message || String(error),
		});
	}

	const response = await fetch(request);
	if (cache && response.ok) {
		try {
			await cache.put(request, response.clone());
		} catch (error) {
			console.warn(`[PFR cache] Could not persist ${fileName}:`, error);
			void postToClient(clientId, {
				type: 'pfr-storage-fallback',
				code: 'storage-unavailable',
				message: error.message || String(error),
			});
		}
	}
	return response;
}

async function removeOldAssetCaches() {
	const keep = new Set([SHELL_CACHE_NAME]);
	for (const [fileName, asset] of RESUMABLE_ASSETS) {
		keep.add(assetCacheName(fileName, asset));
	}
	try {
		const names = await caches.keys();
		await Promise.all(names
			.filter((name) => name.startsWith(CACHE_PREFIX) && !keep.has(name))
			.map((name) => caches.delete(name)));
	} catch (error) {
		console.warn('[PFR cache] Could not prune old asset caches:', error);
	}
}

async function clearCurrentAssetCaches(assetNames = null) {
	const requested = Array.isArray(assetNames)
		? [...new Set(assetNames.filter((name) => RESUMABLE_ASSETS.has(name)))]
		: [...RESUMABLE_ASSETS.keys()];
	await Promise.all(requested.map((fileName) => (
		caches.delete(assetCacheName(fileName, RESUMABLE_ASSETS.get(fileName)))
	)));
	return requested;
}

self.addEventListener('install', (event) => {
	event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		await removeOldAssetCaches();
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
	const asset = RESUMABLE_ASSETS.get(fileName);
	const requestedVersion = url.searchParams.get('v');
	if (asset && requestedVersion && requestedVersion !== CACHE_VERSION) {
		// A newly deployed page can briefly remain controlled by the previous
		// worker. Let that request use the ordinary network path instead of
		// reconstructing it with a stale manifest.
		return;
	}
	if (asset && !request.headers.has('range')) {
		event.respondWith(handleResumableAsset(request, fileName, asset, event.clientId));
		return;
	}
	if (CACHEABLE_SHELL_FILES.has(fileName)) {
		event.respondWith(handleShellAsset(request, fileName, event.clientId));
	}
});

self.addEventListener('message', (event) => {
	const message = event.data || {};
	if (message.buildVersion !== CACHE_VERSION) {
		return;
	}
	const reply = (payload) => {
		if (event.ports && event.ports[0]) {
			event.ports[0].postMessage(payload);
		} else if (event.source) {
			event.source.postMessage(payload);
		}
	};
	if (message.type === 'pfr-query-asset-readiness') {
		event.waitUntil(queryAssetReadiness(message.assets).then(
			(result) => reply({
				type: 'pfr-query-asset-readiness-result',
				requestId: message.requestId,
				buildVersion: CACHE_VERSION,
				storageAvailable: result.storageAvailable,
				assets: result.assets,
			}),
			(error) => reply({
				type: 'pfr-query-asset-readiness-result',
				requestId: message.requestId,
				buildVersion: CACHE_VERSION,
				storageAvailable: false,
				assets: {},
				message: error.message || String(error),
			}),
		));
		return;
	}
	if (message.type !== 'pfr-clear-asset-cache') {
		return;
	}
	event.waitUntil(clearCurrentAssetCaches(message.assets).then(
		(clearedAssets) => reply({
			type: 'pfr-clear-asset-cache-result',
			requestId: message.requestId,
			buildVersion: CACHE_VERSION,
			ok: true,
			assets: clearedAssets,
		}),
		(error) => {
			console.error('[PFR cache] Could not clear current asset chunks:', error);
			reply({
				type: 'pfr-clear-asset-cache-result',
				requestId: message.requestId,
				buildVersion: CACHE_VERSION,
				ok: false,
				message: error.message || String(error),
			});
		},
	));
});

if (self.PFR_ENABLE_TEST_HOOKS) {
	self.PFR_CACHE_WORKER_TEST_API = Object.freeze({
		PFRAssetError,
		assetCacheName,
		assetIsReady,
		cacheKey,
		chunkBounds,
		clearCurrentAssetCaches,
		completionMarkerKey,
		handleResumableAsset,
		parseContentRange,
		probeCacheStorage,
		queryAssetReadiness,
	});
}
