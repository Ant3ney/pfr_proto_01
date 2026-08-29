#!/usr/bin/env node

'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const fsp = fs.promises;
const os = require('node:os');
const path = require('node:path');
const process = require('node:process');
const {
  Worker,
  isMainThread,
  parentPort,
  workerData,
} = require('node:worker_threads');
const { decompressFrames, parseGIF } = require('gifuct-js');
const { PNG } = require('pngjs');

const PIPELINE_NAME = 'pfr-battle-sprite-pipeline';
const PIPELINE_VERSION = 1;
const MANIFEST_SCHEMA_VERSION = 1;
const CATALOG_SCHEMA_VERSION = 1;
const PROVENANCE_SCHEMA_VERSION = 1;
const STYLES = Object.freeze(['ani', 'ani-back']);
const EXPECTED_STYLE_COUNTS = Object.freeze({ ani: 1054, 'ani-back': 1052 });
const EXPECTED_SOURCE_COUNT = 2106;
const EXPECTED_FRAME_COUNT = 121213;
const EXPECTED_MAX_FRAME_COUNT = 315;
const EXPECTED_ABSENT_BASE_IDS = Object.freeze([
  'irontreads',
  'ironbundle',
  'ironhands',
  'ironjugulis',
  'ironmoth',
  'ironthorns',
  'wochien',
  'chienpao',
  'tinglu',
  'chiyu',
  'ironvaliant',
  'miraidon',
  'ironleaves',
  'okidogi',
  'munkidori',
  'fezandipiti',
  'ogerpon',
  'ironboulder',
  'ironcrown',
  'terapagos',
  'pecharunt',
]);
const FOCUSED_RENDER_KEYS = new Set([
  'ani-back/palkia',
  'ani-back/mothim',
  'ani-back/hoothoot',
  'ani-back/vespiquen',
  'ani-back/luxray',
  'ani-back/pelipper',
  'ani/wooper',
  'ani/magikarp',
  'ani/ferroseed',
  'ani-back/ferroseed',
  'ani/regieleki',
  'ani-back/regieleki',
  'ani/dipplin',
  'ani-back/psyduck',
  'ani/kingler',
]);
const ALPHA_THRESHOLD = 12;
const ATLAS_PADDING = 4;
const TRANSPARENT_BLEED_PASSES = 4;
const MAX_GITHUB_OBJECT_BYTES = 100 * 1000 * 1000;

const PROJECT_ROOT = path.resolve(__dirname, '..', '..');
const DEFAULT_SOURCE_ROOT = path.join(
  PROJECT_ROOT,
  'source_assets',
  'battle_sprites',
  'pokemon_showdown'
);
const DEFAULT_RUNTIME_ROOT = path.join(
  PROJECT_ROOT,
  'art',
  'battle',
  'sprites',
  'generated'
);

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

async function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('error', reject);
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

function stableJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

async function readJson(filePath) {
  return JSON.parse(await fsp.readFile(filePath, 'utf8'));
}

async function writeJson(filePath, value) {
  await fsp.mkdir(path.dirname(filePath), { recursive: true });
  await fsp.writeFile(filePath, stableJson(value), 'utf8');
}

function normalizePath(filePath) {
  return filePath.split(path.sep).join('/');
}

function projectResourcePath(filePath) {
  const relative = normalizePath(path.relative(PROJECT_ROOT, filePath));
  if (relative.startsWith('../') || relative === '..') {
    throw new Error(`Runtime output is outside the project: ${filePath}`);
  }
  return `res://${relative}`;
}

function parseArgs(argv) {
  const command = argv[0] || 'help';
  const options = {};
  for (const argument of argv.slice(1)) {
    if (!argument.startsWith('--')) {
      throw new Error(`Unexpected argument: ${argument}`);
    }
    const separator = argument.indexOf('=');
    if (separator < 0) {
      options[argument.slice(2)] = true;
      continue;
    }
    options[argument.slice(2, separator)] = argument.slice(separator + 1);
  }
  return { command, options };
}

function optionPath(options, name, fallback) {
  const value = String(options[name] || '').trim();
  return value ? path.resolve(value) : fallback;
}

function selectedStyles(options) {
  const value = String(options.styles || '').trim();
  const styles = value ? value.split(',').map((item) => item.trim()).filter(Boolean) : [...STYLES];
  for (const style of styles) {
    if (!STYLES.includes(style)) throw new Error(`Unsupported style: ${style}`);
  }
  return [...new Set(styles)].sort();
}

function selectedIds(options) {
  const value = String(options.ids || '').trim();
  if (!value) return null;
  const ids = value.split(',').map((item) => item.trim()).filter(Boolean);
  for (const id of ids) {
    if (!/^[a-z0-9-]+$/.test(id)) throw new Error(`Invalid exact sprite id: ${id}`);
  }
  return new Set(ids);
}

async function listGifFiles(sourceRoot, styles = STYLES) {
  const files = [];
  for (const style of styles) {
    const styleRoot = path.join(sourceRoot, style);
    const names = (await fsp.readdir(styleRoot, { withFileTypes: true }))
      .filter((entry) => entry.isFile() && entry.name.endsWith('.gif'))
      .map((entry) => entry.name)
      .sort();
    for (const name of names) {
      files.push({
        style,
        id: name.slice(0, -4),
        relativePath: `${style}/${name}`,
        absolutePath: path.join(styleRoot, name),
      });
    }
  }
  return files;
}

