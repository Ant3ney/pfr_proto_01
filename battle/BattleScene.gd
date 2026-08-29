class_name BattleScene
extends Node3D

## Thin presentation/input adapter. BattleSystem owns every rule, REST command,
## snapshot, retry, and outcome; this scene only renders state and emits typed
## UI intents through BattleSystem's public methods.

signal intro_finished
signal battle_ui_shown
signal battle_action_selected(action: StringName)

@onready var battle_camera: Camera3D = %BattleCamera
@onready var battlefield_art: Node3D = %BattlefieldArt
@onready var intro_overlay: Control = %IntroOverlay
@onready var color_wash: ColorRect = %ColorWash
@onready var impact_ring: Panel = %ImpactRing
@onready var horizon_flash: ColorRect = %HorizonFlash
@onready var intro_banner: Panel = %IntroBanner
@onready var intro_title: Label = %IntroTitle
@onready var intro_streaks: Control = %IntroStreaks
@onready var player_spawn: Marker3D = %PlayerSpawn
@onready var opponent_spawn: Marker3D = %OpponentSpawn
@onready var battle_actors: Node3D = %BattleActors
@onready var choice_overlay: BattleChoiceOverlay = %BattleChoiceOverlay

var battle_data: Dictionary = {}
var _intro_tweens: Array[Tween] = []
var _camera_target_position := Vector3.ZERO
var _camera_target_fov := 42.0
var _battle_ui_template: UITemplate
var _battle_start_handoff_pending := false
var _networked_battle := false
var _initial_snapshot_received := false
var _intro_has_started := false
var _intro_has_finished := false
var _presentation_running := false
var _pending_presentation_events: Array[Dictionary] = []
var _pending_presentation_revision := -1
var _snapshot: Dictionary = {}
var _choice_request: Dictionary = {}
var _sprite_presenter: Node


func _ready() -> void:
	_battle_start_handoff_pending = GameInstance.is_battle_start_in_progress()
	if not GameInstance.battle_start_finished.is_connected(
		_on_battle_start_finished
	):
		GameInstance.battle_start_finished.connect(_on_battle_start_finished)
	_connect_battle_system()
	_connect_choice_overlay()
	_create_sprite_presenter()
	_prepare_intro_presentation()
	battle_data = GameInstance.enter_battle_scene()
	intro_title.text = String(
		battle_data.get("intro_title", "BATTLE START!")
	).strip_edges().to_upper()
	if intro_title.text.is_empty():
		intro_title.text = "BATTLE START!"

	_networked_battle = (
		_battle_start_handoff_pending
		and not String(battle_data.get("encounter_id", "")).is_empty()
	)
	if _networked_battle:
		BattleSystem.begin_current_battle_scene()
	else:
		# Directly opening the shared scene (and legacy transition smoke tests)
		# remains intentionally network-free.
		if _battle_start_handoff_pending:
			GameInstance.reveal_battle_scene()
		_start_intro_once()


func _exit_tree() -> void:
	_stop_intro_tweens()
	if GameInstance.battle_start_finished.is_connected(
		_on_battle_start_finished
	):
		GameInstance.battle_start_finished.disconnect(_on_battle_start_finished)
	_disconnect_battle_system()
	if is_instance_valid(_battle_ui_template):
		_battle_ui_template.close()
	_battle_ui_template = null
	if is_instance_valid(_sprite_presenter) and _sprite_presenter.has_method("clear"):
		_sprite_presenter.call("clear")


func get_battle_data() -> Dictionary:
	return battle_data.duplicate(true)


func get_battle_ui() -> UITemplate:
	return _battle_ui_template if is_instance_valid(_battle_ui_template) else null


