extends Node

const TEST_SAVE_PATH := "user://pfr_startup_flow_smoke_test.json"
const StartupScene: PackedScene = preload(
	"res://game/startup/startup_controller.tscn"
)
const ROUTE_ZERO_PATH := (
	"res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn"
)
const EXPECTED_INTRO: Array[String] = [
	"Welcome, young Trainer. I’m Professor Cypress.",
	"Pokémon share our homes, our cities, and the wild places beyond.",
	"A few choose to travel beside us. We call them partners.",
	"Travel the region, earn Gym Badges, and challenge the Pokémon League.",
	"Dream of becoming Champion—but remember who stands beside you.",
	"Our region is changing. Kindness and friendship still matter.",
	"Your journey begins in New Bouffalant City.",
	"Choose your first partner. The road is waiting.",
]

var _failures: Array[String] = []


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
	MusicManager.call("_handle_scene_path", ROUTE_ZERO_PATH)
	await get_tree().create_timer(
		MusicManager.CROSSFADE_SECONDS + 0.12,
		true,
		false,
		true
	).timeout
	_check(
		MusicManager.get_current_track_id() == MusicManager.ROUTE_TRACK_ID,
		"The startup music fixture should begin on the route theme."
	)

	# A valid schema-6 profile without a usable location still exposes Continue
	# and advertises the safe Stretchman-room fallback.
	_check(ProgressionAutosave.save_now(true), "The valid startup fixture should save.")
	var startup := await _instantiate_startup()
	var continue_button := startup.find_child("Continue", true, false) as Button
	var save_status := startup.find_child("SaveStatus", true, false) as Label
	_check(
		continue_button != null
		and continue_button.visible
		and "Stretchman’s room" in save_status.text,
		"A valid save with no location should offer Continue through the station fallback."
	)
	await get_tree().create_timer(
		MusicManager.CROSSFADE_SECONDS + 0.12,
		true,
		false,
		true
	).timeout
	_check(
		MusicManager.get_current_track_id() == MusicManager.MAIN_TRACK_ID
		and _main_theme_player_is_audible(),
		"Opening the main menu should settle on the audible main theme."
	)
	await _dispose_startup(startup)

	# Invalid data is never offered as Continue and can only be replaced through
	# the same shared three-Yes sequence used by the in-game menu.
	_write_text(TEST_SAVE_PATH, "{ definitely not valid json")
	startup = await _instantiate_startup()
	continue_button = startup.find_child("Continue", true, false) as Button
	save_status = startup.find_child("SaveStatus", true, false) as Label
	var new_game := startup.find_child("NewGame", true, false) as Button
	_check(
		continue_button != null
		and not continue_button.visible
		and "SAVE DATA ERROR" in save_status.text,
		"An invalid save should show an error and hide Continue."
	)
	new_game.pressed.emit()
	var reset := startup.find_child(
		"ProgressResetConfirmation", true, false
	) as ProgressResetConfirmation
	_check(
		reset != null and reset.visible and reset.get_warning_step() == 1,
		"Replacing invalid data should open the shared reset sequence."
	)
	reset.cancel()
	_check(
		FileAccess.file_exists(TEST_SAVE_PATH),
		"Canceling invalid-save replacement should preserve the file."
	)
	await _dispose_startup(startup)

	# A true first launch renders an isolated, non-gameplay Route 0 and proceeds
	# through exactly the supplied Cypress dialog before showing the picker.
	_remove_test_save()
	startup = await _instantiate_startup()
	continue_button = startup.find_child("Continue", true, false) as Button
	new_game = startup.find_child("NewGame", true, false) as Button
	var quit_button := startup.find_child("Quit", true, false) as Button
	_check(
		continue_button != null and not continue_button.visible,
		"First launch should omit Continue."
	)
	_check(
		quit_button != null or OS.has_feature("web") or OS.has_feature("mobile"),
		"Desktop startup should expose Quit while Web and mobile omit it."
	)
	_check(
		startup.is_menu_backdrop_rendering(),
		"The main menu should actively render its isolated Route 0 viewport."
	)
	var route := startup.get_route_backdrop()
	var grass_nodes := (
		route.find_children("*", "TallGrassEncounterZone", true, false)
		if route != null
		else []
	)
	var grass_is_inert := grass_nodes.size() == 5
	for value: Node in grass_nodes:
		var grass := value as TallGrassEncounterZone
		grass_is_inert = (
			grass_is_inert
			and not grass.enabled
			and not grass.start_battle_automatically
			and grass.get_node_or_null(^"TallGrassVisuals") != null
		)
	_check(
		route != null
		and route.get_node_or_null(^"Player") == null
		and route.get_node_or_null(^"Gameplay/Actors") == null
		and route.get_node_or_null(^"Gameplay/Transitions") == null
		and grass_is_inert,
		"The backdrop should keep five visible grass patches but no player, trainers, or transitions."
	)
	var camera_curve := startup.get_camera_curve()
	_check(
		camera_curve != null
		and camera_curve.closed
		and camera_curve.point_count == StartupController.CAMERA_POINTS.size()
		and is_equal_approx(StartupController.CAMERA_CIRCUIT_SECONDS, 60.0),
		"The live camera should follow a smoothed, closed 60-second circuit."
	)
	_check(
		startup.find_children("*", "AudioStreamPlayer", true, false).is_empty()
		and startup.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(),
		"Startup should add no music or other audio player."
	)

	new_game.pressed.emit()
	await get_tree().process_frame
	_check(
		ProgressionAutosave.is_profile_initialization_pending()
		and not startup.is_menu_backdrop_rendering(),
		"New Game should prepare an unsaved profile and stop the menu backdrop."
	)
	_check(
		startup.get_intro_messages() == EXPECTED_INTRO,
		"Professor Cypress should deliver the exact eight requested messages."
	)
	var cypress_art := startup.find_child(
		"ProfessorCypressIllustration", true, false
	) as TextureRect
	_check(
		cypress_art != null
		and cypress_art.is_visible_in_tree()
		and cypress_art.texture != null,
		"The prototype Cypress illustration should sit behind the intro dialog."
	)
	for index in EXPECTED_INTRO.size():
		var template := startup._intro_template as UITemplate
		_check(
			template != null
			and template.message_label.text == EXPECTED_INTRO[index]
			and template.speaker_label.text == "Professor Cypress"
			and template.action_button.text.begins_with("Next"),
			"Intro line %d should use the existing dialog UI and Next action." % (index + 1)
		)
		startup._advance_intro()
		await get_tree().process_frame
	_check(
		StarterSelectionSystem.is_selection_required()
		and StarterSelectionSystem.get_active_ui() != null,
		"The eighth intro message should hand off to the existing starter picker."
	)
	GameInstance.scene_transfer_failed.connect(
		ProgressionAutosave._on_scene_transfer_failed
	)
	_check(
		StarterSelectionSystem.choose_starter(4),
		"The retry fixture should create its starter once."
	)
	ProgressionAutosave._startup_retry_scene_path = "res://missing/startup_retry_fixture.tscn"
	await get_tree().process_frame
	await get_tree().process_frame
	var retry_button := startup.find_child("RetryEntry", true, false) as Button
	_check(
		retry_button != null
		and retry_button.visible
		and CollectionSystem.get_collection().size() == 1
		and int(CollectionSystem.get_collection()[0].get("pokemonId", 0)) == 4
		and not StarterSelectionSystem.is_selection_required(),
		"A failed gameplay load should offer Retry without creating another starter."
	)
	retry_button.pressed.emit()
	await get_tree().process_frame
	_check(
		CollectionSystem.get_collection().size() == 1
		and int(CollectionSystem.get_collection()[0].get("pokemonId", 0)) == 4,
		"Retrying a failed scene should retain the existing selected starter."
	)
	GameInstance.scene_transfer_failed.disconnect(
		ProgressionAutosave._on_scene_transfer_failed
	)

	StarterSelectionSystem.reset_for_testing()
	await _dispose_startup(startup)
	_restore_state(
		original_collection,
		original_move_learning,
		original_economy,
		original_inventory,
		original_challenges,
		original_starter_id,
		original_movement
	)
	ProgressionAutosave.save_path = original_save_path
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)
	_remove_test_save()

	if _failures.is_empty():
		print(
			"Startup-flow smoke test passed: save visibility, invalid replacement, "
			+ "main-theme entry, isolated Route 0 camera, Cypress art, and exact "
			+ "eight-line intro verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Startup-flow smoke test failed: %s" % failure)
	get_tree().quit(1)


