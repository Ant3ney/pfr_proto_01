# Stretchman R&D Goal Hub

Read this document when changing Stretchman, his economy and catalogs, loot
boxes, battle payouts, generated destinations, or their trainer integration.
This entire feature is deliberately isolated under `rnd/stretch/` except for
the autoload, Pokemon Center instance, save, and export integration points.

## Runtime ownership and Pokemon Center entry

`StretchGoalSystem` is an autoload after `BattleSystem`. It owns the `$500`
starting balance, purchased-item quantities, shop transactions, badges,
Champion completion, active generated destination, defeated encounter IDs, and
battle payouts. `StretchmanBehavior` owns the interaction movement lock and
instances `StretchGoalUI` under `UIManager`. The Pokemon Center scene instances
`stretchman.tscn` and provides `StretchmanReturnSpawn` for destination returns.

`StretchGoalUI` has Items, Pokemon, Loot Boxes, Gyms, Champion, and Routes
tabs. Item and Pokemon tabs expose keyboard/gamepad-focusable filters. Search
updates as text changes, normalizes accents and punctuation, tokenizes fields,
and accepts bounded edit distance so one- and two-character spelling errors can
still match. Do not replace it with a network search service.

## Catalogs, prices, and Pokemon presentation

`rnd/stretch/data/items.json` contains all 2,223 records from the same pinned
PokeAPI api-data commit as the creature snapshot. `pokemon.json` contains all
1,025 default Pokemon. Regenerate both with
`rnd/stretch/tools/generate_stretch_catalogs.py --item-source <pinned-checkout>`;
plain `--check` validates the committed catalogs, while combining `--check`
with the pinned source verifies byte-for-byte output. The generator—not UI
code—is the pricing authority.

Basic items fit the low-cash economy (`Potion` and `Poke Ball` are `$20`),
while scarce collector items retain premiums. Ordinary LC Pokemon such as
Caterpie, Rattata, and Magikarp cost `$200`. Competitive tier, capture rarity,
starter status, and the generator's explicit `ICONIC_PRICE_FLOORS` list raise
other prices. Legendary and mythical floors remain deliberately extreme at
`$2.25B` and `$3B`.

Pokemon list icons call the existing `BattleSpriteCatalog.load_front_thumbnail`
and lazily load only visible rows. A selected Pokemon uses that catalog's full
front `SpriteFrames` atlas and original decoded GIF frame durations in the
detail preview. Exact IDs come from `BattleSpeciesMapping`; unsupported art
uses the existing neutral placeholder. Do not add a second GIF decoder or a
parallel Pokemon-sprite catalog for this menu.

## Loot boxes

There are six increasingly expensive tiers from `$100` to `$1,000,000`. Every
tier uses the identical `LOOT_BOX_HIGH_QUALITY_CHANCE` of `0.10`. A failed high
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

`StretchContent` supplies eight gym rosters, eight four-trainer outdoor routes,
and an ordered Champion corridor with Elite Four teams at levels 62–78 and a
Champion team at levels 80–85. `StretchDestination` builds the selected R&D
shell, a valid `NavigationRegion3D`, and opponents in the player's forward path.
Two static gate segments on the approach side of every opponent leave a `0.9 m`
center gap; the player capsule must cross the existing trainer ray before it can
pass the opponent. This level geometry makes challenges unavoidable without
broadening trainer detection.

Generated opponents do not have an R&D trainer script, controller, behavior,
or battle-launch override. The destination instances the existing authored
trainer scenes from `overworld/trainer_lake/`, retains their `NPCController` and
the exact `core/TrainerBehavior.gd`, and configures dialog, sight distance,
normal `0.15 m` stopping distance, battle scene path, stable encounter ID, and
the shared behavior's `HIGHLY_AGGRO` mode. Authored trainer controller resources
are scene-local, so an opponent completed earlier in a long play session cannot
poison a later generated instance. Highly Aggro ignores standard trainers'
session-level sight consumption; the immediate return remains suppressed to
avoid a battle loop, while starting a fresh destination run restores forced sight.
The generic R&D battle provider resolves that normal GameInstance launch ID
against the active `StretchContent` encounter. Never restore the removed
pending-encounter wrapper or subclass `TrainerBehavior` for this feature.

Winning a Route 1 battle pays `$20`; route payouts rise by authored route table
to `$4,000` for every Route 8 trainer. Gym wins pay `$200–$6,000`; Elite Four
and Champion wins pay `$8,000–$12,000`. A non-forfeit tie pays 25% and a loss
pays 10%, so every completed battle can still award money. A forfeit pays zero.
Battles outside a Stretchman destination use the `$20` beginner fallback on a
win (`$5` tie, `$2` loss), so the shared money balance is not limited to R&D
opponents.

## Persistence, export, and regression checks

ProgressionAutosave schema 3 stores the complete StretchGoalSystem payload.
The persistent Bag UI can reduce owned stacks through `discard_item()`, which
emits the same inventory and progression signals and needs no additional save
field.
The selected-resource Web export explicitly includes the dynamic destination,
battle scene, catalogs, UI, NPC, and loot reel through
`tools/battle_sprite_pipeline/update_export_preset.cjs`.

```bash
python3 rnd/stretch/tools/generate_stretch_catalogs.py --check
godot --headless --path . --scene res://rnd/tests/stretch_goal_system_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretchman_hub_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/stretch_destination_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/progression_autosave_smoke_test.tscn
```

The destination regression explicitly verifies that every generated opponent
uses `core/PFRCharacter.gd` and `core/TrainerBehavior.gd`, with no R&D trainer
subclass. It also poisons one instance of every trainer template to verify
scene-local state, checks Highly Aggro sight again after scene re-entry, and
dispatches a gym leader through the E-key HUD path. Keep new implementation and
tuning under
`rnd/stretch/` and limit outside changes to thin project, scene, save, export,
test, and context wiring.
