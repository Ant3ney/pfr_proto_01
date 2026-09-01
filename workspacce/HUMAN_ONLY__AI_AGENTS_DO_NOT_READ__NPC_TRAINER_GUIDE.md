<!--
AI AGENT WARNING: STOP HERE.
This is a human-only learning document. AI agents, automated assistants,
indexers acting as agents, and agentic code-review tools must not read,
summarize, ingest, quote, or use the contents of this file.
-->

> [!CAUTION]
> **HUMAN-ONLY FILE — AI AGENTS MUST NOT READ THIS FILE.** This guide is for
> Anthony to study directly. Automated agents should close it and use the live
> code plus the routed documents under `ai_context/` instead.

# How the NPC Trainer System Works

This guide follows one concrete example—Trainer Kyle—from an idle character in
the overworld through detection, navigation, dialog, scene transition, battle
data setup, battle UI, and return to the overworld.

It describes the repository's current working tree, verified on September 1,
2026. The code is authoritative if this guide later becomes stale.

## The shortest useful mental model

A trainer is not one large script. It is a `PFRCharacter` assembled from several
small pieces:

```text
Level scene
└── TrainerKyle (CharacterBody3D + PFRCharacter.gd)
    ├── CollisionShape3D
    └── Visual
        └── CharacterArt (instance of model.glb)

Resources assigned to TrainerKyle
├── CharacterMovement       physical locomotion and turning
├── NPCController           destination and NavigationAgent3D ownership
├── TrainerBehavior         detection, approach, dialog, and battle launch
├── PFRCharacterArtAssetPack model and animation clip names
└── Dialog                  speaker name and ordered lines
```

The important ownership split is:

| Question | Owner |
| --- | --- |
| What runs every physics frame? | [`core/PFRCharacter.gd`](core/PFRCharacter.gd) |
| Is this NPC waiting, approaching, or finished? | [`core/TrainerBehavior.gd`](core/TrainerBehavior.gd) |
| What is the next navigation waypoint? | [`core/NPCController.gd`](core/NPCController.gd) |
| How does the body turn and physically move? | [`core/CharacterMovement.gd`](core/CharacterMovement.gd) |
| Which model and animation clips are used? | [`core/PFRCharacterArtAssetPack.gd`](core/PFRCharacterArtAssetPack.gd) plus a character `.tres` |
| What does the trainer say? | [`core/Dialog.gd`](core/Dialog.gd) plus a dialog `.tres` |
| Who locks player movement and changes scenes? | [`core/GameInstance.gd`](core/GameInstance.gd) |
| Who owns battle rules and battle state? | [`battle/system/BattleSystem.gd`](battle/system/BattleSystem.gd) |
| Who translates battle state into visuals and UI calls? | [`battle/BattleScene.gd`](battle/BattleScene.gd) |

## Start with the scene, not with a similarly named script

Open [`overworld/trainer_lake/TrainerKyle.tscn`](overworld/trainer_lake/TrainerKyle.tscn).
Its root is a `CharacterBody3D` running `PFRCharacter.gd`. The scene assigns:

- a scene-local `TrainerBehavior` subresource to `npc_behavior`;
- [`art/characters/zach/zach.tres`](art/characters/zach/zach.tres) to
  `character_art_asset_pack`;
- [`art/characters/zach/models/model.glb`](art/characters/zach/models/model.glb)
  as the existing `Visual/CharacterArt` child;
- [`overworld/dialogs/trainer_kyle.tres`](overworld/dialogs/trainer_kyle.tres)
  to the behavior's `dialog`;
- `res://battle/kyle_battle_scene.tscn` as its battle scene; and
- `trainer-kyle-lake-v1` as its stable encounter ID.

There is also an
[`overworld/trainer_lake/TrainerKyle.gd`](overworld/trainer_lake/TrainerKyle.gd)
custom controller in the repository. **The current Kyle scene does not reference
that script.** It now authors `TrainerBehavior` directly on `PFRCharacter`.
Reading the `.tscn` first prevents you from accidentally tracing an unused or
legacy path.

`resource_local_to_scene = true` on the behavior matters. `TrainerBehavior` is a
mutable `Resource`: its approach state changes at runtime. Each trainer instance
must get its own behavior state instead of sharing `COMPLETE` with other
trainers.

## Where the standing trainer comes from

