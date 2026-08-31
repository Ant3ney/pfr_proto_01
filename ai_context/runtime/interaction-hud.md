# RND Look Interaction and HUD Contract

Use this document when adding an NPC action, changing player target selection,
or changing the touch/keyboard interaction prompt during the RND phase.

## Target selection and HUD

The shared [`player.tscn`](../../demo/player.tscn) owns
[`RNDPlayerInteractionDetector`](../../rnd/interaction/PlayerInteractionDetector.gd).
Every `PFRCharacter` joins the `pfr_characters` group at runtime. While player
movement is free, the detector chooses one behavior-approved non-player
character within 3.25 m, a 38-degree forward half-angle, and a clear layer-1
line of sight at 1.35 m. The elevated sight line reaches an attendant over the
Pokemon Center counter while ordinary walls still block selection.

[`GameUI`](../../demo/GameUI.gd) binds to that detector and reveals its shared
bottom-right `InteractionButton` only while a target is available. Touch/click,
E, Enter, Space, and gamepad A all call the same `try_interact()` path. The
button disappears as soon as the target accepts and locks a sequence.

The same `GameUI` also instances the always-visible R&D player-menu HUD on its
own higher canvas layer. That independent Menu/M/Y path is documented in
[`player-menu.md`](player-menu.md); it does not change interaction target
selection or dispatch behavior.

## Behavior dispatch boundary

`PFRCharacter` delegates `can_interact`, `get_interaction_prompt`, and
`interact` to `NPCController`, which delegates to its `NPCBehavior`. The base
behavior rejects interaction. An implementing behavior remains the owner of
its dialog, battle launch, movement lock, and cleanup; the detector and HUD do
not interpret gameplay data.

`TrainerBehavior` accepts interaction only from `WAITING`. A trainer with dialog
opens that dialog and starts its configured battle after the final line. A
trainer without dialog can launch its configured battle directly. Its exported
`automatic_sight_encounter` flag independently controls the classic forward-ray
approach. Kyle and all six city-line trainers use `STANDARD` aggression: their
first battle consumes forced sight for the current play session, and later
rematches start only from the HUD. Generated Stretchman opponents use
`HIGHLY_AGGRO`; they are quiet in the immediate battle-return scene, then force
their sight challenge again after the player leaves and starts that destination
anew. The HUD remains an alternate way to talk while a trainer is `WAITING`,
such as when the player approaches from the side or behind.

Every stateful NPC scene explicitly marks its controller and behavior resources
`resource_local_to_scene`. `PFRCharacter._ready()` calls
`NPCController.prepare_for_character()` so `TrainerKyle` can re-synchronize its
exported dialog, battle path, encounter ID, and aggression mode after Godot
duplicates the controller. Do not remove either ownership step: shared resources
leak `COMPLETE` between trainers, while an unsynchronized duplicate launches the
generic no-encounter battle preview.

`PokemonCenterHealerBehavior` exposes the same dispatcher through
`start_healing_sequence()`. The behavior still supports legacy automatic
proximity prompting with `automatic_proximity_prompt`; the authored Center
attendant sets it to `false` and uses the shared HUD.

The older [`Interaction`](../../core/Interaction.gd) data resource is not yet a
general interaction runner. Current RND dispatch is deliberately behavior-owned.

## Regression checks

```bash
godot --headless --path . --scene res://rnd/tests/interaction_hud_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
godot --headless --path . --scene res://tests/pokemon_center_healer_smoke_test.tscn
godot --headless --path . --scene res://tests/trainer_dialog_battle_start_smoke_test.tscn
```
