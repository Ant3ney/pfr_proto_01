#!/usr/bin/env python3
"""Vendor the PokeAPI creature records used by the Godot Creature System.

The importer reads PokeAPI's official api-data repository instead of issuing one
HTTP request per Pokemon. Each JSON record is compacted and gzip-compressed
without changing its JSON content. The Godot runtime then loads records lazily.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any


REPOSITORY_URL = "https://github.com/PokeAPI/api-data.git"
DEFAULT_OUTPUT = Path("data/creatures")
ENDPOINTS = ("pokemon", "pokemon-species", "evolution-chain")
SCHEMA_VERSION = 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        help="Existing checkout of PokeAPI/api-data (avoids a temporary clone).",
    )
    parser.add_argument(
        "--ref",
        default="master",
        help="PokeAPI/api-data branch, tag, or commit to import (default: master).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Generated dataset directory (default: data/creatures).",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Verify the existing output without downloading or replacing it.",
    )
    args = parser.parse_args()
    if args.verify and args.source:
        parser.error("--source cannot be combined with --verify")
    return args


def run(command: list[str], cwd: Path | None = None) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return completed.stdout.strip()


def clone_source(destination: Path, git_ref: str) -> Path:
    run(
        [
            "git",
            "clone",
            "--depth",
            "1",
            "--filter=blob:none",
            "--sparse",
            REPOSITORY_URL,
            str(destination),
        ]
    )
    run(["git", "fetch", "--depth", "1", "origin", git_ref], destination)
    run(["git", "checkout", "--detach", "FETCH_HEAD"], destination)
    run(
        [
            "git",
            "sparse-checkout",
            "set",
            *(f"data/api/v2/{endpoint}" for endpoint in ENDPOINTS),
        ],
        destination,
    )
    return destination


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as source_file:
        return json.load(source_file)


def write_json(path: Path, value: Any, *, pretty: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if pretty:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ).encode("utf-8") + b"\n"
    else:
        encoded = json.dumps(
            value,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
    path.write_bytes(encoded)


def write_compressed_json(path: Path, value: Any) -> None:
    compact_json = json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    compressed = io.BytesIO()
    with gzip.GzipFile(
        filename="",
        mode="wb",
        fileobj=compressed,
        compresslevel=9,
        mtime=0,
    ) as compressed_file:
        compressed_file.write(compact_json)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(compressed.getvalue())


def record_paths(endpoint_root: Path) -> list[Path]:
    paths = [
        path
        for path in endpoint_root.glob("*/index.json")
        if path.parent.name.isdigit()
    ]
    return sorted(paths, key=lambda path: int(path.parent.name))


def resource_id(resource: Any, field_name: str) -> int:
    if not isinstance(resource, dict) or not isinstance(resource.get("url"), str):
        raise ValueError(f"{field_name} is missing its PokeAPI resource URL")
    segments = [segment for segment in resource["url"].split("/") if segment]
    if not segments or not segments[-1].isdigit():
        raise ValueError(f"{field_name} has an invalid resource URL: {resource['url']}")
    return int(segments[-1])


def git_metadata(source: Path) -> tuple[str, str]:
    try:
        commit = run(["git", "rev-parse", "HEAD"], source)
        commit_date = run(["git", "show", "-s", "--format=%cI", "HEAD"], source)
    except (subprocess.CalledProcessError, FileNotFoundError):
        commit = "unknown-local-source"
        commit_date = "unknown"
    return commit, commit_date


def dataset_digest(root: Path) -> str:
    digest = hashlib.sha256()
    included_paths = sorted(
        [root / "index.json"]
        + list((root / "encounters").glob("*.json.gz"))
        + list((root / "pokemon").glob("*.json.gz"))
        + list((root / "species").glob("*.json.gz"))
        + list((root / "evolution_chains").glob("*.json.gz")),
        key=lambda path: path.relative_to(root).as_posix(),
    )
    for path in included_paths:
        relative_path = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(relative_path)
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def import_dataset(source: Path, staging_root: Path) -> dict[str, int]:
    api_root = source / "data" / "api" / "v2"
    endpoint_roots = {endpoint: api_root / endpoint for endpoint in ENDPOINTS}
    for endpoint, endpoint_root in endpoint_roots.items():
        if not endpoint_root.is_dir():
            raise FileNotFoundError(
                f"PokeAPI source is missing data/api/v2/{endpoint}: {source}"
            )

    pokemon_paths = record_paths(endpoint_roots["pokemon"])
    species_paths = record_paths(endpoint_roots["pokemon-species"])
    evolution_paths = record_paths(endpoint_roots["evolution-chain"])
    if not pokemon_paths or not species_paths or not evolution_paths:
        raise ValueError("PokeAPI source did not contain all required record groups")

    species_by_id: dict[int, dict[str, Any]] = {}
    for path in species_paths:
        species = read_json(path)
        species_id = int(species["id"])
        if species_id != int(path.parent.name):
            raise ValueError(f"Species ID/path mismatch in {path}")
        species_by_id[species_id] = species
        write_compressed_json(
            staging_root / "species" / f"{species_id}.json.gz",
            species,
        )

    evolution_ids: set[int] = set()
    for path in evolution_paths:
        evolution_chain = read_json(path)
        evolution_id = int(evolution_chain["id"])
        if evolution_id != int(path.parent.name):
            raise ValueError(f"Evolution-chain ID/path mismatch in {path}")
        evolution_ids.add(evolution_id)
        write_compressed_json(
            staging_root / "evolution_chains" / f"{evolution_id}.json.gz",
            evolution_chain,
        )

    entries: list[dict[str, Any]] = []
    seen_names: set[str] = set()
    default_count = 0
    encounter_count = 0
    for path in pokemon_paths:
        pokemon = read_json(path)
        pokemon_id = int(pokemon["id"])
        if pokemon_id != int(path.parent.name):
            raise ValueError(f"Pokemon ID/path mismatch in {path}")

        pokemon_name = str(pokemon["name"])
        if pokemon_name in seen_names:
            raise ValueError(f"Duplicate Pokemon name: {pokemon_name}")
        seen_names.add(pokemon_name)

        species_id = resource_id(pokemon.get("species"), "pokemon.species")
        if species_id not in species_by_id:
            raise ValueError(
                f"Pokemon {pokemon_id} references missing species {species_id}"
            )
        evolution_id = resource_id(
            species_by_id[species_id].get("evolution_chain"),
            "pokemon_species.evolution_chain",
        )
        if evolution_id not in evolution_ids:
            raise ValueError(
                f"Species {species_id} references missing evolution chain {evolution_id}"
            )

        is_default = bool(pokemon["is_default"])
        if is_default:
            default_count += 1
        entries.append(
            {
                "evolution_chain_id": evolution_id,
                "id": pokemon_id,
                "is_default": is_default,
                "name": pokemon_name,
                "species_id": species_id,
            }
        )
        write_compressed_json(
            staging_root / "pokemon" / f"{pokemon_id}.json.gz",
            pokemon,
        )
        encounters_path = path.parent / "encounters" / "index.json"
        if not encounters_path.is_file():
            raise FileNotFoundError(
                f"Pokemon {pokemon_id} is missing its encounters record"
            )
        encounters = read_json(encounters_path)
        if not isinstance(encounters, list):
            raise ValueError(
                f"Pokemon {pokemon_id} encounters record is not a JSON array"
            )
        write_compressed_json(
            staging_root / "encounters" / f"{pokemon_id}.json.gz",
            encounters,
        )
        encounter_count += 1

    source_index = read_json(endpoint_roots["pokemon"] / "index.json")
    if int(source_index.get("count", -1)) != len(entries):
        raise ValueError(
            "PokeAPI pokemon index count does not match the imported records"
        )

    index = {
        "default_pokemon_count": default_count,
        "pokemon": entries,
        "pokemon_count": len(entries),
        "schema_version": SCHEMA_VERSION,
    }
    write_json(staging_root / "index.json", index, pretty=True)

    return {
        "default_pokemon": default_count,
        "encounters": encounter_count,
        "evolution_chains": len(evolution_ids),
        "pokemon": len(entries),
        "species": len(species_by_id),
    }


def read_compressed_json(path: Path) -> Any:
    with gzip.open(path, "rt", encoding="utf-8") as compressed_file:
        return json.load(compressed_file)


def verify_dataset(root: Path) -> dict[str, int]:
    index_path = root / "index.json"
    manifest_path = root / "manifest.json"
    if not index_path.is_file() or not manifest_path.is_file():
        raise FileNotFoundError(f"Creature dataset is incomplete: {root}")

    index = read_json(index_path)
    manifest = read_json(manifest_path)
    entries = index.get("pokemon")
    if not isinstance(entries, list):
        raise ValueError("Creature index is missing its pokemon list")

    seen_ids: set[int] = set()
    seen_names: set[str] = set()
    species_ids: set[int] = set()
    evolution_ids: set[int] = set()
    default_count = 0
    encounter_count = 0
    for entry in entries:
        pokemon_id = int(entry["id"])
        pokemon_name = str(entry["name"])
        species_id = int(entry["species_id"])
        evolution_id = int(entry["evolution_chain_id"])
        if pokemon_id in seen_ids or pokemon_name in seen_names:
            raise ValueError(f"Duplicate creature index entry: {entry}")
        seen_ids.add(pokemon_id)
        seen_names.add(pokemon_name)
        species_ids.add(species_id)
        evolution_ids.add(evolution_id)
        default_count += int(bool(entry["is_default"]))

        pokemon = read_compressed_json(root / "pokemon" / f"{pokemon_id}.json.gz")
        if int(pokemon["id"]) != pokemon_id or pokemon["name"] != pokemon_name:
            raise ValueError(f"Pokemon record does not match index entry {pokemon_id}")
        if resource_id(pokemon.get("species"), "pokemon.species") != species_id:
            raise ValueError(f"Pokemon/species mismatch for {pokemon_id}")
        encounters = read_compressed_json(
            root / "encounters" / f"{pokemon_id}.json.gz"
        )
        if not isinstance(encounters, list):
            raise ValueError(f"Pokemon encounters are not an array for {pokemon_id}")
        encounter_count += 1

    for species_id in species_ids:
        species = read_compressed_json(root / "species" / f"{species_id}.json.gz")
        if int(species["id"]) != species_id:
            raise ValueError(f"Species record ID mismatch for {species_id}")
        if (
            resource_id(
                species.get("evolution_chain"),
                "pokemon_species.evolution_chain",
            )
            not in evolution_ids
        ):
            raise ValueError(f"Species {species_id} has an unindexed evolution chain")

    for evolution_id in evolution_ids:
        evolution_chain = read_compressed_json(
            root / "evolution_chains" / f"{evolution_id}.json.gz"
        )
        if int(evolution_chain["id"]) != evolution_id:
            raise ValueError(f"Evolution-chain record ID mismatch for {evolution_id}")

    counts = {
        "default_pokemon": default_count,
        "encounters": encounter_count,
        "evolution_chains": len(evolution_ids),
        "pokemon": len(seen_ids),
        "species": len(species_ids),
    }
    expected_counts = manifest.get("counts")
    if counts != expected_counts:
        raise ValueError(f"Manifest counts {expected_counts} do not match {counts}")
    if int(index.get("pokemon_count", -1)) != counts["pokemon"]:
        raise ValueError("Creature index pokemon_count is incorrect")
    if int(index.get("default_pokemon_count", -1)) != counts["default_pokemon"]:
        raise ValueError("Creature index default_pokemon_count is incorrect")

    actual_digest = dataset_digest(root)
    if manifest.get("dataset_sha256") != actual_digest:
        raise ValueError("Creature dataset SHA-256 does not match the manifest")
    return counts


def write_support_files(
    source: Path,
    staging_root: Path,
    counts: dict[str, int],
) -> None:
    commit, commit_date = git_metadata(source)
    source_license = source / "LICENSE.txt"
    if not source_license.is_file():
        raise FileNotFoundError(f"PokeAPI license is missing: {source_license}")
    shutil.copyfile(source_license, staging_root / "POKEAPI_LICENSE.txt")

    readme = """# Local Creature Data