The playable Route 0 wrapper is
[`overworld/route_0/route_0.tscn`](overworld/route_0/route_0.tscn). It instances
the larger authored meadow scene in
[`overworld/route_4/route_4.tscn`](overworld/route_4/route_4.tscn). That larger
scene instances Kyle and the other six trainer scenes under `RouteTrainers` and
gives each trainer a position and rotation.

[`overworld/route_0/RouteZeroRuntime.gd`](overworld/route_0/RouteZeroRuntime.gd)
then performs route-specific setup. It builds checkpoint walls, turns the
trainers toward the challenge lane, and moves a standard trainer aside if that
trainer's forced sight encounter was already consumed during this play session.
So, when debugging a Route 0 trainer's exact transform, check both the authored
scene transform and `RouteZeroRuntime._build_trainer_chokepoints()`.

When the trainer enters the scene tree, `PFRCharacter._ready()` does this:

1. Adds the character to the `pfr_characters` group.
2. Prepares its movement controller and behavior composition.
3. Loads or finds its character art.
4. Builds the runtime locomotion animation library.
5. Starts the idle animation.

At this point the trainer is visually standing still and its encounter state is
`TrainerBehavior.ApproachState.WAITING`.

## How it gets its art

Follow this chain:

```text
TrainerKyle.tscn
  → character_art_asset_pack = zach.tres
      → character_scene = zach/models/model.glb
  → Visual/CharacterArt = an instance of that same model.glb
```

[`art/characters/zach/zach.tres`](art/characters/zach/zach.tres) is a
`PFRCharacterArtAssetPack`. It records:

- the packed GLB scene;
- a 180-degree model correction;
- the idle clip name;
- the run clip name; and
- the root-motion bone name, `origin`.

`PFRCharacter._load_character_art_asset_pack()` first looks for an existing
`Visual/CharacterArt`. Kyle's scene already has one, so it reuses it. If that
child were missing, it would instantiate `character_scene` from the art pack at
runtime. It then applies the art-pack rotation and finds the GLB's
`AnimationPlayer` using the pack's `animation_player_path` (the default is
`AnimationPlayer`).

The `.glb.import` file confirms that Godot imports the GLB as a `PackedScene`
with animation import enabled at 30 FPS. The separate `.tranm` files and
`source_manifest.json` preserve source/provenance information; gameplay code
does not load `.tranm` files. Runtime animation clips are already embedded in
the imported GLB.

## Where its animation state machine actually comes from

There is **no `AnimationTree` state machine** in this trainer path. The current
"state machine" is a two-choice switch written directly in
`PFRCharacter.gd`.

During setup, `_prepare_animation_library()`:

1. Finds the art pack's named idle and run animations in the model's
   `AnimationPlayer`.
2. Deep-duplicates both clips.
3. Removes position tracks targeting the configured root-motion bone. This is
   why the animation does not drag the model independently of game movement.
4. Puts the copies into a new animation library named `locomotion`.
5. Exposes them to playback as `locomotion/idle` and `locomotion/run`.

After movement each physics frame, `_update_animation()` measures horizontal
velocity:

```text
horizontal speed > 0.05  → locomotion/run
horizontal speed ≤ 0.05  → locomotion/idle
```

`_play_animation()` calls `AnimationPlayer.play()` with the exported blend time
(default `0.15` seconds), and `_current_animation` prevents the same clip from
restarting every frame.

Do not confuse the two state systems:

| State system | States | Purpose |
| --- | --- | --- |
| Trainer encounter state | `WAITING`, `APPROACHING`, `COMPLETE` | Decides detection, approach, dialog, and battle flow |
| Character animation choice | idle or run | Reflects current horizontal velocity |

Because `CharacterMovement` can rotate the `Visual` in place before applying
velocity, a sharp turn can correctly remain in the idle animation until forward
movement begins.

## The physics-frame call order

This small ordering in `PFRCharacter._physics_process()` explains most of the
system:

```text
1. npc_behavior.process_behavior(character, controller)
2. controller.get_move_target(character)
3. character_movement.process_movement(..., move_target, delta)
4. PFRCharacter._update_animation()
```

In plain language: the trainer decides what it wants, navigation supplies the
next point, locomotion moves the body toward that point, and animation reflects
the resulting velocity.

## How automatic trainer detection works

While the behavior is `WAITING`, `TrainerBehavior.process_behavior()` performs
the classic trainer sight check.

