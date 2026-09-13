import assert from 'node:assert/strict';
import test from 'node:test';

import {
	PATCHES,
	PATCH_MARKER,
	patchGodotWebLoader,
} from '../../tools/patch_godot_web_loader.mjs';

test('Godot 4.7.2 signatures receive every startup rejection patch', () => {
	const fixture = PATCHES.map((patch, index) => `// fixture ${index}\n${patch.before}`).join('\n');
	const patched = patchGodotWebLoader(fixture);
	assert.match(patched, new RegExp(PATCH_MARKER));
	for (const patch of PATCHES) {
		assert.equal(patched.includes(patch.before), false, patch.name);
		assert.equal(patched.includes(patch.after), true, patch.name);
	}
});

test('Godot loader patch fails closed when an expected source signature changes', () => {
	const fixture = PATCHES.map((patch) => patch.before).join('\n');
	const changed = fixture.replace(PATCHES[0].before, PATCHES[0].before.slice(1));
	assert.throws(
		() => patchGodotWebLoader(changed),
		/signature mismatch/,
	);
});

test('Godot loader patch refuses already-patched or duplicate input', () => {
	const fixture = PATCHES.map((patch) => patch.before).join('\n');
	const patched = patchGodotWebLoader(fixture);
	assert.throws(() => patchGodotWebLoader(patched), /already patched/);
	assert.throws(
		() => patchGodotWebLoader(`${fixture}\n${PATCHES[1].before}`),
		/signature mismatch/,
	);
});
