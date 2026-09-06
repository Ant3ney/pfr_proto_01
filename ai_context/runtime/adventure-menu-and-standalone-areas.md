# Adventure Menu and Standalone Areas

Read this document when changing Stretchman, the Adventure Menu, shops, loot
boxes, battle money rewards, route/gym/Champion progression, or the authored
menu-accessible areas. These features are production domains under `game/`;
there is no Stretchman-specific progression owner or procedural destination
runtime.

## Stretchman and menu ownership

[`stretchman.tscn`](../../game/actors/npcs/residents/stretchman/stretchman.tscn)
inherits [`resident_base.tscn`](../../game/actors/npcs/residents/resident_base.tscn),
which inherits the shared
[`pfr_character.tscn`](../../game/actors/character/pfr_character.tscn).
Stretchman's scene-local `NPCController` contains the reusable
[`MenuNpcBehavior`](../../game/actors/npcs/shared/menu_npc_behavior.gd). Its two
principal Inspector properties are `menu_scene` and `interaction_prompt`; the
scene assigns
[`adventure_menu.tscn`](../../game/ui/adventure_menu/adventure_menu.tscn).

`MenuNpcBehavior` faces the interactor, locks player movement while its assigned
menu exists, adds the menu beneath `UIManager`, and restores movement from both
the menu's `closed` signal and `tree_exited`. It has no dependency on economy,
inventory, shops, battles, rewards, progression, or area metadata. The
Adventure Menu calls domain services directly and emits `closed` before asking
`ChallengeProgressionSystem` to travel.

Stretchman is an ordinary resident instance in Miare Station. The station and
all other city-connected interiors remain beneath
[`new_bouffalant_city/`](../../game/world/levels/new_bouffalant_city/); they are
not standalone menu destinations.

## Domain boundaries

The former consolidated goal state is split among these autoloads:

- [`EconomySystem`](../../game/economy/economy_system.gd) exclusively owns the
  balance, affordability, spending/granting, money formatting, and last battle
  reward. A new profile starts with `$50`.
- [`InventorySystem`](../../game/inventory/inventory_system.gd) owns item
  quantities, claimed one-time gifts, discards, and atomic bag/Pokémon held-item
  transfers.
- [`ShopSystem`](../../game/economy/shop/shop_system.gd) owns immutable item,
  Pokémon, and loot-box catalogs plus purchase transactions. It delegates money,
  bag, and captured-Pokémon mutations to their owning systems and compensates a
  failed delivery by refunding the charge.
- [`ChallengeProgressionSystem`](../../game/progression/challenges/challenge_progression_system.gd)
  owns route completion/unlocks, badges, Champion completion, the active area,
  run identity, and defeated non-wild encounters.
- [`BattleRewardSystem`](../../game/battle/rewards/battle_reward_system.gd)
  listens for completed battles, records wins with challenge progression, and
  grants the outcome's money through `EconomySystem`.
- [`AdventureMenu`](../../game/ui/adventure_menu/adventure_menu.gd) owns only
  presentation, filtering, focus, selection, and calls into those services.

The menu has Buy Items, Buy Pokémon, Loot Boxes, Gyms 1–8, Champion, and Routes
tabs. Item and Pokémon search normalizes punctuation and accents and tolerates
bounded spelling errors. Pokémon filters run before the Pokédex, price, or
subjective-coolness sort. Visible list rows use
`BattleSpriteCatalog.load_front_thumbnail`; the detail panel uses the existing
animated front atlas. Do not add network lookup or a second GIF decoder.

## Shop and loot-box rules

[`items.json`](../../game/economy/shop/catalogs/items.json) contains 2,223
PokeAPI item rows and
[`pokemon.json`](../../game/economy/shop/catalogs/pokemon.json) contains all
1,025 default Pokémon. Regenerate or validate them with
[`generate_shop_catalogs.py`](../../tools/catalogs/generate_shop_catalogs.py).
The generator, not UI code, is the price authority.

Basic items fit the low-cash economy (`Potion` and `Poke Ball` cost `$20`), and
`exp-share` has a fixed `$100,000` price. Direct Pokémon purchases cost at least
`$500` and arrive in PC storage from Lv. 5 through Lv. 20 using the one-way
logarithmic price projection in `ShopSystem`. Later evolution stages retain the
catalog generator's monotonic price constraint.

[`LootBoxCatalog`](../../game/economy/loot_boxes/loot_box_catalog.gd) owns the
six tier offers and the common/high-quality pools. Every tier uses the same
`0.10` high-quality chance; price changes the high-quality table, not the hit
rate. `ShopSystem.buy_loot_box()` chooses and adds the immutable prize before
returning its summary, and purchases/loot prizes enter PC storage rather than
changing the active party. The
[`LootBoxRoulette`](../../game/economy/loot_boxes/loot_box_roulette.gd) is
presentation-only and places the already-awarded Pokémon at its authored stop.
Skipping or closing the animation cannot reroll or lose the prize.

