# Optional Cloud Save and Conflict Resolution

Read this document when changing the player-selected Save ID, background cloud
sync, offline conflict resolution, the Atlas document, or the Netlify
`/api/cloud-save` function. Check both local-save validation and the pure Node
resolver before changing the protocol.

## Trust boundary and deployment

[`CloudSaveSync.gd`](../../rnd/save/CloudSaveSync.gd) is the optional Godot
client and [`cloud-save.mjs`](../../netlify/functions/cloud-save.mjs) is the
only MongoDB boundary. A Web export calls the same-origin `/api/cloud-save`
path. Native development and release builds default to the linked
`https://pfr-early-alpha.netlify.app/api/cloud-save` function, so running the
project from the Godot editor requires no hidden launch variable. Developers
may still replace it with `PFR_CLOUD_SAVE_ENDPOINT` or the script's endpoint
override. Non-local endpoints must use HTTPS. The public function URL is safe
to ship; the game never contains an Atlas username, password, URI, or pepper.

The Netlify function reads these runtime variables. Configure them as
production values in the Netlify UI or CLI, use Functions-only scope when the
site plan supports granular scopes, and mark the URI and pepper as secrets:

- `MONGODB_URI`: the rotated Atlas connection string.
- `MONGODB_DATABASE`: optional; defaults to `pfr_locomotion`.
- `CLOUD_SAVE_PEPPER`: a stable independent random secret of at least 32
  characters.

The linked deployment currently stores the URI and pepper as production
Netlify secrets. Its plan does not provide granular environment scopes, so
Netlify exposes those secrets to its build, function, and runtime processes;
the build pipeline must continue proving that none enter the published files.
Never put real values in `netlify.toml`, `.env.example`, Godot project settings,
AI Context, source, tests, logs, or the published Web directory. The function
fails closed with `cloud_save_not_configured` when the URI or pepper is absent.
It reuses one module-scope `MongoClient` pool, caps requests at 2 MiB, performs
optimistic compare-and-swap writes, accepts JSON requests only, returns
`no-store` JSON, and has a per-IP and-domain rate limit. Atlas documents use an
HMAC-SHA-256 lookup key; they do not store the raw Save ID.

## Player linkage and offline behavior

The player menu's `Cloud Save` overlay makes this feature explicitly optional.
A Save ID is 12–128 printable characters and acts as the profile's password:
anyone who knows it can load that save. The field is masked by default. `Opt
Out` clears the local ID and cloud linkage without touching the ordinary save.
On touchscreen Web builds, the field's press handler explicitly enters edit
mode and calls `DisplayServer.virtual_keyboard_show()` during the gesture; do
not rely only on a prior programmatic `grab_focus()`, which a mobile browser can
accept without opening its keyboard.
The local linkage file is `user://pfr_cloud_sync.json`; it stores the enabled
flag, raw player-entered ID, random device ID, reset epoch, last cloud revision,
base section fingerprints, and last successful-sync time. It is never uploaded
as part of the progression payload.

Portable JSON export contains only the same schema-5 progression payload sent
under the protocol request's `payload` field; it never contains this linkage
file or any of its Save ID/device/revision fields. Manual JSON import preserves
the current linkage and reset epoch, validates through `ProgressionAutosave`,
re-timestamps each imported section as a new local edit, checkpoints it, and
queues the ordinary sync path. Consequently an import during an in-flight
request receives the same local-change rebase protection as gameplay edits,
and first-time linking still obeys the existing-cloud-pull rule.

Local `ProgressionAutosave` remains authoritative while offline. Schema 5
stores a `saved_at_ms` clock and independent timestamps for `profile`,
`collection`, `move_learning`, `stretch`, and `world`. Cloud sync is debounced
after disk checkpoints, polls every 45 seconds for another device's changes,
and retries failures from 5 seconds up to 5 minutes. Network or server failure
does not block gameplay or local writes. A local section changed while an HTTP
request is in flight is rebased onto the response and sent in the next pass,
rather than being overwritten. That pass explicitly marks the section as
divergent so the server performs its intelligent conflict merge even when the
cloud revision itself did not advance during the request. A response received
during a battle, battle return, scene transfer, or starter handoff waits locally
and applies only after those transition-sensitive owners are idle.

## Resolver order

Protocol version 1 resolves a single Atlas document in this order:

1. A missing document is created from the local schema-5 payload.
2. First-time linking to an existing ID pulls the cloud document. It does not
   overwrite an established save with an unrelated newly linked profile.
3. A larger reset epoch replaces the older profile. A smaller epoch always
   loses, preventing an offline pre-reset device from resurrecting deleted
   progress.
4. At the same epoch, per-section cloud revisions establish causal order. If
   only one device changed a section since the common base, that change wins.
5. If both changed the same section, the newer validated section timestamp is
   preferred, with a stable device-ID tie break. `profile`, move-choice state,
   and world pose use that winner directly. Collection conflicts union unique
   PCL IDs into PC storage, retain the preferred party/moves/health/held item,
   and never reduce already-earned XP or level. Stretch conflicts take the
   newer balance, inventory, and active-run state while unioning one-time
   gifts, badges, contiguous completed routes, Champion completion, and
   defeated IDs for the same active run.

The resolver clamps a client timestamp more than five minutes ahead of server
time. The server reconstructs save metadata after a merge and increments one
document revision atomically. Cloud results still pass the same Godot profile,
collection, move-learning, and Stretch validators before replacing in-memory
or local disk state.

## Reset and verification

The existing three-warning `RESET FOREVER` flow also advances the linked cloud
epoch. No empty profile is uploaded while the starter picker is pending. The
new starter checkpoint then replaces the previous cloud generation; an old
offline device subsequently pulls that newer epoch. A portable JSON file
exported before reset is not part of the active local/cloud deletion. Importing
it after the new starter handoff preserves the advanced epoch and sends the
restored payload as a fresh local change.

```bash
npm run test:cloud-save
godot --headless --path . --scene res://tests/integration/cloud_save_sync_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/progression_autosave_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/player_menu_hud_smoke_test.tscn
```

The Node suite covers first link, causal updates, forced first-link conflicts,
divergent collection and Stretch merges, and reset epochs. The Godot tests
cover private-ID validation, opt-in/out, masked UI, schema-5 timestamps, normal
save validation, linked JSON import, and in-flight local-change rebasing. The
selected-resource export must include `CloudSaveSync.gd`; Netlify deploys the
function separately from the Web PCK.
