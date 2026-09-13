import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';

const shellPath = new URL('../../addons/plain_http_lan_web/plain_http_shell.html', import.meta.url);

async function loadBootApi() {
	const shell = await readFile(shellPath, 'utf8');
	const startMarker = '/* PFR_BOOT_API_START */';
	const endMarker = '/* PFR_BOOT_API_END */';
	const start = shell.indexOf(startMarker);
	const end = shell.indexOf(endMarker);
	assert.notEqual(start, -1);
	assert.notEqual(end, -1);
	const source = shell.slice(start + startMarker.length, end);
	const window = {};
	new vm.Script(source, { filename: 'plain_http_shell.boot.js' }).runInNewContext({
		Number,
		Object,
		URL,
		window,
	});
	return { api: window.PFRBoot, shell };
}

function launchOptions(overrides = {}) {
	return {
		buildVersion: 'build-1',
		hasBuildVersion: true,
		productionHttps: true,
		bootRuntimeSupported: true,
		cacheWorkerReady: true,
		storageAvailable: true,
		fullPackReady: false,
		requestedMode: '',
		requestedBuild: '',
		...overrides,
	};
}

test('launch selection uses the boot battle only for a writable production cache miss', async () => {
	const { api } = await loadBootApi();
	assert.equal(api.selectLaunchMode(launchOptions()), 'boot');
	assert.equal(api.selectLaunchMode(launchOptions({ fullPackReady: true })), 'full');
	assert.equal(api.selectLaunchMode(launchOptions({ productionHttps: false })), 'full');
	assert.equal(api.selectLaunchMode(launchOptions({ bootRuntimeSupported: false })), 'full');
	assert.equal(api.selectLaunchMode(launchOptions({ cacheWorkerReady: false })), 'full');
	assert.equal(api.selectLaunchMode(launchOptions({ storageAvailable: false })), 'full');
	assert.equal(api.selectLaunchMode(launchOptions({ hasBuildVersion: false })), 'full');
	assert.equal(api.selectLaunchMode(launchOptions({
		requestedMode: 'game',
		requestedBuild: 'build-1',
	})), 'full');
	assert.equal(api.selectLaunchMode(launchOptions({
		requestedMode: 'game',
		requestedBuild: 'stale-build',
	})), 'boot');
});

test('explicit handoff replaces into the current build and cleans only mode parameters', async () => {
	const { api } = await loadBootApi();
	const handoff = new URL(api.handoffUrl('https://game.test/play?keep=yes#arena', 'build-7'));
	assert.equal(handoff.searchParams.get('keep'), 'yes');
	assert.equal(handoff.searchParams.get('pfr-mode'), 'game');
	assert.equal(handoff.searchParams.get('pfr-build'), 'build-7');
	assert.equal(handoff.hash, '#arena');
	const clean = new URL(api.cleanModeUrl(handoff.href));
	assert.equal(clean.searchParams.get('keep'), 'yes');
	assert.equal(clean.searchParams.has('pfr-mode'), false);
	assert.equal(clean.searchParams.has('pfr-build'), false);
});

test('background progress remains monotonic through retries and reports exact byte units', async () => {
	const { api } = await loadBootApi();
	assert.deepEqual(
		JSON.parse(JSON.stringify(api.monotonicProgress(70, 20, 100))),
		{ loaded: 70, total: 100 },
	);
	assert.deepEqual(
		JSON.parse(JSON.stringify(api.monotonicProgress(70, 140, 100))),
		{ loaded: 100, total: 100 },
	);
	assert.equal(api.formatBytes(8 * 1024 * 1024), '8.0 MiB');
});

test('shell keeps readiness explicit and provides independent recovery controls', async () => {
	const { shell } = await loadBootApi();
	assert.match(shell, /mainPack: bootPack/);
	assert.match(shell, /canvasResizePolicy: 0/);
	assert.match(shell, /window\.devicePixelRatio/);
	assert.match(shell, /const bootPack = 'pfr-loading-battle\.pck'/);
	assert.match(shell, /location\.replace\(window\.PFRBoot\.handoffUrl/);
	assert.match(shell, /Adventure Ready — Enter Game/);
	assert.match(shell, /await clearAssetDownload\(\['index\.pck'\]\)/);
	assert.match(shell, /backgroundController\.abort\(\)/);
	assert.match(shell, /position: fixed !important/);
	assert.match(shell, /dispatchEvent\(new Event\('resize'\)\)/);
	assert.match(shell, />Load Game Normally</);
	assert.match(shell, />Retry Download</);
	assert.match(shell, />Restart Download</);
	assert.doesNotMatch(shell, /showBackgroundReady\(\)[\s\S]{0,180}location\.(?:replace|reload)/);
});