## Standalone-area resources

[`standalone_area_catalog.tres`](../../game/world/levels/standalone_areas/standalone_area_catalog.tres)
contains exactly 49 unique definitions: `route_00` through `route_39`, `gym_01`
through `gym_08`, and `champion_challenge`. Each adjacent
`area_definition.tres` uses
[`StandaloneAreaDefinition`](../../game/world/levels/standalone_areas/standalone_area_definition.gd)
to expose these Inspector fields:

- stable ID, route/gym/Champion category, numeric order, display name,
  description, and biome;
- a `PackedScene` destination and entry marker;
- suggested minimum and maximum levels;
- trainer and wild `BattleEncounterDefinition` arrays; and
- the immediately preceding route prerequisite where applicable.

The catalog validates exact counts, IDs, definitions, scene references,
encounter IDs, and the contiguous route prerequisite chain.
`ChallengeProgressionSystem.launch_area(area_id)` resolves the resource,
validates its unlock state, records a new active run, and calls the unchanged
`GameInstance.transfer_to_scene()` contract. Failure rolls the run state back.
Route 0 begins unlocked; each later route requires the prior route's completion.
Routes 1–39 require all authored trainer encounters in the current run before
their physical end gate can complete the route. Route 0 retains its standard
session-level trainers and is allowed to complete at its far gate directly.

The challenge battle scene uses
[`ChallengeBattleEncounterProvider`](../../game/battle/encounters/challenge_battle_encounter_provider.gd)
to resolve the active encounter from the catalog. Encounter rosters are typed,
Inspector-editable resources stored with their owning area, not dictionaries
constructed by a menu or NPC.

## Authored level workflow

All 49 menu-accessible areas are independent inherited scenes beneath
[`standalone_areas/`](../../game/world/levels/standalone_areas/). Routes 1–39,
all eight gyms, and the five-opponent Champion challenge were seeded from the
former deterministic layouts and then materialized. Trainers, grass, gates,
boundaries, decorations, lights, objectives, and markers are ordinary scene
nodes visible in the Scene tree. There is no runtime world generator.

Every walkable level inherits a base from
[`level_bases/`](../../game/world/level_bases/). `PFRWorldLevel` supplies
`get_player()`, `find_spawn_marker()`, and editor configuration warnings. Its
required hierarchy is:

```text
PFRWorldLevel
├── Runtime
│   ├── Player
│   ├── Camera3D
│   └── GameUI
├── Environment
├── NavigationRegion3D
│   └── WorldGeometry
│       ├── Ground
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

Production code must use the level API rather than assume the player is a root
child. Author areas through Godot inherited scenes, the FileSystem dock, the
Scene tree, Inspector resources, and drag-and-drop. Shared trainer presets
inherit [`trainer_base.tscn`](../../game/actors/npcs/trainers/trainer_base.tscn),
and levels instance those presets instead of reproducing character hierarchies.
Edit a route such as
[`route_17.tscn`](../../game/world/levels/standalone_areas/routes/route_17/route_17.tscn)
directly and run it with F6; no generation step is part of routine authoring.

Route 0 remains the detailed authored meadow reference: 96 unit-scale 4 × 4 m
modules, five tall-grass fields, seven Lv. 3–6 trainers, mandatory sight
chokepoints, `Route0Start`, a far-end completion gate, and a red interactive
return gateway to the Gate Building's `Route0ReturnSpawn`.

## Rewards, persistence, export, and verification

Route battle wins follow the quadratic curve from the `$20` Route 0 baseline to
`$94,610` at Route 39. Gym wins pay `$200` through `$6,000`; the Elite Four and
Champion pay `$8,000` through `$12,000`. A non-forfeit tie pays 25%, a loss pays
10%, and a forfeit pays zero. Battles not found in the standalone catalog use
the `$20` beginner win baseline.

`ProgressionAutosave` schema 6 persists economy, inventory, and challenge
progression as independent sections. It migrates schema 1–5 saves by splitting
the former consolidated payload without losing balance, items, gifts, badges,
completed routes, Champion completion, or active-run data. See
[`progression-autosave.md`](progression-autosave.md).

The selected-resource Web preset is regenerated by
[`update_export_preset.cjs`](../../tools/battle_sprite_pipeline/update_export_preset.cjs).
Its pack verifier requires exactly 49 standalone scenes and rejects legacy
runtime roots. Core regression checks are:

```bash
python3 tools/catalogs/generate_shop_catalogs.py --check
godot --headless --path . --scene res://tests/integration/domain_systems_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/adventure_menu_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/standalone_area_scenes_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/progression_autosave_smoke_test.tscn
```

The standalone scene test requires all 49 valid, independently loadable scenes,
the common hierarchy, static trainers and encounter resources, and the absence
of the former procedural destination/content classes.
