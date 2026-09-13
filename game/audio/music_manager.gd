extends Node

## Persistent scene-aware music playback. Scene changes use two players for an
## equal-power crossfade, while battle launch deliberately cuts straight to the
## battle track so its first beat lands on battle_starting.

signal track_changed(track_id: StringName)

const MAIN_TRACK_ID: StringName = &"main"
const ROUTE_TRACK_ID: StringName = &"route"
const BATTLE_TRACK_ID: StringName = &"battle"

const MAIN_TRACK_PATH := "res://audio/pfr-main-theme.ogg"
const ROUTE_TRACK_PATH := "res://audio/tribly_town_theme.ogg"
const BATTLE_TRACK_PATH := "res://audio/battle_theme.ogg"

const MAIN_GAIN_DB := 10.3
const ROUTE_GAIN_DB := -0.6
const BATTLE_GAIN_DB := -8.3
const CROSSFADE_SECONDS := 0.5
const SILENCE_DB := -80.0

const ROUTE_SCENE_PREFIX := (
	"res://game/world/levels/standalone_areas/routes/"
)
const BATTLE_SCENE_PREFIX := "res://game/battle/scenes/"

const TRACK_STREAMS: Dictionary = {
	MAIN_TRACK_ID: preload(MAIN_TRACK_PATH),
	ROUTE_TRACK_ID: preload(ROUTE_TRACK_PATH),
	BATTLE_TRACK_ID: preload(BATTLE_TRACK_PATH),
}
const TRACK_GAINS_DB: Dictionary = {
	MAIN_TRACK_ID: MAIN_GAIN_DB,
	ROUTE_TRACK_ID: ROUTE_GAIN_DB,
	BATTLE_TRACK_ID: BATTLE_GAIN_DB,
}

var _players: Array[AudioStreamPlayer] = []
var _player_track_ids: Array[StringName] = [&"", &""]
var _current_track_id: StringName = &""
var _current_player_index := -1

var _fade_active := false
var _fade_elapsed := 0.0
var _fade_from_index := -1
var _fade_to_index := -1
var _fade_start_angle := 0.0
var _fade_start_energy := 1.0

var _battle_active := false
var _has_interrupted_overworld := false
var _interrupted_track_id: StringName = &""
var _interrupted_playback_position := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_players()
	set_process(false)
	get_tree().scene_changed.connect(_on_scene_changed)
	GameInstance.battle_starting.connect(_on_battle_starting)
	GameInstance.battle_start_failed.connect(_on_battle_start_failed)
	_sync_to_current_scene.call_deferred()


func _process(delta: float) -> void:
	if not _fade_active:
		set_process(false)
		return
	_fade_elapsed += maxf(delta, 0.0)
	var ratio := minf(_fade_elapsed / CROSSFADE_SECONDS, 1.0)
	var angle := lerpf(_fade_start_angle, PI * 0.5, ratio)
	var energy := lerpf(_fade_start_energy, 1.0, ratio)
	_set_player_amplitude(_fade_from_index, cos(angle) * energy)
	_set_player_amplitude(_fade_to_index, sin(angle) * energy)
	if ratio >= 1.0:
		_finish_crossfade()


func _exit_tree() -> void:
	# Release active Ogg playback before the autoload's preloaded stream
	# constants are torn down during engine shutdown.
	for player in _players:
		player.stop()
		player.stream = null
	_players.clear()
	_player_track_ids = [&"", &""]


## Returns the stable logical ID selected for the current scene.
func get_current_track_id() -> StringName:
	return _current_track_id


## Returns the position of the selected player, including while it fades in.
func get_current_playback_position() -> float:
	if not _is_player_index_valid(_current_player_index):
		return 0.0
	var player := _players[_current_player_index]
	return player.get_playback_position() if player.playing else 0.0


## Guarantees that startup/menu presentation uses the main theme. Repeating the
## request while the main theme is already playing preserves its player and
## playback position through the ordinary same-track continuity rule.
func ensure_main_menu_theme() -> void:
	if _battle_active:
		_resume_after_battle(MAIN_TRACK_ID)
		return
	_crossfade_to(MAIN_TRACK_ID, 0.0)


## Resolves a scene Node, resource path, or the current scene when omitted.
## Unknown paths intentionally use the main theme.
func resolve_track_for_scene(scene: Variant = null) -> StringName:
	var scene_path := _scene_path_from(scene)
	if _is_route_scene_path(scene_path):
		return ROUTE_TRACK_ID
	if (
		scene_path.begins_with(BATTLE_SCENE_PREFIX)
		and scene_path.ends_with(".tscn")
	):
		return BATTLE_TRACK_ID
	return MAIN_TRACK_ID


