# pfr_proto_01

A Godot prototype for reusable 3D character locomotion, player controls, camera behavior, and NPC navigation.

## Query Local Creature Data

`CreatureSystem` is a global, offline API for the complete PokeAPI creature snapshot bundled with the project. Pass a numeric PokeAPI ID to get the original Pokemon record plus its full encounter, species, and evolution-chain records:

```gdscript
var pikachu := CreatureSystem.get_creature(25)
print(pikachu["name"])                              # pikachu
print(pikachu["stats"])                             # Base stats
print(pikachu["encounters_data"])                   # Location encounters
print(pikachu["species_data"]["capture_rate"])      # Species metadata
print(pikachu["evolution_chain_data"]["chain"])     # Full evolution tree
print(pikachu["xp_multiplier"])                      # Pinned reward multiplier
print(pikachu["experience_data"]["experience_by_level"][25]) # XP for Lv. 25
```

The API includes all 1,351 current PokeAPI Pokemon records: 1,025 default National-Dex entries plus 326 alternate and battle forms. `get_pokemon(id)` is an alias, `has_pokemon(id)` checks an ID without loading its record, and invalid lookups return an empty dictionary with details available from `get_last_error()`. Returned objects are deep copies and are safe for callers to modify.

The losslessly compressed local snapshot lives in [`data/creatures`](data/creatures/README.md). It retains every JSON field from PokeAPI's `pokemon`, per-Pokemon encounter, `pokemon-species`, and `evolution-chain` endpoints; sprite and cry URL fields are retained, while the binary media itself is not vendored. To verify or intentionally refresh the snapshot:

```sh
python3 tools/sync_pokeapi_data.py --verify
node tools/generate_creature_experience_data.mjs --check
python3 tools/sync_pokeapi_data.py
godot --headless --path . --scene res://tests/integration/creature_system_smoke_test.tscn
```

## Manage the Player's Collection

`CollectionSystem` is the global owner of captured Pokemon and the six-slot party. Each captured instance is a PCL (Pokemon collection instance) with its own ID, party assignment, normalized health, cumulative `currentXp`, and derived level:

A fresh profile first presents animated Charmander (Generation I), Froakie
(Generation VI), and Treecko (Generation III) cards. Confirming one creates that
Pokemon as the only initial party member in slot 1 at level 5 and full health.
Existing saves keep their collection. The player menu can completely reset a
profile only after three destructive warnings, two acknowledgements, and the
exact phrase `RESET FOREVER`; reset returns to this starter choice.

```gdscript
var level_five_xp := CreatureSystem.get_experience_for_level(25, 5)
var pcl := CollectionSystem.add_pokemon(25, 5, 1.0, level_five_xp, 1)
var battle_pcl := CollectionSystem.get_pcl_by_party_slot(1)
CollectionSystem.update_instance_stats(pcl["pclID"], {
	"health": 0.4,
	"currentXp": level_five_xp + 40,
})
var award := CollectionSystem.grant_experience(pcl["pclID"], 25)
```

Party slots are integers `1–6`; passing slot `0` stores the Pokemon outside the party. Health is normalized from `0.0` to `1.0`; XP is the exact cumulative integer for the species growth curve. `load_save_data()` migrates the former normalized `xp` field once. Use `get_experience_progress()` for the in-level fraction and `get_save_data()`/`load_save_data()` for persistence. Returned PCL objects are deep copies and can be safely modified by callers.

Captured instances may also persist one optional `heldItem`. Researcher Lumen
in the main city's paved plaza gives one Exp. Share per profile. The Pokemon
menu moves it between the bag and a selected PCL; a party holder that did not
enter battle receives half of its own normal knockout XP, while an active
holder receives the ordinary full award without doubling it.

When a battle-supported Pokemon crosses a level-up learnset threshold, the
move-learning system derives the move from the committed PokeAPI snapshot. It
automatically fills an open move slot; at four moves it pauses play so the
player can replace one exact slot or keep the current set. Unresolved choices
survive schema-6 autosaves. See the
[level-up move-learning contract](ai_context/runtime/move-learning.md).

Run the collection verification with:

```sh
godot --headless --path . --scene res://tests/integration/collection_system_smoke_test.tscn
```

## Optional Cloud Saves

The player menu now has an optional masked `Cloud Save` panel. A private Save
ID links the local profile to the same ID on other devices; `Opt Out` forgets
that linkage without affecting ordinary local saves. Background sync retains
per-section timestamps while offline, pulls an existing cloud save on first
link, and resolves later conflicts with causal revisions, timestamps, monotonic
XP/achievements, and reset protection.

