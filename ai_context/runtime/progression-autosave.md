# RND Progression Autosave Contract

Use this document when changing automatic persistence, collection save loading,
or overworld pose checkpoints during the RND phase. Verify the implementation
and focused smoke test before changing the schema or lifecycle.

## Runtime owner and file

[`RNDProgressionAutosave`](../../rnd/save/ProgressionAutosave.gd) is registered
as the `ProgressionAutosave` autoload after the collection, battle,
move-learning, and Stretch progression owners. It writes schema version `3` to
`user://pfr_rnd_progression.json`:

```json
{
  "schema_version": 3,
  "collection": [],
  "move_learning": {
    "pending": []
  },
  "stretch": {
    "economy_version": 2,
    "balance": 500,
    "item_inventory": {},
    "earned_badges": [],
    "champion_cleared": false,
    "active_destination": {},
    "run_defeated_ids": [],
    "run_id": 0,
    "last_battle_reward": {}
  },
  "world": {
    "scene_path": "res://demo/primary_development_enviroment.tscn",
    "player_position": [0.0, 0.0, 0.0],
    "player_rotation": [0.0, 0.0, 0.0],
    "visual_rotation": [0.0, 0.0, 0.0]
  }
}
```

The collection payload comes only from `CollectionSystem.get_save_data()` and
is restored only through its atomic `load_save_data()` validator. A rejected
collection never partially replaces the in-memory party. The `stretch` payload
comes from `StretchGoalSystem`, is validated before either owner is loaded, and
persists money, purchased-item counts, badges, Champion completion, and the
active generated run. The `move_learning` payload comes from
`RNDMoveLearningSystem`, contains only unresolved level-up move choices, and is
validated against the incoming collection and generated learnset before load.
Schema-1 saves remain readable and acquire fresh Stretchman defaults; schema-1
and schema-2 saves acquire an empty move-learning queue. An untouched legacy
R&D balance of `$5,000,000` migrates to the current `$500` start; progressed
saves are not silently reset.

## Automatic checkpoints

- `CollectionSystem.collection_changed` queues a 0.35-second debounced write.
- `RNDMoveLearningSystem.progression_changed` uses the same debounced write.
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
exists, it writes the starting collection and current player pose. A saved pose
is applied only when its `scene_path` equals the active scene; autosave does not
silently navigate away from an editor-run or intentionally selected scene.

`save_now(force := false)`, `load_now()`, and `request_autosave()` are the public
RND checkpoint API. Automatic disk I/O is disabled when the process starts in
`res://tests/` or `res://rnd/tests/`; focused tests can still call the immediate
methods with an isolated temporary path.

Normal authored trainers consume automatic sight for the current process and
remain manually interactable for rematches. Those consumed standard-trainer IDs
are intentionally session-only and are not part of schema 3. Stretchman's
generated destination runs separately persist their stable defeated encounter
IDs so a won route, gym, or Champion opponent stays removed when that generated
scene reloads after battle; a newly started run clears those IDs and restores
its Highly Aggro sight encounters.

## Regression check

```bash
godot --headless --path . --scene res://rnd/tests/progression_autosave_smoke_test.tscn
```

The test uses a dedicated temporary `user://` filename and removes it after
verifying disk write, validated collection reload, a pending level-up move
choice, and same-scene pose restore. It also verifies Stretchman economy
restoration from the same checkpoint.
