class_name RNDLootBoxRoulette
extends Control

## Blocking loot-box reveal. The prize is committed by StretchGoalSystem before
## this presentation begins; this node only visualizes that immutable result.

signal closed

const SpriteMapping := preload("res://battle/system/BattleSpeciesMapping.gd")
const SPRITE_ANIMATION := &"idle"
const REEL_SIZE := 31
const WINNER_INDEX := 26
const CARD_WIDTH := 132.0
const CARD_HEIGHT := 164.0
const CARD_SEPARATION := 10
const ICON_SIZE := Vector2i(84, 84)

var spin_duration := 5.2

var _summary: Dictionary = {}
var _sprite_catalog := BattleSpriteCatalog.new()
var _thumbnail_cache: Dictionary = {}
var _reel_window: Control
var _reel_track: HBoxContainer
var _status: Label
var _close_button: Button
var _skip_button: Button
var _spin_tween: Tween
var _revealed := false
var _reveal_pending := false


func _ready() -> void:
	set_process_unhandled_input(true)
	_sprite_catalog.initialize()
	_build_interface()


func _exit_tree() -> void:
	_sprite_catalog.release_all()


func present(summary: Dictionary) -> bool:
	_summary = summary.duplicate(true)
	var box_id := String(_summary.get("id", ""))
	var winner_id := int(_summary.get("pokemon_id", 0))
	var reel := StretchGoalSystem.build_loot_box_reel(
		box_id,
		winner_id,
		REEL_SIZE,
		WINNER_INDEX
	)
	if reel.size() != REEL_SIZE:
		_status.text = "The reel could not be prepared, but your prize is already in storage."
		_finish_spin()
		return false

	var offer := _summary.get("offer", {}) as Dictionary
	var price := int(_summary.get("price", 0))
	($Panel/Margin/Column/Heading as Label).text = "%s  •  %s" % [
		String(offer.get("name", "Loot Box")),
		StretchGoalSystem.format_money(price),
	]
	for pokemon_id in reel:
		_add_reel_card(int(pokemon_id))
	_start_spin.call_deferred()
	return true


func reveal_immediately() -> void:
	if _revealed or _reveal_pending:
		return
	_reveal_pending = true
	if is_instance_valid(_spin_tween):
		_spin_tween.kill()
	_finish_immediate_reveal()


func _finish_immediate_reveal() -> void:
	# The HBox must complete one layout pass before its winner-card position is
	# authoritative. This also makes an immediate Skip press land on the knob.
	await get_tree().process_frame
	_snap_winner_to_marker()
	_reveal_pending = false
	_finish_spin()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var dismiss := (
		event is InputEventKey
		and (event as InputEventKey).keycode == KEY_ESCAPE
	) or (
		event is InputEventJoypadButton
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B
	)
	if not dismiss:
		return
	get_viewport().set_input_as_handled()
	if _revealed:
		_close()
	else:
		reveal_immediately()


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.008, 0.015, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.04
	panel.anchor_top = 0.035
	panel.anchor_right = 0.96
	panel.anchor_bottom = 0.965
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "STRETCHMAN LOOT REEL"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 25)
	column.add_child(heading)
	var odds := Label.new()
	odds.text = (
		"Every tier: 10% high-quality hit • 90% Voltorb-family, baby, duo, "
		+ "Budew, Mantyke, or Bidoof pool"
	)
	odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(odds)

	_reel_window = Control.new()
	_reel_window.name = "ReelWindow"
	_reel_window.custom_minimum_size = Vector2(0.0, 180.0)
	_reel_window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reel_window.clip_contents = true
	column.add_child(_reel_window)
	_reel_track = HBoxContainer.new()
	_reel_track.name = "ReelTrack"
	_reel_track.add_theme_constant_override("separation", CARD_SEPARATION)
	_reel_track.position = Vector2(0.0, 14.0)
	_reel_window.add_child(_reel_track)

	var marker := ColorRect.new()
	marker.name = "MiddleKnob"
	marker.color = Color(1.0, 0.67, 0.12, 0.92)
	marker.anchor_left = 0.5
	marker.anchor_right = 0.5
	marker.anchor_bottom = 1.0
	marker.offset_left = -2.0
	marker.offset_right = 2.0
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reel_window.add_child(marker)
	var top_knob := Label.new()
	top_knob.text = "▼"
	top_knob.add_theme_font_size_override("font_size", 30)
	top_knob.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_knob.anchor_left = 0.5
	top_knob.anchor_right = 0.5
	top_knob.offset_left = -25.0
	top_knob.offset_right = 25.0
	top_knob.offset_top = -8.0
	top_knob.offset_bottom = 34.0
	top_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reel_window.add_child(top_knob)

	_status = Label.new()
	_status.name = "LootBoxStatus"
	_status.text = "The reel is spinning…"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_skip_button = Button.new()
	_skip_button.text = "Skip Animation"
	_skip_button.custom_minimum_size = Vector2(170.0, 48.0)
	_skip_button.pressed.connect(reveal_immediately)
	buttons.add_child(_skip_button)
	_close_button = Button.new()
	_close_button.text = "Prize Pending"
	_close_button.disabled = true
	_close_button.custom_minimum_size = Vector2(220.0, 48.0)
	_close_button.pressed.connect(_close)
	buttons.add_child(_close_button)


