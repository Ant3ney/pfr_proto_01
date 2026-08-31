@tool
class_name TallGrassEncounterZone
extends Area3D

## Reusable walkable tall-grass patch. Encounter checks are based on horizontal
## distance travelled, so idling in the grass never starts a battle.

signal encounter_roll_completed(roll: float, chance: float, succeeded: bool)
signal encounter_selected(battle_data: Dictionary)
signal encounter_started(encounter_id: String)
signal encounter_start_failed(message: String)

@export_group("Encounter")
@export_file("*.tscn") var battle_scene_path := ""
@export var encounter_id := ""
@export var encounter_name := "Wild Pokemon"
@export_range(0.0, 1.0, 0.001) var encounter_chance_per_check := 0.08
@export_range(0.25, 20.0, 0.25, "suffix:m") var distance_between_checks := 2.0
@export var enabled := true

@export_group("Runtime")
## Leave enabled in levels. Tests and custom encounter directors may disable
## this and consume encounter_selected instead.
@export var start_battle_automatically := true
## Zero selects a fresh random seed. A non-zero value makes rolls repeatable.
@export var random_seed := 0
@export_range(0.5, 10.0, 0.5, "suffix:m") var maximum_tracked_frame_distance := 2.0

var _active_player: PlayerCharacter
var _last_player_position := Vector3.ZERO
var _distance_since_check := 0.0
var _encounter_pending := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_active_player):
		_clear_active_player()
		return

	var current_position := _active_player.global_position
	var horizontal_delta := Vector2(
		current_position.x - _last_player_position.x,
		current_position.z - _last_player_position.z
	).length()
	_last_player_position = current_position

	if (
		not enabled
		or _encounter_pending
		or not GameInstance.is_player_movement_enabled()
		or GameInstance.is_battle_start_in_progress()
		or GameInstance.is_battle_return_in_progress()
		or GameInstance.is_scene_transfer_in_progress()
	):
		return
	if horizontal_delta <= 0.0001 or horizontal_delta > maximum_tracked_frame_distance:
		return

	_distance_since_check += horizontal_delta
	var check_distance := maxf(distance_between_checks, 0.25)
	while _distance_since_check >= check_distance and not _encounter_pending:
		_distance_since_check -= check_distance
		_perform_encounter_check()


func is_encounter_pending() -> bool:
	return _encounter_pending


## Makes the patch reusable after a custom encounter director finishes.
func reset_encounter_state() -> void:
	_encounter_pending = false
	_distance_since_check = 0.0
	if is_instance_valid(_active_player):
		_last_player_position = _active_player.global_position
		set_physics_process(true)


func _perform_encounter_check() -> void:
	var chance := clampf(encounter_chance_per_check, 0.0, 1.0)
	var roll := _rng.randf()
	var succeeded := roll < chance
	encounter_roll_completed.emit(roll, chance, succeeded)
	if not succeeded:
		return

	var battle_data := _build_battle_data()
	_encounter_pending = true
	set_physics_process(false)
	encounter_selected.emit(battle_data.duplicate(true))
	if not start_battle_automatically:
		return

	var validation_error := _get_battle_configuration_error()
	if not validation_error.is_empty():
		_recover_from_failed_start(validation_error)
		return
	if not GameInstance.startBattle(battle_data):
		_recover_from_failed_start("GameInstance rejected the wild encounter battle start.")
		return
	encounter_started.emit(encounter_id.strip_edges())


func _build_battle_data() -> Dictionary:
	return {
		"encounter_type": "wild",
		"encounter_name": encounter_name.strip_edges(),
		"opponent_name": encounter_name.strip_edges(),
		"battle_scene_path": battle_scene_path.strip_edges(),
		"encounter_id": encounter_id.strip_edges(),
	}


func _get_battle_configuration_error() -> String:
	var normalized_path := battle_scene_path.strip_edges()
	if normalized_path.is_empty():
		return "Tall grass has no battle scene configured."
	if not ResourceLoader.exists(normalized_path, "PackedScene"):
		return "Tall grass battle scene is missing: %s" % normalized_path
	if encounter_id.strip_edges().is_empty():
		return "Tall grass has no encounter ID configured."
	return ""


func _recover_from_failed_start(message: String) -> void:
	_encounter_pending = false
	_distance_since_check = 0.0
	if is_instance_valid(_active_player):
		_last_player_position = _active_player.global_position
		set_physics_process(true)
	push_warning("%s: %s" % [get_path(), message])
	encounter_start_failed.emit(message)


func _on_body_entered(body: Node3D) -> void:
	if not enabled or _encounter_pending or not body is PlayerCharacter:
		return
	_active_player = body as PlayerCharacter
	_last_player_position = _active_player.global_position
	_distance_since_check = 0.0
	set_physics_process(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _active_player:
		_clear_active_player()


func _clear_active_player() -> void:
	_active_player = null
	_distance_since_check = 0.0
	set_physics_process(false)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var configuration_error := _get_battle_configuration_error()
	if not configuration_error.is_empty():
		warnings.append(configuration_error)
	var has_enabled_shape := false
	for node: Node in find_children("*", "CollisionShape3D", true, false):
		var collision_shape := node as CollisionShape3D
		if collision_shape != null and collision_shape.shape != null and not collision_shape.disabled:
			has_enabled_shape = true
			break
	if not has_enabled_shape:
		warnings.append("Add an enabled CollisionShape3D for the walkable grass volume.")
	return warnings
