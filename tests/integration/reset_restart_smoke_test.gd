extends Node

const TEST_SAVE_PATH := "user://pfr_reset_restart_smoke_test.json"
const RESET_SCENE: PackedScene = preload(
	"res://game/ui/reset_progress/progress_reset_confirmation.tscn"
)

var _failures: Array[String] = []
var _reset_started_count := 0
var _reset_completed_count := 0
var _entry_completed := false
var _entry_failure := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_test_save()
	var original_save_path := ProgressionAutosave.save_path
	var original_collection := CollectionSystem.get_save_data()
	var original_move_learning := MoveLearningSystem.get_save_data()
	var original_economy := EconomySystem.get_save_data()
	var original_inventory := InventorySystem.get_save_data()
	var original_challenges := ChallengeProgressionSystem.get_save_data()
	var original_starter_id := ProgressionAutosave.get_starter_pokemon_id()
	var original_movement := GameInstance.is_player_movement_enabled()
	ProgressionAutosave.save_path = TEST_SAVE_PATH
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(false)
	ProgressionAutosave.progress_reset_started.connect(_on_reset_started)
	ProgressionAutosave.progress_reset_completed.connect(_on_reset_completed)
	ProgressionAutosave.startup_entry_completed.connect(_on_entry_completed)
	ProgressionAutosave.startup_entry_failed.connect(_on_entry_failed)
	GameInstance.scene_transfer_finished.connect(
		ProgressionAutosave._on_scene_transfer_finished
	)
	GameInstance.scene_transfer_failed.connect(
		ProgressionAutosave._on_scene_transfer_failed
	)

	var scene_anchor := Node.new()
	scene_anchor.name = "ResetSceneAnchor"
	get_tree().root.add_child(scene_anchor)
	get_tree().current_scene = scene_anchor
	ProgressionAutosave._startup_in_progress = false
	ProgressionAutosave._profile_initialization_pending = false
	ProgressionAutosave._reset_in_progress = false
	_check(
		ProgressionAutosave.save_now(true) and FileAccess.file_exists(TEST_SAVE_PATH),
		"The reset-restart fixture should begin with a real checkpoint."
	)

	var reset := RESET_SCENE.instantiate() as ProgressResetConfirmation
	add_child(reset)
	reset.confirmed.connect(
		func() -> void:
			reset.visible = false
			ProgressionAutosave.reset_all_progress()
	)
	reset.open()
	_check(
		reset.press_yes()
		and reset.get_warning_step() == 2
		and FileAccess.file_exists(TEST_SAVE_PATH)
		and _reset_started_count == 0,
		"The first Yes must not erase progress."
	)
	_check(
		reset.press_yes()
		and reset.get_warning_step() == 3
		and FileAccess.file_exists(TEST_SAVE_PATH)
		and _reset_started_count == 0,
		"The second Yes must not erase progress."
	)
	_check(
		reset.press_yes(),
		"The third Yes should accept the destructive reset."
	)
	for frame in 600:
		if (
			get_tree().current_scene != null
			and get_tree().current_scene.scene_file_path
			== ProgressionAutosaveService.STARTUP_SCENE_PATH
		):
			break
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var startup := get_tree().current_scene as StartupController
	_check(
		_reset_started_count == 1
		and _reset_completed_count == 0
		and not FileAccess.file_exists(TEST_SAVE_PATH)
		and startup != null
		and ProgressionAutosave.is_profile_initialization_pending(),
		"Only the third Yes should erase once and enter unsaved startup onboarding."
	)
	_check(
		startup._intro_template != null
		and startup._intro_template.message_label.text
		== StartupController.INTRO_MESSAGES[0]
		and StarterSelectionSystem.get_active_ui() == null,
		"A confirmed in-game reset should replay the complete intro before the picker."
	)
	for index in StartupController.INTRO_MESSAGES.size():
		startup._advance_intro()
		await get_tree().process_frame
	_check(
		StarterSelectionSystem.get_active_ui() != null
		and not FileAccess.file_exists(TEST_SAVE_PATH),
		"Completing the reset intro should show the picker without saving yet."
	)
	StarterSelectionSystem.choose_starter(252)
	for frame in 600:
		if _entry_completed or not _entry_failure.is_empty():
			break
		await get_tree().process_frame
	var party := CollectionSystem.get_party()
	_check(
		_entry_failure.is_empty()
		and _entry_completed
		and _reset_completed_count == 1
		and FileAccess.file_exists(TEST_SAVE_PATH)
		and get_tree().current_scene.scene_file_path
		== ProgressionAutosaveService.FIRST_GAMEPLAY_SCENE_PATH
		and party.size() == 1
		and int(party[0].get("pokemonId", 0)) == 252,
		"The new checkpoint and cloud-reset completion should occur once after station arrival."
	)

	MoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(original_collection)
	MoveLearningSystem.load_save_data(original_move_learning)
	MoveLearningSystem.finish_save_restore()
	EconomySystem.load_save_data(original_economy)
	InventorySystem.load_save_data(original_inventory)
	ChallengeProgressionSystem.load_save_data(original_challenges)
	StarterSelectionSystem.mark_profile_loaded(original_starter_id)
	ProgressionAutosave._starter_pokemon_id = original_starter_id
	ProgressionAutosave._startup_in_progress = false
	ProgressionAutosave._profile_initialization_pending = false
	ProgressionAutosave.save_path = original_save_path
	GameInstance.set_player_movement_enabled(original_movement)
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)
	GameInstance.scene_transfer_finished.disconnect(
		ProgressionAutosave._on_scene_transfer_finished
	)
	GameInstance.scene_transfer_failed.disconnect(
		ProgressionAutosave._on_scene_transfer_failed
	)
	_remove_test_save()

	if _failures.is_empty():
		print(
			"Reset-restart smoke test passed: three Yes presses reset once, replayed "
			+ "all onboarding, and checkpointed only after the new station arrival."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Reset-restart smoke test failed: %s" % failure)
	get_tree().quit(1)


func _on_reset_started() -> void:
	_reset_started_count += 1


func _on_reset_completed(_starter_pokemon_id: int) -> void:
	_reset_completed_count += 1


func _on_entry_completed(_destination_scene_path: String, _used_fallback: bool) -> void:
	_entry_completed = true


func _on_entry_failed(message: String) -> void:
	_entry_failure = message


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
