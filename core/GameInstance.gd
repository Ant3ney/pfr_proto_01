extends Node

## Owns state and operations that apply across the entire game.

signal battle_starting(battle_data: Dictionary)
signal battle_scene_entered(battle_data: Dictionary)
signal battle_start_finished(battle_data: Dictionary)
signal battle_start_failed(message: String)
signal battle_return_started(encounter_id: String)
signal battle_return_finished
signal battle_return_failed(message: String)
signal scene_transfer_started(destination_scene_path: String, destination_spawn_marker: StringName)
signal scene_transfer_finished(
	destination_scene_path: String,
	destination_spawn_marker: StringName,
	spawn_marker_applied: bool
)
signal scene_transfer_failed(message: String)

const DEFAULT_BATTLE_SCENE_PATH := "res://battle/battle_scene.tscn"
const DEFAULT_RETURN_SCENE_PATH := "res://demo/primary_development_enviroment.tscn"

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
var _battle_scene_path := DEFAULT_BATTLE_SCENE_PATH
var _battle_return_in_progress := false
var _battle_return_scene_path := DEFAULT_RETURN_SCENE_PATH
var _battle_return_source_scene_path := ""
var _battle_return_player_transform := Transform3D.IDENTITY
var _battle_return_player_visual_rotation := Vector3.ZERO
var _has_battle_return_player_state := false
var _one_scene_suppression_id := ""
var _suppression_scene_instance_id := 0
var _consumed_standard_trainer_sight_encounters: Dictionary = {}
var _scene_transfer_in_progress := false
var _scene_transfer_destination_path := ""
var _scene_transfer_spawn_marker: StringName = &""
var _movement_enabled_before_scene_transfer := true


func _ready() -> void:
	get_tree().scene_changed.connect(_on_any_scene_changed)


func set_player_movement_enabled(is_enabled: bool) -> void:
	_player_movement_enabled = is_enabled


func is_player_movement_enabled() -> bool:
	return _player_movement_enabled


## Changes to an authored scene while preserving the cross-scene movement
## contract. If a marker name is supplied, the destination's PlayerCharacter
## is moved to the matching Node3D after the new scene has entered the tree.
func transfer_to_scene(
	destination_scene_path: String,
	destination_spawn_marker: StringName = &""
) -> bool:
	if _scene_transfer_in_progress:
		return _reject_scene_transfer("A scene transfer is already in progress.")
	if _battle_start_in_progress or _battle_return_in_progress:
		return _reject_scene_transfer("A battle scene transition is already in progress.")

	var normalized_path := destination_scene_path.strip_edges()
	if normalized_path.is_empty():
		return _reject_scene_transfer("The destination scene path is empty.")
	if not ResourceLoader.exists(normalized_path, "PackedScene"):
		return _reject_scene_transfer("Destination scene is missing: %s" % normalized_path)

	_scene_transfer_in_progress = true
	_scene_transfer_destination_path = normalized_path
	_scene_transfer_spawn_marker = destination_spawn_marker
	_movement_enabled_before_scene_transfer = _player_movement_enabled
	set_player_movement_enabled(false)
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	scene_transfer_started.emit(normalized_path, destination_spawn_marker)
	call_deferred("_perform_scene_transfer")
	return true


func _perform_scene_transfer() -> void:
	if not _scene_transfer_in_progress:
		return

	var callback := Callable(self, "_on_scene_transfer_scene_changed")
	if not get_tree().scene_changed.is_connected(callback):
		get_tree().scene_changed.connect(callback, CONNECT_ONE_SHOT)
	var error := get_tree().change_scene_to_file(_scene_transfer_destination_path)
	if error != OK:
		if get_tree().scene_changed.is_connected(callback):
			get_tree().scene_changed.disconnect(callback)
		_fail_scene_transfer(
			"Unable to open destination scene: %s" % error_string(error)
		)


func is_scene_transfer_in_progress() -> bool:
	return _scene_transfer_in_progress


