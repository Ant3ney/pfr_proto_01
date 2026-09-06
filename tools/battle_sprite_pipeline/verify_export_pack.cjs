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
  if (fileCount <= 0 || fileCount > 1000000) {
    throw new Error(`Godot PCK file count is invalid: ${fileCount}.`);
  }
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
    if (!entryPath || paths.has(entryPath)) {
      throw new Error(`Godot PCK path is empty or duplicated: ${entryPath}`);
    }
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

const requiredPaths = [
  'game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn.remap',
  'game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_interior.tscn.remap',
  'game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_annex.tscn.remap',
  'game/world/levels/new_bouffalant_city/interiors/miare_station_concourse.tscn.remap',
  'game/world/levels/new_bouffalant_city/interiors/gatehouse_interior.tscn.remap',
  'game/world/levels/standalone_areas/standalone_area_catalog.tres.remap',
  'game/world/levels/standalone_areas/standalone_area_definition.gd.remap',
  'game/world/levels/standalone_areas/standalone_area_catalog.gd.remap',
  'game/world/level_bases/world_level_base.tscn.remap',
  'game/world/level_bases/outdoor_level_base.tscn.remap',
  'game/world/level_bases/interior_level_base.tscn.remap',
  'game/actors/character/pfr_character.tscn.remap',
  'game/actors/npcs/residents/resident_base.tscn.remap',
  'game/actors/npcs/residents/stretchman/stretchman.tscn.remap',
  'game/actors/npcs/shared/menu_npc_behavior.gd.remap',
  'game/actors/npcs/trainers/trainer_base.tscn.remap',
  'game/ui/adventure_menu/adventure_menu.tscn.remap',
  'game/economy/economy_system.gd.remap',
  'game/economy/shop/shop_system.gd.remap',
  'game/inventory/inventory_system.gd.remap',
  'game/progression/challenges/challenge_progression_system.gd.remap',
  'game/battle/rewards/battle_reward_system.gd.remap',
  'game/battle/scenes/challenge_battle.tscn.remap',
  'game/save/progression_autosave.gd.remap',
  'game/save/cloud_save_sync.gd.remap',
  'art/battle/sprites/generated/catalog.json',
  'data/creatures/experience.json',
];
for (let routeIndex = 0; routeIndex < 40; routeIndex += 1) {
  const id = `route_${String(routeIndex).padStart(2, '0')}`;
  requiredPaths.push(`game/world/levels/standalone_areas/routes/${id}/${id}.tscn.remap`);
  requiredPaths.push(`game/world/levels/standalone_areas/routes/${id}/area_definition.tres.remap`);
}
for (let gymIndex = 1; gymIndex <= 8; gymIndex += 1) {
  const id = `gym_${String(gymIndex).padStart(2, '0')}`;
  requiredPaths.push(`game/world/levels/standalone_areas/gyms/${id}/${id}.tscn.remap`);
  requiredPaths.push(`game/world/levels/standalone_areas/gyms/${id}/area_definition.tres.remap`);
}
requiredPaths.push(
  'game/world/levels/standalone_areas/champion/champion_challenge/champion_challenge.tscn.remap',
  'game/world/levels/standalone_areas/champion/champion_challenge/area_definition.tres.remap',
);

for (const required of requiredPaths) {
  if (!packPaths.has(required)) throw new Error(`Export is missing ${required}.`);
}

const standaloneScenePaths = [...packPaths].filter((entry) => (
  /^game\/world\/levels\/standalone_areas\/(?:routes\/route_\d{2}\/route_\d{2}|gyms\/gym_\d{2}\/gym_\d{2}|champion\/champion_challenge\/champion_challenge)\.tscn\.remap$/.test(entry)
));
if (standaloneScenePaths.length !== 49) {
  throw new Error(`Export contains ${standaloneScenePaths.length} standalone-area scenes; expected 49.`);
}

for (const forbiddenPrefix of [
  'source_assets/battle_sprites/',
  'battle_server/',
  'core/',
  'demo/',
  'overworld/',
  'rnd/',
]) {
  if ([...packPaths].some((entry) => entry.startsWith(forbiddenPrefix))) {
    throw new Error(`Export contains forbidden legacy/source path prefix: ${forbiddenPrefix}`);
  }
}

console.log(JSON.stringify({
  pack: packPath,
  bytes: bytes.length,
  packEntries: packPaths.size,
  standaloneAreaScenes: standaloneScenePaths.length,
  atlasImports: atlasImports.size,
  timingManifests: timingManifests.size,
  rawGifSourcesPresent: false,
  battleServerPresent: false,
  legacyRuntimeRootsPresent: false,
}, null, 2));
