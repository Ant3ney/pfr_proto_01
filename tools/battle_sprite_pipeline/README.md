# Offline Battle Sprite Pipeline

This pinned Node tool copies an explicitly supplied local Pokémon Showdown GIF
corpus, verifies SHA-256 provenance, composites GIF frames, and generates the
Godot runtime PNG-atlas catalog. It contains no network-fetch path.

## Install and run

From this directory:

```bash
npm ci --ignore-scripts
npm test
node sprite_pipeline.cjs verify
```

To reproduce the tracked source copy from an authorized sibling corpus:

```bash
node sprite_pipeline.cjs sync-local \
  --from=/path/to/sibling/battle_server/sprite_disk_cache/pokemon-sprite
```

`sync-local` requires exactly 1,054 `ani` and 1,052 `ani-back` GIFs, preserves
the supplied `sync-manifest.json`, and creates `sha256-manifest.json`. It never
contacts the upstream site.

To regenerate every runtime asset:

```bash
node sprite_pipeline.cjs convert --concurrency=4 --force
node sprite_pipeline.cjs verify-runtime
npm run update-export
```

Omit `--force` to reuse an existing atlas only after its source hash, manifest,
atlas byte count, and atlas SHA-256 all verify. A focused diagnostic conversion
is also supported:

```bash
node sprite_pipeline.cjs convert \
  --ids=ferroseed,regieleki,palkia,wooper \
  --styles=ani,ani-back
```

A focused conversion writes an intentionally incomplete `catalog.json`; run the
complete conversion afterward before launching or exporting the game.

`npm run update-export` preserves the existing selected-resource list, adds all
2,106 atlas resources, and explicitly selects the catalog/presenter,
placeholder, battle coordinator, choice UI, encounter data, Kyle scene, and
species-mapping runtime closure. It also reinforces the raw-source export
exclusion. JSON manifests are shipped by the preset's existing `*.json`
non-resource include filter. Re-run it after the catalog or battle runtime file
set changes.

After producing a Web PCK, verify its path table and exclusions with:

```bash
npm run verify-export -- /path/to/export.pck
```

This requires all 2,106 imported atlases, all 2,106 timing manifests, the
catalog, placeholder, coordinator, choice UI, encounter/Kyle resources, and
runtime scripts, while rejecting raw sprite-source and `battle_server/` path
prefixes.

## Conversion contract

The tool pins `gifuct-js` 2.1.2 and `pngjs` 7.0.0 in `package-lock.json`. For
each GIF it:

1. Verifies the source SHA-256 before conversion.
2. Decompresses every image patch; `gifuct-js` deinterlaces interlaced frames.
3. Composites logical-screen offsets and transparency.
4. Applies GIF disposal 2 (restore the patch rectangle to transparent
   background) and disposal 3 (restore the previous canvas).
5. Preserves the decoded millisecond frame delay, including variable-duration
   animations.
6. Computes per-frame alpha bounds, bleeds RGB into transparent edge pixels,
   and places every full logical-screen frame in one padded PNG atlas.
7. Writes a per-animation timing/bounds manifest and a metadata-only catalog.
8. Rejects any generated file at or above GitHub's 100,000,000-byte object
   limit.

The pinned corpus produces 2,106 atlases and 2,106 manifests containing exactly
121,213 frames. Ferroseed front/back exercise the one-frame case. Regieleki
front exercises the 315-frame maximum. The complete verification also checks
every source hash, PNG hash, PNG dimension, frame region, alpha bound, duration
sum, pair count, and runtime file-size limit.

The verified base-species absence list is stored in `catalog.json` and contains
21 exact IDs: `irontreads`, `ironbundle`, `ironhands`, `ironjugulis`,
`ironmoth`, `ironthorns`, `wochien`, `chienpao`, `tinglu`, `chiyu`,
`ironvaliant`, `miraidon`, `ironleaves`, `okidogi`, `munkidori`,
`fezandipiti`, `ogerpon`, `ironboulder`, `ironcrown`, `terapagos`, and
`pecharunt`. Verification fails if any unexpectedly appears in either style.

Runtime assets live in `art/battle/sprites/generated/`. Raw GIFs live under the
Godot-ignored `source_assets/battle_sprites/` tree and must remain excluded from
exports.
