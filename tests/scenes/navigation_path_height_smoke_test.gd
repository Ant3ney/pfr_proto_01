extends Node3D

const MOVE_SPEED := 4.0
const PHYSICS_STEP := 1.0 / 60.0
const TEST_TIMEOUT_FRAMES := 240
const ARRIVAL_DISTANCE := 0.15


func _ready() -> void:
	var test_cases: Array[Dictionary] = [
		_create_test_case("ground_level", Vector3.ZERO, 0.0),
		_create_test_case("elevated_path", Vector3(20.0, 0.0, 0.0), 0.5),
	]

	if not await _wait_for_navigation_map(test_cases.size()):
		_fail("Navigation map did not synchronize both test regions.")
		return

	for test_case: Dictionary in test_cases:
		var controller := test_case["controller"] as NPCController
		controller.move_to(test_case["target"] as Vector3)

	for frame in range(TEST_TIMEOUT_FRAMES):
		var all_arrived := true
		for test_case: Dictionary in test_cases:
			var character := test_case["character"] as CharacterBody3D
			var target := test_case["target"] as Vector3
			var horizontal_offset := Vector2(
				target.x - character.global_position.x,
				target.z - character.global_position.z
			)
			if horizontal_offset.length() <= ARRIVAL_DISTANCE:
				continue

			all_arrived = false
			var controller := test_case["controller"] as NPCController
			var next_position := controller.get_move_target(character)
			var movement_offset := Vector2(
				next_position.x - character.global_position.x,
				next_position.z - character.global_position.z
			)
			if not movement_offset.is_zero_approx():
				var movement_step := minf(
					MOVE_SPEED * PHYSICS_STEP,
					movement_offset.length()
				)
				var movement_direction := movement_offset.normalized()
				character.global_position += Vector3(
					movement_direction.x * movement_step,
					0.0,
					movement_direction.y * movement_step
				)

		if all_arrived:
			break
		await get_tree().physics_frame

	for test_case: Dictionary in test_cases:
		if not _validate_test_case(test_case):
			return

	print(
		"Navigation path height smoke test passed: "
		+ "ground-level and 0.5 m elevated paths both reached at character Y = 0."
	)
	get_tree().quit(0)


func _create_test_case(
	case_name: String,
	center: Vector3,
	path_height: float
) -> Dictionary:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.set_vertices(PackedVector3Array([
		Vector3(-4.0, path_height, -4.0),
		Vector3(-4.0, path_height, 4.0),
		Vector3(4.0, path_height, 4.0),
		Vector3(4.0, path_height, -4.0),
	]))
	navigation_mesh.add_polygon(PackedInt32Array([3, 2, 0]))
	navigation_mesh.add_polygon(PackedInt32Array([0, 2, 1]))

	var region := NavigationRegion3D.new()
	region.name = "%sRegion" % case_name.to_pascal_case()
	region.position = center
	region.navigation_mesh = navigation_mesh
	add_child(region)

	var character := CharacterBody3D.new()
	character.name = "%sCharacter" % case_name.to_pascal_case()
	character.position = center + Vector3(-3.0, 0.0, 0.0)
	add_child(character)

	return {
		"name": case_name,
		"character": character,
		"controller": NPCController.new(),
		"target": center + Vector3(3.0, 0.0, 0.0),
		"expected_path_height_offset": path_height,
	}


func _wait_for_navigation_map(expected_region_count: int) -> bool:
	var navigation_map := get_world_3d().get_navigation_map()
	for frame in range(60):
		await get_tree().physics_frame
		if (
			NavigationServer3D.map_get_iteration_id(navigation_map) > 0
			and NavigationServer3D.map_get_regions(navigation_map).size()
				>= expected_region_count
		):
			return true
	return false


func _validate_test_case(test_case: Dictionary) -> bool:
	var case_name := str(test_case["name"])
	var character := test_case["character"] as CharacterBody3D
	var target := test_case["target"] as Vector3
	var horizontal_distance := Vector2(
		target.x - character.global_position.x,
		target.z - character.global_position.z
	).length()
	if horizontal_distance > ARRIVAL_DISTANCE:
		_fail("%s did not reach its target; %.3f m remain." % [
			case_name,
			horizontal_distance,
		])
		return false

	if not is_zero_approx(character.global_position.y):
		_fail("%s changed character height to %.3f." % [
			case_name,
			character.global_position.y,
		])
		return false

	var navigation_agent := character.get_node_or_null(
		^"NavigationAgent3D"
	) as NavigationAgent3D
	if not navigation_agent:
		_fail("%s did not create a NavigationAgent3D." % case_name)
		return false

	var expected_offset := float(test_case["expected_path_height_offset"])
	if not is_equal_approx(
		navigation_agent.path_height_offset,
		expected_offset
	):
		_fail("%s used path-height offset %.3f; expected %.3f." % [
			case_name,
			navigation_agent.path_height_offset,
			expected_offset,
		])
		return false

	return true


func _fail(message: String) -> void:
	push_error("Navigation path height smoke test failed: %s" % message)
	get_tree().quit(1)
