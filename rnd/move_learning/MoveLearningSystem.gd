extends Node

## Observes real collection level changes, queues PokeAPI level-up moves, and
## owns the blocking replace-or-keep flow. Equipped moves remain owned by the
## existing CollectionSystem battleProfile.

signal progression_changed
signal move_learning_queued(request: Dictionary)
signal move_learning_resolved(result: Dictionary)

const MAX_PENDING_REQUESTS := 512
const UI_SCENE: PackedScene = preload(
	"res://rnd/move_learning/move_learning_ui.tscn"
)
const Catalog := preload("res://rnd/move_learning/MoveLearnsetCatalog.gd")
const SpeciesMapping := preload("res://battle/system/BattleSpeciesMapping.gd")

var _known_levels_by_pcl_id: Dictionary = {}
var _pending_requests: Array[Dictionary] = []
var _active_ui: RNDMoveLearningUI
var _presenting := false
var _tracking_suspended := false
var _automatic_presentation_enabled := true
var _automatic_presentation_scheduled := false
var _owns_movement_lock := false
var _test_process := false


func _ready() -> void:
	_test_process = _is_test_process_command_line()
	_snapshot_current_levels()
	CollectionSystem.collection_changed.connect(_on_collection_changed)
	BattleSystem.state_changed.connect(_on_battle_state_changed)
	GameInstance.battle_return_finished.connect(_on_safe_presentation_point)
	GameInstance.scene_transfer_finished.connect(_on_scene_transfer_finished)


func has_pending_requests() -> bool:
	return not _pending_requests.is_empty()


func has_pending_for_member(pcl_id: String) -> bool:
	return _find_pending_index(pcl_id) >= 0


func get_pending_requests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for request in _pending_requests:
		result.append(request.duplicate(true))
	return result


## Called by BattleScene after it presents the corresponding XP message. This
## keeps learning inside the PRESENTING phase, before the next server request.
func present_pending_for_member(pcl_id: String) -> bool:
	return await _present_pending(pcl_id)


func present_all_pending() -> bool:
	return await _present_pending("")


## Resolves the first queued request without presentation. Used by focused
## tests and by tools that deliberately provide their own R&D presentation.
func resolve_next_pending(replacement_index := -1) -> Dictionary:
	if _pending_requests.is_empty():
		return {}
	return _resolve_request_at(0, replacement_index)


func get_save_data() -> Dictionary:
	var pending: Array[Dictionary] = []
	for request in _pending_requests:
		pending.append({
			"pcl_id": String(request.get("pclID", "")),
			"pokemon_id": int(request.get("pokemonId", 0)),
			"learned_level": int(request.get("learnedLevel", 0)),
			"move_id": String(request.get("moveId", "")),
		})
	return {"pending": pending}


func validate_save_data(value: Variant, collection_data: Array) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "Move-learning progression is not an object."
	var pending_value: Variant = (value as Dictionary).get("pending", [])
	if typeof(pending_value) != TYPE_ARRAY:
		return "Move-learning progression has an invalid pending list."
	var pending := pending_value as Array
	if pending.size() > MAX_PENDING_REQUESTS:
		return "Move-learning progression has too many pending choices."

	var collection_by_id: Dictionary = {}
	for pcl_value: Variant in collection_data:
		if typeof(pcl_value) != TYPE_DICTIONARY:
			continue
		var pcl := pcl_value as Dictionary
		collection_by_id[String(pcl.get("pclID", ""))] = pcl
	var seen: Dictionary = {}
	for request_value: Variant in pending:
		if typeof(request_value) != TYPE_DICTIONARY:
			return "Move-learning progression contains a non-object choice."
		var request := request_value as Dictionary
		if (
			typeof(request.get("pcl_id")) != TYPE_STRING
			or not _is_integer_value(request.get("pokemon_id"))
			or not _is_integer_value(request.get("learned_level"))
			or typeof(request.get("move_id")) != TYPE_STRING
		):
			return "Move-learning progression contains invalid choice fields."
		var pcl_id := String(request.get("pcl_id", ""))
		var pokemon_id := int(request.get("pokemon_id", 0))
		var learned_level := int(request.get("learned_level", 0))
		var move_id := String(request.get("move_id", ""))
		var pcl_value: Variant = collection_by_id.get(pcl_id)
		if pcl_id.is_empty() or typeof(pcl_value) != TYPE_DICTIONARY:
			return "Move-learning progression references an unknown Pokémon."
		var pcl := pcl_value as Dictionary
		var stats_value: Variant = pcl.get("instanceStats")
		if (
			int(pcl.get("pokemonId", 0)) != pokemon_id
			or typeof(pcl.get("battleProfile")) != TYPE_DICTIONARY
			or typeof(stats_value) != TYPE_DICTIONARY
			or learned_level < 1
			or learned_level > int((stats_value as Dictionary).get("level", 0))
			or not _catalog_has_move(pokemon_id, learned_level, move_id)
		):
			return "Move-learning progression contains an impossible choice."
		var request_key := "%s:%d:%s" % [pcl_id, learned_level, move_id]
		if seen.has(request_key):
			return "Move-learning progression repeats a pending choice."
		seen[request_key] = true
	return ""


