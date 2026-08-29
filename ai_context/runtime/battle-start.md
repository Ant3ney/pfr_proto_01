# Battle Start, Reveal, and Return Contract

Read this document when changing trainer launch data, cross-scene transition
timing, battle-scene entry, failure presentation, return-to-world ordering, or
one-scene encounter suppression. Verify the current scripts and lifecycle tests
before changing this contract.

## Launch boundary

[`GameInstance.startBattle(battle_data := {})`](../../core/GameInstance.gd) is
the single transition entry point. Callers identify an authored battle scene and
encounter; they never pass player or opponent team DTOs:

```gdscript
GameInstance.startBattle({
	"encounter_type": "trainer",
	"trainer_name": "Trainer Kyle",
	"battle_scene_path": "res://battle/kyle_battle_scene.tscn",
	"encounter_id": "trainer-kyle-lake-v1",
})
```

`TrainerBehavior` closes its dialog through the normal `UITemplate.close()`
lifecycle, releases its dialog lock, and transfers control to `startBattle()`.
Kyle's controller supplies only the stable ID and concrete scene path.

`GameInstance` deep-copies launch data, captures `source_scene_path`, fills the
transition title/subtitle, locks movement, and covers the old scene before
loading `battle_scene_path`. `return_scene_path` remains launch metadata for
legacy callers; completed networked battles always return through
`BattleSystem` to `res://demo/modular_ground_scene.tscn`.

## Covered connection and reveal

The same autoload-owned transition template stays fully covered while the new
scene connects:

| Stage | Owner and verified action |
| --- | --- |
| Launch accepted | `GameInstance` locks movement, stores defensive launch data, and begins the cover |
| Cover complete | `GameInstance` loads the requested concrete battle scene |
| Scene ready | `BattleScene` calls `enter_battle_scene()`, which promotes pending data but does not reveal |
| Session preflight | `BattleSystem` discovers exactly one `battle_encounter_provider`, validates its resource, reads `CollectionSystem.get_battle_party_members()`, and sends the start DTO |
| Valid response | `BattleSystem` validates versions/identity/revision/schema, atomically writes player HP, then emits the presentation snapshot/events |
| Reveal | The adapter calls `GameInstance.reveal_battle_scene()` and starts its local intro only after that accepted response |
| Intro complete | `GameInstance` waits for both transition reveal and local intro, retires the transition template, and emits `battle_start_finished` |
| HUD | `BattleScene` creates a second template for the persistent request-driven HUD and presents queued events before acknowledging the revision |

A start transport failure leaves the cover and movement lock in place. The
battle interaction layer renders Retry and Return above the cover. Retrying
reuses the exact pending bytes. A valid initial response is the only networked
path that reveals the battlefield.

## Direct visual preview

Opening `res://battle/battle_scene.tscn` directly remains network-free. With no
active launch handoff it plays its local intro and shows presentation defaults.
The legacy default-scene transition path without an encounter ID is also kept
offline for focused transition smoke tests. Production trainer entry uses the
concrete Kyle scene and therefore always goes through `BattleSystem`.

## Completion and return

After all response events are acknowledged, `BattleSystem` emits the server
result and waits for `continue_after_result()`. Win, loss, tie, forfeit, and
unrecoverable-error returns all use this ordering:

1. Enter `RETURNING`, cancel callbacks, and clear token/session data.
2. Ask `GameInstance.return_from_battle()` to cover the battlefield.
3. Change to `res://demo/modular_ground_scene.tscn` without restoring a saved
   transform, so the scene's authored player spawn is used.
4. Clear active launch data and enable movement only from `scene_changed`, after
   the modular scene is ready.
5. Reveal the overworld and emit `battle_return_finished`; `BattleSystem` then
   returns to `IDLE`.

The completed encounter ID is retained only for that returned scene instance.
`TrainerBehavior` checks `GameInstance.is_encounter_suppressed()` before any
detection and starts Kyle in `COMPLETE`. Loading another scene clears the ID.
This is trigger suppression, not persistent trainer progression or a rematch
system.

## Ownership boundaries

- `GameInstance`: scene changes, transition template, movement lock, one-scene
  suppression.
- `BattleSystem`: encounter/party DTOs, REST session, tokens, revisions,
  validation, retries, snapshots, event ordering, HP writeback, outcome.
- `BattleScene`: thin signal-to-visual and UI-intent adapter.
- `UITemplate` and `BattleChoiceOverlay`: input/presentation surfaces only.

Every dictionary emitted from the battle coordinator or returned by a public
getter is a deep copy. The state token never enters launch data, presentation
state, logs, save data, or scene scripts.

## Regression checks

```bash
godot --headless --path . --scene res://tests/battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/trainer_dialog_battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_system_session_test.tscn
godot --headless --path . --scene res://tests/battle_scene_lifecycle_test.tscn
```

These cover the offline preview path, concrete provider discovery, covered
connection, deep-copy boundaries, request-driven locking, event acknowledgement,
confirmed forfeit, ordered return, movement restoration, and Kyle suppression.