async function syncLocalCorpus(fromRoot, destinationRoot) {
  const sourceManifestPath = path.join(fromRoot, 'sync-manifest.json');
  const sourceManifest = await readJson(sourceManifestPath);
  const sourceFiles = await listGifFiles(fromRoot);
  if (sourceFiles.length !== EXPECTED_SOURCE_COUNT) {
    throw new Error(
      `Supplied corpus has ${sourceFiles.length} GIFs; expected ${EXPECTED_SOURCE_COUNT}.`
    );
  }
  for (const style of STYLES) {
    const count = sourceFiles.filter((entry) => entry.style === style).length;
    if (count !== EXPECTED_STYLE_COUNTS[style]) {
      throw new Error(`Supplied ${style} corpus has ${count} GIFs; expected ${EXPECTED_STYLE_COUNTS[style]}.`);
    }
  }
  if (Number(sourceManifest.downloaded) !== EXPECTED_SOURCE_COUNT) {
    throw new Error('Supplied sync-manifest.json does not describe the expected downloaded corpus.');
  }

  await fsp.mkdir(destinationRoot, { recursive: true });
  const provenanceFiles = [];
  let totalBytes = 0;
  for (let index = 0; index < sourceFiles.length; index += 1) {
    const entry = sourceFiles[index];
    const bytes = await fsp.readFile(entry.absolutePath);
    const destination = path.join(destinationRoot, entry.relativePath);
    await fsp.mkdir(path.dirname(destination), { recursive: true });
    await fsp.writeFile(destination, bytes);
    provenanceFiles.push({
      path: entry.relativePath,
      bytes: bytes.length,
      sha256: sha256(bytes),
    });
    totalBytes += bytes.length;
    if ((index + 1) % 250 === 0 || index + 1 === sourceFiles.length) {
      console.log(`Copied and hashed ${index + 1}/${sourceFiles.length} GIFs.`);
    }
  }

  const originalManifestBytes = await fsp.readFile(sourceManifestPath);
  await fsp.writeFile(path.join(destinationRoot, 'sync-manifest.json'), originalManifestBytes);
  const styleCounts = Object.fromEntries(
    STYLES.map((style) => [style, provenanceFiles.filter((entry) => entry.path.startsWith(`${style}/`)).length])
  );
  const provenance = {
    schemaVersion: PROVENANCE_SCHEMA_VERSION,
    source: {
      description: 'Local copy of the user-supplied sibling project sprite cache.',
      upstreamAssetRoot: 'https://play.pokemonshowdown.com/sprites',
      originalSyncManifest: 'sync-manifest.json',
      originalSyncManifestSha256: sha256(originalManifestBytes),
    },
    totals: {
      files: provenanceFiles.length,
      bytes: totalBytes,
      styles: styleCounts,
    },
    files: provenanceFiles,
  };
  await writeJson(path.join(destinationRoot, 'sha256-manifest.json'), provenance);
  return provenance;
}

async function verifySourceCorpus(sourceRoot) {
  const provenancePath = path.join(sourceRoot, 'sha256-manifest.json');
  const provenance = await readJson(provenancePath);
  if (Number(provenance.schemaVersion) !== PROVENANCE_SCHEMA_VERSION) {
    throw new Error(`Unsupported provenance schema: ${provenance.schemaVersion}`);
  }
  const declaredFiles = Array.isArray(provenance.files) ? provenance.files : [];
  if (declaredFiles.length !== EXPECTED_SOURCE_COUNT) {
    throw new Error(`Provenance declares ${declaredFiles.length} GIFs; expected ${EXPECTED_SOURCE_COUNT}.`);
  }
  const actualFiles = await listGifFiles(sourceRoot);
  for (const style of STYLES) {
    const styleCount = actualFiles.filter((entry) => entry.style === style).length;
    if (styleCount !== EXPECTED_STYLE_COUNTS[style]) {
      throw new Error(`Source ${style} corpus has ${styleCount} GIFs; expected ${EXPECTED_STYLE_COUNTS[style]}.`);
    }
  }
  const actualPaths = actualFiles.map((entry) => entry.relativePath);
  const declaredPaths = declaredFiles.map((entry) => String(entry.path));
  if (stableJson(actualPaths) !== stableJson(declaredPaths)) {
    throw new Error('Source file set does not match sha256-manifest.json.');
  }
  const actualIdsByStyle = Object.fromEntries(
    STYLES.map((style) => [
      style,
      new Set(actualFiles.filter((entry) => entry.style === style).map((entry) => entry.id)),
    ])
  );
  for (const id of EXPECTED_ABSENT_BASE_IDS) {
    for (const style of STYLES) {
      if (actualIdsByStyle[style].has(id)) {
        throw new Error(`Expected absent base sprite unexpectedly exists: ${style}/${id}`);
      }
    }
  }

  let totalBytes = 0;
  for (let index = 0; index < declaredFiles.length; index += 1) {
    const entry = declaredFiles[index];
    const filePath = path.join(sourceRoot, String(entry.path));
    const stat = await fsp.stat(filePath);
    if (stat.size !== Number(entry.bytes)) {
      throw new Error(`Source byte-size mismatch: ${entry.path}`);
    }
    const digest = await sha256File(filePath);
    if (digest !== entry.sha256) throw new Error(`Source SHA-256 mismatch: ${entry.path}`);
    totalBytes += stat.size;
    if ((index + 1) % 250 === 0 || index + 1 === declaredFiles.length) {
      console.log(`Verified ${index + 1}/${declaredFiles.length} source hashes.`);
    }
  }
  if (totalBytes !== Number(provenance.totals.bytes)) {
    throw new Error('Source total byte count does not match provenance.');
  }

  const syncManifestBytes = await fsp.readFile(path.join(sourceRoot, 'sync-manifest.json'));
  if (sha256(syncManifestBytes) !== provenance.source.originalSyncManifestSha256) {
    throw new Error('Original sync manifest SHA-256 mismatch.');
  }
  const syncManifest = JSON.parse(syncManifestBytes.toString('utf8'));
  if (
    Number(syncManifest.downloaded) !== EXPECTED_SOURCE_COUNT ||
    Number(syncManifest.failed) !== 0
  ) {
    throw new Error('Original sync manifest does not describe the accepted local corpus.');
  }
  return provenance;
}

