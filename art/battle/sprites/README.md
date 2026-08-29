# Runtime Battle Sprites

`generated/` is the complete tracked PNG-atlas catalog generated from the
verified raw GIF corpus. Every animation has one PNG atlas and one JSON timing,
region, alpha-bound, and provenance manifest. `generated/catalog.json` is a
metadata-only index; it does not preload textures.

`BattleSpriteCatalog.gd` loads only the current opponent `ani` atlas and current
player `ani-back` atlas with Godot's cache bypassed. Replacing or clearing a
side drops this catalog's prior texture references. `BattleSpritePresenter.gd`
builds `AtlasTexture` frames lazily, grounds each frame from its alpha bottom,
normalizes visible height, and keeps attack, hit, heal, switch, and faint motion
on a separate transform root.

Lookups are exact. Missing forms, the 21 absent base species, and shiny requests
use `placeholder.svg` unless battle data supplies an explicit approved
`res://` PNG, WebP, or SVG override. A different form is never substituted.

Regenerate and verify through
[`tools/battle_sprite_pipeline/`](../../../tools/battle_sprite_pipeline/README.md).
Do not edit generated PNGs or manifests by hand.
