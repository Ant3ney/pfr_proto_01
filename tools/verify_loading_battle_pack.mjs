#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { LOADING_BATTLE_SPRITES } from './verify_loading_battle_stage.mjs';

export const MAX_LOADING_BATTLE_PACK_BYTES = 4 * 1024 * 1024;

export function readPackPaths(bytes) {
	if (bytes.length < 40 || bytes.subarray(0, 4).toString('ascii') !== 'GDPC') {
		throw new Error('Loading battle export is not a standalone Godot PCK.');
	}
	const packFormat = bytes.readUInt32LE(4);
	const packFlags = bytes.readUInt32LE(20);
	if (packFormat !== 4 || (packFlags & 1) !== 0) {
		throw new Error(`Unsupported or encrypted Godot PCK format: ${packFormat}.`);
	}
	const directoryOffset = Number(bytes.readBigUInt64LE(32));
	if (!Number.isSafeInteger(directoryOffset) || directoryOffset < 0 || directoryOffset + 4 > bytes.length) {
		throw new Error('Loading battle PCK directory offset is invalid.');
	}
	let cursor = directoryOffset;
	const fileCount = bytes.readUInt32LE(cursor);
	cursor += 4;
	if (fileCount <= 0 || fileCount > 10000) {
		throw new Error(`Loading battle PCK file count is invalid: ${fileCount}.`);
	}
	const paths = new Set();
	for (let index = 0; index < fileCount; index += 1) {
		if (cursor + 4 > bytes.length) throw new Error('Loading battle PCK directory is truncated.');
		const pathBytes = bytes.readUInt32LE(cursor);
		cursor += 4;
		const recordBytes = pathBytes + 8 + 8 + 16 + 4;
		if (pathBytes <= 0 || pathBytes > 1024 * 1024 || cursor + recordBytes > bytes.length) {
			throw new Error(`Loading battle PCK directory entry ${index} is invalid.`);
		}
		const entryPath = bytes.subarray(cursor, cursor + pathBytes).toString('utf8').replace(/\0+$/u, '');
		if (!entryPath || paths.has(entryPath)) {
			throw new Error(`Loading battle PCK path is empty or duplicated: ${entryPath}`);
		}
		paths.add(entryPath);
		cursor += recordBytes;
	}
	return paths;
}

export async function verifyLoadingBattlePack(packPath) {
	const bytes = await readFile(packPath);
	if (bytes.length > MAX_LOADING_BATTLE_PACK_BYTES) {
		throw new Error(
			`Loading battle PCK is ${bytes.length} bytes; maximum is ${MAX_LOADING_BATTLE_PACK_BYTES}.`,
		);
	}
	const packPaths = readPackPaths(bytes);
	const expectedImports = new Set();
	const expectedManifests = new Set();
	for (const [style, ids] of Object.entries(LOADING_BATTLE_SPRITES)) {
		for (const id of ids) {
			const base = `art/battle/sprites/generated/${style}/${id}`;
			expectedImports.add(`${base}.png.import`);
			expectedManifests.add(`${base}.json`);
		}
	}
	const actualImports = new Set([...packPaths].filter((entry) => (
		/^art\/battle\/sprites\/generated\/(?:ani|ani-back)\/[^/]+\.png\.import$/u.test(entry)
	)));
	const actualManifests = new Set([...packPaths].filter((entry) => (
		/^art\/battle\/sprites\/generated\/(?:ani|ani-back)\/[^/]+\.json$/u.test(entry)
	)));
	for (const [label, actual, expected] of [
		['atlas imports', actualImports, expectedImports],
		['timing manifests', actualManifests, expectedManifests],
	]) {
		if (actual.size !== expected.size || [...expected].some((entry) => !actual.has(entry))) {
			throw new Error(`Loading battle PCK ${label} differ from the exact approved eight-pair set.`);
		}
	}
	for (const required of [
		'main.tscn.remap',
		'src/loading_battle_main.gd.remap',
		'src/loading_battle_rules.gd.remap',
		'src/loading_battle_session.gd.remap',
		'src/loading_battle_sprite.gd.remap',
		'shared/battle_rest_client.gd.remap',
		'shared/battle_dto_validator.gd.remap',
		'shared/battle_event_translator.gd.remap',
	]) {
		if (!packPaths.has(required)) throw new Error(`Loading battle PCK is missing ${required}.`);
	}
	for (const entry of packPaths) {
		if (/\.gif$|\.(?:ogg|mp3|wav)$|(?:^|\/)(?:save|saves|world|autoloads?)(?:\/|$)/iu.test(entry)
				|| entry.startsWith('source_assets/') || entry.includes('/catalog.json')
				|| entry.startsWith('tests/')) {
			throw new Error(`Loading battle PCK contains forbidden runtime content: ${entry}`);
		}
	}
	return { bytes: bytes.length, entries: packPaths.size };
}

async function main() {
	const [packArgument] = process.argv.slice(2);
	if (!packArgument) throw new Error('Usage: node tools/verify_loading_battle_pack.mjs <pack>');
	const result = await verifyLoadingBattlePack(path.resolve(packArgument));
	process.stdout.write(
		`Verified loading battle PCK (${result.bytes} bytes, ${result.entries} entries, eight atlas/manifest pairs).\n`,
	);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		console.error(error.message);
		process.exitCode = 1;
	});
}

