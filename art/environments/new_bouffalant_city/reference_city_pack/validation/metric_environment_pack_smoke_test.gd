extends Node

const CATALOG_PATH := "res://art/environments/new_bouffalant_city/reference_city_pack/catalog.json"
const SHOWCASE_SCENE := preload("res://art/environments/new_bouffalant_city/reference_city_pack/showcase/building_ground_metric_showcase.tscn")
const CollisionProfiles := preload("res://art/environments/new_bouffalant_city/reference_city_pack/collision/collision_profiles.gd")
const RuntimeContract := preload("res://art/environments/new_bouffalant_city/reference_city_pack/runtime_contract.gd")
const THUMBNAIL_DIRECTORY := "res://addons/new_bouffalant_city_asset_palette/thumbnails"
const MAX_MODULAR_ARCHITECTURE_HORIZONTAL_EXTENT_M := 16.0
const IMPORTED_COLLISION_NODE := "GameplayCollision"
const EXPECTED_COLLISION_PROFILE_COUNTS := {
	CollisionProfiles.Profile.NONE: 13,
	CollisionProfiles.Profile.MESH: 119,
	CollisionProfiles.Profile.BOX: 8,
	CollisionProfiles.Profile.TRUNK: 7,
}
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
const EXPECTED_PERFORMANCE_SENSITIVE_ASSET_COUNT := 44
const EXPECTED_VULKAN_SAFE_MESH_IMPORT_COUNT := 3


