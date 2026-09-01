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

`PFRCharacter` directly exports one optional `npc_behavior: NPCBehavior` and
dispatches `can_interact`, `get_interaction_prompt`, `interact`, and per-physics
behavior processing to it. The character passes its `NPCController` into those
calls as movement/navigation infrastructure; the controller does not own new
gameplay behavior authoring. The base behavior rejects interaction. An
implementing behavior remains the owner of its dialog, battle launch, movement
lock, and cleanup; the detector and HUD do not interpret gameplay data.

The intended Inspector workflow is to add a `PFRCharacter`, assign its art and
collision, then create a `TownNpcBehavior`, `RoamingTownNpcBehavior`,
`TrainerBehavior`, `PokemonCenterHealerBehavior`, or another subclass directly
in the character's **NPC Behavior** property. Trainer dialog, battle scene,
encounter ID, detection, and aggression fields are exported by
`TrainerBehavior`; no trainer-specific controller is required.

`TrainerBehavior` accepts interaction only from `WAITING`. A trainer with dialog
opens that dialog and starts its configured battle after the final line. A
trainer without dialog can launch its configured battle directly. Its exported
`automatic_sight_encounter` flag independently controls the classic forward-ray
approach. Kyle and all six standard prototype trainers use `STANDARD` aggression: their
first battle consumes forced sight for the current play session, and later
rematches start only from the HUD. Generated Stretchman opponents use
`HIGHLY_AGGRO`; they are quiet in the immediate battle-return scene, then force
their sight challenge again after the player leaves and starts that destination
anew. The HUD remains an alternate way to talk while a trainer is `WAITING`,
such as when the player approaches from the side or behind.

Every authored stateful behavior subresource is explicitly
`resource_local_to_scene`, and `NPCBehavior._init()` applies the same rule to
runtime-created behaviors. `PFRCharacter.prepare_runtime_composition()` keeps a
hidden serialized controller mirror only for compatibility: it adopts behavior
from a pre-migration controller when needed, while direct character authoring is
authoritative for current scenes. Generated destinations configure the direct
`TrainerBehavior` before adding the character to the tree and recreate it if a
release export stripped the resource. Do not remove the scene-local ownership or
pre-spawn repair: shared behavior resources leak `COMPLETE` between trainers,
and a null exported behavior makes generated opponents disappear.

`PokemonCenterHealerBehavior` exposes the same dispatcher through
`start_healing_sequence()`. The behavior still supports legacy automatic
proximity prompting with `automatic_proximity_prompt`; the authored Center
attendant sets it to `false` and uses the shared HUD.

The older [`Interaction`](../../core/Interaction.gd) data resource is not yet a
general interaction runner. Current RND dispatch is deliberately behavior-owned.

[`TownNpcBehavior`](../../overworld/town_npcs/TownNpcBehavior.gd) is the
non-battling resident implementation. It owns repeatable multi-line dialog and
an optional one-time catalog-item gift; it never enters trainer state or starts
a battle. [`RoamingTownNpcBehavior`](../../overworld/town_npcs/RoamingTownNpcBehavior.gd)
adds short, deterministic local strolls and pauses whenever a conversation or
another gameplay sequence owns movement. The primary development environment's
`TownResidents` group contains seven lore-focused residents, including three
women models and three roamers. Researcher Lumen stands on the interior plaza
cobblestone and grants the persistent one-time Exp. Share gift.

## Regression checks

```bash
godot --headless --path . --scene res://tests/pfr_character_behavior_composition_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/interaction_hud_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
godot --headless --path . --scene res://tests/pokemon_center_healer_smoke_test.tscn
godot --headless --path . --scene res://tests/trainer_dialog_battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/town_npc_smoke_test.tscn
```
