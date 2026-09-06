extends SceneTree

const RuntimeContract := preload("res://game/world/level_kits/structures/new_bouffalant_city/runtime_contract.gd")
const CATALOG_PATH := "res://art/environments/new_bouffalant_city/reference_city_pack/catalog.json"
const SHOWCASE_PATH := (
	"res://art/environments/new_bouffalant_city/reference_city_pack/showcase/"
	+ "building_ground_metric_showcase.tscn"
)


func _initialize() -> void:
	var assets_by_id := _load_assets_by_id()
	if assets_by_id.is_empty():
		quit(1)
		return
	var source := FileAccess.get_file_as_string(SHOWCASE_PATH)
	var lines := source.split("\n")
	var output := PackedStringArray()
	var current_asset: Dictionary = {}
	var current_node_kind := ""
	var updated_assets := {}
	var index := 0
	while index < lines.size():
		var line := String(lines[index])
		if line.begins_with("[node "):
			current_node_kind = ""
			if line.contains('name="PlayerScaleReference"'):
				current_node_kind = "player_reference"
			elif line.contains('name="DimensionsLabel"'):
				current_node_kind = "dimensions_label"

		if line.begins_with("metadata/asset_id = "):
			var asset_id := line.trim_prefix('metadata/asset_id = "').trim_suffix('"')
			current_asset = assets_by_id.get(asset_id, {})

		if line.begins_with("editor_description = \"") and line.contains(": native bounds"):
			var asset_id := line.trim_prefix('editor_description = "').get_slice(":", 0)
			var described_asset: Dictionary = assets_by_id.get(asset_id, {})
			if RuntimeContract.is_imported_model(described_asset):
				line = _editor_description(asset_id, described_asset)

		if line.begins_with("metadata/native_dimensions_m = ") and RuntimeContract.is_imported_model(current_asset):
			output.append(line)
			output.append(_runtime_dimensions_metadata(current_asset))
			updated_assets[String(current_asset.get("id", ""))] = true
			if (
				index + 1 < lines.size()
				and String(lines[index + 1]).begins_with("metadata/runtime_dimensions_m = ")
			):
				index += 1
			index += 1
			continue

		if (
			line.begins_with("position = ")
			and RuntimeContract.is_imported_model(current_asset)
		):
			if current_node_kind == "player_reference":
				line = _player_reference_position(current_asset)
			elif current_node_kind == "dimensions_label":
				line = _dimensions_label_position(current_asset)
		elif (
			line.begins_with('text = "')
			and current_node_kind == "dimensions_label"
			and RuntimeContract.is_imported_model(current_asset)
		):
			line = _dimensions_label_text(line, current_asset)

		if line.begins_with("editor_description = \"True-metric environment atlas."):
			line = (
				"editor_description = \"Player-calibrated environment atlas. The 147 transferred "
				+ "GLBs bake a 0.75 import factor while every instance remains scale 1,1,1; "
				+ "the 11 authored ground modules retain exact 2/4 m dimensions. Wrappers use "
				+ "the 0.5 m grid and cyan capsules are 1.67 m player references.\""
			)

		output.append(line)
		index += 1

	if updated_assets.size() != 147:
		push_error(
			"Expected to annotate 147 imported GLBs, updated %d." % updated_assets.size()
		)
		quit(1)
		return
	var file := FileAccess.open(SHOWCASE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not update showcase annotations: %s" % SHOWCASE_PATH)
		quit(1)
		return
	file.store_string("\n".join(output))
	print("Updated runtime-scale annotations for %d showcase assets." % updated_assets.size())
	quit(0)


func _load_assets_by_id() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not (parsed is Dictionary):
		push_error("Could not parse catalog: %s" % CATALOG_PATH)
		return {}
	var result := {}
	for value: Variant in parsed.get("assets", []):
		var asset: Dictionary = value
		result[String(asset.get("id", ""))] = asset
	return result


func _editor_description(asset_id: String, asset: Dictionary) -> String:
	var source_dimensions: Array = asset.get("dimensions", [])
	var runtime_dimensions := RuntimeContract.effective_dimensions(asset)
	return (
		'editor_description = "%s: source bounds %.2f × %.2f × %.2f m; '
		+ "runtime bounds %.2f × %.2f × %.2f m after the baked %.2f import. "
		+ "Wrapper and imported root remain scale 1,1,1 on the 0.5 m grid.\""
	) % [
		asset_id,
		float(source_dimensions[0]),
		float(source_dimensions[1]),
		float(source_dimensions[2]),
		runtime_dimensions[0],
		runtime_dimensions[1],
		runtime_dimensions[2],
		RuntimeContract.IMPORTED_MODEL_SCALE,
	]


func _runtime_dimensions_metadata(asset: Dictionary) -> String:
	var dimensions := RuntimeContract.effective_dimensions(asset)
	return "metadata/runtime_dimensions_m = Vector3(%.5f, %.5f, %.5f)" % dimensions


func _player_reference_position(asset: Dictionary) -> String:
	var dimensions := RuntimeContract.effective_dimensions(asset)
	return "position = Vector3(%.6f, 0.835, %.6f)" % [
		-dimensions[0] * 0.5 - 1.25,
		dimensions[2] * 0.5 + 1.25,
	]


func _dimensions_label_position(asset: Dictionary) -> String:
	var dimensions := RuntimeContract.effective_dimensions(asset)
	return "position = Vector3(0, 2.7, %.6f)" % (dimensions[2] * 0.5 + 2.2)


func _dimensions_label_text(current_line: String, asset: Dictionary) -> String:
	var title_literal := current_line.get_slice("\\n", 0)
	var dimensions := RuntimeContract.effective_dimensions(asset)
	return '%s\\n%.1f × %.1f × %.1f m  |  baked 75%%, node scale 1"' % [
		title_literal,
		dimensions[0],
		dimensions[1],
		dimensions[2],
	]
