@tool
extends RefCounted

const IMPORTED_MODEL_SCALE := 0.75
const PERFORMANCE_SENSITIVE_CATEGORY := "Complete Environment Sections"
const PERFORMANCE_SENSITIVE_TRIANGLE_COUNT := 25000
const PERFORMANCE_SENSITIVE_HORIZONTAL_EXTENT_M := 60.0
const COLLISION_POST_IMPORT_SCRIPT := (
	"res://art/environments/new_bouffalant_city/reference_city_pack/collision/"
	+ "city_asset_post_import.gd"
)
const CONFIRMED_INTEL_VULKAN_TRIGGER_IDS := {
	"t1_b_gate_building": true,
	"t1_b_museum": true,
}


static func is_imported_model(asset: Dictionary) -> bool:
	return String(asset.get("model_path", "")).ends_with(".glb")


static func is_confirmed_intel_vulkan_trigger(asset_or_id: Variant) -> bool:
	var asset_id := ""
	if asset_or_id is Dictionary:
		asset_id = String((asset_or_id as Dictionary).get("id", ""))
	else:
		asset_id = String(asset_or_id)
	return CONFIRMED_INTEL_VULKAN_TRIGGER_IDS.has(asset_id)


static func effective_dimensions(asset: Dictionary) -> Array[float]:
	var result: Array[float] = []
	var dimensions: Array = asset.get("dimensions", [])
	if dimensions.size() != 3:
		return result
	var factor := IMPORTED_MODEL_SCALE if is_imported_model(asset) else 1.0
	for value: Variant in dimensions:
		result.append(float(value) * factor)
	return result


static func is_performance_sensitive(asset: Dictionary) -> bool:
	if String(asset.get("category", "")) == PERFORMANCE_SENSITIVE_CATEGORY:
		return true
	if int(asset.get("triangles", 0)) >= PERFORMANCE_SENSITIVE_TRIANGLE_COUNT:
		return true
	var dimensions := effective_dimensions(asset)
	return (
		dimensions.size() == 3
		and maxf(float(dimensions[0]), float(dimensions[2]))
		>= PERFORMANCE_SENSITIVE_HORIZONTAL_EXTENT_M
	)


static func performance_summary(asset: Dictionary) -> String:
	return "%s triangles • %s mesh objects" % [
		_format_integer(int(asset.get("triangles", 0))),
		_format_integer(int(asset.get("mesh_objects", 0))),
	]


static func _format_integer(value: int) -> String:
	var text := str(value)
	var first_separator := text.length() % 3
	if first_separator == 0:
		first_separator = 3
	var result := text.left(first_separator)
	for index in range(first_separator, text.length(), 3):
		result += "," + text.substr(index, 3)
	return result