First, it checks whether this encounter should be suppressed after a battle
return. It also refuses automatic sight if `automatic_sight_encounter` is false,
or if a standard trainer's one-time sight encounter was already consumed.

It derives forward from the `Visual` node's global local `-Z` direction. This is
important: the trainer root/`Visual` direction determines gameplay facing; the
180-degree rotation on `CharacterArt` is merely a model correction.

It casts one physics ray:

- origin: trainer position plus `ray_height` (default `0.8 m`);
- end: forward by `detection_distance` (default `80 m`);
- collision mask: default layer 1; and
- excluded body: the trainer itself.

The first hit must cast to `PlayerCharacter`. A wall or another layer-1 body in
front of the player blocks detection by design.

When the player is detected, the behavior immediately disables player movement
through `GameInstance`. It then calculates a fixed stopping point beside the
player. The distance is based on:

```text
trainer collision radius
+ player collision radius
+ stopping_buffer (default 0.15 m)
```

The behavior stores that one position in `_approach_target`; it does not chase a
later-moving target. It switches to `APPROACHING` and calls
`controller.move_to(_approach_target)`.

The encounter-state flow is:

```text
WAITING
  │ player is first unobstructed ray hit
  ▼
APPROACHING
  │ horizontal distance to fixed target ≤ arrival_distance
  ▼
COMPLETE
  │ stop navigation
  └ start dialog
```

## How it interacts with Godot navigation

`TrainerBehavior` decides the final approach destination, but
[`core/NPCController.gd`](core/NPCController.gd) owns path following.

`move_to()` stores the destination and marks it changed. On the next call to
`get_move_target()` the controller lazily creates a `NavigationAgent3D` as a
child of the trainer. Trainer scenes intentionally do not contain a manually
authored agent.

The controller then:

1. Waits until the world's navigation-map iteration is nonzero.
2. Recalibrates if the map changed.
3. Finds the navigation point closest to the trainer's foot-level position.
4. Assigns the vertical difference to
   `NavigationAgent3D.path_height_offset`.
5. Assigns the final `target_position`.
6. Returns `get_next_path_position()` to the movement system each frame.

The path-height adjustment is why the character root stays on the visible floor
even when baked navigation points appear at something like `Y = 0.5`.

[`core/CharacterMovement.gd`](core/CharacterMovement.gd) is the physical half of
the journey. It flattens the target offset onto XZ, clears velocity, rotates the
`Visual` toward the target, applies forward XZ velocity, and calls
`CharacterBody3D.move_and_slide()`. It can pivot in place for large direction
changes and arc through smaller turns.

Navigation and collision solve different problems:

- the baked `NavigationMesh` proposes a route around obstacles;
- physics collision prevents the `CharacterBody3D` from passing through actual
  solid shapes; and
- this movement system is planar and does not apply gravity or climb between
  genuinely different floor elevations.

When the trainer reaches the fixed approach point,
`TrainerBehavior._complete_approach()` changes the encounter state to
`COMPLETE`, calls `controller.stop_moving()`, and starts dialog.

## The alternate manual-interaction path

The player scene contains
[`rnd/interaction/PlayerInteractionDetector.gd`](rnd/interaction/PlayerInteractionDetector.gd)
as `LookInteraction`. Every physics frame, while player movement is available,
it scans the `pfr_characters` group and chooses one behavior-approved NPC:

- within `3.25 m`;
- inside a 38-degree forward half-angle;
- visible along a layer-1 ray at `1.35 m`; and
- accepted by the NPC's `can_interact()` implementation.

[`demo/GameUI.gd`](demo/GameUI.gd) listens to the detector's `target_changed`
signal. It shows the bottom-right interaction button and routes touch/click, E,
Enter, Space, or gamepad A into `try_interact()`.

The current dispatch chain is:

```text
GameUI
  → PlayerInteractionDetector.try_interact()
  → target PFRCharacter.interact(player)
  → TrainerBehavior.interact(character, controller, player)
```

Manual interaction is accepted only while the trainer is `WAITING` and no
movement lock or scene/battle transition is active. The trainer stops, turns its
`Visual` toward the player, locks player movement, and starts the same dialog.
If a manually activated trainer has no dialog, it can launch its configured
battle directly. In contrast, the automatic approach path treats a missing or
empty dialog as cleanup and does not start a battle.

## How dialog starts and controls UI

