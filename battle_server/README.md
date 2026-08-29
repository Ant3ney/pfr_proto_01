# PFR Battle Server

`battle_server` is an API-only Next.js service for deterministic Gen 9 singles
battles between one player and a server-controlled opponent. It is stateless:
every action reconstructs the battle from the opaque `stateToken` returned at
the previous player decision boundary. There is no database, authentication,
multiplayer synchronization, or process-local battle registry.

The simulator is pinned to the published `pokemon-showdown@0.11.11` package.
The `core/` checkout is kept only as local reference material and is excluded
from Git, TypeScript, ESLint, and the deployed service.

## Local setup

Install Node.js 24 and dependencies, then generate one random 32-byte key:

```bash
cd battle_server
npm ci
openssl rand -base64 32
```

Store the single line printed by OpenSSL as `BATTLE_STATE_KEY` in an untracked
`.env.local` file:

```dotenv
BATTLE_STATE_KEY=<base64 value from openssl>
```

Do not commit or expose this key. Changing it makes every outstanding state
token unreadable. Start the development server with:

```bash
npm run dev
```

The API is then available at `http://localhost:3000/api/v1`.

## API conventions

All endpoints use the Node.js runtime and return JSON, except successful
`OPTIONS` requests, which return an empty `204` response. Every response sends
`Cache-Control: no-store`. CORS permits any origin and the `Content-Type`
request header without sending `Access-Control-Allow-Credentials`.

Errors have a stable public shape:

```json
{
  "error": {
    "code": "invalid_json",
    "message": "Request body must contain valid JSON."
  }
}
```

The status classes are `400` for malformed JSON or tokens, `409` for
incompatible state and battle limits, `413` for size limits, `422` for invalid
teams or choices, and a sanitized `500` for unexpected failures.

### Health

```bash
curl http://localhost:3000/api/v1/health
```

```json
{
  "service": "pfr-battle-server",
  "apiVersion": "v1",
  "engineVersion": "0.11.11",
  "formatVersion": "pfr-gen9-singles-v1"
}
```

### Start a battle

`POST /api/v1/battles` accepts a player and opponent with one to six team
members. This minimal request starts a one-on-one battle:

```bash
curl --request POST http://localhost:3000/api/v1/battles \
  --header 'Content-Type: application/json' \
  --data '{
    "player": {
      "name": "Player",
      "team": [{
        "memberId": "player-pikachu",
        "species": "Pikachu",
        "level": 50,
        "health": 1,
        "moves": ["Thunderbolt", "Quick Attack"]
      }]
    },
    "opponent": {
      "name": "Rival",
      "team": [{
        "memberId": "rival-eevee",
        "species": "Eevee",
        "level": 50,
        "health": 0.75,
        "moves": ["Swift", "Quick Attack"]
      }]
    }
  }'
```

`memberId`, a species-form string, level `1..100`, normalized health in
`0..1`, and one to four move strings are required. Numeric PokéAPI species IDs
are rejected.
Nickname, ability, held item (`item`), nature, gender, IVs, and EVs are optional.
Omitted values default to the species' primary ability, no item, Serious
nature, 31 IVs, and 0 EVs. The service verifies identifiers and wrapper limits
but intentionally does not enforce competitive learnsets or species-level team
legality.

Members whose starting health is zero remain visible as fainted party members
but do not enter the simulator. Each side must still have at least one living
member. A positive health fraction is rounded to integer HP once and that
resolved value is carried by the token for deterministic replay.

### Submit an action

`POST /api/v1/battles/actions` accepts a token plus exactly one nested typed
action. Move slots are one-based:

```bash
curl --request POST http://localhost:3000/api/v1/battles/actions \
  --header 'Content-Type: application/json' \
  --data '{
    "stateToken": "<stateToken from the previous response>",
    "action": {"type": "move", "moveIndex": 1}
  }'
```

A forced or voluntary switch identifies the original caller member ID:

```json
{
  "stateToken": "<stateToken>",
  "action": {"type": "switch", "memberId": "player-pikachu"}
}
```

Forfeit is the server behavior a client may present as Run:

```json
{
  "stateToken": "<stateToken>",
  "action": {"type": "forfeit"}
}
```

An action advances through all required AI-only choices until the player must
choose again or the battle ends. The deterministic AI uniformly chooses an
enabled move and randomly selects a living replacement only when forced; it
never switches voluntarily.

Successful battle responses contain the version fields, battle ID, revision,
phase, filtered protocol events, structured player request, public party
snapshots, and an optional result. A new `stateToken` is returned only while
the phase is `awaiting_player`. Clients select moves and switches from the
structured request and never send raw Pokemon Showdown commands or logs.

## Godot client integration

The Godot game uses the same production base URL in development and release
builds:

```text
https://pfr-locomotion-prototype.vercel.app/api/v1
```

Send JSON with `Content-Type: application/json`. The v1 API uses no cookies,
credentials, authentication headers, or caller-supplied Showdown commands.
Keep `stateToken` opaque and memory-only: it must not enter save data, logs,
presentation state, or scene-owned DTOs.

Only one battle request should be in flight. Retain the exact submitted body
until it succeeds or the session is abandoned. A transport failure, timeout,
or `5xx` is retried with the byte-identical token/action payload; a retry must
not select a new action. After an accepted response, first apply its complete
party snapshots and then replace the current token with the returned token, or
clear it when the phase is `ended`. Although the trusted PvE service can
deterministically replay or fork an older valid token, the Godot client must
never intentionally use that behavior.

Drive choices only from `request`: one-based `moveIndex` values come from
`moves`, and switch actions use only the returned `memberId` options. Response
snapshots—not protocol event text—are authoritative for health, active members,
status, the next request, and the result. Events are a presentation delta and
may be animated before exposing the next request.

Client error handling for v1 is:

| Response | Client behavior |
| --- | --- |
| Network failure, timeout, or `5xx` | Offer Retry with the retained byte-identical request, or Return |
| `422 invalid_action` | Restore the last valid structured choice request |
| Invalid/incompatible token, version mismatch, battle limit, malformed response, or size failure | End the local session and offer Return |

## Extensive battle examples

