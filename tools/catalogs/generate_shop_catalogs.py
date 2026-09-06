#!/usr/bin/env python3
"""Generate the production item and Pokemon shop catalogs.

Items come from the same pinned PokeAPI api-data commit as the project's
creature snapshot. Pokemon rows come from the already-vendored creature index
and experience/tier table. Rarity, competitive demand, evolution stage, and a
small curated visual-appeal list create steep premiums for sought-after
Pokemon.
"""

from __future__ import annotations

import argparse
import gzip
import json
import math
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = ROOT / "game" / "economy" / "shop" / "catalogs"
ITEM_OUTPUT = OUTPUT_ROOT / "items.json"
POKEMON_OUTPUT = OUTPUT_ROOT / "pokemon.json"
CREATURE_INDEX = ROOT / "data" / "creatures" / "index.json"
EXPERIENCE_DATA = ROOT / "data" / "creatures" / "experience.json"
SPECIES_ROOT = ROOT / "data" / "creatures" / "species"
CREATURE_MANIFEST = ROOT / "data" / "creatures" / "manifest.json"

MIN_ITEM_PRICE = 5
ITEM_PRICE_ROUNDING = 5
XP_SHARE_ITEM_PRICE = 100_000
MIN_POKEMON_PRICE = 500
POKEMON_PRICE_INCREASE_NUMERATOR = 5
POKEMON_PRICE_INCREASE_DENOMINATOR = 4
EVOLUTION_PRICE_MARKUP_NUMERATOR = 3
EVOLUTION_PRICE_MARKUP_DENOMINATOR = 2
MIN_EVOLUTION_PRICE_INCREASE = 500

# Subjective by design: these are the recognizable, visually high-interest
# species that the shop marks up beyond their competitive tier. Keeping the
# list here makes the prototype taste decision obvious and easy to tune.
ICONIC_PRICE_FLOORS: dict[int, int] = {
    3: 20_000,
    6: 100_000,
    9: 25_000,
    25: 20_000,
    38: 20_000,
    59: 25_000,
    94: 100_000,
    130: 150_000,
    131: 75_000,
    133: 25_000,
    143: 100_000,
    149: 250_000,
    196: 75_000,
    197: 75_000,
    212: 150_000,
    248: 300_000,
    257: 175_000,
    282: 150_000,
    330: 75_000,
    350: 100_000,
    359: 75_000,
    373: 300_000,
    376: 300_000,
    445: 400_000,
    448: 300_000,
    461: 100_000,
    470: 75_000,
    471: 75_000,
    571: 175_000,
    609: 125_000,
    635: 300_000,
    658: 400_000,
    700: 125_000,
    706: 200_000,
    724: 200_000,
    745: 75_000,
    778: 200_000,
    823: 250_000,
    849: 125_000,
    887: 500_000,
    908: 150_000,
    911: 175_000,
    914: 125_000,
    937: 400_000,
    998: 400_000,
}

STARTER_IDS = {
    1, 4, 7, 152, 155, 158, 252, 255, 258, 387, 390, 393, 495, 498,
    501, 650, 653, 656, 722, 725, 728, 810, 813, 816, 906, 909, 912,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--item-source",
        type=Path,
        help=(
            "PokeAPI api-data checkout or its data/api/v2/item directory. "
            "Required when regenerating."
        ),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help=(
            "Validate committed catalogs and compare the locally generated Pokemon "
            "catalog byte for byte; item bytes also require --item-source."
        ),
    )
    parser.add_argument(
        "--pokemon-only",
        action="store_true",
        help="Regenerate only the Pokemon catalog from the vendored project snapshot.",
    )
    return parser.parse_args()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def compact_text(value: str) -> str:
    return " ".join(value.replace("\n", " ").replace("\r", " ").split())


def english_name(record: dict[str, Any]) -> str:
    for entry in record.get("names", []):
        if entry.get("language", {}).get("name") == "en":
            return compact_text(str(entry.get("name", "")))
    return display_slug(str(record.get("name", "Unknown item")))


