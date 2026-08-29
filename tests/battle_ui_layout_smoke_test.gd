extends Node

const BATTLE_UI := preload("res://core/ui/battle_ui_overlay.tscn")
const DESIGN_VIEWPORT := Vector2(960.0, 540.0)
const MINIMUM_BUTTON_HEIGHT := 40.0
const MAXIMUM_COMPACT_PANEL_HEIGHT := 60.0

var _failures: Array[String] = []


func _ready() -> void:
	var overlay := BATTLE_UI.instantiate() as Control
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	overlay.size = DESIGN_VIEWPORT
	await get_tree().process_frame
	await get_tree().process_frame

	var opponent_status := overlay.get_node(^"OpponentStatus") as PanelContainer
	var player_status := overlay.get_node(^"PlayerStatus") as PanelContainer
	var message_panel := overlay.get_node(^"MessagePanel") as PanelContainer
	var action_tray := overlay.get_node(^"ActionTray") as PanelContainer

	for panel in [opponent_status, player_status, message_panel, action_tray]:
		_check(
			panel.size.y <= MAXIMUM_COMPACT_PANEL_HEIGHT,
			"%s should remain at most %.0f px tall; got %.1f px."
			% [panel.name, MAXIMUM_COMPACT_PANEL_HEIGHT, panel.size.y]
		)
		_check_stylebox_borders(panel.get_theme_stylebox(&"panel"), panel.name)

	_check(
		is_equal_approx(player_status.position.y, message_panel.position.y)
			and is_equal_approx(player_status.size.y, message_panel.size.y),
		"The player status and message panel should share one compact row."
	)
	_check(
		is_equal_approx(
			player_status.position.y + player_status.size.y + 4.0,
			action_tray.position.y
		),
		"The lower rows should use only a 4 px vertical gap."
	)
	_check(
		is_equal_approx(
			action_tray.position.y + action_tray.size.y,
			DESIGN_VIEWPORT.y - 4.0
		),
		"The command tray should sit 4 px above the viewport bottom."
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

	for button_name in ["FightButton", "BagButton", "PartyButton", "RunButton"]:
		var button := overlay.get_node(
			"ActionTray/Margin/Actions/%s" % button_name
		) as Button
		_check(
			button.size.y >= MINIMUM_BUTTON_HEIGHT,
			"%s should remain at least %.0f px tall; got %.1f px."
			% [button_name, MINIMUM_BUTTON_HEIGHT, button.size.y]
		)
		for style_name in [&"normal", &"hover", &"pressed", &"focus"]:
			_check_stylebox_borders(
				button.get_theme_stylebox(style_name),
				"%s %s state" % [button_name, style_name]
			)

	if _failures.is_empty():
		print(
			"Battle UI layout smoke test passed: compact panels stay at or below "
			+ "60 px, lower rows are bottom-pinned, and all command buttons retain "
			+ "40 px touch targets."
		)
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("Battle UI layout smoke test failed: %s" % failure)
	get_tree().quit(1)


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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
