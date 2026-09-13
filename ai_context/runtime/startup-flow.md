# Startup Menu, Introduction, and Gameplay Entry

Read this document when changing the configured project entry scene, main-menu
presentation, Cypress introduction, Continue/New Game routing, Route 0 backdrop,
or the point at which startup hands control to gameplay. Verify the current
scene, save owner, and focused startup tests before changing this lifecycle.

## Entry-scene ownership

[`startup_controller.tscn`](../../game/startup/startup_controller.tscn) is the
`run/main_scene`. Its
[`StartupController`](../../game/startup/startup_controller.gd) coordinates the
main menu, introduction, existing starter picker, saved-game loading, gameplay
scene transfer, failure retry, and the final movement handoff. The title is
**Pokémon Fracture × Revolt**. `Continue` appears only when
`ProgressionAutosave.inspect_local_save()` accepts the save. `New Game` starts
immediately only when no local file exists; any existing file, including an
invalid one, must pass the shared three-warning reset component first. `Quit`
is present on desktop and omitted on Web/mobile builds.

All actionable controls are ordinary focusable Godot buttons, so mouse, touch,
keyboard focus, and controller focus share one path. The menu uses the
project's blue/red identity over an opaque-enough navy panel. It creates no
scene-local audio player; the persistent
[`MusicManager`](music.md) selects and starts the main theme for this startup
scene.

## Isolated Route 0 backdrop

While the main menu is visible, the controller instances the playable
[`route_00.tscn`](../../game/world/levels/standalone_areas/routes/route_00/route_00.tscn)
inside a `SubViewport` with its own 3D world. The environment, lighting,
scenery, and `TallGrassVisuals` remain renderable. The player, actors,
interactions, transitions, and objectives are removed. Tall-grass encounter
zones retain their visual children but have processing, monitoring, collision,
and battle launch disabled. The route root is also process-disabled, so this
presentation cannot mutate progression or begin gameplay.

A camera follows a smooth closed `Curve3D` and looks along a corresponding
closed target curve. One circuit is exactly 60 seconds and surveys the route
entrance, central clearings and grass, and northern section. Leaving the menu
immediately disables viewport updates and frees the entire backdrop. Keep
camera-loop visual inspection in the validation path when route geometry or
camera points change; a passing structural test alone cannot detect clipping
or newly exposed map edges.

## New Game and Continue

New Game presents the Cypress illustration from
[`professor_cypress_intro.png`](../../art/ui/startup/professor_cypress_intro.png)
behind the shared `UIManager` dialog template. The action label is `Next`, the
dialog cannot be dismissed, and the controller advances these eight messages
in order:

1. “Welcome, young Trainer. I’m Professor Cypress.”
2. “Pokémon share our homes, our cities, and the wild places beyond.”
3. “A few choose to travel beside us. We call them partners.”
4. “Travel the region, earn Gym Badges, and challenge the Pokémon League.”
5. “Dream of becoming Champion—but remember who stands beside you.”
6. “Our region is changing. Kindness and friendship still matter.”
7. “Your journey begins in New Bouffalant City.”
8. “Choose your first partner. The road is waiting.”

The eighth action opens the existing Charmander/Froakie/Treecko picker and
confirmation. Confirmation queues the station concourse, requires the existing
`StretchmanReturnSpawn`, and keeps control disabled until placement succeeds.
The marker faces Stretchman. Only then does startup enable movement and write
the first schema-6 checkpoint, containing exactly the selected level-5 party
member and the placed station pose.

Continue applies the validated save through the normal schema-1-through-6 load
path, changes to the saved scene, and restores the saved global position,
player rotation, and visual rotation before enabling control. A valid legacy
profile with no usable world location keeps every progression domain but uses
the station marker fallback and checkpoints that safe placement. Automatic
move-choice presentation and cloud sync remain suspended until this placement
finishes; pending work is notified immediately afterward.

If a requested gameplay scene or placement fails, startup returns to a blocking
Retry state. Retry reuses the retained entry mode, destination, saved data, and
selected starter; it never creates a second PCL. Failure after a scene was
opened routes back to the startup scene before another attempt.

## Direct-scene and reset boundaries

Automatic save I/O detects the startup scene and waits for the coordinator.
Direct F6 launches and integration scenes preserve the previous convenience
behavior: the save owner loads/restores only the active scene and can show the
starter picker directly. This distinction keeps scene authoring and focused
tests useful without weakening the configured launch sequence.

Both menu New Game replacement and in-game Reset use
[`progress_reset_confirmation.tscn`](../../game/ui/reset_progress/progress_reset_confirmation.tscn).
It requires three distinct red **Yes** presses, offers **Cancel** at each stage,
and has no text field or checkbox. Only the third press can call the reset API.
An accepted in-game reset transfers to this startup scene and replays the
complete eight-message introduction before the picker.

## Regression and export checks

```bash
godot --headless --path . --scene res://tests/integration/startup_flow_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/startup_entry_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/startup_continue_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/reset_restart_smoke_test.tscn
```

The structural startup test covers menu visibility, platform Quit behavior,
invalid-save replacement gating, exact intro content, isolated inert Route 0,
the closed 60-second curve, backdrop teardown, and retry without duplication.
The entry and Continue tests use real scene transfers to cover all three
starters, station placement, Stretchman facing and interaction, city exit,
exact saved poses, legacy fallback, first-checkpoint timing, and delayed move
prompts. The selected Web export must include all startup/reset scenes and
scripts, the Cypress PNG, and the persistent music manager and its three Ogg
streams; run
`node tools/battle_sprite_pipeline/update_export_preset.cjs` after
adding runtime resources.

This leaf describes only configured launch and startup-to-gameplay ownership.
See [`starter-selection.md`](starter-selection.md),
[`progression-autosave.md`](progression-autosave.md), and
[`cloud-save.md`](cloud-save.md) for their narrower data contracts.
