import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const shellPath = new URL('../../addons/plain_http_lan_web/plain_http_shell.html', import.meta.url);

async function loadRecoveryApi() {
	const shell = await readFile(shellPath, 'utf8');
	const startMarker = '/* PFR_RECOVERY_API_START */';
	const endMarker = '/* PFR_RECOVERY_API_END */';
	const start = shell.indexOf(startMarker);
	const end = shell.indexOf(endMarker);
	assert.notEqual(start, -1);
	assert.notEqual(end, -1);
	const source = shell.slice(start + startMarker.length, end);
	const window = {
		clearTimeout,
		setTimeout,
	};
	const quietConsole = { error() {}, log() {}, warn() {} };
	const context = vm.createContext({ console: quietConsole, performance, Promise, window });
	new vm.Script(source, { filename: 'plain_http_shell.recovery.js' }).runInContext(context);
	return window.PFRRecovery;
}

test('automatic recovery can be claimed once per build and manual retry resets it', async () => {
	const recovery = await loadRecoveryApi();
	const values = new Map();
	const storage = {
		getItem: (key) => values.get(key) ?? null,
		setItem: (key, value) => values.set(key, value),
		removeItem: (key) => values.delete(key),
	};
	const gate = recovery.createRetryGate(storage, 'pfr-auto-retry:test-build');
	assert.equal(gate.claim(), true);
	assert.equal(gate.claim(), false);
	gate.reset();
	assert.equal(gate.claim(), true);

	const unavailable = recovery.createRetryGate({
		getItem() {
			throw new Error('blocked');
		},
	}, 'pfr-auto-retry:test-build');
	assert.equal(unavailable.claim(), false, 'storage failure must disable automatic reloads');
});

test('download watchdog pauses while hidden or offline and detects a visible silent stall', async () => {
	const recovery = await loadRecoveryApi();
	let currentTime = 0;
	const failures = [];
	const watchdog = recovery.createWatchdog({
		now: () => currentTime,
		downloadLimit: 45000,
		initializationLimit: 120000,
		onTimeout: (code) => failures.push(code),
	});

	currentTime = 44000;
	assert.equal(watchdog.tick(), null);
	watchdog.setPaused(true);
	currentTime = 300000;
	assert.equal(watchdog.tick(), null);
	watchdog.setPaused(false);
	currentTime = 344999;
	assert.equal(watchdog.tick(), null);
	currentTime = 345001;
	assert.equal(watchdog.tick(), 'download-stall');
	assert.deepEqual(failures, ['download-stall']);
});

test('download activity resets the stall clock and initialization has its own 120 second limit', async () => {
	const recovery = await loadRecoveryApi();
	let currentTime = 0;
	const failures = [];
	const watchdog = recovery.createWatchdog({
		now: () => currentTime,
		downloadLimit: 45000,
		initializationLimit: 120000,
		onTimeout: (code) => failures.push(code),
	});
	currentTime = 40000;
	watchdog.tick();
	watchdog.activity();
	currentTime = 80000;
	assert.equal(watchdog.tick(), null);
	watchdog.enterInitialization();
	watchdog.setPaused(true);
	currentTime = 200000;
	watchdog.tick();
	watchdog.setPaused(false);
	currentTime = 319999;
	assert.equal(watchdog.tick(), null);
	currentTime = 320001;
	assert.equal(watchdog.tick(), 'initialization-timeout');
	assert.deepEqual(failures, ['initialization-timeout']);
});

test('service worker setup has a bounded fallback and failure messages are actionable', async () => {
	const recovery = await loadRecoveryApi();
	const never = new Promise(() => {});
	assert.equal(await recovery.withTimeout(never, 5, false), false);
	const corrupt = recovery.classifyFailure(
		new Error('bad bytes'),
		{ code: 'integrity-failure' },
		true,
	);
	assert.equal(corrupt.canRestart, true);
	assert.equal(corrupt.transient, false);
	const offline = recovery.classifyFailure(new Error('fetch failed'), null, false);
	assert.equal(offline.kind, 'offline');
	const stream = recovery.classifyFailure(
		new Error('stream ended'),
		{ code: 'stream-interrupted' },
		true,
	);
	assert.equal(stream.transient, true);
});
