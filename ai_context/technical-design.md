# Technical Design

## Battle System

The `BattleSystem` autoload is the single gameplay coordinator for PvE battles.
It talks to the stateless production REST service backed by pinned Pokémon
Showdown, owns the token/revision/retry and validation lifecycle, writes
authoritative health snapshots to `CollectionSystem`, and exposes only copied
presentation state and typed UI intents. Battle scenes remain presentation and
input adapters; they do not construct REST commands or calculate results. See
[`runtime/battle-client.md`](runtime/battle-client.md) for the verified contract.

## Local and optional cloud persistence

`ProgressionAutosave` owns the validated schema-6 local checkpoint and
per-section offline timestamps. Optional `CloudSaveSync` sends that payload to
a same-origin Netlify Function only after a player enters a private Save ID;
opting out never disables local saving. MongoDB Atlas credentials remain
server-side, Save IDs are HMACed before becoming document keys, and
revision/timestamp/epoch conflict resolution prevents an old offline device
from undoing a confirmed reset. See
[`runtime/progression-autosave.md`](runtime/progression-autosave.md) and
[`runtime/cloud-save.md`](runtime/cloud-save.md).

## Overworld and traversal

Walkable worlds are authored as native Godot inherited scenes with modular
assets, the FileSystem dock, the Scene tree, Inspector resources, and
drag-and-drop. All 61 playable cities, routes, gyms, Champion areas, and
interiors inherit the single canonical
[`level_base.tscn`](../game/world/level_bases/level_base.tscn) directly.
`PFRWorldLevel` provides `get_player()` and `find_spawn_marker()` and warns when
the required direct `Player`, `Player/Camera3D`, `Player/GameUI`, Environment,
NavigationRegion3D/WorldGeometry, Gameplay, Markers, or Backdrop hierarchy is
incomplete. `player.tscn` owns the camera and HUD; there is no Runtime wrapper.

New Bouffalant City and its directly connected interiors live together under
[`new_bouffalant_city/`](../game/world/levels/new_bouffalant_city/). The 50
walkable areas opened from the Adventure Menu live together under
[`standalone_areas/`](../game/world/levels/standalone_areas/): 41 routes, eight
gyms, and one Champion challenge. Battle-only scenes remain under
`game/battle/`.

### Routes 0–40 and wild grass

Every route is an independent, directly editable inherited scene. The opening
level is
[`route_00.tscn`](../game/world/levels/standalone_areas/routes/route_00/route_00.tscn).
It uses the painted grass/dirt MeshLibrary, dense hedge and boulder banks,
side trails and tall-grass clearings from the `route_00_Real` visual direction.
Its seven original standard trainers retain their encounter data and Lv. 3–6
order, and `Route0Start` remains the stable entry marker. Routes 1–39 retain
their trainer and wild rosters in rebuilt textured layouts; Route 40 adds the
final Homeward Crown area.

Physical exits connect every route in both directions. The southeast city
approach enters Route 0, and Route 0's south exit returns to the city. The
Gate Building remains an additional connection. Far checkpoints retain the
route unlock and trainer-win requirements. Walking between areas
preserves journey victories; menu launches start fresh runs. See
[`runtime/adventure-menu-and-standalone-areas.md`](runtime/adventure-menu-and-standalone-areas.md)
for the verified 50-area catalog, authoring, navigation and travel contracts.

All eight gym leaders and the five Elite Four/Champion opponents keep Highly
Aggro encounter identity for repeatable challenge progression, but disable
automatic sight encounters. They stay in place until the nearby player uses
the shared Talk interaction, and a returned scene leaves the defeated boss in
`WAITING` so the same dialog can start a rematch immediately.

