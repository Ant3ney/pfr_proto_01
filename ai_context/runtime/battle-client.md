# Centralized Godot Battle Client

Read this document when changing the Godot battle coordinator, REST transport,
response validation, collection health/XP writeback, request-driven choices, or
presentation event sequencing. Check the linked implementation and focused
tests before changing these contracts.

## Runtime ownership

[`BattleSystem`](../../battle/system/BattleSystem.gd) is an autoload and the
only gameplay coordinator for networked PvE battles. Its state flow is:

```text
IDLE -> CONNECTING -> PRESENTING -> AWAITING_PLAYER
                         ^              |
                         |              v
                         +--------- SUBMITTING

PRESENTING/SUBMITTING -> ENDED -> RETURNING -> IDLE
```

`BattleSystem` owns encounter discovery, collection-party DTO construction,
the memory-only state token, battle ID and revision, exact request retries,
response validation, atomic health/XP writeback, event/request ordering, result state,
and session cleanup. [`BattleScene`](../../battle/BattleScene.gd) is a thin
adapter: it converts UI actions into typed coordinator calls and converts
copied snapshots/events into presentation. It must not create REST commands,
hold tokens, infer outcomes from event text, or mutate collection state.

`GameInstance` owns only scene transitions, the movement lock, and one-scene
encounter suppression. See [`battle-start.md`](battle-start.md) for the covered
connection, reveal, and return order.

## Session and transport contract

[`BattleRestClient`](../../battle/system/BattleRestClient.gd) sends JSON to the
fixed base URL `https://pfr-locomotion-prototype.vercel.app/api/v1`. It permits
one `HTTPRequest` at a time, sends no credentials or authentication header,
enforces a response-size ceiling, and tags callbacks with a local request ID.
Production and development use this URL; automated tests inject a fake
transport.

The token never enters presentation state, signals, logs, launch data, or save
data. `BattleSystem` retains the submitted token and serialized action bytes
until a response is accepted. A transport retry sends those byte-identical
bytes. Stale callbacks and duplicate accepted responses are ignored; the
client never intentionally submits a new action against an older token.

[`BattleDtoValidator`](../../battle/system/BattleDtoValidator.gd) checks the
API, engine, and format versions; battle identity; revision progression; phase;
token presence; structured request; party snapshots; result; event shape; and
response size before any state is applied. The untouched server snapshot is
authoritative for HP, active members, status, requests, and outcome. Local
sprite metadata is joined by `memberId` only after validation and only in the
deep-copied presentation snapshot.

Every accepted response, including loss and forfeit, is written through
`CollectionSystem.apply_battle_health_and_experience()`. That API validates a
complete player party and all XP recipients before applying health and
progression atomically and emitting one collection update. `BattleSystem`
tracks every player member that appeared on the stage for the rest of the
current session. An active accepted snapshot records ordinary appearances, and
a living-to-fainted player transition records a forced-in member that fainted
before the final state could show it active. An accepted typed switch also
records its target before rewards, covering a target that enters and leaves or
faints within the same response. A validated opponent transition from
not-fainted to fainted awards every recorded participant once, including
participants that later switched out or fainted. Initial snapshots, stale
callbacks, retries, and duplicate responses cannot award XP. The level
differential supplies the base reward in
[`BattleExperience`](../../battle/system/BattleExperience.gd), then the
defeated Pokemon's local Pokédex `xp_multiplier` is applied. This progression
metadata stays local and never enters the strict REST team DTO.

Applied local XP awards also report whether a direct level-only evolution is
available and copy its eligible targets. A level-up presentation message points
the player to the Pokemon menu; the collection species is not changed during
the in-flight server session. See [`evolution.md`](evolution.md).

