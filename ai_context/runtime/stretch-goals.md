# Stretchman R&D Goal Hub

Read this document when changing Stretchman, his economy and catalogs, loot
boxes, battle payouts, generated destinations, or their trainer integration.
This entire feature is deliberately isolated under `rnd/stretch/` except for
the autoload, Miare Station instance, save, and export integration points.

## Runtime ownership and Miare Station entry

`StretchGoalSystem` is an autoload after `BattleSystem`. It owns the `$50`
starting balance, purchased-item quantities, one-time world gift claims,
held-item bag transfers, shop transactions, badges, Champion completion,
completed-route sequence, active destination, defeated encounter IDs, and
battle payouts.
`StretchmanBehavior` owns the interaction movement lock and
instances `StretchGoalUI` under `UIManager`. The Miare Station concourse
instances `stretchman.tscn` and provides `StretchmanReturnSpawn` for generated
destination returns. The Pokemon Center no longer owns either node.

`StretchGoalUI` has Items, Pokemon, Loot Boxes, Gyms, Champion, and Routes
tabs. Item and Pokemon tabs expose keyboard/gamepad-focusable filters. Search
updates as text changes, normalizes accents and punctuation, tokenizes fields,
and accepts bounded edit distance so one- and two-character spelling errors can
still match. The Pokemon tab adds a separate keyboard/gamepad-focusable sort
selector for Pokedex number, both price directions, and both coolness
directions. Filtering and search run before sorting. Do not replace either path
with a network service. A refresh caused by `LineEdit.text_changed` preserves
the search field's keyboard and virtual-keyboard focus; category, filter, and
sort navigation may deliberately return focus to the results list.

## Catalogs, prices, and Pokemon presentation

`rnd/stretch/data/items.json` contains all 2,223 records from the same pinned
PokeAPI api-data commit as the creature snapshot. `pokemon.json` contains all
1,025 default Pokemon. Regenerate both with
`rnd/stretch/tools/generate_stretch_catalogs.py --item-source <pinned-checkout>`,
or regenerate only Pokemon from vendored inputs with `--pokemon-only`. Plain
`--check` validates both committed catalogs and reproduces Pokemon bytes;
combining `--check` with the pinned item source also reproduces item bytes. The
generator—not UI code—is the pricing authority.

Basic items fit the low-cash economy (`Potion` and `Poke Ball` are `$20`),
while scarce collector items retain premiums. The functional `exp-share` has
an explicit `$100,000` fixed price in the generator; the committed-catalog
validator and economy regression both enforce that exact amount. Every Pokemon
offer is at least `$500` and strictly above the price produced by the former
policy: the generator applies a universal 25% increase before rounding.
Competitive tier, capture rarity, starter status, and the explicit
`ICONIC_PRICE_FLOORS` list can raise it further. Each row records
`evolvesFromId` and `evolutionStage`; after base pricing, every direct evolution
is raised to at least 150% of its parent's final price and at least `$500` above
it. This makes every later stage strictly more expensive, including branching
families. The former legendary and mythical floors receive the same uplift,
producing minimum offers of `$2.8125B` and `$3.75B` before any evolution
adjustment.

Direct Pokemon shop purchases arrive between Lv. 5 and Lv. 20. Catalog price
is the only input to `get_pokemon_purchase_level()`: a one-way logarithmic
projection maps the `$500` floor to Lv. 5 and prices at or above `$2B` to Lv.
20, with monotonic levels between them. Level never feeds back into catalog
generation or price. The list, detail panel, purchase receipt, and stored PCL
all use the same derived level. Loot-box prizes retain their separate authored
tier levels.

Pokemon list icons call the existing `BattleSpriteCatalog.load_front_thumbnail`
and lazily load only visible rows. A selected Pokemon uses that catalog's full
front `SpriteFrames` atlas and original decoded GIF frame durations in the
detail preview. Exact IDs come from `BattleSpeciesMapping`; unsupported art
uses the existing neutral placeholder. Do not add a second GIF decoder or a
parallel Pokemon-sprite catalog for this menu.

“Coolest to Lamest” is Stretchman's deterministic subjective rating, not a
gameplay stat. `StretchGoalUI._pokemon_coolness_score()` starts from the
catalog's authored appeal label (standard 25, rare 55, iconic 70, legendary 80,
mythical 84), adds 0–14 community-tier points, 0–8 capture-rarity points, and
0/3/6 evolution-stage points, then clamps to 0–100. Equal coolness scores use
price and then Pokedex ID as stable tie breakers; the reverse mode reverses the
score and price priorities. Price sorts also use Pokedex ID for equal prices.

## Loot boxes

There are six increasingly expensive tiers from `$400` to `$4,000,000`. All
six former prices were multiplied by four, so no tier stayed flat. Every tier
uses the identical `LOOT_BOX_HIGH_QUALITY_CHANCE` of `0.10`. A failed high
quality roll selects uniformly from Voltorb, Electrode, Igglybuff, Cleffa,
Plusle, Minun, Budew, Mantyke, and Bidoof. Price changes only the tier-specific
high-quality table; the top tier's high table contains top legendaries.

`buy_loot_box()` validates funds, rolls once, adds the immutable result to
`CollectionSystem` storage, and only then deducts money and returns its summary.
Both loot-box awards and direct Pokemon purchases explicitly use party slot
zero, so the permanent player menu finds them in PC storage rather than
silently changing the active battle party.
The `LootBoxRoulette` is presentation-only: it builds a GIF-frame card reel,
uses a quintic ease-out to slow beneath the fixed middle knob, and forces the
already-awarded Pokemon into stop index 26. Skipping or closing presentation
cannot lose or reroll the prize.