Kyle's dialog data lives in
[`overworld/dialogs/trainer_kyle.tres`](overworld/dialogs/trainer_kyle.tres).
The `Dialog` resource contains only `character_name` and `dialog_lines`.

The presentation chain is:

```text
TrainerBehavior._start_dialog()
  → UIManager.show_ui(first_line)
      → instantiate core/ui/ui_template.tscn on CanvasLayer 100
  → set speaker name
  → label the primary action "Next"
  → bind _advance_dialog as the action callback
  → bind _finish_dialog as the dismiss callback
```

`TrainerBehavior`, not `UIManager`, owns the current line index. Each press calls
`UITemplate.set_text()` on the same template. After the final line, the behavior
sets `_start_battle_after_dialog`, then calls `UITemplate.close()`.

`close()` is important. It emits `dismissed`, calls the registered dismiss
callback, and only then queues the UI for deletion. The dismiss callback clears
the trainer's dialog state and releases its movement lock. Directly calling
`queue_free()` would skip that cleanup callback.

## How the battle scene starts

After normal final-line completion, `TrainerBehavior._finish_dialog()` calls
`_start_configured_battle()`. That method hands this small dictionary to
`GameInstance.startBattle()`:

```gdscript
{
    "encounter_type": "trainer",
    "trainer_name": dialog.character_name,
    "battle_scene_path": battle_scene_path,
    "encounter_id": encounter_id,
    "trainer_aggression_mode": aggression_mode,
}
```

The trainer briefly releases its dialog lock first. `GameInstance.startBattle()`
synchronously takes over the movement lock if the launch is accepted.

`GameInstance` is an autoload, so it survives the scene change. It deep-copies
the dictionary into pending battle data and adds information such as:

- the source overworld scene path;
- the implicit return scene path;
- a default transition title such as `TRAINER BATTLE`; and
- a transition subtitle based on the trainer name.

It also records the player's pre-battle global transform and visual facing so
they can be restored on return. A normal accepted standard-trainer launch marks
that encounter's automatic sight challenge as consumed for the current process.

Next, `GameInstance` creates another `UITemplate`, changes it from dialog mode
to battle-transition mode, and fully covers the overworld. Only the transition's
covered callback calls `change_scene_to_file(battle_scene_path)`.

### What the trainer sends—and what it does not

The trainer sends identity and routing metadata. It does **not** send either
Pokémon team to the battle scene.

| Data | Source |
| --- | --- |
| Which concrete scene to open | `TrainerBehavior.battle_scene_path` |
| Which encounter that scene must contain | `TrainerBehavior.encounter_id` |
| Player party | `CollectionSystem.get_battle_party_members()` inside `BattleSystem` |
| Opponent party | The concrete battle scene's encounter resource |
| Server battle token and revisions | `BattleSystem`, kept in memory and never placed in launch data |

The cross-scene dictionary is temporary handoff state in `GameInstance`; Godot's
scene-change call itself receives only a scene path.

## How Kyle's encounter data reaches the battle system

[`battle/kyle_battle_scene.tscn`](battle/kyle_battle_scene.tscn) inherits the
shared [`battle/battle_scene.tscn`](battle/battle_scene.tscn) and adds exactly one
node in the `battle_encounter_provider` group. That provider references
[`battle/encounters/trainer_kyle_lake_v1.tres`](battle/encounters/trainer_kyle_lake_v1.tres).

The encounter resource owns Kyle's battle-side data:

- stable encounter ID and display/API names;
- Wooper and Magikarp member IDs;
- Pokémon IDs and exact sprite IDs;
- levels and starting health;
- move IDs; and
- forfeit policy.

On `_ready()`, `BattleScene`:

1. Connects to `BattleSystem` signals.
2. Prepares local intro visuals and the sprite presenter.
3. Calls `GameInstance.enter_battle_scene()`, promoting pending launch data to
   active launch data.
4. Detects that this is a networked encounter because the launch has an
   `encounter_id`.
5. Calls `BattleSystem.begin_current_battle_scene()`.

`BattleSystem` finds exactly one encounter provider inside the current scene,
validates its resource, and requires the provider's encounter ID to match the
ID sent by the trainer. It then gets the player's team from `CollectionSystem`,
converts the encounter resource into the opponent server team, and sends the
start request through `BattleRestClient`.

This split prevents overworld code from constructing battle DTOs. The overworld
chooses an encounter; the concrete battle scene owns the opponent definition;
`BattleSystem` owns protocol and state.

