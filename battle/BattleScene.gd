class_name BattleScene
extends Node3D

## Presentation shell for the battle field. Battle rules and creature spawning
## are intentionally outside this class; it only receives launch data and plays
## the scene-side half of the battle intro.

signal intro_finished

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


func _ready() -> void:
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


func get_battle_data() -> Dictionary:
	return battle_data.duplicate(true)


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