## Destinations, trainers, encounters, and rewards

`StretchContent` supplies eight gym rosters, 40 outdoor routes numbered 0–39,
and an ordered Champion corridor with Elite Four teams at levels 62–78 and a
Champion team at levels 80–85. Routes are divided into 10 difficulty bands of
four routes each; every route in a band advertises the same level range. The
catalog spans 20 distinct biome families, then revisits each as a named deep
variant for the second 20 routes. Route 0 is the renamed authored modular
meadow at `overworld/route_0/route_0.tscn`. Routes 1–39 are deterministic
runtime dungeons built by `StretchDestination`.

Generated routes replace the former straight 70 m corridor with a multi-segment
sine centerline, locally rotated dirt-path slabs, continuous collision walls on
both sides, biome-colored lighting and primitive decoration, and real
`TallGrassEncounterZone` fields backed by a route-specific wild encounter.
Route length scales from 80 m on Route 1 to 196 m on Route 39; mandatory trainer
count grows from four to eight and grass-field count from four to nine. Every
route retains a valid `NavigationRegion3D`. Two static gate segments immediately
before each trainer cross the local winding path and leave a `0.9 m` center
opening. The player capsule must pass through the trainer's ray and cannot walk
around the gate because it meets the continuous route walls.

The authored Route 0 keeps its 96 modular tiles, 21-tile winding dirt path,
five grass fields, and seven Lv. 3–6 standard trainers. Runtime wiring adds a
full-map two-segment choke at every trainer, with small path-safe position
offsets where scenery formerly blocked a sight ray. These trainers retain
standard one-time automatic sight and manual rematches; they do not become
Highly Aggro. A glowing physical completion gate is placed at Route 0's far end.

Generated opponents do not have an R&D character, controller, behavior, or
battle-launch subclass. The destination instances the existing authored
trainer scenes from `overworld/trainer_lake/`, retains their direct
`PFRCharacter.npc_behavior` using the exact `core/TrainerBehavior.gd`, and
configures dialog, sight distance,
normal `0.15 m` stopping distance, battle scene path, stable encounter ID, and
the shared behavior's `HIGHLY_AGGRO` mode. Authored trainer behavior resources
are scene-local, so an opponent completed earlier in a long play session cannot
poison a later generated instance. Highly Aggro ignores standard trainers'
session-level sight consumption; the immediate return remains suppressed to
avoid a battle loop, while starting a fresh destination run restores forced sight.
The generic R&D battle provider resolves that normal GameInstance launch ID
against the active `StretchContent` encounter. Never restore the removed
pending-encounter wrapper or subclass `TrainerBehavior` for this feature.

The Routes tab always lists all 40 destinations. Route 0 starts available; a
later route is locked until its immediately preceding route appears in the
contiguous `completed_routes` array. Completion is not awarded by the last
battle. The player must physically reach the far-end `RouteCompletionGate`,
and generated routes keep that gate sealed until every active trainer encounter
has been won. Completing the gate persists the route and unlocks exactly the
next one; Route 39 reports the all-routes clear. Save validation rejects gaps,
duplicates, and out-of-range route IDs.

Winning a Route 1 battle pays `$80`; the quadratic route curve preserves the
former `$4,000` Route 8 payout and reaches `$94,610` per Route 39 trainer. Gym
wins pay `$200–$6,000`; Elite Four and Champion wins pay `$8,000–$12,000`. A
non-forfeit tie pays 25% and a loss pays 10%, so every completed battle can
still award money. A forfeit pays zero. Battles outside a Stretchman destination
use the `$20` beginner fallback on a win (`$5` tie, `$2` loss), so the shared
money balance is not limited to R&D opponents.

## Persistence, export, and regression checks

ProgressionAutosave schema 5 stores the complete StretchGoalSystem payload,
including the contiguous `completed_routes` list and active run state.
The persistent Bag UI can reduce owned stacks through `discard_item()`, which
emits the same inventory and progression signals and needs no additional save
field. Researcher Lumen's `new-bouffalant-lumen-exp-share` claim is stored in
the payload's `claimed_gifts` array, so revisiting town or spending the held
item cannot duplicate the gift.
The selected-resource Web export explicitly includes the authored Route 0
wrapper/runtime, completion gate, dynamic destination, battle scenes, catalogs,
UI, NPC, and loot reel through
`tools/battle_sprite_pipeline/update_export_preset.cjs`.

```bash
python3 rnd/stretch/tools/generate_stretch_catalogs.py --check
godot --headless --path . --scene res://rnd/tests/stretch_goal_system_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretchman_hub_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/progression_autosave_smoke_test.tscn
```

The regressions enforce 40 catalog entries, 20 biome families, four routes per
level band, contiguous save validation, physical end-gate unlocking, winding
path metadata, continuous walls, real grass, four-to-eight trainer scaling,
and the full Route 39 dungeon. They also verify that every generated opponent
uses `core/PFRCharacter.gd` and `core/TrainerBehavior.gd`, with no R&D trainer
subclass; poison one instance of every trainer template to verify scene-local
state; check Highly Aggro sight again after scene re-entry; and dispatch a gym
leader through the E-key HUD path. Keep new implementation and tuning under
`rnd/stretch/` and limit outside changes to thin project, scene, save, export,
test, and context wiring.
