class_name RNDCloudSaveSync
extends Node

## Optional cloud-save coordinator. Atlas credentials exist only in the
## server-side Netlify Function; this client holds a player-selected Save ID,
## local causal revision, and offline-safe section fingerprints.

signal status_changed(state: String, message: String)
signal configuration_changed(enabled: bool)
signal sync_completed(outcome: String)
signal sync_failed(message: String)

const PROTOCOL_VERSION := 1
const DEFAULT_CONFIG_PATH := "user://pfr_cloud_sync.json"
const WEB_ENDPOINT_PATH := "/api/cloud-save"
const NATIVE_DEFAULT_ENDPOINT := (
	"https://pfr-early-alpha.netlify.app/api/cloud-save"
)
const SAVE_ID_MIN_LENGTH := 12
const SAVE_ID_MAX_LENGTH := 128
const REQUEST_TIMEOUT_SECONDS := 18.0
const LOCAL_CHANGE_DEBOUNCE_SECONDS := 1.0
const POLL_SECONDS := 45.0
const INITIAL_RETRY_SECONDS := 5.0
const MAX_RETRY_SECONDS := 300.0
const SAVE_SECTIONS: Array[String] = [
	"profile",
	"collection",
	"move_learning",
	"stretch",
	"world",
]
const TEST_SCENE_PREFIXES: Array[String] = [
	"res://tests/",
	"res://rnd/tests/",
]

@export var endpoint_override := ""

var config_path := DEFAULT_CONFIG_PATH

var _enabled := false
var _save_id := ""
var _device_id := ""
var _epoch := 0
var _base_revision := 0
var _base_section_fingerprints: Dictionary = {}
var _force_conflict_sections: Dictionary = {}
var _last_sync_at_ms := 0
var _state := "disabled"
var _status_message := "Cloud sync is off. Local saves remain enabled."
var _http_request: HTTPRequest
var _sync_timer: Timer
var _sync_in_flight := false
var _sync_requested := false
var _applying_cloud_payload := false
var _retry_seconds := INITIAL_RETRY_SECONDS
var _inflight_section_fingerprints: Dictionary = {}
var _inflight_save_id := ""
var _inflight_epoch := 0
var _inflight_conflict_sections: Array[String] = []
var _deferred_response: Dictionary = {}
var _test_mode := false


func _ready() -> void:
	_initialize.call_deferred()


