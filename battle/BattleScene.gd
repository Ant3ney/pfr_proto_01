class_name BattleScene
extends Node3D

## Presentation shell for the battle field. It receives launch data, plays the
## scene-side intro, and owns the template-driven battle HUD. Battle rules and
## creature spawning are intentionally outside this class.

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

var battle_data: Dictionary = {}
var _intro_tweens: Array[Tween] = []
var _camera_target_position := Vector3.ZERO
var _camera_target_fov := 42.0
var _battle_ui_template: UITemplate
var _battle_start_handoff_pending := false


func _ready() -> void:
	_battle_start_handoff_pending = GameInstance.is_battle_start_in_progress()
	if not GameInstance.battle_start_finished.is_connected(
		_on_battle_start_finished
	):
		GameInstance.battle_start_finished.connect(_on_battle_start_finished)
	_prepare_intro_presentation()
	battle_data = GameInstance.enter_battle_scene()
	intro_title.text = String(
		battle_data.get("intro_title", "BATTLE START!")
	).strip_edges().to_upper()
	if intro_title.text.is_empty():
		intro_title.text = "BATTLE START!"
	_play_intro_presentation()


func _exit_tree() -> void:
	_stop_intro_tweens()
	if GameInstance.battle_start_finished.is_connected(
		_on_battle_start_finished
	):
		GameInstance.battle_start_finished.disconnect(_on_battle_start_finished)
	if is_instance_valid(_battle_ui_template):
		_battle_ui_template.close()
	_battle_ui_template = null


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


func _finish_intro_presentation() -> void:
	battle_camera.position = _camera_target_position
	battle_camera.fov = _camera_target_fov
	battlefield_art.scale = Vector3.ONE
	intro_overlay.visible = false
	GameInstance.notify_battle_intro_finished()
	intro_finished.emit()
	if not _battle_start_handoff_pending:
		_show_battle_ui()


func _on_battle_start_finished(finished_data: Dictionary) -> void:
	_battle_start_handoff_pending = false
	battle_data = finished_data.duplicate(true)
	_show_battle_ui()


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


func _on_battle_ui_shown() -> void:
	battle_ui_shown.emit()


func _on_battle_action_selected(action: StringName) -> void:
	battle_action_selected.emit(action)


func _on_battle_ui_dismissed() -> void:
	_battle_ui_template = null


func _build_battle_ui_data() -> Dictionary:
	var ui_data := battle_data.duplicate(true)
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
	return ui_data


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
