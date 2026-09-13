#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export const LOADING_BATTLE_SPRITES = Object.freeze({
	ani: Object.freeze(['charmander', 'froakie', 'treecko', 'ditto', 'wobbuffet']),
	'ani-back': Object.freeze(['charmander', 'froakie', 'treecko']),
});

function sha256(bytes) {
	return createHash('sha256').update(bytes).digest('hex');
}

async function listFiles(root, relative = '') {
	const entries = await readdir(path.join(root, relative), { withFileTypes: true });
	const files = [];
	for (const entry of entries) {
		const child = path.join(relative, entry.name);
		if (entry.isDirectory()) {
			files.push(...await listFiles(root, child));
		} else if (entry.isFile()) {
			files.push(child.split(path.sep).join('/'));
		}
	}
	return files.sort();
}

async function assertSameBytes(stagedPath, sourcePath, label) {
	const [staged, source] = await Promise.all([readFile(stagedPath), readFile(sourcePath)]);
	if (staged.length !== source.length || sha256(staged) !== sha256(source)) {
		throw new Error(`Staged loading-battle file changed bytes: ${label}`);
	}
}

export async function verifyLoadingBattleStage(stageRoot, projectRoot) {
	const sourceCopies = Object.freeze({
		'project.godot': 'loading_battle/project.godot',
		'export_presets.cfg': 'loading_battle/export_presets.cfg',
		'main.tscn': 'loading_battle/main.tscn',
		'src/loading_battle_main.gd': 'loading_battle/src/loading_battle_main.gd',
		'src/loading_battle_rules.gd': 'loading_battle/src/loading_battle_rules.gd',
		'src/loading_battle_session.gd': 'loading_battle/src/loading_battle_session.gd',
		'src/loading_battle_sprite.gd': 'loading_battle/src/loading_battle_sprite.gd',
		'tests/loading_battle_smoke_test.gd': 'loading_battle/tests/loading_battle_smoke_test.gd',
		'tests/loading_battle_smoke_test.tscn': 'loading_battle/tests/loading_battle_smoke_test.tscn',
		'shared/battle_rest_client.gd': 'game/battle/system/battle_rest_client.gd',
		'shared/battle_dto_validator.gd': 'game/battle/system/battle_dto_validator.gd',
		'shared/battle_event_translator.gd': 'game/battle/system/battle_event_translator.gd',
	});
	for (const [stagedRelative, sourceRelative] of Object.entries(sourceCopies)) {
		await assertSameBytes(
			path.join(stageRoot, stagedRelative),
			path.join(projectRoot, sourceRelative),
			stagedRelative,
		);
	}
	const expectedFiles = new Set(Object.keys(sourceCopies));
	for (const [style, ids] of Object.entries(LOADING_BATTLE_SPRITES)) {
		const assetDirectory = path.join(stageRoot, 'art', 'battle', 'sprites', 'generated', style);
		const actualNames = (await readdir(assetDirectory)).sort();
		const expectedNames = ids.flatMap((id) => [`${id}.json`, `${id}.png`]).sort();
		if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
			throw new Error(`${style} staging assets differ from the exact approved set.`);
		}
		for (const fileName of expectedNames) {
			const relative = `art/battle/sprites/generated/${style}/${fileName}`;
			expectedFiles.add(relative);
			await assertSameBytes(
				path.join(stageRoot, relative),
				path.join(projectRoot, relative),
				relative,
			);
		}
	}
	const actualFiles = await listFiles(stageRoot);
	if (actualFiles.length !== expectedFiles.size
			|| actualFiles.some((file) => !expectedFiles.has(file))) {
		throw new Error('Loading-battle stage contains files outside the exact approved source set.');
	}

	const stagedTopLevel = await readdir(stageRoot);
	for (const forbidden of ['game', 'source_assets', 'data', 'saves', 'audio']) {
		if (stagedTopLevel.includes(forbidden)) {
			throw new Error(`Loading-battle stage contains forbidden top-level path: ${forbidden}`);
		}
	}
	const project = await readFile(path.join(stageRoot, 'project.godot'), 'utf8');
	if (!project.includes('PackedStringArray("4.7", "GL Compatibility")') || project.includes('[autoload]')) {
		throw new Error('Loading-battle project must target Godot 4.7 with no autoloads.');
	}
	return true;
}

async function main() {
	const [stageRoot, projectRoot] = process.argv.slice(2);
	if (!stageRoot || !projectRoot) {
		throw new Error('Usage: node tools/verify_loading_battle_stage.mjs <stage> <project-root>');
	}
	await verifyLoadingBattleStage(path.resolve(stageRoot), path.resolve(projectRoot));
	process.stdout.write('Verified exact loading-battle stage contents.\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		console.error(error.message);
		process.exitCode = 1;
	});
}