The Web client talks only to the same-origin Netlify function. MongoDB Atlas
credentials are never compiled into Godot or published in browser assets. A
deployment must configure a rotated `MONGODB_URI`, optional
`MONGODB_DATABASE`, and independent `CLOUD_SAVE_PEPPER` as production Netlify
environment variables, with the URI and pepper marked secret. See the
[cloud-save runtime contract](ai_context/runtime/cloud-save.md)
and [function deployment notes](netlify/functions/README.md).

```sh
npm run test:cloud-save
godot --headless --path . --scene res://tests/integration/cloud_save_sync_smoke_test.tscn
```

## Author and Run PvE Battles

`BattleSystem` is the global coordinator for networked PvE battles. It reads
the six-slot party from `CollectionSystem`, discovers the encounter resource in
the active concrete battle scene, and calls the production API at
`https://pfr-locomotion-prototype.vercel.app/api/v1`. Scene scripts handle only
input and presentation; they do not construct REST commands, retain state
tokens, calculate results, or write collection health.

The included Kyle battle is the reference authoring setup:

- [`kyle_battle_scene.tscn`](game/battle/scenes/kyle_battle_scene.tscn) inherits the
  shared battlefield and contains exactly one encounter provider.
- [`trainer_kyle_lake_v1.tres`](game/battle/encounters/trainer_kyle_lake_v1.tres)
  defines stable encounter and member IDs, canonical species, exact sprites,
  levels, normalized health, and equipped moves.
- [`TrainerController`](game/actors/npcs/trainers/trainer_controller.gd) passes only the
  concrete scene path and stable encounter ID to `GameInstance.startBattle()`.

To author another encounter, duplicate the concrete scene and encounter
resource, keep one provider in group `battle_encounter_provider`, and validate
one to six members with unique IDs. Player instances persist a `battleProfile`
containing canonical Showdown species, exact sprite ID, and one to four equipped
moves. `pclID` remains the REST `memberId`; unsupported PokeAPI forms stay
collectible but fail battle preflight until explicitly mapped.

Run the focused battle gates with:

```sh
node tools/generate_battle_species_mapping.mjs --check
node tools/generate_creature_experience_data.mjs --check
node tools/creatures/generate_move_learnsets.mjs --check
godot --headless --path . --scene res://tests/integration/battle_data_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/battle_system_session_test.tscn
godot --headless --path . --scene res://tests/scenes/battle_scene_lifecycle_test.tscn
godot --headless --path . --scene res://tests/integration/move_learning_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/starter_selection_smoke_test.tscn
```

See the [Godot battle client contract](ai_context/runtime/battle-client.md),
[battle start/return lifecycle](ai_context/runtime/battle-start.md),
[server operations guide](battle_server/README.md), and
[sprite regeneration guide](ai_context/runtime/battle-sprites.md) for the
request-driven UI, exact retry behavior, encounter schema, production setup,
and offline animated-atlas pipeline.

## Show UI with the UI Template System

Call `UIManager.show_ui(text)` to display the shared template, then configure and retain the returned `UITemplate`:

```gdscript
var template := UIManager.show_ui("The door is locked.")
if template:
	template.set_speaker_name("System")
	template.set_action_text("Okay")
	template.set_action_callback(template.close)
```

The caller owns the template's state and lifecycle. Actions do not close automatically, the dismiss button is hidden by default, and `UIManager` does not prevent overlapping templates. Use `close()` rather than `queue_free()` when dismissal must run cleanup.

See the complete [UI Template System guide](game/battle/ui/README.md) for single messages, confirm/cancel UI, multi-line `Dialog` resources, movement locks, callbacks and signals, styling, lifecycle rules, and troubleshooting.

## Adventure Menu and Standalone Areas

Stretchman is an ordinary resident NPC in Miare Station. His scene inherits the
resident and `PFRCharacter` bases and assigns the reusable `MenuNpcBehavior` to
open [`adventure_menu.tscn`](game/ui/adventure_menu/adventure_menu.tscn). The
behavior only faces the player, owns the menu movement lock, and restores it
when the menu closes; it does not own shops, rewards, battles, or progression.

The Adventure Menu calls the production domain autoloads directly:
`EconomySystem`, `InventorySystem`, `ShopSystem`,
`ChallengeProgressionSystem`, and `BattleRewardSystem`. Its walkable catalog
contains exactly 49 Inspector-authored destinations under
[`standalone_areas/`](game/world/levels/standalone_areas/): Route 00–39, Gym
01–08, and one Champion challenge. Each area folder contains its own scene,
`area_definition.tres`, and only the local encounter resources it needs. All
49 are native inherited scenes with static trainers, grass, gates, geometry,
lights, objectives, and markers visible in Godot's Scene tree; routine
authoring never invokes a world generator.