The pinned PvE rule sets `d = defeated_level - participant_level`. For `d >= 0`,
`level_factor = clamp(1 + 0.18d, 1.0, 2.2)`; the higher-level opponent bonus is
unchanged. For `d < 0`, `level_factor = max(0.7, 1 + 0.09d)`. This halves the
former lower-level penalty from 18 to 9 percentage points per level and halves
its maximum penalty from 60% to 30%. It then computes
`base = round(defeated_level * 10 * level_factor)` and
`award = round(base * xp_multiplier)`, with a minimum award of 1. Every member
that appeared receives the full award rather than dividing it; members that
never appeared normally receive none. A current party member that never
entered but holds `exp-share` receives half of the award calculated from its
own level for each knockout. A participating holder receives only the ordinary
full award, never a second Exp. Share award. Held-item metadata remains local
collection progression and never enters the strict REST team DTO. Every XP
presentation event includes the recipient's post-award in-level progress and
remaining XP to the next-level target, so a holder's gain remains visible even
when it does not cross a level threshold. A per-session level-announcement
high-water mark prevents the same Pokemon from presenting `grew to Lv. N`
twice; multi-opponent battles still present one ordinary XP gain per knockout.

## Public input and presentation boundary

Scene/UI code may call only these coordinator inputs:

- `begin_current_battle_scene()`
- `choose_move(move_index)`
- `choose_switch(member_id)`
- `forfeit()` after confirmation
- `retry_pending_request()`
- `acknowledge_events_presented(revision)`
- `continue_after_result()`

Presentation observes `state_changed`, `snapshot_changed`,
`presentation_events_ready`, `choice_request_changed`, `battle_ended`, and
`battle_error_changed`. Signal dictionaries and public getters are recursive
copies. Choices remain disabled while a request or event sequence is active.
The structured server request alone determines enabled move indices, PP,
switch member IDs, and whether a switch is forced. Bag is unavailable in v1;
Run requires confirmation and submits a forfeit.

Known p1-filtered protocol events are translated by
[`BattleEventTranslator`](../../battle/system/BattleEventTranslator.gd) into
message, switch, attack, damage/heal, status, knockout, and result presentation
events. Unknown events safely become a message or no-op. The adapter must
acknowledge a revision only after its complete event sequence finishes; the
next choice request is not exposed before that acknowledgement.

## Compact battle HUD

[`battle_ui_overlay.tscn`](../../core/ui/battle_ui_overlay.tscn) defines the
persistent status, message, and command HUD. [`UITemplate`](../../core/UITemplate.gd)
binds copied battle presentation data to it, while
[`BattleUIOverlay`](../../core/ui/BattleUIOverlay.gd) owns presentation-only
responsive layout and layered command materials. At the 960-by-540 design
viewport, each status card and the message panel is 58 px tall, the command
tray is 56 px tall, the lower rows have a 4 px gap, and the tray ends 4 px above
the usable bottom. Command buttons retain 40 px touch targets. Horizontal
gutters are `max(16 px, 1.5% of viewport width)`; status cards use 26% of the
width clamped to 236 to 288 px, with a 10 px player-card/message gap, so wider
landscape viewports give their extra width to the message panel rather than
making the compact cards taller.

The player card includes `PlayerXP`, a label-free 3 px cyan strip directly
under HP. It displays copied `experienceProgress` from the active PCL and does
not increase the 58 px card height. A level-up may update the local collection
level immediately for presentation and later battles; the in-flight server
session remains snapshot-authoritative for combat calculations.

After an `experience` event is displayed, `BattleScene` asks the R&D
`MoveLearningSystem` to present every move earned by that event's `memberId`.
The scene awaits replacement or decline before acknowledging the event
revision, so the next server request cannot appear beneath the modal. Equipped
moves still change only in `CollectionSystem`; the current REST session keeps
its original team snapshot and later battles receive the updated move set. See
[`move-learning.md`](move-learning.md) for the generated learnset and queue
contract.

Ordinary choices use [`battle_choice_overlay.tscn`](../../battle/ui/battle_choice_overlay.tscn)
and [`BattleChoiceOverlay`](../../battle/ui/BattleChoiceOverlay.gd) as a bottom
tray with the same 56 px geometry and no battlefield dim. Move buttons preserve
the returned order and `moveIndex`, show the returned PP and disabled state,
and include Back; voluntary switches show only returned `memberId` options
joined to snapshot names, HP, and exact `spriteId`. Each switch card includes a
32 px, alpha-cropped still from frame zero of that Pokémon's front-facing `ani`
GIF atlas; unsupported exact forms and unapproved shiny requests retain the
neutral placeholder policy rather than substituting related art. Forced
switches omit Back and cannot be cancelled. Forfeit confirmation, retry/return
errors, and final results instead use the compact centered modal mode with a
dim layer.

