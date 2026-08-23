# New Bouffalant City Environment Pack

This directory is the runtime-ready environment asset root for New Bouffalant City. Assets use the project scale of one Godot unit per meter and should normally be instanced at `Vector3(1, 1, 1)`.

## Contents

- `ground_tile/` contains the canonical 2 × 2 m city-cobble MeshLibrary, its shared meshes/materials/textures, and five directly placeable scene wrappers used by the transferred atlas. The MeshLibrary also contains the project's additional cobble end tile.
- `route_tile/` contains six exact 4 × 4 m meadow/dirt-path scenes, shared materials, four runtime textures, and full-slab static collision. Place these as snapped `Node3D` instances; do not put them in the 2 × 2 m GridMap library.
- `reference_city_pack/models/` contains 147 grounded, true-meter GLBs plus 1,831 companion PNGs materialized by Godot's Extract Textures import mode. The image payloads originate inside the GLBs, but after import the complete directory is the transferable unit.
- `reference_city_pack/catalog.json` is the authoritative 158-entry index. It records display names, categories, source provenance, dimensions, mesh statistics, material metadata, and current `res://` paths.
- `reference_city_pack/showcase/building_ground_metric_showcase.tscn` is the editor-visible asset browser. It includes all 147 GLBs and all 11 modular ground scenes, a 0.5 m grid, dimensions, and 1.67 m player references.
- `reference_city_pack/validation/` contains the automated catalog/scene integrity check.

## Placement Contract

- Keep imported asset scale at `1, 1, 1`.
- Use 0.5 m translation snapping and 90° rotation increments for normal environment placement.
- The 2 × 2 m and 4 × 4 m ground scenes use a centered pivot on the walkable surface at local `Y = 0`; their 0.25 m slab extends downward.
- `Modular Ground` and `Modular Architecture` entries are reusable pieces. `Complete Environment Sections` are large source-authored assemblies and must not be treated as GridMap modules.
- The ground and route scene wrappers include slab collision. The imported buildings, props, vegetation, bridges, and large sections are visual assets; author gameplay collision, navigation, occlusion, and interaction boundaries for the way each is used.

Open the metric browser in Godot and select an asset's `Model` child to inspect it. The catalog is the quickest way to search by category, source ID, dimensions, or kind.

## Validation

From the repository root, run:

```sh
godot --headless --path . --import
godot --headless --path . --scene res://art/environments/new_bouffalant_city/reference_city_pack/validation/metric_environment_pack_smoke_test.tscn
```

The smoke test verifies that every catalog path exists, all 158 IDs appear exactly once in the showcase, wrappers remain at scale one on the 0.5 m grid, and modular-ground dimensions and collision slabs follow the 2/4/8 m system.

## Provenance And Production Status

The reference-city models are derived from Pokémon Z-A field assets; per-asset archive and source paths remain in the catalog. They are useful for prototype composition and scale/reference work, but are not original New Bouffalant City designs. Confirm the project's rights and replacement plan before redistribution or release, and review any production use against the project's original-art direction and overworld budgets.