See the [standalone-area contract](ai_context/runtime/adventure-menu-and-standalone-areas.md)
for domain ownership, resource fields, unlocks, rewards, save migration, and
export verification.

## Place the Player in a Traversable Scene

[`pfr_character.tscn`](game/actors/character/pfr_character.tscn) is the shared scene foundation
for every player and NPC. It owns the `PFRCharacter` body, standard capsule, and
`Visual` pivot. Role scenes inherit that foundation: the complete reusable player
is [`player.tscn`](game/actors/player/player.tscn), which also owns `Camera3D`
and `GameUI`, while town residents, trainers, healers, and Stretchman add their
own controller, behavior, art, and interaction data.
Instance the role scene instead of rebuilding the character hierarchy in a
level. Assign character appearance through one `PFRCharacterArtAssetPack`;
the shared character creates the matching `CharacterArt` model at runtime and
as a non-persistent editor preview.

Every playable level inherits the single
[`level_base.tscn`](game/world/level_bases/level_base.tscn) directly and keeps
this common structure:

```text
PFRWorldLevel
├── Player
│   ├── Camera3D
│   └── GameUI
├── Environment
├── NavigationRegion3D
│   └── WorldGeometry
│       ├── Ground
│       │   └── ModularGroundGrid
│       ├── Structures
│       ├── Props
│       └── Boundaries
├── Gameplay
│   ├── Actors
│   ├── Encounters
│   ├── Interactions
│   ├── Transitions
│   └── Objectives
├── Markers
└── Backdrop
```

### Set Up the Level

1. In the FileSystem dock, right-click
   [`level_base.tscn`](game/world/level_bases/level_base.tscn) and create a
   native inherited scene.
2. Set the root's level identity and entry marker in the Inspector. Keep the
   inherited player at unit scale and place its foot-level root on the walkable
   surface. The included capsule is 1.6 meters tall and centered at `Y = 0.8`.
3. Put walkable and blocking physics beneath
   `NavigationRegion3D/WorldGeometry`. A visible `MeshInstance3D` alone does not
   stop the player: use `StaticBody3D` collision or a collision-enabled GridMap.
4. Keep actors, encounter volumes, interaction objects, transitions, and
   objectives under their corresponding `Gameplay` branches, and put stable
   arrival points under `Markers`.
5. Adjust composition on `Player/Camera3D` when needed, keeping its target on
   the parent Player, and author lighting or `WorldEnvironment` beneath
   `Environment`/`Backdrop` as appropriate.
6. Retain `Player/GameUI` for the floating joystick, interaction prompt, and
   permanent player menu. Keyboard and gamepad locomotion do not depend on the
   joystick control.

Use `PFRWorldLevel.get_player()` and `find_spawn_marker()` in production scripts;
the canonical Player path is the direct root child `Player`.

The project registers [`game_instance.gd`](game/runtime/game_instance.gd) as the `GameInstance` autoload. Keep that autoload enabled because `PlayerController` checks it before accepting movement. A `NavigationRegion3D` is not required for player movement; navigation meshes are used by NPC controllers.

The controller currently moves only on the XZ plane and does not apply gravity. Spawn the player directly on the floor rather than above it, and use a common walkable elevation for dependable traversal. Test slopes, steps, ledges, and drops individually before relying on them.

### Controls and Verification

- **Keyboard:** `WASD` or the arrow keys.
- **Gamepad:** left stick on the first connected controller.
- **Touch or mouse:** press or click away from other controls and drag when `Player/GameUI` is present.

Run the current scene with Godot's **Run Current Scene** command. Use **Debug → Visible Collision Shapes** when checking level collision.

| Problem | Check |
| --- | --- |
| The player is not visible | Confirm the camera is current and its target path resolves to the player |
| Input does not move the player | Focus the game window and confirm `GameInstance.is_player_movement_enabled()` is true |
| The player passes through scenery | Add active physics shapes and confirm their collision layer overlaps the player's mask |
| The player floats or starts at the wrong height | Align the player root with the surface; the current controller does not fall onto the floor |
| The character does not animate | Check Godot's output for missing art-pack, `AnimationPlayer`, idle-animation, or run-animation errors |

The New Bouffalant City ground wrappers and imported reference assets already include profile-appropriate layer-1 collision: exact static meshes for hard surfaces, simple volumes for dense vegetation and trunks, and intentional pass-through behavior for soft decoration and water-only pieces. Navigation meshes are still authored per level. See the [environment asset guide](art/environments/new_bouffalant_city/README.md) for placement and collision details.

