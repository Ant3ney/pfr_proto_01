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

`game/battle/system/battle_sprite_catalog.gd` loads the metadata-only catalog, enforces
exact IDs, builds `SpriteFrames` from one manifest at a time, and retains at most
the active `ani` and `ani-back` assets. It uses cache-bypassing texture loads so
discarding those references does not intentionally retain prior atlases.
`load_front_thumbnail()` reads the first composited `ani` frame for a compact
switch-card still, crops it to that frame's alpha bounds, preserves its aspect,
and grounds it inside a small transparent texture. The full atlas is transient
and is never added to the active-asset cache, so rendering a party tray does not
retain six animation atlases.

`game/battle/system/battle_sprite_presenter.gd` owns both billboarded
`AnimatedSprite3D` actors. `configure(player_spawn, opponent_spawn,
player_shadow, opponent_shadow)` binds them to authored scene anchors and
optional scene-authored ground shadows. `present_battlers` or `present_snapshot`
selects the active exact IDs. Frame changes use manifest alpha bounds and the
active camera-up axis so the billboard's visible bottom remains projected onto
its authored ground anchor. GIF playback stays on the sprite; attack, hit,
heal, status, switch, and faint effects use each actor's separate motion root.
Because BattleSystem emits the authoritative final snapshot before its event list,
`present_snapshot` queues an active-member change while an old battler is
visible. A knockout event can therefore animate the old battler, and the
matching switch event commits and animates the queued replacement instead of
fainting the replacement shown by the final snapshot.

Player lookups always use `ani-back`; opponent lookups always use `ani`. Missing
exact forms, shiny requests, and the 21 unsupported base species use the neutral
placeholder unless an explicit approved `res://` override is supplied. The
catalog never strips a form suffix or substitutes a related ID.

## Developer screenshot showcase

[`developer_battle_showcase.tscn`](../../tests/manual/battle_screenshot_showcase/developer_battle_showcase.tscn)
inherits the production battle scene and renders ten curated, network-free
matchups with the real HUD and `BattleSpritePresenter`. Run it directly with F6,
press K to cycle, and press H to hide or restore its title card. Its first
pairing is Rayquaza versus Giratina, and the remaining list includes several
legendary rivalries, a Joltik-versus-Wailord scale contrast, and classic rivals.
Keeping it beneath `tests/manual/` prevents automatic profile initialization and
save writes while it is used as a screenshot stage.

## Pokédex-driven proportions

`BattleSpriteScale.gd` computes a presentation-only footprint from the exact
form's local PokeAPI `height` (decimeters) and `weight` (hectograms), carried in
the generated Showdown mapping. BattleSystem enriches copied player and
opponent snapshots with the local `pokemonId`; that field never enters the REST
team DTO. PokeAPI has no width measurement, so the catalog measures the maximum
single-frame alpha-bound width and divides it by the animation's maximum visible
alpha height. This preserves the authored silhouette without guessing a
physical width. It separately records the asymmetric left/right union of every
frame's alpha bounds so animations that travel across an offset GIF canvas are
also camera-safe. Weight supplies only a clamped `0.85..1.18` horizontal bulk
correction; a recorded zero weight means unknown and uses neutral bulk.

The deliberately exaggerated height curve is `sqrt(height_m)` below one metre
and `height_m ^ 0.32` at or above one metre. Player/back and opponent/front
reference geometric sizes are `2.05 m` and `1.90 m`. The result is uniformly
fit to the authored camera bounds: player `5.88 x 3.06 m`, opponent
`6.55 x 2.88 m`, with phone-readability height floors of `0.88 m` and `0.85 m`.
The presenter derives a tighter horizontal limit from the active camera,
projected side anchor, viewport bounds, and a 16 px safe inset when the authored
maximum would clip. Normal 16:9 and wider phone framing keeps the full bounds;
narrow previews shrink only species that exceed their side's available width.
When a huge opponent's projected envelope reaches the compact top-right status
card, a second uniform fit keeps a 4 px visual gap from that HUD exclusion zone.
BattleScene calls `refresh_layout()` after its intro camera settles so an
initial covered snapshot is framed against the final battle camera, not the
temporary intro zoom.
Missing dimensions use the former safe fixed heights and no width correction.
Persistent species size lives on `AnimatedSprite3D.pixel_size` and its local
x-scale, never on the motion root, so every motion animation preserves it.

The presenter resizes each ground shadow from the resulting visible width,
animates it during switch/faint presentation, and hides it when a side is empty
or a faint animation finishes. A queued voluntary replacement animates the
outgoing sprite and shadow completely before loading and switching in the new
member; a replacement after a knockout skips the redundant switch-out because
the outgoing battler is already hidden. Composite hit and switch effects return
completion signals tied to their actual child tweens, not mirrored duration
timers. Side-scoped completion IDs are explicitly released if clear,
reconfigure, or a new direct presentation interrupts those tweens.
Regression coverage includes exact Palkia/Wooper dimensions and contrast,
Joltik/Wailord bounds, unknown zero weight, every-frame grounding, camera
framing, shadow lifecycle, multi-tween completion at reduced fixed frame rates,
front-facing switch-card thumbnail extraction and placeholder behavior, and
preservation of strict REST DTO keys.

## Export and provenance boundaries

The raw source tree has `.gdignore`, is tracked by Git, and is excluded from Web
exports. The generated PNG/JSON runtime catalog and placeholder are included.
Godot does not list GIF among its supported imported image formats, which is why
conversion is required.

The source README records the supplied corpus and links the Smogon / Pokémon
Showdown artwork-rights caveat. Project documentation must describe provenance
without asserting that an upstream code license grants an artwork license.

Run `npm test`, `node sprite_pipeline.cjs verify`, the Godot battle-data,
session, sprite-catalog, and battle-start smoke tests, and `git diff --check`
after mapping, pipeline, catalog, presenter, or export changes.

This document covers only animated battle sprites. Battle protocol state,
collection mapping, encounters, and scene lifecycle are routed separately from
the runtime index.
