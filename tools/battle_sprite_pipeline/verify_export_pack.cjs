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
  'art/environments/new_bouffalant_city/pokemon_center_interior/pokemon_center_interior.tscn.remap',
  'art/environments/new_bouffalant_city/pokemon_center_interior/pokemon_center_interior_environment.glb.import',
  'art/environments/new_bouffalant_city/pokemon_center_annex/pokemon_center_annex.tscn.remap',
  'art/environments/new_bouffalant_city/city_interiors/miare_station_concourse.tscn.remap',
  'art/environments/new_bouffalant_city/city_interiors/gatehouse_interior.tscn.remap',
  'overworld/route_0/route_0.tscn.remap',
  'overworld/route_0/RouteZeroRuntime.gd.remap',
  'overworld/route_4/route_4.tscn.remap',
  'overworld/route_4/route_4_gateway.tscn.remap',
  'overworld/route_4/route_4_return_gateway.tscn.remap',
  'overworld/route_4/Route4Gateway.gd.remap',
  'rnd/tall_grass_encounter_zone.tscn.remap',
  'rnd/TallGrassEncounterZone.gd.remap',
  'rnd/interaction/PlayerInteractionDetector.gd.remap',
  'overworld/town_npcs/RoamingTownNpcBehavior.gd.remap',
  'overworld/town_npcs/TownNpcBehavior.gd.remap',
  'overworld/town_npcs/town_npc.tscn.remap',
  'rnd/player_menu/PlayerMenuHUD.gd.remap',
  'rnd/player_menu/PlayerMenuUI.gd.remap',
  'rnd/player_menu/player_menu_hud.tscn.remap',
  'rnd/player_menu/player_menu_ui.tscn.remap',
  'rnd/move_learning/MoveLearningSystem.gd.remap',
  'rnd/move_learning/MoveLearnsetCatalog.gd.remap',
  'rnd/move_learning/MoveLearningUI.gd.remap',
  'rnd/move_learning/move_learning_ui.tscn.remap',
  'rnd/move_learning/data/level_up_learnsets.json',
  'rnd/starter_selection/StarterSelectionSystem.gd.remap',
  'rnd/starter_selection/StarterSelectionUI.gd.remap',
  'rnd/starter_selection/starter_selection_ui.tscn.remap',
  'rnd/save/ProgressionAutosave.gd.remap',
  'rnd/save/CloudSaveSync.gd.remap',
  'rnd/stretch/StretchContent.gd.remap',
  'rnd/stretch/StretchGoalSystem.gd.remap',
  'rnd/stretch/battle/stretch_battle_scene.tscn.remap',
  'rnd/stretch/data/items.json',
  'rnd/stretch/data/pokemon.json',
  'rnd/stretch/npc/stretchman.tscn.remap',
  'rnd/stretch/ui/loot_box_roulette.tscn.remap',
  'rnd/stretch/ui/stretch_goal_ui.tscn.remap',
  'rnd/stretch/worlds/RouteCompletionGate.gd.remap',
  'rnd/stretch/worlds/route_completion_gate.tscn.remap',
  'rnd/stretch/worlds/stretch_destination.tscn.remap',
  'battle/route_0_wild_battle_scene.tscn.remap',
  'battle/encounters/wild_fletchling_route_0_v1.tres.remap',
  'overworld/pokemon_center/PokemonCenterHealer.tscn.remap',
  'core/PokemonCenterHealerBehavior.gd.remap',
  'core/CollectionSystem.gd.remap',
  'art/characters/za_city_waiter/za_city_waiter.tres.remap',
  'art/characters/za_city_waiter/models/model.glb.import',
  'art/battle/ui/icons/bag_icon.png.import',
  'art/battle/ui/icons/pokeball_icon.png.import',
  'art/battle/ui/icons/run_icon.png.import',
  'art/battle/ui/icons/sword_icon.png.import',
  'art/battle/sprites/generated/catalog.json',
  'art/battle/sprites/placeholder.svg.import',
  'core/ui/BattleUIOverlay.gd.remap',
  'core/CreatureExperience.gd.remap',
  'battle/kyle_battle_scene.tscn.remap',
  'battle/delivery_worker_battle_scene.tscn.remap',
  'battle/police_officer_battle_scene.tscn.remap',
  'battle/businessman_battle_scene.tscn.remap',
  'battle/backpacker_battle_scene.tscn.remap',
  'battle/jogger_battle_scene.tscn.remap',
  'battle/tourist_battle_scene.tscn.remap',
  'battle/encounters/trainer_delivery_worker_city_v1.tres.remap',
  'battle/encounters/trainer_police_officer_city_v1.tres.remap',
  'battle/encounters/trainer_businessman_city_v1.tres.remap',
  'battle/encounters/trainer_backpacker_city_v1.tres.remap',
  'battle/encounters/trainer_jogger_city_v1.tres.remap',
  'battle/encounters/trainer_tourist_city_v1.tres.remap',
  'battle/ui/BattleChoiceOverlay.gd.remap',
  'battle/ui/battle_choice_overlay.tscn.remap',
  'battle/system/BattleSystem.gd.remap',
  'battle/system/BattleExperience.gd.remap',
  'battle/system/BattleRestClient.gd.remap',
  'battle/system/BattleDtoValidator.gd.remap',
  'battle/system/BattleEventTranslator.gd.remap',
  'battle/system/BattleSpeciesMapping.gd.remap',
  'battle/system/BattleSpriteCatalog.gd.remap',
  'battle/system/BattleSpriteScale.gd.remap',
  'battle/system/BattleSpritePresenter.gd.remap',
  'battle/data/BattleEncounterDefinition.gd.remap',
  'battle/data/BattleEncounterMember.gd.remap',
  'battle/data/BattleEncounterProvider.gd.remap',
  'battle/data/pokeapi_showdown_mapping.json',
  'data/creatures/experience.json',
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