## Add a Trainer to a Scene

All trainer prefabs inherit
[`pfr_character.tscn`](game/actors/character/pfr_character.tscn).
[`trainer_kyle.tscn`](game/actors/npcs/trainers/presets/trainer_kyle.tscn)
is the reference trainer role scene, and
[`route_00.tscn`](game/world/levels/standalone_areas/routes/route_00/route_00.tscn)
demonstrates all seven standard prototype placements in Lv. 3–6 order. A
trainer uses the same character body, collision, movement, art-pack, and
animation system as the player, but its controller waits for a line-of-sight
detection and then navigates toward the player.

A trainer-ready level adds these nodes to the playable-level structure above:

```text
PFRWorldLevel
├── Player
│   ├── Camera3D
│   └── GameUI
├── NavigationRegion3D
│   └── WorldGeometry
│       ├── Ground
│       │   └── ModularGroundGrid
│       ├── Structures
│       ├── Props
│       └── Boundaries
└── Gameplay
    └── Actors
        └── TrainerKyle (inherited trainer preset instance)
```

### Place and Configure a Trainer

1. In the FileSystem dock, drag the required reusable trainer scene from
   [`game/actors/npcs/trainers/presets/`](game/actors/npcs/trainers/presets/) into the level's Scene
   tree. Do not copy its node hierarchy into the level. Keep its scale at
   `1, 1, 1`, and place its root directly on the walkable surface, inside the
   navigation mesh.
2. Rotate the trainer root around the Y axis to face its detection lane. [`trainer_behavior.gd`](game/actors/npcs/trainers/trainer_behavior.gd) casts forward along the `Visual` node's local `-Z` axis, from `Y = 0.8`. The current Kyle configuration detects up to 80 meters away.
3. Keep the player's collision body on physics layer 1, or update the trainer's detection mask to match. The detection ray stops at the first body it hits, so walls and other layer-1 collision correctly block the trainer's view.
4. Add and bake the `NavigationRegion3D` using the recipe below. The baked surface must include both the trainer's starting position and the stopping point beside the player. Re-bake it whenever relevant level geometry changes.
5. Assign a non-empty [`Dialog`](game/dialogue/dialog.gd) resource to the trainer's **Dialog** property. The bundled Kyle scene already uses [`trainer_kyle.tres`](game/dialogue/resources/trainers/trainer_kyle.tres); create another resource with a speaker name and ordered lines for a different trainer.
6. Run the scene and walk into the trainer's forward sightline. The trainer should lock player movement, create its `NavigationAgent3D` at runtime, navigate around baked obstacles, stop beside the player, and open its dialog. Advancing the last line closes the template and restores player movement. Do not add a `NavigationAgent3D` manually.

Trainer navigation and physical collision are separate. The `NavigationMesh` supplies a path, while `StaticBody3D`, `GridMap`, and other collision shapes keep the characters out of walls and scenery. A trainer needs both systems to behave correctly.

### Bake the Navigation Mesh

1. Add a `NavigationRegion3D` at the level origin and leave its position, rotation, and scale at their defaults. In its **Navigation Mesh** property, choose **New NavigationMesh**.
2. Put the ground and every obstacle that should affect routing below the region, normally inside a `NavigationSource` `Node3D` as shown above. The default source mode scans descendants of the region; unrelated sibling geometry is not included. If the level hierarchy must remain flat, instead put the source nodes in one group and configure the `NavigationMesh` resource's **Source Geometry Mode** and **Source Geometry Group Name** to use that group.
3. Click the `NavigationMesh` resource in the Inspector and make **Parsed Geometry Type** match the source: **Mesh Instances** for visible `MeshInstance3D` or `GridMap` geometry, or **Static Colliders** for the corresponding physics shapes. When using static colliders, keep **Collision Mask** on layer 1 for this project's environment collision.
4. Re-select the `NavigationRegion3D` node in the Scene dock. The bake controls appear in the toolbar above the 3D viewport, not in the Inspector's three-dot menu. Click **Bake NavMesh**.
5. Run the scene and enable **Debug → Visible Navigation**. Confirm the colored navigation surface connects the trainer to the player and leaves clearance around obstacles.

You do not need to draw a rectangular navigation boundary. With the `NavigationMesh` resource's `filter_baking_aabb` left empty, Godot derives the covered area from the source geometry it finds. Set `filter_baking_aabb` and its offset only when intentionally cropping a large bake or building navigation chunks.