def english_description(record: dict[str, Any]) -> str:
    for entry in record.get("effect_entries", []):
        if entry.get("language", {}).get("name") == "en":
            short_effect = compact_text(str(entry.get("short_effect", "")))
            if short_effect:
                return short_effect
    english_flavor = [
        compact_text(str(entry.get("text", "")))
        for entry in record.get("flavor_text_entries", [])
        if entry.get("language", {}).get("name") == "en"
    ]
    return english_flavor[-1] if english_flavor else "No effect description is available."


def display_slug(slug: str) -> str:
    words = [word for word in slug.replace("_", "-").split("-") if word]
    return " ".join(word[:1].upper() + word[1:] for word in words)


def round_up(value: float, unit: int) -> int:
    return int(math.ceil(value / unit) * unit)


def source_purchase_price(record: dict[str, Any]) -> int:
    prices = record.get("prices", [])
    candidates = [
        int(price["purchase_price"])
        for price in prices
        if price.get("currency", {}).get("name") == "poke-dollar"
        and isinstance(price.get("purchase_price"), int)
        and int(price["purchase_price"]) > 0
    ]
    return max(candidates, default=0)


def item_price(record: dict[str, Any]) -> int:
    source_price = source_purchase_price(record)
    category = str(record.get("category", {}).get("name", "miscellaneous"))
    attributes = {str(value.get("name", "")) for value in record.get("attributes", [])}
    slug = str(record.get("name", ""))
    price = max(MIN_ITEM_PRICE, source_price / 10)

    category_floors = {
        "status-cures": 10,
        "healing": 20,
        "medicine": 20,
        "standard-balls": 20,
        "special-balls": 50,
        "stat-boosts": 75,
        "held-items": 100,
        "revival": 250,
        "pp-recovery": 250,
        "evolution": 400,
        "effort-training": 500,
        "nature-mints": 500,
        "vitamins": 500,
        "species-specific": 750,
        "plates": 1_000,
        "memories": 1_000,
        "mega-stones": 5_000,
        "z-crystals": 5_000,
        "event-items": 10_000,
        "plot-advancement": 10_000,
    }
    price = max(price, category_floors.get(category, MIN_ITEM_PRICE))

    fixed_prices = {
        "potion": 20,
        "super-potion": 50,
        "hyper-potion": 120,
        "max-potion": 300,
        "poke-ball": 20,
        "great-ball": 60,
        "ultra-ball": 120,
        "revive": 250,
        "max-revive": 600,
        "rare-candy": 1_000,
        "ability-capsule": 5_000,
        "ability-patch": 10_000,
        "exp-share": XP_SHARE_ITEM_PRICE,
    }
    if slug in fixed_prices:
        price = fixed_prices[slug]
    if "mega-stones" in category or "z-crystals" in category:
        price = max(price, 5_000)
    if slug == "master-ball":
        price = max(price, 1_000_000)
    if "consumable" not in attributes:
        price = max(price, 100)
    return round_up(price, ITEM_PRICE_ROUNDING)


def resolve_item_root(source: Path) -> Path:
    candidates = [source, source / "data" / "api" / "v2" / "item"]
    for candidate in candidates:
        if candidate.is_dir() and any(candidate.glob("*/index.json")):
            return candidate
    raise ValueError(f"Could not find PokeAPI item records under {source}")


def generate_items(source: Path, source_commit: str) -> dict[str, Any]:
    item_root = resolve_item_root(source)
    records: list[dict[str, Any]] = []
    paths = sorted(
        (path for path in item_root.glob("*/index.json") if path.parent.name.isdigit()),
        key=lambda path: int(path.parent.name),
    )
    for path in paths:
        record = read_json(path)
        item_id = int(record.get("id", 0))
        slug = str(record.get("name", "")).strip()
        if item_id <= 0 or not slug:
            raise ValueError(f"Invalid PokeAPI item record: {path}")
        records.append(
            {
                "id": item_id,
                "slug": slug,
                "name": english_name(record),
                "category": str(record.get("category", {}).get("name", "miscellaneous")),
                "description": english_description(record),
                "price": item_price(record),
                "sourcePrice": source_purchase_price(record),
            }
        )
    records.sort(key=lambda item: (item["name"].casefold(), item["id"]))
    return {
        "schemaVersion": 2,
        "source": "PokeAPI/api-data",
        "sourceCommit": source_commit,
        "pricingPolicy": "Low-cash economy with collector premiums",
        "itemCount": len(records),
        "items": records,
    }


