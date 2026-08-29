extends Node

const WRAPPER_SCENE := preload("res://art/environments/new_bouffalant_city/pokemon_center_roof/pokemon_center_with_roof.tscn")
const MODULAR_GROUND_SCENE := preload("res://demo/modular_ground_scene.tscn")
const WRAPPER_PATH := "res://art/environments/new_bouffalant_city/pokemon_center_roof/pokemon_center_with_roof.tscn"
const EXPECTED_WORLD_POSITION := Vector3(-1.0, 0.0, -17.0)
const MAX_ROOF_TRIANGLES := 256
const MAX_DOOR_TRIANGLES := 96
const COVERING_EAVE_HEIGHT := 4.5523


func _ready() -> void:
	var wrapper := WRAPPER_SCENE.instantiate() as Node3D
	if wrapper == null:
		_fail("Pokemon Center roof wrapper could not be instantiated.")
		return
	add_child(wrapper)
	await get_tree().process_frame

	if not wrapper.scale.is_equal_approx(Vector3.ONE):
		_fail("Pokemon Center wrapper is not at unit scale.")
		return
	var building := wrapper.get_node_or_null("Building") as Node3D
	var roof_root := wrapper.get_node_or_null("Roof") as Node3D
	var doors_root := wrapper.get_node_or_null("Doors") as Node3D
	if building == null or roof_root == null or doors_root == null:
		_fail("Pokemon Center wrapper is missing its Building, Roof, or Doors child.")
		return
	if (
		not building.scale.is_equal_approx(Vector3.ONE)
		or not roof_root.scale.is_equal_approx(Vector3.ONE)
		or not doors_root.scale.is_equal_approx(Vector3.ONE)
	):
		_fail("Pokemon Center assembly children are not all at unit scale.")
		return

	var roof_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(roof_root, roof_meshes)
	if roof_meshes.size() != 1:
		_fail("Roof must contain exactly one MeshInstance3D; found %d." % roof_meshes.size())
		return
	var roof_mesh_instance := roof_meshes[0]
	var roof_mesh := roof_mesh_instance.mesh
	if roof_mesh == null or roof_mesh.get_surface_count() != 1:
		_fail("Roof must use one mesh surface/material draw.")
		return

	var triangle_count := _triangle_count(roof_mesh)
	if triangle_count <= 0 or triangle_count > MAX_ROOF_TRIANGLES:
		_fail("Roof has %d triangles; mobile budget is %d." % [triangle_count, MAX_ROOF_TRIANGLES])
		return
	var material := roof_mesh.surface_get_material(0) as BaseMaterial3D
	if material == null:
		_fail("Roof surface is missing its mobile material.")
		return
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		_fail("Roof material must remain opaque.")
		return
	if material.albedo_texture == null:
		_fail("Roof material is missing its tiny color palette.")
		return
	if material.albedo_texture.get_width() != 64 or material.albedo_texture.get_height() != 16:
		_fail("Roof palette is not the expected 64 x 16 texture.")
		return
	if roof_mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("Roof shadow casting was disabled.")
		return
	if _contains_collision(roof_root):
		_fail("Decorative roof must not add gameplay collision.")
		return

	var bounds := _bounds_in_ancestor_space(wrapper, roof_mesh_instance)
	if bounds.position.y < 3.005 or bounds.position.y > 3.030:
		_fail("Roof mounting edge is not aligned to the 3 m wall rim: %s" % bounds)
		return
	if bounds.end.y < 6.08 or bounds.end.y > 6.20:
		_fail("Roof crown height is outside the fitted tall-roof range: %s" % bounds)
		return
	if bounds.size.x < 7.84 or bounds.size.x > 7.94 or bounds.size.z < 7.84 or bounds.size.z > 7.94:
		_fail("Roof footprint does not overhang the complete measured building envelope: %s" % bounds)
		return
	var building_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(building, building_meshes)
	var building_bounds := _merged_bounds_in_ancestor_space(wrapper, building_meshes)
	if (
		bounds.position.x > building_bounds.position.x - 0.05
		or bounds.end.x < building_bounds.end.x + 0.05
		or bounds.position.z > building_bounds.position.z - 0.05
		or bounds.end.z < building_bounds.end.z + 0.05
	):
		_fail("Roof does not overhang all four building plan bounds: roof=%s building=%s" % [bounds, building_bounds])
		return
	if COVERING_EAVE_HEIGHT < building_bounds.end.y + 0.05:
		_fail("Roof eave does not vertically clear the facade medallions: %s" % building_bounds)
		return
	var eave_area := _horizontal_vertex_ring_area_at_height(
		wrapper,
		roof_mesh_instance,
		COVERING_EAVE_HEIGHT,
		0.006,
	)
	if eave_area < 59.5 or eave_area > 60.8:
		_fail(
			"Roof eave covers %.2f m^2; expected the complete overhanging five-sided envelope."
			% eave_area
		)
		return

	var door_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(doors_root, door_meshes)
	if door_meshes.size() != 1:
		_fail("Doors must contain exactly one MeshInstance3D; found %d." % door_meshes.size())
		return
	var door_mesh_instance := door_meshes[0]
	var door_mesh := door_mesh_instance.mesh
	if door_mesh == null or door_mesh.get_surface_count() != 1:
		_fail("Doors must use one mesh surface/material draw.")
		return
	var door_triangles := _triangle_count(door_mesh)
	if door_triangles <= 0 or door_triangles > MAX_DOOR_TRIANGLES:
		_fail("Doors have %d triangles; mobile budget is %d." % [door_triangles, MAX_DOOR_TRIANGLES])
		return
	var door_material := door_mesh.surface_get_material(0) as BaseMaterial3D
	if door_material == null or door_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		_fail("Doors must retain one opaque mobile material.")
		return
	if (
		door_material.albedo_texture == null
		or door_material.albedo_texture.get_width() != 64
		or door_material.albedo_texture.get_height() != 16
	):
		_fail("Door material is missing its expected 64 x 16 palette.")
		return
	if door_mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("Door shadow casting was disabled.")
		return
	if _contains_collision(doors_root):
		_fail("Decorative doors must not add gameplay collision.")
		return
	var door_fit := _street_door_fit_ranges(wrapper, door_mesh_instance)
	if (
		door_fit[0] < -1.95 or door_fit[0] > -1.92
		or door_fit[1] < 1.40 or door_fit[1] > 1.43
		or door_fit[2] < 3.04 or door_fit[2] > 3.07
		or door_fit[3] < 3.07 or door_fit[3] > 3.10
		or door_fit[4] < 0.35 or door_fit[4] > 0.37
		or door_fit[5] < 3.06 or door_fit[5] > 3.08
		or door_fit[6] < -1.95 or door_fit[6] > -1.92
		or door_fit[7] < 1.40 or door_fit[7] > 1.43
		or door_fit[8] < 3.04 or door_fit[8] > 3.07
		or door_fit[9] < 3.07 or door_fit[9] > 3.10
		or door_fit[10] < 0.35 or door_fit[10] > 0.37
		or door_fit[11] < 3.06 or door_fit[11] > 3.08
	):
		_fail("Door sets no longer fit both measured street entrances: %s" % [door_fit])
		return

	var modular_ground := MODULAR_GROUND_SCENE.instantiate() as Node3D
	if modular_ground == null:
		_fail("Modular ground scene could not be instantiated.")
		return
	add_child(modular_ground)
	await get_tree().process_frame
	var placed_center := modular_ground.get_node_or_null("T1BPokemonCenterOut") as Node3D
	if placed_center == null:
		_fail("modular_ground_scene is missing T1BPokemonCenterOut.")
		return
	if placed_center.scene_file_path != WRAPPER_PATH:
		_fail("T1BPokemonCenterOut is not instancing the fitted roof wrapper.")
		return
	if not placed_center.position.is_equal_approx(EXPECTED_WORLD_POSITION):
		_fail("Pokemon Center placement moved while adding the roof.")
		return
	if not placed_center.scale.is_equal_approx(Vector3.ONE):
		_fail("Placed Pokemon Center assembly is not at unit scale.")
		return
	if (
		placed_center.get_node_or_null("Building") == null
		or placed_center.get_node_or_null("Roof") == null
		or placed_center.get_node_or_null("Doors") == null
	):
		_fail("Placed Pokemon Center is missing a wrapper child.")
		return
	var sun := modular_ground.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null or not sun.shadow_enabled:
		_fail("Modular ground's basic directional shadows are not enabled.")
		return

	print(
		(
			"Pokemon Center assembly smoke test passed: %d roof triangles, %d door triangles, "
			+ "two opaque palette draws, full eave coverage, two fitted street entrances, exact unit-scale "
			+ "placement, no added collision, shadows enabled."
		)
		% [triangle_count, door_triangles]
	)
	get_tree().quit(0)


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, output)


