# New Bouffalant City Environment Pack

This directory is the runtime-ready environment asset root for New Bouffalant City. One Godot unit remains one meter, and every asset should normally be instanced at `Vector3(1, 1, 1)`. The 147 transferred GLBs bake a `0.75` source-to-runtime calibration into their imports so they fit the 1.67 m player without per-instance scaling; the 11 authored ground modules retain their exact project dimensions.

## Contents

- `ground_tile/` contains the canonical 2 × 2 m city-cobble MeshLibrary, its shared meshes/materials/textures, and five directly placeable scene wrappers used by the transferred atlas. The MeshLibrary also contains the project's additional cobble end tile.
- `route_tile/` contains six exact 4 × 4 m meadow/dirt-path scenes, shared materials, four runtime textures, and full-slab static collision. Place these as snapped `Node3D` instances; do not put them in the 2 × 2 m GridMap library.
- `reference_city_pack/models/` contains 147 grounded GLBs plus 1,831 companion PNGs materialized by Godot's Extract Textures import mode. Their `.glb.import` files bake the `0.75` calibration and run the pack's collision post-import script, so the complete directory and its import metadata are the transferable unit.
- `reference_city_pack/collision/` contains the collision profiles, the GLB post-import generator, and the maintenance command that enforces scale and collision settings on every model import.
- `reference_city_pack/catalog.json` is the authoritative 158-entry index. It records display names, categories, source provenance, source dimensions for GLBs, runtime dimensions for authored scenes, mesh statistics, material metadata, and current `res://` paths.
- `reference_city_pack/showcase/building_ground_metric_showcase.tscn` is the editor-visible asset browser. It includes all 147 GLBs and all 11 modular ground scenes, a 0.5 m grid, dimensions, and 1.67 m player references.
- `reference_city_pack/validation/` contains the automated catalog/scene integrity check.
- `pokemon_center_roof/` contains the fitted, mobile-safe tiered roof, two street-facing automatic door sets, and a unit-scale wrapper around the unchanged reference Pokemon Center. Use its wrapper instead of editing or rescaling the source GLB.
- `pokemon_center_interior/` contains the playable five-sided Pokemon Center level, its two-draw classical brick-and-limestone environment, simplified authored collision, bright restrained lighting, player/camera/UI composition, and gameplay markers.
- `pokemon_center_annex/` contains the distinct east-storefront service interior, including its apothecary cabinet, consultation area, two-draw mobile environment, authored collision, and dedicated east return marker contract.
- `city_interiors/` retains eight lightweight classical scenes for City Hall, Rouge Tower, Miare Station, the garage, Gate Building, both tenant buildings, and the museum. Rouge Tower and the garage are no longer live exterior destinations. Miare Station owns Stretchman; the Gate Building has one safe city entrance, clearly marked city/Route 0 exits, and a walk-through rear Route 0 door.

## Editor Placement Palette

The enabled [`New Bouffalant City Asset Palette`](../../../addons/new_bouffalant_city_asset_palette/README.md) exposes all 158 catalog entries as thumbnail cards in the **Bouffalant Assets** editor dock. It provides search, category filtering, 0.5/2/4 m XZ snapping, 90-degree rotation, upward-surface detection, an explicit fallback Y level, and undoable click-to-place scene instances.

1. Open the 3D scene you want to build. If necessary, reopen the dock through **Editor → Editor Docks → Bouffalant Assets**.
2. Select an asset, choose the snap and elevation settings, and enable **Place in 3D View**.
3. Left-click to place. Use `Q`/`E` to rotate and `Escape` or right-click to leave placement mode.

Placed instances are grouped under `NewBouffalantCityAssets` in the edited scene. Use **Add at Scene Origin** for very large assets. The dock also links directly to the `ModularGroundGrid` workspace and the full metric browser.

The dock identifies whole environment sections plus exceptionally wide or dense entries as high-load, but that label is advisory. Museum and Gate Building are the only confirmed triggers for the Intel Vulkan/Forward+ driver hang on this workstation, so only those two entries and the metric browser are intercepted on that renderer. Their GLBs validate and render correctly on both supported paths. Double-clicking either asset offers to save and restart in Intel OpenGL Compatibility, then automatically resumes placement for that asset. The manual launchers remain `./addons/new_bouffalant_city_asset_palette/open_editor_compatibility.sh`, which matches `project.godot`, and `./addons/new_bouffalant_city_asset_palette/open_editor_nvidia.sh` for NVIDIA Vulkan.

