# Web Export Browser Cache

Read this when a repeat visit to the Netlify-hosted Godot build downloads the
large runtime again, or before changing the web loader, build versioning,
service worker, or response cache headers.

## Verified bottleneck

The August 2026 web export contains an approximately 216 MB `index.pck` and a
38 MB `index.wasm`. Godot requests both with ordinary `fetch()` calls. Browser
HTTP caches may evict a response this large, so response headers alone are not
a reliable persistent cache.

## Cache ownership and update contract

- `addons/plain_http_lan_web/plain_http_shell.html` registers the PFR cache
  worker before starting the engine and gives `index.pck` and `index.wasm`
  content-versioned query strings.
- `addons/plain_http_lan_web/pfr_cache_service_worker.js` is the source worker
  template. It stores the engine, pack, runtime, and audio worklets in Cache
  Storage while their first network responses stream to Godot.
- `tools/netlify_build_web.sh` hashes the exported `index.js`, `index.pck`, and
  `index.wasm`, replaces every `__PFR_CACHE_VERSION__` token in generated HTML,
  and emits `build/web/v1/pfr-cache-sw.js` with the same version.
- `netlify.toml` makes HTML and the worker revalidate while allowing versioned
  runtime URLs to remain immutable in the ordinary HTTP cache.
- The worker never intercepts navigation or caches `index.html`. A new HTML
  document therefore discovers a new build hash. The newly activated worker
  deletes only older caches whose names begin with `pfr-web-assets-`.

Do not enable Godot's separate Progressive Web App worker for this export. Two
workers cannot own the same scope, and Godot's generic PWA cache does not supply
this project's content-hash invalidation contract.

Direct editor and insecure LAN exports leave `__PFR_CACHE_VERSION__` intact.
The shell detects that state and disables production caching so local iteration
does not become stale. Netlify is HTTPS, which allows the production worker.

## Expected behavior and limits

The first visit still transfers the full game and stores the response at the
same time. A repeat visit with the same browser profile should report zero
network transfer for versioned `index.pck` and `index.wasm` resource entries.
A changed content hash must create one new cache, remove the previous PFR cache,
and fetch the changed-version URLs once.

Cache Storage is an optimization, not a startup dependency. Private browsing,
low device storage, quota rejection, or browser eviction can prevent or remove
the roughly 255 MB cache. The worker catches cache-write failures and lets the
network response continue, so the game must still launch.

## Regression checks

Run the production export and source checks:

```bash
bash tools/netlify_build_web.sh
node --check build/web/v1/pfr-cache-sw.js
git diff --check
```

Then confirm that neither generated file contains an unresolved version token:

```bash
rg '__PFR_CACHE_VERSION__|\$GODOT_' \
  build/web/v1/index.html \
  build/web/v1/pfr-cache-sw.js
```

That final command should print nothing. Browser verification must reuse one
profile across two page visits. On the first visit, Cache Storage should contain
the versioned pack and runtime. On the second, the server should receive no
request for either file and their resource timing `transferSize` should be zero.

This document describes only delivery caching. Reducing the first-load time
requires shrinking or splitting the exported pack and is a separate task.
