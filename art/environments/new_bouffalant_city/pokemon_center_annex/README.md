# Pokemon Center Service Annex

[`pokemon_center_annex.tscn`](pokemon_center_annex.tscn) is the distinct interior reached through the Pokemon Center's east exterior storefront. The south storefront continues to open the main clinic lobby; the east storefront now opens this service annex instead of placing both entrances at the same indoor spawn.

## Design

The annex shares the main clinic's renovated civic language—warm worn brick, pale limestone pilasters and cornices, dark walnut paneling, and restrained grime—but has its own purpose and silhouette. An apothecary-style dispensing cabinet, four collection pods, consultation seating, automated lockers, and a standing terminal distinguish it from the main healing room while preserving clear walking space.

`EntrySpawn` is safely inside the open foreground. `ExitToCity` returns to `PokemonCenterEastEntrance`, a dedicated marker outside the east trigger volume, so leaving the annex cannot immediately send the player back inside.

## Mobile-Web Contract

- The environment is one unit-scale mesh with 1,962 triangles and two opaque material draws.
- It reuses the main clinic's 128 × 16 palette and repeating 512 × 512 brick albedo, with no extra normal, roughness, transparency, emission, animation, or runtime-generation pass.
- Thirteen authored primitive shapes provide floor, wall, counter, seating, table, locker, terminal, and planter collision; the GLB contains no generated mesh collision.
- One directional light casts basic shadows. Two low-energy local fills remain shadow-free.
- The GLB import disables tangents, animation, generated LODs, and a separate optimized shadow mesh.

Source authoring files and regeneration instructions live under [`../../../../source_assets/pokemon_center_annex/`](../../../../source_assets/pokemon_center_annex/).

## Verification

```sh
godot --headless --path . --import
godot --headless --rendering-method gl_compatibility --path . --scene res://art/environments/new_bouffalant_city/pokemon_center_annex/validation/pokemon_center_annex_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/pokemon_center_scene_transfer_smoke_test.tscn
```

The focused annex test protects its geometry, textures, bounds, collision, gameplay nodes, lights, and east-return contract. The transfer test traverses both real exterior openings and confirms that each reaches its assigned interior and returns through its matching safe marker.