func _prepare_intro_presentation() -> void:
	intro_overlay.visible = true
	color_wash.modulate.a = 0.72
	impact_ring.scale = Vector2(0.12, 0.12)
	impact_ring.rotation = -0.35
	impact_ring.modulate.a = 0.0
	horizon_flash.pivot_offset = horizon_flash.size * 0.5
	horizon_flash.scale = Vector2(0.01, 1.0)
	horizon_flash.modulate.a = 0.0
	intro_banner.pivot_offset = intro_banner.size * 0.5
	_remember_intro_position(intro_banner)
	intro_banner.position = _intro_position(intro_banner) + Vector2(0.0, 54.0)
	intro_banner.scale = Vector2(0.72, 0.72)
	intro_banner.modulate.a = 0.0

	for streak_variant in intro_streaks.get_children():
		var streak := streak_variant as Control
		if not streak:
			continue
		_remember_intro_position(streak)
		var direction := -1.0 if streak.name.begins_with("Left") else 1.0
		streak.position = _intro_position(streak) + Vector2(direction * 190.0, 0.0)
		streak.modulate.a = 0.0

	_camera_target_position = battle_camera.position
	_camera_target_fov = battle_camera.fov
	battle_camera.position = _camera_target_position + Vector3(0.0, 0.32, 0.85)
	battle_camera.fov = maxf(20.0, _camera_target_fov - 7.0)
	battlefield_art.scale = Vector3(0.985, 0.985, 0.985)


