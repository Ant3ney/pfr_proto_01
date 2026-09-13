import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const workerPath = new URL(
	'../../addons/plain_http_lan_web/pfr_cache_service_worker.js',
	import.meta.url,
);

function digest(bytes) {
	return createHash('sha256').update(bytes).digest('hex');
}

function makeManifest(bytes, chunkSize) {
	const chunks = [];
	for (let start = 0; start < bytes.length; start += chunkSize) {
		chunks.push(digest(bytes.subarray(start, Math.min(start + chunkSize, bytes.length))));
	}
	return {
		schemaVersion: 1,
		chunkSize,
		assets: {
			'index.pck': {
				hash: digest(bytes),
				size: bytes.length,
				mimeType: 'application/octet-stream',
				chunkSize,
				chunks,
			},
		},
	};
}

function keyUrl(key) {
	return typeof key === 'string' ? key : key.url;
}

class FakeCache {
	constructor(options) {
		this.options = options;
		this.entries = new Map();
	}

	async match(key) {
		const entry = this.entries.get(keyUrl(key));
		if (!entry) {
			return undefined;
		}
		return new Response(entry.body.slice(), {
			status: entry.status,
			statusText: entry.statusText,
			headers: entry.headers,
		});
	}

	async put(key, response) {
		if (this.options.rejectCacheWrites) {
			throw new DOMException('Quota exceeded', 'QuotaExceededError');
		}
		const body = new Uint8Array(await response.arrayBuffer());
		this.entries.set(keyUrl(key), {
			body,
			status: response.status,
			statusText: response.statusText,
			headers: Array.from(response.headers.entries()),
		});
	}

	async delete(key) {
		if (this.options.rejectCacheDeletes) {
			return false;
		}
		return this.entries.delete(keyUrl(key));
	}
}

class FakeCacheStorage {
	constructor(options) {
		this.options = options;
		this.caches = new Map();
	}

	async open(name) {
		if (this.options.rejectCacheOpen) {
			throw new DOMException('Cache disabled', 'SecurityError');
		}
		if (!this.caches.has(name)) {
			this.caches.set(name, new FakeCache(this.options));
		}
		return this.caches.get(name);
	}

	async keys() {
		return Array.from(this.caches.keys());
	}

	async delete(name) {
		return this.caches.delete(name);
	}
}

function makeNetwork(bytes, options, calls) {
	return async function networkFetch(request) {
		if (options.throwNetworkError) {
			throw new TypeError('Network connection changed');
		}
		const range = request.headers.get('range');
		const match = /^bytes=(\d+)-(\d+)$/.exec(range || '');
		assert.ok(match, 'worker must issue an explicit byte range');
		const start = Number(match[1]);
		const end = Number(match[2]);
		calls.push({ start, end });

		if (options.httpStatus) {
			return new Response('failed', { status: options.httpStatus });
		}
		if (options.ignoreRanges) {
			return new Response(bytes.slice(), {
				status: 200,
				headers: {
					'content-length': String(bytes.length),
					'content-type': 'application/octet-stream',
				},
			});
		}

		let body = bytes.slice(start, end + 1);
		const headers = {
			'content-length': String(end - start + 1),
			'content-range': options.invalidRange
				? `bytes ${start + 1}-${end}/${bytes.length}`
				: `bytes ${start}-${end}/${bytes.length}`,
			'content-type': 'application/octet-stream',
		};
		if (options.truncateRange) {
			body = body.subarray(0, Math.max(0, body.length - 1));
		}
		if (Number.isInteger(options.interruptAt)
				&& !options.interruptionUsed
				&& options.interruptAt >= start
				&& options.interruptAt <= end) {
			options.interruptionUsed = true;
			const prefixLength = Math.max(1, options.interruptAt - start);
			const prefix = body.subarray(0, prefixLength);
			const stream = new ReadableStream({
				start(controller) {
					controller.enqueue(prefix);
					controller.error(new TypeError('Socket closed mid-body'));
				},
			});
			return new Response(stream, { status: 206, headers });
		}
		return new Response(body, { status: 206, headers });
	};
}

