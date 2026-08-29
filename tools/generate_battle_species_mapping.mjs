#!/usr/bin/env node

/**
 * Generate the Godot battle profile map from the vendored PokeAPI index and
 * the exact Pokemon Showdown engine used by the REST service.
 *
 * Run after `npm ci` in battle_server/. Use --check in regression gates.
 */

import { createHash } from "node:crypto";
import { createRequire } from "node:module";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

const EXPECTED_SHOWDOWN_VERSION = "0.11.11";
const SCRIPT_DIRECTORY = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(SCRIPT_DIRECTORY, "..");
const POKEAPI_INDEX_PATH = resolve(REPOSITORY_ROOT, "data/creatures/index.json");
const POKEAPI_MANIFEST_PATH = resolve(REPOSITORY_ROOT, "data/creatures/manifest.json");
const POKEAPI_POKEMON_ROOT = resolve(REPOSITORY_ROOT, "data/creatures/pokemon");
const SHOWDOWN_PACKAGE_PATH = resolve(
  REPOSITORY_ROOT,
  "battle_server/node_modules/pokemon-showdown/package.json",
);
const SHOWDOWN_DEX_PATH = resolve(
  REPOSITORY_ROOT,
  "battle_server/node_modules/pokemon-showdown/dist/sim/dex.js",
);
const OUTPUT_PATH = resolve(
  REPOSITORY_ROOT,
  "battle/data/pokeapi_showdown_mapping.json",
);

const STARTING_MOVE_OVERRIDES = new Map([
  [484, ["scaryface", "waterpulse", "dragonbreath", "ancientpower"]],
  [414, ["tackle", "gust", "confusion", "bugbite"]],
  [163, ["tackle", "growl", "peck", "hypnosis"]],
  [416, ["gust", "poisonsting", "confuseray", "bugbite"]],
  [405, ["tackle", "leer", "thundershock", "charge"]],
  [279, ["watergun", "growl", "supersonic", "wingattack"]],
]);

// PokeAPI and Showdown use different canonical names for these exact forms.
// Entries are intentionally reviewed one by one: unmatched forms must remain
// unsupported instead of being collapsed into a different form by a heuristic.
const SPECIES_NAME_OVERRIDES = new Map([
  ["frillish-male", "Frillish"],
  ["jellicent-male", "Jellicent"],
  ["pyroar-male", "Pyroar"],
  ["minior-red-meteor", "Minior-Meteor"],
  ["indeedee-male", "Indeedee"],
  ["basculegion-male", "Basculegion"],
  ["oinkologne-male", "Oinkologne"],
  ["maushold-family-of-four", "Maushold-Four"],
  ["squawkabilly-green-plumage", "Squawkabilly"],
  ["raticate-totem-alola", "Raticate-Alola-Totem"],
  ["pikachu-original-cap", "Pikachu-Original"],
  ["pikachu-hoenn-cap", "Pikachu-Hoenn"],
  ["pikachu-sinnoh-cap", "Pikachu-Sinnoh"],
  ["pikachu-unova-cap", "Pikachu-Unova"],
  ["pikachu-kalos-cap", "Pikachu-Kalos"],
  ["pikachu-alola-cap", "Pikachu-Alola"],
  ["mimikyu-totem-disguised", "Mimikyu-Totem"],
  ["mimikyu-totem-busted", "Mimikyu-Busted-Totem"],
  ["pikachu-partner-cap", "Pikachu-Partner"],
  ["marowak-totem", "Marowak-Alola-Totem"],
  ["rockruff-own-tempo", "Rockruff-Dusk"],
  ["pikachu-world-cap", "Pikachu-World"],
  ["darmanitan-galar-standard", "Darmanitan-Galar"],
  ["indeedee-female", "Indeedee-F"],
  ["basculegion-female", "Basculegion-F"],
  ["tauros-paldea-combat-breed", "Tauros-Paldea-Combat"],
  ["tauros-paldea-blaze-breed", "Tauros-Paldea-Blaze"],
  ["tauros-paldea-aqua-breed", "Tauros-Paldea-Aqua"],
  ["oinkologne-female", "Oinkologne-F"],
  ["maushold-family-of-three", "Maushold"],
  ["squawkabilly-blue-plumage", "Squawkabilly-Blue"],
  ["squawkabilly-yellow-plumage", "Squawkabilly-Yellow"],
  ["squawkabilly-white-plumage", "Squawkabilly-White"],
  ["meowstic-male-mega", "Meowstic-M-Mega"],
]);

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function generatedDefaultMoves(dex, species) {
  const inheritedLearnsets = dex.species.getFullLearnset(species.name);
  const learnset = inheritedLearnsets[0]?.learnset ?? {};

  for (let generation = 9; generation >= 1; generation -= 1) {
    const candidates = [];
    for (const [moveId, sources] of Object.entries(learnset)) {
      let minimumLevel = Number.POSITIVE_INFINITY;
      for (const source of sources) {
        const match = new RegExp(`^${generation}L(\\d+)$`, "u").exec(source);
        if (match) minimumLevel = Math.min(minimumLevel, Number(match[1]));
      }
      if (Number.isFinite(minimumLevel) && dex.moves.get(moveId).exists) {
        candidates.push({ id: dex.moves.get(moveId).id, level: minimumLevel });
      }
    }
    if (candidates.length > 0) {
      candidates.sort((left, right) => left.level - right.level || left.id.localeCompare(right.id));
      return candidates.slice(0, 4).map((candidate) => candidate.id);
    }
  }

  const firstKnownMove = Object.keys(learnset)
    .map((moveId) => dex.moves.get(moveId))
    .find((move) => move.exists);
  return [firstKnownMove?.id ?? "tackle"];
}

