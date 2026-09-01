# Trainer Interactions Fail After Earlier Battles

Use this document when trainers work in a fresh process, then stop noticing the
player and disappear from the interaction HUD after battles or scene changes.

## Recognize the Failure Signature

This failure has all or most of these signs:

- Trainers in more than one scene are affected, including newly generated
  Stretchman destinations.
- Forward sight and manual E interaction both fail because the trainer behavior
  is already in `COMPLETE` before the player approaches it.
- Quitting the entire game and launching it again temporarily restores the
  trainers.
- Two instances of the same trainer scene expose the same direct behavior
  resource instance.

After making those resources scene-local, a related configuration failure can
show an empty generic battle shell with `Opponent`, `Lv. ?`, and no sprites. In
that case inspect the direct `TrainerBehavior` encounter ID and authored battle
scene path; trainer launch configuration no longer belongs to a custom
controller.

## Verified Cause

`TrainerBehavior` is a mutable Resource. Trainer approaches, dialogs, and battle
returns change its state. If a scene subresource is shared, completing one
trainer changes every later instance backed by that same resource, including
instances created after a scene transfer. Restarting the process clears that
in-memory resource cache, which explains the temporary recovery.

Godot duplicates resources marked `resource_local_to_scene`. Two initialization
boundaries still matter:

1. Re-applying a serialized navigation coordinate must not implicitly activate
   movement; only `NPCController.move_to()` may set the move-target flags.
2. Generated destinations configure a trainer immediately after
   `PackedScene.instantiate()` and before `_ready()`. They must inspect and, if
   necessary, recreate the direct behavior before spawning it.

## Current Required Behavior

Every authored scene with mutable NPC state serializes its direct
`PFRCharacter.npc_behavior` subresource as `resource_local_to_scene`.
Runtime-created behaviors apply the same rule from `NPCBehavior._init()`.
Trainer dialog, encounter ID, battle scene path, sight flag, and aggression mode
are exported directly on `TrainerBehavior`.

[`PFRCharacter.gd`](../../core/PFRCharacter.gd) owns behavior dispatch.
`prepare_runtime_composition()` also adopts behavior from the hidden serialized
`NPCController.npc_behavior` compatibility mirror so pre-migration scenes still
load. Runtime destination spawners configure the direct behavior before the
trainer enters the tree and recreate a stripped null behavior; see
[`web-export-trainer-behavior.md`](web-export-trainer-behavior.md). Keep
`NPCController.map_coordinates` as passive storage and activate travel only
through `move_to()`.

Standard trainers consume automatic sight once per play session and then remain
in `WAITING` for manual rematches. Stretchman destination trainers use
`HIGHLY_AGGRO`: the immediate return scene is suppressed to prevent a loop, but
a newly entered destination gets a fresh local behavior and forces sight again.

## Regression Checks

From the repository root, run:

```sh
godot --headless --path . --scene res://tests/pfr_character_behavior_composition_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_data_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_scene_lifecycle_test.tscn
godot --headless --path . --scene res://tests/navigation_path_height_smoke_test.tscn
```

The composition test verifies the direct Inspector property and legacy bridge.
The destination test poisons an instance of every authored trainer template,
requires the next instance to own fresh controller and direct behavior resources,
exercises Highly Aggro sight again after route scene re-entry, and dispatches
Gym 8 through the E-key HUD path. The battle-data test verifies that an
instantiated Kyle retains its concrete encounter ID and battle scene path; the
lifecycle test covers forced sight, battle return, suppression, and manual
rematch behavior.

If these checks pass but an individual trainer still fails, inspect its facing,
line-of-sight collision, authored resources, and scene-specific geometry before
changing the shared lifecycle contract.
