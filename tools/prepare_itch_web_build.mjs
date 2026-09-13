#!/usr/bin/env node

import { createHash } from 'node:crypto';
import {
  createReadStream,
  createWriteStream,
  existsSync,
  promises as fs,
} from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { createGunzip, createGzip, constants as zlibConstants } from 'node:zlib';
import { pipeline } from 'node:stream/promises';

export const MAX_ITCH_HTML_FILE_BYTES = 200 * 1024 * 1024;

const VERSIONED_BUILD_SIGNATURE = (
  "const PFR_HAS_BUILD_VERSION = !PFR_BUILD_VERSION.startsWith('__PFR_');"
);
const ITCH_BUILD_SIGNATURE = (
  'const PFR_HAS_BUILD_VERSION = false; // Itch serves a precompressed PCK without range caching.'
);

export function patchItchHtml(source) {
  const matches = source.split(VERSIONED_BUILD_SIGNATURE).length - 1;
  if (matches !== 1) {
    throw new Error(`Expected one versioned Web-cache signature, found ${matches}.`);
  }
  return source.replace(VERSIONED_BUILD_SIGNATURE, ITCH_BUILD_SIGNATURE);
}

async function hashFile(filePath) {
  const hash = createHash('sha256');
  let bytes = 0;
  for await (const chunk of createReadStream(filePath)) {
    hash.update(chunk);
    bytes += chunk.length;
  }
  return { bytes, sha256: hash.digest('hex') };
}

async function hashGzipContents(filePath) {
  const hash = createHash('sha256');
  let bytes = 0;
  for await (const chunk of createReadStream(filePath).pipe(createGunzip())) {
    hash.update(chunk);
    bytes += chunk.length;
  }
  return { bytes, sha256: hash.digest('hex') };
}

async function prepare() {
  const projectRoot = path.resolve(import.meta.dirname, '..');
  const sourceRoot = path.join(projectRoot, 'build', 'web', 'v1');
  const outputRoot = path.join(projectRoot, 'build', 'itch', 'html5');
  const required = ['index.html', 'index.js', 'index.pck', 'index.wasm'];
  for (const fileName of required) {
    if (!existsSync(path.join(sourceRoot, fileName))) {
      throw new Error(`Build the Netlify Web export first; missing ${fileName}.`);
    }
  }

  await fs.mkdir(outputRoot, { recursive: true });
  for (const entry of await fs.readdir(outputRoot)) {
    await fs.rm(path.join(outputRoot, entry), { recursive: true, force: true });
  }
  await fs.cp(sourceRoot, outputRoot, { recursive: true });

  const htmlPath = path.join(outputRoot, 'index.html');
  const html = await fs.readFile(htmlPath, 'utf8');
  await fs.writeFile(htmlPath, patchItchHtml(html), 'utf8');

  const sourcePack = path.join(sourceRoot, 'index.pck');
  const outputPack = path.join(outputRoot, 'index.pck');
  const compressedPack = `${outputPack}.tmp.gz`;
  await pipeline(
    createReadStream(sourcePack),
    createGzip({
      level: zlibConstants.Z_BEST_COMPRESSION,
      mtime: 0,
    }),
    createWriteStream(compressedPack, { flags: 'wx' }),
  );
  await fs.rename(compressedPack, outputPack);

  const sourceIdentity = await hashFile(sourcePack);
  const restoredIdentity = await hashGzipContents(outputPack);
  if (
    restoredIdentity.bytes !== sourceIdentity.bytes
    || restoredIdentity.sha256 !== sourceIdentity.sha256
  ) {
    throw new Error('The precompressed itch.io PCK does not restore byte-for-byte.');
  }
  const compressedBytes = (await fs.stat(outputPack)).size;
  if (compressedBytes > MAX_ITCH_HTML_FILE_BYTES) {
    throw new Error(
      `The itch.io PCK is ${(compressedBytes / 1024 / 1024).toFixed(2)} MiB; `
      + 'the browser-upload limit is 200 MiB.',
    );
  }

  console.log(JSON.stringify({
    output: path.relative(projectRoot, outputRoot),
    sourcePackBytes: sourceIdentity.bytes,
    compressedPackBytes: compressedBytes,
    compressedPackMiB: Number((compressedBytes / 1024 / 1024).toFixed(2)),
    itchFileLimitMiB: 200,
    restoredSha256: restoredIdentity.sha256,
    rangeCacheDisabled: true,
  }, null, 2));
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(import.meta.filename)) {
  prepare().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
