# Progression Autosave Contract

Use this document when changing automatic persistence, collection loading,
domain progression, legacy-save migration, or overworld pose checkpoints.
Verify the implementation and focused smoke test before changing the schema or
lifecycle.

## Runtime owner and schema

[`ProgressionAutosaveService`](../../game/save/progression_autosave.gd) is the
`ProgressionAutosave` autoload after the collection, move-learning, economy,
inventory, challenge, battle-reward, and starter-selection owners. It writes
schema version `6` to `user://pfr_rnd_progression.json`. The historical filename
is retained for existing installations; it does not indicate an R&D subsystem.

```json
{
  "schema_version": 6,
  "profile": {"starter_pokemon_id": 656},
  "collection": [{"pokemonId": 656, "pclID": "example-pcl-id"}],
  "move_learning": {"pending": []},
  "economy": {
    "version": 2,
    "balance": 50,
    "last_battle_reward": {}
  },
  "inventory": {
    "item_quantities": {},
    "claimed_gifts": []
  },
  "challenge_progression": {
    "earned_badges": [],
    "champion_completed": false,
    "completed_routes": [],
    "active_area_id": "",
    "run_defeated_ids": [],
    "run_id": 0
  },
  "world": {
    "scene_path": "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn",
    "player_position": [0.0, 0.0, 0.0],
    "player_rotation": [0.0, 0.0, 0.0],
    "visual_rotation": [0.0, 0.0, 0.0]
  },
  "save_meta": {
    "saved_at_ms": 1788134400000,
    "section_updated_at_ms": {
      "profile": 1788134400000,
      "collection": 1788134400000,
      "move_learning": 1788134400000,
      "economy": 1788134400000,
      "inventory": 1788134400000,
      "challenge_progression": 1788134400000,
      "world": 1788134400000
    }
  }
}
```

Each section is validated by its owner before any accepted load is committed.
`CollectionSystem.load_save_data()` atomically restores PCLs and their optional
held items. `MoveLearningSystem` validates pending choices against the incoming
collection. `EconomySystem`, `InventorySystem`, and
`ChallengeProgressionSystem` validate and load their own independent sections.
The route list must be unique, in range, and contiguous from Route 0.
Schema 6 reads schemas 1–5. A schema 2–5 `stretch` object is split into the
three production domains, including balance, battle reward, item quantities,
claimed gifts, badges, Champion completion, completed routes, active area,
defeated encounters, and run ID. Legacy destination dictionaries and encounter
IDs are mapped to the canonical 50-area catalog, and former city/Route 0/dynamic
world paths are mapped to their current authored scenes. An untouched legacy
`$5,000,000` bootstrap balance still migrates to the current `$50` start;
progressed saves are not reset. Pre-schema-5 saves receive fresh per-section
timestamps, while schema 5's former `stretch` timestamp seeds all three split
section timestamps.

## Automatic checkpoints

- `CollectionSystem.collection_changed`, `MoveLearningSystem.progression_changed`,
  and each of the economy, inventory, and challenge progression signals queue a
  0.35-second debounced write.
- A five-second timer detects a changed walkable-level player pose.
- Battle start checkpoints while the source player still exists.
- Ordinary scene-transfer start and completion checkpoint the source and then
  the marker-adjusted destination.
- Battle-return completion checkpoints the restored source pose.
- A window-close notification performs an immediate final write.

Battle scenes have no `PlayerCharacter`. A save caused by battle HP, XP, or
reward changes therefore retains the last walkable-level record instead of
replacing it with an empty battle location. Identical payloads do not rewrite
the file. The timestamp for a section advances only when that section's JSON
changes.

## Load, location, and reset behavior

The autoload attempts a load after the initial scene is ready. Without a valid
save it clears bootstrap collection/domain state and opens the mandatory
starter picker without writing an empty profile. Starter confirmation creates
the only initial PCL and writes the first checkpoint. A pose is applied only
when its `scene_path` equals the active scene, so F6 scene authoring does not
silently navigate elsewhere.

`save_now(force := false)`, `load_now()`, `request_autosave()`, and the
confirmation-gated `reset_all_progress()` are the checkpoint API.
`get_save_payload()` returns the same timestamped data without a Save ID.
`apply_cloud_payload()` runs a resolved cloud result through all normal
validators and immediately checkpoints it. `get_export_json()` and
`write_export_json(path)` serialize the same credential-free schema-6 payload.
`import_json_save()` accepts at most 2 MiB, preserves separate cloud linkage,
re-timestamps every imported section as a fresh local edit, and refuses
replacement during a battle, transfer, reset, or starter handoff.

Reset deletes the old local checkpoint, clears every progression owner and
session-level trainer state, returns to the canonical New Bouffalant City scene,
and suppresses saving until a new starter is chosen. Automatic disk I/O is
disabled when the process starts under `res://tests/`; focused tests may still
call immediate methods with an isolated temporary path.

Standard authored trainers' consumed automatic-sight IDs remain session-only.
Standalone challenge runs persist non-wild defeated encounter IDs so returning
from battle does not respawn a won opponent. Starting a new area run clears
those IDs. Route completion is separate and occurs only at the physical end
gate, so later-route unlocks survive a new run, scene change, and process
restart.

## Regression checks

```bash
godot --headless --path . --scene res://tests/integration/progression_autosave_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/starter_selection_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/cloud_save_sync_smoke_test.tscn
```

The autosave regression covers schema-6 disk output, all independent domain
sections, held items and claimed gifts, route unlocks and active challenge runs,
schema-5 migration, older schema defaults, legacy scene/encounter mapping,
credential-free JSON round trips, validated cloud application, and same-scene
pose restore.
