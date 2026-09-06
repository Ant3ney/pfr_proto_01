# Pokemon Center Interior Source

This directory contains the deterministic Blender authoring source for the playable Pokemon Center interior environment.

## Files

- `create_pokemon_center_interior.py` builds the complete low-poly environment, writes its compact palette, maps the classical brick texture, saves an editable Blender file, exports the runtime GLB, and renders a preview.
- `pokemon_center_interior.blend` is the generated editable source scene.
- `pokemon_center_interior_palette.png` is the generated 128 x 16 source palette.
- `pokemon_center_classic_brick_source.png` is the preserved 1,254 x 1,254 generated texture source.
- `pokemon_center_classic_brick.png` is the stripped 512 x 512 runtime-authoring texture embedded in the GLB.
- `pokemon_center_interior_preview.png` is the generated authoring preview.

The playable Godot composition, lighting, collision, player, camera, and gameplay markers live separately in [`pokemon_center_interior.tscn`](../../game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_interior.tscn).

The generated reception counter is intentionally authored at Blender `Y = 2.75 m`
(Godot `Z = -2.75 m`). This leaves the service aisle used by the staffed healer;
keep the scene's simplified counter collision and `NurseSpawn` aligned when the
counter depth or position changes.

## Regeneration

Run from the repository root with Blender 5.2 LTS or a compatible release:

```sh
blender --background --factory-startup --python source_assets/pokemon_center_interior/create_pokemon_center_interior.py
godot --headless --path . --import
```

The builder writes directly to `art/environments/new_bouffalant_city/pokemon_center_interior/pokemon_center_interior_environment.glb`. Keep that GLB at unit scale and preserve its Godot import settings: no tangents, animation, generated LODs, optimized shadow mesh, or generated collision. After regeneration, run the focused interior smoke test documented in the runtime README.

## Brick Texture Provenance

The original brick material was created with OpenAI's built-in image generation, then given a targeted seam-continuity edit. The final edit request was:

> Modify only the outer-edge continuity so the warm terracotta brick courses, pale mortar, palette, scale, painterly wear, and restrained cream limewash/grime connect when repeated horizontally and vertically. Preserve flat material-reference lighting; add no focal object, text, logo, border, perspective, or lighting gradient.

The unmodified final generator output remains in `pokemon_center_classic_brick_source.png`; the deterministic Blender build consumes only its compact 512 px derivative. The texture intentionally keeps grime broad and restrained so the classical room feels inhabited rather than ruined.
