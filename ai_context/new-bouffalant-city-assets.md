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

### Vulkan-safe targeted mesh imports

`runtime_contract.gd` classifies complete environment sections, assets with at least 25,000 triangles, and assets with a runtime horizontal extent of at least 60 m as performance-sensitive. There are currently 44; this classification is advisory and does not block placement or play.

Museum (`t1_b_museum`) and Gate Building (`t1_b_gate_building`) previously reproduced a Linux Intel `i915` GPU hang and context reset under Vulkan/Forward+, followed by Godot aborting after device loss. This was not a GDScript exception, physics crash, corrupt source GLB, general polygon-count limit, or texture/material failure: source positions, normals, UVs, tangents, base indices, generated LOD indices, and textures validated; flat materials did not eliminate the reset; and larger City Hall, Rouge Tower, and Miare Station controls rendered normally.

The asset-level solution is to keep the original imported mesh buffers for Gate Building, Museum, and Tenant Building (`t1_b_tenant_building`). For only these three IDs, `meshes/generate_lods=false` and `meshes/create_shadow_meshes=false`. Removing both optional Godot-generated buffer types avoids the Intel Vulkan driver path that hung while retaining the source geometry, original per-surface textured materials, baked `0.75` scale, generated gameplay collision, and normal shadow casting through the original mesh. Gate and Museum were the reproduced failures; Tenant uses the same targeted profile preventively, not because a Tenant-only hang was independently confirmed.

[`../art/environments/new_bouffalant_city/reference_city_pack/runtime_contract.gd`](../art/environments/new_bouffalant_city/reference_city_pack/runtime_contract.gd) owns the three-ID `VULKAN_SAFE_MESH_IMPORT_IDS` set. [`../art/environments/new_bouffalant_city/reference_city_pack/collision/apply_model_import_settings.gd`](../art/environments/new_bouffalant_city/reference_city_pack/collision/apply_model_import_settings.gd) enforces both settings as `false` for that set and `true` for every other GLB. Keep the exception centralized there; do not hand-edit an imported cache, globally disable the optimizations, flatten these assets' materials, or restore the old Compatibility-restart/placement guard. The palette now permits ordinary double-click placement and ordinary play on Forward+.

After the targeted reimport, an animated directional-shadow stress scene containing all three affected imports plus the three controls completed 600 frames on Intel ADL GT2 Vulkan/Forward+. The real [`../demo/modular_ground_scene.tscn`](../demo/modular_ground_scene.tscn) also completed 600 iterations on the same Intel Forward+ path. These successful runs are the current regression baseline. The two importer options were disabled together, so documentation must not claim that either LOD generation or shadow-mesh generation was individually isolated as the sole trigger.

## Placement And Classification

Keep runtime instances at unit scale. The 147 GLB imports bake the source geometry to `0.75`, calibrated against the 1.67 m player; do not also scale their scene instances. The catalog preserves source-space GLB bounds and declares `runtime_import_scale`, while the palette and showcase present the resulting runtime bounds. The 11 authored ground scenes are not reduced and retain their exact dimensions. Normal placement uses 0.5 m translation snapping and 90° rotations. Ground pivots are centered on the walkable surface at local `Y = 0`, with their 0.25 m slabs below the surface.

Catalog entries under `Complete Environment Sections` are large source-authored assemblies, not modular tiles. Only `Modular Ground` entries follow the strict 2/4/8 m ground system.

Imported GLBs generate layer-1 static collision at import time, after the baked scale is applied. Hard-surface assets use double-sided concave mesh shapes; shrubs and hedges use boxes; trees, bamboo, and stumps use central cylinders. Grass, flowers, loose soil, the fissure decal, and water-only entries intentionally have no collision. The 11 modular ground scenes retain authored slabs. This collision is for static prototype environment use and does not replace per-level navigation, occlusion, or interaction authoring. When adding models, changing profiles, or regenerating `.glb.import` files, run `collision/apply_model_import_settings.gd`, then refresh imports. This step also preserves the three Vulkan-safe mesh exceptions.

## Storage And Provenance

Keep the extracted model PNGs and their `.import` metadata beside the GLBs. Godot materializes those files from the embedded image payloads and the imported scenes reference them. Do not create another duplicate source-texture archive inside the runtime pack. Four additional shared textures under `route_tile/textures/` serve the authored 4 × 4 m route scenes.

The reference-city GLBs are derived from Pokémon Z-A field assets. The catalog retains per-asset provenance. Treat them as prototype/reference content unless the project's rights and production replacement plan establish otherwise; they do not supersede [`art-direction.md`](art-direction.md) or [`overworld-art-framework.md`](overworld-art-framework.md).

## Verification

After changing paths or contents, refresh imports and run:

```sh
godot --headless --rendering-method gl_compatibility --path . --script res://art/environments/new_bouffalant_city/reference_city_pack/collision/apply_model_import_settings.gd
godot --headless --path . --import
godot --headless --path . --editor --quit
godot --headless --path . --script res://addons/new_bouffalant_city_asset_palette/validation/asset_palette_activation_smoke_test.gd
godot --headless --path . --scene res://art/environments/new_bouffalant_city/reference_city_pack/validation/metric_environment_pack_smoke_test.tscn
```

On a steady-state rerun, the import-settings tool should report `0 updated, 147 already configured`; it may report up to three updates when a refresh has reset the targeted settings. The palette activation test verifies that Gate Building, Museum, and Tenant Building double-click directly into normal viewport placement even when the dock is initialized as Intel Forward+. The environment test checks catalog and thumbnail completeness, category membership, unique IDs, the 44-entry advisory performance classification, all three targeted `.glb.import` settings, absence of generated LOD and optimized shadow buffers in the loaded meshes, retained textured materials, unit node transforms, baked `0.75` GLB bounds, configured collisions, representative live physics queries, and modular-ground dimensions and slabs. The editor startup check parses and initializes the placement plugin.

For a renderer-level regression check, run the real modular ground scene for a bounded frame count on the intended Vulkan device and inspect the kernel log for a new `i915` hang or context reset. GPU indices are workstation-specific; verify the selected adapter instead of assuming an index. Do not run a potentially hanging Vulkan regression while another editor has unsaved work.
