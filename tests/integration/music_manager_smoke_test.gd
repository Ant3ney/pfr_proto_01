extends Node

const ROUTE_PATH_TEMPLATE := (
	"res://game/world/levels/standalone_areas/routes/route_%02d/route_%02d.tscn"
)
const CITY_PATH := (
	"res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
)
const POKEMON_CENTER_PATH := (
	"res://game/world/levels/new_bouffalant_city/interiors/"
	+ "pokemon_center/pokemon_center_interior.tscn"
)
const MAIN_SCENE_PATHS: Array[String] = [
	"res://game/startup/startup_controller.tscn",
	CITY_PATH,
	"res://game/world/levels/new_bouffalant_city/interiors/city_hall_interior.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/garage_workshop.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/gatehouse_interior.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/miare_station_concourse.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/museum_gallery.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/north_tenant_lobby.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_annex.tscn",
	POKEMON_CENTER_PATH,
	"res://game/world/levels/new_bouffalant_city/interiors/rouge_tower_lobby.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/west_tenant_lobby.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/shared/ambient_roaming_navigation.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/shared/classic_city_room.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/shared/classic_interior_door.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/shared/classic_interior_lighting.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_01/gym_01.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_02/gym_02.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_03/gym_03.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_04/gym_04.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_05/gym_05.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_06/gym_06.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_07/gym_07.tscn",
	"res://game/world/levels/standalone_areas/gyms/gym_08/gym_08.tscn",
	"res://game/world/levels/standalone_areas/champion/champion_challenge/champion_challenge.tscn",
	"res://tests/fixtures/unrecognized_scene.tscn",
]
const BATTLE_SCENE_PATHS: Array[String] = [
	"res://game/battle/scenes/battle_scene.tscn",
	"res://game/battle/scenes/backpacker_battle_scene.tscn",
	"res://game/battle/scenes/businessman_battle_scene.tscn",
	"res://game/battle/scenes/challenge_battle.tscn",
	"res://game/battle/scenes/delivery_worker_battle_scene.tscn",
	"res://game/battle/scenes/jogger_battle_scene.tscn",
	"res://game/battle/scenes/kyle_battle_scene.tscn",
	"res://game/battle/scenes/police_officer_battle_scene.tscn",
	"res://game/battle/scenes/route_0_wild_battle_scene.tscn",
	"res://game/battle/scenes/tourist_battle_scene.tscn",
]

var _failures: Array[String] = []
var _changed_tracks: Array[StringName] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MusicManager.track_changed.connect(_on_track_changed)
	await get_tree().process_frame
	_verify_resolution()
	_verify_player_and_stream_configuration()

	var route_zero_path := ROUTE_PATH_TEMPLATE % [0, 0]
	var route_one_path := ROUTE_PATH_TEMPLATE % [1, 1]
	MusicManager.call("_handle_scene_path", route_zero_path)
	await _wait_for_crossfade()
	var route_player := _current_player()
	var position_before_transfer := MusicManager.get_current_playback_position()
	MusicManager.call("_handle_scene_path", route_one_path)
	var position_after_transfer := MusicManager.get_current_playback_position()
	_check(
		MusicManager.get_current_track_id() == MusicManager.ROUTE_TRACK_ID
		and _current_player() == route_player
		and position_after_transfer + 0.03 >= position_before_transfer
		and absf(position_after_transfer - position_before_transfer) < 0.12,
		"A Route 0-to-Route 1 transfer should keep the same player and position."
	)

	var interrupted_route_position := MusicManager.get_current_playback_position()
	GameInstance.battle_starting.emit({"fixture": "same-frame-cut"})
	_check(
		MusicManager.get_current_track_id() == MusicManager.BATTLE_TRACK_ID
		and MusicManager.get_current_playback_position() < 0.12
		and _playing_players().size() == 1,
		"battle_starting should cut to battle position zero with no outgoing player audible."
	)
	_assert_current_gain(MusicManager.BATTLE_GAIN_DB, "battle")

	await get_tree().create_timer(0.08, true, false, true).timeout
	GameInstance.battle_start_failed.emit("Expected music smoke-test failure.")
	var failed_start_resume_position := MusicManager.get_current_playback_position()
	_check(
		MusicManager.get_current_track_id() == MusicManager.ROUTE_TRACK_ID
		and absf(failed_start_resume_position - interrupted_route_position) < 0.15
		and _playing_players().size() == 2,
		"battle_start_failed should crossfade to the interrupted route position."
	)
	await _wait_for_crossfade()
	_assert_settled_track(
		MusicManager.ROUTE_TRACK_ID,
		MusicManager.ROUTE_GAIN_DB,
		"failed-start route recovery"
	)

	var successful_resume_position := MusicManager.get_current_playback_position()
	GameInstance.battle_starting.emit({"fixture": "same-track-return"})
	await get_tree().create_timer(0.08, true, false, true).timeout
	MusicManager.call("_handle_scene_path", route_zero_path)
	_check(
		MusicManager.get_current_track_id() == MusicManager.ROUTE_TRACK_ID
		and absf(
			MusicManager.get_current_playback_position()
			- successful_resume_position
		) < 0.15,
		"A battle return to another route should resume the interrupted route position."
	)
	await _wait_for_crossfade()

	GameInstance.battle_starting.emit({"fixture": "different-track-return"})
	await get_tree().create_timer(0.08, true, false, true).timeout
	MusicManager.call("_handle_scene_path", POKEMON_CENTER_PATH)
	_check(
		MusicManager.get_current_track_id() == MusicManager.MAIN_TRACK_ID
		and MusicManager.get_current_playback_position() < 0.12,
		"A route loss destination should start the main theme from zero."
	)
	await _wait_for_crossfade()
	_assert_settled_track(
		MusicManager.MAIN_TRACK_ID,
		MusicManager.MAIN_GAIN_DB,
		"different-track battle return"
	)

	# Superseding requests reuse whichever of the two players is still relevant;
	# no stale fade callback can stop the final target.
	MusicManager.call("_handle_scene_path", route_zero_path)
	MusicManager.call("_handle_scene_path", "res://unknown/rapid-main.tscn")
	MusicManager.call("_handle_scene_path", route_one_path)
	await _wait_for_crossfade()
	_assert_settled_track(
		MusicManager.ROUTE_TRACK_ID,
		MusicManager.ROUTE_GAIN_DB,
		"rapid transition cancellation"
	)

	_check(
		MusicManager.BATTLE_TRACK_ID in _changed_tracks
		and MusicManager.MAIN_TRACK_ID in _changed_tracks
		and MusicManager.ROUTE_TRACK_ID in _changed_tracks,
		"track_changed should report each selected logical track."
	)

	if _failures.is_empty():
		print(
			"Music-manager smoke test passed: 41 routes, main/battle scene "
			+ "fallbacks, looping, gains, continuity, battle resume, and rapid "
			+ "crossfade cancellation verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Music-manager smoke test failed: %s" % failure)
	get_tree().quit(1)