def read_species(species_id: int) -> dict[str, Any]:
    path = SPECIES_ROOT / f"{species_id}.json.gz"
    with gzip.open(path, "rt", encoding="utf-8") as source:
        value = json.load(source)
    if not isinstance(value, dict):
        raise ValueError(f"Invalid species record: {path}")
    return value


def pokemon_price_rounding(price: int | float) -> int:
    return 100_000 if price >= 1_000_000 else (100 if price >= 1_000 else 10)


def baseline_pokemon_price(
    pokemon_id: int,
    multiplier_basis_points: int,
    tier: str,
    capture_rate: int,
    is_legendary: bool,
    is_mythical: bool,
) -> int:
    tier_floors = {
        "AG": 1_000_000,
        "Uber": 500_000,
        "OU": 100_000,
        "UUBL": 50_000,
        "UU": 25_000,
        "RUBL": 15_000,
        "RU": 8_000,
        "NUBL": 5_000,
        "NU": 2_500,
        "PUBL": 1_500,
        "PU": 900,
        "ZUBL": 750,
        "ZU": 600,
        "NFE": 400,
        "LC": 200,
    }
    price = float(tier_floors.get(tier, 500))
    if capture_rate <= 15:
        price *= 8.0
    elif capture_rate <= 30:
        price *= 4.0
    elif capture_rate <= 45:
        price *= 2.0
    elif capture_rate <= 75:
        price *= 1.5

    # Preserve a modest influence from the project's established rarity/power
    # multiplier without making ordinary Pokemon unaffordable again.
    multiplier = multiplier_basis_points / 10_000.0
    price *= max(1.0, multiplier**2)
    if pokemon_id in STARTER_IDS:
        price = max(price, 2_500)
    price = max(price, ICONIC_PRICE_FLOORS.get(pokemon_id, 0))
    if is_legendary:
        price = max(price, 2_250_000_000)
    if is_mythical:
        price = max(price, 3_000_000_000)
    return round_up(price, pokemon_price_rounding(price))


def increased_pokemon_price(baseline_price: int) -> int:
    """Raise every prior offer and apply the new absolute shop floor."""
    increased = math.ceil(
        baseline_price
        * POKEMON_PRICE_INCREASE_NUMERATOR
        / POKEMON_PRICE_INCREASE_DENOMINATOR
    )
    increased = max(MIN_POKEMON_PRICE, increased)
    return round_up(increased, pokemon_price_rounding(increased))


def referenced_resource_id(value: Any) -> int | None:
    if not isinstance(value, dict):
        return None
    url = str(value.get("url", "")).strip().rstrip("/")
    final_segment = url.rsplit("/", 1)[-1]
    return int(final_segment) if final_segment.isdigit() else None


def evolution_stages(parent_by_pokemon: dict[int, int]) -> dict[int, int]:
    stages: dict[int, int] = {}
    visiting: set[int] = set()

    def resolve(pokemon_id: int) -> int:
        if pokemon_id in stages:
            return stages[pokemon_id]
        if pokemon_id in visiting:
            raise ValueError(f"Evolution cycle detected at Pokemon {pokemon_id}")
        visiting.add(pokemon_id)
        parent_id = parent_by_pokemon.get(pokemon_id)
        stage = resolve(parent_id) + 1 if parent_id is not None else 1
        visiting.remove(pokemon_id)
        stages[pokemon_id] = stage
        return stage

    for pokemon_id in parent_by_pokemon:
        resolve(pokemon_id)
    return stages