## Begins the complete visual handoff into battle. The passed dictionary is
## deep-copied, enriched with implicit scene/transition data, and kept in
## temporary GameInstance state for the battle scene to consume.
func startBattle(battle_data: Dictionary = {}) -> bool:
	if _battle_start_in_progress:
		push_warning("GameInstance rejected startBattle: a battle start is already active.")
		return false
	_movement_enabled_before_battle = _player_movement_enabled
	var requested_scene_path := String(
		battle_data.get("battle_scene_path", DEFAULT_BATTLE_SCENE_PATH)
	).strip_edges()
	if requested_scene_path.is_empty():
		requested_scene_path = DEFAULT_BATTLE_SCENE_PATH
	if not ResourceLoader.exists(requested_scene_path):
		return _fail_battle_start(
			"Battle scene is missing: %s" % requested_scene_path
		)
	_battle_scene_path = requested_scene_path
	_capture_battle_return_player_state()

	set_player_movement_enabled(false)
	_pending_battle_data = _build_battle_start_data(battle_data)
	_record_standard_trainer_sight_from_launch(_pending_battle_data)
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

	return get_active_battle_data()


## Called only after BattleSystem has accepted and written back the initial
## server response (or by the network-free shared-scene preview path).
func reveal_battle_scene() -> void:
	if not _battle_start_in_progress or not _battle_scene_has_entered:
		return
	if _battle_template_reveal_finished:
		return
	if is_instance_valid(_battle_transition_ui):
		_battle_transition_ui.play_battle_transition_in(
			_on_battle_reveal_finished
		)
	else:
		_complete_battle_start_without_template()


func get_pending_battle_data() -> Dictionary:
	return _pending_battle_data.duplicate(true)


func get_active_battle_data() -> Dictionary:
	return _active_battle_data.duplicate(true)


func is_battle_start_in_progress() -> bool:
	return _battle_start_in_progress


func is_battle_return_in_progress() -> bool:
	return _battle_return_in_progress


func is_encounter_suppressed(encounter_id: String) -> bool:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id.is_empty() or normalized_id != _one_scene_suppression_id:
		return false
	if _battle_return_in_progress:
		return true
	var current_scene := get_tree().current_scene
	return (
		current_scene != null
		and current_scene.get_instance_id() == _suppression_scene_instance_id
	)


## Standard authored trainers force their first encounter only. This transient
## progression survives scene changes for the current play session; Stretchman
## opponents opt into Highly Aggro mode and deliberately ignore it.
func mark_standard_trainer_sight_encounter_consumed(encounter_id: String) -> void:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id.is_empty():
		return
	_consumed_standard_trainer_sight_encounters[normalized_id] = true


func has_consumed_standard_trainer_sight_encounter(encounter_id: String) -> bool:
	var normalized_id := encounter_id.strip_edges()
	return (
		not normalized_id.is_empty()
		and _consumed_standard_trainer_sight_encounters.has(normalized_id)
	)


## Clears process-only encounter history when the player explicitly creates a
## completely fresh profile. Persistent owners reset their own state separately.
func reset_profile_transient_progress() -> void:
	_one_scene_suppression_id = ""
	_suppression_scene_instance_id = 0
	_consumed_standard_trainer_sight_encounters.clear()


func _record_standard_trainer_sight_from_launch(battle_data: Dictionary) -> void:
	if String(battle_data.get("encounter_type", "")) != "trainer":
		return
	if (
		int(battle_data.get(
			"trainer_aggression_mode",
			TrainerBehavior.AggressionMode.STANDARD
		))
		== TrainerBehavior.AggressionMode.HIGHLY_AGGRO
	):
		return
	mark_standard_trainer_sight_encounter_consumed(
		String(battle_data.get("encounter_id", ""))
	)


