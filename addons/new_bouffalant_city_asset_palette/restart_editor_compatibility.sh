#!/usr/bin/env bash
set -euo pipefail

task_previous_pid="${1:-}"
if [[ ! "$task_previous_pid" =~ ^[1-9][0-9]*$ ]]; then
	echo "Expected the current Godot process ID." >&2
	exit 2
fi

task_addon_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if kill -0 "$task_previous_pid" 2>/dev/null; then
	tail --pid="$task_previous_pid" -f /dev/null >/dev/null 2>&1
fi

exec "$task_addon_dir/open_editor_compatibility.sh"
