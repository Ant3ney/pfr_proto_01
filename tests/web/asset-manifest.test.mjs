import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
	WEB_CHUNK_SIZE,
	finalizeWebExport,
} from '../../tools/finalize_web_export.mjs';

function hash(bytes) {
	return createHash('sha256').update(bytes).digest('hex');
}

async function makeExport(root, loaderText, pck, wasm, bootPack = Buffer.from('boot pack bytes')) {
	await Promise.all([
		writeFile(path.join(root, 'index.js'), loaderText),
		writeFile(path.join(root, 'index.pck'), pck),
		writeFile(path.join(root, 'index.wasm'), wasm),
		writeFile(path.join(root, 'pfr-loading-battle.pck'), bootPack),
		writeFile(
			path.join(root, 'index.html'),
			`<script>const manifest = __PFR_ASSET_MANIFEST__; const version = '__PFR_CACHE_VERSION__';</script>\n<script src="index.js?v=__PFR_CACHE_VERSION__"></script>`,
		),
		writeFile(
			path.join(root, 'worker-template.js'),
			`const version = '__PFR_CACHE_VERSION__'; const manifest = __PFR_ASSET_MANIFEST__;`,
		),
	]);
	return finalizeWebExport(root, path.join(root, 'worker-template.js'));
}

test('generated manifest records exact independent asset identity and 8 MiB chunks', async (t) => {
	const firstRoot = await mkdtemp(path.join(os.tmpdir(), 'pfr-web-manifest-a-'));
	const secondRoot = await mkdtemp(path.join(os.tmpdir(), 'pfr-web-manifest-b-'));
	t.after(async () => Promise.all([
		rm(firstRoot, { recursive: true, force: true }),
		rm(secondRoot, { recursive: true, force: true }),
	]));
	const pck = Buffer.alloc(WEB_CHUNK_SIZE + 3, 0x5a);
	const wasm = Buffer.from('test wasm bytes');
	const first = await makeExport(firstRoot, 'loader version one', pck, wasm);
	const second = await makeExport(secondRoot, 'loader version two', pck, wasm);

	assert.notEqual(first.buildVersion, second.buildVersion);
	assert.equal(first.manifest.chunkSize, WEB_CHUNK_SIZE);
	assert.deepEqual(first.manifest.assets, second.manifest.assets);
	assert.equal(first.manifest.assets['index.pck'].hash, hash(pck));
	assert.equal(first.manifest.assets['index.pck'].size, pck.length);
	assert.equal(first.manifest.assets['index.pck'].mimeType, 'application/octet-stream');
	assert.equal(first.manifest.assets['index.pck'].chunks.length, 2);
	assert.equal(first.manifest.assets['index.wasm'].hash, hash(wasm));
	assert.equal(first.manifest.assets['index.wasm'].mimeType, 'application/wasm');
	assert.equal(first.manifest.assets['pfr-loading-battle.pck'].hash, hash(Buffer.from('boot pack bytes')));
	assert.equal(first.manifest.assets['pfr-loading-battle.pck'].mimeType, 'application/octet-stream');

	for (const fileName of ['index.html', 'pfr-cache-sw.js']) {
		const generated = await readFile(path.join(firstRoot, fileName), 'utf8');
		assert.doesNotMatch(generated, /__PFR_[A-Z_]+__/);
	}
});
