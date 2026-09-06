class_name ProgressionAutosaveService
extends Node

## Persistence owner for player-owned progression. Domain changes are
## debounced to disk, while the most recent overworld scene and player pose are
## retained so battle and scene transitions cannot overwrite them with a scene
## that has no PlayerCharacter. Schema 6 records independent economy,
## inventory, and challenge sections while continuing to migrate schemas 1–5.

signal save_completed(save_path: String)
signal save_failed(message: String)
signal load_completed(source_label: String)
signal load_failed(message: String)
signal progress_reset_started
signal progress_reset_completed(starter_pokemon_id: int)

const SAVE_SCHEMA_VERSION := 6
const LEGACY_SAVE_SCHEMA_VERSION := 1
const STRETCH_SAVE_SCHEMA_VERSION := 2
const MOVE_LEARNING_SAVE_SCHEMA_VERSION := 3
const STARTER_PROFILE_SAVE_SCHEMA_VERSION := 4
const TIMESTAMPED_SAVE_SCHEMA_VERSION := 5
const DOMAIN_SPLIT_SAVE_SCHEMA_VERSION := 6
const MAX_JSON_TRANSFER_BYTES := 2 * 1024 * 1024
const SAVE_SECTIONS: Array[String] = [
	"profile",
	"collection",
	"move_learning",
	"economy",
	"inventory",
	"challenge_progression",
	"world",
]
const DEFAULT_SAVE_PATH := "user://pfr_rnd_progression.json"
const MAIN_SCENE_PATH := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
const TEST_SCENE_PREFIXES: Array[String] = [
	"res://tests/",
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
var _last_error := ""


func _ready() -> void:
	if not StarterSelectionSystem.starter_selected.is_connected(
		_on_starter_selected
	):
		StarterSelectionSystem.starter_selected.connect(_on_starter_selected)
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
## overworld player pose. Public so callers can explicitly checkpoint a
## milestone in addition to the automatic hooks.
func save_now(force := false) -> bool:
	_last_error = ""
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
	_last_error = ""
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


## Serializes the current progression payload consumed by cloud sync.
## Cloud linkage credentials and device metadata live in a separate file and
## are intentionally never included in a portable export.
func get_export_json() -> String:
	_last_error = ""
	var payload := get_save_payload()
	if payload.is_empty():
		_report_save_failure(
			"A save cannot be exported until the profile has been initialized."
		)
		return ""
	return JSON.stringify(payload, "\t")


## Writes a portable JSON backup outside the ordinary user:// checkpoint.
## This does not emit save_completed because exporting a backup is not a local
## progression mutation and should not schedule an unnecessary cloud request.
func write_export_json(path: String) -> bool:
	_last_error = ""
	if path.strip_edges().is_empty():
		return _report_save_failure("No JSON export path was selected.")
	var source := get_export_json()
	if source.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _report_save_failure(
			"Could not open %s for writing: %s"
			% [path, error_string(FileAccess.get_open_error())]
		)
	file.store_string(source)
	file.flush()
	return true


## Parses a portable backup, applies it through the same validators as local
## and cloud loads, and checkpoints the accepted result. Imported sections are
## timestamped as a new local change so an already-linked cloud profile can
## resolve the import through its normal causal merge rather than ignoring an
## older backup timestamp.
func import_json_save(source: String, source_label := "JSON import") -> bool:
	_last_error = ""
	if source.to_utf8_buffer().size() > MAX_JSON_TRANSFER_BYTES:
		return _report_load_failure(
			"The selected JSON save is larger than the 2 MiB cloud-save limit."
		)
	if not _can_replace_progress():
		return _report_load_failure(
			"A save cannot be imported during a battle, scene transition, reset, "
			+ "or starter selection."
		)

	var json := JSON.new()
	var parse_error := json.parse(source)
	if parse_error != OK:
		return _report_load_failure(
			"The selected save is not valid JSON (line %d: %s)."
			% [json.get_error_line(), json.get_error_message()]
		)
	if typeof(json.data) != TYPE_DICTIONARY:
		return _report_load_failure("The selected save is not a JSON object.")
	var previous_saved_at_ms := _last_saved_at_ms
	if not _apply_payload(json.data as Dictionary, source_label):
		return false

	_retimestamp_imported_sections(previous_saved_at_ms)
	return save_now(true)


func get_last_error() -> String:
	return _last_error


## Applies an already-resolved cloud payload through the same validators used
## for disk loading, then immediately checkpoints the accepted result locally.
func apply_cloud_payload(payload: Dictionary) -> bool:
	_last_error = ""
	if not _apply_payload(payload, "cloud sync"):
		return false
	return save_now(true)


func _can_replace_progress() -> bool:
	return (
		BattleSystem.get_state() == BattleSystem.State.IDLE
		and not GameInstance.is_battle_start_in_progress()
		and not GameInstance.is_battle_return_in_progress()
		and not GameInstance.is_scene_transfer_in_progress()
		and not _profile_initialization_pending
		and not _reset_in_progress
	)


func _retimestamp_imported_sections(previous_saved_at_ms: int) -> void:
	_last_saved_at_ms = maxi(
		maxi(_unix_time_ms(), previous_saved_at_ms + 1),
		1
	)
	_section_updated_at_ms.clear()
	for section in SAVE_SECTIONS:
		_section_updated_at_ms[section] = _last_saved_at_ms
	_last_section_fingerprints.clear()
	_last_payload_fingerprint = ""


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

	var economy_value: Variant = _default_economy_data()
	var inventory_value: Variant = _default_inventory_data()
	var challenge_value: Variant = _default_challenge_data()
	if schema_version >= DOMAIN_SPLIT_SAVE_SCHEMA_VERSION:
		economy_value = payload.get("economy")
		inventory_value = payload.get("inventory")
		challenge_value = payload.get("challenge_progression")
	elif schema_version >= STRETCH_SAVE_SCHEMA_VERSION:
		var migrated_domains := _migrate_legacy_stretch_data(payload.get("stretch"))
		var migration_error := String(migrated_domains.get("error", ""))
		if not migration_error.is_empty():
			return _report_load_failure(migration_error)
		economy_value = migrated_domains.get("economy")
		inventory_value = migrated_domains.get("inventory")
		challenge_value = migrated_domains.get("challenge_progression")

	var economy_error := EconomySystem.validate_save_data(economy_value)
	if not economy_error.is_empty():
		return _report_load_failure(economy_error)
	var inventory_error := InventorySystem.validate_save_data(inventory_value)
	if not inventory_error.is_empty():
		return _report_load_failure(inventory_error)
	var challenge_error := ChallengeProgressionSystem.validate_save_data(
		challenge_value
	)
	if not challenge_error.is_empty():
		return _report_load_failure(challenge_error)

	var move_learning_value: Variant = payload.get("move_learning", {"pending": []})
	if schema_version >= MOVE_LEARNING_SAVE_SCHEMA_VERSION:
		var move_learning_error := MoveLearningSystem.validate_save_data(
			move_learning_value,
			collection_value as Array
		)
		if not move_learning_error.is_empty():
			return _report_load_failure(move_learning_error)
	if schema_version >= TIMESTAMPED_SAVE_SCHEMA_VERSION:
		var save_meta_error := _validate_save_meta(
			payload.get("save_meta"), schema_version
		)
		if not save_meta_error.is_empty():
			return _report_load_failure(save_meta_error)

	MoveLearningSystem.begin_save_restore()
	_is_loading = true
	var collection_loaded := CollectionSystem.load_save_data(collection_value as Array)
	if not collection_loaded:
		_is_loading = false
		MoveLearningSystem.finish_save_restore()
		return _report_load_failure(
			"Collection save data was rejected: %s" % CollectionSystem.get_last_error()
		)
	if not EconomySystem.load_save_data(economy_value):
		_is_loading = false
		MoveLearningSystem.finish_save_restore()
		return _report_load_failure(
			"Economy progression was rejected: %s" % EconomySystem.get_last_error()
		)
	if not InventorySystem.load_save_data(inventory_value):
		_is_loading = false
		MoveLearningSystem.finish_save_restore()
		return _report_load_failure(
			"Inventory progression was rejected: %s" % InventorySystem.get_last_error()
		)
	if not ChallengeProgressionSystem.load_save_data(challenge_value):
		_is_loading = false
		MoveLearningSystem.finish_save_restore()
		return _report_load_failure(
			"Challenge progression was rejected: %s"
			% ChallengeProgressionSystem.get_last_error()
		)
	var loaded_move_learning := MoveLearningSystem.load_save_data(
		move_learning_value
		if schema_version >= MOVE_LEARNING_SAVE_SCHEMA_VERSION
		else {"pending": []}
	)
	if not loaded_move_learning:
		_is_loading = false
		MoveLearningSystem.finish_save_restore()
		return _report_load_failure("Move-learning progression was rejected.")
	MoveLearningSystem.finish_save_restore()
	_is_loading = false
	_starter_pokemon_id = loaded_starter_pokemon_id
	_profile_initialization_pending = false
	_reset_in_progress = false
	_explicit_reset_pending = false
	StarterSelectionSystem.mark_profile_loaded(_starter_pokemon_id)

	_saved_world_state = _migrate_legacy_world_data(
		payload.get("world", {}),
		String((challenge_value as Dictionary).get("active_area_id", "")),
		schema_version
	)
	_restore_saved_world_state_for_current_scene()
	if schema_version >= TIMESTAMPED_SAVE_SCHEMA_VERSION:
		_load_save_meta(payload.get("save_meta") as Dictionary, schema_version)
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
	MoveLearningSystem.progression_changed.connect(
		_on_move_learning_progression_changed
	)
	EconomySystem.progression_changed.connect(_on_domain_progression_changed)
	InventorySystem.progression_changed.connect(_on_domain_progression_changed)
	ChallengeProgressionSystem.progression_changed.connect(
		_on_domain_progression_changed
	)
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


func _on_domain_progression_changed() -> void:
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
		"move_learning": MoveLearningSystem.get_save_data(),
		"economy": EconomySystem.get_save_data(),
		"inventory": InventorySystem.get_save_data(),
		"challenge_progression": ChallengeProgressionSystem.get_save_data(),
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
	MoveLearningSystem.begin_save_restore()
	CollectionSystem.clear_collection()
	MoveLearningSystem.load_save_data({"pending": []})
	MoveLearningSystem.finish_save_restore()
	EconomySystem.reset_progress()
	InventorySystem.reset_progress()
	ChallengeProgressionSystem.reset_progress()
	GameInstance.reset_profile_transient_progress()
	_is_loading = false
	_saved_world_state.clear()
	_last_payload_fingerprint = ""
	_last_saved_at_ms = 0
	_section_updated_at_ms.clear()
	_last_section_fingerprints.clear()
	StarterSelectionSystem.prepare_new_profile()


func _finish_fresh_profile_handoff() -> void:
	if not _profile_initialization_pending:
		return
	_reset_in_progress = false
	StarterSelectionSystem.show_selection()


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


func _default_economy_data() -> Dictionary:
	return {
		"version": EconomyService.CURRENT_ECONOMY_VERSION,
		"balance": EconomyService.STARTING_BALANCE,
		"last_battle_reward": {},
	}


func _default_inventory_data() -> Dictionary:
	return {"item_quantities": {}, "claimed_gifts": []}


func _default_challenge_data() -> Dictionary:
	return {
		"earned_badges": [],
		"champion_completed": false,
		"completed_routes": [],
		"active_area_id": "",
		"run_defeated_ids": [],
		"run_id": 0,
	}


func _migrate_legacy_stretch_data(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "Legacy progression is not an object."}
	var legacy := value as Dictionary
	var economy_version: Variant = legacy.get("economy_version", 1)
	if (
		not _is_integer_value(economy_version)
		or int(economy_version) < 1
		or int(economy_version) > EconomyService.CURRENT_ECONOMY_VERSION
	):
		return {"error": "Legacy progression has an invalid economy version."}
	var economy := {
		"version": EconomyService.CURRENT_ECONOMY_VERSION,
		"balance": legacy.get("balance"),
		"last_battle_reward": legacy.get("last_battle_reward", {}),
	}
	var economy_error := EconomySystem.validate_save_data(economy)
	if not economy_error.is_empty():
		return {"error": economy_error}
	if int(economy_version) < 2 and _is_untouched_legacy_economy(legacy):
		economy["balance"] = EconomyService.STARTING_BALANCE

	var inventory := {
		"item_quantities": legacy.get("item_inventory", {}),
		"claimed_gifts": legacy.get("claimed_gifts", []),
	}
	var inventory_error := InventorySystem.validate_save_data(inventory)
	if not inventory_error.is_empty():
		return {"error": inventory_error}

	var active_destination: Variant = legacy.get("active_destination", {})
	var active_area_id := _legacy_destination_to_area_id(active_destination)
	var defeated_value: Variant = legacy.get("run_defeated_ids", [])
	var converted_defeated: Variant = defeated_value
	if typeof(defeated_value) == TYPE_ARRAY:
		var defeated_ids: Array[String] = []
		for defeated_id_value: Variant in defeated_value as Array:
			if typeof(defeated_id_value) != TYPE_STRING:
				defeated_ids.append("__invalid__")
				continue
			var converted_id := _convert_legacy_encounter_id(
				String(defeated_id_value)
			)
			if not converted_id.is_empty():
				defeated_ids.append(converted_id)
		converted_defeated = defeated_ids
	var challenge := {
		"earned_badges": legacy.get("earned_badges", []),
		"champion_completed": legacy.get("champion_cleared", false),
		"completed_routes": legacy.get("completed_routes", []),
		"active_area_id": active_area_id,
		"run_defeated_ids": converted_defeated,
		"run_id": legacy.get("run_id", 0),
	}
	var challenge_error := ChallengeProgressionSystem.validate_save_data(challenge)
	if not challenge_error.is_empty():
		return {"error": challenge_error}
	return {
		"economy": economy,
		"inventory": inventory,
		"challenge_progression": challenge,
	}


func _legacy_destination_to_area_id(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "__invalid__"
	var destination := value as Dictionary
	if destination.is_empty():
		return ""
	var index_value: Variant = destination.get("index")
	if not _is_integer_value(index_value):
		return "__invalid__"
	var destination_index := int(index_value)
	match String(destination.get("kind", "")):
		"route":
			return (
				"route_%02d" % destination_index
				if destination_index >= 0 and destination_index < 40
				else "__invalid__"
			)
		"gym":
			return (
				"gym_%02d" % destination_index
				if destination_index >= 1 and destination_index <= 8
				else "__invalid__"
			)
		"champion":
			return "champion_challenge" if destination_index == 1 else "__invalid__"
	return "__invalid__"


func _convert_legacy_encounter_id(encounter_id: String) -> String:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id.is_empty():
		return "__invalid__"
	if ChallengeProgressionSystem.find_encounter_definition(normalized_id) != null:
		return normalized_id
	if normalized_id == "stretch-champion":
		return "champion"
	var parts := normalized_id.split("-", false)
	var converted_id := normalized_id
	if (
		parts.size() == 5
		and parts[0] == "stretch"
		and parts[1] == "route"
		and parts[2].is_valid_int()
		and parts[3] == "trainer"
		and parts[4].is_valid_int()
	):
		var route_index := int(parts[2])
		if route_index == 0:
			# Route 0 now retains its original authored encounter IDs and never
			# gates completion on this transient run list.
			return ""
		converted_id = "route-%02d-trainer-%02d" % [route_index, int(parts[4])]
	elif (
		parts.size() == 4
		and parts[0] == "stretch"
		and parts[1] == "gym"
		and parts[2].is_valid_int()
		and parts[3] == "leader"
	):
		converted_id = "gym-%02d-leader" % int(parts[2])
	elif (
		parts.size() == 4
		and parts[0] == "stretch"
		and parts[1] == "elite"
		and parts[2] == "four"
		and parts[3].is_valid_int()
	):
		converted_id = "elite-four-%02d" % int(parts[3])
	elif (
		parts.size() == 4
		and parts[0] == "stretch"
		and parts[1] == "route"
		and parts[2].is_valid_int()
		and parts[3] == "wild"
	):
		var route_index := int(parts[2])
		if route_index == 0:
			return "wild-fletchling-route-0-v1"
		converted_id = "route-%02d-wild" % route_index
	return converted_id


func _is_untouched_legacy_economy(data: Dictionary) -> bool:
	var inventory_value: Variant = data.get("item_inventory", {})
	var badges_value: Variant = data.get("earned_badges", [])
	var reward_value: Variant = data.get("last_battle_reward", {})
	return (
		int(data.get("balance", 0)) == EconomyService.LEGACY_STARTING_BALANCE
		and typeof(inventory_value) == TYPE_DICTIONARY
		and (inventory_value as Dictionary).is_empty()
		and typeof(badges_value) == TYPE_ARRAY
		and (badges_value as Array).is_empty()
		and not bool(data.get("champion_cleared", false))
		and typeof(reward_value) == TYPE_DICTIONARY
		and (reward_value as Dictionary).is_empty()
	)


func _migrate_legacy_world_data(
	value: Variant,
	active_area_id: String,
	schema_version: int
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var world := (value as Dictionary).duplicate(true)
	if schema_version >= DOMAIN_SPLIT_SAVE_SCHEMA_VERSION:
		return world
	var scene_path := String(world.get("scene_path", ""))
	match scene_path:
		"res://demo/primary_development_enviroment.tscn", \
		"res://demo/new_bouffalant_city_scene.tscn":
			world["scene_path"] = MAIN_SCENE_PATH
		"res://overworld/route_0/route_0.tscn", \
		"res://overworld/route_4/route_4.tscn":
			world["scene_path"] = (
				"res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn"
			)
		"res://rnd/stretch/worlds/stretch_destination.tscn":
			var area := ChallengeProgressionSystem.get_area(active_area_id)
			if area != null and area.destination != null:
				world["scene_path"] = area.destination.resource_path
	return world


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
		not in StarterSelectionSystem.STARTER_POKEMON_IDS
	):
		return "Progression profile references an unknown starter."
	if collection_data.is_empty():
		return "An initialized progression profile cannot have an empty collection."
	return ""


func _validate_save_meta(value: Variant, schema_version: int) -> String:
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
	for section in _save_sections_for_schema(schema_version):
		if not _is_non_negative_integer_value(section_timestamps.get(section)):
			return "Progression save has an invalid %s timestamp." % section
	return ""


func _load_save_meta(save_meta: Dictionary, schema_version: int) -> void:
	_last_saved_at_ms = int(save_meta.get("saved_at_ms", 0))
	var saved_timestamps := save_meta.get("section_updated_at_ms", {}) as Dictionary
	_section_updated_at_ms.clear()
	for section in SAVE_SECTIONS:
		var source_section := section
		if (
			schema_version < DOMAIN_SPLIT_SAVE_SCHEMA_VERSION
			and section in ["economy", "inventory", "challenge_progression"]
		):
			source_section = "stretch"
		_section_updated_at_ms[section] = int(
			saved_timestamps.get(source_section, _last_saved_at_ms)
		)
	_last_section_fingerprints.clear()


func _save_sections_for_schema(schema_version: int) -> Array[String]:
	if schema_version >= DOMAIN_SPLIT_SAVE_SCHEMA_VERSION:
		return SAVE_SECTIONS.duplicate()
	return ["profile", "collection", "move_learning", "stretch", "world"]


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
	_last_error = message
	push_error("Progression autosave failed: %s" % message)
	save_failed.emit(message)
	return false


func _report_load_failure(message: String) -> bool:
	_last_error = message
	push_error("Progression load failed: %s" % message)
	load_failed.emit(message)
	return false
