# New Bouffalant City Environment Assets

The runtime environment pack lives at [`../art/environments/new_bouffalant_city/`](../art/environments/new_bouffalant_city/). Its local [`README.md`](../art/environments/new_bouffalant_city/README.md) is the usage guide.

## Asset Families

- `ground_tile/` is the canonical 2 × 2 m city-cobble family. Use `ground_tile_mesh_library.tres` for the 2 × 2 m GridMap workflow. Direct scene wrappers exist under `ground_tile/scenes/`.
- `route_tile/` is a six-piece 4 × 4 m meadow/dirt family. Place these as snapped scene instances rather than adding them to the 2 × 2 m GridMap library. Each scene has a centered surface pivot and a 4 × 0.25 × 4 m static collision slab.
- `reference_city_pack/models/` contains 147 grounded GLBs and 1,831 companion PNGs produced by Godot's Extract Textures import mode. The original image payloads are embedded in the GLBs, but the complete imported directory is the transferable unit.
- `reference_city_pack/catalog.json` indexes 158 assets: the 147 GLBs, six route tiles, and five canonical cobble wrappers.
- `reference_city_pack/showcase/building_ground_metric_showcase.tscn` is the complete true-meter browser and scale-reference scene.

## Placement And Classification

Keep runtime instances at unit scale. Normal placement uses 0.5 m translation snapping and 90° rotations. Ground pivots are centered on the walkable surface at local `Y = 0`, with their 0.25 m slabs below the surface.

Catalog entries under `Complete Environment Sections` are large source-authored assemblies, not modular tiles. Only `Modular Ground` entries follow the strict 2/4/8 m ground system. Imported GLBs do not provide production gameplay collision; add collision, navigation, occlusion, and interaction boundaries per usage.

## Storage And Provenance

Keep the extracted model PNGs and their `.import` metadata beside the GLBs. Godot materializes those files from the embedded image payloads and the imported scenes reference them. Do not create another duplicate source-texture archive inside the runtime pack. Four additional shared textures under `route_tile/textures/` serve the authored 4 × 4 m route scenes.

The reference-city GLBs are derived from Pokémon Z-A field assets. The catalog retains per-asset provenance. Treat them as prototype/reference content unless the project's rights and production replacement plan establish otherwise; they do not supersede [`art-direction.md`](art-direction.md) or [`overworld-art-framework.md`](overworld-art-framework.md).

## Verification

After changing paths or contents, refresh imports and run:

```sh
godot --headless --path . --import
godot --headless --path . --scene res://art/environments/new_bouffalant_city/reference_city_pack/validation/metric_environment_pack_smoke_test.tscn
```

The test checks catalog completeness, path existence, category membership, unique IDs, true-meter scale, 0.5 m placement snapping, and modular-ground dimensions and collision slabs.