func load_save_data(value: Variant) -> bool:
	var collection_data := CollectionSystem.get_save_data()
	var validation_error := validate_save_data(value, collection_data)
	if not validation_error.is_empty():
		return false
	_pending_requests.clear()
	for request_value: Variant in (value as Dictionary).get("pending", []) as Array:
		var saved := request_value as Dictionary
		var pcl_id := String(saved.get("pcl_id", ""))
		var pokemon_id := int(saved.get("pokemon_id", 0))
		var learned_level := int(saved.get("learned_level", 0))
		var move_id := String(saved.get("move_id", ""))
		var pcl := CollectionSystem.get_pcl(pcl_id)
		var profile := CollectionSystem.get_battle_profile(pcl_id)
		_pending_requests.append(_build_request(
			pcl_id,
			pokemon_id,
			String(profile.get("species", "Pokémon")),
			int((pcl.get("instanceStats", {}) as Dictionary).get("level", learned_level)),
			learned_level,
			move_id
		))
	return true


## ProgressionAutosave brackets collection replacement with these calls so a
## load cannot look like a new level gain before its saved queue is restored.
func begin_save_restore() -> void:
	_tracking_suspended = true


func finish_save_restore() -> void:
	_snapshot_current_levels()
	_tracking_suspended = false
	_prune_invalid_pending_requests()
	_try_present_pending_automatically()


func set_automatic_presentation_enabled_for_testing(enabled: bool) -> void:
	_automatic_presentation_enabled = enabled
	if enabled:
		_try_present_pending_automatically()


func reset_for_testing() -> void:
	_pending_requests.clear()
	_snapshot_current_levels()
	if is_instance_valid(_active_ui):
		_active_ui.queue_free()
	_active_ui = null
	_presenting = false
	_tracking_suspended = false
	_automatic_presentation_scheduled = false
	_release_movement_lock()


func _on_collection_changed() -> void:
	if _tracking_suspended:
		return
	var current_levels: Dictionary = {}
	var queued_any := false
	for pcl in CollectionSystem.get_collection():
		var pcl_id := String(pcl.get("pclID", ""))
		var stats := pcl.get("instanceStats", {}) as Dictionary
		var current_level := int(stats.get("level", 1))
		current_levels[pcl_id] = current_level
		if _known_levels_by_pcl_id.has(pcl_id):
			var previous_level := int(_known_levels_by_pcl_id[pcl_id])
			if current_level > previous_level:
				queued_any = (
					_queue_level_up_moves(pcl, previous_level, current_level)
					or queued_any
				)
	_known_levels_by_pcl_id = current_levels
	var pruned_any := _prune_invalid_pending_requests()
	if queued_any or pruned_any:
		progression_changed.emit()
	_try_present_pending_automatically()


func _queue_level_up_moves(
	pcl: Dictionary,
	previous_level: int,
	current_level: int
) -> bool:
	var profile_value: Variant = pcl.get("battleProfile")
	if typeof(profile_value) != TYPE_DICTIONARY:
		return false
	var profile := profile_value as Dictionary
	var equipped_moves: Array = profile.get("moves", []) as Array
	var pcl_id := String(pcl.get("pclID", ""))
	var pokemon_id := int(pcl.get("pokemonId", 0))
	var pokemon_name := String(profile.get("species", "Pokémon"))
	var queued_any := false
	for learned_move in Catalog.get_moves_learned_between(
		pokemon_id,
		previous_level,
		current_level
	):
		var move_id := String(learned_move.get("moveId", ""))
		if move_id in equipped_moves:
			continue
		if _pending_requests.size() >= MAX_PENDING_REQUESTS:
			push_error("R&D move-learning queue reached its safety limit.")
			break
		var learned_level := int(learned_move.get("level", current_level))
		var request_key := "%s:%d:%s" % [pcl_id, learned_level, move_id]
		if _has_request_key(request_key):
			continue
		var request := _build_request(
			pcl_id,
			pokemon_id,
			pokemon_name,
			current_level,
			learned_level,
			move_id
		)
		_pending_requests.append(request)
		queued_any = true
		move_learning_queued.emit(request.duplicate(true))
	return queued_any


