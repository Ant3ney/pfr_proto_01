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
"${godot_bin}" \
	--quiet \
	--headless \
	--path "${project_root}" \
	--export-release WebBuild \
	"${project_root}/build/web/v1/index.html"

for artifact in index.html index.js index.pck index.wasm; do
	test -s "${project_root}/build/web/v1/${artifact}"
done
