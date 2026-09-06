extends Node

const LIBRARY_PATH := "res://game/world/level_kits/terrain/new_bouffalant_city/ground/ground_tile_mesh_library.tres"
const CITY_PATH := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
const TEXTURE_DIRECTORY := "res://art/environments/new_bouffalant_city/ground_tile/textures"
const EXPECTED_AABB := AABB(Vector3(-1.0, -0.25, -1.0), Vector3(2.0, 0.25001, 2.0))
const OPENING_HALF_WIDTH := 0.825
const OPENING_WIDTH := 1.65
const EPSILON := 0.00002

const GRASS := preload("res://game/world/level_kits/terrain/new_bouffalant_city/ground/materials/grass_dirt_grass.tres")
const DIRT := preload("res://game/world/level_kits/terrain/new_bouffalant_city/ground/materials/grass_dirt_dirt.tres")
const SOIL := preload("res://game/world/level_kits/terrain/new_bouffalant_city/ground/materials/grass_dirt_soil.tres")

const ASSETS := {
	6: {
		"id": "grass_dirt_flat_02x02",
		"name": "Grass/Dirt - Flat",
		"scene": "res://game/world/level_kits/terrain/new_bouffalant_city/ground/scenes/grass_dirt_flat_02x02.tscn",
		"triangles": 14,
		"vertices": 25,
		"openings": [],
		"materials": ["grass", "soil"],
	},
	7: {
		"id": "grass_dirt_straight_02x02",
		"name": "Grass/Dirt - Straight",
		"scene": "res://game/world/level_kits/terrain/new_bouffalant_city/ground/scenes/grass_dirt_straight_02x02.tscn",
		"triangles": 58,
		"vertices": 73,
		"openings": ["N", "S"],
		"materials": ["grass", "dirt", "soil"],
	},
	8: {
		"id": "grass_dirt_corner_02x02",
		"name": "Grass/Dirt - L Intersection",
		"scene": "res://game/world/level_kits/terrain/new_bouffalant_city/ground/scenes/grass_dirt_corner_02x02.tscn",
		"triangles": 76,
		"vertices": 91,
		"openings": ["S", "W"],
		"materials": ["grass", "dirt", "soil"],
	},
	9: {
		"id": "grass_dirt_t_junction_02x02",
		"name": "Grass/Dirt - T Intersection",
		"scene": "res://game/world/level_kits/terrain/new_bouffalant_city/ground/scenes/grass_dirt_t_junction_02x02.tscn",
		"triangles": 82,
		"vertices": 99,
		"openings": ["E", "S", "W"],
		"materials": ["grass", "dirt", "soil"],
	},
	10: {
		"id": "grass_dirt_cross_02x02",
		"name": "Grass/Dirt - Junction",
		"scene": "res://game/world/level_kits/terrain/new_bouffalant_city/ground/scenes/grass_dirt_cross_02x02.tscn",
		"triangles": 102,
		"vertices": 121,
		"openings": ["N", "E", "S", "W"],
		"materials": ["grass", "dirt", "soil"],
	},
	11: {
		"id": "grass_dirt_end_02x02",
		"name": "Grass/Dirt - End",
		"scene": "res://game/world/level_kits/terrain/new_bouffalant_city/ground/scenes/grass_dirt_end_02x02.tscn",
		"triangles": 66,
		"vertices": 79,
		"openings": ["N"],
		"materials": ["grass", "dirt", "soil"],
	},
}

const SIDES := ["N", "E", "S", "W"]


func _ready() -> void:
	if not _validate_materials_and_textures():
		return
	var library := load(LIBRARY_PATH) as MeshLibrary
	if library == null or not _validate_library(library):
		return
	if not _validate_city_compatibility(library):
		return
	if not _validate_all_rotated_boundaries(library):
		return
	if not _validate_transition_cases(library):
		return
	print(
		"Grass/dirt GridMap smoke test passed: IDs 6-11, six native meshes, shared "
		+ "materials, six 512 px textures, collisions, 270 preserved city cells, "
		+ "all rotated boundaries, and representative transitions validated."
	)
	get_tree().quit(0)