function arrayBufferForBuffer(buffer) {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
}

function gifFrameRecords(parsedGif) {
  return parsedGif.frames.filter((frame) => frame && frame.image);
}

function renderCompositedFrames(frames, width, height) {
  const canvas = new Uint8ClampedArray(width * height * 4);
  const output = [];
  for (const frame of frames) {
    const previous = new Uint8ClampedArray(canvas);
    drawFramePatch(canvas, frame, width, height);
    const pixels = bleedTransparentPixels(canvas, width, height);
    output.push({
      pixels,
      durationMs: normalizeFrameDelay(frame.delay),
      alphaBounds: alphaBoundsForPixels(pixels, width, height),
      disposalType: Number(frame.disposalType || 0),
      offset: { x: frame.dims.left, y: frame.dims.top },
    });
    if (frame.disposalType === 2) {
      clearRect(canvas, width, height, frame.dims.left, frame.dims.top, frame.dims.width, frame.dims.height);
    } else if (frame.disposalType === 3) {
      canvas.set(previous);
    }
  }
  return output;
}

function drawFramePatch(canvas, frame, canvasWidth, canvasHeight) {
  const { left, top, width, height } = frame.dims;
  const patch = frame.patch;
  for (let y = 0; y < height; y += 1) {
    const destinationY = top + y;
    if (destinationY < 0 || destinationY >= canvasHeight) continue;
    for (let x = 0; x < width; x += 1) {
      const destinationX = left + x;
      if (destinationX < 0 || destinationX >= canvasWidth) continue;
      const sourceIndex = (y * width + x) * 4;
      const alpha = patch[sourceIndex + 3] || 0;
      if (alpha <= 0) continue;
      const destinationIndex = (destinationY * canvasWidth + destinationX) * 4;
      canvas[destinationIndex] = patch[sourceIndex] || 0;
      canvas[destinationIndex + 1] = patch[sourceIndex + 1] || 0;
      canvas[destinationIndex + 2] = patch[sourceIndex + 2] || 0;
      canvas[destinationIndex + 3] = alpha;
    }
  }
}

function clearRect(canvas, canvasWidth, canvasHeight, left, top, width, height) {
  for (let y = 0; y < height; y += 1) {
    const destinationY = top + y;
    if (destinationY < 0 || destinationY >= canvasHeight) continue;
    for (let x = 0; x < width; x += 1) {
      const destinationX = left + x;
      if (destinationX < 0 || destinationX >= canvasWidth) continue;
      const index = (destinationY * canvasWidth + destinationX) * 4;
      canvas[index] = 0;
      canvas[index + 1] = 0;
      canvas[index + 2] = 0;
      canvas[index + 3] = 0;
    }
  }
}

function alphaBoundsForPixels(pixels, width, height) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const alpha = pixels[(y * width + x) * 4 + 3] || 0;
      if (alpha <= ALPHA_THRESHOLD) continue;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    }
  }
  if (maxX < minX || maxY < minY) return { x: 0, y: 0, width, height };
  return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

function unionBounds(bounds) {
  let minX = Number.POSITIVE_INFINITY;
  let minY = Number.POSITIVE_INFINITY;
  let maxX = Number.NEGATIVE_INFINITY;
  let maxY = Number.NEGATIVE_INFINITY;
  for (const entry of bounds) {
    minX = Math.min(minX, entry.x);
    minY = Math.min(minY, entry.y);
    maxX = Math.max(maxX, entry.x + entry.width);
    maxY = Math.max(maxY, entry.y + entry.height);
  }
  if (!Number.isFinite(minX)) return { x: 0, y: 0, width: 1, height: 1 };
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

function bleedTransparentPixels(source, width, height) {
  let output = new Uint8ClampedArray(source);
  for (let pass = 0; pass < TRANSPARENT_BLEED_PASSES; pass += 1) {
    const next = new Uint8ClampedArray(output);
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const index = (y * width + x) * 4;
        if ((output[index + 3] || 0) > ALPHA_THRESHOLD) continue;
        let count = 0;
        let red = 0;
        let green = 0;
        let blue = 0;
        for (let dy = -1; dy <= 1; dy += 1) {
          const sampleY = y + dy;
          if (sampleY < 0 || sampleY >= height) continue;
          for (let dx = -1; dx <= 1; dx += 1) {
            const sampleX = x + dx;
            if ((dx === 0 && dy === 0) || sampleX < 0 || sampleX >= width) continue;
            const sampleIndex = (sampleY * width + sampleX) * 4;
            if ((output[sampleIndex + 3] || 0) <= ALPHA_THRESHOLD) continue;
            red += output[sampleIndex] || 0;
            green += output[sampleIndex + 1] || 0;
            blue += output[sampleIndex + 2] || 0;
            count += 1;
          }
        }
        if (count > 0) {
          next[index] = Math.round(red / count);
          next[index + 1] = Math.round(green / count);
          next[index + 2] = Math.round(blue / count);
        }
      }
    }
    output = next;
  }
  return output;
}

function copyFrameToPaddedAtlas(source, destination, width, height, atlasWidth, cellX, cellY, padding) {
  for (let y = -padding; y < height + padding; y += 1) {
    const sourceY = clamp(y, 0, height - 1);
    const destinationY = cellY + y + padding;
    for (let x = -padding; x < width + padding; x += 1) {
      const sourceX = clamp(x, 0, width - 1);
      const destinationX = cellX + x + padding;
      const sourceIndex = (sourceY * width + sourceX) * 4;
      const destinationIndex = (destinationY * atlasWidth + destinationX) * 4;
      destination[destinationIndex] = source[sourceIndex] || 0;
      destination[destinationIndex + 1] = source[sourceIndex + 1] || 0;
      destination[destinationIndex + 2] = source[sourceIndex + 2] || 0;
      destination[destinationIndex + 3] = source[sourceIndex + 3] || 0;
    }
  }
}