This generated directory contains the local, losslessly compressed PokeAPI
`pokemon`, Pokemon encounter, `pokemon-species`, and `evolution-chain` JSON
records consumed by `CreatureSystem`. Do not hand-edit generated records.

From the repository root:

```sh
python3 tools/sync_pokeapi_data.py
python3 tools/sync_pokeapi_data.py --verify
```

The source revision, record counts, and content digest are recorded in
`manifest.json`. PokeAPI's license is preserved in `POKEAPI_LICENSE.txt`.
Sprites and cries are represented by the original URL fields; binary media is
not part of this stat-data snapshot.
"""
    (staging_root / "README.md").write_text(readme, encoding="utf-8")

    manifest = {
        "counts": counts,
        "dataset_sha256": dataset_digest(staging_root),
        "record_encoding": "utf-8 JSON compressed as deterministic gzip",
        "schema_version": SCHEMA_VERSION,
        "source_commit": commit,
        "source_commit_date": commit_date,
        "source_repository": REPOSITORY_URL,
    }
    write_json(staging_root / "manifest.json", manifest, pretty=True)


def replace_output(staging_root: Path, output: Path) -> None:
    output = output.resolve()
    if output == Path(output.anchor) or output == Path.cwd().resolve():
        raise ValueError("Refusing to replace a filesystem or working-directory root")
    output.parent.mkdir(parents=True, exist_ok=True)
    backup = output.parent / f".{output.name}.previous"
    if backup.exists():
        shutil.rmtree(backup)

    had_output = output.exists()
    if had_output:
        output.rename(backup)
    try:
        staging_root.rename(output)
    except Exception:
        if had_output and backup.exists() and not output.exists():
            backup.rename(output)
        raise
    if backup.exists():
        shutil.rmtree(backup)


def main() -> int:
    args = parse_args()
    output = args.output.resolve()
    if args.verify:
        counts = verify_dataset(output)
        print(f"Creature dataset verified: {counts}")
        return 0

    with tempfile.TemporaryDirectory(prefix="pfr-pokeapi-") as temporary:
        temporary_root = Path(temporary)
        source = args.source.resolve() if args.source else None
        if source is None:
            source = clone_source(temporary_root / "api-data", args.ref)

        output.parent.mkdir(parents=True, exist_ok=True)
        staging_root = Path(
            tempfile.mkdtemp(prefix=f".{output.name}-", dir=output.parent)
        )
        staging_root.chmod(0o755)
        try:
            counts = import_dataset(source, staging_root)
            write_support_files(source, staging_root, counts)
            verify_dataset(staging_root)
            replace_output(staging_root, output)
        finally:
            if staging_root.exists():
                shutil.rmtree(staging_root)

    print(f"Creature dataset synchronized: {counts}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