## Covers the battlefield, clears launch data during the scene change, and
## reveals the authored overworld scene only after it reports ready.
func return_from_battle(
	return_scene_path := "",
	suppression_id := ""
) -> bool:
	if _battle_return_in_progress:
		return false
	var normalized_path := _resolve_battle_return_scene_path(
		String(return_scene_path)
	)
	if not ResourceLoader.exists(normalized_path):
		return false

	_battle_return_in_progress = true
	_battle_return_scene_path = normalized_path
	_one_scene_suppression_id = suppression_id.strip_edges()
	_suppression_scene_instance_id = 0
	set_player_movement_enabled(false)
	battle_return_started.emit(_one_scene_suppression_id)

	if is_instance_valid(_battle_transition_ui):
		_battle_transition_ui.set_dismiss_callback(
			_on_battle_return_transition_dismissed
		)
		if _battle_transition_ui.is_battle_transition_active():
			_change_to_return_scene()
		else:
			_battle_transition_ui.play_battle_transition_out(
				{"transition_title": "BATTLE COMPLETE", "transition_subtitle": "RETURNING"},
				_change_to_return_scene
			)
		return true

	_battle_transition_ui = UIManager.show_ui("")
	if not is_instance_valid(_battle_transition_ui):
		_battle_return_in_progress = false
		return false
	_battle_transition_ui.set_dismiss_callback(
		_on_battle_return_transition_dismissed
	)
	_battle_transition_ui.play_battle_transition_out(
		{"transition_title": "BATTLE COMPLETE", "transition_subtitle": "RETURNING"},
		_change_to_return_scene
	)
	return true


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
	prepared["battle_scene_path"] = _battle_scene_path
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
	var error := get_tree().change_scene_to_file(_battle_scene_path)
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
	_clear_battle_return_player_state()
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
	_clear_battle_return_player_state()
	set_player_movement_enabled(_movement_enabled_before_battle)
	if is_instance_valid(transition):
		transition.set_dismiss_callback(Callable())
		transition.close()
	push_error("GameInstance could not start battle: %s" % message)
	battle_start_failed.emit(message)
	return false


func _change_to_return_scene() -> void:
	if not _battle_return_in_progress:
		return
	var callback := Callable(self, "_on_return_scene_changed")
	if not get_tree().scene_changed.is_connected(callback):
		get_tree().scene_changed.connect(callback, CONNECT_ONE_SHOT)
	var error := get_tree().change_scene_to_file(_battle_return_scene_path)
	if error != OK:
		if get_tree().scene_changed.is_connected(callback):
			get_tree().scene_changed.disconnect(callback)
		_fail_battle_return(
			"Unable to open the overworld scene: %s" % error_string(error)
		)


func _on_return_scene_changed() -> void:
	if not _battle_return_in_progress:
		return
	var scene := get_tree().current_scene
	_pending_battle_data.clear()
	_active_battle_data.clear()
	_battle_start_in_progress = false
	_battle_scene_change_requested = false
	_battle_scene_has_entered = false
	_battle_template_reveal_finished = false
	_battle_local_intro_finished = false
	_restore_battle_return_player_state(scene)
	_suppression_scene_instance_id = scene.get_instance_id() if scene else 0
	set_player_movement_enabled(true)
	if is_instance_valid(_battle_transition_ui):
		_battle_transition_ui.play_battle_transition_in()
	else:
		_finish_battle_return()


func _on_battle_return_transition_dismissed() -> void:
	_battle_transition_ui = null
	_finish_battle_return()


func _finish_battle_return() -> void:
	if not _battle_return_in_progress:
		return
	_battle_return_in_progress = false
	_battle_return_scene_path = DEFAULT_RETURN_SCENE_PATH
	_clear_battle_return_player_state()
	battle_return_finished.emit()


func _fail_battle_return(message: String) -> void:
	var transition := _battle_transition_ui
	_battle_transition_ui = null
	_battle_return_in_progress = false
	_one_scene_suppression_id = ""
	_suppression_scene_instance_id = 0
	_clear_battle_return_player_state()
	if is_instance_valid(transition):
		transition.set_dismiss_callback(Callable())
		transition.close()
	push_error("GameInstance could not return from battle: %s" % message)
	battle_return_failed.emit(message)


func _on_any_scene_changed() -> void:
	if _one_scene_suppression_id.is_empty() or _battle_return_in_progress:
		return
	var scene := get_tree().current_scene
	if scene == null or scene.get_instance_id() != _suppression_scene_instance_id:
		_one_scene_suppression_id = ""
		_suppression_scene_instance_id = 0