func _verify_resolution() -> void:
	for route_index in 41:
		var route_path := ROUTE_PATH_TEMPLATE % [route_index, route_index]
		_check(
			ResourceLoader.exists(route_path, "PackedScene")
			and MusicManager.resolve_track_for_scene(route_path)
			== MusicManager.ROUTE_TRACK_ID,
			"Route %d should exist and resolve to route music." % route_index
		)
	for scene_path in MAIN_SCENE_PATHS:
		_check(
			MusicManager.resolve_track_for_scene(scene_path)
			== MusicManager.MAIN_TRACK_ID,
			"Main-theme scene should resolve correctly: %s" % scene_path
		)
	_check(
		MusicManager.resolve_track_for_scene(
			"res://game/world/levels/standalone_areas/routes/route_41/route_41.tscn"
		) == MusicManager.MAIN_TRACK_ID,
		"An out-of-range route-like path should use the main fallback."
	)
	_check(
		MusicManager.resolve_track_for_scene(
			"res://game/world/levels/standalone_areas/routes/route_00_Real/route_00_Real.tscn"
		) == MusicManager.MAIN_TRACK_ID,
		"The unfinished Route 0 visual reference should use the main fallback."
	)
	for scene_path in BATTLE_SCENE_PATHS:
		_check(
			ResourceLoader.exists(scene_path, "PackedScene")
			and MusicManager.resolve_track_for_scene(scene_path)
			== MusicManager.BATTLE_TRACK_ID,
			"Battle scene should exist and resolve correctly: %s" % scene_path
		)


func _verify_player_and_stream_configuration() -> void:
	_check(
		_audio_players().size() == 2,
		"MusicManager should own exactly two persistent AudioStreamPlayers."
	)
	var expectations := {
		MusicManager.MAIN_TRACK_PATH: MusicManager.MAIN_GAIN_DB,
		MusicManager.ROUTE_TRACK_PATH: MusicManager.ROUTE_GAIN_DB,
		MusicManager.BATTLE_TRACK_PATH: MusicManager.BATTLE_GAIN_DB,
	}
	for stream_path: String in expectations:
		var stream := load(stream_path) as AudioStreamOggVorbis
		_check(stream != null, "Music stream should load: %s" % stream_path)
		if stream != null:
			_check(
				stream.loop and is_zero_approx(stream.loop_offset),
				"Music stream should loop from offset zero: %s" % stream_path
			)
	_check(
		is_equal_approx(float(expectations[MusicManager.MAIN_TRACK_PATH]), 10.3)
		and is_equal_approx(float(expectations[MusicManager.ROUTE_TRACK_PATH]), -0.6)
		and is_equal_approx(float(expectations[MusicManager.BATTLE_TRACK_PATH]), -8.3),
		"Measured per-track gains should remain +10.3, -0.6, and -8.3 dB."
	)


func _wait_for_crossfade() -> void:
	await get_tree().create_timer(
		MusicManager.CROSSFADE_SECONDS + 0.12,
		true,
		false,
		true
	).timeout


func _assert_settled_track(
	track_id: StringName,
	expected_gain: float,
	label: String
) -> void:
	_check(
		MusicManager.get_current_track_id() == track_id
		and _playing_players().size() == 1,
		"%s should settle with only its final player active." % label
	)
	_assert_current_gain(expected_gain, label)


func _assert_current_gain(expected_gain: float, label: String) -> void:
	var player := _current_player()
	_check(
		player != null and is_equal_approx(player.volume_db, expected_gain),
		"%s should apply its measured playback gain." % label
	)


func _audio_players() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for child in MusicManager.get_children():
		if child is AudioStreamPlayer:
			result.append(child as AudioStreamPlayer)
	return result


func _playing_players() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for player in _audio_players():
		if player.playing:
			result.append(player)
	return result


func _current_player() -> AudioStreamPlayer:
	var expected_path := ""
	match MusicManager.get_current_track_id():
		MusicManager.MAIN_TRACK_ID:
			expected_path = MusicManager.MAIN_TRACK_PATH
		MusicManager.ROUTE_TRACK_ID:
			expected_path = MusicManager.ROUTE_TRACK_PATH
		MusicManager.BATTLE_TRACK_ID:
			expected_path = MusicManager.BATTLE_TRACK_PATH
	for player in _audio_players():
		if player.stream != null and player.stream.resource_path == expected_path:
			return player
	return null


func _on_track_changed(track_id: StringName) -> void:
	_changed_tracks.append(track_id)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