func _validate_materials_and_textures() -> bool:
	for material: StandardMaterial3D in [GRASS, DIRT, SOIL]:
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return _fail("Grass/dirt material is not opaque: %s" % material.resource_path)
		if not is_zero_approx(material.metallic):
			return _fail("Grass/dirt material is metallic: %s" % material.resource_path)
		if material.roughness < 0.85:
			return _fail("Grass/dirt material is not highly rough: %s" % material.resource_path)
		if not material.uv1_scale.is_equal_approx(Vector3.ONE) or not material.uv1_offset.is_zero_approx():
			return _fail("Grass/dirt material overrides the authored UVs: %s" % material.resource_path)
	if not GRASS.normal_enabled or not is_equal_approx(GRASS.normal_scale, 0.20):
		return _fail("Muted grass normal strength is not 0.20.")
	if not DIRT.normal_enabled or not is_equal_approx(DIRT.normal_scale, 0.16):
		return _fail("Warm dirt normal strength is not 0.16.")
	if SOIL.normal_enabled:
		return _fail("Untextured dark soil unexpectedly enables normal mapping.")

	var textures: Array[Texture2D] = [
		GRASS.albedo_texture,
		GRASS.roughness_texture,
		GRASS.normal_texture,
		DIRT.albedo_texture,
		DIRT.roughness_texture,
		DIRT.normal_texture,
	]
	for texture: Texture2D in textures:
		if texture == null or texture.get_width() != 512 or texture.get_height() != 512:
			return _fail("Grass/dirt material texture is missing or not 512 × 512.")
	for normal_name: String in ["grass_dirt_grass_normal.png", "grass_dirt_dirt_normal.png"]:
		var import_path := TEXTURE_DIRECTORY.path_join(normal_name) + ".import"
		var import_settings := FileAccess.get_file_as_string(import_path)
		if not import_settings.contains("compress/normal_map=1"):
			return _fail("Normal map import is not configured as a normal map: %s" % normal_name)
		if not import_settings.contains("process/normal_map_invert_y=false"):
			return _fail("OpenGL normal map is inverted during import: %s" % normal_name)
	return true


func _validate_library(library: MeshLibrary) -> bool:
	var item_ids := library.get_item_list()
	if item_ids.size() != 12:
		return _fail("Ground MeshLibrary has %d items; expected 12." % item_ids.size())
	for expected_id in range(12):
		if not item_ids.has(expected_id):
			return _fail("Ground MeshLibrary is missing item ID %d." % expected_id)

	for item_id: int in ASSETS:
		var specification: Dictionary = ASSETS[item_id]
		if library.get_item_name(item_id) != String(specification.name):
			return _fail("MeshLibrary item %d has the wrong name." % item_id)
		if not library.get_item_mesh_transform(item_id).is_equal_approx(Transform3D.IDENTITY):
			return _fail("MeshLibrary item %d has a non-identity mesh transform." % item_id)
		if library.get_item_mesh_cast_shadow(item_id) != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			return _fail("MeshLibrary item %d does not use the cobble shadow setting." % item_id)
		if not library.get_item_navigation_mesh_transform(item_id).is_equal_approx(Transform3D.IDENTITY):
			return _fail("MeshLibrary item %d has a non-identity navigation transform." % item_id)
		if library.get_item_navigation_layers(item_id) != 1:
			return _fail("MeshLibrary item %d does not use navigation layer 1." % item_id)
		var shapes := library.get_item_shapes(item_id)
		if shapes.size() != 2 or not (shapes[0] is BoxShape3D) or not (shapes[1] is Transform3D):
			return _fail("MeshLibrary item %d does not have exactly one box collision." % item_id)
		var box := shapes[0] as BoxShape3D
		var shape_transform := shapes[1] as Transform3D
		if not box.size.is_equal_approx(Vector3(2.0, 0.25, 2.0)):
			return _fail("MeshLibrary item %d collision has the wrong size." % item_id)
		if not shape_transform.is_equal_approx(
			Transform3D(Basis.IDENTITY, Vector3(0.0, -0.125, 0.0))
		):
			return _fail("MeshLibrary item %d collision has the wrong transform." % item_id)

		var mesh := library.get_item_mesh(item_id) as ArrayMesh
		if mesh == null or not _validate_mesh(mesh, item_id, specification):
			return false
		if not _validate_wrapper(specification, mesh):
			return false
	return true


