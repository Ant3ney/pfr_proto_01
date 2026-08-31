extends Node

const ANNEX_SCENE := preload(
	"res://art/environments/new_bouffalant_city/pokemon_center_annex/pokemon_center_annex.tscn"
)
const EXPECTED_TRIANGLES := 1962
const MAX_ENVIRONMENT_TRIANGLES := 2100
const EXPECTED_MATERIAL_DRAWS := 2
const EXPECTED_COLLISION_SHAPES := 13


func _ready() -> void:
	var annex := ANNEX_SCENE.instantiate() as Node3D
	if annex == null:
		_fail("Pokemon Center annex could not be instantiated.")
		return
	add_child(annex)
	await get_tree().process_frame

	if not annex.scale.is_equal_approx(Vector3.ONE):
		_fail("Pokemon Center annex root must remain at unit scale.")
		return
	if not bool(annex.get_meta("mobile_web_level", false)):
		_fail("Pokemon Center annex is missing its mobile-web level contract.")
		return
	if String(annex.get_meta("exterior_opening", "")) != "east":
		_fail("Pokemon Center annex no longer identifies the east exterior opening.")
		return

	var environment_root := annex.get_node_or_null("Environment") as Node3D
	if environment_root == null:
		_fail("Pokemon Center annex is missing its environment model.")
		return
	if not environment_root.scale.is_equal_approx(Vector3.ONE):
		_fail("Pokemon Center annex environment must remain at unit scale.")
		return
	if _contains_collision(environment_root):
		_fail("Imported annex environment must not contain generated triangle collision.")
		return

	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(environment_root, mesh_instances)
	if mesh_instances.size() != 1:
		_fail("Annex environment must contain exactly one MeshInstance3D; found %d." % mesh_instances.size())
		return
	var mesh_instance := mesh_instances[0]
	var mesh := mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() != EXPECTED_MATERIAL_DRAWS:
		_fail(
			"Annex environment must use exactly %d opaque material draws; found %d."
			% [EXPECTED_MATERIAL_DRAWS, 0 if mesh == null else mesh.get_surface_count()]
		)
		return
	var triangle_count := _triangle_count(mesh)
	if triangle_count != EXPECTED_TRIANGLES or triangle_count > MAX_ENVIRONMENT_TRIANGLES:
		_fail(
			"Annex has %d triangles; expected %d within the %d-triangle mobile budget."
			% [triangle_count, EXPECTED_TRIANGLES, MAX_ENVIRONMENT_TRIANGLES]
		)
		return

	var texture_sizes: Array[Vector2i] = []
	for surface_index in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			_fail("Annex surface %d must use an opaque BaseMaterial3D." % surface_index)
			return
		if material.albedo_texture == null:
			_fail("Annex surface %d is missing its compact albedo texture." % surface_index)
			return
		texture_sizes.append(
			Vector2i(
				material.albedo_texture.get_width(),
				material.albedo_texture.get_height(),
			)
		)
	if not texture_sizes.has(Vector2i(128, 16)) or not texture_sizes.has(Vector2i(512, 512)):
		_fail("Annex must retain the 128 x 16 palette and 512 x 512 brick albedo.")
		return
	if mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("Annex environment shadow casting was disabled.")
		return

	var bounds := _bounds_in_ancestor_space(annex, mesh_instance)
	if (
		bounds.position.x < -5.25 or bounds.position.x > -4.95
		or bounds.end.x < 4.95 or bounds.end.x > 5.25
		or bounds.position.z < -4.75 or bounds.position.z > -4.45
		or bounds.end.z < 4.45 or bounds.end.z > 4.75
		or bounds.position.y < -0.05 or bounds.position.y > 0.05
		or bounds.end.y < 3.15 or bounds.end.y > 3.35
	):
		_fail("Annex bounds no longer match the authored 10 x 9 m room: %s" % bounds)
		return

	var collision_root := annex.get_node_or_null("Collision") as Node3D
	var collision_shapes: Array[CollisionShape3D] = []
	if collision_root != null:
		_collect_collision_shapes(collision_root, collision_shapes)
	if collision_shapes.size() != EXPECTED_COLLISION_SHAPES:
		_fail(
			"Annex has %d authored collision shapes; expected %d."
			% [collision_shapes.size(), EXPECTED_COLLISION_SHAPES]
		)
		return
	for collision_shape in collision_shapes:
		if collision_shape.shape == null or collision_shape.disabled:
			_fail("Annex contains a missing or disabled authored collision shape.")
			return

	for node_path: String in [
		"EntrySpawn",
		"ExitToCity",
		"ClerkSpawn",
		"ConsultationVisitorSpawn",
		"LockerVisitorSpawn",
		"Player",
		"Camera",
		"WorldEnvironment",
		"GameUI",
	]:
		if annex.get_node_or_null(node_path) == null:
			_fail("Pokemon Center annex is missing required node %s." % node_path)
			return

	var exit_trigger := annex.get_node_or_null("ExitToCity") as SceneTransferTrigger
	if (
		exit_trigger == null
		or exit_trigger.destination_scene_path != "res://demo/primary_development_enviroment.tscn"
		or exit_trigger.destination_spawn_marker != &"PokemonCenterEastEntrance"
	):
		_fail("Annex exit no longer identifies the east city return contract.")
		return
	var key_light := annex.get_node_or_null("KeyLight") as DirectionalLight3D
	var fill_a := annex.get_node_or_null("DispensaryFill") as OmniLight3D
	var fill_b := annex.get_node_or_null("ConsultationFill") as OmniLight3D
	if key_light == null or not key_light.shadow_enabled:
		_fail("Annex key light must retain basic directional shadows.")
		return
	if fill_a == null or fill_b == null or fill_a.shadow_enabled or fill_b.shadow_enabled:
		_fail("Annex fill lights must remain shadow-free for mobile performance.")
		return

	print(
		(
			"Pokemon Center annex smoke test passed: %d triangles, two opaque compact draws, "
			+ "%d simplified collision shapes, an east-door return contract, one shadowed key, "
			+ "and two shadow-free fills."
		)
		% [triangle_count, collision_shapes.size()]
	)
	get_tree().quit(0)


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, output)


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
