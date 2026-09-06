#!/usr/bin/env node

/**
 * Generate compact, offline Pokemon experience data.
 *
 * Growth curves reproduce the PokeAPI growth-rate endpoint. Reward multipliers
 * are a project balance rule derived from the exact Pokemon Showdown version
 * used by the battle server. Run with --check in regression gates.
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
const INDEX_PATH = resolve(REPOSITORY_ROOT, "data/creatures/index.json");
const MANIFEST_PATH = resolve(REPOSITORY_ROOT, "data/creatures/manifest.json");
const SPECIES_ROOT = resolve(REPOSITORY_ROOT, "data/creatures/species");
const BATTLE_MAPPING_PATH = resolve(
  REPOSITORY_ROOT,
  "game/battle/encounters/pokeapi_showdown_mapping.json",
);
const SHOWDOWN_PACKAGE_PATH = resolve(
  REPOSITORY_ROOT,
  "battle_server/node_modules/pokemon-showdown/package.json",
);
const SHOWDOWN_DEX_PATH = resolve(
  REPOSITORY_ROOT,
  "battle_server/node_modules/pokemon-showdown/dist/sim/dex.js",
);
const OUTPUT_PATH = resolve(REPOSITORY_ROOT, "data/creatures/experience.json");

const GROWTH_RATE_NAMES = [
  "slow",
  "medium",
  "fast",
  "medium-slow",
  "slow-then-very-fast",
  "fast-then-very-slow",
];

// Basis points avoid floating-point drift in the generated packed rows.
const TIER_MULTIPLIER_BASIS_POINTS = new Map([
  ["AG", 16000],
  ["Uber", 15000],
  ["OU", 13500],
  ["UUBL", 12800],
  ["UU", 12200],
  ["RUBL", 11600],
  ["RU", 11200],
  ["NUBL", 10800],
  ["NU", 10400],
  ["PUBL", 10000],
  ["PU", 9600],
  ["ZUBL", 9300],
  ["ZU", 9000],
  ["NFE", 8200],
  ["LC", 7500],
]);

const FALLBACK_BANDS = [
  { minimumBst: 670, label: "BST-670+", basisPoints: 15000 },
  { minimumBst: 600, label: "BST-600+", basisPoints: 13500 },
  { minimumBst: 540, label: "BST-540+", basisPoints: 12200 },
  { minimumBst: 480, label: "BST-480+", basisPoints: 11000 },
  { minimumBst: 420, label: "BST-420+", basisPoints: 10000 },
  { minimumBst: 330, label: "BST-330+", basisPoints: 9000 },
  { minimumBst: 0, label: "BST-under-330", basisPoints: 8000 },
];

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function floorRatio(numerator, denominator) {
  return Math.floor(numerator / denominator);
}

function experienceForLevel(growthRate, level) {
  if (level === 1) return 0;
  const cube = level ** 3;
  switch (growthRate) {
    case "slow":
      return floorRatio(5 * cube, 4);
    case "medium":
      return cube;
    case "fast":
      return floorRatio(4 * cube, 5);
    case "medium-slow":
      return Math.max(0, floorRatio(6 * cube, 5) - 15 * level ** 2 + 100 * level - 140);
    case "slow-then-very-fast":
      if (level <= 50) return floorRatio(cube * (100 - level), 50);
      if (level <= 68) return floorRatio(cube * (150 - level), 100);
      if (level <= 98) {
        const remainder = level % 3;
        const factor = 1274 + remainder ** 2 - 9 * remainder - 20 * Math.floor(level / 3);
        return floorRatio(cube * factor, 1000);
      }
      return floorRatio(cube * (160 - level), 100);
    case "fast-then-very-slow":
      if (level <= 15) return floorRatio(cube * (24 + Math.floor((level + 1) / 3)), 50);
      if (level <= 35) return floorRatio(cube * (14 + level), 50);
      return floorRatio(cube * (32 + Math.floor(level / 2)), 50);
    default:
      throw new Error(`Unknown PokeAPI growth rate: ${growthRate}`);
  }
}

function growthCurve(name) {
  const row = [0];
  for (let level = 1; level <= 100; level += 1) {
    row.push(experienceForLevel(name, level));
  }
  for (let level = 2; level <= 100; level += 1) {
    if (row[level] <= row[level - 1]) {
      throw new Error(`${name} experience is not increasing at level ${level}`);
    }
  }
  return row;
}

function normalizedTier(species) {
  const tierCandidates = [species.tier, species.natDexTier];
  for (const rawTier of tierCandidates) {
    const tier = String(rawTier ?? "").replace(/^\((.*)\)$/u, "$1");
    if (TIER_MULTIPLIER_BASIS_POINTS.has(tier)) return tier;
  }
  return "";
}

function fallbackBand(species) {
  const bst = Number(species.bst ?? 0);
  return FALLBACK_BANDS.find((band) => bst >= band.minimumBst) ?? FALLBACK_BANDS.at(-1);
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

  const indexBytes = readFileSync(INDEX_PATH);
  const index = JSON.parse(indexBytes.toString("utf8"));
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  const battleMappingBytes = readFileSync(BATTLE_MAPPING_PATH);
  const battleMapping = JSON.parse(battleMappingBytes.toString("utf8"));
  const mappingById = battleMapping.mappings;
  const defaultEntryBySpeciesId = new Map(
    index.pokemon
      .filter((entry) => entry.is_default)
      .map((entry) => [entry.species_id, entry]),
  );

  const speciesGrowthById = new Map();
  const tiers = [...TIER_MULTIPLIER_BASIS_POINTS.keys(), ...FALLBACK_BANDS.map((band) => band.label)];
  const tierIndexByName = new Map(tiers.map((tier, indexValue) => [tier, indexValue]));
  const pokemonRows = [];

  for (const pokemon of index.pokemon) {
    if (!speciesGrowthById.has(pokemon.species_id)) {
      const speciesPath = resolve(SPECIES_ROOT, `${pokemon.species_id}.json.gz`);
      const speciesRecord = JSON.parse(gunzipSync(readFileSync(speciesPath)).toString("utf8"));
      const growthRate = String(speciesRecord.growth_rate?.name ?? "");
      if (!GROWTH_RATE_NAMES.includes(growthRate)) {
        throw new Error(`Pokemon species ${pokemon.species_id} has invalid growth rate ${growthRate}`);
      }
      speciesGrowthById.set(pokemon.species_id, growthRate);
    }

    const exactMapping = mappingById[String(pokemon.id)];
    const defaultEntry = defaultEntryBySpeciesId.get(pokemon.species_id);
    const fallbackMapping = defaultEntry ? mappingById[String(defaultEntry.id)] : undefined;
    const showdownName = exactMapping?.species ?? fallbackMapping?.species ?? pokemon.name;
    const species = dex.species.get(showdownName);
    if (!species.exists) {
      throw new Error(`No Showdown species for Pokemon ${pokemon.id} (${pokemon.name})`);
    }

    let tier = normalizedTier(species);
    let multiplierBasisPoints;
    if (tier) {
      multiplierBasisPoints = TIER_MULTIPLIER_BASIS_POINTS.get(tier);
    } else {
      const band = fallbackBand(species);
      tier = band.label;
      multiplierBasisPoints = band.basisPoints;
    }
    const growthRate = speciesGrowthById.get(pokemon.species_id);
    pokemonRows.push([
      pokemon.id,
      GROWTH_RATE_NAMES.indexOf(growthRate),
      multiplierBasisPoints,
      tierIndexByName.get(tier),
    ]);
  }

  if (pokemonRows.length !== index.pokemon_count) {
    throw new Error("Generated experience Pokemon count is inconsistent");
  }

  return {
    schemaVersion: 1,
    pokemonShowdownVersion: packageJson.version,
    growthRateSource: "https://pokeapi.co/docs/v2#growth-rates",
    communityTierSource: "https://github.com/smogon/pokemon-showdown/blob/master/data/formats-data.ts",
    communityTierPolicy: "exact current singles tier, then National Dex tier, then exact-form BST band",
    pokeapiIndexSha256: sha256(indexBytes),
    pokeapiDatasetSha256: manifest.dataset_sha256,
    battleMappingSha256: sha256(battleMappingBytes),
    sourcePokemonCount: index.pokemon_count,
    growthRateNames: GROWTH_RATE_NAMES,
    experienceByGrowthRate: GROWTH_RATE_NAMES.map(growthCurve),
    communityTiers: tiers,
    tierMultiplierBasisPoints: Object.fromEntries(TIER_MULTIPLIER_BASIS_POINTS),
    fallbackBstBands: FALLBACK_BANDS,
    pokemonRowColumns: ["pokemonId", "growthRateIndex", "xpMultiplierBasisPoints", "communityTierIndex"],
    pokemonRows,
  };
}

const encoded = `${JSON.stringify(buildOutput())}\n`;
if (process.argv.includes("--check")) {
  if (readFileSync(OUTPUT_PATH, "utf8") !== encoded) {
    throw new Error(
      "Creature experience data is stale. Run tools/generate_creature_experience_data.mjs.",
    );
  }
  process.stdout.write("Creature experience data is current.\n");
} else {
  writeFileSync(OUTPUT_PATH, encoded);
  process.stdout.write(`Wrote ${OUTPUT_PATH}\n`);
}
