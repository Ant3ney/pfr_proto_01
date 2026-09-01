class_name RNDProgressionAutosave
extends Node

## RND persistence owner for player-owned progression. Collection changes are
## debounced to disk, while the most recent overworld scene and player pose are
## retained so battle and scene transitions cannot overwrite them with a scene
## that has no PlayerCharacter. Schema 5 also records per-section wall clocks
## so optional cloud sync can resolve changes made while a device was offline.

signal save_completed(save_path: String)
signal save_failed(message: String)
signal load_completed(source_label: String)
signal load_failed(message: String)
signal progress_reset_started
signal progress_reset_completed(starter_pokemon_id: int)

const SAVE_SCHEMA_VERSION := 5
const LEGACY_SAVE_SCHEMA_VERSION := 1
const STRETCH_SAVE_SCHEMA_VERSION := 2
const MOVE_LEARNING_SAVE_SCHEMA_VERSION := 3
const STARTER_PROFILE_SAVE_SCHEMA_VERSION := 4
const TIMESTAMPED_SAVE_SCHEMA_VERSION := 5
const SAVE_SECTIONS: Array[String] = [
	"profile",
	"collection",
	"move_learning",
	"stretch",
	"world",
]
const DEFAULT_SAVE_PATH := "user://pfr_rnd_progression.json"
const MAIN_SCENE_PATH := "res://demo/primary_development_enviroment.tscn"
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
var _profile_initialization_pending := false
var _reset_in_progress := false
var _explicit_reset_pending := false
var _starter_pokemon_id := 0
var _saved_world_state: Dictionary = {}
var _last_payload_fingerprint := ""
var _last_saved_at_ms := 0
var _section_updated_at_ms: Dictionary = {}
var _last_section_fingerprints: Dictionary = {}


func _ready() -> void:
	if not RNDStarterSelectionSystem.starter_selected.is_connected(
		_on_starter_selected
	):
		RNDStarterSelectionSystem.starter_selected.connect(_on_starter_selected)
	_initialize_automatic_io.call_deferred()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		and _automatic_io_enabled
		and not _profile_initialization_pending
		and not _reset_in_progress
	):
		save_now()


## Immediately writes the current CollectionSystem snapshot and most recent
## overworld player pose. Public so RND callers can explicitly checkpoint a
## milestone in addition to the automatic hooks.
func save_now(force := false) -> bool:
	if _profile_initialization_pending or _reset_in_progress:
		return false
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

	return _apply_payload(parsed as Dictionary, save_path)


## Returns the same validated, timestamped snapshot written to local storage.
## The Save ID is deliberately not part of this payload.
func get_save_payload() -> Dictionary:
	if _profile_initialization_pending or _reset_in_progress:
		return {}
	return _build_payload().duplicate(true)


## Applies an already-resolved cloud payload through the same validators used
## for disk loading, then immediately checkpoints the accepted result locally.
func apply_cloud_payload(payload: Dictionary) -> bool:
	if not _apply_payload(payload, "cloud sync"):
		return false
	return save_now(true)


func _apply_payload(payload: Dictionary, source_label: String) -> bool:
	var schema_version := int(payload.get("schema_version", -1))
	if schema_version < LEGACY_SAVE_SCHEMA_VERSION or schema_version > SAVE_SCHEMA_VERSION:
		return _report_load_failure(
			"Unsupported progression save schema from %s." % source_label
		)

	var collection_value: Variant = payload.get("collection")
	if typeof(collection_value) != TYPE_ARRAY:
		return _report_load_failure("Progression save has no valid collection array.")
	var loaded_starter_pokemon_id := 0
	if schema_version >= STARTER_PROFILE_SAVE_SCHEMA_VERSION:
		var profile_error := _validate_profile_data(
			payload.get("profile"),
			collection_value as Array
		)
		if not profile_error.is_empty():
			return _report_load_failure(profile_error)
		loaded_starter_pokemon_id = int(
			(payload.get("profile") as Dictionary).get("starter_pokemon_id", 0)
		)
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
	if schema_version >= TIMESTAMPED_SAVE_SCHEMA_VERSION:
		var save_meta_error := _validate_save_meta(payload.get("save_meta"))
		if not save_meta_error.is_empty():
			return _report_load_failure(save_meta_error)

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
	_starter_pokemon_id = loaded_starter_pokemon_id
	_profile_initialization_pending = false
	_reset_in_progress = false
	_explicit_reset_pending = false
	RNDStarterSelectionSystem.mark_profile_loaded(_starter_pokemon_id)

	var world_value: Variant = payload.get("world", {})
	_saved_world_state = (
		(world_value as Dictionary).duplicate(true)
		if typeof(world_value) == TYPE_DICTIONARY
		else {}
	)
	_restore_saved_world_state_for_current_scene()
	if schema_version >= TIMESTAMPED_SAVE_SCHEMA_VERSION:
		_load_save_meta(payload.get("save_meta") as Dictionary)
	else:
		_initialize_save_meta(_unix_time_ms())
	var current_payload := _build_payload(false)
	_last_payload_fingerprint = JSON.stringify(current_payload)
	load_completed.emit(source_label)
	return true