function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value));
}

function normalizeFrameDelay(delayMs) {
  if (!Number.isFinite(delayMs) || delayMs <= 0) return 100;
  return Math.round(delayMs);
}

function chooseAtlasGrid(frameCount, cellWidth, cellHeight) {
  let best = null;
  for (let columns = 1; columns <= frameCount; columns += 1) {
    const rows = Math.ceil(frameCount / columns);
    const width = columns * cellWidth;
    const height = rows * cellHeight;
    const score = Math.max(width, height);
    const area = width * height;
    if (!best || score < best.score || (score === best.score && area < best.area)) {
      best = { columns, rows, width, height, score, area };
    }
  }
  return best;
}

function frameFeatureSummary(parsedGif, decompressedFrames) {
  const frameRecords = gifFrameRecords(parsedGif);
  const interlacedFrames = frameRecords.filter(
    (frame) => Boolean(frame.image && frame.image.descriptor && frame.image.descriptor.lct.interlaced)
  ).length;
  const offsetFrames = decompressedFrames.filter(
    (frame) => frame.dims.left !== 0 || frame.dims.top !== 0
  ).length;
  const disposalModes = [...new Set(decompressedFrames.map((frame) => Number(frame.disposalType || 0)))].sort();
  const durations = [...new Set(decompressedFrames.map((frame) => normalizeFrameDelay(frame.delay)))].sort((a, b) => a - b);
  return {
    interlacedFrames,
    offsetFrames,
    disposalModes,
    variableDuration: durations.length > 1,
  };
}

function sourceFrameContract(parsedGif) {
  const frameRecords = gifFrameRecords(parsedGif);
  const frames = frameRecords.map((frame) => ({
    durationMs: normalizeFrameDelay(frame.gce ? (frame.gce.delay || 10) * 10 : undefined),
    disposalType: Number(frame.gce && frame.gce.extras ? frame.gce.extras.disposal || 0 : 0),
    offset: {
      x: Number(frame.image.descriptor.left),
      y: Number(frame.image.descriptor.top),
    },
    interlaced: Boolean(frame.image.descriptor.lct.interlaced),
  }));
  const durations = [...new Set(frames.map((frame) => frame.durationMs))];
  return {
    canvas: {
      width: Math.max(1, Number(parsedGif.lsd.width)),
      height: Math.max(1, Number(parsedGif.lsd.height)),
    },
    frames,
    sourceFeatures: {
      interlacedFrames: frames.filter((frame) => frame.interlaced).length,
      offsetFrames: frames.filter((frame) => frame.offset.x !== 0 || frame.offset.y !== 0).length,
      disposalModes: [...new Set(frames.map((frame) => frame.disposalType))].sort(),
      variableDuration: durations.length > 1,
    },
  };
}

function verifyFocusedRendering(parsedGif, manifest, atlasPng, identity) {
  const decompressedFrames = decompressFrames(parsedGif, true);
  const renderedFrames = renderCompositedFrames(
    decompressedFrames,
    Number(manifest.canvas.width),
    Number(manifest.canvas.height)
  );
  if (renderedFrames.length !== manifest.frames.length) {
    throw new Error(`Focused frame count mismatch: ${identity}`);
  }
  for (let frameIndex = 0; frameIndex < renderedFrames.length; frameIndex += 1) {
    const rendered = renderedFrames[frameIndex];
    const declared = manifest.frames[frameIndex];
    if (
      rendered.durationMs !== Number(declared.durationMs) ||
      stableJson(rendered.alphaBounds) !== stableJson(declared.alphaBounds)
    ) {
      throw new Error(`Focused timing/alpha-bound mismatch: ${identity}#${frameIndex}`);
    }
    for (let y = 0; y < declared.region.height; y += 1) {
      for (let x = 0; x < declared.region.width; x += 1) {
        const sourceIndex = (y * declared.region.width + x) * 4;
        const atlasIndex = (
          (declared.region.y + y) * atlasPng.width + declared.region.x + x
        ) * 4;
        for (let channel = 0; channel < 4; channel += 1) {
          if (rendered.pixels[sourceIndex + channel] !== atlasPng.data[atlasIndex + channel]) {
            throw new Error(`Focused atlas pixel mismatch: ${identity}#${frameIndex}@${x},${y}`);
          }
        }
      }
    }
  }
}

