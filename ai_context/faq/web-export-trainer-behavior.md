# Trainers Are Inert or Missing in Web Exports

Use this document when trainer interactions work from source but fail in a
release or web package.

## Recognize the Failure Signature

- Route 0's standard trainers remain visible but neither notice the player nor accept the
  shared interaction action.
- Stretchman and the Pokemon Center attendant still work because they use
  different behavior resources.
- Generated routes, gyms, and the Pokemon League contain no opponents.
- Source-scene interaction and destination smoke tests pass.
- Inspecting an exported Route 0 `PFRCharacter` shows that its direct
  `npc_behavior` property is null.

## Verified Cause

Trainer roles are serialized directly in `PFRCharacter.npc_behavior`. If a
release PackedScene strips or nulls that Resource, the character has no role and
therefore rejects both automatic sight and manual interaction. The historical
custom-controller initialization path is retained only as a hidden legacy
serialization bridge and is not the current authoring contract.

Generated destinations expose a second edge: they configure a trainer directly
after `PackedScene.instantiate()` and before `add_child()` can run
`PFRCharacter._ready()`. Their validation rejects and frees a trainer whose
behavior is null, which makes every generated opponent appear to be absent.

## Current Required Behavior

Every authored trainer scene directly serializes a scene-local
[`TrainerBehavior`](../../core/TrainerBehavior.gd) on its `PFRCharacter`,
including dialog, battle scene, encounter ID, automatic sight, and aggression
settings. `PFRCharacter.prepare_runtime_composition()` synchronizes that direct
Resource into a hidden controller compatibility mirror and can adopt the old
nested format, but current scenes must not depend on a custom trainer controller.

[`StretchDestination`](../../rnd/stretch/worlds/StretchDestination.gd) calls
`prepare_runtime_composition()` before reading a newly instantiated trainer's
direct behavior and recreates a missing `TrainerBehavior` before configuring
it. Do not rely only on `PFRCharacter._ready()` at this boundary because the
destination configures and may discard the trainer before adding it to the tree.

## Regression Checks

```sh
godot --headless --path . --scene res://tests/pfr_character_behavior_composition_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/interaction_hud_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
netlify build
```

The destination test simulates the exported null property before pre-spawn
configuration. The Netlify build exports the actual PCK and then runs
[`verify_web_export.gd`](../../tools/verify_web_export.gd) against that package.
The packaged check requires all seven Route 0 trainers to accept interaction,
requires sight detection to enter an approach state, and verifies destination
pre-spawn repair.
