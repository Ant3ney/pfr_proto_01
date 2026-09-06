# Pokemon Center Interior

[`pokemon_center_interior.tscn`](../../../../game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_interior.tscn) is the playable interior level for New Bouffalant City's Pokemon Center. Open that scene directly in Godot to edit or play it.

## Design

The five-sided, open-front room echoes the exterior building footprint while remaining readable from the project's low follow camera. It now presents the Center as a near-future clinic renovated inside an older civic shell: warm worn brick, pale limestone pilasters and cornices, dark walnut wainscot and benches, and lightly grungy mortar surround the vivid red/cyan healing technology. The wear stays broad and restrained so the room feels established and inhabited rather than ruined. Sparse props and low foreground walls preserve uncluttered walking space and clear silhouettes.

The level includes the player, gameplay camera, game UI, a central entry spawn, nurse and visitor markers, and an `ExitToCity` [`SceneTransferTrigger`](../../../../game/world/level_kits/gameplay/transitions/scene_transfer_trigger.md). A formal male attendant now occupies `NurseSpawn` behind the healing desk. Walking up to the desk opens a touch-friendly **Heal** / **Not now** conversation; confirming restores the current party and reuses the same UI for the result. The exterior's south storefront enters this main clinic and its exit returns to the safe `PokemonCenterEntrance` marker. The east storefront instead enters the distinct [`pokemon_center_annex.tscn`](../../../../game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_annex.tscn) service environment and returns through its own east marker.

## Mobile-Web Contract

- The complete visual environment is 1,948 triangles in one mesh with two opaque material draws.
- Color comes from one 128 x 16 nearest-filtered palette plus one repeating 512 x 512 brick albedo; there are no normal, roughness, transparency, or emission texture passes.
- Runtime nodes and the imported environment remain at unit scale.
- Fourteen boxes/cylinders provide simplified floor, wall, counter, seating, terminal, and planter collision. The GLB has no generated mesh collision.
- The counter is shifted 0.35 m forward to leave a safe service aisle. The attendant adds one compact capsule and one non-blocking, player-only interaction sphere; the environment geometry and fourteen static shapes are unchanged in complexity.
- The imported waiter is 7,656 runtime skinned triangles in nine material draws with nine 256 x 256 albedo textures. No second staff character, extra light, particle system, or healer-only environment material is added.
- One directional light casts basic shadows. Two low-energy counter fills do not cast shadows.
- The GLB import disables tangents, animation, generated LODs, and a separate optimized shadow mesh.

Source authoring files and regeneration instructions live under [`../../../../source_assets/pokemon_center_interior/`](../../../../source_assets/pokemon_center_interior/).

## Verification

From the repository root, run:

```sh
godot --headless --path . --import
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/assets/pokemon_center_interior_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/pokemon_center_scene_transfer_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/pokemon_center_healer_smoke_test.tscn
```

The interior test verifies the exact geometry/two-draw texture budget, authored bounds, collision, staffed-attendant clearance and interaction area, gameplay markers, camera, exit-trigger configuration, and the shadow-light contract. The healer test covers its full UI and collection sequence. The transfer test traverses both real exterior openings, confirms that they load different assigned environments, returns through each matching marker, and rejects reverse-trigger loops.
