# PFR Locomotion Prototype

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
```

The API includes all 1,351 current PokeAPI Pokemon records: 1,025 default National-Dex entries plus 326 alternate and battle forms. `get_pokemon(id)` is an alias, `has_pokemon(id)` checks an ID without loading its record, and invalid lookups return an empty dictionary with details available from `get_last_error()`. Returned objects are deep copies and are safe for callers to modify.

The losslessly compressed local snapshot lives in [`data/creatures`](data/creatures/README.md). It retains every JSON field from PokeAPI's `pokemon`, per-Pokemon encounter, `pokemon-species`, and `evolution-chain` endpoints; sprite and cry URL fields are retained, while the binary media itself is not vendored. To verify or intentionally refresh the snapshot:

```sh
python3 tools/sync_pokeapi_data.py --verify
python3 tools/sync_pokeapi_data.py
godot --headless --path . --scene res://tests/creature_system_smoke_test.tscn
```

## Manage the Player's Collection

`CollectionSystem` is the global owner of captured Pokemon and the six-slot party. Each captured instance is a PCL (Pokemon collection instance) with its own ID, party assignment, health/XP percentages, and level:

A fresh game starts with Palkia, Mothim, Hoothoot, Vespiquen, Luxray, and Pelipper in party slots 1–6. All six start at level 3, full health, and zero XP progress.

```gdscript
var pcl := CollectionSystem.add_pokemon(25, 5, 1.0, 0.0, 1)
var battle_pcl := CollectionSystem.get_pcl_by_party_slot(1)
CollectionSystem.update_instance_stats(pcl["pclID"], {
	"health": 0.4,
	"xp": 0.3,
	"level": 6,
})
```

Party slots are integers `1–6`; passing slot `0` stores the Pokemon outside the party. Health and XP use normalized percentages from `0.0` to `1.0`. Use `get_save_data()` and `load_save_data()` to hand the complete collection to the future Save System. Returned PCL objects are deep copies and can be safely modified by callers.

Run the collection verification with:

```sh
godot --headless --path . --scene res://tests/collection_system_smoke_test.tscn
```

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

See the complete [UI Template System guide](core/ui/README.md) for single messages, confirm/cancel UI, multi-line `Dialog` resources, movement locks, callbacks and signals, styling, lifecycle rules, and troubleshooting.

## Place the Player in a Traversable Scene

[`demo/main.tscn`](demo/main.tscn) is the complete working example. The reusable player is [`demo/player.tscn`](demo/player.tscn); instance that scene instead of rebuilding its character body, collision capsule, controller, art, and animation setup in every level.

A playable level normally has this structure:

```text
Level (Node3D)
├── Environment visuals
├── Ground/Obstacles (StaticBody3D or collision-enabled GridMap)
│   └── CollisionShape3D or MeshLibrary collision shapes
├── Player (instance of demo/player.tscn)
├── Camera (Camera3D using core/PlayerCamera.gd)
├── WorldEnvironment and DirectionalLight3D
└── GameUI (optional; enables touch and mouse-drag movement)
```

### Set Up the Level

1. Create or open a scene with a `Node3D` root.
2. Instance [`demo/player.tscn`](demo/player.tscn) as a child. Keep its scale at `1, 1, 1` and place the `Player` root at the walkable surface height. The included capsule is 1.6 meters tall, centered at `Y = 0.8`, so the player root represents the character's foot position.
3. Give every walkable surface and blocking obstacle physics collision. A visible `MeshInstance3D` alone does not stop the player: use a `StaticBody3D` with one or more `CollisionShape3D` children, or a `GridMap` whose `MeshLibrary` items contain collision shapes. The default collision layer and mask, layer 1, match the player.
4. Add a `Camera3D` as a sibling of the player, attach [`core/PlayerCamera.gd`](core/PlayerCamera.gd), enable **Current**, and set **Target Path** to the player. For the tree above, the path is `../Player`. Movement is camera-relative when this camera is active.
5. Add lighting and a `WorldEnvironment` so the level is visible. These nodes affect presentation, not movement.
6. Optionally instance [`demo/game_ui.tscn`](demo/game_ui.tscn) to enable the floating touch/mouse joystick and fullscreen control. Keyboard and gamepad movement work without this UI.

The current project already registers [`core/GameInstance.gd`](core/GameInstance.gd) as the `GameInstance` autoload. Keep that autoload enabled because `PlayerController` checks it before accepting movement. A `NavigationRegion3D` is not required for player movement; navigation meshes are used by NPC controllers.

The controller currently moves only on the XZ plane and does not apply gravity. Spawn the player directly on the floor rather than above it, and use a common walkable elevation for dependable traversal. Test slopes, steps, ledges, and drops individually before relying on them.

### Controls and Verification

- **Keyboard:** `WASD` or the arrow keys.
- **Gamepad:** left stick on the first connected controller.
- **Touch or mouse:** press or click away from other controls and drag when `GameUI` is present.

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

[`overworld/trainer_lake/TrainerKyle.tscn`](overworld/trainer_lake/TrainerKyle.tscn) is the current trainer template, and [`demo/main.tscn`](demo/main.tscn) demonstrates a complete placement. A trainer uses the same character body, collision, movement, art-pack, and animation system as the player, but its controller waits for a line-of-sight detection and then navigates toward the player.

A trainer-ready level adds these nodes to the playable-level structure above:

```text
Level (Node3D)
├── NavigationRegion3D
│   └── NavigationSource (Node3D)
│       ├── Walkable ground with collision
│       └── Blocking obstacles with collision
├── Player
└── TrainerKyle (instance of overworld/trainer_lake/TrainerKyle.tscn)
```

### Place and Configure a Trainer

1. Instance [`overworld/trainer_lake/TrainerKyle.tscn`](overworld/trainer_lake/TrainerKyle.tscn) under the level root. Keep its scale at `1, 1, 1`, and place its root directly on the walkable surface, inside the navigation mesh.
2. Rotate the trainer root around the Y axis to face its detection lane. [`core/TrainerBehavior.gd`](core/TrainerBehavior.gd) casts forward along the `Visual` node's local `-Z` axis, from `Y = 0.8`. The current Kyle configuration detects up to 80 meters away.
3. Keep the player's collision body on physics layer 1, or update the trainer's detection mask to match. The detection ray stops at the first body it hits, so walls and other layer-1 collision correctly block the trainer's view.
4. Add and bake the `NavigationRegion3D` using the recipe below. The baked surface must include both the trainer's starting position and the stopping point beside the player. Re-bake it whenever relevant level geometry changes.
5. Assign a non-empty [`Dialog`](core/Dialog.gd) resource to the trainer's **Dialog** property. The bundled Kyle scene already uses [`trainer_kyle.tres`](overworld/dialogs/trainer_kyle.tres); create another resource with a speaker name and ordered lines for a different trainer.
6. Run the scene and walk into the trainer's forward sightline. The trainer should lock player movement, create its `NavigationAgent3D` at runtime, navigate around baked obstacles, stop beside the player, and open its dialog. Advancing the last line closes the template and restores player movement. Do not add a `NavigationAgent3D` manually.

Trainer navigation and physical collision are separate. The `NavigationMesh` supplies a path, while `StaticBody3D`, `GridMap`, and other collision shapes keep the characters out of walls and scenery. A trainer needs both systems to behave correctly.

### Bake the Navigation Mesh

1. Add a `NavigationRegion3D` at the level origin and leave its position, rotation, and scale at their defaults. In its **Navigation Mesh** property, choose **New NavigationMesh**.
2. Put the ground and every obstacle that should affect routing below the region, normally inside a `NavigationSource` `Node3D` as shown above. The default source mode scans descendants of the region; unrelated sibling geometry is not included. If the level hierarchy must remain flat, instead put the source nodes in one group and configure the `NavigationMesh` resource's **Source Geometry Mode** and **Source Geometry Group Name** to use that group.
3. Click the `NavigationMesh` resource in the Inspector and make **Parsed Geometry Type** match the source: **Mesh Instances** for visible `MeshInstance3D` or `GridMap` geometry, or **Static Colliders** for the corresponding physics shapes. When using static colliders, keep **Collision Mask** on layer 1 for this project's environment collision.
4. Re-select the `NavigationRegion3D` node in the Scene dock. The bake controls appear in the toolbar above the 3D viewport, not in the Inspector's three-dot menu. Click **Bake NavMesh**.
5. Run the scene and enable **Debug → Visible Navigation**. Confirm the colored navigation surface connects the trainer to the player and leaves clearance around obstacles.

You do not need to draw a rectangular navigation boundary. With the `NavigationMesh` resource's `filter_baking_aabb` left empty, Godot derives the covered area from the source geometry it finds. Set `filter_baking_aabb` and its offset only when intentionally cropping a large bake or building navigation chunks.

Keep character roots on the visible walkable surface; never move a character upward to match the navigation debug overlay. Baked path points can be vertically offset from the rendered floor because of navigation rasterization and source transforms. [`NPCController`](core/NPCController.gd) measures that difference for every new path and automatically applies the appropriate `NavigationAgent3D.path_height_offset`. This works without scene-specific tuning whether the baked path is at `Y = 0`, `Y = 0.5`, or another height near the character.

For predictable baking, keep the `NavigationRegion3D` at scale `1, 1, 1`. Prefer unit-scale source geometry as well; set modular dimensions through meshes and `GridMap.cell_size` instead of scaling the navigation source merely to enlarge the bake. The navigation mesh gets its coverage from parsed source geometry, not from the `NavigationRegion3D` transform.

To verify the automatic height handling from the repository root, run:

```sh
godot --headless --path . --scene res://tests/navigation_path_height_smoke_test.tscn
```

### Current Encounter Limits

The existing behavior implements a one-time approach and linear dialog, but not a complete trainer encounter. After detecting the player, it approaches only once, remains complete, displays its assigned dialog through the UI Template System, and restores player movement when that template closes. It does not start a battle. Avoid overlapping trainer sightlines for now because there is no encounter manager arbitrating between multiple simultaneous detections or UI templates.

To make another trainer type, duplicate the Kyle scene and give it a descriptive name. Keep the `PFRCharacter` root structure, collision capsule, `Visual` node, and character art pack. Duplicate [`overworld/trainer_lake/TrainerKyle.gd`](overworld/trainer_lake/TrainerKyle.gd) when that trainer needs different detection distance, ray height, collision mask, stopping buffer, or arrival distance; the controller should continue to extend [`core/NPCController.gd`](core/NPCController.gd) and assign a `TrainerBehavior` resource.

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
