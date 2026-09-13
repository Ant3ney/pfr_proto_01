#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
stage_root="${1:-}"

if [[ -z "${stage_root}" || "${stage_root}" == "/" || "${stage_root}" == "${project_root}" ]]; then
	echo "Usage: tools/stage_loading_battle.sh /safe/empty/staging-directory" >&2
	exit 1
fi

mkdir -p \
	"${stage_root}/src" \
	"${stage_root}/tests" \
	"${stage_root}/shared" \
	"${stage_root}/art/battle/sprites/generated/ani" \
	"${stage_root}/art/battle/sprites/generated/ani-back"

cp \
	"${project_root}/loading_battle/project.godot" \
	"${project_root}/loading_battle/export_presets.cfg" \
	"${project_root}/loading_battle/main.tscn" \
	"${stage_root}/"
cp "${project_root}/loading_battle/src/"*.gd "${stage_root}/src/"
cp "${project_root}/loading_battle/tests/"* "${stage_root}/tests/"
cp \
	"${project_root}/game/battle/system/battle_rest_client.gd" \
	"${project_root}/game/battle/system/battle_dto_validator.gd" \
	"${project_root}/game/battle/system/battle_event_translator.gd" \
	"${stage_root}/shared/"

for sprite_id in charmander froakie treecko ditto wobbuffet; do
	cp \
		"${project_root}/art/battle/sprites/generated/ani/${sprite_id}.png" \
		"${project_root}/art/battle/sprites/generated/ani/${sprite_id}.json" \
		"${stage_root}/art/battle/sprites/generated/ani/"
done
for sprite_id in charmander froakie treecko; do
	cp \
		"${project_root}/art/battle/sprites/generated/ani-back/${sprite_id}.png" \
		"${project_root}/art/battle/sprites/generated/ani-back/${sprite_id}.json" \
		"${stage_root}/art/battle/sprites/generated/ani-back/"
done

node "${project_root}/tools/verify_loading_battle_stage.mjs" \
	"${stage_root}" \
	"${project_root}"

