# Animated Battle Sprite Pipeline and Runtime

Read this document for verified animated battle-sprite provenance, regeneration,
catalog lookup, loading, grounding, and export behavior. Check the current tool,
manifests, presenter, and export preset before changing the contract.

## Verified corpus and generated catalog

The user-supplied sibling corpus was copied locally without a network fallback
to `source_assets/battle_sprites/pokemon_showdown/`. Its preserved
`sync-manifest.json` reports 2,106 downloads and zero failures. The generated
`sha256-manifest.json` records every source path, byte count, and SHA-256.

The verified source split is 1,054 `ani` opponent/front GIFs and 1,052
`ani-back` player/back GIFs (143,982,935 source bytes). `colossoil` and `pyroak`
are the two front-only IDs. There are no back-only IDs.

`tools/battle_sprite_pipeline/sprite_pipeline.cjs` pins `gifuct-js` 2.1.2 and
`pngjs` 7.0.0 and has no download code path. It handles logical-screen offsets,
alpha compositing, disposal modes 2 and 3, interlacing through `gifuct-js`,
decoded millisecond durations, transparent-edge RGB bleed, per-frame alpha
bounds, and one padded PNG atlas per animation.

The complete generated catalog under `art/battle/sprites/generated/` contains
2,106 PNG atlases and 2,106 timing manifests with exactly 121,213 composited
frames and 621,466,600 atlas bytes. Verified feature coverage includes 32
variable-duration animations, 23 interlaced animations, 1,979 animations with
offset patches, and 2,104 animations using disposal mode 2 or 3. Ferroseed is a
one-frame gate; `ani/regieleki` is the 315-frame maximum.

## Runtime ownership

`battle/system/BattleSpriteCatalog.gd` loads the metadata-only catalog, enforces
exact IDs, builds `SpriteFrames` from one manifest at a time, and retains at most
the active `ani` and `ani-back` assets. It uses cache-bypassing texture loads so
discarding those references does not intentionally retain prior atlases.

`battle/system/BattleSpritePresenter.gd` owns both billboarded
`AnimatedSprite3D` actors. `configure(player_spawn, opponent_spawn)` binds them
to authored scene anchors. `present_battlers` or `present_snapshot` selects the
active exact IDs. Frame changes use manifest alpha bounds for local-y grounding
and maximum visible alpha height for consistent scale. GIF playback stays on
the sprite; attack, hit, heal, status, switch, and faint effects use each
actor's separate motion root. Because BattleSystem emits the authoritative
final snapshot before its event list, `present_snapshot` queues an active-member
change while an old battler is visible. A knockout event can therefore animate
the old battler, and the matching switch event commits and animates the queued
replacement instead of fainting the replacement shown by the final snapshot.

Player lookups always use `ani-back`; opponent lookups always use `ani`. Missing
exact forms, shiny requests, and the 21 unsupported base species use the neutral
placeholder unless an explicit approved `res://` override is supplied. The
catalog never strips a form suffix or substitutes a related ID.

## Export and provenance boundaries

The raw source tree has `.gdignore`, is tracked by Git, and is excluded from Web
exports. The generated PNG/JSON runtime catalog and placeholder are included.
Godot does not list GIF among its supported imported image formats, which is why
conversion is required.

The source README records the supplied corpus and links the Smogon / Pokémon
Showdown artwork-rights caveat. Project documentation must describe provenance
without asserting that an upstream code license grants an artwork license.

Run `npm test`, `node sprite_pipeline.cjs verify`, the Godot sprite smoke test,
and `git diff --check` after pipeline, catalog, presenter, or export changes.

This document covers only animated battle sprites. Battle protocol state,
collection mapping, encounters, and scene lifecycle are routed separately from
the runtime index.