async function convertOne(task) {
  const sourceBytes = await fsp.readFile(task.sourcePath);
  const sourceDigest = sha256(sourceBytes);
  if (sourceDigest !== task.sourceSha256) {
    throw new Error(`Source changed before conversion: ${task.relativePath}`);
  }
  const parsedGif = parseGIF(arrayBufferForBuffer(sourceBytes));
  const width = Math.max(1, Number(parsedGif.lsd.width));
  const height = Math.max(1, Number(parsedGif.lsd.height));
  const decompressedFrames = decompressFrames(parsedGif, true);
  if (decompressedFrames.length === 0) throw new Error(`GIF has no frames: ${task.relativePath}`);
  const renderedFrames = renderCompositedFrames(decompressedFrames, width, height);
  const cellWidth = width + ATLAS_PADDING * 2;
  const cellHeight = height + ATLAS_PADDING * 2;
  const grid = chooseAtlasGrid(renderedFrames.length, cellWidth, cellHeight);
  const atlas = new PNG({ width: grid.width, height: grid.height });
  atlas.data.fill(0);

  const manifestFrames = [];
  let durationMs = 0;
  for (let index = 0; index < renderedFrames.length; index += 1) {
    const frame = renderedFrames[index];
    const column = index % grid.columns;
    const row = Math.floor(index / grid.columns);
    const cellX = column * cellWidth;
    const cellY = row * cellHeight;
    copyFrameToPaddedAtlas(
      frame.pixels,
      atlas.data,
      width,
      height,
      atlas.width,
      cellX,
      cellY,
      ATLAS_PADDING
    );
    durationMs += frame.durationMs;
    manifestFrames.push({
      index,
      region: {
        x: cellX + ATLAS_PADDING,
        y: cellY + ATLAS_PADDING,
        width,
        height,
      },
      durationMs: frame.durationMs,
      alphaBounds: frame.alphaBounds,
    });
  }

  const atlasBytes = PNG.sync.write(atlas, { colorType: 6, inputColorType: 6 });
  if (atlasBytes.length >= MAX_GITHUB_OBJECT_BYTES) {
    throw new Error(
      `Generated atlas exceeds GitHub's 100 MB object limit: ${task.style}/${task.id}.png (${atlasBytes.length} bytes)`
    );
  }
  await fsp.mkdir(path.dirname(task.atlasPath), { recursive: true });
  await fsp.writeFile(task.atlasPath, atlasBytes);
  const contentBounds = unionBounds(manifestFrames.map((frame) => frame.alphaBounds));
  const manifest = {
    schemaVersion: MANIFEST_SCHEMA_VERSION,
    generator: {
      name: PIPELINE_NAME,
      version: PIPELINE_VERSION,
      gifuctJs: '2.1.2',
      pngjs: '7.0.0',
    },
    id: task.id,
    style: task.style,
    source: {
      path: task.relativePath,
      sha256: sourceDigest,
    },
    atlas: {
      path: projectResourcePath(task.atlasPath),
      sha256: sha256(atlasBytes),
      bytes: atlasBytes.length,
      width: atlas.width,
      height: atlas.height,
      columns: grid.columns,
      rows: grid.rows,
      padding: ATLAS_PADDING,
    },
    canvas: { width, height },
    contentBounds,
    contentHeight: Math.max(1, ...manifestFrames.map((frame) => frame.alphaBounds.height)),
    frameCount: manifestFrames.length,
    durationMs,
    sourceFeatures: frameFeatureSummary(parsedGif, decompressedFrames),
    frames: manifestFrames,
  };
  await writeJson(task.manifestPath, manifest);
  return catalogEntryForManifest(manifest, task.manifestPath);
}

function catalogEntryForManifest(manifest, manifestPath) {
  return {
    id: manifest.id,
    style: manifest.style,
    manifest: projectResourcePath(manifestPath),
    atlas: manifest.atlas.path,
    sourceSha256: manifest.source.sha256,
    atlasSha256: manifest.atlas.sha256,
    atlasBytes: manifest.atlas.bytes,
    atlasWidth: manifest.atlas.width,
    atlasHeight: manifest.atlas.height,
    canvasWidth: manifest.canvas.width,
    canvasHeight: manifest.canvas.height,
    frameCount: manifest.frameCount,
    durationMs: manifest.durationMs,
    contentHeight: manifest.contentHeight,
    sourceFeatures: manifest.sourceFeatures,
  };
}

async function existingConversion(task) {
  try {
    const manifest = await readJson(task.manifestPath);
    if (
      Number(manifest.schemaVersion) !== MANIFEST_SCHEMA_VERSION ||
      Number(manifest.generator && manifest.generator.version) !== PIPELINE_VERSION ||
      manifest.source.sha256 !== task.sourceSha256 ||
      manifest.id !== task.id ||
      manifest.style !== task.style
    ) return null;
    const atlasStat = await fsp.stat(task.atlasPath);
    if (atlasStat.size !== Number(manifest.atlas.bytes)) return null;
    const digest = await sha256File(task.atlasPath);
    if (digest !== manifest.atlas.sha256) return null;
    return catalogEntryForManifest(manifest, task.manifestPath);
  } catch {
    return null;
  }
}

async function workerConvert(task, force) {
  if (!force) {
    const existing = await existingConversion(task);
    if (existing) return { entry: existing, converted: false };
  }
  return { entry: await convertOne(task), converted: true };
}

async function runWorkerThread() {
  parentPort.on('message', async (message) => {
    try {
      const result = await workerConvert(message.task, message.force);
      parentPort.postMessage({ id: message.id, result });
    } catch (error) {
      parentPort.postMessage({
        id: message.id,
        error: error instanceof Error ? error.stack || error.message : String(error),
      });
    }
  });
}

async function runConversionWorkers(tasks, concurrency, force) {
  if (tasks.length === 0) return [];
  const results = new Array(tasks.length);
  const workers = [];
  let nextTask = 0;
  let completed = 0;
  let converted = 0;
  let failed = false;

  return new Promise((resolve, reject) => {
    const stopWorkers = () => Promise.all(workers.map((worker) => worker.terminate()));
    const dispatch = (worker) => {
      if (failed) return;
      if (nextTask >= tasks.length) {
        if (completed === tasks.length) {
          stopWorkers().then(() => {
            console.log(`Conversion complete: ${converted} generated, ${tasks.length - converted} verified existing.`);
            resolve(results);
          }, reject);
        }
        return;
      }
      const id = nextTask;
      nextTask += 1;
      worker.postMessage({ id, task: tasks[id], force });
    };

    for (let index = 0; index < Math.min(concurrency, tasks.length); index += 1) {
      const worker = new Worker(__filename, { workerData: { pipelineWorker: true } });
      workers.push(worker);
      worker.on('message', (message) => {
        if (failed) return;
        if (message.error) {
          failed = true;
          stopWorkers().finally(() => reject(new Error(message.error)));
          return;
        }
        results[message.id] = message.result.entry;
        completed += 1;
        if (message.result.converted) converted += 1;
        if (completed % 25 === 0 || completed === tasks.length) {
          console.log(`Processed ${completed}/${tasks.length} animations.`);
        }
        dispatch(worker);
      });
      worker.on('error', (error) => {
        if (failed) return;
        failed = true;
        stopWorkers().finally(() => reject(error));
      });
      dispatch(worker);
    }
  });
}