Keep using `ModularGroundGrid` and its MeshLibrary palette for repeated 2 × 2 m city-cobble painting. The editor dock is the corresponding workflow for 4 × 4 m route scenes, buildings, props, vegetation, architecture, and large sections, which cannot safely share one GridMap cell contract.

## Placement Contract

- Keep every placed asset at `1, 1, 1`. Do not apply another `0.75` transform to a GLB instance; that factor is already baked into its imported geometry.
- Use 0.5 m translation snapping and 90° rotation increments for normal environment placement.
- The 2 × 2 m and 4 × 4 m ground scenes use a centered pivot on the walkable surface at local `Y = 0`; their 0.25 m slab extends downward.
- `Modular Ground` and `Modular Architecture` entries are reusable pieces. `Complete Environment Sections` are large source-authored assemblies and must not be treated as GridMap modules.
- All generated collision uses physics layer and mask 1, matching the player. Author navigation, occlusion, and interaction boundaries for the way each asset is used.

## Collision Contract

Collision is generated inside each imported GLB by `reference_city_pack/collision/city_asset_post_import.gd` after the baked scale is applied, so direct instances, palette placements, and the metric browser all use physics aligned to the visible geometry. The profiles are deliberately selective:

- Buildings, architectural modules, bridges, rocks, raised rubble, and complete environment sections use accurate, double-sided static triangle collision.
- Hedges, bushes, shrubs, and topiary use simple box volumes so individual leaf planes do not snag the player.
- Trees, bamboo, and the stump use central cylinder volumes; their canopies and branches remain pass-through.
- Grass, flower patches, the loose-soil patch, the fissure overlay, and water-only source sections remain pass-through by design and rely on supporting terrain where appropriate.
- The 11 modular ground scenes keep their authored 0.25 m slab collision.

These are static environment colliders, not collision for moving rigid bodies. They do not create a `NavigationMesh`; bake or update navigation after laying out a level. After adding GLBs or changing collision profiles, run:

```sh
godot --headless --path . --script res://tools/new_bouffalant_city_import/apply_model_import_settings.gd
godot --headless --path . --import
```

If the pack-wide calibration changes, also refresh the browser annotations with `godot --headless --path . --script res://tools/new_bouffalant_city_import/update_runtime_scale_annotations.gd`.

Open the metric browser in Godot and select an asset's `Model` child to inspect it. The catalog is the quickest way to search by category, source ID, dimensions, or kind.

## Validation

From the repository root, run:

```sh
godot --headless --path . --import
godot --headless --path . --editor --quit
godot --headless --path . --scene res://tests/scenes/assets/metric_environment_pack_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/assets/pokemon_center_roof_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/assets/pokemon_center_interior_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/assets/pokemon_center_annex_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/pokemon_center_scene_transfer_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/modular_city_scene_transfer_smoke_test.tscn
```

The editor startup check loads the placement plugin and its dock. The environment smoke test verifies all 158 catalog paths and thumbnails, showcase IDs, unit node transforms, the baked `0.75` GLB bounds, the 44-entry high-load classification, the two confirmed Intel Vulkan triggers and three known controls, 0.5 m placement, collision import settings, every collision profile and shape type, representative live physics hits, and the modular-ground 2/4/8 m contract. The focused Pokemon Center tests protect the exterior roof/door fit; both interiors' two-draw geometry, collision, gameplay markers, cameras, and restrained shadow-light setups; and real bidirectional travel from the south storefront to the main clinic and from the east storefront to the service annex without an arrival loop. The modular-city transfer test additionally validates all 10 live exterior openings, proves the Rouge Tower, garage, and duplicate Gate Building transitions stay absent, and checks Stretchman in Miare Station. The Route 0 gateway test holds an arriving player idle inside the Gate Building, validates clear exit signage, walks through its rear door, and uses the red interactive Route 0 return object.

## Provenance And Production Status

The reference-city models are derived from Pokémon Z-A field assets; per-asset archive and source paths remain in the catalog. They are useful for prototype composition and scale/reference work, but are not original New Bouffalant City designs. Confirm the project's rights and replacement plan before redistribution or release, and review any production use against the project's original-art direction and overworld budgets.
