'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  alphaBoundsForPixels,
  chooseAtlasGrid,
  normalizeFrameDelay,
  renderCompositedFrames,
  unionBounds,
} = require('./sprite_pipeline.cjs');

function patch(red, green, blue, alpha = 255) {
  return new Uint8ClampedArray([red, green, blue, alpha]);
}

function frame(left, color, disposalType = 1, delay = 100) {
  return {
    dims: { left, top: 0, width: 1, height: 1 },
    patch: color,
    disposalType,
    delay,
  };
}

function pixel(renderedFrame, x) {
  return [...renderedFrame.pixels.slice(x * 4, x * 4 + 4)];
}

test('frame delays preserve positive GIF timing and normalize missing timing', () => {
  assert.equal(normalizeFrameDelay(20), 20);
  assert.equal(normalizeFrameDelay(130), 130);
  assert.equal(normalizeFrameDelay(0), 100);
  assert.equal(normalizeFrameDelay(Number.NaN), 100);
});

test('restore-to-background disposal clears only the preceding frame rectangle', () => {
  const rendered = renderCompositedFrames([
    {
      dims: { left: 0, top: 0, width: 2, height: 1 },
      patch: new Uint8ClampedArray([255, 0, 0, 255, 255, 0, 0, 255]),
      disposalType: 1,
      delay: 100,
    },
    frame(0, patch(0, 255, 0), 2),
    frame(1, patch(0, 0, 255), 1),
  ], 2, 1);

  assert.deepEqual(pixel(rendered[1], 0), [0, 255, 0, 255]);
  assert.deepEqual(pixel(rendered[1], 1), [255, 0, 0, 255]);
  assert.equal(pixel(rendered[2], 0)[3], 0);
  assert.deepEqual(pixel(rendered[2], 1), [0, 0, 255, 255]);
});

test('restore-to-previous disposal reinstates the canvas before the patch', () => {
  const rendered = renderCompositedFrames([
    {
      dims: { left: 0, top: 0, width: 2, height: 1 },
      patch: new Uint8ClampedArray([255, 0, 0, 255, 255, 0, 0, 255]),
      disposalType: 1,
      delay: 100,
    },
    frame(0, patch(0, 255, 0), 3),
    frame(1, patch(0, 0, 255), 1),
  ], 2, 1);

  assert.deepEqual(pixel(rendered[1], 0), [0, 255, 0, 255]);
  assert.deepEqual(pixel(rendered[2], 0), [255, 0, 0, 255]);
  assert.deepEqual(pixel(rendered[2], 1), [0, 0, 255, 255]);
});

test('alpha bounds and their union stay inside the logical GIF canvas', () => {
  const pixels = new Uint8ClampedArray(4 * 3 * 4);
  pixels[(1 * 4 + 2) * 4 + 3] = 255;
  pixels[(2 * 4 + 3) * 4 + 3] = 255;
  assert.deepEqual(alphaBoundsForPixels(pixels, 4, 3), {
    x: 2,
    y: 1,
    width: 2,
    height: 2,
  });
  assert.deepEqual(unionBounds([
    { x: 2, y: 1, width: 2, height: 2 },
    { x: 0, y: 0, width: 1, height: 1 },
  ]), { x: 0, y: 0, width: 4, height: 3 });
});

test('atlas grid balances non-square frame cells without dropping a frame', () => {
  const grid = chooseAtlasGrid(315, 104, 88);
  assert.ok(grid.columns * grid.rows >= 315);
  assert.equal(grid.width, grid.columns * 104);
  assert.equal(grid.height, grid.rows * 88);
  assert.ok(grid.columns > 1);
  assert.ok(grid.rows > 1);
});
