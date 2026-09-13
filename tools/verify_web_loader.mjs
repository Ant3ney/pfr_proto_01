#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { webcrypto } from 'node:crypto';
import path from 'node:path';
import vm from 'node:vm';
import { pathToFileURL } from 'node:url';

import { PATCHES, PATCH_MARKER } from './patch_godot_web_loader.mjs';
import { describeAsset } from './finalize_web_export.mjs';

const UNRESOLVED_PATTERN = /\$(?:GODOT_[A-Z_]+)|__PFR_[A-Z_]+__/g;

async function verifyAsset(webOutput, fileName, description, topLevelChunkSize) {
	const assetPath = path.join(webOutput, fileName);
	if (description.chunkSize !== topLevelChunkSize || topLevelChunkSize !== 8 * 1024 * 1024) {
		throw new Error(`${fileName} does not use the required 8 MiB chunk size.`);
	}
	const actual = await describeAsset(assetPath, description.mimeType, description.chunkSize);
	if (JSON.stringify(actual) !== JSON.stringify(description)) {
		throw new Error(`${fileName} bytes differ from pfr-asset-manifest.json.`);
	}
}

function verifyInlineScripts(html) {
	const scriptPattern = /<script(?<attributes>[^>]*)>(?<source>[\s\S]*?)<\/script>/gi;
	let inlineCount = 0;
	for (const match of html.matchAll(scriptPattern)) {
		if (/\bsrc\s*=/.test(match.groups.attributes)) {
			continue;
		}
		inlineCount += 1;
		new vm.Script(match.groups.source, { filename: `index.html:inline-${inlineCount}` });
	}
	if (inlineCount < 2) {
		throw new Error(`Expected at least two inline scripts in index.html; found ${inlineCount}.`);
	}
}

async function expectStartupRejection(loader, fetchImplementation, failureName) {
	const browserConsole = { error() {}, log() {}, warn() {} };
	const window = {};
	const context = vm.createContext({
		ArrayBuffer,
		BigInt64Array,
		BigUint64Array,
		DataView,
		Error,
		Float32Array,
		Float64Array,
		Headers,
		Int16Array,
		Int32Array,
		Int8Array,
		Promise,
		ReadableStream,
		Request,
		Response,
		TextDecoder,
		TextEncoder,
		URL,
		Uint16Array,
		Uint32Array,
		Uint8Array,
		WebAssembly,
		clearTimeout,
		console: browserConsole,
		crypto: webcrypto,
		fetch: fetchImplementation,
		performance,
		requestAnimationFrame: () => 0,
		setTimeout,
		window,
	});
	new vm.Script(loader, { filename: 'index.js' }).runInContext(context);
	if (typeof window.Engine !== 'function') {
		throw new Error('Patched loader did not expose Engine.');
	}
	const engine = new window.Engine({
		executable: 'deliberately-invalid',
		fileSizes: {
			'deliberately-invalid.pck': 4,
			'deliberately-invalid.wasm': 4,
		},
		mainPack: 'deliberately-invalid.pck',
	});
	let timer;
	const result = await Promise.race([
		engine.startGame().then(
			() => ({ type: 'resolved' }),
			(error) => ({ type: 'rejected', error }),
		),
		new Promise((resolve) => {
			timer = setTimeout(() => resolve({ type: 'timeout' }), 2000);
		}),
	]);
	clearTimeout(timer);
	if (result.type !== 'rejected' || !(result.error instanceof Error)) {
		throw new Error(
			`Patched Engine.startGame() must reject ${failureName}; observed ${result.type}.`,
		);
	}
}

async function verifyStartupRejection(loader) {
	await expectStartupRejection(
		loader,
		async () => new Response(new Uint8Array([0, 1, 2, 3]), {
			status: 200,
			headers: { 'content-type': 'application/wasm' },
		}),
		'invalid WebAssembly',
	);
	await expectStartupRejection(
		loader,
		async (input) => {
			const url = typeof input === 'string' ? input : input.url;
			if (url.endsWith('.pck')) {
				return new Response(new ReadableStream({
					start(controller) {
						controller.error(new TypeError('Body stream interrupted'));
					},
				}), { status: 200 });
			}
			return new Promise(() => {});
		},
		'an interrupted response body',
	);
}

export async function verifyWebLoader(webOutput) {
	const paths = {
		html: path.join(webOutput, 'index.html'),
		loader: path.join(webOutput, 'index.js'),
		worker: path.join(webOutput, 'pfr-cache-sw.js'),
		manifest: path.join(webOutput, 'pfr-asset-manifest.json'),
	};
	const [html, loader, worker, manifestSource] = await Promise.all([
		readFile(paths.html, 'utf8'),
		readFile(paths.loader, 'utf8'),
		readFile(paths.worker, 'utf8'),
		readFile(paths.manifest, 'utf8'),
	]);

	for (const [name, source] of Object.entries({ html, loader, worker, manifestSource })) {
		const unresolved = source.match(UNRESOLVED_PATTERN);
		if (unresolved) {
			throw new Error(`${name} contains unresolved placeholders: ${[...new Set(unresolved)].join(', ')}`);
		}
	}
	if (!loader.includes(PATCH_MARKER) || loader.includes('const DOWNLOAD_ATTEMPTS_MAX = 4;')) {
		throw new Error('index.js is missing the fail-closed Godot 4.7.2 startup patch.');
	}
	for (const patch of PATCHES) {
		if (loader.includes(patch.before) || loader.split(patch.after).length !== 2) {
			throw new Error(`index.js does not contain exactly one applied ${patch.name} patch.`);
		}
	}
	await verifyStartupRejection(loader);
	verifyInlineScripts(html);
	new vm.Script(worker, { filename: 'pfr-cache-sw.js' });

	const manifest = JSON.parse(manifestSource);
	if (manifest.schemaVersion !== 1 || !manifest.assets || typeof manifest.assets !== 'object') {
		throw new Error('pfr-asset-manifest.json has an unsupported shape.');
	}
	for (const fileName of ['index.pck', 'index.wasm', 'pfr-loading-battle.pck']) {
		if (!manifest.assets[fileName]) {
			throw new Error(`pfr-asset-manifest.json is missing ${fileName}.`);
		}
		await verifyAsset(webOutput, fileName, manifest.assets[fileName], manifest.chunkSize);
	}

	return manifest;
}

async function main() {
	const [webOutput] = process.argv.slice(2);
	if (!webOutput) {
		throw new Error('Usage: node tools/verify_web_loader.mjs <web-output-directory>');
	}
	await verifyWebLoader(webOutput);
	process.stdout.write('Verified resumable web loader, generated manifest, and inline script syntax.\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		console.error(error.message);
		process.exitCode = 1;
	});
}
