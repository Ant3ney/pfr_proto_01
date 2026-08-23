# New Bouffalant City Environment Assets

The runtime environment pack lives at [`../art/environments/new_bouffalant_city/`](../art/environments/new_bouffalant_city/). Its local [`README.md`](../art/environments/new_bouffalant_city/README.md) is the usage guide.

## Asset Families

- `ground_tile/` is the canonical 2 × 2 m city-cobble family. Use `ground_tile_mesh_library.tres` for the 2 × 2 m GridMap workflow. Direct scene wrappers exist under `ground_tile/scenes/`.
- `route_tile/` is a six-piece 4 × 4 m meadow/dirt family. Place these as snapped scene instances rather than adding them to the 2 × 2 m GridMap library. Each scene has a centered surface pivot and a 4 × 0.25 × 4 m static collision slab.
- `reference_city_pack/models/` contains 147 grounded GLBs and 1,831 companion PNGs produced by Godot's Extract Textures import mode. The original image payloads are embedded in the GLBs, but the complete imported directory, including `.glb.import` scale and collision configuration, is the transferable unit.
- `reference_city_pack/collision/` owns the selective collision profiles, `EditorScenePostImport` generator, and model-import settings tool used by every imported GLB.
- `reference_city_pack/catalog.json` indexes 158 assets: the 147 GLBs, six route tiles, and five canonical cobble wrappers.
- `reference_city_pack/showcase/building_ground_metric_showcase.tscn` is the complete player-calibrated browser and scale-reference scene.

## Editor Placement Workflow

The enabled editor plugin at [`../addons/new_bouffalant_city_asset_palette/`](../addons/new_bouffalant_city_asset_palette/) reads `catalog.json` and exposes all entries as bundled thumbnail cards through the **Bouffalant Assets** dock. It places undoable `PackedScene` instances under a `NewBouffalantCityAssets` child of the edited scene. Placement supports search/category filtering, 0.5/2/4 m XZ snap, 90-degree rotation, upward-facing collision surfaces, and a fallback Y plane. The plugin's [`README.md`](../addons/new_bouffalant_city_asset_palette/README.md) is the operator guide and records the thumbnail regeneration command.

This dock complements rather than replaces `ModularGroundGrid`: use the GridMap MeshLibrary to paint strict 2 × 2 m cobble cells, and use the dock for 4 × 4 m route scenes and irregular or unique assets. Do not make one GridMap library from the full catalog.

### Renderer compatibility and scoped guard

`runtime_contract.gd` classifies complete environment sections, assets with at least 25,000 triangles, and assets with a runtime horizontal extent of at least 60 m as performance-sensitive. There are currently 44; this classification is advisory and does not block them. Repeated losses were verified as Linux Intel `i915` Vulkan hangs followed by Godot `SIGABRT`, not GDScript, physics, corrupt GLB data, or general asset size. A launcher outside the project forced Intel Vulkan/Forward+ even though `project.godot` declares GL Compatibility.

Museum (`t1_b_museum`) and Gate Building (`t1_b_gate_building`) are the two confirmed workload triggers. Their source mesh data, generated tangents, base indices, and LOD indices validate, and larger control assets remain valid. An isolated five-asset render completed 600 animated, shadowed frames on Intel OpenGL Compatibility and 600 on NVIDIA Vulkan. The palette therefore blocks only these two entries, a scene containing one, and the all-assets metric browser while Intel Vulkan is active. Other high-load entries remain available.

Close existing project editors before changing renderer. `addons/new_bouffalant_city_asset_palette/open_editor_compatibility.sh` forces the project's validated Intel OpenGL Compatibility path; `open_editor_nvidia.sh` selects the validated NVIDIA Vulkan device. Do not run multiple graphical editor instances against the same project cache.

## Placement And Classification

Keep runtime instances at unit scale. The 147 GLB imports bake the source geometry to `0.75`, calibrated against the 1.67 m player; do not also scale their scene instances. The catalog preserves source-space GLB bounds and declares `runtime_import_scale`, while the palette and showcase present the resulting runtime bounds. The 11 authored ground scenes are not reduced and retain their exact dimensions. Normal placement uses 0.5 m translation snapping and 90° rotations. Ground pivots are centered on the walkable surface at local `Y = 0`, with their 0.25 m slabs below the surface.

Catalog entries under `Complete Environment Sections` are large source-authored assemblies, not modular tiles. Only `Modular Ground` entries follow the strict 2/4/8 m ground system.

Imported GLBs generate layer-1 static collision at import time, after the baked scale is applied. Hard-surface assets use double-sided concave mesh shapes; shrubs and hedges use boxes; trees, bamboo, and stumps use central cylinders. Grass, flowers, loose soil, the fissure decal, and water-only entries intentionally have no collision. The 11 modular ground scenes retain authored slabs. This collision is for static prototype environment use and does not replace per-level navigation, occlusion, or interaction authoring. When adding models or changing profiles, run `collision/apply_model_import_settings.gd`, then refresh imports.

## Storage And Provenance

Keep the extracted model PNGs and their `.import` metadata beside the GLBs. Godot materializes those files from the embedded image payloads and the imported scenes reference them. Do not create another duplicate source-texture archive inside the runtime pack. Four additional shared textures under `route_tile/textures/` serve the authored 4 × 4 m route scenes.

The reference-city GLBs are derived from Pokémon Z-A field assets. The catalog retains per-asset provenance. Treat them as prototype/reference content unless the project's rights and production replacement plan establish otherwise; they do not supersede [`art-direction.md`](art-direction.md) or [`overworld-art-framework.md`](overworld-art-framework.md).

## Verification

After changing paths or contents, refresh imports and run:

```sh
godot --headless --path . --import
godot --headless --path . --editor --quit
godot --headless --path . --scene res://art/environments/new_bouffalant_city/reference_city_pack/validation/metric_environment_pack_smoke_test.tscn
```

The editor startup check parses and initializes the placement plugin. The environment test checks catalog and thumbnail completeness, category membership, unique IDs, the 44-entry performance-sensitive classification, the two-entry Intel Vulkan trigger scope and three known controls, unit node transforms, baked `0.75` GLB bounds, 0.5 m placement snapping, configured GLB collision imports, every collision profile and shape, representative live physics queries, and modular-ground dimensions and slabs.