func _ready() -> void:
	var catalog := _load_and_validate_catalog()
	if catalog.is_empty():
		get_tree().quit(1)
		return

	var showcase := SHOWCASE_SCENE.instantiate()
	add_child(showcase)
	await get_tree().process_frame
	if not is_equal_approx(
		float(showcase.get_meta("imported_glb_baked_scale", -1.0)),
		RuntimeContract.IMPORTED_MODEL_SCALE
	):
		_fail("Metric showcase does not declare the GLB baked scale contract.")
		return

	var expected_ids_by_node := _catalog_ids_by_scene_node(catalog)
	var catalog_assets_by_id := _catalog_assets_by_id(catalog)
	var seen_ids := {}
	var collision_profile_counts := {
		CollisionProfiles.Profile.NONE: 0,
		CollisionProfiles.Profile.MESH: 0,
		CollisionProfiles.Profile.BOX: 0,
		CollisionProfiles.Profile.TRUNK: 0,
	}
	var physics_representatives := {}
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
			var asset_id := str(slot.get_meta("asset_id", ""))
			if catalog_category == "Modular Ground" and not _validate_ground_collision(model, slot.name):
				return
			if catalog_category != "Modular Ground":
				var catalog_asset: Dictionary = catalog_assets_by_id.get(asset_id, {})
				if not _validate_imported_runtime_scale(model, catalog_asset, asset_id):
					return
				var profile: CollisionProfiles.Profile = CollisionProfiles.profile_for_asset(asset_id)
				collision_profile_counts[profile] = int(collision_profile_counts[profile]) + 1
				if not _validate_imported_collision(model, asset_id, profile):
					return
				if RuntimeContract.uses_vulkan_safe_mesh_import(asset_id):
					if not _validate_vulkan_safe_mesh_import(model, asset_id):
						return
					if not _validate_textured_materials_retained(model, asset_id):
						return
				if asset_id in ["t1_ar301", "t1_pl011", "t1_pl024"]:
					physics_representatives[asset_id] = model
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
	for profile: CollisionProfiles.Profile in EXPECTED_COLLISION_PROFILE_COUNTS:
		if int(collision_profile_counts[profile]) != int(EXPECTED_COLLISION_PROFILE_COUNTS[profile]):
			_fail(
				"Collision profile %s has %d assets; expected %d."
				% [
					CollisionProfiles.profile_name(profile),
					collision_profile_counts[profile],
					EXPECTED_COLLISION_PROFILE_COUNTS[profile],
				]
			)
			return

	await get_tree().physics_frame
	for representative_id: String in physics_representatives:
		if not _validate_collision_in_physics_space(
			physics_representatives[representative_id], representative_id
		):
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
		(
			"Metric environment showcase smoke test passed: %d assets at scale 1 on the %.1f m grid; "
			+ "147 GLBs baked to 0.75 at node scale 1; 44 high-load entries classified; "
			+ "3 buildings use Vulkan-safe original mesh buffers; "
			+ "119 mesh, 8 box, 7 trunk, "
			+ "13 pass-through, and 11 ground collisions validated."
		)
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
	if not is_equal_approx(
		float(catalog.get("runtime_import_scale", -1.0)),
		RuntimeContract.IMPORTED_MODEL_SCALE
	):
		_fail("Catalog runtime_import_scale does not match the runtime contract.")
		return {}
	var failures: Variant = catalog.get("failures", [])
	if not (failures is Array) or not failures.is_empty():
		_fail("Catalog contains conversion failures.")
		return {}

	var seen_catalog_ids := {}
	var performance_sensitive_count := 0
	var vulkan_safe_mesh_import_count := 0
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
		if RuntimeContract.is_performance_sensitive(entry):
			performance_sensitive_count += 1
		if RuntimeContract.uses_vulkan_safe_mesh_import(entry):
			vulkan_safe_mesh_import_count += 1
		var model_path := str(entry.get("model_path", ""))
		if model_path.is_empty() or not FileAccess.file_exists(model_path):
			_fail("Converted model is missing: %s" % model_path)
			return {}
		var thumbnail_path := THUMBNAIL_DIRECTORY.path_join("%s.png" % asset_id)
		if not ResourceLoader.exists(thumbnail_path, "Texture2D"):
			_fail("Asset thumbnail is missing or not imported: %s" % thumbnail_path)
			return {}
		if model_path.ends_with(".glb") and not _uses_runtime_import_settings(model_path):
			_fail("GLB is not configured for baked scale and collision: %s" % model_path)
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
	if performance_sensitive_count != EXPECTED_PERFORMANCE_SENSITIVE_ASSET_COUNT:
		_fail(
			"Performance-sensitive asset classification has %d entries; expected %d."
			% [
				performance_sensitive_count,
				EXPECTED_PERFORMANCE_SENSITIVE_ASSET_COUNT,
			]
		)
		return {}
	if vulkan_safe_mesh_import_count != EXPECTED_VULKAN_SAFE_MESH_IMPORT_COUNT:
		_fail(
			"Vulkan-safe mesh import scope has %d entries; expected %d."
			% [vulkan_safe_mesh_import_count, EXPECTED_VULKAN_SAFE_MESH_IMPORT_COUNT]
		)
		return {}
	for expected_heavy_id: String in ["t3_road_line_e", "t1_g17_1", "t1_b_school"]:
		var expected_heavy: Dictionary = _catalog_assets_by_id(catalog).get(expected_heavy_id, {})
		if not RuntimeContract.is_performance_sensitive(expected_heavy):
			_fail("Known high-load asset is not classified: %s" % expected_heavy_id)
			return {}
	var catalog_assets_by_id := _catalog_assets_by_id(catalog)
	for safe_import_id: String in [
		"t1_b_gate_building",
		"t1_b_museum",
		"t1_b_tenant_building",
	]:
		if not RuntimeContract.uses_vulkan_safe_mesh_import(
			catalog_assets_by_id.get(safe_import_id, {})
		):
			_fail("Vulkan-safe mesh import is not scoped: %s" % safe_import_id)
			return {}
	for safe_control_id: String in ["t1_b_cityhall", "t1_b_rouge_tower", "t1_b_miare_station"]:
		if RuntimeContract.uses_vulkan_safe_mesh_import(
			catalog_assets_by_id.get(safe_control_id, {})
		):
			_fail("Known renderer control has the targeted import override: %s" % safe_control_id)
			return {}
	return catalog


func _uses_runtime_import_settings(model_path: String) -> bool:
	var import_path := model_path + ".import"
	if not FileAccess.file_exists(import_path):
		return false
	var settings := FileAccess.get_file_as_string(import_path)
	var expected_script := (
		'import_script/path="%s"' % RuntimeContract.COLLISION_POST_IMPORT_SCRIPT
	)
	var asset_id := model_path.get_file().trim_suffix(".glb")
	var uses_original_buffers := RuntimeContract.uses_vulkan_safe_mesh_import(asset_id)
	var expected_generated_buffers := "false" if uses_original_buffers else "true"
	return (
		settings.contains("nodes/apply_root_scale=true")
		and settings.contains("nodes/root_scale=%s" % RuntimeContract.IMPORTED_MODEL_SCALE)
		and settings.contains("meshes/generate_lods=%s" % expected_generated_buffers)
		and settings.contains("meshes/create_shadow_meshes=%s" % expected_generated_buffers)
		and settings.contains(expected_script)
	)


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