async function createHarness(bytes, suppliedOptions = {}) {
	const options = { ...suppliedOptions };
	const manifest = makeManifest(bytes, suppliedOptions.chunkSize || 20);
	const workerTemplate = await readFile(workerPath, 'utf8');
	const workerSource = workerTemplate
		.replace('__PFR_CACHE_VERSION__', 'test-build')
		.replace('__PFR_ASSET_MANIFEST__', JSON.stringify(manifest));
	const listeners = new Map();
	const messages = [];
	const calls = [];
	const cacheStorage = new FakeCacheStorage(options);
	const client = { postMessage: (message) => messages.push(message) };
	const self = {
		PFR_ENABLE_TEST_HOOKS: true,
		addEventListener: (type, listener) => listeners.set(type, listener),
		clients: {
			claim: async () => {},
			get: async () => client,
			matchAll: async () => [client],
		},
		crypto: webcrypto,
		location: { origin: 'https://game.test' },
		registration: { scope: 'https://game.test/' },
		skipWaiting: async () => {},
	};
	const quietConsole = {
		error() {},
		log() {},
		warn() {},
	};
	const context = vm.createContext({
		Array,
		DOMException,
		Error,
		Headers,
		Map,
		Number,
		Object,
		Promise,
		ReadableStream,
		Request,
		Response,
		Set,
		String,
		URL,
		Uint8Array,
		caches: cacheStorage,
		console: quietConsole,
		fetch: makeNetwork(bytes, options, calls),
		self,
	});
	new vm.Script(workerSource, { filename: 'pfr-cache-sw.js' }).runInContext(context);
	return {
		api: self.PFR_CACHE_WORKER_TEST_API,
		asset: manifest.assets['index.pck'],
		caches: cacheStorage,
		calls,
		listeners,
		messages,
		options,
	};
}

async function requestAsset(harness) {
	const response = await harness.api.handleResumableAsset(
		new Request('https://game.test/index.pck?v=test-build'),
		'index.pck',
		harness.asset,
		'client-1',
	);
	return new Uint8Array(await response.arrayBuffer());
}

async function expectFailure(harness, code) {
	await assert.rejects(
		requestAsset(harness),
		(error) => error && error.code === code,
	);
}

const sampleBytes = Uint8Array.from({ length: 100 }, (_, index) => (index * 17) % 251);

test('interrupted download resumes at the incomplete chunk and reconstructs exact bytes', async () => {
	const harness = await createHarness(sampleBytes, { interruptAt: 72, chunkSize: 20 });
	await expectFailure(harness, 'stream-interrupted');
	assert.deepEqual(harness.calls, [
		{ start: 0, end: 19 },
		{ start: 20, end: 39 },
		{ start: 40, end: 59 },
		{ start: 60, end: 79 },
	]);
	const cache = await harness.caches.open(
		harness.api.assetCacheName('index.pck', harness.asset),
	);
	assert.equal(cache.entries.size, 3, 'the interrupted chunk must not be cached');
	assert.ok(
		Array.from(cache.entries.values()).every((entry) => entry.status === 200),
		'validated 206 ranges must be normalized before Cache.put',
	);

	const resumed = await requestAsset(harness);
	assert.deepEqual(resumed, sampleBytes);
	assert.deepEqual(harness.calls.slice(4), [
		{ start: 60, end: 79 },
		{ start: 80, end: 99 },
	]);
	assert.equal(
		await harness.api.assetIsReady('index.pck', harness.asset),
		true,
		'a completion marker should exist only after every validated chunk is persisted',
	);
});

test('invalid, truncated, failed, and unreachable ranges surface structured failures', async (t) => {
	await t.test('invalid Content-Range', async () => {
		await expectFailure(await createHarness(sampleBytes, { invalidRange: true }), 'range-invalid');
	});
	await t.test('truncated body', async () => {
		await expectFailure(await createHarness(sampleBytes, { truncateRange: true }), 'range-truncated');
	});
	await t.test('HTTP error', async () => {
		await expectFailure(await createHarness(sampleBytes, { httpStatus: 503 }), 'http-error');
	});
	await t.test('network error', async () => {
		await expectFailure(await createHarness(sampleBytes, { throwNetworkError: true }), 'network-error');
	});
});

test('a corrupt cached chunk alone is deleted and downloaded again', async () => {
	const harness = await createHarness(sampleBytes);
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	const cacheName = harness.api.assetCacheName('index.pck', harness.asset);
	const cache = await harness.caches.open(cacheName);
	const corruptKey = harness.api.cacheKey('index.pck', harness.asset, 'chunk-2');
	const entry = cache.entries.get(corruptKey);
	entry.body[3] ^= 0xff;
	harness.calls.length = 0;

	assert.deepEqual(await requestAsset(harness), sampleBytes);
	assert.deepEqual(harness.calls, [{ start: 40, end: 59 }]);
	await new Promise((resolve) => setImmediate(resolve));
	assert.ok(harness.messages.some((message) => (
		message.type === 'pfr-load-failure'
		&& message.code === 'corrupt-cache'
		&& message.recovered === true
	)));
});

test('quota rejection is nonfatal and downloads continue without persistence', async () => {
	const harness = await createHarness(sampleBytes, { rejectCacheWrites: true });
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	assert.equal(harness.calls.length, 5);
	await new Promise((resolve) => setImmediate(resolve));
	assert.ok(harness.messages.some((message) => message.type === 'pfr-storage-fallback'));
	const firstVisitCalls = harness.calls.length;
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	assert.equal(harness.calls.length, firstVisitCalls + 5);
	assert.equal(await harness.api.assetIsReady('index.pck', harness.asset), false);
});