func _add_reel_card(pokemon_id: int) -> void:
	var pokemon := StretchGoalSystem.get_pokemon_offer(pokemon_id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	_reel_track.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(content)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _thumbnail_for(pokemon_id, pokemon)
	content.add_child(icon)
	var label := Label.new()
	label.text = String(pokemon.get("name", "Pokemon"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CARD_WIDTH - 18.0, 42.0)
	content.add_child(label)


func _thumbnail_for(pokemon_id: int, pokemon: Dictionary) -> Texture2D:
	if _thumbnail_cache.has(pokemon_id):
		return _thumbnail_cache[pokemon_id] as Texture2D
	var mapping := SpriteMapping.get_entry(pokemon_id)
	var sprite_id := String(mapping.get("spriteId", pokemon.get("slug", "missing-pokemon")))
	var thumbnail := _sprite_catalog.load_front_thumbnail(
		sprite_id,
		false,
		"",
		ICON_SIZE
	)
	var texture := thumbnail.get("texture") as Texture2D
	if texture != null:
		_thumbnail_cache[pokemon_id] = texture
	return texture


func _start_spin() -> void:
	await get_tree().process_frame
	if _reveal_pending or _revealed:
		return
	if _reel_track.get_child_count() <= WINNER_INDEX:
		_finish_spin()
		return
	var first_card := _reel_track.get_child(0) as Control
	_reel_track.position.x = _reel_window.size.x * 0.5 - first_card.size.x * 0.5
	var target_x := _winner_target_x()
	_spin_tween = create_tween()
	_spin_tween.set_trans(Tween.TRANS_QUINT)
	_spin_tween.set_ease(Tween.EASE_OUT)
	_spin_tween.tween_property(_reel_track, "position:x", target_x, spin_duration)
	_spin_tween.tween_callback(_finish_spin)


func _winner_target_x() -> float:
	var winner_card := _reel_track.get_child(WINNER_INDEX) as Control
	return _reel_window.size.x * 0.5 - (winner_card.position.x + winner_card.size.x * 0.5)


func _snap_winner_to_marker() -> void:
	if _reel_track.get_child_count() > WINNER_INDEX:
		_reel_track.position.x = _winner_target_x()
		# Theme/container rounding can leave a few subpixels after the local-space
		# calculation. Correct against the actual global knob center.
		var winner_card := _reel_track.get_child(WINNER_INDEX) as Control
		var winner_center := winner_card.global_position.x + winner_card.size.x * 0.5
		var marker_center := _reel_window.global_position.x + _reel_window.size.x * 0.5
		_reel_track.position.x += marker_center - winner_center


func _finish_spin() -> void:
	if _revealed:
		return
	_revealed = true
	_snap_winner_to_marker()
	var winner_name := String(_summary.get("pokemon_name", "Pokemon"))
	var quality := String(_summary.get("quality", "PRIZE"))
	_status.text = "%s — You got %s at Lv. %d!" % [
		quality,
		winner_name,
		int(_summary.get("level", 1)),
	]
	if _reel_track.get_child_count() > WINNER_INDEX:
		var winner_card := _reel_track.get_child(WINNER_INDEX) as PanelContainer
		var highlight := StyleBoxFlat.new()
		highlight.bg_color = Color(0.20, 0.13, 0.035, 1.0)
		highlight.border_color = Color(1.0, 0.69, 0.12, 1.0)
		highlight.set_border_width_all(4)
		highlight.set_corner_radius_all(10)
		highlight.content_margin_left = 0.0
		highlight.content_margin_top = 0.0
		highlight.content_margin_right = 0.0
		highlight.content_margin_bottom = 0.0
		winner_card.add_theme_stylebox_override("panel", highlight)
	_skip_button.visible = false
	_close_button.disabled = false
	_close_button.text = "Keep %s" % winner_name
	_close_button.grab_focus()


func _close() -> void:
	if not _revealed:
		return
	closed.emit()
	queue_free()