func _initialize() -> void:
	_test_mode = _is_test_scene()
	if _test_mode:
		_device_id = _generate_device_id()
	else:
		_load_config()
	_connect_progression_signals()
	if _test_mode:
		return

	_http_request = HTTPRequest.new()
	_http_request.name = "CloudSaveHTTPRequest"
	_http_request.timeout = REQUEST_TIMEOUT_SECONDS
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)
	_sync_timer = Timer.new()
	_sync_timer.name = "CloudSaveSyncTimer"
	_sync_timer.one_shot = true
	_sync_timer.timeout.connect(_on_sync_timer_timeout)
	add_child(_sync_timer)
	if _enabled:
		_set_status("pending", "Cloud save is enabled. Waiting to synchronize…")
		_schedule_sync(0.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _enabled:
		_persist_config()


func is_enabled() -> bool:
	return _enabled


func get_save_id() -> String:
	return _save_id


func get_state() -> String:
	return _state


func get_status_message() -> String:
	return _status_message


func get_last_sync_at_ms() -> int:
	return _last_sync_at_ms


func get_base_revision() -> int:
	return _base_revision


func validate_save_id(value: String) -> String:
	var normalized := value.strip_edges()
	if (
		normalized.length() < SAVE_ID_MIN_LENGTH
		or normalized.length() > SAVE_ID_MAX_LENGTH
	):
		return "Use a private Save ID between 12 and 128 characters."
	for index in normalized.length():
		var character := normalized.unicode_at(index)
		if character < 32 or character == 127:
			return "Save IDs cannot contain control characters."
	return ""


## Enables background sync. Entering an ID already present in Atlas performs a
## first-link pull; it never overwrites that cloud save with an unrelated local
## profile simply because this device was linked later.
func enable_with_save_id(value: String) -> bool:
	var normalized := value.strip_edges()
	var validation_error := validate_save_id(normalized)
	if not validation_error.is_empty():
		_set_status("error", validation_error)
		return false
	var changed_id := normalized != _save_id
	_save_id = normalized
	_enabled = true
	if changed_id:
		_epoch = 0
		_base_revision = 0
		_base_section_fingerprints.clear()
		_force_conflict_sections.clear()
		_last_sync_at_ms = 0
	_persist_config()
	configuration_changed.emit(true)
	_set_status("pending", "Save ID accepted. Synchronizing in the background…")
	request_sync(true)
	return true


## Opting out clears the local Save ID and all cloud linkage. The ordinary
## progression file continues saving exactly as before.
func disable_cloud_sync() -> void:
	_enabled = false
	_save_id = ""
	_epoch = 0
	_base_revision = 0
	_base_section_fingerprints.clear()
	_force_conflict_sections.clear()
	_last_sync_at_ms = 0
	_sync_requested = false
	_inflight_section_fingerprints.clear()
	_inflight_save_id = ""
	_inflight_conflict_sections.clear()
	_deferred_response.clear()
	if is_instance_valid(_sync_timer):
		_sync_timer.stop()
	if _sync_in_flight and is_instance_valid(_http_request):
		_http_request.cancel_request()
	_sync_in_flight = false
	_persist_config()
	configuration_changed.emit(false)
	_set_status("disabled", "Cloud sync is off. Local saves remain enabled.")


func request_sync(immediate := false) -> bool:
	if not _enabled:
		_set_status("disabled", "Cloud sync is off. Local saves remain enabled.")
		return false
	if ProgressionAutosave.is_profile_initialization_pending():
		_set_status("pending", "Cloud sync will start after a starter is selected.")
		return false
	_sync_requested = true
	if _sync_in_flight:
		return true
	_schedule_sync(0.05 if immediate else LOCAL_CHANGE_DEBOUNCE_SECONDS)
	return true


func _connect_progression_signals() -> void:
	if not ProgressionAutosave.save_completed.is_connected(_on_local_save_completed):
		ProgressionAutosave.save_completed.connect(_on_local_save_completed)
	if not ProgressionAutosave.load_completed.is_connected(_on_local_load_completed):
		ProgressionAutosave.load_completed.connect(_on_local_load_completed)
	if not ProgressionAutosave.progress_reset_started.is_connected(_on_progress_reset_started):
		ProgressionAutosave.progress_reset_started.connect(_on_progress_reset_started)
	if not ProgressionAutosave.progress_reset_completed.is_connected(_on_progress_reset_completed):
		ProgressionAutosave.progress_reset_completed.connect(_on_progress_reset_completed)


func _on_local_save_completed(_save_path: String) -> void:
	if _applying_cloud_payload or not _enabled:
		return
	request_sync()


func _on_local_load_completed(_source: String) -> void:
	if _applying_cloud_payload or not _enabled:
		return
	request_sync(true)


func _on_progress_reset_started() -> void:
	if not _enabled:
		return
	_epoch = mini(_epoch + 1, 2_147_483_647)
	_base_revision = 0
	_base_section_fingerprints.clear()
	_force_conflict_sections.clear()
	_last_sync_at_ms = 0
	_persist_config()
	_set_status(
		"pending",
		"Cloud reset protection is armed; the fresh profile will replace older copies.",
	)


func _on_progress_reset_completed(_starter_pokemon_id: int) -> void:
	if _enabled:
		request_sync(true)


func _schedule_sync(delay_seconds: float) -> void:
	if _test_mode or not _enabled or not is_instance_valid(_sync_timer):
		return
	if _sync_timer.is_stopped() or delay_seconds < _sync_timer.time_left:
		_sync_timer.start(maxf(delay_seconds, 0.01))


func _on_sync_timer_timeout() -> void:
	if not _deferred_response.is_empty():
		_process_successful_response(_deferred_response.duplicate(true))
		return
	_start_sync()


func _start_sync() -> void:
	if not _enabled or _sync_in_flight:
		return
	if not _can_apply_cloud_payload():
		_set_status(
			"pending",
			"Cloud sync is waiting for the current battle or transition to finish.",
		)
		_schedule_sync(1.0)
		return
	var payload := ProgressionAutosave.get_save_payload()
	if payload.is_empty():
		_set_status("pending", "Cloud sync is waiting for an initialized local save.")
		_schedule_sync(POLL_SECONDS)
		return
	var endpoint := _resolve_endpoint()
	if endpoint.is_empty():
		_handle_sync_failure(
			"Cloud endpoint is unavailable here. Your local save is safe; retrying later.",
		)
		return

	var current_fingerprints := _section_fingerprints(payload)
	var changed_sections: Array[String] = []
	if _base_revision <= 0:
		changed_sections.assign(SAVE_SECTIONS)
	else:
		for section in SAVE_SECTIONS:
			if (
				not _base_section_fingerprints.has(section)
				or String(_base_section_fingerprints[section])
				!= String(current_fingerprints[section])
			):
				changed_sections.append(section)

	var request_body := {
		"protocol_version": PROTOCOL_VERSION,
		"save_id": _save_id,
		"device_id": _device_id,
		"epoch": _epoch,
		"base_revision": _base_revision,
		"changed_sections": changed_sections,
		"conflict_sections": _conflict_sections_for(changed_sections),
		"payload": payload,
	}
	var request_error := _http_request.request(
		endpoint,
		PackedStringArray([
			"Accept: application/json",
			"Content-Type: application/json",
		]),
		HTTPClient.METHOD_POST,
		JSON.stringify(request_body)
	)
	if request_error != OK:
		_handle_sync_failure(
			"Cloud sync could not start. Your local save is safe; retrying later."
		)
		return
	_inflight_section_fingerprints = current_fingerprints
	_inflight_save_id = _save_id
	_inflight_epoch = _epoch
	_inflight_conflict_sections.assign(request_body["conflict_sections"])
	_sync_requested = false
	_sync_in_flight = true
	_set_status("syncing", "Synchronizing local and cloud progress…")


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_sync_in_flight = false
	if not _enabled:
		return
	if _inflight_save_id != _save_id or _inflight_epoch != _epoch:
		_inflight_section_fingerprints.clear()
		_inflight_save_id = ""
		_inflight_conflict_sections.clear()
		request_sync(true)
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_sync_failure(
			"You appear to be offline. Local progress is safe and will sync automatically."
		)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_handle_sync_failure("The cloud service returned an invalid response.")
		return
	var response := parsed as Dictionary
	if response_code != 200 or not bool(response.get("ok", false)):
		_handle_service_error(response_code, response)
		return
	if (
		int(response.get("protocol_version", -1)) != PROTOCOL_VERSION
		or not _is_non_negative_integer(response.get("revision"))
		or not _is_non_negative_integer(response.get("epoch"))
		or typeof(response.get("payload")) != TYPE_DICTIONARY
	):
		_handle_sync_failure("The cloud service returned incompatible save data.")
		return
	_process_successful_response(response)


func _process_successful_response(response: Dictionary) -> void:
	if not _enabled:
		_deferred_response.clear()
		return
	if _inflight_save_id != _save_id or _inflight_epoch != _epoch:
		_deferred_response.clear()
		_inflight_section_fingerprints.clear()
		_inflight_save_id = ""
		_inflight_conflict_sections.clear()
		request_sync(true)
		return
	if not _can_apply_cloud_payload():
		_deferred_response = response.duplicate(true)
		_set_status(
			"pending",
			"Cloud progress is ready and will apply after the current battle or transition.",
		)
		_schedule_sync(1.0)
		return
	_deferred_response.clear()

	var cloud_payload := (response.get("payload") as Dictionary).duplicate(true)
	var latest_local_payload := ProgressionAutosave.get_save_payload()
	var latest_fingerprints := _section_fingerprints(latest_local_payload)
	var rebased_payload := cloud_payload.duplicate(true)
	var next_forced_conflicts := _force_conflict_sections.duplicate(true)
	for section in _inflight_conflict_sections:
		next_forced_conflicts.erase(section)
	var changed_during_request := false
	for section in SAVE_SECTIONS:
		if (
			not _inflight_section_fingerprints.has(section)
			or String(_inflight_section_fingerprints[section])
			!= String(latest_fingerprints.get(section, ""))
		):
			rebased_payload[section] = latest_local_payload.get(section)
			var latest_meta := latest_local_payload.get("save_meta", {}) as Dictionary
			var latest_timestamps := (
				latest_meta.get("section_updated_at_ms", {}) as Dictionary
			)
			var rebased_meta := rebased_payload.get("save_meta", {}) as Dictionary
			var rebased_timestamps := (
				rebased_meta.get("section_updated_at_ms", {}) as Dictionary
			)
			rebased_timestamps[section] = int(latest_timestamps.get(section, 0))
			rebased_meta["section_updated_at_ms"] = rebased_timestamps
			rebased_meta["saved_at_ms"] = int(latest_meta.get("saved_at_ms", 0))
			rebased_payload["save_meta"] = rebased_meta
			next_forced_conflicts[section] = true
			changed_during_request = true

	var rebased_fingerprints := _section_fingerprints(rebased_payload)
	var requires_local_apply := false
	for section in SAVE_SECTIONS:
		if String(rebased_fingerprints[section]) != String(latest_fingerprints[section]):
			requires_local_apply = true
			break
	if requires_local_apply:
		_applying_cloud_payload = true
		var applied := ProgressionAutosave.apply_cloud_payload(rebased_payload)
		_applying_cloud_payload = false
		if not applied:
			_handle_sync_failure(
				"Cloud data failed local validation, so the local save was left unchanged."
			)
			return

	_base_revision = int(response.get("revision", 0))
	_epoch = int(response.get("epoch", _epoch))
	_base_section_fingerprints = _section_fingerprints(cloud_payload)
	_force_conflict_sections = next_forced_conflicts
	_last_sync_at_ms = int(response.get("synced_at_ms", _unix_time_ms()))
	_retry_seconds = INITIAL_RETRY_SECONDS
	_persist_config()
	var outcome := String(response.get("outcome", "up_to_date"))
	_set_status("synced", _outcome_message(outcome, changed_during_request))
	sync_completed.emit(outcome)
	_inflight_section_fingerprints.clear()
	_inflight_save_id = ""
	_inflight_conflict_sections.clear()
	if changed_during_request or _sync_requested:
		request_sync(true)
	else:
		_schedule_sync(POLL_SECONDS)


func _can_apply_cloud_payload() -> bool:
	return (
		BattleSystem.get_state() == BattleSystem.State.IDLE
		and not GameInstance.is_battle_start_in_progress()
		and not GameInstance.is_battle_return_in_progress()
		and not GameInstance.is_scene_transfer_in_progress()
		and not ProgressionAutosave.is_profile_initialization_pending()
	)


func _handle_service_error(response_code: int, response: Dictionary) -> void:
	var error_key := String(response.get("error", ""))
	if response_code == 503 and error_key == "cloud_save_not_configured":
		_handle_sync_failure(
			"Cloud save is not configured on this deployment. Local saving still works."
		)
		return
	if response_code == 503 and error_key == "cloud_save_unavailable":
		_handle_sync_failure(
			"The cloud database is temporarily unavailable. Local progress is safe."
		)
		return
	if response_code == 429:
		_handle_sync_failure("Cloud sync is busy. Local progress is safe; retrying later.")
		return
	var service_message := String(response.get("message", ""))
	if service_message.is_empty():
		service_message = "Cloud sync failed with service response %d." % response_code
	_handle_sync_failure(service_message)


func _handle_sync_failure(message: String) -> void:
	_sync_in_flight = false
	_sync_requested = true
	_set_status("offline", message)
	sync_failed.emit(message)
	_schedule_sync(_retry_seconds)
	_retry_seconds = minf(_retry_seconds * 2.0, MAX_RETRY_SECONDS)


func _outcome_message(outcome: String, local_rebase: bool) -> String:
	if local_rebase:
		return "Cloud synchronized; a newer local change is queued for the next pass."
	match outcome:
		"created":
			return "Cloud save created and synchronized."
		"cloud_linked":
			return "Existing cloud progress was linked to this device."
		"cloud_reset_newer":
			return "A newer reset profile from the cloud was restored locally."
		"reset_epoch_applied":
			return "The confirmed reset replaced older cloud progress."
		"merged":
			return "Offline changes from multiple devices were safely merged."
		"client_saved":
			return "Local progress was uploaded to the cloud."
		_:
			return "Local and cloud progress are up to date."


func _resolve_endpoint() -> String:
	var explicit_endpoint := endpoint_override.strip_edges()
	if explicit_endpoint.is_empty():
		explicit_endpoint = OS.get_environment("PFR_CLOUD_SAVE_ENDPOINT").strip_edges()
	if not explicit_endpoint.is_empty():
		return explicit_endpoint if _is_safe_endpoint(explicit_endpoint) else ""
	if OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if typeof(origin) == TYPE_STRING:
			var web_endpoint := String(origin).trim_suffix("/") + WEB_ENDPOINT_PATH
			if _is_safe_endpoint(web_endpoint):
				return web_endpoint
	return NATIVE_DEFAULT_ENDPOINT


func _is_safe_endpoint(value: String) -> bool:
	if value.begins_with("https://"):
		return true
	return (
		value.begins_with("http://localhost:")
		or value.begins_with("http://127.0.0.1:")
		or value.begins_with("http://[::1]:")
	)


func _section_fingerprints(payload: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for section in SAVE_SECTIONS:
		result[section] = JSON.stringify(payload.get(section))
	return result


func _conflict_sections_for(changed_sections: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for section in changed_sections:
		if _force_conflict_sections.has(section):
			result.append(section)
	return result


func _load_config() -> void:
	_device_id = _generate_device_id()
	if not FileAccess.file_exists(config_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var config := parsed as Dictionary
	var stored_device_id := String(config.get("device_id", ""))
	if _is_device_id(stored_device_id):
		_device_id = stored_device_id
	var stored_enabled := bool(config.get("enabled", false))
	var stored_save_id := String(config.get("save_id", ""))
	if stored_enabled and validate_save_id(stored_save_id).is_empty():
		_enabled = true
		_save_id = stored_save_id.strip_edges()
		_epoch = maxi(int(config.get("epoch", 0)), 0)
		_base_revision = maxi(int(config.get("base_revision", 0)), 0)
		var fingerprints_value: Variant = config.get("base_section_fingerprints", {})
		if typeof(fingerprints_value) == TYPE_DICTIONARY:
			_base_section_fingerprints = (
				(fingerprints_value as Dictionary).duplicate(true)
			)
		var conflicts_value: Variant = config.get("force_conflict_sections", [])
		if typeof(conflicts_value) == TYPE_ARRAY:
			for section_value: Variant in conflicts_value as Array:
				var section := String(section_value)
				if section in SAVE_SECTIONS:
					_force_conflict_sections[section] = true
		_last_sync_at_ms = maxi(int(config.get("last_sync_at_ms", 0)), 0)


func _persist_config() -> void:
	if _test_mode and config_path == DEFAULT_CONFIG_PATH:
		return
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		push_error("Cloud-save preferences could not be written.")
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"enabled": _enabled,
		"save_id": _save_id if _enabled else "",
		"device_id": _device_id,
		"epoch": _epoch,
		"base_revision": _base_revision,
		"base_section_fingerprints": _base_section_fingerprints,
		"force_conflict_sections": _force_conflict_sections.keys(),
		"last_sync_at_ms": _last_sync_at_ms,
	}, "\t"))
	file.flush()


func _generate_device_id() -> String:
	var random_bytes := Crypto.new().generate_random_bytes(16)
	if random_bytes.size() == 16:
		return random_bytes.hex_encode()
	return ("%032x" % Time.get_ticks_usec()).right(32)


func _is_device_id(value: String) -> bool:
	if value.length() != 32:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _is_non_negative_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0
	return (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and float(value) >= 0.0
		and is_equal_approx(float(value), float(int(value)))
	)


func _is_test_scene() -> bool:
	var scene := get_tree().current_scene
	var scene_path := scene.scene_file_path if scene != null else ""
	for prefix in TEST_SCENE_PREFIXES:
		if scene_path.begins_with(prefix):
			return true
	return false


func _unix_time_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _set_status(state: String, message: String) -> void:
	_state = state
	_status_message = message
	status_changed.emit(state, message)
