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
- Development server address: `0.0.0.0`
- Development server port: `8060`
- TLS/HTTPS: disabled
- TLS key and certificate paths: cleared

The custom shell skips only Godot's secure-context startup requirement. It
still checks for WebGL 2 and Fetch. On insecure HTTP it selects Godot's Dummy
audio driver; on localhost or HTTPS it keeps normal browser audio.

## Production browser cache

The PFR Netlify build also turns the shell's production cache on. The build
script hashes `index.js`, `index.pck`, and `index.wasm`, injects that version into
the HTML, and generates `pfr-cache-sw.js` from the template beside this README.

On the first HTTPS visit, the game still downloads normally while the service
worker stores the large pack and WebAssembly runtime in browser Cache Storage.
Later visits reuse those responses locally. A changed export produces a new
versioned URL and cache name, so an old pack cannot be combined with a new
build. HTML and the service worker are always revalidated.

Direct editor/LAN exports leave the build-version placeholder untouched and
therefore disable this production cache. This avoids stale assets during local
development and because service workers are unavailable on ordinary insecure
LAN origins. Do not enable Godot's separate PWA service worker for this export;
only one worker should own the same scope.

## Important limits

- Insecure LAN HTTP has no audio with this shell.
- Clipboard, microphone, and some gamepad/browser features may require HTTPS.
- Browsers may evict cached files when storage is low, and private-browsing
  modes may reject the roughly 255 MB persistent cache. The game still falls
  back to the network in either case.
- This changes Web delivery, not input. Add touch controls separately if a game
  currently supports only keyboard or gamepad.
- The shell is based on the Godot 4.7 Web template. When moving projects to a
  different major/minor Godot version, update and retest the shell.
