#!/usr/bin/env node

/**
 * Generate the R&D level-up move catalog from the vendored PokeAPI Pokemon
 * records. The runtime never needs a network request or a second Pokedex.
 */

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

const SCRIPT_DIRECTORY = dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = resolve(SCRIPT_DIRECTORY, "../../..");
const POKEAPI_INDEX_PATH = resolve(REPOSITORY_ROOT, "data/creatures/index.json");
const POKEAPI_MANIFEST_PATH = resolve(REPOSITORY_ROOT, "data/creatures/manifest.json");
const POKEAPI_POKEMON_ROOT = resolve(REPOSITORY_ROOT, "data/creatures/pokemon");
const BATTLE_MAPPING_PATH = resolve(
  REPOSITORY_ROOT,
  "battle/data/pokeapi_showdown_mapping.json",
);
const OUTPUT_PATH = resolve(
  REPOSITORY_ROOT,
  "rnd/move_learning/data/level_up_learnsets.json",
);

// Prefer the newest conventional main-series learnset available for the exact
// form. Side-game and Japanese-release groups remain deterministic fallbacks.
const VERSION_GROUP_PRIORITY = [
  "scarlet-violet",
  "brilliant-diamond-shining-pearl",
  "sword-shield",
  "lets-go-pikachu-lets-go-eevee",
  "ultra-sun-ultra-moon",
  "sun-moon",
  "omega-ruby-alpha-sapphire",
  "x-y",
  "black-2-white-2",
  "black-white",
  "heartgold-soulsilver",
  "platinum",
  "diamond-pearl",
  "firered-leafgreen",
  "emerald",
  "ruby-sapphire",
  "crystal",
  "gold-silver",
  "yellow",
  "red-blue",
  "legends-arceus",
  "xd",
  "colosseum",
  "blue-japan",
  "red-green-japan",
];

// PokeAPI retains this historical spelling while modern Showdown uses the
// current official spelling.
const MOVE_ID_ALIASES = new Map([
  ["vice-grip", "visegrip"],
]);
const MOVE_NAME_OVERRIDES = new Map([
  ["visegrip", "Vise Grip"],
]);

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function showdownMoveId(pokeapiSlug) {
  return (
    MOVE_ID_ALIASES.get(pokeapiSlug)
    ?? String(pokeapiSlug).toLowerCase().replace(/[^a-z0-9]+/gu, "")
  );
}

