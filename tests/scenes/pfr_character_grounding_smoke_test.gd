extends Node3D

const DESTINATION := Vector3(3.5, 0.0, 0.0)
const ARRIVAL_DISTANCE := 0.12
const MAX_TRAVEL_FRAMES := 180
const MAX_GROUND_GAP := 0.12


class FixedTargetController extends NPCController:
	var move_target := Vector3.ZERO


	func get_move_target(_character: CharacterBody3D) -> Vector3:
		return move_target


var _failures: Array[String] = []

@onready var character: PFRCharacter = $GroundedCharacter


func _ready() -> void:
	# The authored child has already run PFRCharacter._ready(), so this check
	# verifies the startup raycast without waiting for a physics frame.
	var startup_ground_y := _ground_height_at(character)
	_check(
		absf(character.global_position.y - startup_ground_y) <= 0.01,
		"PFRCharacter._ready() should snap an elevated character to the ground."
	)

	var controller := FixedTargetController.new()
	controller.move_target = DESTINATION
	character.controller = controller
	controller.prepare_for_character(character)

	var greatest_ground_gap := 0.0
	for _frame in range(MAX_TRAVEL_FRAMES):
		await get_tree().physics_frame
		var horizontal_distance := Vector2(
			DESTINATION.x - character.global_position.x,
			DESTINATION.z - character.global_position.z
		).length()
		var ground_y := _ground_height_at(character)
		greatest_ground_gap = maxf(
			greatest_ground_gap,
			absf(character.global_position.y - ground_y)
		)
		if horizontal_distance <= ARRIVAL_DISTANCE:
			break

	var remaining_distance := Vector2(
		DESTINATION.x - character.global_position.x,
		DESTINATION.z - character.global_position.z
	).length()
	_check(
		remaining_distance <= ARRIVAL_DISTANCE,
		"The character should travel across the sloped ground to its target."
	)
	_check(
		greatest_ground_gap <= MAX_GROUND_GAP,
		"Periodic probes should keep travel on the ground plane; max gap was %.3f m."
		% greatest_ground_gap
	)
	_check(
		character.global_position.y < startup_ground_y - 1.0,
		"The character should follow the slope downward instead of retaining its startup Y."
	)

	controller.move_target = character.global_position
	character.character_movement.prepare_for_character(character)
	character.global_position += Vector3.UP
	var lifted_position_y := character.global_position.y
	await get_tree().physics_frame
	_check(
		character.global_position.y > lifted_position_y - 0.1,
		"Ground probes should honor their interval instead of running every frame."
	)
	for _frame in range(8):
		await get_tree().physics_frame
		if character.global_position.y < lifted_position_y - 0.5:
			break
	_check(
		absf(
			character.global_position.y
			- _ground_height_at(character)
		) <= 0.01,
		"A later periodic probe should return a displaced character to the ground."
	)

	_finish()


func _ground_height_at(character: CharacterBody3D) -> float:
	var world_position := character.global_position
	var excluded_bodies: Array[RID] = [character.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(world_position.x, 10.0, world_position.z),
		Vector3(world_position.x, -10.0, world_position.z),
		1,
		excluded_bodies
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_fail("The grounding fixture should have collision below the character.")
		return world_position.y
	return (hit["position"] as Vector3).y


func _finish() -> void:
	if _failures.is_empty():
		print(
			"PFRCharacter grounding smoke test passed: startup and periodic "
			+ "raycasts keep shared characters on sloped ground."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("PFRCharacter grounding smoke test failed: %s" % failure)
	get_tree().quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)