[`TallGrassEncounterZone`](../game/world/level_kits/gameplay/encounters/tall_grass_encounter_zone.gd)
is the reusable player-only `Area3D`. Its ready-made
[`tall_grass_encounter_zone.tscn`](../game/world/level_kits/gameplay/encounters/tall_grass_encounter_zone.tscn)
combines six unit-scale tall-grass clumps with an 8.5 × 4.5 m detection volume.
It accumulates horizontal distance only while movement is enabled, checks the
authored chance every 2 m by default, never rolls while the player stands
still, debounces a selected encounter, and calls `GameInstance.startBattle()`
with a concrete scene and stable encounter ID. Route 0 authors an 8% check
chance and launches `wild-fletchling-route-0-v1` through
[`route_0_wild_battle_scene.tscn`](../game/battle/scenes/route_0_wild_battle_scene.tscn).

The Gate Building's rear `ExitToRoute0` threshold enters Route 0 without an
interaction prop. Its city-facing arrival marker sits beyond the narrower
`ExitFront` threshold, preventing an idle return loop. Route 0's red
[`city_return_gateway.tscn`](../game/world/level_kits/gameplay/transitions/city_return_gateway.tscn)
instance beside `Route0Start` inherits the generic
[`area_gateway.tscn`](../game/world/level_kits/gameplay/transitions/area_gateway.tscn)
and returns to `Route0ReturnSpawn`. It accepts only a nearby PlayerCharacter and
supports E, Enter, Space, gamepad A, and its touch prompt.


### Character

[`pfr_character.tscn`](../game/actors/character/pfr_character.tscn) is the single authored
scene foundation for players and NPCs. It owns the `PFRCharacter` body, standard
capsule, and `Visual` pivot. [`player.tscn`](../game/actors/player/player.tscn) and every reusable NPC role scene
inherit it, then assign their role-specific controller, behavior, art pack,
and interaction children. The art pack is the only model-selection source: the
shared tool script creates a non-persistent editor preview and instantiates the
same model at runtime. Levels instance those reusable role scenes; they do not
rebuild or copy the character hierarchy. Some roles override only the inherited
capsule resource to retain a narrower collision radius.

`player.tscn` explicitly overrides the inherited `controller` property
with a scene-local `PlayerController`. Do not rely only on
`PlayerCharacter._init()` for that assignment: applying the packed base scene
can restore its default `NPCController`, which leaves both keyboard and floating
joystick input unable to produce player movement. The player-input smoke test
covers this inherited-scene boundary.

The root can be a player or NPC. It takes input represented by the player
controller component or an NPC controller that decides what it does and where
it goes.

`CharacterMovement` keeps every runtime `PFRCharacter` on the configured
collision surface without applying gravity. It casts downward once from
`PFRCharacter._ready()`, then repeats the probe at a configurable interval
after planar movement. A hit moves the character's foot-level root to the hit
height; a miss leaves the transform unchanged. The shared defaults use physics
layer 1, probe every 0.25 seconds, begin 0.5 m above the root, and recover
ground up to 12 m below.

### Controllers

### Battle being

To start a battle, you call a function on the game instance class. You pass in the data needed to pas into the battle there. Some data is implicit and you don't' have to pass it in. This function on the game istnace is called startBattle(...). It also handles the visual changes needed to start the battle intor sequence. Saves data to temportal properties that the battle scene will use to set up the battle.

#### NPCController

Specify a point on the map and the NPC will use it's  npc controller to manage the logic to go there.

Can spcifify and make logic saying that this is the kind of character that sits in one spot and looks forward untill the player enters in front of him and then runs to the player and starts a battle.

#### NPC Behavior Script

This is a type script that you can pas int the NPC cotroller and it will controll what the NPC does. The NPC controller simply provides a large ammount of helper functions the NPC behavior can call on for help.

#### Player controller

The implimentation of how the player input controlls the player. Additionaly, somethings the controll of the player may also be controlled by the game and not the player. TLypicaly, during a sequence.

### Interaction

Entities that impliment this interface will be have access to a lot of objects with moethods need to drive the interaction along.

The interaction implementation attaches a forward target detector to the shared
player and a touch-friendly interaction button to `GameUI`. `PFRCharacter`
delegates the request through `NPCController` to the owning `NPCBehavior`, so
trainer dialog/battle and Center healing retain their own sequence state and
cleanup. See [`runtime/interaction-hud.md`](runtime/interaction-hud.md).