function displayMoveName(pokeapiSlug, moveId) {
  if (MOVE_NAME_OVERRIDES.has(moveId)) return MOVE_NAME_OVERRIDES.get(moveId);
  return String(pokeapiSlug)
    .split("-")
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

function readPokemonRecord(pokemonId) {
  const path = resolve(POKEAPI_POKEMON_ROOT, `${pokemonId}.json.gz`);
  return JSON.parse(gunzipSync(readFileSync(path)).toString("utf8"));
}

function movesByVersion(record, validMoveIds, moveNames) {
  const byVersion = new Map();
  for (const moveRecord of record.moves ?? []) {
    const slug = String(moveRecord.move?.name ?? "");
    const moveId = showdownMoveId(slug);
    if (!validMoveIds.has(moveId)) continue;
    if (!moveNames.has(moveId)) {
      moveNames.set(moveId, displayMoveName(slug, moveId));
    }
    for (const detail of moveRecord.version_group_details ?? []) {
      if (detail.move_learn_method?.name !== "level-up") continue;
      const level = Number(detail.level_learned_at);
      const versionGroup = String(detail.version_group?.name ?? "");
      // Level zero represents an evolution move, not a level threshold.
      if (!Number.isInteger(level) || level < 1 || level > 100 || !versionGroup) continue;
      if (!byVersion.has(versionGroup)) byVersion.set(versionGroup, []);
      byVersion.get(versionGroup).push([level, moveId]);
    }
  }
  return byVersion;
}

function selectedVersion(byVersion) {
  return VERSION_GROUP_PRIORITY.find((versionGroup) => {
    const moves = byVersion.get(versionGroup);
    return Array.isArray(moves) && moves.length > 0;
  });
}

function normalizedLevelMoves(moves) {
  const unique = new Map();
  for (const [level, moveId] of moves) {
    unique.set(`${level}:${moveId}`, [level, moveId]);
  }
  return [...unique.values()].sort(
    (left, right) => left[0] - right[0] || left[1].localeCompare(right[1]),
  );
}

function buildOutput() {
  const indexBytes = readFileSync(POKEAPI_INDEX_PATH);
  const index = JSON.parse(indexBytes.toString("utf8"));
  const manifest = JSON.parse(readFileSync(POKEAPI_MANIFEST_PATH, "utf8"));
  const battleMappingBytes = readFileSync(BATTLE_MAPPING_PATH);
  const battleMapping = JSON.parse(battleMappingBytes.toString("utf8"));
  if (battleMapping.pokeapiDatasetSha256 !== manifest.dataset_sha256) {
    throw new Error("Battle mapping and PokeAPI creature snapshot do not match");
  }

  const validMoveIds = new Set(battleMapping.validMoveIds);
  const defaultEntryBySpeciesId = new Map(
    index.pokemon
      .filter((entry) => entry.is_default)
      .map((entry) => [entry.species_id, entry]),
  );
  const recordById = new Map();
  const moveNames = new Map();
  const pokemonRows = [];

  const recordFor = (pokemonId) => {
    if (!recordById.has(pokemonId)) recordById.set(pokemonId, readPokemonRecord(pokemonId));
    return recordById.get(pokemonId);
  };

  // First collect names from every PokeAPI move record, including moves that
  // are not selected by the final level-up version group.
  for (const pokemon of index.pokemon) {
    movesByVersion(recordFor(pokemon.id), validMoveIds, moveNames);
  }

  for (const pokemon of index.pokemon) {
    let sourcePokemon = pokemon;
    let byVersion = movesByVersion(recordFor(pokemon.id), validMoveIds, moveNames);
    let versionGroup = selectedVersion(byVersion);
    if (!versionGroup) {
      sourcePokemon = defaultEntryBySpeciesId.get(pokemon.species_id);
      if (!sourcePokemon) {
        throw new Error(`Pokemon ${pokemon.id} has no default species-form fallback`);
      }
      byVersion = movesByVersion(recordFor(sourcePokemon.id), validMoveIds, moveNames);
      versionGroup = selectedVersion(byVersion);
    }
    if (!versionGroup) {
      throw new Error(`Pokemon ${pokemon.id} has no usable level-up learnset`);
    }
    const levelMoves = normalizedLevelMoves(byVersion.get(versionGroup));
    if (levelMoves.length === 0) {
      throw new Error(`Pokemon ${pokemon.id} selected an empty learnset`);
    }
    pokemonRows.push([
      pokemon.id,
      sourcePokemon.id,
      VERSION_GROUP_PRIORITY.indexOf(versionGroup),
      levelMoves,
    ]);
  }

  if (pokemonRows.length !== index.pokemon_count) {
    throw new Error("Generated learnset Pokemon count is inconsistent");
  }

  return {
    schemaVersion: 1,
    policy: "latest compatible conventional PokeAPI level-up learnset; exact form first, then default species form",
    pokeapiIndexSha256: sha256(indexBytes),
    pokeapiDatasetSha256: manifest.dataset_sha256,
    battleMappingSha256: sha256(battleMappingBytes),
    sourcePokemonCount: index.pokemon_count,
    versionGroups: VERSION_GROUP_PRIORITY,
    pokemonRowColumns: [
      "pokemonId",
      "sourcePokemonId",
      "versionGroupIndex",
      "levelMoves",
    ],
    levelMoveColumns: ["level", "moveId"],
    moveNames: Object.fromEntries([...moveNames.entries()].sort()),
    pokemonRows,
  };
}

const encoded = `${JSON.stringify(buildOutput())}\n`;
if (process.argv.includes("--check")) {
  if (readFileSync(OUTPUT_PATH, "utf8") !== encoded) {
    throw new Error(
      "R&D move learnset data is stale. Run rnd/move_learning/tools/generate_move_learnsets.mjs.",
    );
  }
  process.stdout.write("R&D move learnset data is current.\n");
} else {
  mkdirSync(dirname(OUTPUT_PATH), { recursive: true });
  writeFileSync(OUTPUT_PATH, encoded);
  process.stdout.write(`Wrote ${OUTPUT_PATH}\n`);
}
