# Pokemon Center Service Annex Source

This directory contains the deterministic Blender authoring source for the distinct east-door Pokemon Center service annex.

## Files

- `create_pokemon_center_annex.py` builds the low-poly annex, saves its editable Blender source, exports the runtime GLB, and renders the preview.
- `pokemon_center_annex.blend` is the generated editable source scene.
- `pokemon_center_annex_preview.png` is the generated authoring preview.

The builder imports the shared mesh/material helpers from `source_assets/pokemon_center_interior/create_pokemon_center_interior.py` and embeds the same `pokemon_center_interior_palette.png` and `pokemon_center_classic_brick.png`. Do not create another source copy of those textures.

The playable Godot composition, lighting, collision, player, camera, markers, and exit trigger live in [`../../art/environments/new_bouffalant_city/pokemon_center_annex/pokemon_center_annex.tscn`](../../art/environments/new_bouffalant_city/pokemon_center_annex/pokemon_center_annex.tscn).

## Regeneration

Run from the repository root with Blender 5.2 LTS or a compatible release:

```sh
blender --background --factory-startup --python source_assets/pokemon_center_annex/create_pokemon_center_annex.py
godot --headless --path . --import
```

Keep the exported GLB at unit scale and preserve its Godot import settings: no tangents, animation, generated LODs, optimized shadow mesh, or generated collision. After regeneration, run the focused annex and two-opening transfer tests documented in the runtime README.