func _build_request(
	pcl_id: String,
	pokemon_id: int,
	pokemon_name: String,
	current_level: int,
	learned_level: int,
	move_id: String
) -> Dictionary:
	return {
		"pclID": pcl_id,
		"pokemonId": pokemon_id,
		"pokemonName": pokemon_name,
		"currentLevel": current_level,
		"learnedLevel": learned_level,
		"moveId": move_id,
		"moveName": Catalog.get_move_name(move_id),
		"moveType": SpeciesMapping.get_move_type(move_id),
	}


func _resolve_request_at(request_index: int, replacement_index: int) -> Dictionary:
	if request_index < 0 or request_index >= _pending_requests.size():
		return {}
	var request := _pending_requests[request_index].duplicate(true)
	var pcl_id := String(request.get("pclID", ""))
	var profile := CollectionSystem.get_battle_profile(pcl_id)
	if profile.is_empty():
		return _finish_request(request_index, request, {"status": "discarded"})
	var equipped_moves: Array = profile.get("moves", []) as Array
	var move_id := String(request.get("moveId", ""))
	if move_id in equipped_moves:
		return _finish_request(request_index, request, {"status": "already_known"})

	if equipped_moves.size() < 4:
		var appended := equipped_moves.duplicate()
		appended.append(move_id)
		if not CollectionSystem.set_equipped_moves(pcl_id, appended):
			return {"ok": false, "status": "failed", "request": request}
		return _finish_request(request_index, request, {"status": "learned"})

	if replacement_index < 0:
		return _finish_request(request_index, request, {"status": "skipped"})
	if replacement_index >= equipped_moves.size():
		return {"ok": false, "status": "invalid_choice", "request": request}
	var forgotten_move_id := String(equipped_moves[replacement_index])
	var replaced := equipped_moves.duplicate()
	replaced[replacement_index] = move_id
	if not CollectionSystem.set_equipped_moves(pcl_id, replaced):
		return {"ok": false, "status": "failed", "request": request}
	return _finish_request(request_index, request, {
		"status": "replaced",
		"forgottenMoveId": forgotten_move_id,
		"forgottenMoveName": Catalog.get_move_name(forgotten_move_id),
	})


func _finish_request(
	request_index: int,
	request: Dictionary,
	details: Dictionary
) -> Dictionary:
	_pending_requests.remove_at(request_index)
	var result := request.duplicate(true)
	for key: Variant in details:
		result[key] = details[key]
	result["ok"] = true
	progression_changed.emit()
	move_learning_resolved.emit(result.duplicate(true))
	return result


func _present_pending(pcl_id: String) -> bool:
	if _presenting:
		return false
	if _find_pending_index(pcl_id) < 0:
		return true
	_active_ui = _ensure_ui()
	if not is_instance_valid(_active_ui):
		push_error("R&D move-learning UI could not be created.")
		return false

	_presenting = true
	_acquire_movement_lock()
	while true:
		var request_index := _find_pending_index(pcl_id)
		if request_index < 0 or not is_instance_valid(_active_ui):
			break
		var request := _presentation_request(_pending_requests[request_index])
		var current_moves: Array = request.get("currentMoves", []) as Array
		var move_id := String(request.get("moveId", ""))
		var already_known := false
		for move_value: Variant in current_moves:
			if (
				typeof(move_value) == TYPE_DICTIONARY
				and String((move_value as Dictionary).get("moveId", "")) == move_id
			):
				already_known = true
				break

		var result: Dictionary
		if current_moves.size() < 4 or already_known:
			result = _resolve_request_at(request_index, -1)
		else:
			_active_ui.show_replacement(request)
			var selection_value: Variant = await _active_ui.replacement_selected
			var replacement_index := (
				int(selection_value[0])
				if typeof(selection_value) == TYPE_ARRAY
				else int(selection_value)
			)
			result = _resolve_request_at(request_index, replacement_index)
		if not bool(result.get("ok", false)):
			push_error("R&D move-learning choice could not be applied.")
			break
		_active_ui.show_result(request, result)
		await _active_ui.continued

	if is_instance_valid(_active_ui):
		_active_ui.hide_ui()
	_release_movement_lock()
	_presenting = false
	_try_present_pending_automatically()
	return true


