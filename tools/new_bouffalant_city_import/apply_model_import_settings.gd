extends SceneTree

const RuntimeContract := preload("res://game/world/level_kits/structures/new_bouffalant_city/runtime_contract.gd")
const MODELS_DIRECTORY := (
	"res://art/environments/new_bouffalant_city/reference_city_pack/models"
)


func _initialize() -> void:
	var updated_files := 0
	var unchanged_files := 0
	var failed_files := 0
	var filenames := DirAccess.get_files_at(MODELS_DIRECTORY)
	filenames.sort()
	for filename: String in filenames:
		if not filename.ends_with(".glb.import"):
			continue
		var import_path := MODELS_DIRECTORY.path_join(filename)
		var result := _update_import_file(import_path)
		match result:
			OK:
				updated_files += 1
			ERR_ALREADY_EXISTS:
				unchanged_files += 1
			_:
				failed_files += 1

	print(
		(
			"Bouffalant model import settings: %d updated, %d already configured, "
			+ "%d failed (baked scale %.2f)."
		)
		% [
			updated_files,
			unchanged_files,
			failed_files,
			RuntimeContract.IMPORTED_MODEL_SCALE,
		]
	)
	quit(0 if failed_files == 0 else 1)


func _update_import_file(import_path: String) -> Error:
	var source := FileAccess.get_file_as_string(import_path)
	var lines := source.split("\n")
	var asset_id := import_path.get_file().trim_suffix(".glb.import")
	var use_original_mesh_buffers := RuntimeContract.uses_vulkan_safe_mesh_import(asset_id)
	var generate_optimized_buffers := "false" if use_original_mesh_buffers else "true"
	var required_settings := {
		"nodes/apply_root_scale=": "nodes/apply_root_scale=true",
		"nodes/root_scale=": "nodes/root_scale=%s" % RuntimeContract.IMPORTED_MODEL_SCALE,
		"meshes/generate_lods=": (
			"meshes/generate_lods=%s" % generate_optimized_buffers
		),
		"meshes/create_shadow_meshes=": (
			"meshes/create_shadow_meshes=%s" % generate_optimized_buffers
		),
		"import_script/path=": (
			'import_script/path="%s"' % RuntimeContract.COLLISION_POST_IMPORT_SCRIPT
		),
	}
	var changed := false
	for setting_prefix: String in required_settings:
		var found_setting := false
		for index in range(lines.size()):
			if not lines[index].begins_with(setting_prefix):
				continue
			found_setting = true
			var expected: String = required_settings[setting_prefix]
			if lines[index] != expected:
				lines[index] = expected
				changed = true
			break
		if not found_setting:
			push_error("Missing %s setting: %s" % [setting_prefix, import_path])
			return ERR_INVALID_DATA

	if not changed:
		return ERR_ALREADY_EXISTS
	var file := FileAccess.open(import_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not update import settings: %s" % import_path)
		return ERR_CANT_OPEN
	file.store_string("\n".join(lines))
	return OK
