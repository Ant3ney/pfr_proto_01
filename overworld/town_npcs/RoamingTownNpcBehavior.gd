class_name RoamingTownNpcBehavior
extends TownNpcBehavior

## A conversational resident that strolls within a small authored radius,
## pauses between destinations, and stops whenever a UI sequence owns input.

@export_group("Roaming")
@export_range(0.5, 8.0, 0.1) var roaming_radius := 2.0
@export_range(0.0, 20.0, 0.1) var minimum_pause_seconds := 1.5
@export_range(0.0, 20.0, 0.1) var maximum_pause_seconds := 4.0
@export_range(0.05, 1.0, 0.05) var arrival_distance := 0.3

var _origin := Vector3.ZERO
var _origin_initialized := false
var _moving := false
var _wait_until_msec := 0
var _rng := RandomNumberGenerator.new()


func process_behavior(
	character: CharacterBody3D,
	controller: NPCController
) -> void:
	if not _origin_initialized:
		_origin = character.global_position
		_origin_initialized = true
		_rng.seed = hash("%s:%s" % [speaker_name, character.get_path()])
		_schedule_pause()

	if is_conversation_active() or not GameInstance.is_player_movement_enabled():
		controller.stop_moving(character)
		_moving = false
		_schedule_pause()
		return

	if _moving:
		var offset := character.global_position - controller.map_coordinates
		offset.y = 0.0
		if offset.length() <= arrival_distance:
			controller.stop_moving(character)
			_moving = false
			_schedule_pause()
		return

	if Time.get_ticks_msec() < _wait_until_msec:
		return
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(roaming_radius * 0.35, roaming_radius)
	var destination := _origin + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	controller.move_to(destination)
	_moving = true


func get_roaming_origin() -> Vector3:
	return _origin


func is_currently_roaming() -> bool:
	return _moving


func _schedule_pause() -> void:
	var lower := minf(minimum_pause_seconds, maximum_pause_seconds)
	var upper := maxf(minimum_pause_seconds, maximum_pause_seconds)
	_wait_until_msec = Time.get_ticks_msec() + roundi(_rng.randf_range(lower, upper) * 1000.0)
