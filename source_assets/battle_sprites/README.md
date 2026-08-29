# Battle Sprite GIF Sources

This directory is a Git-tracked, Godot-ignored provenance copy of the animated
sprite corpus supplied in the sibling project. The offline pipeline copied the
files; it did not download or replace any sprite.

The accepted corpus contains:

- `pokemon_showdown/ani/`: 1,054 opponent/front GIFs.
- `pokemon_showdown/ani-back/`: 1,052 player/back GIFs.
- `pokemon_showdown/sync-manifest.json`: the supplied project's original sync
  record (2,106 downloads, 744 missing results, zero failures).
- `pokemon_showdown/sha256-manifest.json`: deterministic SHA-256, byte-size,
  and file-path provenance for every copied GIF plus the original manifest.

The manifest records `https://play.pokemonshowdown.com/sprites` as the upstream
asset root used by the supplied project's sync. The related
[Smogon / Pokémon Showdown sprite repository](https://github.com/smogon/sprites#license)
states that its code license does not grant an artwork license: Pokémon sprites
are identified there as property of Nintendo / Game Freak / The Pokémon Company,
and the status of community-created later-generation sprites is still being
determined. This project therefore records provenance and the user's stated
authorization to copy and ship the supplied corpus; it does not assert a new or
upstream artwork license.

Godot's stable image-import list includes PNG and other raster formats but not
GIF, so runtime atlases are generated as PNG files. See
[Godot's image import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html).

Do not hand-edit these GIFs or silently substitute a different form. Run the
local sync command documented in
[`tools/battle_sprite_pipeline/README.md`](../../tools/battle_sprite_pipeline/README.md)
when an authorized replacement corpus is supplied.
