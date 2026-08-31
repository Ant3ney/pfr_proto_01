# R&D Level-Up Move Learning

Read this document when changing generated level-up learnsets, move-learning
queues, replacement presentation, battle sequencing, or persistence. Verify the
generator, runtime owner, and focused smoke tests before changing the contract.

## Data source and generation policy

[`generate_move_learnsets.mjs`](../../rnd/move_learning/tools/generate_move_learnsets.mjs)
derives the compact
[`level_up_learnsets.json`](../../rnd/move_learning/data/level_up_learnsets.json)
from the project's committed, compressed PokeAPI `pokemon` records. It generates
one row for each of the 1,351 local Pokemon IDs and keeps only Showdown move IDs
accepted by the pinned battle mapping.

For each exact form, the generator selects the first non-empty level-up
learnset in its explicit newest-conventional-game priority. An exact form with
no usable learnset falls back to its species' default-form record. Level-zero
evolution moves are excluded because they are not level thresholds. PokeAPI's
historical `vice-grip` spelling is explicitly mapped to Showdown's `visegrip`;
do not infer other aliases at runtime. The generated file records source hashes,
selected version groups, source-form IDs, display names, and packed level/move
rows. It is generated data and must not be hand-edited.

[`RNDMoveLearnsetCatalog`](../../rnd/move_learning/MoveLearnsetCatalog.gd)
validates that generated schema and every canonical move ID before returning
copied level-up rows, crossed-level results, move names, or source metadata.

## Runtime and choice ownership

`RNDMoveLearningSystem` is an autoload backed by
[`MoveLearningSystem.gd`](../../rnd/move_learning/MoveLearningSystem.gd). It
observes real `CollectionSystem.collection_changed` level increases and queues
every learnset threshold crossed, including several levels or several moves at
one level. It queues only battle-supported PCLs with a `battleProfile`, skips a
move already equipped, and caps persisted pending work at 512 requests.

Equipped moves remain owned by `CollectionSystem`. If the Pokemon has fewer
than four moves, the R&D system appends the learned move automatically through
`set_equipped_moves()`. At four moves,
[`MoveLearningUI`](../../rnd/move_learning/MoveLearningUI.gd) blocks play and
offers the four exact slots plus **Keep Current Moves**. Replacing a slot or
declining resolves only that request; multiple earned moves are presented in
order. The modal owns only presentation. It restores player movement only when
it acquired that lock and never bypasses CollectionSystem validation.

## Battle ordering and persistence

`BattleSystem` applies XP and emits an `experience` presentation event with the
participant `memberId`. After that message is presented,
[`BattleScene`](../../battle/BattleScene.gd) awaits all pending choices for that
member before acknowledging the response revision. The battle therefore stays
in `PRESENTING` and cannot expose the next request early. The in-flight server
team remains snapshot-authoritative, so a learned move is available in later
battles rather than changing the current server session.

ProgressionAutosave schema 3 stores only unresolved queue identity under
`move_learning.pending`: `pcl_id`, `pokemon_id`, `learned_level`, and `move_id`.
The loader validates each row against the incoming collection and generated
learnset before replacing state. Collection restore is bracketed by
`begin_save_restore()` and `finish_save_restore()` so loaded levels cannot be
mistaken for newly earned levels. Schema-1 and schema-2 saves load with an empty
move-learning queue.

## Regression checks

```bash
node rnd/move_learning/tools/generate_move_learnsets.mjs --check
godot --headless --path . --scene res://rnd/tests/move_learning_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/progression_autosave_smoke_test.tscn
godot --headless --path . --scene res://tests/collection_system_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_scene_lifecycle_test.tscn
```

The focused R&D test covers exact-form and fallback catalog selection, crossed
levels, same-level multi-move queues, automatic open-slot learning, four-slot
replacement and decline, touch/keyboard-capable modal behavior, movement-lock
restoration, queue validation, and pending-choice save restoration. Keep new
implementation under `rnd/move_learning/`; outside changes should remain thin
autoload, battle-presentation, autosave, export, test, and context wiring.