### Sequences

A sequnce can be started via all kinds of things not limeted to an interaction or an event. A sequence, on start, will gather all of it's actors needed for the seqence. A entity needed for a sequence is called an actor. The sequence is simply the name of all the interactions and behavior used to make a squence. It's nothing really set in code. It just describes a set of interelated code.

## GameInstance and game mode

The implemented `GameInstance` autoload owns cross-scene gameplay state. It
exposes the player-movement enable flag used by sequences and dialog callers,
the covered battle transition lifecycle, and the ordinary level-transfer entry
point `transfer_to_scene(path, optional_marker_name)`.

[`SceneTransferTrigger`](../game/world/level_kits/gameplay/transitions/scene_transfer_trigger.gd) is the reusable
player-only `Area3D` for ordinary level travel. Place its ready-made
[`scene_transfer_trigger.tscn`](../game/world/level_kits/gameplay/transitions/scene_transfer_trigger.tscn), choose a
`.tscn` path in the inspector, optionally name a destination `Node3D` or
`Marker3D`, and fit its `CollisionShape3D` to the doorway. The trigger debounces
contacts and defers the request outside the physics callback. `GameInstance`
validates that the target is a `PackedScene`, locks movement, clears floating
joystick input, changes scenes, applies the marker to the destination's first
`PlayerCharacter`, and restores the previous movement state. It exposes
started, finished, and failed signals. Path-based targets avoid cyclic scene
dependencies for bidirectional doors; selected-resource export presets must
explicitly include every destination scene. See the
[`Scene Transfer Trigger` guide](../game/world/level_kits/gameplay/transitions/scene_transfer_trigger.md) and its
focused smoke tests for the editor and runtime contracts.

The default editor workflow for a new transition is to find the reusable
packed scene in Godot's FileSystem dock, drag it into the level's
`Gameplay/Transitions` node, and configure that new instance in the Inspector.
Future authoring help should lead with this workflow, not with duplicating a
placed trigger, embedded resource, or scene content from another authored
level. Drag the destination `.tscn` from the FileSystem dock into **Destination
Scene Path**, enter the exact target marker name in **Destination Spawn
Marker**, and place or rotate that `Marker3D` in the target scene to determine
the player's arrival transform. Keep the `Area3D` and `CollisionShape3D` node
scales at `Vector3.ONE`; for per-door bounds, enable editable children on the
instance, assign its `CollisionShape3D` a new local shape resource, and edit the
shape's dimensions directly. Existing city instances that encode bounds with
non-uniform root scale describe current data, not the preferred example for new
authoring. Place every arrival marker clear of geometry and outside the reverse
trigger so entering a scene cannot immediately transfer the player back.

The modular city currently authors 10 contact-triggered exterior openings. Two
serve the Pokemon Center; the other eight serve three City Hall doors, Miare
Station, the city-facing Gate Building door, two tenant buildings, and the
museum. Rouge Tower and the garage remain visual city landmarks but have no
exterior transfer triggers or return markers. Imported building collision
remains solid: each live `Area3D` reaches onto a verified walkable approach,
and every interior exit targets a dedicated exterior marker beyond the
corresponding reverse trigger. The selected-resources Web preset lists all
live string-addressed destination scenes explicitly.

## UI Template System

The implemented `UIManager` autoload displays the shared UI template and
returns the live `UITemplate` instance to its caller. The caller owns content,
callbacks, advancement, gameplay locks, and cleanup; `UIManager` does not own a
dialog state machine or prevent overlapping templates. Use `UITemplate.close()`
to run dismissal cleanup before the instance is freed.

See the [UI Template System guide](../game/battle/ui/README.md) for the complete API,
copyable message, confirmation, and multi-line dialog recipes, editor setup,
styling, lifecycle rules, and troubleshooting.

## Creature System