func _presentation_request(request: Dictionary) -> Dictionary:
	var result := request.duplicate(true)
	var pcl_id := String(request.get("pclID", ""))
	var pcl := CollectionSystem.get_pcl(pcl_id)
	if not pcl.is_empty():
		result["currentLevel"] = int(
			(pcl.get("instanceStats", {}) as Dictionary).get(
				"level",
				request.get("currentLevel", 1)
			)
		)
	var profile := CollectionSystem.get_battle_profile(pcl_id)
	var current_moves: Array[Dictionary] = []
	for move_value: Variant in profile.get("moves", []) as Array:
		var move_id := String(move_value)
		current_moves.append({
			"moveId": move_id,
			"name": Catalog.get_move_name(move_id),
			"type": SpeciesMapping.get_move_type(move_id),
		})
	result["currentMoves"] = current_moves
	return result


func _ensure_ui() -> RNDMoveLearningUI:
	if is_instance_valid(_active_ui):
		return _active_ui
	_active_ui = UI_SCENE.instantiate() as RNDMoveLearningUI
	if _active_ui != null:
		add_child(_active_ui)
	return _active_ui


func _find_pending_index(pcl_id: String) -> int:
	for request_index in _pending_requests.size():
		if (
			pcl_id.is_empty()
			or String(_pending_requests[request_index].get("pclID", "")) == pcl_id
		):
			return request_index
	return -1


func _has_request_key(request_key: String) -> bool:
	for request in _pending_requests:
		if (
			"%s:%d:%s" % [
				String(request.get("pclID", "")),
				int(request.get("learnedLevel", 0)),
				String(request.get("moveId", "")),
			]
			== request_key
		):
			return true
	return false


func _prune_invalid_pending_requests() -> bool:
	var pruned_any := false
	for request_index in range(_pending_requests.size() - 1, -1, -1):
		var request := _pending_requests[request_index]
		var pcl := CollectionSystem.get_pcl(String(request.get("pclID", "")))
		var stats := pcl.get("instanceStats", {}) as Dictionary
		if (
			pcl.is_empty()
			or int(pcl.get("pokemonId", 0)) != int(request.get("pokemonId", 0))
			or int(stats.get("level", 0)) < int(request.get("learnedLevel", 0))
		):
			_pending_requests.remove_at(request_index)
			pruned_any = true
	return pruned_any


func _snapshot_current_levels() -> void:
	_known_levels_by_pcl_id.clear()
	for pcl in CollectionSystem.get_collection():
		_known_levels_by_pcl_id[String(pcl.get("pclID", ""))] = int(
			(pcl.get("instanceStats", {}) as Dictionary).get("level", 1)
		)


func _try_present_pending_automatically() -> void:
	if (
		not _automatic_presentation_enabled
		or _test_process
		or _tracking_suspended
		or _presenting
		or _pending_requests.is_empty()
		or _automatic_presentation_scheduled
		or BattleSystem.get_state() != BattleSystem.State.IDLE
		or GameInstance.is_battle_start_in_progress()
		or GameInstance.is_battle_return_in_progress()
		or GameInstance.is_scene_transfer_in_progress()
	):
		return
	_automatic_presentation_scheduled = true
	_present_automatically.call_deferred()


func _present_automatically() -> void:
	_automatic_presentation_scheduled = false
	if (
		not _automatic_presentation_enabled
		or _test_process
		or _tracking_suspended
		or _presenting
		or _pending_requests.is_empty()
		or BattleSystem.get_state() != BattleSystem.State.IDLE
	):
		return
	await present_all_pending()


func _on_battle_state_changed(_state: int) -> void:
	_try_present_pending_automatically()


func _on_safe_presentation_point() -> void:
	_try_present_pending_automatically()


func _on_scene_transfer_finished(
	_destination_scene_path: String,
	_destination_spawn_marker: StringName,
	_spawn_marker_applied: bool
) -> void:
	_try_present_pending_automatically()


func _acquire_movement_lock() -> void:
	_owns_movement_lock = GameInstance.is_player_movement_enabled()
	if _owns_movement_lock:
		GameInstance.set_player_movement_enabled(false)
		PlayerController.set_floating_joystick_input(Vector2.ZERO)


func _release_movement_lock() -> void:
	if _owns_movement_lock:
		GameInstance.set_player_movement_enabled(true)
	_owns_movement_lock = false


func _catalog_has_move(pokemon_id: int, learned_level: int, move_id: String) -> bool:
	for move in Catalog.get_level_up_moves(pokemon_id):
		if (
			int(move.get("level", 0)) == learned_level
			and String(move.get("moveId", "")) == move_id
		):
			return true
	return false


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and is_equal_approx(float(value), float(int(value)))
	)


func _is_test_process_command_line() -> bool:
	for argument in OS.get_cmdline_args():
		var value := String(argument)
		if "res://tests/" in value or "res://rnd/tests/" in value:
			return true
	return false
