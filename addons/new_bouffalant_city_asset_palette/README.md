# New Bouffalant City Asset Palette

This Godot editor plugin turns the [New Bouffalant City catalog](../../art/environments/new_bouffalant_city/reference_city_pack/catalog.json) into a searchable visual placement dock. It is enabled in `project.godot` and appears as **Bouffalant Assets** on the right side of the editor. If it is closed, reopen it from **Editor → Editor Docks → Bouffalant Assets**.

To learn how this plugin is structured and build an editor dock of your own,
follow the [editor-dock learning guide](LEARNING_GUIDE.md).

## Place Assets

1. Open any 3D scene and choose an asset from the thumbnail cards by search or category.
2. Leave **XZ snap** at `0.5 m` for normal placement. Choose `2 m` or `4 m` when assembling assets on those stricter grids.
3. Leave **Prefer upward-facing colliders** enabled to place on collision-enabled floors. Set **Fallback Y** for an empty scene or a different elevation.
4. Enable **Place in 3D View**, then left-click in a 3D viewport. Use `Q` and `E` to rotate by 90 degrees. Press `Escape` or right-click to stop.
5. Use Godot undo/redo normally. Placed scenes are organized below a `NewBouffalantCityAssets` node and retain their source `PackedScene` connection.

Double-clicking a catalog row starts placement. **Add at Scene Origin** is useful when an asset is large or difficult to aim. The **Ground Grid** button opens the strict 2 × 2 m `GridMap` workspace, and **Metric Browser** opens the full scale-reference scene.

Placed roots intentionally appear as `Scale = (1, 1, 1)`. The transferred GLBs already bake their player-calibrated `0.75` factor into the import, while the authored 2 × 2 m and 4 × 4 m ground scenes retain their exact dimensions. Do not scale a placed GLB to `0.75` again.

## Renderer Safety

Museum and Gate Building previously reproduced an Intel Vulkan/Forward+ driver hang. The current fix is applied to their mesh imports rather than handled by the palette: Museum, Gate Building, and Tenant Building keep their original mesh buffers by disabling generated LOD and optimized shadow buffers. Textures, collision, and normal shadow casting remain intact. The two import options were disabled together and neither has been isolated as the sole trigger.

The exception list lives in [`runtime_contract.gd`](../../game/world/level_kits/structures/new_bouffalant_city/runtime_contract.gd), and [`apply_model_import_settings.gd`](../../tools/new_bouffalant_city_import/apply_model_import_settings.gd) enforces it. The palette displays the active adapter and rendering method, but it does not block, intercept, or restart placement. All three protected assets double-click into the normal placement flow under Forward+.

Alternative renderer launchers remain available manually from the repository root. Intel Compatibility matches the project setting:

```sh
./addons/new_bouffalant_city_asset_palette/open_editor_compatibility.sh
```

NVIDIA Vulkan keeps Forward+ on the discrete GPU:

```sh
./addons/new_bouffalant_city_asset_palette/open_editor_nvidia.sh
```

Every current catalog entry has a bundled 192 × 192 render. The dock loads those renders first, so cards are available without waiting for Godot to synthesize a scene preview. To regenerate every thumbnail from a graphical desktop, run:

```sh
godot --path . --script res://addons/new_bouffalant_city_asset_palette/generate_thumbnails.gd
```

Pass asset IDs after `--` to render only those cards, for example `-- t1_b_cityhall t1_pl024`. The renderer requires a working 3D display/renderer and is not a headless task.

The palette places scene instances; it does not convert irregular buildings or complete environment sections into grid cells. Continue using `ModularGroundGrid` for fast 2 × 2 m cobble painting. Imported assets already carry their configured static collision, but navigation meshes and interaction boundaries remain scene-authoring responsibilities. See the [environment pack guide](../../art/environments/new_bouffalant_city/README.md) for collision profiles, scale, performance classification, and provenance constraints.

The normal double-click path for all three protected imports can be checked headlessly with:

```sh
godot --headless --path . --script res://addons/new_bouffalant_city_asset_palette/validation/asset_palette_activation_smoke_test.gd
```
