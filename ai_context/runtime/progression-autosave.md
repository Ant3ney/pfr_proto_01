# RND Progression Autosave Contract

Use this document when changing automatic persistence, collection save loading,
or overworld pose checkpoints during the RND phase. Verify the implementation
and focused smoke test before changing the schema or lifecycle.

## Runtime owner and file

[`ProgressionAutosaveService`](../../rnd/save/ProgressionAutosave.gd) is registered
as the `ProgressionAutosave` autoload after the collection, battle,
starter-selection, move-learning, and Stretch progression owners. It writes
schema version `5` to
`user://pfr_rnd_progression.json`:

```json
{
  "schema_version": 5,
  "profile": {
    "starter_pokemon_id": 656
  },
  "collection": [
    {
      "pokemonId": 656,
      "pclID": "example-pcl-id"
    }
  ],
  "move_learning": {
    "pending": []
  },
  "stretch": {
    "economy_version": 2,
    "balance": 50,
    "item_inventory": {},
    "claimed_gifts": [],
    "earned_badges": [],
    "champion_cleared": false,
    "completed_routes": [],
    "active_destination": {},
    "run_defeated_ids": [],
    "run_id": 0,
    "last_battle_reward": {}
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
      "stretch": 1788134400000,
      "world": 1788134400000
    }
  }
}
```

The collection payload comes only from `CollectionSystem.get_save_data()` and
is restored only through its atomic `load_save_data()` validator. It includes
each PCL's optional `heldItem`; a rejected collection never partially replaces
the in-memory party. The `stretch` payload comes from `StretchGoalSystem`, is
validated before either owner is loaded, and persists money, purchased-item
counts, one-time world gift claims, badges, Champion completion, the contiguous
Route 0–39 completion sequence, and the active generated run. A later route is
unlocked only when the preceding route is in `completed_routes`; validation
rejects skipped route IDs. The `move_learning` payload comes from
`MoveLearningSystem`, contains only unresolved level-up move choices, and is
validated against the incoming collection and generated learnset before load.
The `profile` payload introduced in schema 4 records the original Charmander,
Froakie, or Treecko choice. Schema 5 adds monotonic local wall-clock metadata
for the five independently mergeable sections. The timestamp changes only when
that section's JSON changes, so a periodic location check does not make every
domain look newer. Schema-1 saves remain readable and acquire fresh Stretchman
defaults; schema-1 and schema-2 saves acquire an empty move-learning queue, and
schema-1 through schema-3 saves acquire legacy starter identity without losing
their collection. Schema-1 through schema-4 saves acquire timestamp metadata
on load. An untouched legacy R&D balance of `$5,000,000` migrates to the current
`$50` start; progressed saves are not silently reset.

## Automatic checkpoints

- `CollectionSystem.collection_changed` queues a 0.35-second debounced write.
- `MoveLearningSystem.progression_changed` uses the same debounced write.
- `StretchGoalSystem.progression_changed` uses the same debounced write.
- A five-second timer detects and persists changed overworld player poses.
- Battle start writes while the source player still exists.
- Ordinary scene-transfer start and completion checkpoint the source and then
  the marker-adjusted destination.
- Battle-return completion checkpoints the restored source pose.
- A window close notification performs an immediate final write.

Battle scenes have no `PlayerCharacter`. Saving battle HP or XP therefore
retains the last overworld world record instead of replacing it with an empty
battlefield location. Identical payloads do not rewrite the file.

## Load and location behavior

The autoload attempts a load after the initial scene is ready. If no valid save
exists, it clears bootstrap state and opens the mandatory animated starter
picker without writing an empty profile. Starter confirmation creates the only
initial PCL and writes the first checkpoint. A saved pose is applied only when
its `scene_path` equals the active scene; autosave does not silently navigate
away from an editor-run or intentionally selected scene.

`save_now(force := false)`, `load_now()`, `request_autosave()`, and the
confirmation-gated `reset_all_progress()` are the ordinary RND checkpoint API.
`get_save_payload()` returns the same timestamped data without a Save ID;
`apply_cloud_payload()` runs an already-resolved cloud result through the normal
validators and immediately checkpoints it locally. `get_export_json()` and
`write_export_json(path)` serialize that same credential-free schema-5 payload
for portable backups. `import_json_save(source, source_label)` accepts at most
2 MiB, reuses the disk/cloud validators, immediately replaces the local
checkpoint, and re-timestamps every section as a fresh monotonic local change.
It preserves the separate cloud linkage and is refused while a battle,
transition, reset, or starter handoff makes replacement unsafe. See
[`cloud-save.md`](cloud-save.md) for the optional sync owner and conflict rules.
Reset deletes the old file and all progression owners, returns to the main
scene, and suppresses saving until a new starter is chosen. Automatic disk I/O
is disabled when the process starts in
`res://tests/` or `res://rnd/tests/`; focused tests can still call the immediate
methods with an isolated temporary path.

Normal authored trainers consume automatic sight for the current process and
remain manually interactable for rematches. Those consumed standard-trainer IDs
are intentionally session-only and are not part of schema 5. A full profile
reset explicitly clears them from the current process. Stretchman's
generated destination runs separately persist their stable defeated encounter
IDs so a won route, gym, or Champion opponent stays removed when that generated
scene reloads after battle; a newly started run clears those IDs and restores
its Highly Aggro sight encounters. Route completion is separate from those run
IDs: touching the physical far-end gate persists `completed_routes`, so the
next route stays unlocked after a new run, scene change, or process restart.

## Regression check

```bash
godot --headless --path . --scene res://tests/integration/progression_autosave_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/starter_selection_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/cloud_save_sync_smoke_test.tscn
```

The test uses a dedicated temporary `user://` filename and removes it after
verifying disk write, validated collection reload, a pending level-up move
choice, a held Exp. Share, a claimed world gift, and same-scene pose restore.
It also verifies Stretchman economy restoration and the Route 0 clear/Route 1
unlock from the same checkpoint, schema-5 section timestamps, credential-free
JSON export, JSON round-trip replacement, and validated cloud-payload
application. The starter test covers schema-5 profile creation and complete
destructive reset; the cloud test covers linked JSON-import synchronization and
in-flight local-change rebasing without contacting an external service.
