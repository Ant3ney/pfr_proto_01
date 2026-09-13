#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { open, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const WEB_CHUNK_SIZE = 8 * 1024 * 1024;
const BUILD_VERSION_TOKEN = '__PFR_CACHE_VERSION__';
const MANIFEST_TOKEN = '__PFR_ASSET_MANIFEST__';

const ASSET_TYPES = Object.freeze({
	'index.pck': 'application/octet-stream',
	'index.wasm': 'application/wasm',
	'pfr-loading-battle.pck': 'application/octet-stream',
});

function sha256(data) {
	return createHash('sha256').update(data).digest('hex');
}

export async function describeAsset(assetPath, mimeType, chunkSize = WEB_CHUNK_SIZE) {
	const file = await open(assetPath, 'r');
	const info = await file.stat();
	const assetHash = createHash('sha256');
	const chunks = [];

	try {
		let position = 0;
		while (position < info.size) {
			const length = Math.min(chunkSize, info.size - position);
			const buffer = Buffer.allocUnsafe(length);
			let offset = 0;
			while (offset < length) {
				const { bytesRead } = await file.read(buffer, offset, length - offset, position + offset);
				if (bytesRead === 0) {
					throw new Error(`Unexpected end of file while hashing ${assetPath}.`);
				}
				offset += bytesRead;
			}
			assetHash.update(buffer);
			chunks.push(sha256(buffer));
			position += length;
		}
	} finally {
		await file.close();
	}

	return {
		hash: assetHash.digest('hex'),
		size: info.size,
		mimeType,
		chunkSize,
		chunks,
	};
}

function replaceRequired(source, token, replacement, fileName, expectedCount = 1) {
	const count = source.split(token).length - 1;
	if (count !== expectedCount) {
		throw new Error(`${fileName} must contain ${token} exactly ${expectedCount} time(s); found ${count}.`);
	}
	return source.split(token).join(replacement);
}

export async function finalizeWebExport(webOutput, workerTemplatePath) {
	const loaderPath = path.join(webOutput, 'index.js');
	const htmlPath = path.join(webOutput, 'index.html');
	const workerOutputPath = path.join(webOutput, 'pfr-cache-sw.js');
	const manifestPath = path.join(webOutput, 'pfr-asset-manifest.json');
	const [loader, htmlTemplate, workerTemplate] = await Promise.all([
		readFile(loaderPath),
		readFile(htmlPath, 'utf8'),
		readFile(workerTemplatePath, 'utf8'),
	]);

	const assets = {};
	for (const [fileName, mimeType] of Object.entries(ASSET_TYPES)) {
		assets[fileName] = await describeAsset(path.join(webOutput, fileName), mimeType);
	}
	const manifest = {
		schemaVersion: 1,
		chunkSize: WEB_CHUNK_SIZE,
		assets,
	};
	const compactManifest = JSON.stringify(manifest);

	const versionHash = createHash('sha256');
	versionHash.update(loader);
	versionHash.update(htmlTemplate);
	versionHash.update(workerTemplate);
	for (const [fileName, asset] of Object.entries(assets)) {
		versionHash.update(`${fileName}:${asset.hash}:${asset.size}\n`);
	}
	const buildVersion = versionHash.digest('hex').slice(0, 20);

	let html = replaceRequired(htmlTemplate, MANIFEST_TOKEN, compactManifest, 'index.html');
	html = replaceRequired(html, BUILD_VERSION_TOKEN, buildVersion, 'index.html', 2);
	let worker = replaceRequired(workerTemplate, MANIFEST_TOKEN, compactManifest, 'pfr_cache_service_worker.js');
	worker = replaceRequired(worker, BUILD_VERSION_TOKEN, buildVersion, 'pfr_cache_service_worker.js');

	await Promise.all([
		writeFile(htmlPath, html),
		writeFile(workerOutputPath, worker),
		writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`),
	]);

	return { buildVersion, manifest };
}

async function main() {
	const [webOutput, workerTemplatePath] = process.argv.slice(2);
	if (!webOutput || !workerTemplatePath) {
		throw new Error(
			'Usage: node tools/finalize_web_export.mjs <web-output-directory> <service-worker-template>',
		);
	}
	const result = await finalizeWebExport(webOutput, workerTemplatePath);
	process.stdout.write(
		`Generated resumable asset manifest for build ${result.buildVersion} (${WEB_CHUNK_SIZE} byte chunks).\n`,
	);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		console.error(error.message);
		process.exitCode = 1;
	});
}
