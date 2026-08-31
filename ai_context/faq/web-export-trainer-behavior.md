# Trainers Are Inert or Missing in Web Exports

Use this document when trainer interactions work from source but fail in a
release or web package.

## Recognize the Failure Signature

- City trainers remain visible but neither notice the player nor accept the
  shared interaction action.
- Stretchman and the Pokemon Center attendant still work because they use
  different behavior resources.
- Generated routes, gyms, and the Pokemon League contain no opponents.
- Source-scene interaction and destination smoke tests pass.
- Inspecting an exported city instance shows a valid `TrainerKyle` controller
  whose inherited `npc_behavior` property is null.

## Verified Cause

`TrainerKyle._init()` creates a `TrainerBehavior`, but release PackedScene
deserialization can subsequently restore the inherited exported
`NPCController.npc_behavior` property to null. A null behavior rejects both
automatic sight and manual interaction.

Generated destinations expose a second edge: they configure a trainer directly
after `PackedScene.instantiate()` and before `add_child()` can run
`PFRCharacter._ready()`. Their validation rejects and frees a trainer whose
behavior is null, which makes every generated opponent appear to be absent.

## Current Required Behavior

[`TrainerKyle`](../../overworld/trainer_lake/TrainerKyle.gd) owns
`_ensure_trainer_behavior()`. Both `_init()` and `prepare_for_character()` call
it before synchronizing dialog, battle scene, encounter ID, automatic sight,
and aggression settings. This makes scene-ready city trainers recover from the
exported null property without weakening the base behavior boundary.

[`StretchDestination`](../../rnd/stretch/worlds/StretchDestination.gd) must call
`prepare_for_character()` before reading a newly instantiated trainer's
behavior. Do not rely only on `PFRCharacter._ready()` at this boundary because
the destination configures and may discard the trainer before adding it to the
tree.

## Regression Checks

```sh
godot --headless --path . --scene res://rnd/tests/interaction_hud_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
netlify build
```

The destination test simulates the exported null property before pre-spawn
configuration. The Netlify build exports the actual PCK and then runs
[`verify_web_export.gd`](../../tools/verify_web_export.gd) against that package.
The packaged check requires all seven city trainers to accept interaction,
requires sight detection to enter an approach state, and verifies destination
pre-spawn repair.
