class_name PFRCharacter
extends CharacterBody3D

## Reusable character locomotion. Child classes provide movement intent by
## overriding _get_movement_input().

@export_group("Character Art")
@export var character_art_asset_pack: PFRCharacterArtAssetPack

@export_group("Movement")
@export_range(1.0, 10.0) var move_speed := 4.0

@export_group("Turning")
## Radius of normal moving turns, measured in meters. Lower values turn tighter.
@export_range(0.1, 5.0, 0.05, "or_greater") var turn_radius := 0.75
## Maximum rotation speed while traveling toward the input direction.
@export_range(1.0, 720.0, 1.0, "degrees") var travel_to_target_angle_speed := 460.0
## Rotation speed used while the character is stopped and turning in place.
@export_range(45.0, 1080.0, 1.0, "degrees") var turn_in_place_speed := 970.0
## Direction changes at or above this angle trigger a turn in place.
@export_range(91.0, 179.0, 1.0, "degrees") var turn_in_place_angle := 91.0

@export_group("Animation")
@export_range(0.0, 1.0, 0.01) var animation_blend_time := 0.15

var is_turning_in_place := false

var visual: Node3D
var character_art: Node3D
var animation_player: AnimationPlayer

var _idle_playback_animation: StringName
var _run_playback_animation: StringName
var _current_animation: StringName


func _ready() -> void:
	if not _load_character_art_asset_pack():
		set_physics_process(false)
		return

	if not _prepare_animation_library():
		set_physics_process(false)
		return

	_play_animation(_idle_playback_animation)


func _physics_process(delta: float) -> void:
	var input_vector := _get_movement_input()
	var move_direction := _screen_input_to_world(input_vector)
	var input_strength := input_vector.length()

	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0

	if not move_direction.is_zero_approx():
		_steer_toward(move_direction, input_strength, delta)
	else:
		is_turning_in_place = false

	move_and_slide()
	_update_animation()


## Override this in a child class to drive the character.
func _get_movement_input() -> Vector2:
	return Vector2.ZERO


func _load_character_art_asset_pack() -> bool:
	if not character_art_asset_pack:
		push_error("%s requires a character art asset pack." % name)
		return false

	var validation_error := character_art_asset_pack.get_validation_error()
	if not validation_error.is_empty():
		push_error("%s has an invalid character art asset pack: %s" % [
			name,
			validation_error,
		])
		return false

	visual = get_node_or_null(^"Visual") as Node3D
	if not visual:
		visual = Node3D.new()
		visual.name = "Visual"
		add_child(visual)

	var art_instance := character_art_asset_pack.character_scene.instantiate()
	if not art_instance is Node3D:
		push_error("%s's character art scene must have a Node3D root." % name)
		art_instance.free()
		return false

	character_art = art_instance as Node3D
	character_art.name = "CharacterArt"
	character_art.rotation_degrees = (
		character_art_asset_pack.character_scene_rotation_degrees
	)
	visual.add_child(character_art)

	animation_player = character_art.get_node_or_null(
		character_art_asset_pack.animation_player_path
	) as AnimationPlayer
	if not animation_player:
		push_error(
			"%s's character art pack does not contain the required AnimationPlayer at '%s'."
			% [name, character_art_asset_pack.animation_player_path]
		)
		return false

	return true


func _steer_toward(target_direction: Vector3, input_strength: float, delta: float) -> void:
	var target_angle := atan2(-target_direction.x, -target_direction.z)
	var angle_to_target := absf(
		wrapf(target_angle - visual.rotation.y, -PI, PI)
	)
	var turn_in_place_threshold := deg_to_rad(turn_in_place_angle)

	if angle_to_target >= turn_in_place_threshold:
		is_turning_in_place = true

	if is_turning_in_place:
		var pivot_step := deg_to_rad(turn_in_place_speed) * delta
		visual.rotation.y = rotate_toward(visual.rotation.y, target_angle, pivot_step)

		angle_to_target = absf(
			wrapf(target_angle - visual.rotation.y, -PI, PI)
		)
		if angle_to_target >= turn_in_place_threshold:
			return

		is_turning_in_place = false

	# Moving along the current facing direction while rotating produces an arc.
	# angular_speed = linear_speed / radius, so turn_radius is measured in meters.
	var current_speed := move_speed * input_strength
	var radius_turn_speed := current_speed / maxf(turn_radius, 0.001)
	var travel_turn_speed := deg_to_rad(travel_to_target_angle_speed)
	var turn_speed := minf(radius_turn_speed, travel_turn_speed)
	visual.rotation.y = rotate_toward(
		visual.rotation.y,
		target_angle,
		turn_speed * delta
	)

	var facing_direction := -visual.global_basis.z
	facing_direction.y = 0.0
	facing_direction = facing_direction.normalized()
	velocity.x = facing_direction.x * current_speed
	velocity.z = facing_direction.z * current_speed


func _prepare_animation_library() -> bool:
	var idle_clip := _duplicate_without_root_motion(
		character_art_asset_pack.idle_animation
	)
	var run_clip := _duplicate_without_root_motion(
		character_art_asset_pack.run_animation
	)
	if not idle_clip or not run_clip:
		return false

	var locomotion_library := AnimationLibrary.new()
	locomotion_library.add_animation(&"idle", idle_clip)
	locomotion_library.add_animation(&"run", run_clip)
	_idle_playback_animation = &"locomotion/idle"
	_run_playback_animation = &"locomotion/run"

	if animation_player.has_animation_library(&"locomotion"):
		animation_player.remove_animation_library(&"locomotion")
	animation_player.add_animation_library(&"locomotion", locomotion_library)
	return true


func _duplicate_without_root_motion(animation_name: StringName) -> Animation:
	if not animation_player.has_animation(animation_name):
		push_error(
			"%s's character art pack is missing animation '%s'."
			% [name, animation_name]
		)
		return null

	var animation := animation_player.get_animation(animation_name).duplicate(true) as Animation
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		var track_path := animation.track_get_path(track_index)
		var targets_root_motion := (
			animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
			and track_path.get_subname_count() > 0
			and track_path.get_subname(track_path.get_subname_count() - 1)
				== character_art_asset_pack.root_motion_bone
		)
		if targets_root_motion:
			animation.remove_track(track_index)

	return animation


func _update_animation() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var desired_animation := (
		_run_playback_animation
		if horizontal_speed > 0.05
		else _idle_playback_animation
	)
	_play_animation(desired_animation)


func _play_animation(animation_name: StringName) -> void:
	if animation_name.is_empty() or animation_name == _current_animation:
		return

	animation_player.play(animation_name, animation_blend_time)
	_current_animation = animation_name


func _screen_input_to_world(input_vector: Vector2) -> Vector3:
	if input_vector.is_zero_approx():
		return Vector3.ZERO

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3(input_vector.x, 0.0, input_vector.y).normalized()

	var camera_right := camera.global_basis.x
	var camera_forward := -camera.global_basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()

	return (camera_right * input_vector.x - camera_forward * input_vector.y).normalized()
