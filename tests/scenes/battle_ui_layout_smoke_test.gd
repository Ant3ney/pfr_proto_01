extends Node

const BATTLE_UI := preload("res://game/battle/ui/battle_ui_overlay.tscn")
const UI_TEMPLATE := preload("res://game/ui/shared/ui_template.tscn")
const DESIGN_VIEWPORTS := [
	Vector2(960.0, 540.0),
	Vector2(1170.0, 540.0),
]
const MINIMUM_BUTTON_HEIGHT := 40.0
const MAXIMUM_COMPACT_PANEL_HEIGHT := 60.0
const MAXIMUM_STATUS_WIDTH := 288.0

var _failures: Array[String] = []


func _ready() -> void:
	for viewport_size in DESIGN_VIEWPORTS:
		var overlay := BATTLE_UI.instantiate() as Control
		add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		overlay.size = viewport_size
		await get_tree().process_frame
		await get_tree().process_frame
		_check_layout(overlay, viewport_size)
		overlay.queue_free()
		await get_tree().process_frame

	await _check_configured_presentation()

	if _failures.is_empty():
		print(
			"Battle UI layout smoke test passed: polished compact panels, "
			+ "responsive status widths, layered icon commands, deliberate states, "
			+ "title-case identity text, and authoritative HP colors are intact."
		)
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("Battle UI layout smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check_layout(overlay: Control, viewport_size: Vector2) -> void:
	var opponent_status := overlay.get_node(^"OpponentStatus") as PanelContainer
	var player_status := overlay.get_node(^"PlayerStatus") as PanelContainer
	var message_panel := overlay.get_node(^"MessagePanel") as PanelContainer
	var action_tray := overlay.get_node(^"ActionTray") as PanelContainer
	var viewport_label := "%dx%d" % [int(viewport_size.x), int(viewport_size.y)]

	for panel in [opponent_status, player_status, message_panel, action_tray]:
		_check(
			panel.size.y <= MAXIMUM_COMPACT_PANEL_HEIGHT,
			"%s %s should remain at most %.0f px tall; got %.1f px."
			% [viewport_label, panel.name, MAXIMUM_COMPACT_PANEL_HEIGHT, panel.size.y]
		)
		_check_stylebox_borders(panel.get_theme_stylebox(&"panel"), panel.name)
		_check(
			panel.get_node_or_null(^"Material/InnerFrame") != null,
			"%s should retain its nested material frame." % panel.name
		)

	_check(
		is_equal_approx(player_status.position.y, message_panel.position.y)
			and is_equal_approx(player_status.size.y, message_panel.size.y),
		"%s player status and message panel should share one compact row."
		% viewport_label
	)
	_check(
		is_equal_approx(
			player_status.position.y + player_status.size.y + 4.0,
			action_tray.position.y
		),
		"%s lower rows should use only a 4 px vertical gap." % viewport_label
	)
	_check(
		is_equal_approx(
			action_tray.position.y + action_tray.size.y,
			viewport_size.y - 4.0
		),
		"%s command tray should sit 4 px above the viewport bottom."
		% viewport_label
	)
	_check(
		player_status.size.x <= MAXIMUM_STATUS_WIDTH + 0.5
			and opponent_status.size.x <= MAXIMUM_STATUS_WIDTH + 0.5,
		"%s status cards should remain clamped near the mockup proportions."
		% viewport_label
	)
	_check(
		player_status.position.x >= 16.0
			and opponent_status.position.x + opponent_status.size.x
				<= viewport_size.x - 16.0 + 0.5,
		"%s status cards should respect compact landscape gutters." % viewport_label
	)
	_check(
		player_status.position.x + player_status.size.x + 8.0
			<= message_panel.position.x,
		"%s player status and message frame should not overlap." % viewport_label
	)
	_check(
		message_panel.position.x + message_panel.size.x
			<= viewport_size.x - 16.0 + 0.5,
		"%s message panel should remain inside the right gutter." % viewport_label
	)

	for margin_path in [
		^"OpponentStatus/Margin",
		^"PlayerStatus/Margin",
		^"MessagePanel/Margin",
		^"ActionTray/Margin",
	]:
		var margin := overlay.get_node(margin_path) as MarginContainer
		_check(
			margin.get_theme_constant(&"margin_top") <= 4
				and margin.get_theme_constant(&"margin_bottom") <= 4,
			"%s should use no more than 4 px of vertical padding."
			% margin_path
		)

	var expected_labels := {
		"FightButton": "Fight",
		"BagButton": "Bag",
		"PartyButton": "Pokémon",
		"RunButton": "Run",
	}
	for button_name: String in expected_labels:
		var button := overlay.get_node(
			"ActionTray/Margin/Actions/%s" % button_name
		) as Button
		_check(
			button.size.y >= MINIMUM_BUTTON_HEIGHT,
			"%s should remain at least %.0f px tall; got %.1f px."
			% [button_name, MINIMUM_BUTTON_HEIGHT, button.size.y]
		)
		_check(
			button.text == expected_labels[button_name],
			"%s should expose its title-case accessible label." % button_name
		)
		var icon := button.get_node_or_null(^"ActionContent/ActionIcon") as TextureRect
		var label := button.get_node_or_null(^"ActionContent/ActionLabel") as Label
		_check(
			icon != null and icon.texture != null and minf(icon.size.x, icon.size.y) >= 22.0,
			"%s should display its imported reference icon." % button_name
		)
		_check(
			label != null and label.text == expected_labels[button_name],
			"%s should display its layered title-case label." % button_name
		)
		for layer_name in [&"UpperShine", &"SpecularLine", &"LowerShade"]:
			_check(
				button.get_node_or_null(NodePath(String(layer_name))) != null,
				"%s should retain its %s material layer."
				% [button_name, layer_name]
			)
		for style_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
			_check_stylebox_borders(
				button.get_theme_stylebox(style_name),
				"%s %s state" % [button_name, style_name]
			)
		var normal := button.get_theme_stylebox(&"normal") as StyleBoxFlat
		var disabled := button.get_theme_stylebox(&"disabled") as StyleBoxFlat
		_check(
			normal != null and disabled != null and normal.bg_color != disabled.bg_color,
			"%s should use an explicit muted disabled state." % button_name
		)


func _check_configured_presentation() -> void:
	var template := UI_TEMPLATE.instantiate() as UITemplate
	add_child(template)
	template.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	template.size = DESIGN_VIEWPORTS[0]
	await get_tree().process_frame
	template.play_battle_ui_in({
		"player_pokemon_name": "palkia",
		"player_level": 100,
		"player_health": 0.4,
		"player_experience_progress": 0.37,
		"opponent_pokemon_name": "CustomCase",
		"opponent_level": 7,
		"opponent_health": 0.15,
		"can_bag": false,
	})
	await get_tree().process_frame
	await get_tree().process_frame

	var player_name := template.get_node(
		^"BattleUIOverlay/PlayerStatus/Margin/Content/Identity/PlayerName"
	) as Label
	var player_level := template.get_node(
		^"BattleUIOverlay/PlayerStatus/Margin/Content/Identity/PlayerLevel"
	) as Label
	var opponent_name := template.get_node(
		^"BattleUIOverlay/OpponentStatus/Margin/Content/Identity/OpponentName"
	) as Label
	var opponent_level := template.get_node(
		^"BattleUIOverlay/OpponentStatus/Margin/Content/Identity/OpponentLevel"
	) as Label
	var player_hp := template.get_node(
		^"BattleUIOverlay/PlayerStatus/Margin/Content/Health/PlayerHP"
	) as ProgressBar
	var player_xp := template.get_node(
		^"BattleUIOverlay/PlayerStatus/Margin/Content/Experience/PlayerXP"
	) as ProgressBar
	var opponent_hp := template.get_node(
		^"BattleUIOverlay/OpponentStatus/Margin/Content/Health/OpponentHP"
	) as ProgressBar
	var bag_button := template.get_node(
		^"BattleUIOverlay/ActionTray/Margin/Actions/BagButton"
	) as Button

	_check(player_name.text == "Palkia", "Canonical lower-case names should render as title case.")
	_check(player_level.text == "Lv. 100", "Player level should use mockup-style casing.")
	_check(opponent_name.text == "CustomCase", "Nickname casing should be preserved.")
	_check(opponent_level.text == "Lv. 7", "Opponent level should use mockup-style casing.")
	_check(is_equal_approx(player_hp.value, 0.4), "Player HP should remain snapshot-authoritative.")
	_check(
		is_equal_approx(player_xp.value, 0.37),
		"Player XP progress should remain collection-authoritative."
	)
	_check(
		player_xp.size.y <= 3.0 and player_xp.custom_minimum_size.y <= 3.0,
		"The player XP strip should remain barely 3 px tall."
	)
	_check(is_equal_approx(opponent_hp.value, 0.15), "Opponent HP should remain snapshot-authoritative.")
	_check(
		_color_near(
			(player_hp.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color,
			Color(0.96, 0.72, 0.18, 1.0)
		),
		"Mid HP should use the polished amber warning fill."
	)
	_check(
		_color_near(
			(opponent_hp.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color,
			Color(0.9, 0.18, 0.1, 1.0)
		),
		"Low HP should use the polished red danger fill."
	)
	_check(bag_button.disabled, "Bag should remain visibly unavailable when presentation data disables it.")

	template.queue_free()
	await get_tree().process_frame


func _check_stylebox_borders(stylebox: StyleBox, control_name: String) -> void:
	var flat := stylebox as StyleBoxFlat
	_check(flat != null, "%s should use a StyleBoxFlat." % control_name)
	if not flat:
		return
	_check(
		flat.border_width_left <= 2
			and flat.border_width_top <= 2
			and flat.border_width_right <= 2
			and flat.border_width_bottom <= 2,
		"%s borders should remain at or below 2 px." % control_name
	)


func _color_near(left: Color, right: Color) -> bool:
	return (
		is_equal_approx(left.r, right.r)
		and is_equal_approx(left.g, right.g)
		and is_equal_approx(left.b, right.b)
		and is_equal_approx(left.a, right.a)
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