func _validate_imported_collision(
	model: Node3D, asset_id: String, profile: CollisionProfiles.Profile
) -> bool:
	var expected_name := CollisionProfiles.profile_name(profile)
	if str(model.get_meta("new_bouffalant_city_collision_profile", "")) != expected_name:
		_fail("Imported collision profile metadata is missing or stale: %s" % asset_id)
		return false

	var body := model.get_node_or_null(IMPORTED_COLLISION_NODE) as StaticBody3D
	if profile == CollisionProfiles.Profile.NONE:
		if body != null:
			_fail("Pass-through decoration unexpectedly has collision: %s" % asset_id)
			return false
		return true
	if body == null or body.get_child_count() == 0:
		_fail("Imported asset has no generated static collision: %s" % asset_id)
		return false
	if body.collision_layer != 1 or body.collision_mask != 1:
		_fail("Imported asset collision is not on the gameplay layer: %s" % asset_id)
		return false

	for child: Node in body.get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null or collision_shape.shape == null:
			_fail("Imported asset contains an invalid collision shape: %s" % asset_id)
			return false
		match profile:
			CollisionProfiles.Profile.MESH:
				if not (collision_shape.shape is ConcavePolygonShape3D):
					_fail("Hard-surface asset does not use mesh collision: %s" % asset_id)
					return false
				if not (collision_shape.shape as ConcavePolygonShape3D).backface_collision:
					_fail("Mesh collision is not double-sided: %s" % asset_id)
					return false
			CollisionProfiles.Profile.BOX:
				if not (collision_shape.shape is BoxShape3D):
					_fail("Hedge/bush asset does not use box collision: %s" % asset_id)
					return false
			CollisionProfiles.Profile.TRUNK:
				if not (collision_shape.shape is CylinderShape3D):
					_fail("Tree/stump asset does not use trunk collision: %s" % asset_id)
					return false
	return true


func _validate_imported_runtime_scale(
	model: Node3D, asset: Dictionary, asset_id: String
) -> bool:
	if asset.is_empty():
		_fail("Catalog data is missing while validating runtime scale: %s" % asset_id)
		return false
	if not model.scale.is_equal_approx(Vector3.ONE):
		_fail("Imported model node is not scale 1 after baking: %s" % asset_id)
		return false
	var expected_dimensions := RuntimeContract.effective_dimensions(asset)
	if expected_dimensions.size() != 3:
		_fail("Catalog dimensions are invalid while validating runtime scale: %s" % asset_id)
		return false
	var actual_dimensions := _visual_bounds(model).size
	for axis in range(3):
		var expected := expected_dimensions[axis]
		var actual := actual_dimensions[axis]
		var tolerance := maxf(0.002, absf(expected) * 0.001)
		if not is_equal_approx(actual, expected) and absf(actual - expected) > tolerance:
			_fail(
				(
					"Baked runtime bounds differ from catalog × %.2f for %s on axis %d: "
					+ "expected %.5f, got %.5f."
				)
				% [
					RuntimeContract.IMPORTED_MODEL_SCALE,
					asset_id,
					axis,
					expected,
					actual,
				]
			)
			return false
	return true


func _validate_vulkan_safe_mesh_import(model: Node3D, asset_id: String) -> bool:
	var mesh_instances: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		mesh_instances.push_front(model)
	var mesh_count := 0
	for node: Node in mesh_instances:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh := mesh_instance.mesh as ArrayMesh
		if mesh == null:
			_fail("Vulkan-safe import did not produce an ArrayMesh: %s" % asset_id)
			return false
		mesh_count += 1
		if mesh.get("shadow_mesh") != null:
			_fail("Vulkan-safe import still has an optimized shadow mesh: %s" % asset_id)
			return false
		var serialized_surfaces: Array = mesh.call("_get_surfaces")
		for surface: Variant in serialized_surfaces:
			if surface is Dictionary and not (surface as Dictionary).get("lods", []).is_empty():
				_fail("Vulkan-safe import still has generated LOD indices: %s" % asset_id)
				return false
	if mesh_count == 0:
		_fail("Vulkan-safe import has no visual meshes: %s" % asset_id)
		return false
	return true


