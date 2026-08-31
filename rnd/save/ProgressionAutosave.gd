class_name RNDProgressionAutosave
extends Node

## RND persistence owner for player-owned progression. Collection changes are
## debounced to disk, while the most recent overworld scene and player pose are
## retained so battle and scene transitions cannot overwrite them with a scene
## that has no PlayerCharacter.

signal save_completed(save_path: String)
signal save_failed(message: String)
signal load_completed(save_path: String)
signal load_failed(message: String)

const SAVE_SCHEMA_VERSION := 3
const LEGACY_SAVE_SCHEMA_VERSION := 1
const STRETCH_SAVE_SCHEMA_VERSION := 2
const MOVE_LEARNING_SAVE_SCHEMA_VERSION := 3
const DEFAULT_SAVE_PATH := "user://pfr_rnd_progression.json"
const TEST_SCENE_PREFIXES: Array[String] = [
	"res://tests/",
	"res://rnd/tests/",
]

@export_range(0.1, 60.0, 0.1, "or_greater", "suffix:s")
var save_debounce_seconds := 0.35
@export_range(1.0, 300.0, 1.0, "or_greater", "suffix:s")
var location_autosave_seconds := 5.0

var save_path := DEFAULT_SAVE_PATH

var _save_debounce_timer: Timer
var _location_timer: Timer
var _automatic_io_enabled := false
var _is_loading := false
var _saved_world_state: Dictionary = {}
var _last_payload_fingerprint := ""


func _ready() -> void:
	_initialize_automatic_io.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _automatic_io_enabled:
		save_now()


## Immediately writes the current CollectionSystem snapshot and most recent
## overworld player pose. Public so RND callers can explicitly checkpoint a
## milestone in addition to the automatic hooks.
func save_now(force := false) -> bool:
	var payload := _build_payload()
	var fingerprint := JSON.stringify(payload)
	if not force and fingerprint == _last_payload_fingerprint:
		return true

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return _report_save_failure(
			"Could not open %s for writing: %s"
			% [save_path, error_string(FileAccess.get_open_error())]
		)

	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	_last_payload_fingerprint = fingerprint
	save_completed.emit(save_path)
	return true


## Loads and validates a saved collection atomically through CollectionSystem.
## Invalid data leaves the current in-memory collection untouched.
func load_now() -> bool:
	if not FileAccess.file_exists(save_path):
		return false

	var source := FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(source)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _report_load_failure("Progression save is not a JSON object: %s" % save_path)

	var payload: Dictionary = parsed
	var schema_version := int(payload.get("schema_version", -1))
	if schema_version < LEGACY_SAVE_SCHEMA_VERSION or schema_version > SAVE_SCHEMA_VERSION:
		return _report_load_failure(
			"Unsupported progression save schema in %s" % save_path
		)

	var collection_value: Variant = payload.get("collection")
	if typeof(collection_value) != TYPE_ARRAY:
		return _report_load_failure("Progression save has no valid collection array.")
	var stretch_value: Variant = payload.get("stretch", {})
	if schema_version >= STRETCH_SAVE_SCHEMA_VERSION:
		var stretch_error := StretchGoalSystem.validate_save_data(stretch_value)
		if not stretch_error.is_empty():
			return _report_load_failure(stretch_error)
	var move_learning_value: Variant = payload.get("move_learning", {"pending": []})
	if schema_version >= MOVE_LEARNING_SAVE_SCHEMA_VERSION:
		var move_learning_error := RNDMoveLearningSystem.validate_save_data(
			move_learning_value,
			collection_value as Array
		)
		if not move_learning_error.is_empty():
			return _report_load_failure(move_learning_error)

	RNDMoveLearningSystem.begin_save_restore()
	_is_loading = true
	var collection_loaded := CollectionSystem.load_save_data(collection_value as Array)
	if not collection_loaded:
		_is_loading = false
		RNDMoveLearningSystem.finish_save_restore()
		return _report_load_failure(
			"Collection save data was rejected: %s" % CollectionSystem.get_last_error()
		)
	if (
		schema_version >= STRETCH_SAVE_SCHEMA_VERSION
		and not StretchGoalSystem.load_save_data(stretch_value)
	):
		_is_loading = false
		RNDMoveLearningSystem.finish_save_restore()
		return _report_load_failure(
			"Stretch progression was rejected: %s" % StretchGoalSystem.get_last_error()
		)
	var loaded_move_learning := RNDMoveLearningSystem.load_save_data(
		move_learning_value
		if schema_version >= MOVE_LEARNING_SAVE_SCHEMA_VERSION
		else {"pending": []}
	)
	if not loaded_move_learning:
		_is_loading = false
		RNDMoveLearningSystem.finish_save_restore()
		return _report_load_failure("Move-learning progression was rejected.")
	RNDMoveLearningSystem.finish_save_restore()
	_is_loading = false

	var world_value: Variant = payload.get("world", {})
	_saved_world_state = (
		(world_value as Dictionary).duplicate(true)
		if typeof(world_value) == TYPE_DICTIONARY
		else {}
	)
	_restore_saved_world_state_for_current_scene()
	_last_payload_fingerprint = JSON.stringify(_build_payload())
	load_completed.emit(save_path)
	return true


## Queues one coalesced write. Repeated collection changes in a single battle
## response therefore produce one disk update.
func request_autosave() -> void:
	if not _automatic_io_enabled or _is_loading:
		return
	if not is_instance_valid(_save_debounce_timer):
		return
	_save_debounce_timer.start(save_debounce_seconds)


