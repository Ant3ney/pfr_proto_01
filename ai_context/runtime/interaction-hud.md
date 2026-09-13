# Look Interaction and HUD Contract

Use this document when adding an NPC action, changing player target selection,
or changing the touch/keyboard interaction prompt.

## Target selection and HUD

The shared [`player.tscn`](../../game/actors/player/player.tscn) owns
[`PlayerInteractionDetector`](../../game/interaction/player_interaction_detector.gd).
The player scene and every reusable NPC role scene inherit the common
[`PFRCharacter.tscn`](../../game/actors/character/pfr_character.tscn) scene, which owns their
shared body, capsule, and `Visual` pivot. Every `PFRCharacter` joins the
`pfr_characters` group at runtime. While player
movement is free, the detector chooses one behavior-approved non-player
character within 3.25 m, a 38-degree forward half-angle, and a clear layer-1
line of sight at 1.35 m. The elevated sight line reaches an attendant over the
Pokemon Center counter while ordinary walls still block selection.

`PFRCharacterArtAssetPack` is the single appearance assignment. In the editor,
the shared tool script adds an unowned `Visual/CharacterArt` preview matching
that pack, including art-pack overrides authored on a level instance. Runtime
instantiates the same packed model and prepares its locomotion animations.
Specialized player, trainer, healer, and Stretchman scenes do not separately
serialize a second GLB reference.

[`GameUI`](../../game/ui/hud/game_ui.gd) binds to that detector and reveals its shared
bottom-right `InteractionButton` only while a target is available. Touch/click,
E, Enter, Space, and gamepad A all call the same `try_interact()` path. The
button disappears as soon as the target accepts and locks a sequence.

The same `GameUI` also instances the always-visible player-menu HUD on its
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
approach. Kyle and all six standard prototype trainers use `STANDARD` aggression: their
first battle consumes forced sight for the current play session, and later
rematches start only from the HUD. Routes 1–40 use automatic `HIGHLY_AGGRO`
opponents; they are quiet in the immediate battle-return scene, then force
their sight challenge again when the area is launched anew. All gym leaders
and the full five-opponent Champion challenge set `automatic_sight_encounter`
to `false`: they stay put until Talk, and immediate-return suppression leaves
them in `WAITING` so Talk can launch the same dialog and a rematch. The HUD is
also an alternate way to talk to an automatic trainer while it is `WAITING`,
such as when the player approaches from the side or behind.

Every stateful NPC scene explicitly marks its controller resource
`resource_local_to_scene`, and `NPCBehavior._init()` makes runtime-created
behaviors scene-local. `PFRCharacter._ready()` calls
`NPCController.prepare_for_character()` so `TrainerKyle` can recreate an
exported null behavior and re-synchronize its dialog, battle path, encounter ID,
and aggression mode after Godot duplicates the controller. Do not remove these
ownership and repair steps: shared resources leak `COMPLETE` between trainers,
an unsynchronized duplicate launches the generic no-encounter battle preview,
and a release-exported null behavior makes authored trainers inert.

`PokemonCenterHealerBehavior` exposes the same dispatcher through
`start_healing_sequence()`. The behavior still supports legacy automatic
proximity prompting with `automatic_proximity_prompt`; the authored Center
attendant sets it to `false` and uses the shared HUD.

The older [`Interaction`](../../game/interaction/interaction.gd) data resource is not yet a
general interaction runner. Current dispatch is deliberately behavior-owned.

[`TownNpcBehavior`](../../game/actors/npcs/residents/behaviors/town_npc_behavior.gd) is the
non-battling resident implementation. It owns repeatable multi-line dialog and
an optional one-time catalog-item gift; it never enters trainer state or starts
a battle. [`RoamingTownNpcBehavior`](../../game/actors/npcs/residents/behaviors/roaming_town_npc_behavior.gd)
adds short, deterministic local strolls and pauses whenever a conversation or
another gameplay sequence owns movement. The primary development environment's
`TownResidents` group contains seven lore-focused residents, including three
women models and three roamers. Researcher Lumen stands on the interior plaza
cobblestone and grants the persistent one-time Exp. Share gift.

## Regression checks

```bash
godot --headless --path . --scene res://tests/scenes/pfr_character_scene_inheritance_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/player_input_movement_smoke_test.tscn
godot --headless --editor --path . --script res://tests/scenes/pfr_character_editor_preview_smoke_test.gd
godot --headless --path . --scene res://tests/scenes/interaction_hud_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/standalone_area_scenes_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/pokemon_center_healer_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/trainer_dialog_battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/trainer_manual_boss_rematch_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/town_npc_smoke_test.tscn
```
