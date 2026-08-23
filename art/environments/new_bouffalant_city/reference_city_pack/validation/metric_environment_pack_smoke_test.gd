extends Node

const CATALOG_PATH := "res://art/environments/new_bouffalant_city/reference_city_pack/catalog.json"
const SHOWCASE_SCENE := preload("res://art/environments/new_bouffalant_city/reference_city_pack/showcase/building_ground_metric_showcase.tscn")
const MAX_MODULAR_ARCHITECTURE_HORIZONTAL_EXTENT_M := 16.0
const CATEGORY_NODES := {
	"Landmarks": "Landmarks",
	"Shops & Hospitality": "ShopsAndHospitality",
	"Bridges & Architecture": "BridgesAndArchitecture",
	"Modular Architecture": "ModularArchitecture",
	"Modular Ground": "ModularGround",
	"Outdoor Routes": "OutdoorRoutes",
	"Complete Environment Sections": "CompleteEnvironmentSections",
}
const SNAP_METERS := 0.5


func _ready() -> void:
	var catalog := _load_and_validate_catalog()
	if catalog.is_empty():
		get_tree().quit(1)
		return

	var showcase := SHOWCASE_SCENE.instantiate()
	add_child(showcase)
	await get_tree().process_frame

	var expected_ids_by_node := _catalog_ids_by_scene_node(catalog)
	var seen_ids := {}
	var asset_count := 0
	for catalog_category: String in CATEGORY_NODES:
		var category_name := str(CATEGORY_NODES[catalog_category])
		var category := showcase.get_node_or_null(category_name)
		if category == null:
			_fail("Metric showcase category is missing: %s" % category_name)
			return
		var expected_ids: Dictionary = expected_ids_by_node.get(category_name, {})
		if category.get_child_count() != expected_ids.size():
			_fail(
				"%s has %d metric slots; expected %d."
				% [category_name, category.get_child_count(), expected_ids.size()]
			)
			return

		for slot: Node in category.get_children():
			asset_count += 1
			if not (slot is Node3D):
				_fail("Metric asset slot is not Node3D: %s" % slot.name)
				return
			var slot_3d := slot as Node3D
			if not slot_3d.scale.is_equal_approx(Vector3.ONE):
				_fail("Metric wrapper is scaled: %s" % slot.name)
				return
			if not _vector_is_snapped(slot_3d.position, SNAP_METERS):
				_fail("Metric wrapper is off the 0.5 m grid: %s" % slot.name)
				return
			if not is_equal_approx(snappedf(slot_3d.rotation_degrees.y, 90.0), slot_3d.rotation_degrees.y):
				_fail("Metric wrapper rotation is not a 90 degree increment: %s" % slot.name)
				return

			var model := slot.get_node_or_null("Model") as Node3D
			if model == null or not model.scale.is_equal_approx(Vector3.ONE):
				_fail("Imported model is missing or not at scale 1,1,1: %s" % slot.name)
				return
			if catalog_category == "Modular Ground" and not _validate_ground_collision(model, slot.name):
				return
			var asset_id := str(slot.get_meta("asset_id", ""))
			if asset_id.is_empty() or seen_ids.has(asset_id):
				_fail("Metric showcase has a missing or duplicate asset ID: %s" % asset_id)
				return
			if not expected_ids.has(asset_id):
				_fail("Metric showcase has an unexpected asset in %s: %s" % [category_name, asset_id])
				return
			seen_ids[asset_id] = true
	if asset_count != int(catalog.get("asset_count", -1)):
		_fail("Metric showcase asset total does not match the catalog.")
		return

	var player_reference := showcase.get_node_or_null("MetricScaleReference/Player1_67m") as MeshInstance3D
	if player_reference == null or not (player_reference.mesh is CapsuleMesh):
		_fail("The 1.67 m player scale reference is missing.")
		return
	var capsule := player_reference.mesh as CapsuleMesh
	if not is_equal_approx(capsule.height, 1.67):
		_fail("Player scale reference is not 1.67 m tall.")
		return

	print(
		"Metric environment showcase smoke test passed: %d assets at scale 1 on the %.1f m grid."
		% [asset_count, SNAP_METERS]
	)
	get_tree().quit(0)


