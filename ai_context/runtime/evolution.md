# Pokemon Evolution Runtime Contract

Read this document when changing evolution thresholds, eligible targets,
captured-instance species changes, branching prompts, or evolution notices.
Verify the current local evolution-chain snapshot and focused tests before
changing the balance policy.

## Level-only evolution policy

`CreatureSystem.get_evolution_options(pokemon_id)` converts every direct edge
in the vendored PokeAPI evolution chains into one level requirement. It keeps
the smallest valid `min_level` authored for that target. A target without an
authored level inherits the smallest authored level among its sibling branches;
when the whole branch group lacks a level, the first evolution uses level 20
and the second uses level 36. This flattens item, trade, friendship, time,
location, move, stat, and other source-game rules into the current
level-only system.

Each returned option contains `pokemonId`, PokeAPI `name`, `requiredLevel`,
evolution depth `stage` (`1` or `2`, with the base species at `0`), and
`levelSource` (`pokeapi`, `branch`, or `stage-default`).
`get_available_evolutions(pokemon_id, level)`
returns only reached direct targets, and `can_evolve(...)` is the boolean
helper. The complete creature record also exposes its direct options under
`evolution_options`.

Only default-form Pokemon receive generic evolution options. PokeAPI chains
identify species rather than the exact alternate form, so automatically
mapping a regional, cosmetic, battle, Gigantamax, or Mega form through that
chain could silently replace it with the wrong default form. Such forms need an
explicit future mapping before they can evolve.

## Captured-instance mutation

`CollectionSystem.get_evolution_options(pcl_id)` derives eligibility from the
PCL's current species and level. No pending or missed-evolution flag is saved,
so a Pokemon acquired above its threshold immediately has the same action as
one that just leveled.

`evolve_pokemon(pcl_id, target_pokemon_id)` accepts only an eligible direct
target. It preserves the PCL ID, party slot, normalized health, level, and
within-level XP progress while remapping cumulative XP to the target growth
curve. It updates the Pokemon ID and battle species/sprite, retains equipped
moves when both forms support battle, emits one `collection_changed`, and then
emits `pokemon_evolved`. Unsupported target forms remain collectible but lose
the optional battle profile under the existing battle-preflight policy.

The ordinary collection payload already persists the evolved Pokemon ID and
reconciled stats/profile, so evolution requires no autosave schema field or
migration.

## Player and battle presentation

The Party & PC detail view lists every direct target and its level. Once at
least one target is eligible, it displays an `Evolve` action. One target opens
a confirmation; multiple eligible targets open the blocking evolution prompt
with an `OptionButton`, so keyboard, gamepad, and pointer users explicitly
choose the result. Evolving one stage can immediately expose the next direct
stage when a high-level PCL already meets it.

Battle XP writeback includes copied `evolutionAvailable` and
`evolutionOptions` metadata in its local award result. A level-up event tells
the player when the Pokemon can now evolve from the Pokemon menu. Evolution is
not applied inside an in-flight server battle, so the accepted battle snapshot
remains authoritative until that session ends.

## Regression checks

```bash
godot --headless --path . --scene res://tests/integration/creature_system_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/collection_system_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/battle_system_session_test.tscn
godot --headless --path . --scene res://tests/scenes/player_menu_hud_smoke_test.tscn
```

This document covers the implemented level-only runtime. Future items,
trading, cancellation history, form-specific routes, move learning, and an
evolution animation belong to later, explicitly designed extensions.
