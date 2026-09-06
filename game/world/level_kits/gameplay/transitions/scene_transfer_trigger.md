# Scene Transfer Trigger

[`scene_transfer_trigger.tscn`](scene_transfer_trigger.tscn) is the ready-to-place player-only scene-transfer object. Its script also registers `SceneTransferTrigger` in Godot's **Create New Node** dialog.

## Editor Use

1. Drag `scene_transfer_trigger.tscn` into a 3D level. Alternatively, create a `SceneTransferTrigger` node and add a `CollisionShape3D` beneath it.
2. In the **Scene Transfer** inspector group, choose a `.tscn` file for **Destination Scene Path**.
3. Optionally enter the exact name of a destination `Node3D` or `Marker3D` in **Destination Spawn Marker**. The destination's first `PlayerCharacter` is moved and faced to match that marker. Leave this blank to keep the player position authored in the destination scene.
4. Scale or replace the included box shape so it spans only the doorway threshold. Contact transfers are immediate, so avoid covering stairs, plazas, or general sidewalk approaches. If the visible door belongs to a solid imported building collider, the narrow volume must still protrude onto the reachable side; a trigger entirely behind the collision can never receive the player. Keep the destination marker outside any reverse trigger to prevent an immediate return loop.

The trigger ignores NPCs and other physics bodies, accepts only one player contact, and defers the request out of the physics callback. `GameInstance.transfer_to_scene()` validates the target, locks movement, clears stale touch input, changes scenes, applies the optional marker, restores the prior movement state, and emits lifecycle signals. A failed request re-enables the trigger.

Paths are stored instead of `PackedScene` references so two levels can safely point at each other without a cyclic resource dependency. When using a selected-resources export preset, add every destination scene to that preset. The current Web preset explicitly includes the modular city, both Pokemon Center destinations, the six live modular-city interior destinations, and Route 0. Rouge Tower and garage interiors remain authored assets but are not live transfer destinations.

## Signals

- `SceneTransferTrigger.transfer_requested(path, marker)` fires after `GameInstance` accepts the request.
- `GameInstance.scene_transfer_started(path, marker)` fires after movement is locked.
- `GameInstance.scene_transfer_finished(path, marker, marker_applied)` fires after the destination is ready.
- `GameInstance.scene_transfer_failed(message)` reports validation or loading failure.

## Verification

```sh
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/scene_transfer_trigger_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/pokemon_center_scene_transfer_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/modular_city_scene_transfer_smoke_test.tscn
godot --headless --rendering-method gl_compatibility --path . --scene res://tests/scenes/area_gateway_smoke_test.tscn
```

The generic test covers inspector configuration, NPC rejection, debounce, movement locking, scene loading, and marker placement. The Pokemon Center test traverses the real south and east openings, verifies that each targets a distinct assigned interior, and checks that both matching safe return markers prevent reverse-trigger loops. The modular-city test checks all 10 live exterior routes, verifies that each authored approach is both physically inside its Area3D and free of imported static collision, confirms that all eight non-Pokemon-Center volumes are narrow threshold strips that ignore a nearby player, and performs a real body-contact transfer through the Miare Station doors and back. The Route 0 test verifies that the Gate Building front arrival remains outside its exit while idle, then exercises its rear contact door and the red interactive return object.
