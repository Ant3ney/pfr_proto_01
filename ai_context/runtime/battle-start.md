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
	"battle_scene_path": "res://game/battle/scenes/kyle_battle_scene.tscn",
	"encounter_id": "trainer-kyle-lake-v1",
	"trainer_aggression_mode": TrainerBehavior.AggressionMode.STANDARD,
})
```

`TrainerBehavior` closes its dialog through the normal `UITemplate.close()`
lifecycle, releases its dialog lock, and transfers control to `startBattle()`.
Each trainer controller supplies only its stable ID and matching concrete scene
path. Kyle uses `trainer-kyle-lake-v1` with `kyle_battle_scene.tscn`. The city
lineup uses stable `trainer-<role>-city-v1` IDs with matching concrete battle
scenes for Delivery Worker, Police Officer, Businessman, Backpacker, Jogger,
and Tourist. Every lineup trainer owns an independent encounter resource even
when two encounters happen to reuse a species.

`trainer_aggression_mode` distinguishes ordinary authored trainers from
Stretchman's `HIGHLY_AGGRO` opponents. `GameInstance` records a standard
trainer's accepted encounter ID as sight-consumed for the current play session;
Highly Aggro launches do not enter that set.

Route 0 wild grass follows the same launch boundary without a trainer dialog.
`TallGrassEncounterZone` supplies `encounter_type = "wild"`, the concrete
`route_0_wild_battle_scene.tscn`, and stable ID
`wild-fletchling-route-0-v1`; the scene-local provider owns the matching
Fletchling encounter resource. Distance and chance logic stay in the overworld
zone and opponent DTO construction stays in `BattleSystem`.

`GameInstance` deep-copies launch data, captures `source_scene_path`, the source
player's global transform and visual facing, fills the transition
title/subtitle, locks movement, and covers the old scene before loading
`battle_scene_path`. Unless a caller supplies an explicit override,
`return_scene_path` is the captured source scene. `BattleSystem` requests this
implicit return instead of hard-coding one overworld.

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

Opening `res://game/battle/scenes/battle_scene.tscn` directly remains network-free. With no
active launch handoff it plays its local intro and shows presentation defaults.
The legacy default-scene transition path without an encounter ID is also kept
offline for focused transition smoke tests. Production trainer entry uses a
concrete encounter scene and therefore always goes through `BattleSystem`.
The launch ID must equal the ID authored by that scene's encounter provider;
the mismatch guard intentionally rejects cross-wired trainer and battle scenes.

## Completion and return

After all response events are acknowledged, `BattleSystem` emits the server
result and waits for `continue_after_result()`. Win, loss, tie, forfeit, and
unrecoverable-error returns all use this ordering:

1. Enter `RETURNING`, cancel callbacks, and clear token/session data.
2. Ask `GameInstance.return_from_battle()` to cover the battlefield.
3. Resolve an explicit launch override when present, otherwise change back to
   the captured source scene.
4. When returning to that source, restore the player's exact pre-battle global
   transform, zero velocity, and visual facing from `scene_changed` after the
   new scene is ready. An explicit different-scene override uses that scene's
   authored spawn instead.
5. Clear active launch data and enable movement only after the returned scene is
   ready.
6. Reveal the overworld and emit `battle_return_finished`; `BattleSystem` then
   returns to `IDLE`.

The completed encounter ID is retained for immediate-return suppression in that
returned scene instance. `TrainerBehavior` checks
`GameInstance.is_encounter_suppressed()` before detection. A standard trainer
returns in `WAITING`; its session-level consumed ID blocks another forced sight
encounter but leaves HUD interaction available for manual rematches. A Highly
Aggro trainer returns in `COMPLETE` so it cannot immediately loop beneath the
player, then regains forced sight after leaving and starting the destination
again. Standard sight consumption is transient and is not autosaved.

## Ownership boundaries

- `GameInstance`: scene changes, transition template, movement lock, one-scene
  suppression, and session-level standard-trainer sight consumption.
- `BattleSystem`: encounter/party DTOs, REST session, tokens, revisions,
  validation, retries, snapshots, event ordering, HP writeback, outcome.
- `BattleScene`: thin signal-to-visual and UI-intent adapter.
- `UITemplate` and `BattleChoiceOverlay`: input/presentation surfaces only.

Every dictionary emitted from the battle coordinator or returned by a public
getter is a deep copy. The state token never enters launch data, presentation
state, logs, save data, or scene scripts.

## Regression checks

```bash
godot --headless --path . --scene res://tests/scenes/battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/trainer_dialog_battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/battle_system_session_test.tscn
godot --headless --path . --scene res://tests/scenes/battle_scene_lifecycle_test.tscn
godot --headless --path . --scene res://tests/integration/battle_return_position_smoke_test.tscn
```

These cover the offline preview path, concrete provider discovery, covered
connection, deep-copy boundaries, request-driven locking, event acknowledgement,
confirmed forfeit, ordered return, movement restoration, one-time Kyle sight,
and manual-rematch availability.