def enforce_evolution_prices(
    records: list[dict[str, Any]],
    parent_by_pokemon: dict[int, int],
) -> None:
    records_by_id = {int(record["id"]): record for record in records}
    stages = evolution_stages(parent_by_pokemon)
    for record in records:
        record["evolutionStage"] = stages.get(int(record["id"]), 1)
        record["evolvesFromId"] = parent_by_pokemon.get(int(record["id"]))

    for record in sorted(
        records,
        key=lambda value: (int(value["evolutionStage"]), int(value["id"])),
    ):
        parent_id = record["evolvesFromId"]
        if parent_id is None:
            continue
        parent_price = int(records_by_id[int(parent_id)]["price"])
        marked_up_price = math.ceil(
            parent_price
            * EVOLUTION_PRICE_MARKUP_NUMERATOR
            / EVOLUTION_PRICE_MARKUP_DENOMINATOR
        )
        required_price = max(
            parent_price + MIN_EVOLUTION_PRICE_INCREASE,
            marked_up_price,
        )
        record["price"] = max(
            int(record["price"]),
            round_up(required_price, pokemon_price_rounding(required_price)),
        )


def appeal_label(
    pokemon_id: int,
    capture_rate: int,
    is_legendary: bool,
    is_mythical: bool,
) -> str:
    if is_mythical:
        return "mythical"
    if is_legendary:
        return "legendary"
    if pokemon_id in ICONIC_PRICE_FLOORS or pokemon_id in STARTER_IDS:
        return "iconic"
    if capture_rate <= 45:
        return "rare"
    return "standard"


def generate_pokemon(source_commit: str) -> dict[str, Any]:
    index = read_json(CREATURE_INDEX)
    experience = read_json(EXPERIENCE_DATA)
    tiers = [str(value) for value in experience["communityTiers"]]
    profiles = {
        int(row[0]): {
            "multiplierBasisPoints": int(row[2]),
            "tier": tiers[int(row[3])],
        }
        for row in experience["pokemonRows"]
    }
    records: list[dict[str, Any]] = []
    species_cache: dict[int, dict[str, Any]] = {}
    default_entries = [
        entry for entry in index["pokemon"] if bool(entry.get("is_default", False))
    ]
    pokemon_by_species = {
        int(entry["species_id"]): int(entry["id"]) for entry in default_entries
    }
    parent_by_pokemon: dict[int, int] = {}
    for entry in default_entries:
        pokemon_id = int(entry["id"])
        species_id = int(entry["species_id"])
        if species_id not in species_cache:
            species_cache[species_id] = read_species(species_id)
        species = species_cache[species_id]
        profile = profiles[pokemon_id]
        capture_rate = int(species.get("capture_rate", 255))
        is_legendary = bool(species.get("is_legendary", False))
        is_mythical = bool(species.get("is_mythical", False))
        parent_species_id = referenced_resource_id(species.get("evolves_from_species"))
        if parent_species_id in pokemon_by_species:
            parent_by_pokemon[pokemon_id] = pokemon_by_species[parent_species_id]
        baseline_price = baseline_pokemon_price(
            pokemon_id,
            profile["multiplierBasisPoints"],
            profile["tier"],
            capture_rate,
            is_legendary,
            is_mythical,
        )
        price = increased_pokemon_price(baseline_price)
        records.append(
            {
                "id": pokemon_id,
                "slug": str(entry["name"]),
                "name": display_slug(str(entry["name"])),
                "tier": profile["tier"],
                "rarityMultiplierBasisPoints": profile["multiplierBasisPoints"],
                "captureRate": capture_rate,
                "appeal": appeal_label(
                    pokemon_id,
                    capture_rate,
                    is_legendary,
                    is_mythical,
                ),
                "isLegendary": is_legendary,
                "isMythical": is_mythical,
                "previousPrice": baseline_price,
                "price": price,
            }
        )
    enforce_evolution_prices(records, parent_by_pokemon)
    records.sort(key=lambda pokemon: pokemon["id"])
    for record in records:
        previous_price = int(record.pop("previousPrice"))
        if int(record["price"]) <= previous_price:
            raise ValueError(
                f"Pokemon {record['id']} did not increase above its previous price"
            )
    return {
        "schemaVersion": 2,
        "source": "project CreatureSystem default-form snapshot",
        "sourceCommit": source_commit,
        "pricingPolicy": (
            "$500 minimum, universal 25% increase, and strictly increasing "
            "50% evolution-stage minimums with tier, rarity, and appeal premiums"
        ),
        "minimumPokemonPrice": MIN_POKEMON_PRICE,
        "universalPriceIncreasePercent": 25,
        "minimumEvolutionMarkupPercent": 50,
        "minimumEvolutionPriceIncrease": MIN_EVOLUTION_PRICE_INCREASE,
        "pokemonCount": len(records),
        "pokemon": records,
    }