func _create_players() -> void:
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%s" % char(65 + index)
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.volume_db = SILENCE_DB
		add_child(player)
		_players.append(player)


func _sync_to_current_scene() -> void:
	var scene := get_tree().current_scene
	_handle_scene_path(scene.scene_file_path if scene != null else "")


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	_handle_scene_path(scene.scene_file_path if scene != null else "")


func _handle_scene_path(scene_path: String) -> void:
	var destination_track := resolve_track_for_scene(scene_path)
	if _battle_active:
		if destination_track == BATTLE_TRACK_ID:
			return
		_resume_after_battle(destination_track)
		return
	_crossfade_to(destination_track, 0.0)


func _on_battle_starting(_battle_data: Dictionary) -> void:
	_clear_interrupted_overworld()
	var source_track := _current_track_id
	if source_track.is_empty() or source_track == BATTLE_TRACK_ID:
		source_track = resolve_track_for_scene()
	if source_track != BATTLE_TRACK_ID:
		_has_interrupted_overworld = true
		_interrupted_track_id = source_track
		_interrupted_playback_position = (
			get_current_playback_position()
			if source_track == _current_track_id
			else 0.0
		)
	_battle_active = true
	_start_track_immediately(BATTLE_TRACK_ID, 0.0)


func _on_battle_start_failed(_message: String) -> void:
	if not _battle_active:
		return
	_battle_active = false
	if _has_interrupted_overworld:
		var track_id := _interrupted_track_id
		var playback_position := _interrupted_playback_position
		_clear_interrupted_overworld()
		_crossfade_to(track_id, playback_position)
		return
	_clear_interrupted_overworld()
	var scene := get_tree().current_scene
	_crossfade_to(resolve_track_for_scene(scene), 0.0)


func _resume_after_battle(destination_track: StringName) -> void:
	_battle_active = false
	var playback_position := 0.0
	if (
		_has_interrupted_overworld
		and destination_track == _interrupted_track_id
	):
		playback_position = _interrupted_playback_position
	_clear_interrupted_overworld()
	_crossfade_to(destination_track, playback_position)


func _start_track_immediately(
	track_id: StringName,
	playback_position: float
) -> void:
	var previous_track := _current_track_id
	_cancel_crossfade()
	var player_index := _current_player_index
	if not _is_player_index_valid(player_index):
		player_index = 0
	for index in _players.size():
		_stop_player(index)
	_start_player(player_index, track_id, playback_position, 1.0)
	_current_player_index = player_index
	_current_track_id = track_id
	_emit_track_changed(previous_track, track_id)


func _crossfade_to(
	track_id: StringName,
	playback_position: float
) -> void:
	if (
		track_id == _current_track_id
		and _is_player_index_valid(_current_player_index)
		and _players[_current_player_index].playing
	):
		return

	var previous_track := _current_track_id
	var existing_target := _find_playing_track(track_id)
	if existing_target >= 0:
		var outgoing := 1 - existing_target
		if not _players[outgoing].playing:
			_stop_player(outgoing)
			_set_player_amplitude(existing_target, 1.0)
			_current_player_index = existing_target
			_current_track_id = track_id
			_cancel_crossfade()
			_emit_track_changed(previous_track, track_id)
			return
		var outgoing_amplitude := _get_player_amplitude(outgoing)
		var incoming_amplitude := _get_player_amplitude(existing_target)
		_begin_crossfade(
			outgoing,
			existing_target,
			atan2(incoming_amplitude, outgoing_amplitude),
			sqrt(
				outgoing_amplitude * outgoing_amplitude
				+ incoming_amplitude * incoming_amplitude
			)
		)
		_current_player_index = existing_target
		_current_track_id = track_id
		_emit_track_changed(previous_track, track_id)
		return

	var outgoing_index := _find_loudest_playing_player()
	if outgoing_index < 0:
		_start_track_immediately(track_id, playback_position)
		return
	var incoming_index := 1 - outgoing_index
	var outgoing_amplitude := _get_player_amplitude(outgoing_index)
	_stop_player(incoming_index)
	_start_player(incoming_index, track_id, playback_position, 0.0)
	_begin_crossfade(
		outgoing_index,
		incoming_index,
		0.0,
		maxf(outgoing_amplitude, 0.001)
	)
	_current_player_index = incoming_index
	_current_track_id = track_id
	_emit_track_changed(previous_track, track_id)