## Queues one coalesced write. Repeated collection changes in a single battle
## response therefore produce one disk update.
func request_autosave() -> void:
	if (
		not _automatic_io_enabled
		or _is_loading
		or _profile_initialization_pending
		or _reset_in_progress
	):
		return
	if not is_instance_valid(_save_debounce_timer):
		return
	_save_debounce_timer.start(save_debounce_seconds)


func is_automatic_io_enabled() -> bool:
	return _automatic_io_enabled


func is_profile_initialization_pending() -> bool:
	return _profile_initialization_pending


func get_starter_pokemon_id() -> int:
	return _starter_pokemon_id


## Erases the save file and every in-memory progression owner after the player
## completes the menu's destructive confirmation sequence. Normal gameplay
## returns to the main scene before the mandatory starter picker is shown.
func reset_all_progress(return_to_main_scene := true) -> bool:
	if (
		_reset_in_progress
		or BattleSystem.get_state() != BattleSystem.State.IDLE
		or GameInstance.is_battle_start_in_progress()
		or GameInstance.is_battle_return_in_progress()
		or GameInstance.is_scene_transfer_in_progress()
	):
		return false
	if FileAccess.file_exists(save_path):
		var remove_error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(save_path)
		)
		if remove_error != OK:
			return _report_save_failure(
				"Could not erase %s: %s" % [save_path, error_string(remove_error)]
			)

	progress_reset_started.emit()
	_explicit_reset_pending = true
	_reset_in_progress = true
	_prepare_fresh_profile_state()

	var scene := get_tree().current_scene
	var current_scene_path := scene.scene_file_path if scene != null else ""
	if (
		return_to_main_scene
		and current_scene_path != MAIN_SCENE_PATH
		and GameInstance.transfer_to_scene(MAIN_SCENE_PATH)
	):
		return true
	_finish_fresh_profile_handoff.call_deferred()
	return true


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
	GameInstance.scene_transfer_failed.connect(_on_scene_transfer_failed)
	get_tree().scene_changed.connect(_on_scene_changed)

	if not load_now():
		_prepare_fresh_profile_state()
		_finish_fresh_profile_handoff.call_deferred()


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
	if _reset_in_progress:
		return
	save_now()


func _on_scene_transfer_finished(
	_destination_scene_path: String,
	_destination_spawn_marker: StringName,
	_spawn_marker_applied: bool
) -> void:
	if _reset_in_progress:
		_finish_fresh_profile_handoff.call_deferred()
		return
	save_now()


func _on_scene_transfer_failed(_message: String) -> void:
	if _reset_in_progress:
		_finish_fresh_profile_handoff.call_deferred()


func _on_world_transition_finished() -> void:
	save_now()


func _on_scene_changed() -> void:
	if _reset_in_progress or _profile_initialization_pending:
		return
	_restore_saved_world_state_for_current_scene.call_deferred()
	request_autosave()