test('Cache Storage access rejection is nonfatal', async () => {
	const harness = await createHarness(sampleBytes, { rejectCacheOpen: true });
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	assert.equal(harness.calls.length, 5);
	await new Promise((resolve) => setImmediate(resolve));
	assert.ok(harness.messages.some((message) => message.type === 'pfr-storage-fallback'));
});

test('readiness rejects storage that cannot complete the delete probe', async () => {
	const harness = await createHarness(sampleBytes, { rejectCacheDeletes: true });
	const readiness = await harness.api.queryAssetReadiness(['index.pck']);
	assert.deepEqual(JSON.parse(JSON.stringify(readiness)), {
		storageAvailable: false,
		assets: { 'index.pck': false },
	});
});

test('a server that ignores Range uses and caches its full 200 response', async () => {
	const harness = await createHarness(sampleBytes, { ignoreRanges: true });
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	assert.equal(harness.calls.length, 1);
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	assert.equal(harness.calls.length, 1, 'the normalized whole-file fallback should be reused');
});

test('clear request acknowledges and removes only current content-hash asset caches', async () => {
	const harness = await createHarness(sampleBytes);
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	await harness.caches.open('godot-save-data-do-not-delete');
	const currentName = harness.api.assetCacheName('index.pck', harness.asset);
	assert.ok((await harness.caches.keys()).includes(currentName));
	let lifetimePromise;
	let reply;
	harness.listeners.get('message')({
		data: {
			type: 'pfr-clear-asset-cache',
			buildVersion: 'test-build',
			requestId: 'clear-1',
			assets: ['index.pck'],
		},
		ports: [{ postMessage: (message) => { reply = message; } }],
		waitUntil(value) {
			lifetimePromise = value;
		},
	});
	await lifetimePromise;
	assert.deepEqual(JSON.parse(JSON.stringify(reply)), {
		type: 'pfr-clear-asset-cache-result',
		requestId: 'clear-1',
		buildVersion: 'test-build',
		ok: true,
		assets: ['index.pck'],
	});
	assert.equal((await harness.caches.keys()).includes(currentName), false);
	assert.ok((await harness.caches.keys()).includes('godot-save-data-do-not-delete'));
});

test('readiness query probes storage and reports completion by requested asset', async () => {
	const harness = await createHarness(sampleBytes);
	let lifetimePromise;
	let reply;
	const postQuery = async (requestId) => {
		harness.listeners.get('message')({
			data: {
				type: 'pfr-query-asset-readiness',
				buildVersion: 'test-build',
				requestId,
				assets: ['index.pck'],
			},
			ports: [{ postMessage: (message) => { reply = message; } }],
			waitUntil(value) {
				lifetimePromise = value;
			},
		});
		await lifetimePromise;
		return JSON.parse(JSON.stringify(reply));
	};

	assert.deepEqual(await postQuery('ready-0'), {
		type: 'pfr-query-asset-readiness-result',
		requestId: 'ready-0',
		buildVersion: 'test-build',
		storageAvailable: true,
		assets: { 'index.pck': false },
	});
	assert.deepEqual(await requestAsset(harness), sampleBytes);
	assert.deepEqual(await postQuery('ready-1'), {
		type: 'pfr-query-asset-readiness-result',
		requestId: 'ready-1',
		buildVersion: 'test-build',
		storageAvailable: true,
		assets: { 'index.pck': true },
	});
});

test('an interrupted stream never writes a false completion marker', async () => {
	const harness = await createHarness(sampleBytes, { interruptAt: 52, chunkSize: 20 });
	await expectFailure(harness, 'stream-interrupted');
	assert.equal(await harness.api.assetIsReady('index.pck', harness.asset), false);
	const cache = await harness.caches.open(
		harness.api.assetCacheName('index.pck', harness.asset),
	);
	assert.equal(
		cache.entries.has(harness.api.completionMarkerKey('index.pck', harness.asset)),
		false,
	);
});

test('scoped clearing preserves other current asset caches', async () => {
	const harness = await createHarness(sampleBytes);
	const otherAsset = { ...harness.asset, hash: 'b'.repeat(64) };
	const otherName = harness.api.assetCacheName('index.wasm', otherAsset);
	await harness.caches.open(otherName);
	await requestAsset(harness);
	await harness.api.clearCurrentAssetCaches(['index.pck']);
	const names = await harness.caches.keys();
	assert.equal(names.includes(harness.api.assetCacheName('index.pck', harness.asset)), false);
	assert.equal(names.includes(otherName), true);
});

test('a stale controller bypasses assets from a different build version', async () => {
	const harness = await createHarness(sampleBytes);
	let responsePromise = null;
	harness.listeners.get('fetch')({
		clientId: 'client-1',
		request: new Request('https://game.test/index.pck?v=next-build'),
		respondWith(value) {
			responsePromise = value;
		},
	});
	assert.equal(responsePromise, null);
	assert.equal(harness.calls.length, 0);
});
