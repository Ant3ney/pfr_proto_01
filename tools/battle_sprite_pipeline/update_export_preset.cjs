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
const runtimeExtensions = new Set(['.gd', '.tscn', '.tres', '.json', '.json.gz']);

function collectRuntimeResources(directory) {
  const resources = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const localPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      resources.push(...collectRuntimeResources(localPath));
      continue;
    }
    const extension = entry.name.endsWith('.json.gz') ? '.json.gz' : path.extname(entry.name);
    if (!runtimeExtensions.has(extension)) continue;
    resources.push(`res://${path.relative(projectRoot, localPath).split(path.sep).join('/')}`);
  }
  return resources;
}

// Dynamic menu travel cannot be discovered from the main-scene dependency graph.
// Select every runtime-authored game resource so all 49 standalone area scenes,
// their adjacent definitions, and their encounter resources ship together.
const required = [
  ...collectRuntimeResources(path.join(projectRoot, 'game')),
  'res://data/creatures/experience.json',
  'res://art/battle/sprites/generated/catalog.json',
  'res://art/battle/sprites/placeholder.svg',
  'res://art/battle/ui/icons/bag_icon.png',
  'res://art/battle/ui/icons/pokeball_icon.png',
  'res://art/battle/ui/icons/run_icon.png',
  'res://art/battle/ui/icons/sword_icon.png',
  ...catalog.entries.map((entry) => String(entry.atlas)),
];

for (const resourcePath of required) {
  const localPath = path.join(projectRoot, resourcePath.slice('res://'.length));
  if (!fs.existsSync(localPath)) {
    throw new Error(`Required Web battle resource does not exist: ${resourcePath}`);
  }
}
const retainedExisting = existing.filter((file) => {
  if (!file.startsWith('res://')) return false;
  return fs.existsSync(path.join(projectRoot, file.slice('res://'.length)));
});
const files = [...new Set([...retainedExisting, ...required])];
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