func _load_and_validate_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		_fail("Catalog is missing: %s" % CATALOG_PATH)
		return {}
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		_fail("Catalog could not be opened.")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_fail("Catalog JSON is invalid.")
		return {}
	var catalog: Dictionary = parsed
	var raw_assets: Variant = catalog.get("assets", [])
	if not (raw_assets is Array):
		_fail("Catalog has no assets array.")
		return {}
	var catalog_asset_count := int(catalog.get("asset_count", -1))
	if catalog_asset_count <= 0 or catalog_asset_count != raw_assets.size():
		_fail("Catalog asset_count does not match its non-empty assets array.")
		return {}
	var failures: Variant = catalog.get("failures", [])
	if not (failures is Array) or not failures.is_empty():
		_fail("Catalog contains conversion failures.")
		return {}

	var seen_catalog_ids := {}
	for raw_asset: Variant in raw_assets:
		if not (raw_asset is Dictionary):
			_fail("Catalog contains a non-dictionary asset entry.")
			return {}
		var entry: Dictionary = raw_asset
		var asset_id := str(entry.get("id", ""))
		if asset_id.is_empty() or seen_catalog_ids.has(asset_id):
			_fail("Catalog contains a missing or duplicate asset ID: %s" % asset_id)
			return {}
		seen_catalog_ids[asset_id] = true
		var model_path := str(entry.get("model_path", ""))
		if model_path.is_empty() or not FileAccess.file_exists(model_path):
			_fail("Converted model is missing: %s" % model_path)
			return {}
		var category := str(entry.get("category", ""))
		if not CATEGORY_NODES.has(category):
			_fail("Catalog contains an unsupported showcase category: %s" % category)
			return {}
		if category == "Modular Architecture":
			if str(entry.get("kind", "")).begins_with("complete_"):
				_fail("Metric Modular Architecture contains a complete assembly: %s" % asset_id)
				return {}
			var architecture_dimensions: Variant = entry.get("dimensions", [])
			if not (architecture_dimensions is Array) or architecture_dimensions.size() != 3:
				_fail("Metric Modular Architecture asset has invalid dimensions: %s" % asset_id)
				return {}
			var horizontal_extent := maxf(
				float(architecture_dimensions[0]), float(architecture_dimensions[2])
			)
			if horizontal_extent > MAX_MODULAR_ARCHITECTURE_HORIZONTAL_EXTENT_M:
				_fail("Metric Modular Architecture contains an oversized authored section: %s" % asset_id)
				return {}
		if category == "Modular Ground":
			if str(entry.get("kind", "")) != "modular_ground":
				_fail("Metric Modular Ground contains a non-modular asset: %s" % asset_id)
				return {}
			var dimensions: Variant = entry.get("dimensions", [])
			if not (dimensions is Array) or dimensions.size() != 3:
				_fail("Metric Modular Ground asset has invalid dimensions: %s" % asset_id)
				return {}
			if not _is_supported_ground_extent(float(dimensions[0])) or not _is_supported_ground_extent(float(dimensions[2])):
				_fail("Metric Modular Ground asset is not on the 2/4/8 m system: %s" % asset_id)
				return {}
	return catalog


func _is_supported_ground_extent(value: float) -> bool:
	return is_equal_approx(value, 2.0) or is_equal_approx(value, 4.0) or is_equal_approx(value, 8.0)


func _validate_ground_collision(model: Node3D, asset_name: String) -> bool:
	var collision := model.get_node_or_null("Collision/CollisionShape3D") as CollisionShape3D
	if collision == null or not (collision.shape is BoxShape3D):
		_fail("Modular ground asset has no box collision: %s" % asset_name)
		return false
	var box := collision.shape as BoxShape3D
	if (
		not _is_supported_ground_extent(box.size.x)
		or not is_equal_approx(box.size.y, 0.25)
		or not _is_supported_ground_extent(box.size.z)
	):
		_fail("Modular ground collision does not follow the 2/4/8 m system: %s" % asset_name)
		return false
	if not collision.position.is_equal_approx(Vector3(0, -0.125, 0)):
		_fail("Modular ground collision is not centered below the walkable surface: %s" % asset_name)
		return false
	return true


func _catalog_ids_by_scene_node(catalog: Dictionary) -> Dictionary:
	var expected := {}
	for catalog_category: String in CATEGORY_NODES:
		expected[str(CATEGORY_NODES[catalog_category])] = {}
	var raw_assets: Array = catalog.get("assets", [])
	for raw_asset: Variant in raw_assets:
		var asset: Dictionary = raw_asset
		var scene_node_name := str(CATEGORY_NODES[str(asset.get("category", ""))])
		var category_ids: Dictionary = expected.get(scene_node_name, {})
		category_ids[str(asset.get("id", ""))] = true
		expected[scene_node_name] = category_ids
	return expected


func _vector_is_snapped(value: Vector3, step: float) -> bool:
	return (
		is_equal_approx(snappedf(value.x, step), value.x)
		and is_equal_approx(snappedf(value.y, step), value.y)
		and is_equal_approx(snappedf(value.z, step), value.z)
	)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
