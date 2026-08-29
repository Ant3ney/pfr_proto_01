# Stateless PvE Battle Server

Read this document for work inside [`battle_server/`](../../battle_server/) or
when reasoning about the future Godot HTTP boundary. It records verified server
contracts; inspect the current implementation and tests before changing them.

## Ownership and state boundary

[`src/battle/service.ts`](../../battle_server/src/battle/service.ts) is the
framework-neutral entrypoint. Next Route Handlers only enforce HTTP body limits
and translate results or [`ServiceError`](../../battle_server/src/battle/errors.ts)
instances into responses. The service has no database, battle registry, user
session, or mutable process-local battle state.

An awaiting response carries all resumable state in an authenticated,
compressed AES-256-GCM token. The token contains canonical teams, versions,
battle ID and revision, resolved starting HP, external member mappings, the
canonical Showdown input log, and the independent AI PRNG state. A token is
issued only at a stable player decision boundary and is omitted after battle
end. Old valid tokens may intentionally be retried or forked.

`BATTLE_STATE_KEY` must decode to exactly 32 bytes. Changing that key, the token
schema, API version, format version, or engine version invalidates active
tokens. Never add secrets or decrypted tokens to AI Context, logs, fixtures, or
source control.

## Pinned Showdown adapter

The runtime dependency is the published `pokemon-showdown@0.11.11`, not the
newer local `battle_server/core/` reference checkout. The checkout is excluded
from Git, TypeScript, and ESLint and is not present in a fresh clone.

[`src/battle/showdown.ts`](../../battle_server/src/battle/showdown.ts) uses only
deep imports for `Battle`, `extractChannelMessages`, `Dex`, `Format`,
`TeamValidator`, `Teams`, and `PRNG`. Do not import the package root,
`sim/index`, `BattleStream`, serialized Battle internals, or anything under
Showdown's server tree.

Every construction and replay creates a fresh Gen 9 Custom Game-derived
`Format`. It is singles with direct 1–6 team, 1–4 move, and level 1–100 limits;
Team Preview and Cancel Mod are absent and debug mode is false. Wrapper
canonicalization checks identifier existence and defaults, while the format
deliberately does not impose competitive learnset or species legality.

Replay accepts only the adapter's regenerated start/player prefix and its
narrow committed `p1`/`p2` move-or-switch record grammar. It reconstructs from
canonical token fields, feeds choices synchronously through `Battle.choose`,
and finally requires Showdown's regenerated `inputLog` to match the token
exactly. Raw client Showdown commands or logs are never accepted.

## HP and member identity lifecycle

Health-zero members remain in canonical response rosters but are removed before
Showdown validation and simulation; each side must retain one living member.
Positive normalized health is resolved with nearest-integer rounding and a
minimum of one HP only after Showdown calculates max HP. The fresh format's
`onBegin` applies that value before initial switches and requests, and replay
uses the stored integer rather than resolving the fraction again.

Caller `memberId` values never enter Showdown sets or protocol identifiers.
The adapter maps the initial Pokemon objects to member IDs in a request-local
`WeakMap` during `onBegin`. This object-identity mapping is required because
Showdown reorders `side.pokemon` and changes `.position` during switches; a
persistent positional map silently assigns the wrong member IDs after the
first replacement.

## Decision and visibility contract

An action applies the player's typed move, switch, or forfeit, then advances
only required AI choices until the player must choose again or the battle ends.
The AI uniformly samples enabled moves and only selects a party member for a
forced replacement or an in-battle revival target. Its PRNG is separate from
the simulator PRNG, so retries do not perturb damage, speed ties, or effects.

Protocol output is filtered through Showdown channel `p1`; timestamp lines and
opponent-private split messages or requests are never returned. Structured
requests translate move slots and switch targets into API indices and caller
member IDs. Player party snapshots include move PP, while opponent snapshots
omit move, ability, and item details. Every constructed Battle is destroyed in
a `finally` block.

Results use the side object passed to Showdown's `Battle.win`, not remaining
party counts or trainer-name comparison. This preserves Showdown's self-KO
ruling when both sides reach zero living members and remains unambiguous when
the caller gives both trainers the same name.

## Deployment and regression checks

[`next.config.ts`](../../battle_server/next.config.ts) externalizes Showdown and
explicitly traces its compiled simulator, library, format configuration, and
data runtime files for both battle routes. Keep the patterns narrow, inspect
both generated `.nft.json` files after every dependency or engine change, and
verify the uncompressed function remains below Vercel's limit. With the current
lockfile, the local production trace for each battle route is 100.88 MiB and
contains none of Showdown's server, tool, or translation trees; a Vercel
preview remains the authoritative deployment measurement.

Run the local gate from `battle_server/`:

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

Regression coverage must preserve deterministic reconstruction, reduced
starting HP timing, voluntary and forced switching with stable member IDs,
simultaneous decisions, knockout and forfeit results, token corruption and
version errors, p1-only event privacy, HTTP limits, CORS, and no-store headers.
Engine upgrades are explicit changes and require replay fixtures to be
regenerated and reverified; copying behavior from the local newer checkout is
not a valid upgrade path.

Godot collection/trainer schemas and battle UI networking do not yet implement
this REST contract. Keep client schema, retry/UI behavior, and return-to-world
work as a separate change.
