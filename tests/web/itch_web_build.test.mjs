import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  MAX_ITCH_HTML_FILE_BYTES,
  patchItchHtml,
} from '../../tools/prepare_itch_web_build.mjs';

const VERSIONED_SIGNATURE = (
  "const PFR_HAS_BUILD_VERSION = !PFR_BUILD_VERSION.startsWith('__PFR_');"
);

test('itch HTML staging disables range caching for its precompressed PCK', () => {
  const patched = patchItchHtml(`<script>${VERSIONED_SIGNATURE}</script>`);
  assert.match(patched, /const PFR_HAS_BUILD_VERSION = false;/);
  assert.doesNotMatch(patched, /startsWith\('__PFR_'\)/);
  assert.equal(MAX_ITCH_HTML_FILE_BYTES, 209_715_200);
});

test('itch HTML staging fails closed when the generated shell signature changes', () => {
  assert.throws(
    () => patchItchHtml('<script>const changed = true;</script>'),
    /Expected one versioned Web-cache signature, found 0/,
  );
  assert.throws(
    () => patchItchHtml(`${VERSIONED_SIGNATURE}\n${VERSIONED_SIGNATURE}`),
    /Expected one versioned Web-cache signature, found 2/,
  );
});
