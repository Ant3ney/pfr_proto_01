extends Node

const INTERIOR_SCENE := preload("res://game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_interior.tscn")
const EXPECTED_TRIANGLES := 1948
const MAX_ENVIRONMENT_TRIANGLES := 2100
const EXPECTED_MATERIAL_DRAWS := 2
const EXPECTED_COLLISION_SHAPES := 14


func _ready() -> void:
	var interior := INTERIOR_SCENE.instantiate() as Node3D
	if interior == null:
		_fail("Pokemon Center interior could not be instantiated.")
		return
	add_child(interior)
	await get_tree().process_frame

	if not interior.scale.is_equal_approx(Vector3.ONE):
		_fail("Pokemon Center interior root must remain at unit scale.")
		return
	if not bool(interior.get_meta("mobile_web_level", false)):
		_fail("Pokemon Center interior is missing its mobile-web level contract.")
		return

	var environment_root := interior.get_node_or_null(
		^"NavigationRegion3D/WorldGeometry/Structures/Environment"
	) as Node3D
	if environment_root == null:
		_fail("Pokemon Center interior is missing its environment model.")
		return
	if not environment_root.scale.is_equal_approx(Vector3.ONE):
		_fail("Pokemon Center environment model must remain at unit scale.")
		return
	if _contains_collision(environment_root):
		_fail("Imported environment model must not contain generated triangle collision.")
		return

	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(environment_root, mesh_instances)
	if mesh_instances.size() != 1:
		_fail("Environment must contain exactly one MeshInstance3D; found %d." % mesh_instances.size())
		return
	var mesh_instance := mesh_instances[0]
	var mesh := mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() != EXPECTED_MATERIAL_DRAWS:
		_fail(
			"Environment must use exactly %d opaque material draws; found %d."
			% [EXPECTED_MATERIAL_DRAWS, 0 if mesh == null else mesh.get_surface_count()]
		)
		return
	var triangle_count := _triangle_count(mesh)
	if triangle_count != EXPECTED_TRIANGLES or triangle_count > MAX_ENVIRONMENT_TRIANGLES:
		_fail(
			"Environment has %d triangles; expected %d within the %d-triangle mobile budget."
			% [triangle_count, EXPECTED_TRIANGLES, MAX_ENVIRONMENT_TRIANGLES]
		)
		return
	var texture_sizes: Array[Vector2i] = []
	for surface_index in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
		if material == null:
			_fail("Environment surface %d is missing its mobile material." % surface_index)
			return
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			_fail("Environment surface %d must remain opaque." % surface_index)
			return
		if material.albedo_texture == null:
			_fail("Environment surface %d is missing its compact albedo texture." % surface_index)
			return
		texture_sizes.append(
			Vector2i(
				material.albedo_texture.get_width(),
				material.albedo_texture.get_height(),
			)
		)
	if not texture_sizes.has(Vector2i(128, 16)):
		_fail("Environment is missing its expected 128 x 16 palette texture.")
		return
	if not texture_sizes.has(Vector2i(512, 512)):
		_fail("Environment is missing its expected 512 x 512 classical brick texture.")
		return
	if mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("Environment shadow casting was disabled.")
		return

	var bounds := _bounds_in_ancestor_space(interior, mesh_instance)
	if (
		bounds.position.x < -6.25 or bounds.position.x > -5.95
		or bounds.end.x < 5.95 or bounds.end.x > 6.25
		or bounds.position.z < -5.25 or bounds.position.z > -4.95
		or bounds.end.z < 4.95 or bounds.end.z > 5.25
		or bounds.position.y < -0.05 or bounds.position.y > 0.05
		or bounds.end.y < 3.15 or bounds.end.y > 3.35
	):
		_fail("Environment bounds no longer match the authored 12 x 10 m room: %s" % bounds)
		return

	var collision_root := interior.get_node_or_null(
		^"NavigationRegion3D/WorldGeometry/Boundaries/Collision"
	) as Node3D
	if collision_root == null:
		_fail("Pokemon Center interior is missing simplified gameplay collision.")
		return
	var collision_shapes: Array[CollisionShape3D] = []
	_collect_collision_shapes(collision_root, collision_shapes)
	if collision_shapes.size() != EXPECTED_COLLISION_SHAPES:
		_fail(
			"Interior has %d authored collision shapes; expected %d."
			% [collision_shapes.size(), EXPECTED_COLLISION_SHAPES]
		)
		return
	for collision_shape in collision_shapes:
		if collision_shape.shape == null or collision_shape.disabled:
			_fail("Interior contains a missing or disabled authored collision shape.")
			return

	var required_nodes := [
		"EntrySpawn",
		"ExitToCity",
		"NurseSpawn",
		"PokemonCenterHealer",
		"VisitorSpawnLeft",
		"VisitorSpawnRight",
		"Player",
		"Camera3D",
		"WorldEnvironment",
		"GameUI",
	]
	for node_path: String in required_nodes:
		if _find_node_by_name(interior, StringName(node_path)) == null:
			_fail("Pokemon Center interior is missing required node %s." % node_path)
			return

	var key_light := interior.get_node_or_null(^"Environment/KeyLight") as DirectionalLight3D
	var fill_left := interior.get_node_or_null(^"Environment/CounterFillLeft") as OmniLight3D
	var fill_right := interior.get_node_or_null(^"Environment/CounterFillRight") as OmniLight3D
	if key_light == null or not key_light.shadow_enabled:
		_fail("Interior key light must retain basic directional shadows.")
		return
	if fill_left == null or fill_right == null or fill_left.shadow_enabled or fill_right.shadow_enabled:
		_fail("Interior fill lights must exist and remain shadow-free for mobile performance.")
		return

	var camera := interior.get_node_or_null(^"Player/Camera3D") as Camera3D
	if camera == null or not camera.current or camera.fov < 51.5 or camera.fov > 52.5:
		_fail("Interior gameplay camera no longer matches the authored lower-view composition.")
		return
	var exit_trigger := interior.get_node_or_null(^"Gameplay/Transitions/ExitToCity") as SceneTransferTrigger
	if (
		exit_trigger == null
		or exit_trigger.destination_scene_path != "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
		or exit_trigger.destination_spawn_marker != &"PokemonCenterEntrance"
	):
		_fail("Interior exit trigger no longer identifies the city return contract.")
		return

	var healer := interior.get_node_or_null(^"Gameplay/Actors/PokemonCenterHealer") as PFRCharacter
	var nurse_spawn := interior.get_node_or_null(^"Markers/NurseSpawn") as Marker3D
	if (
		healer == null
		or nurse_spawn == null
		or not healer.position.is_equal_approx(nurse_spawn.position)
		or not healer.controller.npc_behavior is PokemonCenterHealerBehavior
	):
		_fail("The staffed healer must occupy NurseSpawn and use PokemonCenterHealerBehavior.")
		return
	var interaction_area := healer.get_node_or_null(^"InteractionArea") as Area3D
	if interaction_area == null or interaction_area.collision_layer != 0 or interaction_area.collision_mask != 1:
		_fail("The healer needs a player-only, non-blocking desk interaction area.")
		return

	var healer_shape := healer.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var counter_shape := interior.get_node_or_null(
		^"NavigationRegion3D/WorldGeometry/Boundaries/Collision/HealingCounter/CollisionShape3D"
	) as CollisionShape3D
	var console_shape := interior.get_node_or_null(
		^"NavigationRegion3D/WorldGeometry/Boundaries/Collision/HealingConsole/CollisionShape3D"
	) as CollisionShape3D
	if (
		healer_shape == null
		or not healer_shape.shape is CapsuleShape3D
		or counter_shape == null
		or not counter_shape.shape is BoxShape3D
		or console_shape == null
		or not console_shape.shape is BoxShape3D
	):
		_fail("The staffed counter is missing its simplified clearance shapes.")
		return
	var healer_radius := (healer_shape.shape as CapsuleShape3D).radius
	var counter_back_z := (
		counter_shape.position.z - (counter_shape.shape as BoxShape3D).size.z * 0.5
	)
	var console_front_z := (
		console_shape.position.z + (console_shape.shape as BoxShape3D).size.z * 0.5
	)
	var clearance_margin := 0.05
	if (
		healer.position.z - healer_radius <= console_front_z + clearance_margin
		or healer.position.z + healer_radius >= counter_back_z - clearance_margin
	):
		_fail("The healer capsule no longer has safe clearance behind the desk.")
		return

	print(
		(
			"Pokemon Center interior smoke test passed: %d triangles, two opaque compact material draws, "
			+ "%d simplified collision shapes, staffed healer clearance, unit scale, gameplay markers, "
			+ "one shadowed key light, and two shadow-free fills."
		)
		% [triangle_count, collision_shapes.size()]
	)
	get_tree().quit(0)


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, output)


func _find_node_by_name(root: Node, target_name: StringName) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _collect_collision_shapes(node: Node, output: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		output.append(node as CollisionShape3D)
	for child: Node in node.get_children():
		_collect_collision_shapes(child, output)


func _contains_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		return true
	for child: Node in node.get_children():
		if _contains_collision(child):
			return true
	return false


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


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
