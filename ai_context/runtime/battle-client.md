# Centralized Godot Battle Client

Read this document when changing the Godot battle coordinator, REST transport,
response validation, collection health writeback, request-driven choices, or
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
response validation, health writeback, event/request ordering, result state,
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
`CollectionSystem.apply_battle_health_snapshot()`. That API validates a
complete player party before applying all health values atomically and emitting
one collection update.

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

## Regression checks

```bash
node tools/generate_battle_species_mapping.mjs --check
godot --headless --path . --scene res://tests/battle_data_smoke_test.tscn
godot --headless --path . --scene res://tests/battle_system_session_test.tscn
godot --headless --path . --scene res://tests/battle_scene_lifecycle_test.tscn
```

These cover migration and mapping, exact Kyle authoring, start/action/retry,
voluntary and forced choices, results, forfeit, malformed/version failures,
stale and duplicate callbacks, request locking, event acknowledgement, return
ordering, and suppression.
