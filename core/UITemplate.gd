class_name UITemplate
extends Control

## Reusable popup returned by UIManager.show_ui().

const BATTLE_TRANSITION_OVERLAY_SCENE: PackedScene = preload(
	"res://core/ui/battle_transition_overlay.tscn"
)

signal action_pressed
signal dismissed

@onready var dialog_panel: PanelContainer = $DialogPanel
@onready var message_label: Label = %Message
@onready var speaker_panel: PanelContainer = %SpeakerPanel
@onready var speaker_label: Label = %Speaker
@onready var action_frame: PanelContainer = $ActionFrame
@onready var action_button: Button = %ActionButton
@onready var dismiss_button: Button = %DismissButton

var _text := ""
var _speaker_name := ""
var _action_text := "Next"
var _dismiss_text := "Close"
var _action_enabled := true
var _dismiss_visible := false
var _action_callback := Callable()
var _dismiss_callback := Callable()
var _is_closing := false
var _battle_transition_overlay: Control
var _battle_transition_tweens: Array[Tween] = []
var _battle_transition_phase := ""


func _ready() -> void:
	message_label.text = _text
	speaker_label.text = _speaker_name
	speaker_panel.visible = not _speaker_name.is_empty()
	action_button.text = _get_action_button_text()
	action_button.disabled = not _action_enabled
	dismiss_button.text = _dismiss_text
	dismiss_button.visible = _dismiss_visible
	action_button.pressed.connect(_on_action_pressed)
	dismiss_button.pressed.connect(close)
	action_button.grab_focus()


func _exit_tree() -> void:
	_stop_battle_transition_tweens()


func set_text(text: String) -> UITemplate:
	_text = text
	if is_instance_valid(message_label):
		message_label.text = _text
	return self


func set_speaker_name(speaker_name: String) -> UITemplate:
	_speaker_name = speaker_name
	if is_instance_valid(speaker_label):
		speaker_label.text = _speaker_name
	if is_instance_valid(speaker_panel):
		speaker_panel.visible = not _speaker_name.is_empty()
	return self


func set_action_text(text: String) -> UITemplate:
	_action_text = text
	if is_instance_valid(action_button):
		action_button.text = _get_action_button_text()
	return self


func set_dismiss_text(text: String) -> UITemplate:
	_dismiss_text = text
	if is_instance_valid(dismiss_button):
		dismiss_button.text = _dismiss_text
	return self


func set_action_callback(callback: Callable) -> UITemplate:
	_action_callback = callback
	return self


func set_dismiss_callback(callback: Callable) -> UITemplate:
	_dismiss_callback = callback
	return self


func set_action_enabled(is_enabled: bool) -> UITemplate:
	_action_enabled = is_enabled
	if is_instance_valid(action_button):
		action_button.disabled = not is_enabled
	return self


func set_dismiss_visible(is_visible: bool) -> UITemplate:
	_dismiss_visible = is_visible
	if is_instance_valid(dismiss_button):
		dismiss_button.visible = _dismiss_visible
	return self


## Re-presents this template as a full-screen battle transition. The caller
## retains ownership and supplies the callback that changes to the battle scene
## only after the old scene is completely covered.
func play_battle_transition_out(
	battle_data: Dictionary,
	covered_callback: Callable
) -> UITemplate:
	if _is_closing:
		return self

	_stop_battle_transition_tweens()
	_set_dialog_presentation_visible(false)
	if not _ensure_battle_transition_overlay():
		push_error("UITemplate could not create the battle transition overlay.")
		if covered_callback.is_valid():
			covered_callback.call()
		return self

	_battle_transition_phase = "covering"
	_configure_battle_transition_text(battle_data)
	_prepare_battle_transition_out()
	_animate_battle_transition_out(covered_callback)
	return self


## Reveals the newly loaded battle scene through the same template instance
## that covered the previous scene. The template closes itself after the reveal
## and therefore still runs its configured dismiss callback.
func play_battle_transition_in(
	completed_callback: Callable = Callable()
) -> UITemplate:
	if _is_closing:
		return self
	if not is_instance_valid(_battle_transition_overlay):
		if completed_callback.is_valid():
			completed_callback.call()
		close()
		return self

	_stop_battle_transition_tweens()
	_battle_transition_phase = "revealing"
	_animate_battle_transition_in(completed_callback)
	return self


