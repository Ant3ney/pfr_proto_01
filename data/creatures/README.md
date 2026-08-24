# Local Creature Data

This generated directory contains the local, losslessly compressed PokeAPI
`pokemon`, Pokemon encounter, `pokemon-species`, and `evolution-chain` JSON
records consumed by `CreatureSystem`. Do not hand-edit generated records.

From the repository root:

```sh
python3 tools/sync_pokeapi_data.py
python3 tools/sync_pokeapi_data.py --verify
```

The source revision, record counts, and content digest are recorded in
`manifest.json`. PokeAPI's license is preserved in `POKEAPI_LICENSE.txt`.
Sprites and cries are represented by the original URL fields; binary media is
not part of this stat-data snapshot.
