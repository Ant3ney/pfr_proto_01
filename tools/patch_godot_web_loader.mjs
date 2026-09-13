#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const PATCH_MARKER = 'PFR_GODOT_LOADER_PATCH_4_7_2';

export const PATCHES = Object.freeze([
	{
		name: 'response body rejection propagation',
		before: `\t\t\t\tonloadprogress(reader, controller).then(function () {
\t\t\t\t\tcontroller.close();
\t\t\t\t});`,
		after: `\t\t\t\tonloadprogress(reader, controller).then(function () {
\t\t\t\t\tcontroller.close();
\t\t\t\t}).catch(function (error) {
\t\t\t\t\tload_status.done = true;
\t\t\t\t\tcontroller.error(error);
\t\t\t\t});`,
	},
	{
		name: 'WebAssembly streaming rejection propagation',
		before: '}catch(reason){err(`wasm streaming compile failed: ${reason}`);err("falling back to ArrayBuffer instantiation")}}return instantiateArrayBuffer(binaryFile,imports)}',
		after: '}catch(reason){err(`wasm streaming compile failed: ${reason}`);throw reason}}return instantiateArrayBuffer(binaryFile,imports)}',
	},
	{
		name: 'custom WebAssembly instantiation rejection bridge',
		before: 'if(Module["instantiateWasm"]){return new Promise((resolve,reject)=>{Module["instantiateWasm"](info,(inst,mod)=>{resolve(receiveInstance(inst,mod))})})}',
		after: 'if(Module["instantiateWasm"]){return new Promise((resolve,reject)=>{Promise.resolve(Module["instantiateWasm"](info,(inst,mod)=>{resolve(receiveInstance(inst,mod))})).catch(reject)})}',
	},
	{
		name: 'opaque download retry removal',
		before: '\tconst DOWNLOAD_ATTEMPTS_MAX = 4;',
		after: `\tconst DOWNLOAD_ATTEMPTS_MAX = 1; // ${PATCH_MARKER}`,
	},
	{
		name: 'engine and filesystem initialization rejection propagation',
		before: `\t\t\t\t\treturn new Promise(function (resolve, reject) {
\t\t\t\t\t\tpromise.then(function (response) {
\t\t\t\t\t\t\tconst cloned = new Response(response.clone().body, { 'headers': [['content-type', 'application/wasm']] });
\t\t\t\t\t\t\tGodot(me.config.getModuleConfig(loadPath, cloned)).then(function (module) {
\t\t\t\t\t\t\t\tconst paths = me.config.persistentPaths;
\t\t\t\t\t\t\t\tmodule['initFS'](paths).then(function (err) {
\t\t\t\t\t\t\t\t\tme.rtenv = module;
\t\t\t\t\t\t\t\t\tif (me.config.unloadAfterInit) {
\t\t\t\t\t\t\t\t\t\tEngine.unload();
\t\t\t\t\t\t\t\t\t}
\t\t\t\t\t\t\t\t\tresolve();
\t\t\t\t\t\t\t\t});
\t\t\t\t\t\t\t});
\t\t\t\t\t\t});
\t\t\t\t\t});`,
		after: `\t\t\t\t\treturn promise.then(function (response) {
\t\t\t\t\t\tconst cloned = new Response(response.clone().body, { 'headers': [['content-type', 'application/wasm']] });
\t\t\t\t\t\treturn Godot(me.config.getModuleConfig(loadPath, cloned));
\t\t\t\t\t}).then(function (module) {
\t\t\t\t\t\tconst paths = me.config.persistentPaths;
\t\t\t\t\t\treturn module['initFS'](paths).then(function (err) {
\t\t\t\t\t\t\tif (err) {
\t\t\t\t\t\t\t\tthrow err instanceof Error ? err : new Error(String(err));
\t\t\t\t\t\t\t}
\t\t\t\t\t\t\tme.rtenv = module;
\t\t\t\t\t\t\tif (me.config.unloadAfterInit) {
\t\t\t\t\t\t\t\tEngine.unload();
\t\t\t\t\t\t\t}
\t\t\t\t\t\t});
\t\t\t\t\t});`,
	},
	{
		name: 'engine start rejection propagation',
		before: `\t\t\t\t\treturn new Promise(function (resolve, reject) {
\t\t\t\t\t\tfor (const file of preloader.preloadedFiles) {
\t\t\t\t\t\t\tme.rtenv['copyToFS'](file.path, file.buffer);
\t\t\t\t\t\t}
\t\t\t\t\t\tpreloader.preloadedFiles.length = 0; // Clear memory
\t\t\t\t\t\tme.rtenv['callMain'](me.config.args);
\t\t\t\t\t\tinitPromise = null;
\t\t\t\t\t\tme.installServiceWorker();
\t\t\t\t\t\tresolve();
\t\t\t\t\t});`,
		after: `\t\t\t\t\tfor (const file of preloader.preloadedFiles) {
\t\t\t\t\t\tme.rtenv['copyToFS'](file.path, file.buffer);
\t\t\t\t\t}
\t\t\t\t\tpreloader.preloadedFiles.length = 0; // Clear memory
\t\t\t\t\tme.rtenv['callMain'](me.config.args);
\t\t\t\t\tinitPromise = null;
\t\t\t\t\treturn me.installServiceWorker();`,
	},
	{
		name: 'Godot WebAssembly instantiation promise propagation',
		before: `\t\t\t'instantiateWasm': function (imports, onSuccess) {
\t\t\t\tfunction done(result) {
\t\t\t\t\tonSuccess(result['instance'], result['module']);
\t\t\t\t}
\t\t\t\tif (typeof (WebAssembly.instantiateStreaming) !== 'undefined') {
\t\t\t\t\tWebAssembly.instantiateStreaming(Promise.resolve(r), imports).then(done);
\t\t\t\t} else {
\t\t\t\t\tr.arrayBuffer().then(function (buffer) {
\t\t\t\t\t\tWebAssembly.instantiate(buffer, imports).then(done);
\t\t\t\t\t});
\t\t\t\t}
\t\t\t\tr = null;
\t\t\t\treturn {};
\t\t\t},`,
		after: `\t\t\t'instantiateWasm': function (imports, onSuccess) {
\t\t\t\tfunction done(result) {
\t\t\t\t\tonSuccess(result['instance'], result['module']);
\t\t\t\t}
\t\t\t\tlet instantiatePromise;
\t\t\t\tif (typeof (WebAssembly.instantiateStreaming) !== 'undefined') {
\t\t\t\t\tinstantiatePromise = WebAssembly.instantiateStreaming(Promise.resolve(r), imports);
\t\t\t\t} else {
\t\t\t\t\tinstantiatePromise = r.arrayBuffer().then(function (buffer) {
\t\t\t\t\t\treturn WebAssembly.instantiate(buffer, imports);
\t\t\t\t\t});
\t\t\t\t}
\t\t\t\tr = null;
\t\t\t\treturn instantiatePromise.then(done);
\t\t\t},`,
	},
]);