func _on_scene_transfer_scene_changed() -> void:
	if not _scene_transfer_in_progress:
		return
	var destination_path := _scene_transfer_destination_path
	var spawn_marker_name := _scene_transfer_spawn_marker
	var movement_enabled_after_transfer := _movement_enabled_before_scene_transfer
	var marker_applied := false
	var scene := get_tree().current_scene

	if not spawn_marker_name.is_empty() and scene != null:
		var spawn_marker := _find_node_3d_by_name(scene, spawn_marker_name)
		var player := _find_player_character(scene)
		if spawn_marker != null and player != null:
			player.global_transform = spawn_marker.global_transform
			player.velocity = Vector3.ZERO
			marker_applied = true
		else:
			push_warning(
				(
					"Scene transfer reached %s but could not apply spawn marker '%s' "
					+ "because the marker or PlayerCharacter is missing."
				)
				% [destination_path, spawn_marker_name]
			)

	_clear_scene_transfer_state()
	set_player_movement_enabled(movement_enabled_after_transfer)
	scene_transfer_finished.emit(destination_path, spawn_marker_name, marker_applied)


func _find_node_3d_by_name(root: Node, target_name: StringName) -> Node3D:
	if root is Node3D and root.name == target_name:
		return root as Node3D
	for child: Node in root.get_children():
		var match := _find_node_3d_by_name(child, target_name)
		if match != null:
			return match
	return null


func _find_player_character(root: Node) -> PlayerCharacter:
	if root is PlayerCharacter:
		return root as PlayerCharacter
	for child: Node in root.get_children():
		var player := _find_player_character(child)
		if player != null:
			return player
	return null


func _capture_battle_return_player_state() -> void:
	_clear_battle_return_player_state()
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path.is_empty():
		return
	var player := _find_player_character(scene)
	if player == null:
		return

	_battle_return_source_scene_path = scene.scene_file_path
	_battle_return_player_transform = player.global_transform
	var visual := player.get_node_or_null(^"Visual") as Node3D
	_battle_return_player_visual_rotation = (
		visual.rotation if visual != null else Vector3.ZERO
	)
	_has_battle_return_player_state = true


func _resolve_battle_return_scene_path(requested_path: String) -> String:
	var normalized_path := requested_path.strip_edges()
	if not normalized_path.is_empty():
		return normalized_path

	for battle_data in [_active_battle_data, _pending_battle_data]:
		for field in ["return_scene_path", "source_scene_path"]:
			var candidate := String(battle_data.get(field, "")).strip_edges()
			if not candidate.is_empty():
				return candidate
	return DEFAULT_RETURN_SCENE_PATH


func _restore_battle_return_player_state(scene: Node) -> bool:
	if not _has_battle_return_player_state or scene == null:
		return false
	if (
		scene.scene_file_path != _battle_return_source_scene_path
		or _battle_return_scene_path != _battle_return_source_scene_path
	):
		return false

	var player := _find_player_character(scene)
	if player == null:
		push_warning(
			"Battle returned to %s without a PlayerCharacter to restore."
			% _battle_return_scene_path
		)
		return false
	player.global_transform = _battle_return_player_transform
	player.velocity = Vector3.ZERO
	var visual := player.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		visual.rotation = _battle_return_player_visual_rotation
	return true


func _clear_battle_return_player_state() -> void:
	_battle_return_source_scene_path = ""
	_battle_return_player_transform = Transform3D.IDENTITY
	_battle_return_player_visual_rotation = Vector3.ZERO
	_has_battle_return_player_state = false


func _reject_scene_transfer(message: String) -> bool:
	push_warning("GameInstance rejected scene transfer: %s" % message)
	scene_transfer_failed.emit(message)
	return false


func _fail_scene_transfer(message: String) -> bool:
	var movement_enabled_after_failure := _movement_enabled_before_scene_transfer
	_clear_scene_transfer_state()
	set_player_movement_enabled(movement_enabled_after_failure)
	push_error("GameInstance could not transfer scenes: %s" % message)
	scene_transfer_failed.emit(message)
	return false


func _clear_scene_transfer_state() -> void:
	_scene_transfer_in_progress = false
	_scene_transfer_destination_path = ""
	_scene_transfer_spawn_marker = &""
	_movement_enabled_before_scene_transfer = true