The request remains authoritative for available move and switch choices, and
the snapshot remains authoritative for names and HP. Move color and type text
are cosmetic only: the tray looks up the returned canonical move `id` through
[`BattleSpeciesMapping.get_move_type()`](../../battle/system/BattleSpeciesMapping.gd).
The generated [`pokeapi_showdown_mapping.json`](../../battle/data/pokeapi_showdown_mapping.json)
contains a validated type for every pinned Showdown move ID; an unknown ID has
no inferred gameplay meaning and falls back to the neutral presentation style.

## Error policy

| Failure | Local behavior |
| --- | --- |
| Network, timeout, or server 5xx | Preserve the exact pending request; offer Retry and Return |
| `422 invalid_action` | Discard the rejected pending request and restore the last valid choice request |
| Token/version/battle-limit incompatibility, malformed or oversized response | End the local session, clear sensitive state, and offer Return |
| Invalid local party or encounter preflight | Do not send; remain covered and offer Return |

An unrecoverable error returns through the same fixed modular-ground path as a
server result. It does not synthesize a win/loss or progression update.

## Party and encounter authoring

`CollectionSystem.get_battle_party_members()` returns server-ready deep copies
using `pclID` as `memberId`. Persisted `battleProfile` data supplies canonical
Showdown species, exact sprite ID, and one to four equipped move IDs. Defaults
are generated only when a supported collection instance is first migrated;
they are never recomputed at battle start. An all-fainted party fails local
preflight, while fainted members remain in a valid mixed-health request.

The PokeAPI-ID mapping is generated against pinned
`pokemon-showdown@0.11.11` and loaded by
[`BattleSpeciesMapping`](../../battle/system/BattleSpeciesMapping.gd). Run
`node tools/generate_battle_species_mapping.mjs --check` after mapping changes.
Unsupported forms remain collectible but cannot enter the battle party until
explicitly mapped.

Concrete battle scenes contain exactly one node in group
`battle_encounter_provider`, exporting a
[`BattleEncounterDefinition`](../../battle/data/BattleEncounterDefinition.gd).
The resource owns stable IDs, protocol-safe side name, one-to-six validated
members, optional approved sprite override, and forfeit policy. Kyle's example
is [`trainer_kyle_lake_v1.tres`](../../battle/encounters/trainer_kyle_lake_v1.tres)
inside [`kyle_battle_scene.tscn`](../../battle/kyle_battle_scene.tscn).
Route 0 uses the same contract for a wild caller: distance travelled inside
[`TallGrassEncounterZone`](../../rnd/TallGrassEncounterZone.gd) launches
[`route_0_wild_battle_scene.tscn`](../../battle/route_0_wild_battle_scene.tscn),
whose provider owns
[`wild_fletchling_route_0_v1.tres`](../../battle/encounters/wild_fletchling_route_0_v1.tres).
The launch ID and provider ID are both `wild-fletchling-route-0-v1`.

## Regression checks

```bash
node tools/generate_battle_species_mapping.mjs --check
node tools/generate_creature_experience_data.mjs --check
node rnd/move_learning/tools/generate_move_learnsets.mjs --check
godot --headless --path . --scene res://tests/integration/battle_data_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/battle_ui_layout_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/battle_choice_overlay_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/battle_system_session_test.tscn
godot --headless --path . --scene res://tests/scenes/battle_scene_lifecycle_test.tscn
godot --headless --path . --scene res://tests/integration/move_learning_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/tall_grass_encounter_zone_smoke_test.tscn
```

These cover migration and mapping, exact Kyle authoring, start/action/retry,
voluntary and forced choices, results, forfeit, malformed/version failures,
stale and duplicate callbacks, compact and wide-phone HUD geometry, typed move
and switch trays, modal modes, request locking, event acknowledgement, return
ordering, and suppression.