function occurrenceCount(source, signature) {
	let count = 0;
	let offset = 0;
	while ((offset = source.indexOf(signature, offset)) !== -1) {
		count += 1;
		offset += signature.length;
	}
	return count;
}

export function patchGodotWebLoader(source) {
	if (source.includes(PATCH_MARKER)) {
		throw new Error('Godot web loader is already patched; expected a fresh 4.7.2 export.');
	}

	let patched = source;
	for (const patch of PATCHES) {
		const matches = occurrenceCount(patched, patch.before);
		if (matches !== 1) {
			throw new Error(
				`Godot 4.7.2 loader signature mismatch for ${patch.name}: expected 1 match, found ${matches}.`,
			);
		}
		patched = patched.replace(patch.before, patch.after);
	}

	return patched;
}

async function main() {
	const [loaderPath] = process.argv.slice(2);
	if (!loaderPath) {
		throw new Error('Usage: node tools/patch_godot_web_loader.mjs <generated-index.js>');
	}
	const source = await readFile(loaderPath, 'utf8');
	const patched = patchGodotWebLoader(source);
	await writeFile(loaderPath, patched);
	process.stdout.write(`Patched ${loaderPath} for bounded, observable startup failures.\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main().catch((error) => {
		console.error(error.message);
		process.exitCode = 1;
	});
}
