# Local Creature Data

This generated directory contains the local, losslessly compressed PokeAPI
`pokemon`, Pokemon encounter, `pokemon-species`, and `evolution-chain` JSON
records consumed by `CreatureSystem`. Do not hand-edit generated records.

At runtime, `CreatureSystem` derives one project level from every direct
default-form evolution edge. Existing PokeAPI minimum levels win; missing
targets inherit an authored sibling level when available, then fall back to
level 20 for the first evolution or level 36 for the second. This deliberately
reduces all current evolution requirements to levels without altering the
vendored source records.

`experience.json` is a separate compact generated artifact. It stores the six
PokeAPI growth curves as a level-indexed two-dimensional table and one packed
row per local Pokemon ID. Each row selects a growth curve and records a reward
multiplier derived from the pinned Pokemon Showdown community singles tier,
with National Dex tier and documented base-stat bands as fallbacks.
The generated document records its [PokeAPI growth-rate](https://pokeapi.co/docs/v2#growth-rates)
and [Pokemon Showdown tier-data](https://github.com/smogon/pokemon-showdown/blob/master/data/formats-data.ts)
sources plus input hashes.

The separate R&D artifact
[`level_up_learnsets.json`](../../rnd/move_learning/data/level_up_learnsets.json)
is derived from the level-up details in these same compressed Pokemon records.
Its generator selects an explicit version group, validates moves against the
pinned battle mapping, and records source hashes; do not hand-edit it.

From the repository root:

```sh
python3 tools/sync_pokeapi_data.py
python3 tools/sync_pokeapi_data.py --verify
node tools/generate_creature_experience_data.mjs
node tools/generate_creature_experience_data.mjs --check
node rnd/move_learning/tools/generate_move_learnsets.mjs
node rnd/move_learning/tools/generate_move_learnsets.mjs --check
```

The source revision, record counts, and content digest are recorded in
`manifest.json`. PokeAPI's license is preserved in `POKEAPI_LICENSE.txt`.
Sprites and cries are represented by the original URL fields; binary media is
not part of this stat-data snapshot.
