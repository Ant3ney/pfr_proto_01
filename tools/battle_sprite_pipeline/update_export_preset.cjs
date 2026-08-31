#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..', '..');
const presetPath = path.join(projectRoot, 'export_presets.cfg');
const catalogPath = path.join(
  projectRoot,
  'art',
  'battle',
  'sprites',
  'generated',
  'catalog.json'
);

const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
if (catalog.complete !== true || !Array.isArray(catalog.entries) || catalog.entries.length !== 2106) {
  throw new Error('Refusing to update export_presets.cfg from an incomplete battle sprite catalog.');
}

const preset = fs.readFileSync(presetPath, 'utf8');
const exportLinePattern = /^export_files=PackedStringArray\((.*)\)$/m;
const match = preset.match(exportLinePattern);
if (!match) throw new Error('WebBuild export_files line was not found.');

const existing = [...match[1].matchAll(/"([^"]+)"/g)].map((entry) => entry[1]);
const required = [
  'res://art/environments/new_bouffalant_city/pokemon_center_annex/pokemon_center_annex.tscn',
  'res://overworld/route_4/route_4.tscn',
  'res://battle/route_4_wild_battle_scene.tscn',
  'res://battle/delivery_worker_battle_scene.tscn',
  'res://battle/police_officer_battle_scene.tscn',
  'res://battle/businessman_battle_scene.tscn',
  'res://battle/backpacker_battle_scene.tscn',
  'res://battle/jogger_battle_scene.tscn',
  'res://battle/tourist_battle_scene.tscn',
  'res://battle/encounters/trainer_delivery_worker_city_v1.tres',
  'res://battle/encounters/trainer_police_officer_city_v1.tres',
  'res://battle/encounters/trainer_businessman_city_v1.tres',
  'res://battle/encounters/trainer_backpacker_city_v1.tres',
  'res://battle/encounters/trainer_jogger_city_v1.tres',
  'res://battle/encounters/trainer_tourist_city_v1.tres',
  'res://rnd/interaction/PlayerInteractionDetector.gd',
  'res://rnd/player_menu/PlayerMenuHUD.gd',
  'res://rnd/player_menu/PlayerMenuUI.gd',
  'res://rnd/player_menu/player_menu_hud.tscn',
  'res://rnd/player_menu/player_menu_ui.tscn',
  'res://rnd/move_learning/MoveLearningSystem.gd',
  'res://rnd/move_learning/MoveLearnsetCatalog.gd',
  'res://rnd/move_learning/MoveLearningUI.gd',
  'res://rnd/move_learning/move_learning_ui.tscn',
  'res://rnd/move_learning/data/level_up_learnsets.json',
  'res://rnd/save/ProgressionAutosave.gd',
  'res://rnd/stretch/StretchContent.gd',
  'res://rnd/stretch/StretchGoalSystem.gd',
  'res://rnd/stretch/battle/stretch_battle_scene.tscn',
  'res://rnd/stretch/data/items.json',
  'res://rnd/stretch/data/pokemon.json',
  'res://rnd/stretch/npc/stretchman.tscn',
  'res://rnd/stretch/ui/loot_box_roulette.tscn',
  'res://rnd/stretch/ui/stretch_goal_ui.tscn',
  'res://rnd/stretch/worlds/stretch_destination.tscn',
  'res://art/battle/ui/icons/bag_icon.png',
  'res://art/battle/ui/icons/pokeball_icon.png',
  'res://art/battle/ui/icons/run_icon.png',
  'res://art/battle/ui/icons/sword_icon.png',
  'res://art/battle/sprites/placeholder.svg',
  'res://core/ui/BattleUIOverlay.gd',
  'res://core/CreatureExperience.gd',
  'res://battle/kyle_battle_scene.tscn',
  'res://battle/ui/BattleChoiceOverlay.gd',
  'res://battle/ui/battle_choice_overlay.tscn',
  'res://battle/system/BattleSystem.gd',
  'res://battle/system/BattleExperience.gd',
  'res://battle/system/BattleRestClient.gd',
  'res://battle/system/BattleDtoValidator.gd',
  'res://battle/system/BattleEventTranslator.gd',
  'res://battle/system/BattleSpeciesMapping.gd',
  'res://battle/system/BattleSpriteCatalog.gd',
  'res://battle/system/BattleSpriteScale.gd',
  'res://battle/system/BattleSpritePresenter.gd',
  'res://battle/data/BattleEncounterDefinition.gd',
  'res://battle/data/BattleEncounterMember.gd',
  'res://battle/data/BattleEncounterProvider.gd',
  'res://battle/data/pokeapi_showdown_mapping.json',
  'res://data/creatures/experience.json',
  'res://battle/encounters/trainer_kyle_lake_v1.tres',
  ...catalog.entries.map((entry) => String(entry.atlas)),
];

for (const resourcePath of required) {
  const localPath = path.join(projectRoot, resourcePath.slice('res://'.length));
  if (!fs.existsSync(localPath)) {
    throw new Error(`Required Web battle resource does not exist: ${resourcePath}`);
  }
}
const files = [...new Set([...existing, ...required])];
const existingSet = new Set(existing);
const prefix = files.filter((file) => existingSet.has(file));
const appended = files.filter((file) => !existingSet.has(file)).sort();
const exportLine = `export_files=PackedStringArray(${[...prefix, ...appended]
  .map((file) => JSON.stringify(file))
  .join(', ')})`;

let updated = preset.replace(exportLinePattern, exportLine);
updated = updated.replace(/^exclude_filter="([^"]*)"$/m, (_line, current) => {
  const patterns = current.split(',').map((value) => value.trim()).filter(Boolean);
  for (const pattern of ['source_assets/battle_sprites/*', 'source_assets/battle_sprites/**']) {
    if (!patterns.includes(pattern)) patterns.push(pattern);
  }
  return `exclude_filter=${JSON.stringify(patterns.join(','))}`;
});

fs.writeFileSync(presetPath, updated, 'utf8');
console.log(`WebBuild now selects ${files.length} resources, including ${catalog.entries.length} sprite atlases.`);