func _validate_mesh(mesh: ArrayMesh, item_id: int, specification: Dictionary) -> bool:
	if not _aabb_is_equal(mesh.get_aabb(), EXPECTED_AABB):
		return _fail("MeshLibrary item %d has an unexpected AABB: %s" % [item_id, mesh.get_aabb()])
	var triangle_count := 0
	var vertex_count := 0
	var material_keys: Array[String] = []
	for surface_index in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			return _fail("MeshLibrary item %d has a non-triangle surface." % item_id)
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if uvs.size() != vertices.size():
			return _fail("MeshLibrary item %d does not preserve authored UVs." % item_id)
		vertex_count += vertices.size()
		triangle_count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
		var material := mesh.surface_get_material(surface_index)
		var material_key := _material_key(material)
		if material_key.is_empty():
			return _fail("MeshLibrary item %d does not use a shared kit material." % item_id)
		material_keys.append(material_key)
	if triangle_count != int(specification.triangles) or triangle_count > 102:
		return _fail(
			"MeshLibrary item %d has %d triangles; expected %d and at most 102."
			% [item_id, triangle_count, int(specification.triangles)]
		)
	if vertex_count != int(specification.vertices):
		return _fail(
			"MeshLibrary item %d has %d vertices; expected %d."
			% [item_id, vertex_count, int(specification.vertices)]
		)
	var expected_materials: Array = specification.materials
	if material_keys != Array(expected_materials, TYPE_STRING, &"", null):
		return _fail("MeshLibrary item %d has the wrong shared material order." % item_id)
	return true


func _validate_wrapper(specification: Dictionary, library_mesh: ArrayMesh) -> bool:
	var packed := load(String(specification.scene)) as PackedScene
	if packed == null:
		return _fail("Grass/dirt wrapper is missing: %s" % specification.scene)
	var wrapper := packed.instantiate() as Node3D
	if wrapper == null or not wrapper.transform.is_equal_approx(Transform3D.IDENTITY):
		return _fail("Grass/dirt wrapper root is missing or transformed: %s" % specification.id)
	var model := wrapper.get_node_or_null("Model") as MeshInstance3D
	if model == null or not model.transform.is_equal_approx(Transform3D.IDENTITY):
		wrapper.free()
		return _fail("Grass/dirt Model is missing or transformed: %s" % specification.id)
	if model.mesh != library_mesh:
		wrapper.free()
		return _fail("Grass/dirt wrapper and MeshLibrary do not share a mesh: %s" % specification.id)
	var body := wrapper.get_node_or_null("Collision") as StaticBody3D
	var collision := wrapper.get_node_or_null("Collision/CollisionShape3D") as CollisionShape3D
	if body == null or body.collision_layer != 1 or body.collision_mask != 1:
		wrapper.free()
		return _fail("Grass/dirt wrapper collision is not on gameplay layer 1: %s" % specification.id)
	if collision == null or not (collision.shape is BoxShape3D):
		wrapper.free()
		return _fail("Grass/dirt wrapper has no box collision: %s" % specification.id)
	var box := collision.shape as BoxShape3D
	if not box.size.is_equal_approx(Vector3(2.0, 0.25, 2.0)):
		wrapper.free()
		return _fail("Grass/dirt wrapper collision size is wrong: %s" % specification.id)
	if not collision.transform.is_equal_approx(
		Transform3D(Basis.IDENTITY, Vector3(0.0, -0.125, 0.0))
	):
		wrapper.free()
		return _fail("Grass/dirt wrapper collision pivot is wrong: %s" % specification.id)
	wrapper.free()
	return true


func _validate_city_compatibility(library: MeshLibrary) -> bool:
	var packed := load(CITY_PATH) as PackedScene
	var city := packed.instantiate() if packed != null else null
	if city == null:
		return _fail("New Bouffalant City could not be instantiated.")
	var grid := city.get_node_or_null(
		"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid"
	) as GridMap
	if grid == null:
		city.free()
		return _fail("New Bouffalant City's ModularGroundGrid is missing.")
	if grid.mesh_library != library:
		city.free()
		return _fail("New Bouffalant City does not use the shared ground MeshLibrary.")
	if not grid.transform.is_equal_approx(
		Transform3D(Basis.from_scale(Vector3(2.0, 2.0, 2.0)), Vector3(3.0, 0.0, -1.0))
	):
		city.free()
		return _fail("New Bouffalant City's GridMap transform changed.")
	if not grid.cell_size.is_equal_approx(Vector3(2.0, 0.25, 2.0)) or grid.cell_center_y:
		city.free()
		return _fail("New Bouffalant City's GridMap cell settings changed.")
	var used_cells := grid.get_used_cells()
	if used_cells.size() != 270:
		city.free()
		return _fail("New Bouffalant City's painted cell count changed: %d." % used_cells.size())
	var expected_item_counts := {0: 247, 1: 12, 2: 4, 3: 1, 4: 1, 5: 5}
	var actual_item_counts := {}
	for cell: Vector3i in used_cells:
		var item_id := grid.get_cell_item(cell)
		actual_item_counts[item_id] = int(actual_item_counts.get(item_id, 0)) + 1
	if actual_item_counts != expected_item_counts:
		city.free()
		return _fail("New Bouffalant City's painted GridMap item distribution changed.")
	city.free()
	return true