## The covered connection, reveal, and intro

The battle is intentionally not revealed just because the new scene loaded.
The normal order is:

```text
Trainer dialog completes
  → GameInstance covers overworld
  → concrete battle scene loads
  → BattleScene promotes launch data
  → BattleSystem validates encounter and sends start request
  → valid initial response is accepted
  → BattleSystem emits snapshot and presentation events
  → BattleScene gives snapshot to sprite presenter and UI data mapper
  → GameInstance reveals the battle scene
  → BattleScene plays its local intro animation
  → both reveal and local intro finish
  → BattleScene creates the persistent battle HUD
  → queued battle events play
```

If initial connection fails, the cover remains in place and the battle choice
overlay can show Retry/Return above it. A valid initial response is the normal
gateway to revealing the battlefield.

## How battle art is chosen

The overworld trainer's 3D model does not transfer into the battle scene. The
battlefield displays the active Pokémon instead.

`BattleSystem` enriches accepted snapshot members with local `pokemonId`,
`spriteId`, and any approved override. `BattleScene` passes a deep copy of that
snapshot to
[`battle/system/BattleSpritePresenter.gd`](battle/system/BattleSpritePresenter.gd).
The presenter asks
[`battle/system/BattleSpriteCatalog.gd`](battle/system/BattleSpriteCatalog.gd)
for the exact generated front sprite for the opponent and back sprite for the
player. The catalog starts at
`art/battle/sprites/generated/catalog.json` and lazily loads the active PNG atlas
and JSON frame metadata.

Translated battle events make the presenter lunge, shake, tint, switch, or faint
the sprite with tweens. Those are presentation effects; `BattleSystem` remains
the owner of the actual battle state.

## How the battle manipulates UI

There are several UI surfaces with different owners:

| Surface | Created/owned by | What drives it |
| --- | --- | --- |
| Overworld interaction button | `GameUI` | `PlayerInteractionDetector.target_changed` |
| Trainer dialog | `TrainerBehavior` using `UIManager`/`UITemplate` | Dialog line index and callbacks |
| Full-screen battle transition | `GameInstance` using `UITemplate` | Cover/reveal lifecycle |
| Persistent battle status/command HUD | `BattleScene` using a new `UITemplate` | Copied `BattleSystem` snapshots and requests |
| Move/switch/error/result surface | `BattleChoiceOverlay` inside the battle scene | Typed request, error, and result data |

Once the battle intro is complete, `BattleScene._show_battle_ui()` asks
`UIManager` for a fresh template and calls `play_battle_ui_in()`. That hides the
template's ordinary dialog controls and instances
[`core/ui/battle_ui_overlay.tscn`](core/ui/battle_ui_overlay.tscn).

`BattleScene` connects to these `BattleSystem` signals:

- `state_changed` to lock or unlock commands;
- `snapshot_changed` to update names, levels, HP, XP, and Pokémon sprites;
- `presentation_events_ready` to show messages and await visual effects;
- `choice_request_changed` to expose only server-authorized moves/switches;
- `battle_ended` to show the result; and
- `battle_error_changed` to show errors and Retry/Return choices.

The response path back from the UI stays typed:

```text
Fight button
  → BattleScene opens BattleChoiceOverlay with request.moves
  → move button emits move_chosen(moveIndex)
  → BattleScene calls BattleSystem.choose_move(moveIndex)
  → BattleSystem validates the option and submits the action
```

Party selection similarly emits a `memberId`, and Run first opens a forfeit
confirmation. The Bag command is currently disabled/unavailable in battle v1.

The crucial design rule is that the trainer does not manipulate battle labels,
buttons, or sprites. The trainer starts a configured encounter; battle state
flows from `BattleSystem` signals through the thin `BattleScene` adapter into UI
and presentation objects.

## Battle completion and return

When translated result events finish, `BattleSystem` enters `ENDED` and
`BattleChoiceOverlay` shows Continue. Continuing calls
`BattleSystem.continue_after_result()`, which asks `GameInstance` to cover the
battlefield and return to the captured source scene.

On return, `GameInstance`:

1. Reloads the overworld scene.
2. Restores the player's exact pre-battle transform, zeroes velocity, and
   restores visual facing.
3. Associates the completed encounter ID with this one returned scene instance
   to prevent an immediate loop.