The implemented Creature System is the `CreatureSystem` autoload backed by the local data snapshot in `data/creatures/`. `CreatureSystem.get_creature(pokemon_id)` is the canonical API; `get_pokemon(pokemon_id)` is an alias. A successful lookup returns the complete PokeAPI `pokemon` record at the root, plus its location encounters in `encounters_data`, complete `pokemon-species` and `evolution-chain` records under `species_data` and `evolution_chain_data`, direct leveled targets in `evolution_options`, a top-level `xp_multiplier`, and `experience_data` containing its growth-row metadata and the cumulative level table. It performs no network request.

[`CreatureExperience`](../game/progression/creatures/creature_experience.gd) validates the generated `data/creatures/experience.json` artifact. The artifact is a compact two-dimensional table: six growth rows indexed from level 0 through 100 and one packed lookup row for every one of the 1,351 Pokemon IDs. `CreatureSystem.get_experience_for_level()`, `get_experience_to_next_level()`, `get_level_for_experience()`, `get_experience_progress()`, and `get_xp_multiplier()` are the public lookup boundary. Growth rows reproduce PokeAPI's six growth-rate tables. Reward multipliers are a project balance rule generated from pinned `pokemon-showdown@0.11.11` community singles tiers, falling back to National Dex tier and then documented BST bands; they are not an official Pokemon experience formula. Regenerate or check with `node tools/generate_creature_experience_data.mjs [--check]`.

The pinned tier multipliers descend as `AG 1.60`, `Uber 1.50`, `OU 1.35`, `UUBL 1.28`, `UU 1.22`, `RUBL 1.16`, `RU 1.12`, `NUBL 1.08`, `NU 1.04`, `PUBL 1.00`, `PU 0.96`, `ZUBL 0.93`, `ZU 0.90`, `NFE 0.82`, and `LC 0.75`. The 106 records without a usable current or National Dex tier use exact-form BST bands from `0.80` below 330 through `1.50` at 670 or above. The generator, rather than battle runtime, owns this mapping.

The snapshot contains 1,351 Pokemon records: 1,025 default National-Dex entries and 326 alternate or battle forms. Numeric IDs are PokeAPI Pokemon IDs, so default forms use National-Dex IDs `1` through `1025`, while alternate forms use PokeAPI's higher IDs such as `10001`. Call `has_pokemon(id)` before optional lookups when appropriate. Unknown IDs return an empty dictionary and set `get_last_error()`.

Every direct default-form evolution edge also has a project level requirement.
`get_evolution_options()` keeps authored PokeAPI minimum levels, fills a missing
branch from an authored sibling, and otherwise uses level 20 for the first
evolution or 36 for the second. `get_available_evolutions()` filters those
options by current level. See [`runtime/evolution.md`](runtime/evolution.md) for
the verified eligibility, form-safety, mutation, and UI contract.

Records are losslessly gzip-compressed and loaded lazily. The runtime keeps a bounded cache and returns deep copies so consumers cannot mutate cached source data. Source provenance and counts are in `data/creatures/manifest.json`; the deterministic sync and full integrity check are provided by `tools/sync_pokeapi_data.py`. The JSON retains PokeAPI's sprite and cry URLs, but those binary media assets are not part of the local stat-data snapshot.

## Collection system

The implemented `CollectionSystem` autoload owns the player's captured Pokemon and six-slot party. A specific captured instance is called a `pcl` (Pokemon collection instance). Pokemon IDs are the numeric PokeAPI IDs accepted by `CreatureSystem`; every PCL has a separately generated unique instance ID.

The autoload still seeds its legacy level-3 six-member fixture so isolated
scenes and collection tests have deterministic bootstrap data. Normal game
startup never exposes that fixture as a new profile: ProgressionAutosave either
replaces it with the saved collection or clears it before the mandatory starter
picker. A player-facing fresh profile chooses animated Charmander, Froakie, or
Treecko and receives exactly that one full-health level-5 PCL in party slot 1.
See [`runtime/starter-selection.md`](runtime/starter-selection.md) for first-run
and complete-reset ownership.

The canonical PCL object is:

```
{
  pokemonId: 25,
  pclID: "generated-unique-instance-id",
  party: {
    inParty: true,
    slot: 3
  },
  instanceStats: {
    health: 0.4,
    currentXp: 152,
    level: 5
  },
  battleProfile: {
    species: "Pikachu",
    spriteId: "pikachu",
    moves: ["thundershock", "growl"]
  },
  heldItem: "exp-share"
}
```

Party slots are integers from `1` through `6`. A Pokemon outside the party has `inParty: false` and `slot: null`. Health is normalized from `0.0` through `1.0`; `currentXp` is cumulative and level is derived from that Pokemon's growth row, from `1` through `100`. Save loading atomically migrates the former normalized `xp` field to cumulative `currentXp` and does not retain both fields.

`heldItem` is an optional lowercase catalog slug owned by the captured instance.
`set_held_item()` validates and mutates that field; it does not manage bag
quantity. `InventorySystem` is the transaction owner that moves an item
between its bag and a PCL, so replacing or taking an item cannot duplicate it.

`add_pokemon(...)` creates a PCL, `get_pcl(pcl_id)` queries a captured instance,
and `get_pcl_by_party_slot(slot)` queries by party position. `set_party_slot(...)`
rejects an occupied destination instead of silently removing another Pokemon.
`move_to_party_slot(...)` is the separate atomic organizer API: a stored member
replaces an occupied target and sends that occupant to storage, while one party
member moved onto another swaps the two slots in a single collection update.
`update_instance_stats(...)` atomically applies health and/or canonical
`currentXp`; setting XP derives level, while setting only level moves XP to the
exact level threshold. `grant_experience()` applies multi-level gains and
`get_experience_progress()` returns presentation-ready in-level progress. All
returned objects are deep copies.

`heal_party()` restores only current party members to normalized health `1.0`,
leaves stored Pokemon untouched, emits at most one `collection_changed` update,
and returns the number of members whose health changed. Overworld healers call
this ownership API instead of mutating copied PCL dictionaries.

Supported instances persist a `battleProfile` with canonical Showdown species,
exact sprite ID, and one to four equipped move IDs. Migration generates its
defaults once; battle start never recomputes them. Use
`get_battle_party_members()` for strict server-ready member DTOs,
`set_equipped_moves()` for a validated future loadout change, and
`apply_battle_health_snapshot()` for health-only callers, or
`apply_battle_health_and_experience()` to validate and commit a complete health
snapshot plus aggregated XP awards in one collection update.

`get_save_data()` returns the full collection in capture/import order. `load_save_data(...)` validates Pokemon IDs, PCL IDs, stats, and unique party slots before replacing any current data, so an invalid save cannot partially overwrite the active collection.

Evolution remains collection-owned. `get_evolution_options(pcl_id)` derives
reached direct targets, while `evolve_pokemon()` validates the selected branch,
preserves instance identity, party, health, level, and in-level XP progress,
and reconciles the Pokemon ID plus battle profile in one collection update.
Because the evolved species replaces `pokemonId` in the existing PCL, autosave
needs no parallel pending-evolution field.

Battle callers do not assemble a party one slot at a time. `BattleSystem` reads
the complete validated party through `get_battle_party_members()` and keeps
collection dictionaries out of scene code.

## Progression systems

Progression is divided by concept. `CollectionSystem` owns captured Pokémon and
party state, `MoveLearningSystem` owns pending learn choices,
`EconomySystem` owns money, `InventorySystem` owns the bag and unique gifts,
and `ChallengeProgressionSystem` owns routes, badges, the Champion result, and
active standalone runs. `ShopSystem` and `BattleRewardSystem` orchestrate
transactions through those owners but do not duplicate their state. World and
NPC logic query the narrow domain API needed for the authored interaction.

## Save system

The save owner automatically persists the validated profile, collection,
move-learning, economy, inventory, challenge-progression, and active walkable
world pose sections. It loads at startup, debounces domain changes, checkpoints
location periodically and around scene/battle transitions, and restores a saved
pose only when the same scene is active. Schema 6 retains the historical
`user://pfr_rnd_progression.json` filename for existing installations and
migrates schemas 1–5. See
[`runtime/progression-autosave.md`](runtime/progression-autosave.md).