function summarizeCatalog(entries, complete) {
  const sortedEntries = [...entries].sort((left, right) => {
    const styleOrder = STYLES.indexOf(left.style) - STYLES.indexOf(right.style);
    return styleOrder || left.id.localeCompare(right.id);
  });
  const front = new Set(sortedEntries.filter((entry) => entry.style === 'ani').map((entry) => entry.id));
  const back = new Set(sortedEntries.filter((entry) => entry.style === 'ani-back').map((entry) => entry.id));
  const paired = [...front].filter((id) => back.has(id)).sort();
  const frontOnly = [...front].filter((id) => !back.has(id)).sort();
  const backOnly = [...back].filter((id) => !front.has(id)).sort();
  const variableDuration = sortedEntries.filter((entry) => entry.sourceFeatures.variableDuration).length;
  const interlaced = sortedEntries.filter((entry) => entry.sourceFeatures.interlacedFrames > 0).length;
  const disposal = sortedEntries.filter((entry) => entry.sourceFeatures.disposalModes.some((mode) => mode >= 2)).length;
  const offset = sortedEntries.filter((entry) => entry.sourceFeatures.offsetFrames > 0).length;
  const maximumFrameEntry = sortedEntries.reduce(
    (maximum, entry) => !maximum || entry.frameCount > maximum.frameCount ? entry : maximum,
    null
  );
  return {
    schemaVersion: CATALOG_SCHEMA_VERSION,
    generator: { name: PIPELINE_NAME, version: PIPELINE_VERSION },
    complete,
    styles: [...STYLES],
    totals: {
      animations: sortedEntries.length,
      frames: sortedEntries.reduce((sum, entry) => sum + entry.frameCount, 0),
      atlasBytes: sortedEntries.reduce((sum, entry) => sum + entry.atlasBytes, 0),
      front: front.size,
      back: back.size,
      paired: paired.length,
      frontOnly,
      backOnly,
      variableDurationAnimations: variableDuration,
      interlacedAnimations: interlaced,
      offsetAnimations: offset,
      disposalAnimations: disposal,
      maximumFrameCount: maximumFrameEntry ? maximumFrameEntry.frameCount : 0,
      maximumFrameAnimation: maximumFrameEntry ? `${maximumFrameEntry.style}/${maximumFrameEntry.id}` : '',
      absentBaseSpecies: complete ? [...EXPECTED_ABSENT_BASE_IDS] : [],
    },
    entries: sortedEntries,
  };
}

async function convertCorpus(sourceRoot, runtimeRoot, options) {
  const provenance = await verifySourceCorpus(sourceRoot);
  const provenanceByPath = new Map(provenance.files.map((entry) => [entry.path, entry]));
  const styles = selectedStyles(options);
  const ids = selectedIds(options);
  const allFiles = await listGifFiles(sourceRoot, styles);
  const selectedFiles = ids ? allFiles.filter((entry) => ids.has(entry.id)) : allFiles;
  if (ids) {
    const found = new Set(selectedFiles.map((entry) => entry.id));
    const missing = [...ids].filter((id) => !found.has(id));
    if (missing.length) throw new Error(`Requested exact sprite IDs are absent: ${missing.join(', ')}`);
  }
  const tasks = selectedFiles.map((entry) => {
    const provenanceEntry = provenanceByPath.get(entry.relativePath);
    if (!provenanceEntry) throw new Error(`No provenance for ${entry.relativePath}`);
    return {
      id: entry.id,
      style: entry.style,
      relativePath: entry.relativePath,
      sourcePath: entry.absolutePath,
      sourceSha256: provenanceEntry.sha256,
      atlasPath: path.join(runtimeRoot, entry.style, `${entry.id}.png`),
      manifestPath: path.join(runtimeRoot, entry.style, `${entry.id}.json`),
    };
  });
  const requestedConcurrency = Number.parseInt(String(options.concurrency || ''), 10);
  const concurrency = clamp(
    Number.isFinite(requestedConcurrency) ? requestedConcurrency : Math.min(4, os.availableParallelism()),
    1,
    16
  );
  const entries = await runConversionWorkers(tasks, concurrency, Boolean(options.force));
  const complete = !ids && styles.length === STYLES.length;
  const catalog = summarizeCatalog(entries, complete);
  if (complete) {
    if (catalog.totals.animations !== EXPECTED_SOURCE_COUNT) {
      throw new Error(`Converted ${catalog.totals.animations} animations; expected ${EXPECTED_SOURCE_COUNT}.`);
    }
    if (catalog.totals.frames !== EXPECTED_FRAME_COUNT) {
      throw new Error(`Converted ${catalog.totals.frames} frames; expected ${EXPECTED_FRAME_COUNT}.`);
    }
    if (catalog.totals.maximumFrameCount !== EXPECTED_MAX_FRAME_COUNT) {
      throw new Error(
        `Maximum frame count is ${catalog.totals.maximumFrameCount}; expected ${EXPECTED_MAX_FRAME_COUNT}.`
      );
    }
  }
  await writeJson(path.join(runtimeRoot, 'catalog.json'), catalog);
  return catalog;
}

