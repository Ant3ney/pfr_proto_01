class_name RNDPlayerInteractionDetector
extends Node

## Chooses one interactable PFRCharacter inside the player's forward view.
## A short cone is intentionally more forgiving than a single physics ray for
## touch controls and for attendants standing behind an authored counter.

signal target_changed(target: PFRCharacter, prompt_text: String)

const CHARACTER_GROUP := &"pfr_characters"

@export_range(0.5, 10.0, 0.1, "or_greater", "suffix:m")
var interaction_distance := 3.25
@export_range(5.0, 85.0, 1.0, "degrees")
var view_half_angle_degrees := 38.0
@export_range(0.1, 3.0, 0.05, "or_greater", "suffix:m")
var sight_line_height := 1.35
@export_flags_3d_physics var sight_collision_mask := 1

var _player: PlayerCharacter
var _current_target: PFRCharacter
var _current_prompt := ""


func _ready() -> void:
	_player = get_parent() as PlayerCharacter
	if _player == null:
		push_error("%s must be a child of PlayerCharacter." % get_path())
		set_physics_process(false)
		return
	_refresh_target()


func _physics_process(_delta: float) -> void:
	_refresh_target()


func get_current_target() -> PFRCharacter:
	return _current_target


func get_current_prompt() -> String:
	return _current_prompt


func is_interaction_available() -> bool:
	return (
		is_instance_valid(_current_target)
		and _current_target.can_interact(_player)
	)


## Dispatches through the target's controller/behavior boundary. Returns true
## only when that behavior accepted and started its sequence.
func try_interact() -> bool:
	if not is_interaction_available():
		_refresh_target()
		return false
	var target := _current_target
	var accepted := target.interact(_player)
	if accepted:
		_set_target(null, "")
	return accepted


func _refresh_target() -> void:
	if (
		_player == null
		or not GameInstance.is_player_movement_enabled()
		or GameInstance.is_battle_start_in_progress()
		or GameInstance.is_battle_return_in_progress()
		or GameInstance.is_scene_transfer_in_progress()
	):
		_set_target(null, "")
		return

	var visual := _player.get_node_or_null(^"Visual") as Node3D
	var facing_basis := visual.global_basis if visual != null else _player.global_basis
	var forward := -facing_basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		_set_target(null, "")
		return
	forward = forward.normalized()

	var minimum_dot := cos(deg_to_rad(view_half_angle_degrees))
	var best_target: PFRCharacter
	var best_score := INF
	for node: Node in get_tree().get_nodes_in_group(CHARACTER_GROUP):
		if not node is PFRCharacter or node == _player:
			continue
		var candidate := node as PFRCharacter
		if not candidate.can_interact(_player):
			continue

		var offset := candidate.global_position - _player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001 or distance > interaction_distance:
			continue
		var facing_alignment := forward.dot(offset / distance)
		if facing_alignment < minimum_dot:
			continue
		if not _has_clear_sight(candidate):
			continue

		# Prefer the nearest centered target when several trainers are lined up.
		var score := distance + (1.0 - facing_alignment) * interaction_distance
		if score < best_score:
			best_score = score
			best_target = candidate

	var prompt := (
		best_target.get_interaction_prompt(_player)
		if best_target != null
		else ""
	)
	_set_target(best_target, prompt)


func _has_clear_sight(candidate: PFRCharacter) -> bool:
	var ray_start := _player.global_position + Vector3.UP * sight_line_height
	var ray_end := candidate.global_position + Vector3.UP * sight_line_height
	var query := PhysicsRayQueryParameters3D.create(
		ray_start,
		ray_end,
		sight_collision_mask,
		[_player.get_rid()]
	)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == candidate


func _set_target(target: PFRCharacter, prompt: String) -> void:
	var normalized_prompt := prompt.strip_edges()
	if target == _current_target and normalized_prompt == _current_prompt:
		return
	_current_target = target
	_current_prompt = normalized_prompt
	target_changed.emit(_current_target, _current_prompt)