func _instantiate_startup() -> StartupController:
	var startup := StartupScene.instantiate() as StartupController
	add_child(startup)
	await get_tree().process_frame
	await get_tree().process_frame
	return startup


func _dispose_startup(startup: StartupController) -> void:
	if is_instance_valid(startup):
		startup.queue_free()
	await get_tree().process_frame
	ProgressionAutosave._startup_in_progress = false
	ProgressionAutosave._startup_intro_pending = false
	ProgressionAutosave._startup_entry_mode = ProgressionAutosaveService.StartupEntryMode.NONE
	ProgressionAutosave._startup_entry_error = ""
	ProgressionAutosave._profile_initialization_pending = false
	ProgressionAutosave._reset_in_progress = false
	GameInstance.set_player_movement_enabled(true)


func _restore_state(
	collection: Array,
	move_learning: Dictionary,
	economy: Dictionary,
	inventory: Dictionary,
	challenges: Dictionary,
	starter_id: int,
	movement_enabled: bool
) -> void:
	MoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(collection)
	MoveLearningSystem.load_save_data(move_learning)
	MoveLearningSystem.finish_save_restore()
	EconomySystem.load_save_data(economy)
	InventorySystem.load_save_data(inventory)
	ChallengeProgressionSystem.load_save_data(challenges)
	StarterSelectionSystem.mark_profile_loaded(starter_id)
	ProgressionAutosave._starter_pokemon_id = starter_id
	GameInstance.set_player_movement_enabled(movement_enabled)


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)
		file.flush()


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _main_theme_player_is_audible() -> bool:
	for child in MusicManager.get_children():
		if child is not AudioStreamPlayer:
			continue
		var player := child as AudioStreamPlayer
		if (
			player.playing
			and player.stream != null
			and player.stream.resource_path == MusicManager.MAIN_TRACK_PATH
			and is_equal_approx(player.volume_db, MusicManager.MAIN_GAIN_DB)
		):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