func _validate_all_rotated_boundaries(library: MeshLibrary) -> bool:
	for item_id: int in ASSETS:
		var specification: Dictionary = ASSETS[item_id]
		var mesh := library.get_item_mesh(item_id) as ArrayMesh
		for rotation_quarters in range(4):
			var expected_openings := _rotated_openings(specification.openings, rotation_quarters)
			for side: String in SIDES:
				var profile := _boundary_profile(mesh, rotation_quarters, side)
				if not _validate_complete_coverage(profile, specification.id, rotation_quarters, side):
					return false
				var should_open := expected_openings.has(side)
				var dirt: Array = profile.dirt
				var grass: Array = profile.grass
				if should_open:
					if not _intervals_match(dirt, [Vector2(-OPENING_HALF_WIDTH, OPENING_HALF_WIDTH)]):
						return _fail(
							"%s rotation %d side %s does not have one exact %.2f m dirt opening."
							% [specification.id, rotation_quarters * 90, side, OPENING_WIDTH]
							+ " Actual dirt intervals: %s" % dirt
						)
					if not _intervals_match(
						grass,
						[
							Vector2(-1.0, -OPENING_HALF_WIDTH),
							Vector2(OPENING_HALF_WIDTH, 1.0),
						]
					):
						return _fail("%s has incorrect grass shoulders on side %s." % [specification.id, side])
				else:
					if not dirt.is_empty() or not _intervals_match(grass, [Vector2(-1.0, 1.0)]):
						return _fail("%s has an unexpected opening on side %s." % [specification.id, side])
	return true


func _validate_transition_cases(library: MeshLibrary) -> bool:
	var cases := [
		["straight chain", 7, 0, "N", 7, 0, "S"],
		["L-to-straight south", 8, 0, "S", 7, 0, "N"],
		["L-to-straight west", 8, 0, "W", 7, 1, "E"],
		["T east branch", 9, 0, "E", 7, 1, "W"],
		["T south branch", 9, 0, "S", 7, 0, "N"],
		["T west branch", 9, 0, "W", 7, 1, "E"],
		["cross north", 10, 0, "N", 7, 0, "S"],
		["cross east", 10, 0, "E", 7, 1, "W"],
		["cross south", 10, 0, "S", 7, 0, "N"],
		["cross west", 10, 0, "W", 7, 1, "E"],
		["end-to-straight", 11, 0, "N", 7, 0, "S"],
		["end closed edge", 11, 0, "S", 6, 0, "N"],
	]
	for transition: Array in cases:
		var first_mesh := library.get_item_mesh(int(transition[1])) as ArrayMesh
		var second_mesh := library.get_item_mesh(int(transition[4])) as ArrayMesh
		var first := _boundary_profile(first_mesh, int(transition[2]), String(transition[3]))
		var second := _boundary_profile(second_mesh, int(transition[5]), String(transition[6]))
		if not _profiles_match(first, second):
			return _fail("Boundary materials do not match for transition: %s." % transition[0])
	return true


func _boundary_profile(mesh: ArrayMesh, rotation_quarters: int, side: String) -> Dictionary:
	var result := {"grass": [], "dirt": []}
	var rotation := Basis(Vector3.UP, deg_to_rad(float(rotation_quarters * 90)))
	for surface_index in mesh.get_surface_count():
		var key := _material_key(mesh.surface_get_material(surface_index))
		if key not in ["grass", "dirt"]:
			continue
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
		for triangle_index in range(triangle_count):
			for edge_index in range(3):
				var first_index := triangle_index * 3 + edge_index
				var second_index := triangle_index * 3 + ((edge_index + 1) % 3)
				if not indices.is_empty():
					first_index = indices[first_index]
					second_index = indices[second_index]
				var first := rotation * vertices[first_index]
				var second := rotation * vertices[second_index]
				var interval: Variant = _edge_interval(first, second, side)
				if interval is Vector2:
					(result[key] as Array).append(interval)
	result.grass = _merge_intervals(result.grass)
	result.dirt = _merge_intervals(result.dirt)
	return result


