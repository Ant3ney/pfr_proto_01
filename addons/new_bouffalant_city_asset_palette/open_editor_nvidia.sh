#!/usr/bin/env bash
set -euo pipefail

task_addon_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
task_project_dir="$(cd -- "$task_addon_dir/../.." && pwd -P)"

exec godot --rendering-driver vulkan --gpu-index 1 --path "$task_project_dir" --editor "$@"