func is_battle_transition_active() -> bool:
	return (
		is_instance_valid(_battle_transition_overlay)
		and _battle_transition_phase in ["covering", "covered", "revealing"]
	)


func close() -> void:
	if _is_closing:
		return

	_is_closing = true
	_stop_battle_transition_tweens()
	dismissed.emit()
	if _dismiss_callback.is_valid():
		_dismiss_callback.call()
	queue_free()


func _on_action_pressed() -> void:
	action_pressed.emit()
	if _action_callback.is_valid():
		_action_callback.call()


func _get_action_button_text() -> String:
	return "%s   ➜" % _action_text


func _set_dialog_presentation_visible(is_visible: bool) -> void:
	dialog_panel.visible = is_visible
	speaker_panel.visible = is_visible and not _speaker_name.is_empty()
	action_frame.visible = is_visible
	dismiss_button.visible = is_visible and _dismiss_visible
	if not is_visible:
		action_button.release_focus()


func _ensure_battle_transition_overlay() -> bool:
	if is_instance_valid(_battle_transition_overlay):
		return true

	_battle_transition_overlay = (
		BATTLE_TRANSITION_OVERLAY_SCENE.instantiate() as Control
	)
	if not _battle_transition_overlay:
		return false

	add_child(_battle_transition_overlay)
	move_child(_battle_transition_overlay, get_child_count() - 1)
	return true


func _configure_battle_transition_text(battle_data: Dictionary) -> void:
	var title := String(
		battle_data.get("transition_title", "BATTLE START")
	).strip_edges()
	var subtitle := String(
		battle_data.get("transition_subtitle", "A NEW CHALLENGER")
	).strip_edges()
	if title.is_empty():
		title = "BATTLE START"
	if subtitle.is_empty():
		subtitle = "A NEW CHALLENGER"

	var title_label := _battle_transition_overlay.get_node(
		^"CenterPresentation/CenterBand/BattleTitle"
	) as Label
	var subtitle_label := _battle_transition_overlay.get_node(
		^"CenterPresentation/CenterBand/OpponentName"
	) as Label
	title_label.text = title.to_upper()
	subtitle_label.text = subtitle.to_upper()


func _prepare_battle_transition_out() -> void:
	var viewport_height := maxf(get_viewport_rect().size.y, 1.0)
	var backdrop := _transition_control(^"Backdrop")
	var speed_lines := _transition_control(^"SpeedLines")
	var top_blade := _transition_control(^"Curtains/TopBlade")
	var bottom_blade := _transition_control(^"Curtains/BottomBlade")
	var center_band := _transition_control(
		^"CenterPresentation/CenterBand"
	)
	var emblem := _transition_control(^"CenterPresentation/EmblemOuter")
	var battle_tag := _transition_control(^"CenterPresentation/BattleTag")
	var title := _transition_control(
		^"CenterPresentation/CenterBand/BattleTitle"
	)
	var subtitle := _transition_control(
		^"CenterPresentation/CenterBand/OpponentName"
	)
	var hold_cover := _transition_control(^"HoldCover")
	var flash := _transition_control(^"Flash")

	_battle_transition_overlay.visible = true
	_battle_transition_overlay.modulate = Color.WHITE
	_remember_transition_position(top_blade)
	_remember_transition_position(bottom_blade)
	_remember_transition_position(title)
	_remember_transition_position(subtitle)
	top_blade.position = (
		_transition_position(top_blade) + Vector2(0.0, -viewport_height * 0.95)
	)
	bottom_blade.position = (
		_transition_position(bottom_blade) + Vector2(0.0, viewport_height * 0.95)
	)

	backdrop.modulate.a = 0.0
	speed_lines.modulate.a = 0.0
	center_band.scale = Vector2(0.025, 1.0)
	center_band.modulate.a = 1.0
	emblem.scale = Vector2(0.08, 0.08)
	emblem.rotation = -0.62
	emblem.modulate.a = 0.0
	battle_tag.scale = Vector2(0.25, 0.25)
	battle_tag.modulate.a = 0.0
	title.position = _transition_position(title) + Vector2(-80.0, 0.0)
	title.modulate.a = 0.0
	subtitle.position = _transition_position(subtitle) + Vector2(80.0, 0.0)
	subtitle.modulate.a = 0.0
	hold_cover.modulate.a = 0.0
	flash.modulate.a = 0.0

	for streak_variant in speed_lines.get_children():
		var streak := streak_variant as Control
		if not streak:
			continue
		_remember_transition_position(streak)
		var direction := -1.0 if streak.name.begins_with("Left") else 1.0
		streak.position = (
			_transition_position(streak) + Vector2(direction * 240.0, 0.0)
		)


