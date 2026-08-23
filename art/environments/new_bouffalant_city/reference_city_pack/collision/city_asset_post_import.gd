@tool
extends EditorScenePostImport

const CollisionProfiles := preload("res://art/environments/new_bouffalant_city/reference_city_pack/collision/collision_profiles.gd")
const COLLISION_NODE_NAME := "GameplayCollision"
const COLLISION_PROFILE_META := "new_bouffalant_city_collision_profile"
const GENERATED_COLLISION_META := "new_bouffalant_city_generated_collision"


func _post_import(scene: Node) -> Object:
	var root := scene as Node3D
	if root == null:
		push_error("[New Bouffalant City] Imported scene root is not Node3D: %s" % get_source_file())
		return scene

	var asset_id := get_source_file().get_file().get_basename()
	var profile: CollisionProfiles.Profile = CollisionProfiles.profile_for_asset(asset_id)
	root.set_meta(COLLISION_PROFILE_META, CollisionProfiles.profile_name(profile))
	if profile == CollisionProfiles.Profile.NONE:
		return root

	var mesh_entries: Array[Dictionary] = []
	_collect_mesh_entries(root, Transform3D.IDENTITY, mesh_entries)
	if mesh_entries.is_empty():
		push_warning("[New Bouffalant City] No meshes found for collision: %s" % asset_id)
		return root

	var body := StaticBody3D.new()
	body.name = COLLISION_NODE_NAME
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_meta(GENERATED_COLLISION_META, true)
	root.add_child(body)
	body.owner = root

	match profile:
		CollisionProfiles.Profile.BOX:
			_add_box_collision(root, body, mesh_entries)
		CollisionProfiles.Profile.TRUNK:
			_add_trunk_collision(root, body, mesh_entries, asset_id)
		_:
			_add_mesh_collision(root, body, mesh_entries)

	if body.get_child_count() == 0:
		push_warning("[New Bouffalant City] Collision generation produced no shapes: %s" % asset_id)
		root.remove_child(body)
		body.queue_free()
	return root


func _collect_mesh_entries(
	node: Node, relative_transform: Transform3D, entries: Array[Dictionary]
) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
			entries.append({"mesh": mesh_instance.mesh, "transform": relative_transform})

	for child: Node in node.get_children():
		var child_transform := relative_transform
		if child is Node3D:
			child_transform *= (child as Node3D).transform
		_collect_mesh_entries(child, child_transform, entries)


func _add_mesh_collision(
	root: Node3D, body: StaticBody3D, mesh_entries: Array[Dictionary]
) -> void:
	var shape_index := 0
	for entry: Dictionary in mesh_entries:
		var mesh := entry.get("mesh") as Mesh
		if mesh == null:
			continue
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			continue
		if shape is ConcavePolygonShape3D:
			(shape as ConcavePolygonShape3D).backface_collision = true
		shape.resource_local_to_scene = true

		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "MeshShape%03d" % shape_index
		collision_shape.transform = entry.get("transform", Transform3D.IDENTITY)
		collision_shape.shape = shape
		body.add_child(collision_shape)
		collision_shape.owner = root
		shape_index += 1


func _add_box_collision(
	root: Node3D, body: StaticBody3D, mesh_entries: Array[Dictionary]
) -> void:
	var bounds := _combined_bounds(mesh_entries)
	if bounds.size.is_zero_approx():
		return
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		maxf(bounds.size.x, 0.1),
		maxf(bounds.size.y, 0.1),
		maxf(bounds.size.z, 0.1)
	)
	shape.resource_local_to_scene = true
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "SolidVolume"
	collision_shape.position = bounds.get_center()
	collision_shape.shape = shape
	body.add_child(collision_shape)
	collision_shape.owner = root


func _add_trunk_collision(
	root: Node3D,
	body: StaticBody3D,
	mesh_entries: Array[Dictionary],
	asset_id: String
) -> void:
	var bounds := _combined_bounds(mesh_entries)
	if bounds.size.is_zero_approx():
		return

	var height_factor := 0.5
	var radius_factor := 0.09
	var maximum_height := 4.5
	var maximum_radius := 0.7
	if asset_id == "t1_pl033":
		height_factor = 0.72
		radius_factor = 0.18
		maximum_height = 6.5
		maximum_radius = 1.25
	elif asset_id == "t1_pl035":
		height_factor = 0.9
		radius_factor = 0.32
		maximum_height = 1.5
		maximum_radius = 0.65

	var collision_height := clampf(bounds.size.y * height_factor, 0.75, maximum_height)
	var horizontal_extent := minf(bounds.size.x, bounds.size.z)
	var collision_radius := clampf(horizontal_extent * radius_factor, 0.14, maximum_radius)
	collision_height = maxf(collision_height, collision_radius * 2.0)

	var shape := CylinderShape3D.new()
	shape.height = collision_height
	shape.radius = collision_radius
	shape.resource_local_to_scene = true
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "TrunkVolume"
	var center := bounds.get_center()
	collision_shape.position = Vector3(
		center.x,
		bounds.position.y + collision_height * 0.5,
		center.z
	)
	collision_shape.shape = shape
	body.add_child(collision_shape)
	collision_shape.owner = root


func _combined_bounds(mesh_entries: Array[Dictionary]) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	for entry: Dictionary in mesh_entries:
		var mesh := entry.get("mesh") as Mesh
		if mesh == null:
			continue
		var transformed := _transformed_aabb(
			mesh.get_aabb(), entry.get("transform", Transform3D.IDENTITY)
		)
		if not has_bounds:
			bounds = transformed
			has_bounds = true
		else:
			bounds = bounds.merge(transformed)
	return bounds


func _transformed_aabb(source: AABB, transform_3d: Transform3D) -> AABB:
	var first := true
	var minimum := Vector3.ZERO
	var maximum := Vector3.ZERO
	for x_index in range(2):
		for y_index in range(2):
			for z_index in range(2):
				var corner := source.position + Vector3(
					source.size.x * float(x_index),
					source.size.y * float(y_index),
					source.size.z * float(z_index)
				)
				var point := transform_3d * corner
				if first:
					minimum = point
					maximum = point
					first = false
				else:
					minimum = minimum.min(point)
					maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)
