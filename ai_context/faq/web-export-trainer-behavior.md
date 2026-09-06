# Trainers Are Inert in Web Exports

Use this document when trainer interactions work from source but fail in a
release or Web package.

## Recognize the failure signature

- A trainer remains visible but neither notices the player nor accepts the
  shared interaction action.
- Stretchman and the Pokémon Center attendant still work because they use
  different behavior resources.
- Source-scene interaction and standalone-area smoke tests pass.
- Inspecting an exported trainer instance shows a valid `TrainerController`
  whose inherited `npc_behavior` property is null.

The current 40 routes, eight gyms, and Champion challenge are static inherited
scenes. If their nodes are absent from a package, diagnose selected-resource
export contents separately; no runtime destination generator exists.

## Verified cause and repair boundary

`TrainerController._init()` creates a `TrainerBehavior`, but release
`PackedScene` deserialization can subsequently restore the inherited exported
`NPCController.npc_behavior` property to null. A null behavior rejects both
automatic sight and manual interaction.

[`TrainerController`](../../game/actors/npcs/trainers/trainer_controller.gd)
owns `_ensure_trainer_behavior()`. Both `_init()` and
`prepare_for_character()` call it before synchronizing dialog, battle scene,
encounter ID, automatic sight, and aggression. Every trainer preset inherits
[`trainer_base.tscn`](../../game/actors/npcs/trainers/trainer_base.tscn), and
`PFRCharacter._ready()` calls the controller preparation hook after scene
deserialization. Preserve the scene-local controller resources and this repair
step; do not add area-specific trainer subclasses or reconstruct trainers from
runtime dictionaries.

## Regression checks

```bash
godot --headless --path . --scene res://tests/scenes/interaction_hud_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/standalone_area_scenes_smoke_test.tscn
godot --headless --path . --export-pack WebBuild /tmp/pfr-web-check.pck
node tools/battle_sprite_pipeline/verify_export_pack.cjs /tmp/pfr-web-check.pck
godot --headless --main-pack /tmp/pfr-web-check.pck --script "$PWD/tools/verify_web_export.gd"
```

The source checks cover behavior reconstruction and all 49 authored area
scenes. The pack checker requires the canonical `level_base.tscn`, exactly 49
standalone scene resources, and the absence of all four removed base/runtime
scenes. The packaged runtime verifier loads the canonical base and Route 0, then
requires all seven static trainers to retain Inspector-authored encounter data
and accept manual interaction.