func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface_index in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += vertices.size() / 3
		else:
			total += indices.size() / 3
	return total


func _bounds_in_ancestor_space(ancestor: Node3D, mesh_instance: MeshInstance3D) -> AABB:
	var source := mesh_instance.get_aabb()
	var transform := ancestor.global_transform.affine_inverse() * mesh_instance.global_transform
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var corner := source.position + source.size * Vector3(x, y, z)
				var point := transform * corner
				minimum = minimum.min(point)
				maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)


func _merged_bounds_in_ancestor_space(
	ancestor: Node3D,
	mesh_instances: Array[MeshInstance3D],
) -> AABB:
	var merged := AABB()
	var initialized := false
	for mesh_instance in mesh_instances:
		var bounds := _bounds_in_ancestor_space(ancestor, mesh_instance)
		if initialized:
			merged = merged.merge(bounds)
		else:
			merged = bounds
			initialized = true
	return merged


func _horizontal_vertex_ring_area_at_height(
	ancestor: Node3D,
	mesh_instance: MeshInstance3D,
	height: float,
	tolerance: float,
) -> float:
	var transform := ancestor.global_transform.affine_inverse() * mesh_instance.global_transform
	var points: Array[Vector2] = []
	for surface_index in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := transform * vertex
			if absf(point.y - height) > tolerance:
				continue
			var projected := Vector2(point.x, point.z)
			if not points.any(func(existing: Vector2) -> bool: return existing.is_equal_approx(projected)):
				points.append(projected)
	if points.size() < 3:
		return 0.0
	var center := Vector2.ZERO
	for point in points:
		center += point
	center /= points.size()
	points.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return atan2(a.y - center.y, a.x - center.x) < atan2(b.y - center.y, b.x - center.x)
	)
	var area := 0.0
	for index in points.size():
		var following := (index + 1) % points.size()
		area += points[index].x * points[following].y - points[following].x * points[index].y
	return absf(area) * 0.5