func _animate_battle_transition_out(covered_callback: Callable) -> void:
	var backdrop := _transition_control(^"Backdrop")
	var speed_lines := _transition_control(^"SpeedLines")
	var top_blade := _transition_control(^"Curtains/TopBlade")
	var bottom_blade := _transition_control(^"Curtains/BottomBlade")
	var center_band := _transition_control(
		^"CenterPresentation/CenterBand"
	)
	var emblem := _transition_control(^"CenterPresentation/EmblemOuter")
	var battle_tag := _transition_control(^"CenterPresentation/BattleTag")
	var title := _transition_control(
		^"CenterPresentation/CenterBand/BattleTitle"
	)
	var subtitle := _transition_control(
		^"CenterPresentation/CenterBand/OpponentName"
	)
	var hold_cover := _transition_control(^"HoldCover")
	var flash := _transition_control(^"Flash")

	var motion := _new_battle_transition_tween(true)
	motion.tween_property(backdrop, ^"modulate:a", 0.96, 0.24)
	motion.tween_property(
		top_blade,
		^"position",
		_transition_position(top_blade),
		0.48
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	motion.tween_property(
		bottom_blade,
		^"position",
		_transition_position(bottom_blade),
		0.48
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	motion.tween_property(speed_lines, ^"modulate:a", 1.0, 0.24).set_delay(0.08)
	motion.tween_property(
		center_band,
		^"scale",
		Vector2.ONE,
		0.36
	).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_property(
		emblem,
		^"scale",
		Vector2.ONE,
		0.38
	).set_delay(0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_property(emblem, ^"rotation", 0.0, 0.38).set_delay(0.25)
	motion.tween_property(emblem, ^"modulate:a", 1.0, 0.16).set_delay(0.25)
	motion.tween_property(
		battle_tag,
		^"scale",
		Vector2.ONE,
		0.3
	).set_delay(0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_property(battle_tag, ^"modulate:a", 1.0, 0.15).set_delay(0.34)
	motion.tween_property(
		title,
		^"position",
		_transition_position(title),
		0.28
	).set_delay(0.31).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	motion.tween_property(title, ^"modulate:a", 1.0, 0.2).set_delay(0.31)
	motion.tween_property(
		subtitle,
		^"position",
		_transition_position(subtitle),
		0.28
	).set_delay(0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	motion.tween_property(subtitle, ^"modulate:a", 1.0, 0.2).set_delay(0.35)

	for streak_variant in speed_lines.get_children():
		var streak := streak_variant as Control
		if not streak:
			continue
		motion.tween_property(
			streak,
			^"position",
			_transition_position(streak),
			0.32
		).set_delay(0.08).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	var cover_timeline := _new_battle_transition_tween()
	cover_timeline.tween_interval(0.58)
	cover_timeline.tween_property(flash, ^"modulate:a", 0.9, 0.07)
	cover_timeline.tween_property(hold_cover, ^"modulate:a", 1.0, 0.1)
	cover_timeline.tween_property(flash, ^"modulate:a", 0.0, 0.1)
	cover_timeline.tween_interval(0.03)
	cover_timeline.tween_callback(
		_on_battle_cover_finished.bind(covered_callback)
	)


func _animate_battle_transition_in(completed_callback: Callable) -> void:
	var viewport_height := maxf(get_viewport_rect().size.y, 1.0)
	var backdrop := _transition_control(^"Backdrop")
	var speed_lines := _transition_control(^"SpeedLines")
	var top_blade := _transition_control(^"Curtains/TopBlade")
	var bottom_blade := _transition_control(^"Curtains/BottomBlade")
	var center_band := _transition_control(
		^"CenterPresentation/CenterBand"
	)
	var emblem := _transition_control(^"CenterPresentation/EmblemOuter")
	var battle_tag := _transition_control(^"CenterPresentation/BattleTag")
	var title := _transition_control(
		^"CenterPresentation/CenterBand/BattleTitle"
	)
	var subtitle := _transition_control(
		^"CenterPresentation/CenterBand/OpponentName"
	)
	var hold_cover := _transition_control(^"HoldCover")
	var flash := _transition_control(^"Flash")

	hold_cover.modulate.a = 1.0
	flash.modulate.a = 0.82
	var motion := _new_battle_transition_tween(true)
	motion.tween_property(hold_cover, ^"modulate:a", 0.0, 0.2).set_delay(0.05)
	motion.tween_property(flash, ^"modulate:a", 0.0, 0.28)
	motion.tween_property(
		top_blade,
		^"position",
		_transition_position(top_blade) + Vector2(0.0, -viewport_height * 1.05),
		0.55
	).set_delay(0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	motion.tween_property(
		bottom_blade,
		^"position",
		_transition_position(bottom_blade) + Vector2(0.0, viewport_height * 1.05),
		0.55
	).set_delay(0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	motion.tween_property(backdrop, ^"modulate:a", 0.0, 0.48).set_delay(0.16)
	motion.tween_property(speed_lines, ^"modulate:a", 0.0, 0.3).set_delay(0.15)
	motion.tween_property(
		center_band,
		^"scale",
		Vector2(0.02, 1.0),
		0.34
	).set_delay(0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	motion.tween_property(center_band, ^"modulate:a", 0.0, 0.24).set_delay(0.2)
	motion.tween_property(
		emblem,
		^"scale",
		Vector2(1.7, 1.7),
		0.38
	).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	motion.tween_property(emblem, ^"rotation", 0.5, 0.38).set_delay(0.1)
	motion.tween_property(emblem, ^"modulate:a", 0.0, 0.3).set_delay(0.16)
	motion.tween_property(battle_tag, ^"modulate:a", 0.0, 0.18).set_delay(0.12)
	motion.tween_property(
		title,
		^"position",
		_transition_position(title) + Vector2(-140.0, 0.0),
		0.32
	).set_delay(0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	motion.tween_property(title, ^"modulate:a", 0.0, 0.22).set_delay(0.15)
	motion.tween_property(
		subtitle,
		^"position",
		_transition_position(subtitle) + Vector2(140.0, 0.0),
		0.32
	).set_delay(0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	motion.tween_property(subtitle, ^"modulate:a", 0.0, 0.22).set_delay(0.15)

	for streak_variant in speed_lines.get_children():
		var streak := streak_variant as Control
		if not streak:
			continue
		var direction := -1.0 if streak.name.begins_with("Left") else 1.0
		motion.tween_property(
			streak,
			^"position",
			_transition_position(streak) + Vector2(direction * 280.0, 0.0),
			0.36
		).set_delay(0.08).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	var finish_timeline := _new_battle_transition_tween()
	finish_timeline.tween_interval(0.76)
	finish_timeline.tween_callback(
		_finish_battle_reveal.bind(completed_callback)
	)


func _on_battle_cover_finished(covered_callback: Callable) -> void:
	if _battle_transition_phase != "covering" or _is_closing:
		return
	_battle_transition_phase = "covered"
	if covered_callback.is_valid():
		covered_callback.call()


func _finish_battle_reveal(completed_callback: Callable) -> void:
	if _battle_transition_phase != "revealing" or _is_closing:
		return
	_battle_transition_phase = "complete"
	if completed_callback.is_valid():
		completed_callback.call()
	close.call_deferred()


func _transition_control(path: NodePath) -> Control:
	return _battle_transition_overlay.get_node(path) as Control


func _remember_transition_position(control: Control) -> void:
	if not control.has_meta("battle_transition_position"):
		control.set_meta("battle_transition_position", control.position)


func _transition_position(control: Control) -> Vector2:
	return control.get_meta(
		"battle_transition_position",
		control.position
	) as Vector2


func _new_battle_transition_tween(is_parallel := false) -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(is_parallel)
	_battle_transition_tweens.append(tween)
	return tween


func _stop_battle_transition_tweens() -> void:
	for tween in _battle_transition_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_battle_transition_tweens.clear()
