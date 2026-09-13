#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
godot_version="${GODOT_VERSION:-4.7.2}"
godot_release="${godot_version}-stable"
godot_archive_name="Godot_v${godot_release}_linux.x86_64.zip"
release_url="https://github.com/godotengine/godot/releases/download/${godot_release}"
cache_root="${XDG_CACHE_HOME:-${HOME}/.cache}/pfr-netlify-godot/${godot_release}"
downloaded_godot="${cache_root}/Godot_v${godot_release}_linux.x86_64"
template_root="${XDG_DATA_HOME:-${HOME}/.local/share}/godot/export_templates/${godot_version}.stable"
web_template_name="web_nothreads_release.zip"
web_template_sha256="d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0"
template_archive_url="https://downloads.godotengine.org/?version=${godot_version}&flavor=stable&slug=export_templates.tpz&platform=templates"
godot_bin=""

npm --prefix "${project_root}" run test:cloud-save
npm --prefix "${project_root}" run test:web-loader

download_file() {
	local url="$1"
	local destination="$2"

	curl \
		--fail \
		--location \
		--retry 4 \
		--retry-all-errors \
		--silent \
		--show-error \
		--output "${destination}" \
		"${url}"
}

if command -v godot >/dev/null 2>&1 && godot --headless --version | grep -q "^${godot_version}\.stable"; then
	godot_bin="$(command -v godot)"
else
	mkdir -p "${cache_root}"
	if [[ ! -x "${downloaded_godot}" ]]; then
		editor_archive="${cache_root}/${godot_archive_name}"
		download_file "${release_url}/${godot_archive_name}" "${editor_archive}"
		unzip -q -o "${editor_archive}" -d "${cache_root}"
		chmod +x "${downloaded_godot}"
	fi
	godot_bin="${downloaded_godot}"
fi

if [[ ! -f "${template_root}/${web_template_name}" ]] || \
	! printf '%s  %s\n' "${web_template_sha256}" "${template_root}/${web_template_name}" | sha256sum --check --status; then
	python3 "${project_root}/tools/fetch_remote_zip_entry.py" \
		"${template_archive_url}" \
		"templates/${web_template_name}" \
		"${template_root}/${web_template_name}" \
		--sha256 "${web_template_sha256}"
fi

mkdir -p "${project_root}/build/web/v1"
web_output="${project_root}/build/web/v1"
loading_battle_stage="$(mktemp -d "${TMPDIR:-/tmp}/pfr-loading-battle.XXXXXX")"
trap 'rm -rf -- "${loading_battle_stage}"' EXIT

bash "${project_root}/tools/stage_loading_battle.sh" "${loading_battle_stage}"
"${godot_bin}" \
	--quiet \
	--headless \
	--path "${loading_battle_stage}" \
	--import
"${godot_bin}" \
	--headless \
	--path "${loading_battle_stage}" \
	--scene res://tests/loading_battle_smoke_test.tscn
"${godot_bin}" \
	--quiet \
	--headless \
	--path "${loading_battle_stage}" \
	--export-pack LoadingBattlePack \
	"${web_output}/pfr-loading-battle.pck"
node "${project_root}/tools/verify_loading_battle_pack.mjs" \
	"${web_output}/pfr-loading-battle.pck"

"${godot_bin}" \
	--quiet \
	--headless \
	--path "${project_root}" \
	--export-release WebBuild \
	"${web_output}/index.html"

for artifact in index.html index.js index.pck index.wasm pfr-loading-battle.pck; do
	test -s "${web_output}/${artifact}"
done

node "${project_root}/tools/patch_godot_web_loader.mjs" \
	"${web_output}/index.js"

if ! grep -q '"experimentalVK":true' "${web_output}/index.html"; then
	echo "Web export must embed touchscreen virtual-keyboard support." >&2
	exit 1
fi

cache_worker_template="${project_root}/addons/plain_http_lan_web/pfr_cache_service_worker.js"
node "${project_root}/tools/finalize_web_export.mjs" \
	"${web_output}" \
	"${cache_worker_template}"

test -s "${web_output}/pfr-cache-sw.js"
test -s "${web_output}/pfr-asset-manifest.json"
if grep -Eq '__PFR_[A-Z_]+__|\$GODOT_[A-Z_]+' \
	"${web_output}/index.html" \
	"${web_output}/pfr-cache-sw.js"; then
	echo "A generated web loader placeholder was not replaced." >&2
	exit 1
fi

node --check "${web_output}/index.js"
node --check "${web_output}/pfr-cache-sw.js"
node "${project_root}/tools/verify_web_loader.mjs" "${web_output}"
node "${project_root}/tools/battle_sprite_pipeline/verify_export_pack.cjs" \
	"${web_output}/index.pck"

"${godot_bin}" \
	--quiet \
	--headless \
	--main-pack "${web_output}/pfr-loading-battle.pck" \
	--quit-after 2

"${godot_bin}" \
	--quiet \
	--headless \
	--main-pack "${project_root}/build/web/v1/index.pck" \
	--script "${project_root}/tools/verify_web_export.gd"