async function verifyRuntimeCatalog(sourceRoot, runtimeRoot) {
  const provenance = await verifySourceCorpus(sourceRoot);
  const catalogPath = path.join(runtimeRoot, 'catalog.json');
  const catalog = await readJson(catalogPath);
  if (Number(catalog.schemaVersion) !== CATALOG_SCHEMA_VERSION || catalog.complete !== true) {
    throw new Error('Runtime catalog is not a complete supported catalog.');
  }
  const entries = Array.isArray(catalog.entries) ? catalog.entries : [];
  if (entries.length !== EXPECTED_SOURCE_COUNT) {
    throw new Error(`Runtime catalog has ${entries.length} animations; expected ${EXPECTED_SOURCE_COUNT}.`);
  }
  if (
    !Array.isArray(catalog.totals.absentBaseSpecies) ||
    stableJson(catalog.totals.absentBaseSpecies) !== stableJson(EXPECTED_ABSENT_BASE_IDS)
  ) {
    throw new Error('Runtime catalog does not preserve the verified 21-species absence list.');
  }

  const entrySourcePaths = entries.map((entry) => `${entry.style}/${entry.id}.gif`).sort();
  const provenancePaths = provenance.files.map((entry) => String(entry.path)).sort();
  if (stableJson(entrySourcePaths) !== stableJson(provenancePaths)) {
    throw new Error('Runtime catalog does not cover the exact provenanced source file set.');
  }
  const recomputedCatalog = summarizeCatalog(entries, true);
  if (stableJson(recomputedCatalog.totals) !== stableJson(catalog.totals)) {
    throw new Error('Runtime catalog totals or front/back pair coverage are inconsistent.');
  }
  if (
    recomputedCatalog.totals.front !== EXPECTED_STYLE_COUNTS.ani ||
    recomputedCatalog.totals.back !== EXPECTED_STYLE_COUNTS['ani-back'] ||
    recomputedCatalog.totals.paired !== EXPECTED_STYLE_COUNTS['ani-back'] ||
    stableJson(recomputedCatalog.totals.frontOnly) !== stableJson(['colossoil', 'pyroak']) ||
    recomputedCatalog.totals.backOnly.length !== 0
  ) {
    throw new Error('Runtime front/back pair coverage differs from the accepted corpus.');
  }
  const provenanceByPath = new Map(provenance.files.map((entry) => [String(entry.path), entry]));

  let frames = 0;
  let atlasBytes = 0;
  let maximumFrameCount = 0;
  let maximumFrameAnimation = '';
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    if (!STYLES.includes(entry.style) || !/^[a-z0-9-]+$/.test(entry.id)) {
      throw new Error(`Invalid exact runtime catalog identity: ${entry.style}/${entry.id}`);
    }
    const expectedManifestResource = projectResourcePath(
      path.join(runtimeRoot, entry.style, `${entry.id}.json`)
    );
    const expectedAtlasResource = projectResourcePath(
      path.join(runtimeRoot, entry.style, `${entry.id}.png`)
    );
    if (entry.manifest !== expectedManifestResource || entry.atlas !== expectedAtlasResource) {
      throw new Error(`Unexpected runtime resource path: ${entry.style}/${entry.id}`);
    }
    const manifestPath = path.join(PROJECT_ROOT, String(entry.manifest).replace(/^res:\/\//, ''));
    const atlasPath = path.join(PROJECT_ROOT, String(entry.atlas).replace(/^res:\/\//, ''));
    const manifest = await readJson(manifestPath);
    const provenanceEntry = provenanceByPath.get(`${entry.style}/${entry.id}.gif`);
    if (
      Number(manifest.schemaVersion) !== MANIFEST_SCHEMA_VERSION ||
      Number(manifest.generator && manifest.generator.version) !== PIPELINE_VERSION ||
      manifest.generator.gifuctJs !== '2.1.2' ||
      manifest.generator.pngjs !== '7.0.0' ||
      manifest.id !== entry.id ||
      manifest.style !== entry.style ||
      manifest.source.path !== `${entry.style}/${entry.id}.gif` ||
      manifest.atlas.path !== entry.atlas ||
      !provenanceEntry ||
      entry.sourceSha256 !== provenanceEntry.sha256 ||
      manifest.source.sha256 !== entry.sourceSha256 ||
      manifest.atlas.sha256 !== entry.atlasSha256 ||
      Number(manifest.frameCount) !== Number(entry.frameCount)
    ) {
      throw new Error(`Catalog/manifest mismatch: ${entry.style}/${entry.id}`);
    }
    const sourceBytes = await fsp.readFile(path.join(sourceRoot, manifest.source.path));
    const parsedGif = parseGIF(arrayBufferForBuffer(sourceBytes));
    const sourceContract = sourceFrameContract(parsedGif);
    if (
      Number(manifest.canvas.width) !== sourceContract.canvas.width ||
      Number(manifest.canvas.height) !== sourceContract.canvas.height ||
      Number(manifest.frameCount) !== sourceContract.frames.length ||
      stableJson(manifest.sourceFeatures) !== stableJson(sourceContract.sourceFeatures)
    ) {
      throw new Error(`Source GIF contract mismatch: ${entry.style}/${entry.id}`);
    }
    const atlasStat = await fsp.stat(atlasPath);
    if (atlasStat.size !== Number(entry.atlasBytes) || atlasStat.size >= MAX_GITHUB_OBJECT_BYTES) {
      throw new Error(`Atlas size mismatch or limit violation: ${entry.style}/${entry.id}`);
    }
    const atlasDigest = await sha256File(atlasPath);
    if (atlasDigest !== entry.atlasSha256) {
      throw new Error(`Atlas SHA-256 mismatch: ${entry.style}/${entry.id}`);
    }
    const atlasPng = PNG.sync.read(await fsp.readFile(atlasPath), { skipRescale: true });
    if (atlasPng.width !== entry.atlasWidth || atlasPng.height !== entry.atlasHeight) {
      throw new Error(`Atlas dimension mismatch: ${entry.style}/${entry.id}`);
    }
    if (!Array.isArray(manifest.frames) || manifest.frames.length !== entry.frameCount) {
      throw new Error(`Frame manifest mismatch: ${entry.style}/${entry.id}`);
    }
    const duration = manifest.frames.reduce((sum, frame) => sum + Number(frame.durationMs), 0);
    if (duration !== Number(manifest.durationMs)) {
      throw new Error(`Timing total mismatch: ${entry.style}/${entry.id}`);
    }
    for (let frameIndex = 0; frameIndex < manifest.frames.length; frameIndex += 1) {
      const frame = manifest.frames[frameIndex];
      const region = frame.region;
      const bounds = frame.alphaBounds;
      if (
        frame.index !== frameIndex ||
        Number(frame.durationMs) !== sourceContract.frames[frameIndex].durationMs ||
        region.width !== manifest.canvas.width ||
        region.height !== manifest.canvas.height ||
        region.x < 0 || region.y < 0 ||
        region.x + region.width > atlasPng.width ||
        region.y + region.height > atlasPng.height ||
        bounds.x < 0 || bounds.y < 0 ||
        bounds.x + bounds.width > manifest.canvas.width ||
        bounds.y + bounds.height > manifest.canvas.height
      ) {
        throw new Error(`Frame timing, region, or bounds are invalid: ${entry.style}/${entry.id}#${frameIndex}`);
      }
    }
    const identity = `${entry.style}/${entry.id}`;
    if (FOCUSED_RENDER_KEYS.has(identity)) {
      verifyFocusedRendering(parsedGif, manifest, atlasPng, identity);
    }
    frames += Number(entry.frameCount);
    atlasBytes += atlasStat.size;
    if (entry.frameCount > maximumFrameCount) {
      maximumFrameCount = entry.frameCount;
      maximumFrameAnimation = `${entry.style}/${entry.id}`;
    }
    if ((index + 1) % 100 === 0 || index + 1 === entries.length) {
      console.log(`Verified ${index + 1}/${entries.length} runtime atlases.`);
    }
  }

  if (frames !== EXPECTED_FRAME_COUNT || frames !== Number(catalog.totals.frames)) {
    throw new Error(`Runtime frame count is ${frames}; expected ${EXPECTED_FRAME_COUNT}.`);
  }
  if (
    maximumFrameCount !== EXPECTED_MAX_FRAME_COUNT ||
    maximumFrameAnimation !== 'ani/regieleki'
  ) {
    throw new Error(
      `Unexpected maximum animation: ${maximumFrameAnimation} (${maximumFrameCount} frames).`
    );
  }
  if (atlasBytes !== Number(catalog.totals.atlasBytes)) {
    throw new Error('Runtime atlas byte total does not match the catalog.');
  }
  return catalog;
}

function printSummary(catalog) {
  console.log(stableJson({ complete: catalog.complete, totals: catalog.totals }).trimEnd());
}

function printHelp() {
  console.log(`Usage:
  node sprite_pipeline.cjs sync-local --from=/path/to/pokemon-sprite [--source=/project/source]
  node sprite_pipeline.cjs convert [--source=/project/source] [--runtime=/project/runtime] [--concurrency=4] [--force]
  node sprite_pipeline.cjs convert --ids=ferroseed,regieleki [--styles=ani,ani-back]
  node sprite_pipeline.cjs verify-source [--source=/project/source]
  node sprite_pipeline.cjs verify-runtime [--source=/project/source] [--runtime=/project/runtime]
  node sprite_pipeline.cjs verify [--source=/project/source] [--runtime=/project/runtime]

The tool never downloads sprites. sync-local copies only from an explicitly supplied local corpus.`);
}

async function main(argv = process.argv.slice(2)) {
  const { command, options } = parseArgs(argv);
  const sourceRoot = optionPath(options, 'source', DEFAULT_SOURCE_ROOT);
  const runtimeRoot = optionPath(options, 'runtime', DEFAULT_RUNTIME_ROOT);
  if (command === 'sync-local') {
    const fromRoot = optionPath(options, 'from', '');
    if (!String(options.from || '').trim()) throw new Error('sync-local requires --from=/path/to/pokemon-sprite');
    const provenance = await syncLocalCorpus(fromRoot, sourceRoot);
    console.log(stableJson(provenance.totals).trimEnd());
    return;
  }
  if (command === 'convert') {
    printSummary(await convertCorpus(sourceRoot, runtimeRoot, options));
    return;
  }
  if (command === 'verify-source') {
    const provenance = await verifySourceCorpus(sourceRoot);
    console.log(stableJson(provenance.totals).trimEnd());
    return;
  }
  if (command === 'verify-runtime' || command === 'verify') {
    printSummary(await verifyRuntimeCatalog(sourceRoot, runtimeRoot));
    return;
  }
  if (command === 'help' || command === '--help' || command === '-h') {
    printHelp();
    return;
  }
  throw new Error(`Unknown command: ${command}`);
}

if (!isMainThread && workerData && workerData.pipelineWorker) {
  runWorkerThread().catch((error) => {
    throw error;
  });
} else if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.stack || error.message : String(error));
    process.exitCode = 1;
  });
}

module.exports = {
  ALPHA_THRESHOLD,
  ATLAS_PADDING,
  EXPECTED_ABSENT_BASE_IDS,
  EXPECTED_FRAME_COUNT,
  EXPECTED_SOURCE_COUNT,
  alphaBoundsForPixels,
  chooseAtlasGrid,
  normalizeFrameDelay,
  renderCompositedFrames,
  summarizeCatalog,
  unionBounds,
};
