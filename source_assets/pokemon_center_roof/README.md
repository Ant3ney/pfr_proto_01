# Pokemon Center Roof Authoring

This source folder rebuilds the fitted roof and doors used by `art/environments/new_bouffalant_city/pokemon_center_roof/pokemon_center_with_roof.tscn`. The runtime additions remain conventional low-poly GLBs; Hunyuan and its Python dependencies are offline roof-authoring tools only.

1. Render the exact-fit multiview reference and building-context preview:

   ```sh
   blender --background --factory-startup \
       --python source_assets/pokemon_center_roof/prepare_hunyuan_roof_reference.py
   ```

2. In an isolated compatible environment for [Tencent Hunyuan3D-2](https://github.com/Tencent-Hunyuan/Hunyuan3D-2), run the multiview turbo generator from the Hunyuan checkout:

   ```sh
   python /path/to/project/source_assets/pokemon_center_roof/run_hunyuan_roof.py
   ```

   `HUNYUAN_MODEL_PATH` may point at a locally staged `Hunyuan3D-2mv` repository directory. The runner uses the FP16 SafeTensors checkpoint and retains its bundled VAE, avoiding redundant checkpoint and VAE downloads.

3. Render the seeded candidates from matching angles for review:

   ```sh
   blender --background --factory-startup \
       --python source_assets/pokemon_center_roof/render_hunyuan_candidates.py
   ```

4. Inspect the seeded GLBs and review renders in `hunyuan_output/`, select the cleanest silhouette, and conform it to the measured rim. Seed `731903` was selected for the checked-in roof:

   ```sh
   blender --background --factory-startup \
       --python source_assets/pokemon_center_roof/finalize_pokemon_center_roof.py \
       -- source_assets/pokemon_center_roof/hunyuan_output/roof_candidate_seed_731903.glb
   ```

The finalizer lets the Hunyuan donor influence only tightly clamped upper-roof proportions and skylight placement. The five-sided plan uses the model's complete 10.26 m source envelope and measured front chamfer. Its broad eave overhangs all four plan bounds and starts 8 cm above the source building's highest vertex, while a deeply recessed drum fills the space behind the facade emblems. The finalizer also rejects roof/building triangle intersections. It exports one opaque 201-triangle mesh with one 64 × 16 palette material, no tangents, animation, generated LODs, extra shadow mesh, or collision.

5. Rebuild both measured street-facing automatic door sets and their front-facade fit preview:

   ```sh
   blender --background --factory-startup \
       --python source_assets/pokemon_center_roof/create_pokemon_center_doors.py
   ```

The door builder uses the original south and east street-opening measurements and places a four-panel storefront beneath each large facade emblem. Its tagged outer frame layers deliberately tuck behind the opening edges to eliminate oblique-view seams; the authoring check excludes only those layers and rejects building intersections from the glass and hardware. It exports both storefronts as one opaque 56-triangle mesh with one 64 × 16 palette material and no transparency, tangents, animation, generated LODs, extra shadow mesh, or collision.

After regeneration, refresh Godot imports and run the focused smoke test:

```sh
godot --headless --rendering-method gl_compatibility --path . --import
godot --headless --rendering-method gl_compatibility --path . \
    --scene res://art/environments/new_bouffalant_city/pokemon_center_roof/validation/pokemon_center_roof_smoke_test.tscn
```

Review the Hunyuan repository's current license before regenerating or redistributing derived output. The underlying reference building is prototype/reference content with the provenance documented in the city-pack AI Context.
