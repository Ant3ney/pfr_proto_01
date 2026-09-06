# Modular City Interiors

These Godot scenes provide the city-connected destinations for the solid imported building entrances in [`new_bouffalant_city.tscn`](../new_bouffalant_city.tscn). They preserve the project's near-future city inside a classical brick-and-mortar shell: warm worn brick, limestone trim, dark walnut, restrained civic colors, opaque materials, and broad readable props.

## Destinations

| Exterior | Scene | Indoor spawn and matching exit |
| --- | --- | --- |
| City Hall front, rear, and side | `city_hall_interior.tscn` | `FrontEntrySpawn` / `ExitFront`, `RearEntrySpawn` / `ExitRear`, `SideEntrySpawn` / `ExitSide` |
| Miare Station double doors | `miare_station_concourse.tscn` | `EntrySpawn` / `ExitToCity`; also owns `Stretchman` and `StretchmanReturnSpawn` |
| Gate Building city-facing door | `gatehouse_interior.tscn` | Safe `FrontEntrySpawn` / narrow `ExitFront`; rear `Route0ExitRoom` owns the walk-through `ExitToRoute0` door and `Route0ReturnSpawn` |
| West and north tenant doors | `west_tenant_lobby.tscn`, `north_tenant_lobby.tscn` | `EntrySpawn` / `ExitToCity` |
| Museum doors | `museum_gallery.tscn` | `EntrySpawn` / `ExitToCity` |

`shared/` owns the reusable brick room, one-shadow-light setup, and door visual.
Every interior inherits the common interior level base, which owns its nested
player/camera/UI runtime and standard level hierarchy. Each exit returns to a
dedicated marker beyond its exterior trigger, so arrival never immediately
reverses the scene transfer.

`rouge_tower_lobby.tscn` and `garage_workshop.tscn` remain as authored development assets, but the modular city no longer has Rouge Tower or garage transfer triggers or return markers. The Gate Building similarly has only one city-side transition; its clearly labeled rear door leads directly to Route 0 instead of back to a second city doorway. The front arrival marker is inset and faces into the room, outside the narrowed city-exit threshold. A blue `CITY EXIT` guide and green `ROUTE 0` guide distinguish the two directions.

The imported buildings keep their accurate solid collision. Exterior transfer boxes therefore straddle the facade or begin at the outer walkable approach rather than sitting behind the door mesh. Because transfer happens immediately on contact, the eight non-Pokemon-Center volumes are narrow `0.35 m` threshold strips fitted to their individual openings rather than broad sidewalk zones. Every exterior trigger stores a collision-free `metadata/approach_position` used by the physical regression test. The Gate Building's sole trigger uses the east, city-facing opening so the player does not need to walk around the landmark.

Because destination paths are strings, all eight live top-level destination scenes—the two Pokemon Center scenes and six scenes represented in the table—must remain explicitly selected in the `WebBuild` export preset. Shared scenes and textures are then included as dependencies.

## Verification

```sh
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/modular_city_scene_transfer_smoke_test.tscn
```

The test checks all 10 live city openings, destination spawns, matching indoor exits, safe outdoor markers, and live player overlap at collision-free approach points. It verifies that removed Rouge Tower, garage, and duplicate Gate Building transition nodes stay absent, every non-Pokemon-Center strip ignores a nearby player, and Miare Station contains Stretchman. `area_gateway_smoke_test.tscn` separately proves that an idle Gate Building arrival does not bounce outside, checks both exit guides, traverses the rear Route 0 door by contact, and uses the red interactive object at `Route0Start` to return safely.