function pokedexDimensions(pokemon) {
  const recordPath = resolve(POKEAPI_POKEMON_ROOT, `${pokemon.id}.json.gz`);
  const record = JSON.parse(gunzipSync(readFileSync(recordPath)).toString("utf8"));
  if (
    record.id !== pokemon.id
    || record.name !== pokemon.name
    || !Number.isInteger(record.height)
    || record.height <= 0
    || !Number.isInteger(record.weight)
    || record.weight < 0
  ) {
    throw new Error(`PokeAPI dimensions are invalid for Pokemon ${pokemon.id}`);
  }
  return {
    pokedexHeightDm: record.height,
    pokedexWeightHg: record.weight,
  };
}

function buildOutput() {
  const packageJson = JSON.parse(readFileSync(SHOWDOWN_PACKAGE_PATH, "utf8"));
  if (packageJson.version !== EXPECTED_SHOWDOWN_VERSION) {
    throw new Error(
      `Expected pokemon-showdown ${EXPECTED_SHOWDOWN_VERSION}, found ${packageJson.version}`,
    );
  }

  const require = createRequire(import.meta.url);
  const { Dex } = require(SHOWDOWN_DEX_PATH);
  const dex = Dex.forGen(9);
  const indexBytes = readFileSync(POKEAPI_INDEX_PATH);
  const index = JSON.parse(indexBytes.toString("utf8"));
  const pokeapiManifest = JSON.parse(readFileSync(POKEAPI_MANIFEST_PATH, "utf8"));
  if (!/^[a-f0-9]{64}$/u.test(pokeapiManifest.dataset_sha256 ?? "")) {
    throw new Error("PokeAPI dataset manifest has no valid SHA-256");
  }
  const validMoveIds = [
    ...new Set(
      dex.moves
        .all()
        .filter((move) => move.exists)
        .map((move) => move.id),
    ),
  ].sort();
  const moveTypes = Object.fromEntries(
    validMoveIds.map((moveId) => {
      const moveType = dex.moves.get(moveId).type;
      if (!moveType) {
        throw new Error(`Showdown move ${moveId} has no presentation type`);
      }
      return [moveId, moveType];
    }),
  );
  const mappings = {};
  const unsupportedPokemonIds = [];

  for (const pokemon of index.pokemon) {
    const species = dex.species.get(SPECIES_NAME_OVERRIDES.get(pokemon.name) ?? pokemon.name);
    if (!species.exists || species.num !== pokemon.species_id) {
      unsupportedPokemonIds.push(pokemon.id);
      continue;
    }

    mappings[String(pokemon.id)] = {
      species: species.name,
      spriteId: species.spriteid || species.id,
      ...pokedexDimensions(pokemon),
      defaultMoves:
        STARTING_MOVE_OVERRIDES.get(pokemon.id) ?? generatedDefaultMoves(dex, species),
    };
  }

  return {
    schemaVersion: 2,
    pokemonShowdownVersion: packageJson.version,
    pokeapiIndexSha256: sha256(indexBytes),
    pokeapiDatasetSha256: pokeapiManifest.dataset_sha256,
    sourcePokemonCount: index.pokemon.length,
    supportedPokemonCount: Object.keys(mappings).length,
    unsupportedPokemonIds,
    validMoveIds,
    moveTypes,
    mappings,
  };
}

const encoded = `${JSON.stringify(buildOutput(), null, 2)}\n`;
if (process.argv.includes("--check")) {
  const current = readFileSync(OUTPUT_PATH, "utf8");
  if (current !== encoded) {
    throw new Error(
      "Battle species mapping is stale. Run tools/generate_battle_species_mapping.mjs.",
    );
  }
  process.stdout.write("Battle species mapping is current.\n");
} else {
  writeFileSync(OUTPUT_PATH, encoded);
  process.stdout.write(`Wrote ${OUTPUT_PATH}\n`);
}