func _street_door_fit_ranges(
	ancestor: Node3D,
	mesh_instance: MeshInstance3D,
) -> PackedFloat32Array:
	var transform := ancestor.global_transform.affine_inverse() * mesh_instance.global_transform
	var south := PackedFloat32Array([INF, -INF, INF, -INF, INF, -INF])
	var east := PackedFloat32Array([INF, -INF, INF, -INF, INF, -INF])
	var south_vertices := 0
	var east_vertices := 0
	for surface_index in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := transform * vertex
			if point.z > 3.0:
				south[0] = minf(south[0], point.x)
				south[1] = maxf(south[1], point.x)
				south[2] = minf(south[2], point.z)
				south[3] = maxf(south[3], point.z)
				south[4] = minf(south[4], point.y)
				south[5] = maxf(south[5], point.y)
				south_vertices += 1
			elif point.x > 3.0:
				east[0] = minf(east[0], point.z)
				east[1] = maxf(east[1], point.z)
				east[2] = minf(east[2], point.x)
				east[3] = maxf(east[3], point.x)
				east[4] = minf(east[4], point.y)
				east[5] = maxf(east[5], point.y)
				east_vertices += 1
	if south_vertices == 0 or east_vertices == 0:
		return PackedFloat32Array([INF, INF, INF, INF, INF, INF, INF, INF, INF, INF, INF, INF])
	var combined := south
	combined.append_array(east)
	return combined


func _contains_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		return true
	for child: Node in node.get_children():
		if _contains_collision(child):
			return true
	return false


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
