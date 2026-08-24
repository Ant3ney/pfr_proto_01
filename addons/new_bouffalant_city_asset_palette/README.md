# New Bouffalant City Asset Palette

This Godot editor plugin turns the [New Bouffalant City catalog](../../art/environments/new_bouffalant_city/reference_city_pack/catalog.json) into a searchable visual placement dock. It is enabled in `project.godot` and appears as **Bouffalant Assets** on the right side of the editor. If it is closed, reopen it from **Editor → Editor Docks → Bouffalant Assets**.

## Place Assets

1. Open any 3D scene and choose an asset from the thumbnail cards by search or category.
2. Leave **XZ snap** at `0.5 m` for normal placement. Choose `2 m` or `4 m` when assembling assets on those stricter grids.
3. Leave **Prefer upward-facing colliders** enabled to place on collision-enabled floors. Set **Fallback Y** for an empty scene or a different elevation.
4. Enable **Place in 3D View**, then left-click in a 3D viewport. Use `Q` and `E` to rotate by 90 degrees. Press `Escape` or right-click to stop.
5. Use Godot undo/redo normally. Placed scenes are organized below a `NewBouffalantCityAssets` node and retain their source `PackedScene` connection.

Double-clicking a catalog row starts placement. **Add at Scene Origin** is useful when an asset is large or difficult to aim. The **Ground Grid** button opens the strict 2 × 2 m `GridMap` workspace, and **Metric Browser** opens the full scale-reference scene. If Intel Vulkan was forced for Museum or Gate Building, double-clicking opens a safe-restart confirmation instead; after reopening, the same asset is selected with placement active, so hovering the 3D viewport displays the reticle immediately.

Placed roots intentionally appear as `Scale = (1, 1, 1)`. The transferred GLBs already bake their player-calibrated `0.75` factor into the import, while the authored 2 × 2 m and 4 × 4 m ground scenes retain their exact dimensions. Do not scale a placed GLB to `0.75` again.

## Renderer Safety

The source and imported mesh data for Museum, Gate Building, City Hall, Rouge Tower, and Lumiose Station validate. Untouched copies of all five also completed 600 animated, shadowed frames on Intel OpenGL Compatibility and 600 on NVIDIA Vulkan. Every recorded hard failure instead came from Intel Vulkan/Forward+, which a launcher outside this project forced despite the project's **GL Compatibility** setting.

Museum and Gate Building are the two confirmed triggers for that driver hang. On Intel Vulkan, the palette intercepts only those two entries, play from a scene containing one, and the metric browser because it contains both. High-load classification remains visible but does not block the other assets.

Double-click either intercepted asset, or press its placement button, and confirm **Save and Restart in Compatibility**. The plugin saves open scenes and scripts, waits for the current editor to close, reopens through the validated Compatibility launcher, reselects the requested asset, and resumes placement. If an untitled scene still needs a file path, finish the Save As operation and invoke placement again.

The same renderer paths remain available manually from the repository root. Intel Compatibility matches the project setting and is the simplest option:

```sh
./addons/new_bouffalant_city_asset_palette/open_editor_compatibility.sh
```

NVIDIA Vulkan keeps Forward+ on the discrete GPU:

```sh
./addons/new_bouffalant_city_asset_palette/open_editor_nvidia.sh
```

The palette displays the active adapter and rendering method. Museum and Gate Building become available automatically on either safe path. Their original materials remain intact; flat replacement materials are unnecessary because the crash is in the renderer/driver combination rather than malformed asset content.

Every current catalog entry has a bundled 192 × 192 render. The dock loads those renders first, so cards are available without waiting for Godot to synthesize a scene preview. To regenerate every thumbnail from a graphical desktop, run:

```sh
godot --path . --script res://addons/new_bouffalant_city_asset_palette/generate_thumbnails.gd
```

Pass asset IDs after `--` to render only those cards, for example `-- t1_b_cityhall t1_pl024`. The renderer requires a working 3D display/renderer and is not a headless task.

The palette places scene instances; it does not convert irregular buildings or complete environment sections into grid cells. Continue using `ModularGroundGrid` for fast 2 × 2 m cobble painting. Imported assets already carry their configured static collision, but navigation meshes and interaction boundaries remain scene-authoring responsibilities. See the [environment pack guide](../../art/environments/new_bouffalant_city/README.md) for collision profiles, scale, performance classification, and provenance constraints.

The guarded and normal double-click paths can be checked headlessly with:

```sh
godot --headless --path . --script res://addons/new_bouffalant_city_asset_palette/validation/asset_palette_activation_smoke_test.gd
```