func _validate_textured_materials_retained(model: Node3D, asset_id: String) -> bool:
	var mesh_instances: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		mesh_instances.push_front(model)
	for node: Node in mesh_instances:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index)
			if material == null:
				continue
			for property: Dictionary in material.get_property_list():
				if material.get(property.name) is Texture2D:
					return true
	_fail("Original textured materials were not retained for: %s" % asset_id)
	return false


func _visual_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var model_inverse := model.global_transform.affine_inverse()
	var visual_nodes := model.find_children("*", "VisualInstance3D", true, false)
	if model is VisualInstance3D:
		visual_nodes.push_front(model)
	for value: Variant in visual_nodes:
		var visual := value as VisualInstance3D
		if visual == null or not visual.visible:
			continue
		var visual_bounds := visual.get_aabb()
		var to_model := model_inverse * visual.global_transform
		for endpoint_index in range(8):
			var point := to_model * visual_bounds.get_endpoint(endpoint_index)
			if has_bounds:
				bounds = bounds.expand(point)
			else:
				bounds = AABB(point, Vector3.ZERO)
				has_bounds = true
	return bounds


func _validate_collision_in_physics_space(model: Node3D, asset_id: String) -> bool:
	var body := model.get_node_or_null(IMPORTED_COLLISION_NODE) as StaticBody3D
	if body == null:
		_fail("Physics representative has no collision body: %s" % asset_id)
		return false
	var collision_shape := body.get_child(0) as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		_fail("Physics representative has no collision shape: %s" % asset_id)
		return false
	var segment := _physics_probe_segment(collision_shape)
	if segment.is_empty():
		_fail("Could not build a physics probe for: %s" % asset_id)
		return false
	var query := PhysicsRayQueryParameters3D.create(segment.from, segment.to, 1)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_back_faces = true
	var hit := model.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.get("collider") == body:
		return true
	_fail("Generated collision is not active in physics space: %s" % asset_id)
	return false


func _physics_probe_segment(collision_shape: CollisionShape3D) -> Dictionary:
	var shape := collision_shape.shape
	var shape_transform := collision_shape.global_transform
	if shape is ConcavePolygonShape3D:
		var faces := (shape as ConcavePolygonShape3D).get_faces()
		for index in range(0, faces.size(), 3):
			if index + 2 >= faces.size():
				break
			var first := shape_transform * faces[index]
			var second := shape_transform * faces[index + 1]
			var third := shape_transform * faces[index + 2]
			var normal := (second - first).cross(third - first).normalized()
			if normal.is_zero_approx():
				continue
			var center := (first + second + third) / 3.0
			return {"from": center + normal * 0.25, "to": center - normal * 0.25}
	elif shape is BoxShape3D:
		var box := shape as BoxShape3D
		var axis := shape_transform.basis.x.normalized()
		var distance := maxf(box.size.x, 0.25)
		return {
			"from": shape_transform.origin + axis * distance,
			"to": shape_transform.origin - axis * distance,
		}
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var axis := shape_transform.basis.x.normalized()
		var distance := maxf(cylinder.radius * 2.0, 0.25)
		return {
			"from": shape_transform.origin + axis * distance,
			"to": shape_transform.origin - axis * distance,
		}
	return {}


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


func _catalog_assets_by_id(catalog: Dictionary) -> Dictionary:
	var result := {}
	var raw_assets: Array = catalog.get("assets", [])
	for value: Variant in raw_assets:
		var asset: Dictionary = value
		result[String(asset.get("id", ""))] = asset
	return result


func _vector_is_snapped(value: Vector3, step: float) -> bool:
	return (
		is_equal_approx(snappedf(value.x, step), value.x)
		and is_equal_approx(snappedf(value.y, step), value.y)
		and is_equal_approx(snappedf(value.z, step), value.z)
	)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