Keep character roots on the visible walkable surface; never move a character upward to match the navigation debug overlay. Baked path points can be vertically offset from the rendered floor because of navigation rasterization and source transforms. [`NPCController`](game/actors/npcs/shared/npc_controller.gd) measures that difference for every new path and automatically applies the appropriate `NavigationAgent3D.path_height_offset`. This works without scene-specific tuning whether the baked path is at `Y = 0`, `Y = 0.5`, or another height near the character.

For predictable baking, keep the `NavigationRegion3D` at scale `1, 1, 1`. Prefer unit-scale source geometry as well; set modular dimensions through meshes and `GridMap.cell_size` instead of scaling the navigation source merely to enlarge the bake. The navigation mesh gets its coverage from parsed source geometry, not from the `NavigationRegion3D` transform.

To verify the automatic height handling from the repository root, run:

```sh
godot --headless --path . --scene res://tests/scenes/navigation_path_height_smoke_test.tscn
```

### Current Encounter Limits

The existing Kyle behavior implements a complete one-time approach, linear
dialog, and networked battle. After the result or an unrecoverable failure, it
returns to the authored pose in `game/world/levels/standalone_areas/routes/route_00/route_00.tscn`.
Standard authored trainers consume their forced sight encounter for the current
play session, then remain available through the shared interaction prompt for
manual rematches. Authored standalone-area trainers use **Highly Aggro** mode:
the just-returned scene suppresses an immediate loop, but leaving and starting
that destination again restores their forced sight challenge. Standard sight
consumption is not yet persisted to disk. Avoid overlapping trainer sightlines
because there is no encounter arbiter for simultaneous detections or UI templates.

To author a genuinely new reusable character role, create an inherited scene
from [`pfr_character.tscn`](game/actors/character/pfr_character.tscn); do not duplicate an
existing character scene. Preserve the inherited `CollisionShape3D` and
`Visual` nodes, override the capsule shape only when the role needs a different
radius, and assign a `PFRCharacterArtAssetPack` on the root. Do not separately
add the pack's GLB beneath `Visual`; the inherited character owns both its
editor preview and runtime instantiation. A trainer assigns a scene-local
[`TrainerController`](game/actors/npcs/trainers/trainer_controller.gd), its `Dialog`,
concrete battle-scene path, and matching encounter ID. Save that role scene
under `game/actors/npcs/trainers/presets/`, then drag instances of it from the FileSystem dock into
levels.

Run the shared-scene regression whenever character scene composition changes:

```sh
godot --headless --path . --scene res://tests/scenes/level_base_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/pfr_character_scene_inheritance_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/player_input_movement_smoke_test.tscn
godot --headless --editor --path . --script res://tests/scenes/pfr_character_editor_preview_smoke_test.gd
```

| Problem | Check |
| --- | --- |
| The trainer never notices the player | Confirm its `Visual` `-Z` direction faces the player, the player is on the detection mask, and no collider blocks the ray |
| The trainer reacts but does not move | Confirm a baked navigation map exists, both endpoints are on its reachable surface, and run the navigation height smoke test above |
| The trainer walks through or catches on scenery | Check physical collision separately from the navigation mesh and leave enough clearance for the 0.32-meter capsule radius |
| The trainer stops too early or too late | Adjust `stopping_buffer` and `arrival_distance` in that trainer's controller configuration |
| The player remains frozen afterward | Confirm the trainer has a non-empty `Dialog` and that the final action reaches `UITemplate.close()`; cleanup and movement restoration run through its dismiss callback |

## AI Context

[`ai_context/`](ai_context/) holds durable, project-specific knowledge that would otherwise be costly for future contributors and AI agents to rediscover. Start at [`ai_context/index.md`](ai_context/index.md), use its task-oriented routing table, and read only the narrowest document relevant to the work. When a route leads to a subject directory, read that directory's `index.md` before selecting a leaf document.

When a verified lesson remains useful beyond the current task, update the closest existing context document and its immediate index. Create a focused leaf only when existing documents do not cover the subject. Keep the root index broad; introduce a new subject directory only when multiple related documents or a distinct routing layer justify it, and give that directory its own `Task | Read next | Purpose` routing index.

Current code, configuration, tests, and verified runtime behavior take precedence over the documentation. Never put credentials, keys, passwords, cookies, tokens, nonces, private keys, or other secrets in `ai_context/`. See [`AGENTS.md`](AGENTS.md) for the complete agent-facing rules.

## Environment Assets

The New Bouffalant City runtime environment pack, searchable editor placement palette, metric asset browser, catalog, and validation instructions are documented in [`art/environments/new_bouffalant_city/README.md`](art/environments/new_bouffalant_city/README.md). Its transferred GLBs bake a player-calibrated `0.75` import factor while placed scene roots remain at `Scale = (1, 1, 1)`.