func _begin_crossfade(
	from_index: int,
	to_index: int,
	start_angle: float,
	start_energy: float
) -> void:
	_fade_active = true
	_fade_elapsed = 0.0
	_fade_from_index = from_index
	_fade_to_index = to_index
	_fade_start_angle = clampf(start_angle, 0.0, PI * 0.5)
	_fade_start_energy = clampf(start_energy, 0.001, 1.0)
	set_process(true)


func _finish_crossfade() -> void:
	var outgoing_index := _fade_from_index
	var incoming_index := _fade_to_index
	_cancel_crossfade()
	_stop_player(outgoing_index)
	_set_player_amplitude(incoming_index, 1.0)
	_current_player_index = incoming_index


func _cancel_crossfade() -> void:
	_fade_active = false
	_fade_elapsed = 0.0
	_fade_from_index = -1
	_fade_to_index = -1
	_fade_start_angle = 0.0
	_fade_start_energy = 1.0
	set_process(false)


func _start_player(
	player_index: int,
	track_id: StringName,
	playback_position: float,
	amplitude: float
) -> void:
	var player := _players[player_index]
	player.stream = TRACK_STREAMS.get(track_id) as AudioStream
	_player_track_ids[player_index] = track_id
	_set_player_amplitude(player_index, amplitude)
	player.play(maxf(playback_position, 0.0))


func _stop_player(player_index: int) -> void:
	if not _is_player_index_valid(player_index):
		return
	var player := _players[player_index]
	player.stop()
	player.volume_db = SILENCE_DB
	player.stream = null
	_player_track_ids[player_index] = &""


func _set_player_amplitude(player_index: int, amplitude: float) -> void:
	if not _is_player_index_valid(player_index):
		return
	var track_id := _player_track_ids[player_index]
	if track_id.is_empty() or amplitude <= 0.0001:
		_players[player_index].volume_db = SILENCE_DB
		return
	_players[player_index].volume_db = (
		_gain_for_track(track_id) + linear_to_db(amplitude)
	)


func _get_player_amplitude(player_index: int) -> float:
	if (
		not _is_player_index_valid(player_index)
		or not _players[player_index].playing
		or _player_track_ids[player_index].is_empty()
	):
		return 0.0
	return db_to_linear(
		_players[player_index].volume_db
		- _gain_for_track(_player_track_ids[player_index])
	)


func _find_playing_track(track_id: StringName) -> int:
	for index in _players.size():
		if _players[index].playing and _player_track_ids[index] == track_id:
			return index
	return -1


func _find_loudest_playing_player() -> int:
	var loudest_index := -1
	var loudest_amplitude := 0.0
	for index in _players.size():
		var amplitude := _get_player_amplitude(index)
		if amplitude > loudest_amplitude:
			loudest_index = index
			loudest_amplitude = amplitude
	return loudest_index


func _gain_for_track(track_id: StringName) -> float:
	return float(TRACK_GAINS_DB.get(track_id, 0.0))


func _scene_path_from(scene: Variant) -> String:
	if scene == null:
		var current_scene := get_tree().current_scene
		return current_scene.scene_file_path if current_scene != null else ""
	if scene is Node:
		return (scene as Node).scene_file_path
	return String(scene).strip_edges()


func _is_route_scene_path(scene_path: String) -> bool:
	if not scene_path.begins_with(ROUTE_SCENE_PREFIX):
		return false
	var relative_path := scene_path.trim_prefix(ROUTE_SCENE_PREFIX)
	var segments := relative_path.split("/", false)
	if segments.size() != 2:
		return false
	var route_id := String(segments[0])
	if String(segments[1]) != "%s.tscn" % route_id:
		return false
	if not route_id.begins_with("route_"):
		return false
	var route_number := route_id.trim_prefix("route_")
	if route_number.length() != 2 or not route_number.is_valid_int():
		return false
	var route_index := int(route_number)
	return (
		route_index >= 0
		and route_index <= 40
		and route_id == "route_%02d" % route_index
	)


func _is_player_index_valid(player_index: int) -> bool:
	return player_index >= 0 and player_index < _players.size()


func _emit_track_changed(
	previous_track: StringName,
	new_track: StringName
) -> void:
	if previous_track != new_track:
		track_changed.emit(new_track)


func _clear_interrupted_overworld() -> void:
	_has_interrupted_overworld = false
	_interrupted_track_id = &""
	_interrupted_playback_position = 0.0