func is_automatic_io_enabled() -> bool:
	return _automatic_io_enabled


func _initialize_automatic_io() -> void:
	var scene := get_tree().current_scene
	var scene_path := scene.scene_file_path if scene != null else ""
	if _is_test_scene_path(scene_path):
		return

	_automatic_io_enabled = true
	_save_debounce_timer = Timer.new()
	_save_debounce_timer.name = "SaveDebounceTimer"
	_save_debounce_timer.one_shot = true
	_save_debounce_timer.timeout.connect(save_now)
	add_child(_save_debounce_timer)

	_location_timer = Timer.new()
	_location_timer.name = "LocationAutosaveTimer"
	_location_timer.wait_time = location_autosave_seconds
	_location_timer.timeout.connect(save_now)
	add_child(_location_timer)
	_location_timer.start()

	CollectionSystem.collection_changed.connect(_on_collection_changed)
	RNDMoveLearningSystem.progression_changed.connect(
		_on_move_learning_progression_changed
	)
	StretchGoalSystem.progression_changed.connect(_on_stretch_progression_changed)
	GameInstance.battle_starting.connect(_on_battle_starting)
	GameInstance.battle_return_finished.connect(_on_world_transition_finished)
	GameInstance.scene_transfer_started.connect(_on_scene_transfer_started)
	GameInstance.scene_transfer_finished.connect(_on_scene_transfer_finished)
	get_tree().scene_changed.connect(_on_scene_changed)

	if not load_now():
		save_now(true)


func _on_collection_changed() -> void:
	request_autosave()


func _on_stretch_progression_changed() -> void:
	request_autosave()


func _on_move_learning_progression_changed() -> void:
	request_autosave()


func _on_battle_starting(_battle_data: Dictionary) -> void:
	# This signal fires while the source overworld and its player still exist.
	save_now()


func _on_scene_transfer_started(
	_destination_scene_path: String,
	_destination_spawn_marker: StringName
) -> void:
	save_now()


func _on_scene_transfer_finished(
	_destination_scene_path: String,
	_destination_spawn_marker: StringName,
	_spawn_marker_applied: bool
) -> void:
	save_now()


func _on_world_transition_finished() -> void:
	save_now()


func _on_scene_changed() -> void:
	_restore_saved_world_state_for_current_scene.call_deferred()
	request_autosave()


func _build_payload() -> Dictionary:
	return {
		"schema_version": SAVE_SCHEMA_VERSION,
		"collection": CollectionSystem.get_save_data(),
		"move_learning": RNDMoveLearningSystem.get_save_data(),
		"stretch": StretchGoalSystem.get_save_data(),
		"world": _capture_current_world_state(),
	}


func _capture_current_world_state() -> Dictionary:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path.is_empty():
		return _saved_world_state.duplicate(true)

	var player := _find_player_character(scene)
	if player == null:
		# Battle scenes deliberately have no overworld player. Keep the source
		# pose instead of replacing it while battle HP/XP is autosaved.
		return _saved_world_state.duplicate(true)

	var visual := player.get_node_or_null(^"Visual") as Node3D
	_saved_world_state = {
		"scene_path": scene.scene_file_path,
		"player_position": _vector_to_array(player.global_position),
		"player_rotation": _vector_to_array(player.global_rotation),
		"visual_rotation": _vector_to_array(
			visual.rotation if visual != null else Vector3.ZERO
		),
	}
	return _saved_world_state.duplicate(true)


func _restore_saved_world_state_for_current_scene() -> bool:
	if _saved_world_state.is_empty():
		return false
	var scene := get_tree().current_scene
	if scene == null:
		return false
	if String(_saved_world_state.get("scene_path", "")) != scene.scene_file_path:
		return false

	var position_value: Variant = _saved_world_state.get("player_position")
	var rotation_value: Variant = _saved_world_state.get("player_rotation")
	var visual_rotation_value: Variant = _saved_world_state.get("visual_rotation")
	if (
		not _is_vector_array(position_value)
		or not _is_vector_array(rotation_value)
		or not _is_vector_array(visual_rotation_value)
	):
		return false

	var player := _find_player_character(scene)
	if player == null:
		return false
	player.global_position = _array_to_vector(position_value as Array)
	player.global_rotation = _array_to_vector(rotation_value as Array)
	player.velocity = Vector3.ZERO
	var visual := player.get_node_or_null(^"Visual") as Node3D
	if visual != null:
		visual.rotation = _array_to_vector(visual_rotation_value as Array)
	return true


func _find_player_character(root: Node) -> PlayerCharacter:
	if root is PlayerCharacter:
		return root as PlayerCharacter
	for child: Node in root.get_children():
		var player := _find_player_character(child)
		if player != null:
			return player
	return null


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _array_to_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _is_vector_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return false
	for component: Variant in value as Array:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]:
			return false
	return true


func _is_test_scene_path(scene_path: String) -> bool:
	for prefix in TEST_SCENE_PREFIXES:
		if scene_path.begins_with(prefix):
			return true
	return false


func _report_save_failure(message: String) -> bool:
	push_error("RND progression autosave failed: %s" % message)
	save_failed.emit(message)
	return false


func _report_load_failure(message: String) -> bool:
	push_error("RND progression load failed: %s" % message)
	load_failed.emit(message)
	return false