def encoded(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n"


def validate_committed() -> None:
    item_data = read_json(ITEM_OUTPUT)
    pokemon_data = read_json(POKEMON_OUTPUT)
    if int(item_data.get("itemCount", -1)) != len(item_data.get("items", [])):
        raise ValueError("Committed item catalog count is inconsistent")
    if int(pokemon_data.get("pokemonCount", -1)) != len(pokemon_data.get("pokemon", [])):
        raise ValueError("Committed Pokemon catalog count is inconsistent")
    if len(item_data["items"]) < 2_000:
        raise ValueError("Committed item catalog is unexpectedly incomplete")
    if len(pokemon_data["pokemon"]) != 1_025:
        raise ValueError("Committed Pokemon catalog must contain all 1,025 default species forms")
    items_by_slug = {
        str(record["slug"]): record for record in item_data["items"]
    }
    if int(items_by_slug.get("exp-share", {}).get("price", 0)) != XP_SHARE_ITEM_PRICE:
        raise ValueError(
            f"Exp. Share must cost exactly ${XP_SHARE_ITEM_PRICE:,}"
        )
    pokemon_by_id = {
        int(record["id"]): record for record in pokemon_data["pokemon"]
    }
    for record in pokemon_data["pokemon"]:
        pokemon_id = int(record["id"])
        price = int(record.get("price", 0))
        if price < MIN_POKEMON_PRICE:
            raise ValueError(f"Pokemon {pokemon_id} is below the ${MIN_POKEMON_PRICE} floor")
        parent_id = record.get("evolvesFromId")
        if parent_id is not None:
            if int(parent_id) not in pokemon_by_id:
                raise ValueError(f"Pokemon {pokemon_id} has an unknown evolution parent")
            if price <= int(pokemon_by_id[int(parent_id)]["price"]):
                raise ValueError(
                    f"Pokemon {pokemon_id} is not more expensive than evolution parent {parent_id}"
                )


def main() -> None:
    args = parse_args()
    manifest = read_json(CREATURE_MANIFEST)
    source_commit = str(manifest.get("source_commit", ""))
    if len(source_commit) != 40:
        raise ValueError("Creature manifest has no pinned source commit")

    pokemon_document = generate_pokemon(source_commit)
    expected = {POKEMON_OUTPUT: encoded(pokemon_document)}
    item_document: dict[str, Any] | None = None
    if args.item_source is not None:
        item_document = generate_items(args.item_source, source_commit)
        expected[ITEM_OUTPUT] = encoded(item_document)
    elif not args.check and not args.pokemon_only:
        raise ValueError(
            "--item-source is required when regenerating both catalogs; "
            "use --pokemon-only for the vendored Pokemon catalog"
        )

    if args.check:
        validate_committed()
        mismatches = [path for path, text in expected.items() if not path.exists() or path.read_text(encoding="utf-8") != text]
        if mismatches:
            raise SystemExit("Out-of-date shop catalogs: " + ", ".join(str(path) for path in mismatches))
        if args.item_source is None:
            print("Shop catalogs passed validation; Pokemon pricing matches vendored inputs.")
        else:
            print("Shop catalogs match the pinned PokeAPI source.")
        return

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    for path, text in expected.items():
        path.write_text(text, encoding="utf-8")
    if item_document is None:
        print(f"Generated {pokemon_document['pokemonCount']} Pokemon shop rows.")
    else:
        print(
            f"Generated {item_document['itemCount']} items and "
            f"{pokemon_document['pokemonCount']} Pokemon shop rows."
        )


if __name__ == "__main__":
    main()