The examples below use `curl`, Bash, and
[`jq`](https://jqlang.github.io/jq/). Install `jq` with your operating system's
package manager if `jq --version` is not available. Start the server, then
define these helpers once:

```bash
API_BASE="${API_BASE:-http://localhost:3000/api/v1}"

start_battle() {
  curl --silent --show-error \
    --request POST "$API_BASE/battles" \
    --header 'Content-Type: application/json' \
    --data-binary @-
}

post_action() {
  local token="$1"
  local action="$2"

  jq -nc \
    --arg stateToken "$token" \
    --argjson action "$action" \
    '{stateToken: $stateToken, action: $action}' |
    curl --silent --show-error \
      --request POST "$API_BASE/battles/actions" \
      --header 'Content-Type: application/json' \
      --data-binary @-
}
```

The JSON transcripts use readable values such as `<state-token-r0>` in place
of the long encrypted token. They also use a fixed illustrative `battleId` so
the relationship between responses is easy to see. A live server generates a
new UUID and opaque token. Never construct, edit, inspect, or decode a token;
pass it back exactly as returned.

Damage rolls and randomly selected AI choices can vary between separately
created battles. They are deterministic after creation because both simulator
state and AI state travel in the token. The transcripts below were captured
with fixed test seeds, and their teams use guaranteed outcomes where the exact
result matters.

| Example | What it demonstrates |
| --- | --- |
| 1 | Fully expanded start and ended responses |
| 2 | A complete multi-member opponent battle and automatic AI replacement |
| 3 | Voluntary switching by caller `memberId` |
| 4 | A forced player replacement after a knockout |
| 5 | Simultaneous player and AI replacements |
| 6 | Zero-health filtering and reduced-health rounding |
| 7 | Deterministic retry and old-token battle forks |
| 8 | Forfeit and ended-result semantics |
| 9 | A happy-path request-driven client loop |
| 10 | Multi-option deterministic AI choices and a natural opponent win |
| 11 | Invalid team, token, and action responses |

### Example 1: complete one-turn battle, with full responses

This is the smallest complete lifecycle: create the battle, read the move
request, submit the move, and receive an ended response.

```bash
START_RESPONSE="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [{
      "memberId": "aster-mewtwo",
      "species": "Mewtwo",
      "level": 100,
      "health": 1,
      "moves": ["Psychic"]
    }]
  },
  "opponent": {
    "name": "Youngster Ben",
    "team": [{
      "memberId": "ben-magikarp",
      "species": "Magikarp",
      "level": 1,
      "health": 1,
      "moves": ["Splash"]
    }]
  }
}
JSON
)"

printf '%s\n' "$START_RESPONSE" | jq
TOKEN_R0="$(printf '%s' "$START_RESPONSE" | jq -r '.stateToken')"
```

Representative revision-0 response:

```json
{
  "apiVersion": "v1",
  "engineVersion": "0.11.11",
  "formatVersion": "pfr-gen9-singles-v1",
  "battleId": "00000000-0000-4000-8000-000000000101",
  "revision": 0,
  "phase": "awaiting_player",
  "stateToken": "<state-token-r0>",
  "events": [
    "|gametype|singles",
    "|player|p1|Aster||",
    "|player|p2|Youngster Ben||",
    "|gen|9",
    "|tier|pfr-gen9-singles-v1",
    "|",
    "|teamsize|p1|1",
    "|teamsize|p2|1",
    "|start",
    "|switch|p1a: Mewtwo|Mewtwo|353/353",
    "|switch|p2a: Magikarp|Magikarp, L1|100/100",
    "|-ability|p1a: Mewtwo|Pressure",
    "|turn|1"
  ],
  "request": {
    "type": "move",
    "activeMemberId": "aster-mewtwo",
    "moves": [
      {
        "moveIndex": 1,
        "id": "psychic",
        "name": "Psychic",
        "pp": 16,
        "maxPp": 16,
        "disabled": false
      }
    ],
    "switchOptions": []
  },
  "parties": {
    "player": [
      {
        "memberId": "aster-mewtwo",
        "species": "Mewtwo",
        "nickname": "Mewtwo",
        "level": 100,
        "hp": 353,
        "maxHp": 353,
        "normalizedHealth": 1,
        "fainted": false,
        "active": true,
        "status": null,
        "moves": [
          {
            "moveIndex": 1,
            "id": "psychic",
            "name": "Psychic",
            "pp": 16,
            "maxPp": 16
          }
        ]
      }
    ],
    "opponent": [
      {
        "memberId": "ben-magikarp",
        "species": "Magikarp",
        "nickname": "Magikarp",
        "level": 1,
        "hp": 11,
        "maxHp": 11,
        "normalizedHealth": 1,
        "fainted": false,
        "active": true,
        "status": null
      }
    ]
  }
}
```

The opponent's switch event uses Showdown's public percentage scale
(`100/100`), while `parties.opponent` contains the authoritative integer
snapshot (`11/11`). Opponent move lists, requests, and other private protocol
messages are not returned.

Choose slot 1 from `request.moves` and use the token from that same response:

```bash
END_RESPONSE="$(
  post_action "$TOKEN_R0" '{"type":"move","moveIndex":1}'
)"
printf '%s\n' "$END_RESPONSE" | jq
```

Representative revision-1 response:

```json
{
  "apiVersion": "v1",
  "engineVersion": "0.11.11",
  "formatVersion": "pfr-gen9-singles-v1",
  "battleId": "00000000-0000-4000-8000-000000000101",
  "revision": 1,
  "phase": "ended",
  "events": [
    "|",
    "|move|p1a: Mewtwo|Psychic|p2a: Magikarp",
    "|-damage|p2a: Magikarp|0 fnt",
    "|faint|p2a: Magikarp",
    "|",
    "|win|Aster"
  ],
  "request": null,
  "parties": {
    "player": [
      {
        "memberId": "aster-mewtwo",
        "species": "Mewtwo",
        "nickname": "Mewtwo",
        "level": 100,
        "hp": 353,
        "maxHp": 353,
        "normalizedHealth": 1,
        "fainted": false,
        "active": true,
        "status": null,
        "moves": [
          {
            "moveIndex": 1,
            "id": "psychic",
            "name": "Psychic",
            "pp": 15,
            "maxPp": 16
          }
        ]
      }
    ],
    "opponent": [
      {
        "memberId": "ben-magikarp",
        "species": "Magikarp",
        "nickname": "Magikarp",
        "level": 1,
        "hp": 0,
        "maxHp": 11,
        "normalizedHealth": 0,
        "fainted": true,
        "active": true,
        "status": null
      }
    ]
  },
  "result": {
    "winner": "player",
    "reason": "all_pokemon_fainted"
  }
}
```

An ended response has no `stateToken`, has `request: null`, and includes a
`result`. The `events` array is only the new event delta caused by this action;
clients append it to previously received events if they want a full visual log.

### Example 2: complete battle against a two-member opponent team

This example shows a stable decision boundary in action. Mewtwo knocks out the
first opponent. Because only the AI needs to replace it, the same action call
also selects and switches in the next opponent before returning control to the
player.

```bash
DRIVER_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [{
      "memberId": "aster-mewtwo",
      "species": "Mewtwo",
      "level": 100,
      "health": 1,
      "moves": ["Psychic"]
    }]
  },
  "opponent": {
    "name": "Rival",
    "team": [
      {
        "memberId": "rival-magikarp",
        "species": "Magikarp",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      },
      {
        "memberId": "rival-feebas",
        "species": "Feebas",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      }
    ]
  }
}
JSON
)"

DRIVER_TOKEN_R0="$(printf '%s' "$DRIVER_START" | jq -r '.stateToken')"
DRIVER_R1="$(
  post_action "$DRIVER_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"
printf '%s\n' "$DRIVER_R1" | jq '{
  revision,
  phase,
  stateToken,
  events,
  request,
  opponentParty: [
    .parties.opponent[] | {memberId, hp, fainted, active}
  ]
}'
```

This focused projection shows the first action returning another player
decision at revision 1. Its event delta contains both the knockout and the
AI-only replacement:

```json
{
  "revision": 1,
  "phase": "awaiting_player",
  "stateToken": "<driver-state-token-r1>",
  "events": [
    "|",
    "|move|p1a: Mewtwo|Psychic|p2a: Magikarp",
    "|-damage|p2a: Magikarp|0 fnt",
    "|faint|p2a: Magikarp",
    "|",
    "|upkeep",
    "|",
    "|switch|p2a: Feebas|Feebas, L1|100/100",
    "|turn|2"
  ],
  "request": {
    "type": "move",
    "activeMemberId": "aster-mewtwo",
    "moves": [
      {
        "moveIndex": 1,
        "id": "psychic",
        "name": "Psychic",
        "pp": 15,
        "maxPp": 16,
        "disabled": false
      }
    ],
    "switchOptions": []
  },
  "opponentParty": [
    {
      "memberId": "rival-magikarp",
      "hp": 0,
      "fainted": true,
      "active": false
    },
    {
      "memberId": "rival-feebas",
      "hp": 11,
      "fainted": false,
      "active": true
    }
  ]
}
```

The actual response also contains all version, battle, player-party, and full
opponent-party fields. Use its new token for turn 2:

```bash
DRIVER_TOKEN_R1="$(printf '%s' "$DRIVER_R1" | jq -r '.stateToken')"
DRIVER_R2="$(
  post_action "$DRIVER_TOKEN_R1" '{"type":"move","moveIndex":1}'
)"
printf '%s\n' "$DRIVER_R2" |
  jq '{revision, phase, events, request, result, opponent: .parties.opponent}'
```

```json
{
  "revision": 2,
  "phase": "ended",
  "events": [
    "|",
    "|move|p1a: Mewtwo|Psychic|p2a: Feebas",
    "|-damage|p2a: Feebas|0 fnt",
    "|faint|p2a: Feebas",
    "|",
    "|win|Aster"
  ],
  "request": null,
  "result": {
    "winner": "player",
    "reason": "all_pokemon_fainted"
  },
  "opponent": [
    {
      "memberId": "rival-magikarp",
      "species": "Magikarp",
      "nickname": "Magikarp",
      "level": 1,
      "hp": 0,
      "maxHp": 11,
      "normalizedHealth": 0,
      "fainted": true,
      "active": false,
      "status": null
    },
    {
      "memberId": "rival-feebas",
      "species": "Feebas",
      "nickname": "Feebas",
      "level": 1,
      "hp": 0,
      "maxHp": 11,
      "normalizedHealth": 0,
      "fainted": true,
      "active": true,
      "status": null
    }
  ]
}
```

### Example 3: complete battle with a voluntary switch

The first living member is the initial active Pokémon. A voluntary switch is
available only when its `memberId` appears in `request.switchOptions`.

```bash
VOLUNTARY_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [
      {
        "memberId": "aster-pikachu",
        "species": "Pikachu",
        "level": 50,
        "health": 1,
        "moves": ["Quick Attack"]
      },
      {
        "memberId": "aster-bulbasaur",
        "species": "Bulbasaur",
        "level": 50,
        "health": 1,
        "moves": ["Tackle"]
      }
    ]
  },
  "opponent": {
    "name": "Youngster Ben",
    "team": [{
      "memberId": "ben-magikarp",
      "species": "Magikarp",
      "level": 1,
      "health": 1,
      "moves": ["Splash"]
    }]
  }
}
JSON
)"

VOLUNTARY_TOKEN_R0="$(printf '%s' "$VOLUNTARY_START" | jq -r '.stateToken')"
VOLUNTARY_R1="$(
  post_action \
    "$VOLUNTARY_TOKEN_R0" \
    '{"type":"switch","memberId":"aster-bulbasaur"}'
)"

printf '%s\n' "$VOLUNTARY_R1" | jq '{
  revision,
  phase,
  events,
  request,
  player: [.parties.player[] | {memberId, active, hp, maxHp}]
}'
```

```json
{
  "revision": 1,
  "phase": "awaiting_player",
  "events": [
    "|",
    "|switch|p1a: Bulbasaur|Bulbasaur, L50|120/120",
    "|move|p2a: Magikarp|Splash|p2a: Magikarp",
    "|-nothing",
    "|",
    "|upkeep",
    "|turn|2"
  ],
  "request": {
    "type": "move",
    "activeMemberId": "aster-bulbasaur",
    "moves": [
      {
        "moveIndex": 1,
        "id": "tackle",
        "name": "Tackle",
        "pp": 56,
        "maxPp": 56,
        "disabled": false
      }
    ],
    "switchOptions": [
      {
        "memberId": "aster-pikachu"
      }
    ]
  },
  "player": [
    {
      "memberId": "aster-pikachu",
      "active": false,
      "hp": 110,
      "maxHp": 110
    },
    {
      "memberId": "aster-bulbasaur",
      "active": true,
      "hp": 120,
      "maxHp": 120
    }
  ]
}
```

The party remains in caller order even though Showdown internally reorders
slots while switching. Always track party members by `memberId`, not by party
array position, nickname, or protocol ident. Finish the battle with the move
offered for the newly active member:

```bash
VOLUNTARY_TOKEN_R1="$(printf '%s' "$VOLUNTARY_R1" | jq -r '.stateToken')"
VOLUNTARY_R2="$(
  post_action "$VOLUNTARY_TOKEN_R1" '{"type":"move","moveIndex":1}'
)"
printf '%s\n' "$VOLUNTARY_R2" | jq '{revision, phase, events, request, result}'
```

```json
{
  "revision": 2,
  "phase": "ended",
  "events": [
    "|",
    "|move|p1a: Bulbasaur|Tackle|p2a: Magikarp",
    "|-damage|p2a: Magikarp|0 fnt",
    "|faint|p2a: Magikarp",
    "|",
    "|win|Aster"
  ],
  "request": null,
  "result": {
    "winner": "player",
    "reason": "all_pokemon_fainted"
  }
}
```

### Example 4: forced replacement after the active Pokémon faints

Here Magikarp is knocked out before Splash can execute. The service returns a
typed switch request instead of accepting another move.

```bash
FORCED_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [
      {
        "memberId": "aster-magikarp",
        "species": "Magikarp",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      },
      {
        "memberId": "aster-gengar",
        "species": "Gengar",
        "level": 100,
        "health": 1,
        "moves": ["Shadow Ball"]
      }
    ]
  },
  "opponent": {
    "name": "Ace Dana",
    "team": [{
      "memberId": "dana-mewtwo",
      "species": "Mewtwo",
      "level": 50,
      "health": 1,
      "moves": ["Psychic"]
    }]
  }
}
JSON
)"

FORCED_TOKEN_R0="$(printf '%s' "$FORCED_START" | jq -r '.stateToken')"
FORCED_R1="$(
  post_action "$FORCED_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"
printf '%s\n' "$FORCED_R1" | jq '{
  revision,
  phase,
  events,
  request,
  player: [.parties.player[] | {memberId, hp, maxHp, fainted, active, status}]
}'
```

```json
{
  "revision": 1,
  "phase": "awaiting_player",
  "events": [
    "|",
    "|move|p2a: Mewtwo|Psychic|p1a: Magikarp",
    "|-damage|p1a: Magikarp|0 fnt",
    "|faint|p1a: Magikarp",
    "|",
    "|upkeep"
  ],
  "request": {
    "type": "switch",
    "activeMemberId": "aster-magikarp",
    "switchOptions": [
      {
        "memberId": "aster-gengar"
      }
    ]
  },
  "player": [
    {
      "memberId": "aster-magikarp",
      "hp": 0,
      "maxHp": 11,
      "fainted": true,
      "active": true,
      "status": "fnt"
    },
    {
      "memberId": "aster-gengar",
      "hp": 261,
      "maxHp": 261,
      "fainted": false,
      "active": false,
      "status": null
    }
  ]
}
```

Submitting a move with `FORCED_R1`'s token would return `422 invalid_action`
because the current request requires a switch. Select one of the exact
`memberId` values offered by `switchOptions`:

```bash
FORCED_TOKEN_R1="$(printf '%s' "$FORCED_R1" | jq -r '.stateToken')"
FORCED_R2="$(
  post_action \
    "$FORCED_TOKEN_R1" \
    '{"type":"switch","memberId":"aster-gengar"}'
)"
printf '%s\n' "$FORCED_R2" | jq '{revision, phase, events, request}'
```

```json
{
  "revision": 2,
  "phase": "awaiting_player",
  "events": [
    "|",
    "|switch|p1a: Gengar|Gengar|261/261",
    "|turn|2"
  ],
  "request": {
    "type": "move",
    "activeMemberId": "aster-gengar",
    "moves": [
      {
        "moveIndex": 1,
        "id": "shadowball",
        "name": "Shadow Ball",
        "pp": 24,
        "maxPp": 24,
        "disabled": false
      }
    ],
    "switchOptions": []
  }
}
```

A forced replacement does not consume a normal battle turn. Finish this battle
from the new move request:

```bash
FORCED_TOKEN_R2="$(printf '%s' "$FORCED_R2" | jq -r '.stateToken')"
FORCED_R3="$(
  post_action "$FORCED_TOKEN_R2" '{"type":"move","moveIndex":1}'
)"
printf '%s\n' "$FORCED_R3" | jq '{revision, phase, events, request, result}'
```

```json
{
  "revision": 3,
  "phase": "ended",
  "events": [
    "|",
    "|move|p1a: Gengar|Shadow Ball|p2a: Mewtwo",
    "|-supereffective|p2a: Mewtwo",
    "|-damage|p2a: Mewtwo|0 fnt",
    "|faint|p2a: Mewtwo",
    "|",
    "|win|Aster"
  ],
  "request": null,
  "result": {
    "winner": "player",
    "reason": "all_pokemon_fainted"
  }
}
```

### Example 5: simultaneous player and AI replacements

Explosion can faint both active Pokémon at once. The revision-1 token remains
at the shared decision boundary: the response asks only for the player's
replacement, and the AI replacement is selected when that player action is
submitted.

```bash
SIMULTANEOUS_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [
      {
        "memberId": "aster-electrode",
        "species": "Electrode",
        "level": 100,
        "health": 1,
        "moves": ["Explosion"]
      },
      {
        "memberId": "aster-gengar",
        "species": "Gengar",
        "level": 100,
        "health": 1,
        "moves": ["Shadow Ball"]
      }
    ]
  },
  "opponent": {
    "name": "Ace Dana",
    "team": [
      {
        "memberId": "dana-magikarp",
        "species": "Magikarp",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      },
      {
        "memberId": "dana-mewtwo",
        "species": "Mewtwo",
        "level": 50,
        "health": 1,
        "moves": ["Psychic"]
      }
    ]
  }
}
JSON
)"

SIMULTANEOUS_TOKEN_R0="$(
  printf '%s' "$SIMULTANEOUS_START" | jq -r '.stateToken'
)"
SIMULTANEOUS_R1="$(
  post_action "$SIMULTANEOUS_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"
printf '%s\n' "$SIMULTANEOUS_R1" |
  jq '{revision, phase, events, request, parties}'
```

The important portion of revision 1 is:

```json
{
  "revision": 1,
  "phase": "awaiting_player",
  "events": [
    "|",
    "|move|p1a: Electrode|Explosion|p2a: Magikarp",
    "|-damage|p2a: Magikarp|0 fnt",
    "|faint|p1a: Electrode",
    "|faint|p2a: Magikarp",
    "|",
    "|upkeep"
  ],
  "request": {
    "type": "switch",
    "activeMemberId": "aster-electrode",
    "switchOptions": [
      {
        "memberId": "aster-gengar"
      }
    ]
  }
}
```

Submit the player replacement. The AI has only one living replacement in this
example, so both switches appear in the same returned event delta:

```bash
SIMULTANEOUS_TOKEN_R1="$(
  printf '%s' "$SIMULTANEOUS_R1" | jq -r '.stateToken'
)"
SIMULTANEOUS_R2="$(
  post_action \
    "$SIMULTANEOUS_TOKEN_R1" \
    '{"type":"switch","memberId":"aster-gengar"}'
)"
printf '%s\n' "$SIMULTANEOUS_R2" |
  jq '{revision, phase, events, request}'
```

```json
{
  "revision": 2,
  "phase": "awaiting_player",
  "events": [
    "|",
    "|switch|p1a: Gengar|Gengar|261/261",
    "|switch|p2a: Mewtwo|Mewtwo, L50|100/100",
    "|-ability|p2a: Mewtwo|Pressure",
    "|turn|2"
  ],
  "request": {
    "type": "move",
    "activeMemberId": "aster-gengar",
    "moves": [
      {
        "moveIndex": 1,
        "id": "shadowball",
        "name": "Shadow Ball",
        "pp": 24,
        "maxPp": 24,
        "disabled": false
      }
    ],
    "switchOptions": []
  }
}
```

The next Shadow Ball ends this example at revision 3 with
`winner: "player"`. Notice that the client never chooses an opponent switch
and never receives the opponent's private request.

### Example 6: zero and reduced starting health

This example models a party arriving from the overworld with one already
fainted member and two partially or fully healthy members. `health` is always
normalized input in the range `0..1`, not an HP integer.

```bash
HEALTH_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [
      {
        "memberId": "fainted-bulbasaur",
        "species": "Bulbasaur",
        "level": 50,
        "health": 0,
        "moves": ["Tackle"]
      },
      {
        "memberId": "hurt-pikachu",
        "species": "Pikachu",
        "level": 50,
        "health": 0.503,
        "moves": ["Thunderbolt"]
      },
      {
        "memberId": "healthy-charmander",
        "species": "Charmander",
        "level": 50,
        "health": 1,
        "moves": ["Ember"]
      }
    ]
  },
  "opponent": {
    "name": "Rival",
    "team": [{
      "memberId": "hurt-opponent",
      "species": "Bulbasaur",
      "level": 50,
      "health": 0.25,
      "moves": ["Tackle"]
    }]
  }
}
JSON
)"

printf '%s\n' "$HEALTH_START" | jq '{events, request, parties}'
```

```json
{
  "events": [
    "|gametype|singles",
    "|player|p1|Aster||",
    "|player|p2|Rival||",
    "|gen|9",
    "|tier|pfr-gen9-singles-v1",
    "|",
    "|teamsize|p1|2",
    "|teamsize|p2|1",
    "|start",
    "|switch|p1a: Pikachu|Pikachu, L50|55/110",
    "|switch|p2a: Bulbasaur|Bulbasaur, L50|25/100",
    "|turn|1"
  ],
  "request": {
    "type": "move",
    "activeMemberId": "hurt-pikachu",
    "moves": [
      {
        "moveIndex": 1,
        "id": "thunderbolt",
        "name": "Thunderbolt",
        "pp": 24,
        "maxPp": 24,
        "disabled": false
      }
    ],
    "switchOptions": [
      {
        "memberId": "healthy-charmander"
      }
    ]
  },
  "parties": {
    "player": [
      {
        "memberId": "fainted-bulbasaur",
        "species": "Bulbasaur",
        "nickname": "Bulbasaur",
        "level": 50,
        "hp": 0,
        "maxHp": 120,
        "normalizedHealth": 0,
        "fainted": true,
        "active": false,
        "status": null,
        "moves": [
          {
            "moveIndex": 1,
            "id": "tackle",
            "name": "Tackle",
            "pp": 56,
            "maxPp": 56
          }
        ]
      },
      {
        "memberId": "hurt-pikachu",
        "species": "Pikachu",
        "nickname": "Pikachu",
        "level": 50,
        "hp": 55,
        "maxHp": 110,
        "normalizedHealth": 0.5,
        "fainted": false,
        "active": true,
        "status": null,
        "moves": [
          {
            "moveIndex": 1,
            "id": "thunderbolt",
            "name": "Thunderbolt",
            "pp": 24,
            "maxPp": 24
          }
        ]
      },
      {
        "memberId": "healthy-charmander",
        "species": "Charmander",
        "nickname": "Charmander",
        "level": 50,
        "hp": 114,
        "maxHp": 114,
        "normalizedHealth": 1,
        "fainted": false,
        "active": false,
        "status": null,
        "moves": [
          {
            "moveIndex": 1,
            "id": "ember",
            "name": "Ember",
            "pp": 40,
            "maxPp": 40
          }
        ]
      }
    ],
    "opponent": [
      {
        "memberId": "hurt-opponent",
        "species": "Bulbasaur",
        "nickname": "Bulbasaur",
        "level": 50,
        "hp": 30,
        "maxHp": 120,
        "normalizedHealth": 0.25,
        "fainted": false,
        "active": true,
        "status": null
      }
    ]
  }
}
```

Important details in this response:

- `teamsize|p1|2` counts only the two living members passed to Showdown, while
  `parties.player` retains all three caller members.
- `fainted-bulbasaur` cannot become active and is absent from switch options.
- `0.503 * 110` rounds once to 55 HP. The returned normalized value is therefore
  the resolved `55 / 110`, or `0.5`, rather than the original `0.503`.
- The opponent's 30/120 HP is rendered as public `25/100` in the event stream.
- The first living member, `hurt-pikachu`, becomes active because the
  zero-health member was filtered before battle construction.

### Example 7: retrying an action and forking from an old token

The server has no consumed-token registry. Keep the revision-0 token in this
example, submit Tackle twice, then submit Growl from that same old token.

```bash
FORK_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [{
      "memberId": "aster-pikachu",
      "species": "Pikachu",
      "level": 50,
      "health": 1,
      "moves": ["Tackle", "Growl"]
    }]
  },
  "opponent": {
    "name": "Rival",
    "team": [{
      "memberId": "rival-magikarp",
      "species": "Magikarp",
      "level": 50,
      "health": 1,
      "moves": ["Splash"]
    }]
  }
}
JSON
)"

FORK_TOKEN_R0="$(printf '%s' "$FORK_START" | jq -r '.stateToken')"

TACKLE_A="$(
  post_action "$FORK_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"
TACKLE_B="$(
  post_action "$FORK_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"

diff -u \
  <(printf '%s' "$TACKLE_A" | jq -S 'del(.stateToken)') \
  <(printf '%s' "$TACKLE_B" | jq -S 'del(.stateToken)')

GROWL_BRANCH="$(
  post_action "$FORK_TOKEN_R0" '{"type":"move","moveIndex":2}'
)"

printf '%s\n' "$TACKLE_A" |
  jq '{battleId, revision, phase, events, playerMoves: .parties.player[0].moves}'
printf '%s\n' "$GROWL_BRANCH" |
  jq '{battleId, revision, phase, events, playerMoves: .parties.player[0].moves}'
```

The `diff` prints nothing: after removing `stateToken`, both Tackle responses
have the same battle ID, revision, events, request, HP, PP, AI decision, and
outcome. The two returned token strings themselves should be treated as
unrelated opaque envelopes because sealing uses a fresh AES-GCM IV.

Both Tackle and Growl branches have the original `battleId` and `revision: 1`,
but they carry different event and battle state:

```json
{
  "tackleBranch": {
    "revision": 1,
    "events": [
      "|",
      "|move|p1a: Pikachu|Tackle|p2a: Magikarp",
      "|-damage|p2a: Magikarp|84/100",
      "|move|p2a: Magikarp|Splash|p2a: Magikarp",
      "|-nothing",
      "|",
      "|upkeep",
      "|turn|2"
    ],
    "movePp": {
      "tackle": 55,
      "growl": 64
    }
  },
  "growlBranch": {
    "revision": 1,
    "events": [
      "|",
      "|move|p1a: Pikachu|Growl|p2a: Magikarp",
      "|-unboost|p2a: Magikarp|atk|1",
      "|move|p2a: Magikarp|Splash|p2a: Magikarp",
      "|-nothing",
      "|",
      "|upkeep",
      "|turn|2"
    ],
    "movePp": {
      "tackle": 56,
      "growl": 63
    }
  }
}
```

The exact Tackle damage in a newly created live battle can differ from the
captured transcript, but retrying that live battle's token reproduces its
original roll. Neither branch invalidates the revision-0 token or the other
branch.

### Example 8: forfeit from any player decision

Forfeit is legal from either a move or forced-switch decision. It ends the
battle immediately without asking the AI to choose and without changing party
HP. This standalone example creates a battle and forfeits at revision 0:

```bash
FORFEIT_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [{
      "memberId": "aster-pikachu",
      "species": "Pikachu",
      "level": 50,
      "health": 1,
      "moves": ["Thunderbolt"]
    }]
  },
  "opponent": {
    "name": "Rival",
    "team": [{
      "memberId": "rival-eevee",
      "species": "Eevee",
      "level": 50,
      "health": 1,
      "moves": ["Swift"]
    }]
  }
}
JSON
)"

FORFEIT_TOKEN_R0="$(printf '%s' "$FORFEIT_START" | jq -r '.stateToken')"
FORFEIT_R1="$(post_action "$FORFEIT_TOKEN_R0" '{"type":"forfeit"}')"
printf '%s\n' "$FORFEIT_R1" | jq
```

```json
{
  "apiVersion": "v1",
  "engineVersion": "0.11.11",
  "formatVersion": "pfr-gen9-singles-v1",
  "battleId": "00000000-0000-4000-8000-000000000105",
  "revision": 1,
  "phase": "ended",
  "events": [
    "|",
    "|win|Rival"
  ],
  "request": null,
  "parties": {
    "player": [
      {
        "memberId": "aster-pikachu",
        "species": "Pikachu",
        "nickname": "Pikachu",
        "level": 50,
        "hp": 110,
        "maxHp": 110,
        "normalizedHealth": 1,
        "fainted": false,
        "active": true,
        "status": null,
        "moves": [
          {
            "moveIndex": 1,
            "id": "thunderbolt",
            "name": "Thunderbolt",
            "pp": 24,
            "maxPp": 24
          }
        ]
      }
    ],
    "opponent": [
      {
        "memberId": "rival-eevee",
        "species": "Eevee",
        "nickname": "Eevee",
        "level": 50,
        "hp": 130,
        "maxHp": 130,
        "normalizedHealth": 1,
        "fainted": false,
        "active": true,
        "status": null
      }
    ]
  },
  "result": {
    "winner": "opponent",
    "reason": "forfeit"
  }
}
```

As with every ended response, there is no new state token. A Godot client can
map a Run control to this action without adding escape mechanics to the server.

### Example 9: a happy-path request-driven client loop

A client should branch on `request.type` and choose only from the options in
that request. While the phase remains `awaiting_player`, it replaces its token
with the one in the newest successful response; it stops when the phase is
`ended`. This Bash example plays the supplied battle forward by selecting the
first enabled move or first required replacement, and finishes in two moves.

```bash
AUTO_RESPONSE="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [{
      "memberId": "aster-mewtwo",
      "species": "Mewtwo",
      "level": 100,
      "health": 1,
      "moves": ["Psychic"]
    }]
  },
  "opponent": {
    "name": "Rival",
    "team": [
      {
        "memberId": "rival-magikarp",
        "species": "Magikarp",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      },
      {
        "memberId": "rival-feebas",
        "species": "Feebas",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      }
    ]
  }
}
JSON
)"

for ((action_count = 0; action_count < 600; action_count += 1)); do
  printf '%s\n' "$AUTO_RESPONSE" |
    jq '{revision, phase, events, request, result}'

  if printf '%s' "$AUTO_RESPONSE" | jq -e 'has("error")' >/dev/null; then
    printf 'battle request failed: %s\n' "$AUTO_RESPONSE" >&2
    exit 1
  fi

  if [[ "$(printf '%s' "$AUTO_RESPONSE" | jq -r '.phase')" == "ended" ]]; then
    break
  fi

  AUTO_TOKEN="$(printf '%s' "$AUTO_RESPONSE" | jq -r '.stateToken')"
  AUTO_ACTION="$(printf '%s' "$AUTO_RESPONSE" | jq -c '
    if .request.type == "move" then
      ([.request.moves[] | select(.disabled == false)] | first) as $move
      | {type: "move", moveIndex: $move.moveIndex}
    elif .request.type == "switch" then
      {type: "switch", memberId: .request.switchOptions[0].memberId}
    else
      error("unsupported player request")
    end
  ')"

  AUTO_RESPONSE="$(post_action "$AUTO_TOKEN" "$AUTO_ACTION")"
done

if [[ "$(printf '%s' "$AUTO_RESPONSE" | jq -r '.phase')" != "ended" ]]; then
  printf 'example client exceeded its local action guard\n' >&2
  exit 1
fi
```

The loop observes revisions `0`, `1`, and `2`. Revision 1 already includes the
AI's forced switch to Feebas, as shown in Example 2. A real UI pauses where this
sample selects an action, renders `events`, and lets the player choose from the
structured request. It should never parse protocol lines to decide which move
or switch payload to send. Production clients should also inspect every HTTP
status before parsing a success response; this compact helper prints response
bodies but does not expose curl's status code.

### Example 10: deterministic AI choices and a natural opponent win

The opponent may have several enabled moves. The AI samples them uniformly
using the independent PRNG stored in the token. Both opponent moves below are
guaranteed to knock out the level-1 Magikarp, but the captured fixed-seed run
selected Psychic:

```bash
AI_MOVE_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [{
      "memberId": "aster-magikarp",
      "species": "Magikarp",
      "level": 1,
      "health": 1,
      "moves": ["Splash"]
    }]
  },
  "opponent": {
    "name": "Champion Nova",
    "team": [{
      "memberId": "nova-mewtwo",
      "species": "Mewtwo",
      "level": 100,
      "health": 1,
      "moves": ["Psychic", "Psystrike"]
    }]
  }
}
JSON
)"

AI_MOVE_TOKEN_R0="$(printf '%s' "$AI_MOVE_START" | jq -r '.stateToken')"
AI_MOVE_R1="$(
  post_action "$AI_MOVE_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"
AI_MOVE_RETRY="$(
  post_action "$AI_MOVE_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"

diff -u \
  <(printf '%s' "$AI_MOVE_R1" | jq -S 'del(.stateToken)') \
  <(printf '%s' "$AI_MOVE_RETRY" | jq -S 'del(.stateToken)')
printf '%s\n' "$AI_MOVE_R1" | jq
```

```json
{
  "apiVersion": "v1",
  "engineVersion": "0.11.11",
  "formatVersion": "pfr-gen9-singles-v1",
  "battleId": "00000000-0000-4000-8000-000000000110",
  "revision": 1,
  "phase": "ended",
  "events": [
    "|",
    "|move|p2a: Mewtwo|Psychic|p1a: Magikarp",
    "|-damage|p1a: Magikarp|0 fnt",
    "|faint|p1a: Magikarp",
    "|",
    "|win|Champion Nova"
  ],
  "request": null,
  "parties": {
    "player": [
      {
        "memberId": "aster-magikarp",
        "species": "Magikarp",
        "nickname": "Magikarp",
        "level": 1,
        "hp": 0,
        "maxHp": 11,
        "normalizedHealth": 0,
        "fainted": true,
        "active": true,
        "status": null,
        "moves": [
          {
            "moveIndex": 1,
            "id": "splash",
            "name": "Splash",
            "pp": 64,
            "maxPp": 64
          }
        ]
      }
    ],
    "opponent": [
      {
        "memberId": "nova-mewtwo",
        "species": "Mewtwo",
        "nickname": "Mewtwo",
        "level": 100,
        "hp": 353,
        "maxHp": 353,
        "normalizedHealth": 1,
        "fainted": false,
        "active": true,
        "status": null
      }
    ]
  },
  "result": {
    "winner": "opponent",
    "reason": "all_pokemon_fainted"
  }
}
```

The player-selected Splash never executes because Mewtwo is faster. Retrying
the same token/action selects the same AI move and returns the same semantic
response, as demonstrated by the empty `diff`. A separately created battle can
select Psystrike instead.

Forced AI replacements use the same rule. This opponent has two living bench
members after its lead faints:

```bash
AI_SWITCH_START="$(start_battle <<'JSON'
{
  "player": {
    "name": "Aster",
    "team": [{
      "memberId": "aster-mewtwo",
      "species": "Mewtwo",
      "level": 100,
      "health": 1,
      "moves": ["Psychic"]
    }]
  },
  "opponent": {
    "name": "Collector Rowan",
    "team": [
      {
        "memberId": "rowan-magikarp",
        "species": "Magikarp",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      },
      {
        "memberId": "rowan-feebas",
        "species": "Feebas",
        "level": 1,
        "health": 1,
        "moves": ["Splash"]
      },
      {
        "memberId": "rowan-caterpie",
        "species": "Caterpie",
        "level": 1,
        "health": 1,
        "moves": ["Tackle"]
      }
    ]
  }
}
JSON
)"

AI_SWITCH_TOKEN_R0="$(printf '%s' "$AI_SWITCH_START" | jq -r '.stateToken')"
AI_SWITCH_R1="$(
  post_action "$AI_SWITCH_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"
AI_SWITCH_RETRY="$(
  post_action "$AI_SWITCH_TOKEN_R0" '{"type":"move","moveIndex":1}'
)"

diff -u \
  <(printf '%s' "$AI_SWITCH_R1" | jq -S 'del(.stateToken)') \
  <(printf '%s' "$AI_SWITCH_RETRY" | jq -S 'del(.stateToken)')
printf '%s\n' "$AI_SWITCH_R1" | jq '{
  revision,
  phase,
  events,
  opponent: [
    .parties.opponent[] | {memberId, hp, maxHp, fainted, active}
  ]
}'
```

```json
{
  "revision": 1,
  "phase": "awaiting_player",
  "events": [
    "|",
    "|move|p1a: Mewtwo|Psychic|p2a: Magikarp",
    "|-damage|p2a: Magikarp|0 fnt",
    "|faint|p2a: Magikarp",
    "|",
    "|upkeep",
    "|",
    "|switch|p2a: Feebas|Feebas, L1|100/100",
    "|turn|2"
  ],
  "opponent": [
    {
      "memberId": "rowan-magikarp",
      "hp": 0,
      "maxHp": 11,
      "fainted": true,
      "active": false
    },
    {
      "memberId": "rowan-feebas",
      "hp": 11,
      "maxHp": 11,
      "fainted": false,
      "active": true
    },
    {
      "memberId": "rowan-caterpie",
      "hp": 12,
      "maxHp": 12,
      "fainted": false,
      "active": false
    }
  ]
}
```

The captured seed selects Feebas; a fresh battle can select Caterpie. A retry
from `AI_SWITCH_TOKEN_R0` repeats the original selection. The AI never makes a
voluntary switch.

`result.winner` is the closed union `"player" | "opponent" | "tie"`. The
`"tie"` value is reserved for a tie reported by the Showdown engine and must be
handled as an ended result. Do not infer a tie merely because both final party
snapshots have zero HP: Showdown's self-KO rules can award the battle to one
side.

### Example 11: representative invalid requests and actions

An action must match the current token's structured request. For example,
submitting a move with the forced-switch token from Example 4 returns:

```bash
post_action "$FORCED_TOKEN_R1" '{"type":"move","moveIndex":1}' | jq
```

```json
{
  "error": {
    "code": "invalid_action",
    "message": "A replacement must be selected"
  }
}
```

The HTTP status is `422`. Selecting a member that is not in the current
`switchOptions` is also `422 invalid_action`. A token that is truncated,
corrupt, or encrypted under another key is malformed state:

```bash
post_action 'not-a-token' '{"type":"forfeit"}' | jq
```

```json
{
  "error": {
    "code": "invalid_state_token",
    "message": "Invalid state token"
  }
}
```

That response has status `400`. Numeric PokéAPI IDs are team validation errors,
even when provided as strings:

```json
{
  "error": {
    "code": "invalid_team",
    "message": "Invalid team",
    "details": [
      {
        "path": "player.team.0.species",
        "message": "Species must be a name, not a numeric PokéAPI ID"
      }
    ]
  }
}
```

That response has status `422`. Other common cases are:

| Status | Code | Typical cause |
| --- | --- | --- |
| `400` | `invalid_json` | Empty, truncated, or syntactically invalid JSON |
| `400` | `invalid_request` | Missing or extra top-level request fields |
| `400` | `invalid_state_token` | Corrupt or unreadable token |
| `409` | `incompatible_state_token` | Token schema, API, engine, format, log, or PRNG state is incompatible |
| `409` | `battle_turn_limit_exceeded` | Reconstructed battle is beyond turn 500 |
| `409` | `battle_limit_exceeded` | Internal per-action AI decision guard or revision limit was exceeded |
| `413` | `request_too_large` | HTTP request body is larger than 128 KiB |
| `413` | `state_token_too_large` | A compact token expands past the decoded-state cap, or new state cannot be sealed within the cap |
| `422` | `invalid_team` | Invalid identifiers, limits, duplicate member IDs, or no living members |
| `422` | `invalid_action` | Action is unavailable at the token's current decision |
| `500` | `internal_error` | Sanitized unexpected server or simulator failure |

Validation errors can include safe `details`. A `500` response never exposes
configuration, token-key, stack, or simulator internals.

An action body containing an encoded token that is itself larger than 128 KiB
is rejected earlier as `request_too_large`, because the enclosing HTTP body has
already crossed the same 128 KiB limit.

## Format and operational limits

The fixed `pfr-gen9-singles-v1` format is derived from Gen 9 Custom Game. It is
singles, has no Team Preview or choice cancellation, accepts one to six living
members per side and one to four moves per member, and runs Showdown with debug
output disabled.

- Request bodies and state tokens are capped at 128 KiB.
- Battles are capped at 500 turns.
- Only player-visible (`p1`) protocol events are returned; timestamp lines and
  opponent-private requests or team details are omitted.
- Starting status/PP, revival of initially fainted members, Bag, capture,
  escape odds, XP, rewards, PvP, and authentication are outside v1.

Reusing an older valid token is intentionally allowed. Retrying the same token
and action reproduces the same result, while a different action forks the
battle from that decision. This is accepted for the trusted PvE client. A key,
API schema, format, or engine-version change invalidates active tokens.

## Vercel deployment

Create a Vercel project with **Root Directory** set to `battle_server`. Add
separate random base64-encoded 32-byte `BATTLE_STATE_KEY` values for Production
and Preview, using the platform's secret-entry workflow so neither value is
printed, written to a repository file, or copied into logs. Redeploy after the
variables are set. Leave framework detection set to Next.js. `package.json`
pins the runtime to Node `24.x`; see Vercel's
[supported Node.js versions](https://vercel.com/docs/functions/runtimes/node-js/node-js-versions).

Deploy through the repository's Git integration rather than a CLI source
upload of the whole game repository. Git deployment honors the configured Root
Directory and avoids the Hobby plan's source-upload ceiling; see
[Vercel limits](https://vercel.com/docs/limits).

Pokemon Showdown is externalized from the Next server bundle. The battle route
traces explicitly include its compiled `dist/sim`, `dist/lib`,
`dist/config/formats.js`, and `dist/data` runtime files. The current lockfile's
local production trace is 100.88 MiB uncompressed per battle route. That
conservative measurement is below Vercel's 250 MB
[Node.js function limit](https://vercel.com/docs/functions/limitations). The
generated trace and preview deployment must still be rechecked after every
engine or dependency change.

### Production diagnostics and troubleshooting

Unexpected `500` responses remain sanitized for callers. The server emits one
diagnostic object containing exactly `route`, `status`, internal `code`, and a
frame-only `stack`. It never logs request bodies, state tokens, teams,
environment values, or encryption keys. In particular, a missing or malformed
`BATTLE_STATE_KEY` is logged only as the internal code
`server_configuration_error`; the response remains the generic
`500 internal_error` shape.

The Next.js header policy applies wildcard CORS and `Cache-Control: no-store`
across `/api/v1/**`, including framework-generated responses such as
`405 Method Not Allowed`. Known routes override the global method list with
their exact `GET` or `POST` plus `OPTIONS` policy. No response sends
`Access-Control-Allow-Credentials`.

For an unexpected production failure:

1. Check `/api/v1/health` and record its public version fields.
2. Filter runtime logs by route, status, and internal code. Do not add body or
   token logging while investigating.
3. For `server_configuration_error`, verify that the affected Vercel
   environment has its own 32-byte key and that it was redeployed after the
   variable changed.
4. For `simulator_error` or `invalid_battle_state`, reproduce with safe local
   fixtures; never copy a live token or team into an issue or log.
5. After a Git-backed deployment becomes ready, repeat health, CORS, battle,
   retry, forfeit, and natural-completion smoke tests and confirm that no new
   `500` diagnostics appeared.

## Verification

Run the complete local gate:

```bash
npm run lint
npm run typecheck
npm test
npm run build
npm run verify:build
```

The Vitest suite starts an actual local Next.js server to cover successful,
application-error, `OPTIONS`, and framework-generated `405` responses. This is
separate from direct Route Handler tests so the `next.config.ts` header layer is
also exercised.

`npm run verify:build` inspects both battle-route `.nft.json` files, resolves
and deduplicates their traced paths, confirms required Showdown runtime trees
are present, rejects server/tool/translation trees, and applies a conservative
250 MiB uncompressed local ceiling. On a Vercel preview, confirm the platform's
reported function size and measure cold-start memory, then smoke-test health,
battle creation, a move, a voluntary switch, a forced replacement, forfeit,
and play-through to an ended response. Repeat the same token/action once to
verify deterministic replay.