func _play_intro_presentation() -> void:
	var camera_tween := _new_intro_tween(true)
	camera_tween.tween_property(
		battle_camera,
		^"position",
		_camera_target_position,
		0.94
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(
		battle_camera,
		^"fov",
		_camera_target_fov,
		0.86
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(
		battlefield_art,
		^"scale",
		Vector3.ONE,
		0.84
	).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	var impact_tween := _new_intro_tween(true)
	impact_tween.tween_property(color_wash, ^"modulate:a", 0.0, 0.66)
	impact_tween.tween_property(impact_ring, ^"modulate:a", 0.92, 0.12).set_delay(0.05)
	impact_tween.tween_property(
		impact_ring,
		^"scale",
		Vector2(1.85, 1.85),
		0.72
	).set_delay(0.05).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(impact_ring, ^"rotation", 0.2, 0.72).set_delay(0.05)
	impact_tween.tween_property(impact_ring, ^"modulate:a", 0.0, 0.3).set_delay(0.42)
	impact_tween.tween_property(horizon_flash, ^"modulate:a", 1.0, 0.08).set_delay(0.08)
	impact_tween.tween_property(
		horizon_flash,
		^"scale",
		Vector2.ONE,
		0.28
	).set_delay(0.08).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	impact_tween.tween_property(horizon_flash, ^"modulate:a", 0.0, 0.28).set_delay(0.34)

	var banner_tween := _new_intro_tween(true)
	banner_tween.tween_property(
		intro_banner,
		^"position",
		_intro_position(intro_banner),
		0.34
	).set_delay(0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(
		intro_banner,
		^"scale",
		Vector2.ONE,
		0.34
	).set_delay(0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(intro_banner, ^"modulate:a", 1.0, 0.18).set_delay(0.14)
	banner_tween.tween_property(
		intro_banner,
		^"position",
		_intro_position(intro_banner) + Vector2(0.0, -32.0),
		0.28
	).set_delay(0.78).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	banner_tween.tween_property(intro_banner, ^"modulate:a", 0.0, 0.24).set_delay(0.78)

	var streak_tween := _new_intro_tween(true)
	for streak_variant in intro_streaks.get_children():
		var streak := streak_variant as Control
		if not streak:
			continue
		var direction := -1.0 if streak.name.begins_with("Left") else 1.0
		streak_tween.tween_property(streak, ^"modulate:a", 0.9, 0.1).set_delay(0.06)
		streak_tween.tween_property(
			streak,
			^"position",
			_intro_position(streak) - Vector2(direction * 55.0, 0.0),
			0.42
		).set_delay(0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		streak_tween.tween_property(streak, ^"modulate:a", 0.0, 0.24).set_delay(0.37)

	var finish_tween := _new_intro_tween()
	finish_tween.tween_interval(1.08)
	finish_tween.tween_callback(_finish_intro_presentation)


func _start_intro_once() -> void:
	if _intro_has_started:
		return
	_intro_has_started = true
	_play_intro_presentation()


func _finish_intro_presentation() -> void:
	battle_camera.position = _camera_target_position
	battle_camera.fov = _camera_target_fov
	battlefield_art.scale = Vector3.ONE
	intro_overlay.visible = false
	_intro_has_finished = true
	GameInstance.notify_battle_intro_finished()
	intro_finished.emit()
	if not _battle_start_handoff_pending:
		_show_battle_ui()
		_try_present_pending_events()


func _on_battle_start_finished(finished_data: Dictionary) -> void:
	_battle_start_handoff_pending = false
	battle_data = finished_data.duplicate(true)
	_show_battle_ui()
	_try_present_pending_events()


func _show_battle_ui() -> void:
	if is_instance_valid(_battle_ui_template):
		return

	_battle_ui_template = UIManager.show_ui("")
	if not is_instance_valid(_battle_ui_template):
		push_error("BattleScene could not create its battle UI template.")
		_battle_ui_template = null
		return

	_battle_ui_template.set_dismiss_callback(_on_battle_ui_dismissed)
	_battle_ui_template.set_battle_action_callback(
		&"fight",
		_on_battle_action_selected.bind(&"fight")
	)
	_battle_ui_template.set_battle_action_callback(
		&"bag",
		_on_battle_action_selected.bind(&"bag")
	)
	_battle_ui_template.set_battle_action_callback(
		&"party",
		_on_battle_action_selected.bind(&"party")
	)
	_battle_ui_template.set_battle_action_callback(
		&"run",
		_on_battle_action_selected.bind(&"run")
	)
	_battle_ui_template.battle_ui_shown.connect(_on_battle_ui_shown)
	_battle_ui_template.play_battle_ui_in(_build_battle_ui_data())
	_update_command_availability()


func _on_battle_ui_shown() -> void:
	battle_ui_shown.emit()


func _on_battle_action_selected(action: StringName) -> void:
	battle_action_selected.emit(action)
	if not _networked_battle or BattleSystem.get_state() != BattleSystem.State.AWAITING_PLAYER:
		return
	match action:
		&"fight":
			if String(_choice_request.get("type", "")) == "move":
				choice_overlay.show_moves(_choice_request)
		&"party":
			var switch_options: Variant = _choice_request.get("switchOptions", [])
			if typeof(switch_options) == TYPE_ARRAY and not (switch_options as Array).is_empty():
				choice_overlay.show_switches(
					_choice_request,
					_snapshot,
					String(_choice_request.get("type", "")) == "switch"
				)
		&"run":
			if BattleSystem.is_forfeit_allowed():
				choice_overlay.show_forfeit_confirmation()
		&"bag":
			_battle_ui_template.set_battle_message("The Bag is unavailable in battle v1.")


func _on_battle_ui_dismissed() -> void:
	_battle_ui_template = null


func _build_battle_ui_data() -> Dictionary:
	var ui_data := battle_data.duplicate(true)
	if not _snapshot.is_empty():
		_apply_snapshot_to_ui_data(ui_data, _snapshot)
		ui_data["can_bag"] = false
		return ui_data
	var player_member := _first_battle_member(ui_data.get("player_party", []))
	_apply_battle_member_to_ui(ui_data, "player", player_member)
	if not _has_battle_member_name(ui_data, "player"):
		_apply_battle_member_to_ui(
			ui_data,
			"player",
			CollectionSystem.get_pcl_by_party_slot(1)
		)

	var opponent_member := _first_battle_member(
		ui_data.get("opponent_party", [])
	)
	_apply_battle_member_to_ui(ui_data, "opponent", opponent_member)
	ui_data["can_bag"] = false
	return ui_data


func _connect_battle_system() -> void:
	var connections := {
		"state_changed": Callable(self, "_on_system_state_changed"),
		"snapshot_changed": Callable(self, "_on_system_snapshot_changed"),
		"presentation_events_ready": Callable(self, "_on_presentation_events_ready"),
		"choice_request_changed": Callable(self, "_on_choice_request_changed"),
		"battle_ended": Callable(self, "_on_battle_ended"),
		"battle_error_changed": Callable(self, "_on_battle_error_changed"),
	}
	for signal_name: String in connections:
		var callback: Callable = connections[signal_name]
		if not BattleSystem.is_connected(signal_name, callback):
			BattleSystem.connect(signal_name, callback)


func _disconnect_battle_system() -> void:
	var connections := {
		"state_changed": Callable(self, "_on_system_state_changed"),
		"snapshot_changed": Callable(self, "_on_system_snapshot_changed"),
		"presentation_events_ready": Callable(self, "_on_presentation_events_ready"),
		"choice_request_changed": Callable(self, "_on_choice_request_changed"),
		"battle_ended": Callable(self, "_on_battle_ended"),
		"battle_error_changed": Callable(self, "_on_battle_error_changed"),
	}
	for signal_name: String in connections:
		var callback: Callable = connections[signal_name]
		if BattleSystem.is_connected(signal_name, callback):
			BattleSystem.disconnect(signal_name, callback)


func _connect_choice_overlay() -> void:
	choice_overlay.move_chosen.connect(_on_move_chosen)
	choice_overlay.switch_chosen.connect(_on_switch_chosen)
	choice_overlay.forfeit_confirmed.connect(_on_forfeit_confirmed)
	choice_overlay.retry_requested.connect(_on_retry_requested)
	choice_overlay.return_requested.connect(_on_return_requested)
	choice_overlay.continue_requested.connect(_on_continue_requested)


func _create_sprite_presenter() -> void:
	var script_path := "res://battle/system/BattleSpritePresenter.gd"
	if not ResourceLoader.exists(script_path):
		return
	var presenter_script := load(script_path) as Script
	if not presenter_script:
		return
	_sprite_presenter = presenter_script.new() as Node
	if not _sprite_presenter:
		return
	_sprite_presenter.name = "BattleSpritePresenter"
	battle_actors.add_child(_sprite_presenter)
	if _sprite_presenter.has_method("configure"):
		_sprite_presenter.call("configure", player_spawn, opponent_spawn)


func _on_system_state_changed(_next_state: int) -> void:
	if not _networked_battle:
		return
	if BattleSystem.get_state() in [
		BattleSystem.State.CONNECTING,
		BattleSystem.State.PRESENTING,
		BattleSystem.State.SUBMITTING,
		BattleSystem.State.RETURNING,
	]:
		choice_overlay.force_hide()
	_update_command_availability()


func _on_system_snapshot_changed(snapshot: Dictionary) -> void:
	if not _networked_battle or snapshot.is_empty():
		return
	_snapshot = snapshot.duplicate(true)
	if is_instance_valid(_sprite_presenter) and _sprite_presenter.has_method("present_snapshot"):
		_sprite_presenter.call("present_snapshot", _snapshot.duplicate(true))
	if is_instance_valid(_battle_ui_template):
		_battle_ui_template.update_battle_ui(_build_battle_ui_data())
		_update_command_availability()

	if not _initial_snapshot_received:
		_initial_snapshot_received = true
		GameInstance.reveal_battle_scene()
		_start_intro_once()


func _on_presentation_events_ready(events: Array, revision: int) -> void:
	if not _networked_battle:
		return
	_pending_presentation_events.clear()
	for value: Variant in events:
		if typeof(value) == TYPE_DICTIONARY:
			_pending_presentation_events.append((value as Dictionary).duplicate(true))
	_pending_presentation_revision = revision
	_try_present_pending_events()


func _try_present_pending_events() -> void:
	if (
		_presentation_running
		or _pending_presentation_revision < 0
		or not _intro_has_finished
		or not is_instance_valid(_battle_ui_template)
	):
		return
	_present_pending_events.call_deferred()


func _present_pending_events() -> void:
	if _presentation_running or _pending_presentation_revision < 0:
		return
	_presentation_running = true
	var events := _pending_presentation_events.duplicate(true)
	var revision := _pending_presentation_revision
	_pending_presentation_events.clear()
	_pending_presentation_revision = -1
	for event_value: Variant in events:
		if not is_inside_tree() or typeof(event_value) != TYPE_DICTIONARY:
			break
		var event := event_value as Dictionary
		var message := String(event.get("message", "")).strip_edges()
		if not message.is_empty() and is_instance_valid(_battle_ui_template):
			_battle_ui_template.set_battle_message(message)
		var waited_for_presenter := false
		if is_instance_valid(_sprite_presenter) and _sprite_presenter.has_method("play_event"):
			var completion: Variant = _sprite_presenter.call("play_event", event.duplicate(true))
			if typeof(completion) == TYPE_SIGNAL:
				waited_for_presenter = true
				await completion
		if not waited_for_presenter and is_inside_tree():
			await get_tree().create_timer(_event_duration(event)).timeout
	_presentation_running = false
	if is_inside_tree():
		BattleSystem.acknowledge_events_presented(revision)


func _on_choice_request_changed(request: Dictionary) -> void:
	if not _networked_battle:
		return
	_choice_request = request.duplicate(true)
	_update_command_availability()
	if (
		String(_choice_request.get("type", "")) == "switch"
		and is_instance_valid(_battle_ui_template)
	):
		choice_overlay.show_switches(_choice_request, _snapshot, true)


func _on_battle_ended(result: Dictionary) -> void:
	if not _networked_battle:
		return
	_update_command_availability()
	choice_overlay.show_result(result)


func _on_battle_error_changed(error: Dictionary) -> void:
	if not _networked_battle:
		return
	if error.is_empty():
		choice_overlay.force_hide()
		return
	if not bool(error.get("can_return", true)):
		if is_instance_valid(_battle_ui_template):
			_battle_ui_template.set_battle_message(String(error.get("message", "Invalid action.")))
		return
	choice_overlay.show_error(error)
	_update_command_availability()


func _on_move_chosen(move_index: int) -> void:
	BattleSystem.choose_move(move_index)


func _on_switch_chosen(member_id: String) -> void:
	BattleSystem.choose_switch(member_id)


func _on_forfeit_confirmed() -> void:
	BattleSystem.forfeit()


func _on_retry_requested() -> void:
	BattleSystem.retry_pending_request()


func _on_return_requested() -> void:
	BattleSystem.continue_after_result()


func _on_continue_requested() -> void:
	BattleSystem.continue_after_result()


func _update_command_availability() -> void:
	if not is_instance_valid(_battle_ui_template):
		return
	if not _networked_battle:
		_battle_ui_template.set_battle_action_enabled(&"bag", false)
		return

	for action in [&"fight", &"bag", &"party", &"run"]:
		_battle_ui_template.set_battle_action_enabled(action, false)
	if BattleSystem.get_state() != BattleSystem.State.AWAITING_PLAYER:
		return
	var request_type := String(_choice_request.get("type", ""))
	var switch_options: Variant = _choice_request.get("switchOptions", [])
	var has_switches := (
		typeof(switch_options) == TYPE_ARRAY
		and not (switch_options as Array).is_empty()
	)
	if request_type == "move":
		_battle_ui_template.set_battle_action_enabled(&"fight", true)
		_battle_ui_template.set_battle_action_enabled(&"party", has_switches)
		_battle_ui_template.set_battle_action_enabled(
			&"run",
			BattleSystem.is_forfeit_allowed()
		)
	elif request_type == "switch":
		_battle_ui_template.set_battle_action_enabled(&"party", has_switches)


func _apply_snapshot_to_ui_data(ui_data: Dictionary, snapshot: Dictionary) -> void:
	var parties_value: Variant = snapshot.get("parties")
	if typeof(parties_value) != TYPE_DICTIONARY:
		return
	var parties := parties_value as Dictionary
	var player_member := _active_snapshot_member(parties.get("player", []))
	var opponent_member := _active_snapshot_member(parties.get("opponent", []))
	_apply_snapshot_member(ui_data, "player", player_member)
	_apply_snapshot_member(ui_data, "opponent", opponent_member)


func _active_snapshot_member(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {}
	var first_member: Dictionary = {}
	for member_value: Variant in value as Array:
		if typeof(member_value) != TYPE_DICTIONARY:
			continue
		var member := member_value as Dictionary
		if first_member.is_empty():
			first_member = member
		if bool(member.get("active", false)):
			return member
	return first_member


func _apply_snapshot_member(
	ui_data: Dictionary,
	prefix: String,
	member: Dictionary
) -> void:
	if member.is_empty():
		return
	ui_data["%s_pokemon_name" % prefix] = String(
		member.get("nickname", member.get("species", "Pokémon"))
	)
	ui_data["%s_level" % prefix] = int(member.get("level", 0))
	ui_data["%s_health" % prefix] = float(member.get("normalizedHealth", 0.0))


func _event_duration(event: Dictionary) -> float:
	match String(event.get("type", "message")):
		"attack", "switch":
			return 0.45
		"damage", "heal", "status", "status_cleared":
			return 0.32
		"knockout", "result":
			return 0.6
		"turn":
			return 0.2
		_:
			return 0.3


func _first_battle_member(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	if typeof(value) != TYPE_ARRAY:
		return {}
	for member_value: Variant in value as Array:
		if typeof(member_value) == TYPE_DICTIONARY:
			return (member_value as Dictionary).duplicate(true)
	return {}


func _apply_battle_member_to_ui(
	ui_data: Dictionary,
	prefix: String,
	member: Dictionary
) -> void:
	if member.is_empty():
		return

	var name_key := "%s_pokemon_name" % prefix
	if not _has_battle_member_name(ui_data, prefix):
		var member_name := String(
			member.get("pokemon_name", member.get("name", ""))
		).strip_edges()
		var pokemon_id := _battle_member_pokemon_id(member)
		if member_name.is_empty() and pokemon_id > 0:
			var creature := CreatureSystem.get_creature(pokemon_id)
			member_name = String(creature.get("name", "")).strip_edges()
		if not member_name.is_empty():
			ui_data[name_key] = member_name

	var stats_value: Variant = member.get("instanceStats", {})
	var stats: Dictionary = (
		stats_value as Dictionary
		if typeof(stats_value) == TYPE_DICTIONARY
		else {}
	)
	var level_key := "%s_level" % prefix
	if not ui_data.has(level_key):
		var level_value: Variant = stats.get(
			"level",
			member.get("level", null)
		)
		if (
			typeof(level_value) in [TYPE_INT, TYPE_FLOAT]
			and int(level_value) > 0
		):
			ui_data[level_key] = int(level_value)

	var health_key := "%s_health" % prefix
	if not ui_data.has(health_key):
		var health_value: Variant = stats.get(
			"health",
			member.get("health", null)
		)
		if typeof(health_value) in [TYPE_INT, TYPE_FLOAT]:
			ui_data[health_key] = clampf(float(health_value), 0.0, 1.0)


func _has_battle_member_name(ui_data: Dictionary, prefix: String) -> bool:
	return (
		not String(ui_data.get("%s_pokemon_name" % prefix, "")).strip_edges().is_empty()
		or not String(ui_data.get("%s_name" % prefix, "")).strip_edges().is_empty()
	)


func _battle_member_pokemon_id(member: Dictionary) -> int:
	for key in ["pokemonId", "pokemon_id", "id"]:
		var value: Variant = member.get(key)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			return int(value)
	return 0


func _remember_intro_position(control: Control) -> void:
	if not control.has_meta("battle_intro_position"):
		control.set_meta("battle_intro_position", control.position)


func _intro_position(control: Control) -> Vector2:
	return control.get_meta("battle_intro_position", control.position) as Vector2


func _new_intro_tween(is_parallel := false) -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(is_parallel)
	_intro_tweens.append(tween)
	return tween


func _stop_intro_tweens() -> void:
	for tween in _intro_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_intro_tweens.clear()
