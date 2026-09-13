# Plain HTTP LAN Web

This Godot 4.7 editor addon makes Web debug exports load on phones and other
devices over ordinary Wi-Fi HTTP. It is intended for local development.

## Install in another project

1. Copy this entire `plain_http_lan_web` folder into the other project's
   `addons` folder. The final path must be:
   `res://addons/plain_http_lan_web/`.
2. Open the project in Godot.
3. Open **Project > Project Settings > Plugins**.
4. Enable **Plain HTTP LAN Web**.
5. Let Godot restart once if it says it changed the configuration.
6. Run the Web build with Godot's remote-deploy button, then open its LAN URL
   on the phone.

That is all. If the project does not have a Web export preset, the addon creates
one. If it already has one or more Web presets, the addon updates all of them
without changing the other platforms.

You can re-run the setup at any time with:
**Project > Tools > Apply Plain HTTP LAN Web Fix**.

## Find the computer's LAN IP on Linux

Run this command in a terminal:

```bash
ip -4 route get 1.1.1.1 | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}'
```

It prints the IPv4 address used by the computer on the local network, such as
`192.168.1.63`. Put that address into the URL opened on the phone:

```text
http://192.168.1.63:8060/tmp_js_export.html
```

The computer and phone must be connected to the same local network.

## What the addon configures

- Custom shell:
  `res://addons/plain_http_lan_web/plain_http_shell.html`
- Web threading: disabled
- Web touchscreen virtual keyboard: enabled for `LineEdit` and `TextEdit`
- Development server address: `0.0.0.0`
- Development server port: `8060`
- TLS/HTTPS: disabled
- TLS key and certificate paths: cleared

The custom shell skips only Godot's secure-context startup requirement. It
still checks for WebGL 2 and Fetch. On insecure HTTP it selects Godot's Dummy
audio driver; on localhost or HTTPS it keeps normal browser audio.

## Production resumable loading

The PFR Netlify build also turns the shell's production cache on. The build
script patches the generated Godot 4.7.2 loader, writes
`pfr-asset-manifest.json`, and generates `pfr-cache-sw.js` from the template
beside this README. The manifest records exact sizes, MIME types, whole-asset
hashes, and per-chunk hashes for `index.pck`, `index.wasm`, and the isolated
`pfr-loading-battle.pck`. Both Godot packs reuse the same JavaScript loader and
WASM engine.

On a first production HTTPS visit with writable Cache Storage, the shell loads
the shared engine and small loading-battle pack first. The player can choose
Charmander, Froakie, or Treecko for silent, REST-backed practice battles while
the full `index.pck` downloads. A compact dock remains above the canvas with
exact percentage and bytes. Once every full-pack chunk is validated, the dock
shows **Adventure Ready — Enter Game** and waits for the player; it never ends a
battle automatically. Entering performs a clean page replacement into the full
game. A repeat visit with a valid full-pack completion marker skips practice.

The worker requests manifest assets as sequential 8 MiB byte ranges. Each
validated range is normalized to a `200` response before being put in Cache
Storage. A completion marker is stored only after every chunk is present and
validated. If a tab is suspended, the screen is locked, or a stream is
interrupted, the next load reuses every completed chunk and starts at the
incomplete one. Each asset cache uses its own content hash, so a loader-only
deployment does not invalidate an unchanged game pack.

Servers that ignore range requests still use and incrementally cache the
returned full `200` response.
If quota, private-browsing policy, or Cache Storage access prevents persistence,
the normal loader continues from the network. Boot mode is entered only after a
write/read/delete storage probe; if storage later fails, its background fetch is
aborted and **Load Game Normally** is offered. HTML, the manifest, and the
service worker are always revalidated.

The shell pauses stall timers while hidden or offline. It allows 45 seconds of
visible, online download inactivity and 120 seconds for initialization after the
download completes. A transient failure reloads automatically once per build
when `sessionStorage` is available. Further failures show **Retry loading**;
cache or integrity failures also show **Restart download**, which removes only
the current build's asset caches and does not touch game saves. The boot dock
instead retries its background PCK once in place, then exposes **Retry
Download** and a scoped **Restart Download** while practice remains playable.

Direct editor/LAN exports leave the build-version placeholder untouched and
therefore disable this production cache. This avoids stale assets during local
development and because service workers are unavailable on ordinary insecure
LAN origins. Do not enable Godot's separate PWA service worker for this export;
only one worker should own the same scope.

## Important limits

- Insecure LAN HTTP has no audio with this shell.
- Clipboard, microphone, and some gamepad/browser features may require HTTPS.
- Browsers may evict cached files when storage is low, and private-browsing
  modes may reject the large persistent cache. The game still falls back to the
  network in either case, but an interrupted visit cannot resume persistently.
- The Web virtual keyboard is experimental and still depends on touchscreen
  browser support. Add touch gameplay controls separately if a game currently
  supports only keyboard or gamepad.
- The generated-loader patch intentionally matches Godot 4.7.2 exactly and
  fails the production build if its source signatures change. Update the patch,
  shell, and loader tests together when upgrading Godot.