func _build_payload(update_timestamps := true) -> Dictionary:
	var payload := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"profile": {
			"starter_pokemon_id": _starter_pokemon_id,
		},
		"collection": CollectionSystem.get_save_data(),
		"move_learning": RNDMoveLearningSystem.get_save_data(),
		"stretch": StretchGoalSystem.get_save_data(),
		"world": _capture_current_world_state(),
	}
	var section_fingerprints: Dictionary = {}
	for section in SAVE_SECTIONS:
		section_fingerprints[section] = JSON.stringify(payload[section])

	if update_timestamps:
		var content_changed := false
		var timestamp := maxi(_unix_time_ms(), _last_saved_at_ms + 1)
		for section in SAVE_SECTIONS:
			if (
				not _last_section_fingerprints.has(section)
				or String(_last_section_fingerprints[section])
				!= String(section_fingerprints[section])
			):
				_section_updated_at_ms[section] = timestamp
				content_changed = true
		if content_changed or _last_saved_at_ms <= 0:
			_last_saved_at_ms = timestamp
		for section in SAVE_SECTIONS:
			if not _section_updated_at_ms.has(section):
				_section_updated_at_ms[section] = timestamp
	else:
		for section in SAVE_SECTIONS:
			if not _section_updated_at_ms.has(section):
				_section_updated_at_ms[section] = _last_saved_at_ms

	_last_section_fingerprints = section_fingerprints
	payload["save_meta"] = {
		"saved_at_ms": _last_saved_at_ms,
		"section_updated_at_ms": _section_updated_at_ms.duplicate(true),
	}
	return payload


func _prepare_fresh_profile_state() -> void:
	_profile_initialization_pending = true
	_starter_pokemon_id = 0
	_is_loading = true
	RNDMoveLearningSystem.begin_save_restore()
	CollectionSystem.clear_collection()
	RNDMoveLearningSystem.load_save_data({"pending": []})
	RNDMoveLearningSystem.finish_save_restore()
	StretchGoalSystem.reset_progress()
	GameInstance.reset_profile_transient_progress()
	_is_loading = false
	_saved_world_state.clear()
	_last_payload_fingerprint = ""
	_last_saved_at_ms = 0
	_section_updated_at_ms.clear()
	_last_section_fingerprints.clear()
	RNDStarterSelectionSystem.prepare_new_profile()


func _finish_fresh_profile_handoff() -> void:
	if not _profile_initialization_pending:
		return
	_reset_in_progress = false
	RNDStarterSelectionSystem.show_selection()


func _on_starter_selected(pokemon_id: int, _pcl: Dictionary) -> void:
	if not _profile_initialization_pending:
		return
	_starter_pokemon_id = pokemon_id
	_profile_initialization_pending = false
	_reset_in_progress = false
	_saved_world_state.clear()
	_last_payload_fingerprint = ""
	save_now(true)
	if _explicit_reset_pending:
		_explicit_reset_pending = false
		progress_reset_completed.emit(pokemon_id)


func _validate_profile_data(value: Variant, collection_data: Array) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "Progression save has no valid profile object."
	var starter_value: Variant = (value as Dictionary).get("starter_pokemon_id")
	if not _is_integer_value(starter_value):
		return "Progression profile has an invalid starter ID."
	var starter_pokemon_id := int(starter_value)
	if (
		starter_pokemon_id != 0
		and starter_pokemon_id
		not in RNDStarterSelectionSystem.STARTER_POKEMON_IDS
	):
		return "Progression profile references an unknown starter."
	if collection_data.is_empty():
		return "An initialized progression profile cannot have an empty collection."
	return ""


func _validate_save_meta(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "Progression save has no valid save metadata object."
	var save_meta := value as Dictionary
	var saved_at_value: Variant = save_meta.get("saved_at_ms")
	if not _is_non_negative_integer_value(saved_at_value):
		return "Progression save has an invalid save timestamp."
	var sections_value: Variant = save_meta.get("section_updated_at_ms")
	if typeof(sections_value) != TYPE_DICTIONARY:
		return "Progression save has no valid section timestamp map."
	var section_timestamps := sections_value as Dictionary
	for section in SAVE_SECTIONS:
		if not _is_non_negative_integer_value(section_timestamps.get(section)):
			return "Progression save has an invalid %s timestamp." % section
	return ""


func _load_save_meta(save_meta: Dictionary) -> void:
	_last_saved_at_ms = int(save_meta.get("saved_at_ms", 0))
	_section_updated_at_ms = (
		(save_meta.get("section_updated_at_ms", {}) as Dictionary).duplicate(true)
	)
	_last_section_fingerprints.clear()


func _initialize_save_meta(timestamp: int) -> void:
	_last_saved_at_ms = maxi(timestamp, 0)
	_section_updated_at_ms.clear()
	for section in SAVE_SECTIONS:
		_section_updated_at_ms[section] = _last_saved_at_ms
	_last_section_fingerprints.clear()


func _unix_time_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


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


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and is_equal_approx(float(value), float(int(value)))
	)


func _is_non_negative_integer_value(value: Variant) -> bool:
	return _is_integer_value(value) and int(value) >= 0


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
