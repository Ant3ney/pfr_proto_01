# Web Loading and Recovery

Read this document when changing or diagnosing the custom Web shell, production
asset worker, Godot JavaScript loader patch, or Netlify Web export. Verify the
current generated export and tests before relying on these contracts.

## Build ownership

- [`../addons/plain_http_lan_web/plain_http_shell.html`](../addons/plain_http_lan_web/plain_http_shell.html)
  owns the branded progress UI, lifecycle handling, watchdogs, retry policy, and
  plain-HTTP LAN behavior.
- [`../addons/plain_http_lan_web/pfr_cache_service_worker.js`](../addons/plain_http_lan_web/pfr_cache_service_worker.js)
  is a template used only by the production build. Ordinary insecure LAN
  origins do not get persistent service-worker caching.
- [`../tools/netlify_build_web.sh`](../tools/netlify_build_web.sh) exports with
  Godot 4.7.2. It first stages and tests the isolated loading-battle project,
  enforces its pack allowlist and 4 MiB ceiling, then exports the full game,
  applies the fail-closed loader patch, generates the asset manifest, and runs
  the generated-loader and both PCK verification gates.
- [`../loading_battle/`](../loading_battle/) is source for the isolated boot
  project. The build copies it to a temporary project with the shared REST
  transport, DTO validator, event translator, and exactly eight approved sprite
  atlas/manifest pairs. Do not add an autoload or a full-project dependency.
- [`../tools/patch_godot_web_loader.mjs`](../tools/patch_godot_web_loader.mjs)
  matches exact Godot 4.7.2 source signatures. A missing or duplicate signature
  is a build error and must be reviewed when upgrading Godot.

## Resumable asset contract

The production build writes `pfr-asset-manifest.json` for `index.pck`,
`index.wasm`, and `pfr-loading-battle.pck`. Each entry has an exact byte size,
MIME type, whole-file SHA-256, 8 MiB chunk size, and ordered chunk SHA-256
values. The same manifest is embedded in the HTML shell and
`pfr-cache-sw.js`. The boot PCK reuses `index.js` and `index.wasm`; it does not
ship a second engine binary.

The worker intercepts full same-origin requests for those two assets, requests
sequential byte ranges, validates status `206`, `Content-Range`, total size,
received byte count, and chunk digest, then caches each complete chunk as a
normalized `200` response. Raw `206` responses must never be passed to
`Cache.put`. Cache names include the individual asset hash, so an unchanged PCK
survives loader-only deployments. A missing, truncated, or corrupt cached chunk
is deleted and fetched again without clearing other chunks. A separate
completion marker is written only after all declared chunks have been validated
and cached; readiness requires both a valid marker and every expected chunk.

If a host ignores `Range` and returns `200`, the worker validates and caches the
response incrementally without retaining the full asset in memory. Cache quota,
security-policy, and private-browsing failures are nonfatal for the normal
loader: bytes continue from the network and the worker sends a
`pfr-storage-fallback` message. Worker activity and structured failures use
`pfr-download-activity` and `pfr-load-failure`. `pfr-query-asset-readiness`
performs a Cache Storage write/read/delete probe and reports readiness per
asset. `pfr-clear-asset-cache` accepts optional asset names, allowing the boot
dock to restart only `index.pck`; neither operation touches IndexedDB saves or
cloud-save data.

## Loading-battle launch contract

Boot mode is eligible only for a versioned production HTTPS build when the
current service worker controls the page, the required stream-abort API exists,
and the storage probe succeeds. A ready `index.pck` marker bypasses the boot
battle. Direct LAN, unsupported browsers, a worker timeout, and initial storage
failure use the normal full loader.

Boot mode starts the shared engine with `pfr-loading-battle.pck` and keeps a
compact HTML dock above its canvas while a discarded response stream consumes
`index.pck` into the worker cache. Progress is monotonic and reports exact bytes.
Completion reveals **Adventure Ready — Enter Game** indefinitely; it never
interrupts a battle. Enter uses `location.replace()` with the current build
identity. The replacement page starts the full pack from cache, then removes
the mode parameters from browser history after `Engine.startGame()` resolves.

The practice client calls the existing `/api/v1/battles` and
`/api/v1/battles/actions` routes. Its state token and exact retry body exist only
in memory. Choices remain locked during requests and event presentation, and
only an accepted result changes the Medium-first Easy/Medium/Hard/Impossible
ladder. The impossible tier is explicitly labeled and uses physical-only player
moves against minimum-speed Counter Wobbuffet. Nothing in the boot project
reads or writes real progression or saves.

## Shell recovery contract

The shell waits at most eight seconds for the production worker to control the
page, then starts through the ordinary network path. It listens for page
visibility, `pageshow`, connection changes, worker messages, global startup
errors, and the `Engine.startGame()` promise.

Download inactivity may accumulate only while the page is visible and online.
Returning from suspension or reconnecting grants a fresh 45-second activity
window. Once reported download progress reaches completion, initialization gets
120 seconds. Offline loading remains indefinitely in a waiting state.

The normal loader retains its one automatic reload per build. In boot mode the
background PCK gets one automatic retry in place; later failures expose
**Retry Download** and a scoped **Restart Download** without stopping practice.
Offline state pauses background watchdogs and lets an exact pending battle
request resume after reconnection. If persistent storage fails after boot has
started, the background fetch is aborted and **Load Game Normally** is offered,
avoiding a completed-but-unusable handoff download.

## Regression checks

Run:

```bash
npm run test:web-loader
bash tools/netlify_build_web.sh
git diff --check
```

The Web tests cover interrupted resume, completion/readiness markers, exact
reconstruction, HTTP and stream failures, invalid ranges, cache corruption,
quota rejection, range-unsupported servers, scoped cache clearing, mode
selection, monotonic background progress, explicit handoff, cache-hit bypass,
watchdog pauses/timeouts, manifest identity, and fail-closed Godot patch
signatures. The build also runs the boot-project smoke test and exact pack
allowlist. Physical iPhone screen-lock, app-switching, orientation, touch-target,
memory, airplane-mode, and prolonged-play behavior still requires device testing
before a high-risk release.
