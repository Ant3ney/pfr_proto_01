extends Node

## Owns state and operations that apply across the entire game.

signal battle_starting(battle_data: Dictionary)
signal battle_scene_entered(battle_data: Dictionary)
signal battle_start_finished(battle_data: Dictionary)
signal battle_start_failed(message: String)

const BATTLE_SCENE_PATH := "res://battle/battle_scene.tscn"

var _player_movement_enabled := true
var _pending_battle_data: Dictionary = {}
var _active_battle_data: Dictionary = {}
var _battle_transition_ui: UITemplate
var _battle_start_in_progress := false
var _battle_scene_change_requested := false
var _battle_scene_has_entered := false
var _battle_template_reveal_finished := false
var _battle_local_intro_finished := false
var _movement_enabled_before_battle := true


func set_player_movement_enabled(is_enabled: bool) -> void:
	_player_movement_enabled = is_enabled


func is_player_movement_enabled() -> bool:
	return _player_movement_enabled


## Begins the complete visual handoff into battle. The passed dictionary is
## deep-copied, enriched with implicit scene/transition data, and kept in
## temporary GameInstance state for the battle scene to consume.
func startBattle(battle_data: Dictionary = {}) -> bool:
	if _battle_start_in_progress:
		push_warning("GameInstance rejected startBattle: a battle start is already active.")
		return false
	_movement_enabled_before_battle = _player_movement_enabled
	if not ResourceLoader.exists(BATTLE_SCENE_PATH):
		return _fail_battle_start(
			"Battle scene is missing: %s" % BATTLE_SCENE_PATH
		)

	set_player_movement_enabled(false)
	_pending_battle_data = _build_battle_start_data(battle_data)
	_active_battle_data.clear()
	_battle_start_in_progress = true
	_battle_scene_change_requested = false
	_battle_scene_has_entered = false
	_battle_template_reveal_finished = false
	_battle_local_intro_finished = false
	battle_starting.emit(get_pending_battle_data())

	_battle_transition_ui = UIManager.show_ui("")
	if not is_instance_valid(_battle_transition_ui):
		return _fail_battle_start(
			"UIManager could not create the battle transition template."
		)

	_battle_transition_ui.set_dismiss_callback(
		_on_battle_transition_dismissed
	)
	_battle_transition_ui.play_battle_transition_out(
		_pending_battle_data,
		_change_to_battle_scene
	)
	return true


## Called by the battle scene after it has prepared its local intro UI. This is
## the handoff point that promotes pending data to active battle data and tells
## the persistent template to reveal the new scene.
func enter_battle_scene() -> Dictionary:
	if not _battle_start_in_progress:
		return {}
	if _battle_scene_has_entered:
		return get_active_battle_data()

	_active_battle_data = _pending_battle_data.duplicate(true)
	_pending_battle_data.clear()
	_battle_scene_has_entered = true
	battle_scene_entered.emit(get_active_battle_data())

	if is_instance_valid(_battle_transition_ui):
		_battle_transition_ui.play_battle_transition_in(
			_on_battle_reveal_finished
		)
	else:
		_complete_battle_start_without_template()
	return get_active_battle_data()


func get_pending_battle_data() -> Dictionary:
	return _pending_battle_data.duplicate(true)


func get_active_battle_data() -> Dictionary:
	return _active_battle_data.duplicate(true)


func is_battle_start_in_progress() -> bool:
	return _battle_start_in_progress


## Called by BattleScene after its scene-local flash, ring, banner, and camera
## motion are complete. The launch is finished only after this and the global
## UITemplate reveal have both completed.
func notify_battle_intro_finished() -> void:
	if not _battle_start_in_progress or not _battle_scene_has_entered:
		return
	_battle_local_intro_finished = true
	_try_finish_battle_start()


func _build_battle_start_data(battle_data: Dictionary) -> Dictionary:
	var prepared := battle_data.duplicate(true)
	var source_scene_path := ""
	var current_scene := get_tree().current_scene
	if current_scene:
		source_scene_path = current_scene.scene_file_path
	prepared["source_scene_path"] = source_scene_path
	if not prepared.has("return_scene_path"):
		prepared["return_scene_path"] = source_scene_path

	var encounter_type := String(
		prepared.get("encounter_type", "wild")
	).strip_edges().to_lower()
	if encounter_type.is_empty():
		encounter_type = "wild"
	prepared["encounter_type"] = encounter_type
	if String(prepared.get("transition_title", "")).strip_edges().is_empty():
		prepared["transition_title"] = _default_battle_transition_title(
			encounter_type
		)
	if String(prepared.get("transition_subtitle", "")).strip_edges().is_empty():
		prepared["transition_subtitle"] = _default_battle_transition_subtitle(
			prepared
		)
	return prepared


func _default_battle_transition_title(encounter_type: String) -> String:
	match encounter_type:
		"trainer":
			return "TRAINER BATTLE"
		"rival":
			return "RIVAL BATTLE"
		"wild":
			return "WILD ENCOUNTER"
		_:
			return "BATTLE START"


func _default_battle_transition_subtitle(battle_data: Dictionary) -> String:
	for field in ["opponent_name", "trainer_name", "encounter_name"]:
		var candidate := String(battle_data.get(field, "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	return "A NEW CHALLENGER APPROACHES"


func _change_to_battle_scene() -> void:
	if not _battle_start_in_progress or _battle_scene_change_requested:
		return
	_battle_scene_change_requested = true
	var error := get_tree().change_scene_to_file(BATTLE_SCENE_PATH)
	if error != OK:
		_fail_battle_start(
			"Unable to open the battle scene: %s" % error_string(error)
		)


func _on_battle_reveal_finished() -> void:
	if not _battle_start_in_progress or not _battle_scene_has_entered:
		return
	_battle_template_reveal_finished = true
	_try_finish_battle_start()


func _on_battle_transition_dismissed() -> void:
	_battle_transition_ui = null
	var was_unexpected := (
		_battle_start_in_progress and not _battle_scene_has_entered
	)
	if not was_unexpected:
		_battle_template_reveal_finished = true
		_try_finish_battle_start()
		return

	_battle_start_in_progress = false
	_battle_scene_change_requested = false
	_pending_battle_data.clear()
	set_player_movement_enabled(_movement_enabled_before_battle)
	var message := "The battle transition closed before the battle scene loaded."
	push_error(message)
	battle_start_failed.emit(message)


func _complete_battle_start_without_template() -> void:
	_battle_template_reveal_finished = true
	_try_finish_battle_start()


func _try_finish_battle_start() -> void:
	if (
		not _battle_start_in_progress
		or not _battle_scene_has_entered
		or not _battle_template_reveal_finished
		or not _battle_local_intro_finished
		or is_instance_valid(_battle_transition_ui)
	):
		return
	_battle_start_in_progress = false
	_battle_scene_change_requested = false
	battle_start_finished.emit(get_active_battle_data())


func _fail_battle_start(message: String) -> bool:
	var transition := _battle_transition_ui
	_battle_transition_ui = null
	_pending_battle_data.clear()
	_active_battle_data.clear()
	_battle_start_in_progress = false
	_battle_scene_change_requested = false
	_battle_scene_has_entered = false
	_battle_template_reveal_finished = false
	_battle_local_intro_finished = false
	set_player_movement_enabled(_movement_enabled_before_battle)
	if is_instance_valid(transition):
		transition.set_dismiss_callback(Callable())
		transition.close()
	push_error("GameInstance could not start battle: %s" % message)
	battle_start_failed.emit(message)
	return false