4. Re-enables player movement.
5. Reveals the overworld.

The reloaded trainer receives a fresh scene-local `TrainerBehavior`. A standard
trainer remains available for a manual rematch, but its consumed encounter ID
prevents another automatic sight challenge during the current play session.
Route 0's runtime also moves such a trainer aside so the checkpoint lane remains
open.

## A practical reading order when debugging

Use this order instead of searching the whole repository at once:

1. **Composition and configuration:** open the trainer `.tscn` and identify its
   root script, `npc_behavior`, art pack, dialog, scene path, and encounter ID.
2. **Placement and facing:** find where that `.tscn` is instanced in the level,
   then check any level runtime script that changes its transform.
3. **Frame loop:** read `PFRCharacter._physics_process()`.
4. **Detection/state:** read `TrainerBehavior.process_behavior()` and watch
   `_approach_state`.
5. **Path request:** follow `controller.move_to()` into
   `NPCController.get_move_target()`.
6. **Physical movement:** follow the returned point into
   `CharacterMovement.process_movement()`.
7. **Animation:** follow velocity into `PFRCharacter._update_animation()` and
   trace clip names back through the art-pack `.tres`.
8. **Dialog:** follow `_start_dialog()`, `_advance_dialog()`, and
   `_finish_dialog()` into `UIManager` and `UITemplate`.
9. **Scene handoff:** follow `_start_configured_battle()` into
   `GameInstance.startBattle()`.
10. **Encounter data:** open the concrete battle scene's provider and its
    encounter `.tres`.
11. **Battle state:** follow `BattleSystem.begin_current_battle_scene()` and its
    emitted signals.
12. **Battle UI:** return to the matching handlers in `BattleScene.gd`.

Useful runtime values to watch in the Godot debugger are:

- `TrainerBehavior._approach_state` and `_approach_target`;
- `NPCController._has_move_target`, `map_coordinates`, and the runtime
  `NavigationAgent3D.target_position`;
- `PFRCharacter.velocity` and `_current_animation`;
- `GameInstance` pending/active battle data and transition flags;
- `BattleSystem._state`, `_encounter_id`, `_revision`, `_snapshot`, and
  `_choice_request`—but do not log or expose `_state_token`; and
- `BattleScene._snapshot`, `_choice_request`, and `_battle_ui_template`.

## Symptom-to-file map

| Symptom | Read first |
| --- | --- |
| Wrong or missing trainer model | trainer `.tscn` → art-pack `.tres` → `PFRCharacter._load_character_art_asset_pack()` |
| Missing idle/run animation | art-pack clip names → imported GLB `AnimationPlayer` → `_prepare_animation_library()` |
| Trainer faces the wrong detection lane | level/root rotation and `TrainerBehavior._get_forward_direction()` |
| Trainer never notices the player | detection mask/ray and first physics hit in `TrainerBehavior._detect_player()` |
| Trainer notices but does not move | `NPCController`, baked `NavigationRegion3D`, reachable endpoints, and path-height offset |
| Trainer moves strangely | `CharacterMovement` turn settings, physical collision, and next nav waypoint |
| Interaction button is missing | `PlayerInteractionDetector.can_interact()` checks and `GameUI` binding |
| Dialog freezes or player stays locked | `TrainerBehavior` callbacks and `UITemplate.close()` |
| Wrong battle opens | trainer `battle_scene_path`, trainer `encounter_id`, and concrete provider ID |
| Empty/wrong opponent team | encounter `.tres` and `BattleSystem.begin_current_battle_scene()` |
| Battle HUD is stale | `BattleSystem` signals → `BattleScene` handlers → `UITemplate.update_battle_ui()` |

## Focused verification scenes

From the repository root, these are the most relevant checks:

```bash
godot --headless --path . --scene res://tests/pfr_character_behavior_composition_smoke_test.tscn
godot --headless --path . --scene res://tests/navigation_path_height_smoke_test.tscn
godot --headless --path . --scene res://tests/trainer_dialog_battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_data_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_scene_lifecycle_test.tscn
godot --headless --path . --scene res://rnd/tests/interaction_hud_smoke_test.tscn
```

The first four passed against the working tree when this guide was written.

---

> [!WARNING]
> **AI AGENTS: DO NOT READ OR PROCESS THIS HUMAN-ONLY FILE.** Use current source,
> tests, and the routing instructions in `ai_context/index.md` instead.
