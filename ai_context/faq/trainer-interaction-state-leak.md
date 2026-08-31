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
- Two instances of the same trainer scene expose the same controller or nested
  behavior resource instance.

After making those resources scene-local, a related configuration failure can
show an empty generic battle shell with `Opponent`, `Lv. ?`, and no sprites. In
that case interaction state is isolated, but the duplicated controller has not
re-synchronized its encounter ID and authored battle scene path into its nested
`TrainerBehavior`.

## Verified Cause

`NPCController` and `TrainerBehavior` are mutable resources. Trainer approaches,
dialogs, and battle returns change the behavior's state. If a scene subresource
is shared, completing one trainer changes every later instance backed by that
same resource, including instances created after a scene transfer. Restarting
the process clears that in-memory resource cache, which explains the temporary
recovery.

Godot duplicates resources marked `resource_local_to_scene`, but controller
duplication also exposes two initialization hazards:

1. Re-applying a serialized navigation coordinate must not implicitly activate
   movement; only `NPCController.move_to()` may set the move-target flags.
2. Duplicating a custom controller does not reliably invoke every exported
   setter that originally copied controller configuration into its nested
   behavior. Without an explicit post-duplication sync, trainer battle data can
   fall back to the generic no-encounter preview.

## Current Required Behavior

Every authored scene with mutable NPC state explicitly serializes its controller
and behavior resources as `resource_local_to_scene`. Do not rely only on setting
that property from a resource constructor; the scene file must own the local
subresource configuration.

[`PFRCharacter.gd`](../../core/PFRCharacter.gd) calls
`NPCController.prepare_for_character()` from `_ready()`. Custom trainer
controllers use that hook to copy their exported dialog, encounter ID, battle
scene path, sight flag, and aggression mode into the local `TrainerBehavior`.
Keep `NPCController.map_coordinates` as passive storage and activate travel only
through `move_to()`.

Standard trainers consume automatic sight once per play session and then remain
in `WAITING` for manual rematches. Stretchman destination trainers use
`HIGHLY_AGGRO`: the immediate return scene is suppressed to prevent a loop, but
a newly entered destination gets a fresh local behavior and forces sight again.

## Regression Checks

From the repository root, run:

```sh
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_data_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_scene_lifecycle_test.tscn
godot --headless --path . --scene res://tests/navigation_path_height_smoke_test.tscn
```

The destination test poisons an instance of every authored trainer template,
requires the next instance to own fresh controller and behavior resources,
exercises Highly Aggro sight again after route scene re-entry, and dispatches
Gym 8 through the E-key HUD path. The battle-data test verifies that an
instantiated Kyle retains its concrete encounter ID and battle scene path; the
lifecycle test covers forced sight, battle return, suppression, and manual
rematch behavior.

If these checks pass but an individual trainer still fails, inspect its facing,
line-of-sight collision, authored resources, and scene-specific geometry before
changing the shared lifecycle contract.
