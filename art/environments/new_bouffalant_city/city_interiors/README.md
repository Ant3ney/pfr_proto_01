# Modular City Interiors

These Godot scenes provide the lightweight destinations for the solid imported building entrances in [`primary_development_enviroment.tscn`](../../../../demo/primary_development_enviroment.tscn). They preserve the project's near-future city inside a classical brick-and-mortar shell: warm worn brick, limestone trim, dark walnut, restrained civic colors, opaque materials, and broad readable props.

## Destinations

| Exterior | Scene | Indoor spawn and matching exit |
| --- | --- | --- |
| City Hall front, rear, and side | `city_hall_interior.tscn` | `FrontEntrySpawn` / `ExitFront`, `RearEntrySpawn` / `ExitRear`, `SideEntrySpawn` / `ExitSide` |
| Rouge Tower south, north, and east approaches | `rouge_tower_lobby.tscn` | `SouthEntrySpawn` / `ExitSouth`, `NorthEntrySpawn` / `ExitNorth`, `EastEntrySpawn` / `ExitEast` |
| Miare Station double doors | `miare_station_concourse.tscn` | `EntrySpawn` / `ExitToCity` |
| Garage office, vehicle bay, and side service doors | `garage_workshop.tscn` | `OfficeEntrySpawn` / `ExitOffice`, `BayEntrySpawn` / `ExitVehicleBay`, `SideEntrySpawn` / `ExitSideService` |
| Gate Building front and rear approaches | `gatehouse_interior.tscn` | `FrontEntrySpawn` / `ExitFront`, `RearEntrySpawn` / `ExitRear` |
| West and north tenant doors | `west_tenant_lobby.tscn`, `north_tenant_lobby.tscn` | `EntrySpawn` / `ExitToCity` |
| Museum doors | `museum_gallery.tscn` | `EntrySpawn` / `ExitToCity` |

`shared/` owns the reusable brick room, one-shadow-light setup, door visual, and nested player/camera/UI runtime. The individual levels add only broad primitive furnishings and simple static collision. Each exit returns to a dedicated marker beyond its exterior trigger, so arrival never immediately reverses the scene transfer.

The imported buildings keep their accurate solid collision. Exterior transfer boxes therefore straddle the facade or begin at the outer walkable approach rather than sitting behind the door mesh. Because transfer happens immediately on contact, the 15 non-Pokemon-Center volumes are narrow `0.35 m` threshold strips fitted to their individual openings rather than broad sidewalk zones. Every exterior trigger stores a collision-free `metadata/approach_position` used by the physical regression test.

Because destination paths are strings, every top-level interior scene must remain explicitly selected in the `WebBuild` export preset. Shared scenes and textures are then included as dependencies.

## Verification

```sh
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/modular_city_scene_transfer_smoke_test.tscn
```

The test checks all 17 city openings, destination spawns, matching indoor exits, safe outdoor markers, and live player overlap at collision-free approach points. It also verifies that every non-Pokemon-Center strip ignores the player at a nearby exterior position and completes a body-contact trip through the photographed Miare Station doors and back.
