#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const packPath = process.argv[2] ? path.resolve(process.argv[2]) : '';
if (!packPath || !fs.existsSync(packPath)) {
  throw new Error('Usage: node verify_export_pack.cjs /path/to/export.pck');
}

const bytes = fs.readFileSync(packPath);

function readPackPaths(packBytes) {
  if (packBytes.length < 40 || packBytes.subarray(0, 4).toString('ascii') !== 'GDPC') {
    throw new Error('Export is not a standalone Godot PCK.');
  }
  const packFormat = packBytes.readUInt32LE(4);
  const packFlags = packBytes.readUInt32LE(20);
  if (packFormat !== 4) throw new Error(`Unsupported Godot PCK format: ${packFormat}.`);
  if ((packFlags & 1) !== 0) throw new Error('Encrypted PCK directory verification is unsupported.');
  const directoryOffset = Number(packBytes.readBigUInt64LE(32));
  if (!Number.isSafeInteger(directoryOffset) || directoryOffset < 0 || directoryOffset + 4 > packBytes.length) {
    throw new Error('Godot PCK directory offset is invalid.');
  }
  let cursor = directoryOffset;
  const fileCount = packBytes.readUInt32LE(cursor);
  cursor += 4;
  if (fileCount <= 0 || fileCount > 1000000) throw new Error(`Godot PCK file count is invalid: ${fileCount}.`);
  const paths = new Set();
  for (let index = 0; index < fileCount; index += 1) {
    if (cursor + 4 > packBytes.length) throw new Error('Godot PCK directory is truncated.');
    const pathBytes = packBytes.readUInt32LE(cursor);
    cursor += 4;
    const recordBytes = pathBytes + 8 + 8 + 16 + 4;
    if (pathBytes <= 0 || pathBytes > 1024 * 1024 || cursor + recordBytes > packBytes.length) {
      throw new Error(`Godot PCK directory entry ${index} is invalid.`);
    }
    const entryPath = packBytes.subarray(cursor, cursor + pathBytes).toString('utf8').replace(/\0+$/, '');
    if (!entryPath || paths.has(entryPath)) throw new Error(`Godot PCK path is empty or duplicated: ${entryPath}`);
    paths.add(entryPath);
    cursor += recordBytes;
  }
  if (cursor > packBytes.length) throw new Error('Godot PCK directory extends beyond the file.');
  return paths;
}

const packPaths = readPackPaths(bytes);
const atlasImports = new Set([...packPaths].filter((entry) => (
  /^art\/battle\/sprites\/generated\/(?:ani|ani-back)\/[a-z0-9-]+\.png\.import$/.test(entry)
)));
const timingManifests = new Set([...packPaths].filter((entry) => (
  /^art\/battle\/sprites\/generated\/(?:ani|ani-back)\/[a-z0-9-]+\.json$/.test(entry)
)));
if (atlasImports.size !== 2106) {
  throw new Error(`Export contains ${atlasImports.size} sprite atlas imports; expected 2106.`);
}
if (timingManifests.size !== 2106) {
  throw new Error(`Export contains ${timingManifests.size} timing manifests; expected 2106.`);
}
for (const required of [
  'art/battle/ui/icons/bag_icon.png.import',
  'art/battle/ui/icons/pokeball_icon.png.import',
  'art/battle/ui/icons/run_icon.png.import',
  'art/battle/ui/icons/sword_icon.png.import',
  'art/battle/sprites/generated/catalog.json',
  'art/battle/sprites/placeholder.svg.import',
  'core/ui/BattleUIOverlay.gd.remap',
  'battle/kyle_battle_scene.tscn.remap',
  'battle/ui/BattleChoiceOverlay.gd.remap',
  'battle/ui/battle_choice_overlay.tscn.remap',
  'battle/system/BattleSystem.gd.remap',
  'battle/system/BattleRestClient.gd.remap',
  'battle/system/BattleDtoValidator.gd.remap',
  'battle/system/BattleEventTranslator.gd.remap',
  'battle/system/BattleSpeciesMapping.gd.remap',
  'battle/system/BattleSpriteCatalog.gd.remap',
  'battle/system/BattleSpritePresenter.gd.remap',
  'battle/data/BattleEncounterDefinition.gd.remap',
  'battle/data/BattleEncounterMember.gd.remap',
  'battle/data/BattleEncounterProvider.gd.remap',
  'battle/data/pokeapi_showdown_mapping.json',
  'battle/encounters/trainer_kyle_lake_v1.tres.remap',
]) {
  if (!packPaths.has(required)) throw new Error(`Export is missing ${required}.`);
}
for (const forbidden of [
  'source_assets/battle_sprites/',
  'res://source_assets/battle_sprites/',
  'battle_server/',
  'res://battle_server/',
]) {
  if ([...packPaths].some((entry) => entry.startsWith(forbidden.replace(/^res:\/\//, '')))) {
    throw new Error(`Export contains forbidden path prefix: ${forbidden}`);
  }
}

console.log(JSON.stringify({
  pack: packPath,
  bytes: bytes.length,
  packEntries: packPaths.size,
  atlasImports: atlasImports.size,
  timingManifests: timingManifests.size,
  rawGifSourcesPresent: false,
  battleServerPresent: false,
}, null, 2));
