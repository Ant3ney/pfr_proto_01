# Scene-Aware Music Lifecycle

Read this document when changing music selection, crossfades, playback gains,
battle interruption/resume behavior, audio imports, or selected-resource Web
exports. Verify the manager, battle signals, current scene paths, focused smoke
test, and an exported pack before changing this contract.

## Ownership and scene selection

[`MusicManager`](../../game/audio/music_manager.gd) is a persistent autoload
registered immediately after `GameInstance`. It owns exactly two
`AudioStreamPlayer` children and is the only runtime owner of background music.
Scenes do not create or stop their own music players.

`resolve_track_for_scene()` returns one of three stable IDs:

| Track ID | Stream | Scene rule | Playback gain |
| --- | --- | --- | ---: |
| `main` | [`pfr-main-theme.ogg`](../../audio/pfr-main-theme.ogg) | Startup/menu, New Bouffalant City, all interiors, gyms, Champion challenge, and every unrecognized path | +10.3 dB |
| `route` | [`tribly_town_theme.ogg`](../../audio/tribly_town_theme.ogg) | The canonical `route_00/route_00.tscn` through `route_40/route_40.tscn` paths | -0.6 dB |
| `battle` | [`battle_theme.ogg`](../../audio/battle_theme.ogg) | Every shared or specialized scene beneath `game/battle/scenes/` | -8.3 dB |

The exact canonical route pattern deliberately excludes the unfinished
`route_00_Real` visual reference and out-of-range route-like paths; both use the
safe main-theme fallback. All three Ogg imports loop from offset zero. The gains
are measured playback adjustments targeting roughly -16 LUFS and do not alter
or re-encode the source files.

## Cross-scene playback

`SceneTree.scene_changed` drives ordinary selection. If the destination resolves
to the active logical track, the current player and playback position are left
untouched. Otherwise, the idle player starts the destination at zero and the two
players follow a 0.5-second equal-power curve: outgoing amplitude uses cosine
and incoming amplitude uses sine. Superseding requests reuse the relevant live
player, replace the other, and invalidate the prior transition state, so no stale
completion can stop the final target.

The read-only diagnostic surface is:

- `track_changed(track_id)`, emitted when the logical ID changes;
- `get_current_track_id()`;
- `get_current_playback_position()`; and
- `resolve_track_for_scene(scene_or_path := null)`.

## Battle interruption and return

`GameInstance.battle_starting` fires while the source scene is still live.
`MusicManager` records the selected overworld track and current position in
memory, cancels any active fade, stops both players immediately, and starts the
battle theme from zero at -8.3 dB in that signal callback. The later change to a
battle scene therefore does not restart it. Every accepted battle launch repeats
this hard cut and starts a fresh battle playback.

On the first non-battle destination after launch, the manager consumes the saved
state. If that scene selects the interrupted track, it crossfades from battle to
that saved position. If it selects a different track, including a route loss
returning to the Pokémon Center, it crossfades to the destination from zero.
Resume state spans only the current battle and is never serialized. If
`battle_start_failed` occurs before entering battle, the same saved track and
position are restored by crossfade. A failed return that has not changed scenes
keeps battle playback and the resume state intact.

## Web export and regression checks

The selected-resource generator explicitly includes all three Ogg sources.
[`verify_export_pack.cjs`](../../tools/battle_sprite_pipeline/verify_export_pack.cjs)
requires each `.ogg.import` entry and the exact `.oggvorbisstr` payload named by
its live import remap. The exported-runtime verifier also loads each stream,
checks zero-offset looping, finds the autoload and two players, and verifies the
diagnostic methods and gains.

```bash
godot --headless --path . --scene res://tests/integration/music_manager_smoke_test.tscn
node tools/battle_sprite_pipeline/update_export_preset.cjs
godot --headless --path . --export-pack WebBuild /tmp/pfr-web-check.pck
node tools/battle_sprite_pipeline/verify_export_pack.cjs /tmp/pfr-web-check.pck
godot --headless --main-pack /tmp/pfr-web-check.pck --script "$PWD/tools/verify_web_export.gd"
```

The focused smoke test covers all 41 route paths, main-theme and unknown
fallbacks, every current battle variant, two-player ownership, looping, gains,
same-track continuity, same-frame battle cutoff, successful and failed-start
resume positions, different-track return-from-zero behavior, signals, and rapid
transition cancellation.
