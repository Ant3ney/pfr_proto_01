# Trainer Stalls on a Vertically Offset Navigation Path

Use this document when a trainer successfully detects the player and disables player movement, but remains stationary even though a baked navigation path appears to cover both characters.

## Recognize the Failure Signature

This specific failure has all or most of these signs:

- Trainer line of sight works, so the encounter behavior runs and player movement is disabled.
- A `NavigationRegion3D` has a baked, connected surface covering the trainer and destination.
- The trainer root is correctly placed at foot level on the visible and collidable floor.
- Navigation debug geometry or returned path points are vertically offset from the character root. The original reproduction used a path at `Y = 0.5` with both characters at `Y = 0`; an otherwise identical path at `Y = 0` did not reproduce it because its path and character roots shared a height.

Do not diagnose this issue from the navigation overlay alone. First inspect the current scene, [`NPCController.gd`](../../game/actors/npcs/shared/npc_controller.gd), [`CharacterMovement.gd`](../../game/actors/character/character_movement.gd), and runtime path data.

## Verified Cause

Project locomotion is planar: `CharacterMovement.process_movement()` discards the target's Y offset and moves a character only on XZ. A `NavigationAgent3D`, however, evaluates the three-dimensional path positions returned by the navigation map. Before the correction was added, an elevated first path point could remain farther away than the controller's `path_desired_distance` even after the trainer reached the same XZ position. Because planar locomotion could never reduce the remaining Y distance, the agent could fail to advance to a useful waypoint and the trainer appeared stuck.

Raising the trainer or player to the navigation debug surface is not a valid fix. Character roots represent foot position and must remain aligned with visible floor geometry and physics collision.

## Current Required Behavior

[`NPCController.gd`](../../game/actors/npcs/shared/npc_controller.gd) owns the correction. Before assigning each changed target, it:

1. Gets the navigation-map point closest to the character's current global position.
2. Measures that point's vertical difference from the character's foot-level pivot.
3. Assigns the difference to `NavigationAgent3D.path_height_offset`.
4. Assigns the navigation target after the offset is calibrated.

The controller recalibrates when a target changes and when the navigation map's iteration changes. This keeps a character on the physical floor while aligning returned path positions with planar locomotion. Do not replace this with a scene-specific constant, do not manually add an agent to trainer scenes, and do not move character roots upward to match a baked mesh.

This correction handles a consistent vertical difference between a flat walkable floor and its baked path. It does not add gravity or support traversal between genuinely different floor elevations; those require a separate locomotion design change.

## Verify Before Changing the Fix

From the repository root, run:

```sh
godot --headless --path . --scene res://tests/scenes/navigation_path_height_smoke_test.tscn
```

The regression scene in [`tests/scenes/`](../../tests/scenes/navigation_path_height_smoke_test.tscn) builds one path at `Y = 0` and another at `Y = 0.5`. Both characters remain at `Y = 0`; the test requires both to reach their targets and verifies path-height offsets of `0` and `0.5` respectively.

If this test passes but a trainer still does not move in a level, investigate a different navigation failure:

- Confirm the navigation map has synchronized and contains polygons.
- Confirm the trainer and destination project onto the same reachable navigation surface.
- Confirm the bake parsed the intended ground and obstacles, following the [trainer and navigation setup](../../README.md#add-a-trainer-to-a-scene).
- Check physical collision separately if the trainer receives a path but catches on scenery.

When changing NPC navigation or vertical locomotion, keep this test current and update this document if the invariant changes. Current verified implementation and runtime behavior always take precedence over this explanation.