func _edge_interval(first: Vector3, second: Vector3, side: String) -> Variant:
	if absf(first.y) > EPSILON or absf(second.y) > EPSILON:
		return null
	var first_parameter := 0.0
	var second_parameter := 0.0
	match side:
		"N":
			if absf(first.z + 1.0) > EPSILON or absf(second.z + 1.0) > EPSILON:
				return null
			first_parameter = first.x
			second_parameter = second.x
		"E":
			if absf(first.x - 1.0) > EPSILON or absf(second.x - 1.0) > EPSILON:
				return null
			first_parameter = first.z
			second_parameter = second.z
		"S":
			if absf(first.z - 1.0) > EPSILON or absf(second.z - 1.0) > EPSILON:
				return null
			first_parameter = first.x
			second_parameter = second.x
		"W":
			if absf(first.x + 1.0) > EPSILON or absf(second.x + 1.0) > EPSILON:
				return null
			first_parameter = first.z
			second_parameter = second.z
		_:
			return null
	if absf(first_parameter - second_parameter) <= EPSILON:
		return null
	return Vector2(minf(first_parameter, second_parameter), maxf(first_parameter, second_parameter))


func _merge_intervals(raw_intervals: Array) -> Array:
	var intervals := raw_intervals.duplicate()
	intervals.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
	var merged: Array = []
	for value: Variant in intervals:
		var interval := value as Vector2
		if merged.is_empty():
			merged.append(interval)
			continue
		var last := merged[-1] as Vector2
		if interval.x <= last.y + EPSILON:
			merged[-1] = Vector2(last.x, maxf(last.y, interval.y))
		else:
			merged.append(interval)
	return merged


func _validate_complete_coverage(
	profile: Dictionary, asset_id: String, rotation_quarters: int, side: String
) -> bool:
	var combined: Array = (profile.grass as Array).duplicate()
	combined.append_array(profile.dirt)
	combined.sort_custom(func(first: Vector2, second: Vector2) -> bool: return first.x < second.x)
	if combined.is_empty() or not is_equal_approx((combined[0] as Vector2).x, -1.0):
		return _fail("%s has no complete boundary coverage on side %s." % [asset_id, side])
	var cursor := -1.0
	for value: Variant in combined:
		var interval := value as Vector2
		if absf(interval.x - cursor) > EPSILON:
			return _fail(
				"%s rotation %d side %s has a gap or overlap at %.5f."
				% [asset_id, rotation_quarters * 90, side, cursor]
			)
		cursor = interval.y
	if absf(cursor - 1.0) > EPSILON:
		return _fail("%s boundary coverage does not reach the end of side %s." % [asset_id, side])
	return true


func _rotated_openings(canonical: Array, rotation_quarters: int) -> Array[String]:
	var result: Array[String] = []
	var rotation := Basis(Vector3.UP, deg_to_rad(float(rotation_quarters * 90)))
	for value: Variant in canonical:
		var direction := rotation * _side_vector(String(value))
		result.append(_side_from_vector(direction))
	return result


func _side_vector(side: String) -> Vector3:
	match side:
		"N":
			return Vector3(0.0, 0.0, -1.0)
		"E":
			return Vector3(1.0, 0.0, 0.0)
		"S":
			return Vector3(0.0, 0.0, 1.0)
		"W":
			return Vector3(-1.0, 0.0, 0.0)
	return Vector3.ZERO


func _side_from_vector(direction: Vector3) -> String:
	if absf(direction.x) > absf(direction.z):
		return "E" if direction.x > 0.0 else "W"
	return "S" if direction.z > 0.0 else "N"


func _profiles_match(first: Dictionary, second: Dictionary) -> bool:
	return (
		_intervals_match(first.grass, second.grass)
		and _intervals_match(first.dirt, second.dirt)
	)


func _intervals_match(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		var actual_interval := actual[index] as Vector2
		var expected_interval := expected[index] as Vector2
		if not actual_interval.is_equal_approx(expected_interval):
			return false
	return true


func _material_key(material: Material) -> String:
	if material == GRASS:
		return "grass"
	if material == DIRT:
		return "dirt"
	if material == SOIL:
		return "soil"
	return ""


func _aabb_is_equal(first: AABB, second: AABB) -> bool:
	return (
		first.position.is_equal_approx(second.position)
		and first.size.is_equal_approx(second.size)
	)


func _fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false
