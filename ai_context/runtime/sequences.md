# Sequence and Player-Control Lifecycle

Use this document when a gameplay sequence temporarily controls the player or
coordinates several runtime actions. The broader sequence description in
[`technical-design.md`](../technical-design.md) is design intent; there is no
general `Sequence` base class or sequence runner in the current implementation.

## Current movement-control authority

[`GameInstance`](../../game/runtime/game_instance.gd) is an autoload that owns one
global boolean. It defaults to `true` and exposes:

- `set_player_movement_enabled(is_enabled: bool)`
- `is_player_movement_enabled() -> bool`

[`PlayerController`](../../game/actors/player/player_controller.gd) checks the flag every time
it supplies a movement target. When movement is disabled, it returns the
player's current position. [`CharacterMovement`](../../game/actors/character/character_movement.gd)
zeros velocity before processing that target, so player locomotion stops on the
next physics update.

This flag affects movement supplied by `PlayerController`. It does not pause
the scene tree, disable UI, stop NPCs, suppress input events, or prevent another
system from moving the player directly.

## Control ownership rules

The runtime currently supports a single effective movement lock, not nested or
concurrent lock ownership.

- The caller that disables movement owns restoring it on every terminal path.
- Route normal completion, missing data, failed UI creation, and explicit
  cancellation through one cleanup function where possible.
- When UI dismissal ends the sequence, connect cleanup through the template's
  dismiss callback and close it with `UITemplate.close()`.
- `GameInstance` survives scene changes. A `false` value remains global until
  some caller explicitly restores it.

The boolean is not reference-counted and does not record who disabled movement.
If two sequences overlap, either one can set the flag to `true` while the other
still expects control. Avoid overlapping locks. Before concurrency is added,
replace this contract with an owner- or token-based lock API and update this
document in the same change.

## Current trainer sequence

[`TrainerBehavior`](../../game/actors/npcs/trainers/trainer_behavior.gd) is the implemented sequence
example:

| Stage | Trainer behavior | Player movement |
| --- | --- | --- |
| `WAITING` | Casts forward for the player | Unchanged |
| Player detected | Locks one collision-safe approach target and starts navigation | Disabled |
| `APPROACHING` | Continues toward the fixed target without following later player movement | Disabled |
| Target reached | Enters `COMPLETE`, stops NPC navigation, and starts assigned dialog | Disabled |
| Dialog advancing | Caller updates the returned UI template | Disabled |
| Final line dismissed | Clears dialog state, releases its lock, and calls `GameInstance.startBattle()` for a trainer encounter | Transferred to the battle-start flow; remains disabled after the synchronous handoff |

The shared interaction HUD can also dispatch a trainer while it is `WAITING`.
Interaction immediately marks the trainer `COMPLETE`, faces the player, and
either starts the same dialog path or launches the configured battle directly
when there is no dialog. `automatic_sight_encounter` controls the independent
classic approach path. Kyle and all six city-line trainers use standard
aggression: the first accepted battle consumes automatic sight for the current
play session, and the returned trainer enters `WAITING` for HUD-driven manual
rematches. Authored standalone-area opponents use Highly Aggro mode, stay
`COMPLETE` only in the immediate suppressed return scene, and regain automatic
sight when their area is launched as a fresh run. The HUD interaction
remains available while a trainer is `WAITING`, including when the player
approaches from outside that sight line.

An absent or empty dialog in the automatic path and a failed UI instantiation
use the finish path, restoring movement without starting a battle. `COMPLETE`
is terminal for that behavior instance; battle return creates a new scene-local
instance and applies the standard/manual or Highly Aggro/suppressed policy above.

## Current Pokemon Center healer sequence

[`PokemonCenterHealerBehavior`](../../game/actors/npcs/services/pokemon_center_healer/pokemon_center_healer_behavior.gd)
can poll its owning character's `InteractionArea` when
`automatic_proximity_prompt` is enabled. The authored Center attendant disables
that mode and is dispatched by the shared look-interaction HUD instead. The area
still detects only the layer-1 `PlayerCharacter` and occupies no collision layer.

| Stage | Healer behavior | Player movement |
| --- | --- | --- |
| Out of range | Waits and clears the re-entry latch | Unchanged |
| Player newly enters or presses interact | Rejects overlap if movement is already locked; otherwise opens the prompt | Disabled |
| Confirmation | **Heal** calls `CollectionSystem.heal_party()` once; **Not now** closes | Disabled |
| Result | Reuses the prompt template for healed, already-healthy, or empty-party feedback | Disabled |
| Dismissed/cancelled | Clears owned UI state and its lock | Restored |

The proximity latch applies only in automatic mode. In HUD mode, a finished or
declined prompt remains closed until the player explicitly presses interact
again. `start_healing_sequence()` is the behavior's public dispatcher entry.

## Known cleanup boundary

The current normal and error paths restore movement, but there is no general
sequence cancellation service or scene-transition cleanup policy. Directly
freeing a UI template bypasses its dismiss callback. Any feature that can abort
a sequence or replace the scene must add an explicit cleanup path before it can
safely use the movement lock.

## Checklist for new sequences

1. Identify the single object that owns the sequence state.
2. Disable movement only after the trigger has been accepted.
3. Retain references needed to update or close owned UI.
4. Send every completion and failure branch through one idempotent finish path.
5. Close owned UI and restore movement during cancellation or transition.
6. Test trigger, active control, normal completion, missing-data failure, and
   repeated completion calls.
