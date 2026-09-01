extends Node

const TEST_SAVE_PATH := "user://pfr_cloud_sync_progression_smoke_test.json"
const PRIVATE_SAVE_ID := "cloud-sync-smoke-private-id"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_test_save()
	var original_collection := CollectionSystem.get_save_data()
	var original_move_learning := RNDMoveLearningSystem.get_save_data()
	var original_stretch := StretchGoalSystem.get_save_data()
	var original_save_path := ProgressionAutosave.save_path
	ProgressionAutosave.save_path = TEST_SAVE_PATH
	CloudSaveSync.disable_cloud_sync()
	_check(
		CloudSaveSync._test_mode,
		"Cloud-save smoke tests must suppress real background network access."
	)
	var original_endpoint_environment := OS.get_environment(
		"PFR_CLOUD_SAVE_ENDPOINT"
	)
	OS.unset_environment("PFR_CLOUD_SAVE_ENDPOINT")
	CloudSaveSync.endpoint_override = ""
	_check(
		CloudSaveSync._resolve_endpoint()
		== RNDCloudSaveSync.NATIVE_DEFAULT_ENDPOINT,
		"Native debug builds should use the linked production cloud endpoint."
	)
	if not original_endpoint_environment.is_empty():
		OS.set_environment(
			"PFR_CLOUD_SAVE_ENDPOINT",
			original_endpoint_environment,
		)
	_check(
		not CloudSaveSync.enable_with_save_id("short")
		and CloudSaveSync.enable_with_save_id(PRIVATE_SAVE_ID),
		"Cloud sync should reject weak IDs and accept a private 12+ character ID."
	)
	_check(
		ProgressionAutosave.save_now(true),
		"The cloud-sync fixture should write its timestamped local baseline."
	)

	var local_payload := ProgressionAutosave.get_save_payload()
	var cloud_payload := local_payload.duplicate(true)
	var cloud_stretch := cloud_payload.get("stretch", {}) as Dictionary
	cloud_stretch["balance"] = 4321
	cloud_payload["stretch"] = cloud_stretch
	_touch_section(cloud_payload, "stretch", 100)
	_prepare_inflight(local_payload)
	ProgressionAutosave._profile_initialization_pending = true
	CloudSaveSync._on_request_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		JSON.stringify({
			"ok": true,
			"protocol_version": 1,
			"outcome": "cloud_linked",
			"revision": 7,
			"epoch": 0,
			"synced_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
			"payload": cloud_payload,
		}).to_utf8_buffer()
	)
	_check(
		not CloudSaveSync._deferred_response.is_empty()
		and StretchGoalSystem.get_balance() != 4321,
		"A cloud response should wait while progression is in a transition-sensitive state."
	)
	ProgressionAutosave._profile_initialization_pending = false
	CloudSaveSync._on_sync_timer_timeout()
	_check(
		StretchGoalSystem.get_balance() == 4321
		and CloudSaveSync.get_base_revision() == 7
		and CloudSaveSync.get_state() == "synced",
		"A successful first link should validate, apply, and checkpoint the cloud payload."
	)

	var request_baseline := ProgressionAutosave.get_save_payload()
	_prepare_inflight(request_baseline)
	var first_party_member := CollectionSystem.get_party()[0] as Dictionary
	var pcl_id := String(first_party_member.get("pclID", ""))
	_check(
		CollectionSystem.update_instance_stats(pcl_id, {"health": 0.37})
		and ProgressionAutosave.save_now(true),
		"The fixture should make a local collection change while a request is in flight."
	)
	var second_cloud_payload := request_baseline.duplicate(true)
	var second_cloud_stretch := (
		second_cloud_payload.get("stretch", {}) as Dictionary
	)
	second_cloud_stretch["balance"] = 8765
	second_cloud_payload["stretch"] = second_cloud_stretch
	_touch_section(second_cloud_payload, "stretch", 200)
	CloudSaveSync._on_request_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		JSON.stringify({
			"ok": true,
			"protocol_version": 1,
			"outcome": "client_saved",
			"revision": 8,
			"epoch": 0,
			"synced_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
			"payload": second_cloud_payload,
		}).to_utf8_buffer()
	)
	var rebased_member := CollectionSystem.get_pcl(pcl_id)
	var rebased_stats := rebased_member.get("instanceStats", {}) as Dictionary
	_check(
		is_equal_approx(float(rebased_stats.get("health", 0.0)), 0.37)
		and StretchGoalSystem.get_balance() == 8765
		and CloudSaveSync._force_conflict_sections.has("collection"),
		(
			"A response must rebase changes made during the request and mark that "
			+ "section for a server-side intelligent merge on the next pass."
		)
	)

	CloudSaveSync.disable_cloud_sync()
	RNDMoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(original_collection)
	RNDMoveLearningSystem.load_save_data(original_move_learning)
	RNDMoveLearningSystem.finish_save_restore()
	StretchGoalSystem.load_save_data(original_stretch)
	ProgressionAutosave.save_path = original_save_path
	_remove_test_save()

	if _failures.is_empty():
		print(
			"Cloud-save sync smoke test passed: private-ID opt-in, validated cloud apply, "
			+ "safe transition deferral, local checkpoint, and in-flight change rebase verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Cloud-save sync smoke test failed: %s" % failure)
	get_tree().quit(1)


func _prepare_inflight(payload: Dictionary) -> void:
	CloudSaveSync._inflight_section_fingerprints = (
		CloudSaveSync._section_fingerprints(payload)
	)
	CloudSaveSync._inflight_save_id = CloudSaveSync.get_save_id()
	CloudSaveSync._inflight_epoch = 0
	CloudSaveSync._inflight_conflict_sections.clear()
	CloudSaveSync._sync_in_flight = true
	CloudSaveSync._sync_requested = false


func _touch_section(payload: Dictionary, section: String, offset_ms: int) -> void:
	var save_meta := payload.get("save_meta", {}) as Dictionary
	var timestamps := save_meta.get("section_updated_at_ms", {}) as Dictionary
	var timestamp := int(save_meta.get("saved_at_ms", 0)) + offset_ms
	timestamps[section] = timestamp
	save_meta["section_updated_at_ms"] = timestamps
	save_meta["saved_at_ms"] = timestamp
	payload["save_meta"] = save_meta


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
