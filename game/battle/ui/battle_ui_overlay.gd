extends Control

## Presentation-only polish for the compact battle HUD. Battle ownership stays
## in BattleSystem/UITemplate; this script only keeps layered button contents
## legible across enabled, disabled, and narrow landscape states.

const ACTION_BUTTON_NAMES: Array[StringName] = [
	&"FightButton",
	&"BagButton",
	&"PartyButton",
	&"RunButton",
]
const ENABLED_CONTENT := Color.WHITE
const DISABLED_CONTENT := Color(0.7, 0.72, 0.68, 0.48)
const ENABLED_MATERIAL := Color.WHITE
const DISABLED_MATERIAL := Color(0.68, 0.7, 0.66, 0.42)
const MINIMUM_GUTTER := 16.0
const GUTTER_RATIO := 0.015
const STATUS_WIDTH_RATIO := 0.26
const MINIMUM_STATUS_WIDTH := 236.0
const MAXIMUM_STATUS_WIDTH := 288.0
const INFO_ROW_GAP := 10.0


func _ready() -> void:
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()
	_sync_action_button_materials()


func _process(_delta: float) -> void:
	_sync_action_button_materials()


func _update_responsive_layout() -> void:
	var gutter := maxf(MINIMUM_GUTTER, size.x * GUTTER_RATIO)
	var status_width := clampf(
		size.x * STATUS_WIDTH_RATIO,
		MINIMUM_STATUS_WIDTH,
		MAXIMUM_STATUS_WIDTH
	)
	var opponent_status := get_node_or_null(^"OpponentStatus") as Control
	var player_status := get_node_or_null(^"PlayerStatus") as Control
	var message_panel := get_node_or_null(^"MessagePanel") as Control
	var action_tray := get_node_or_null(^"ActionTray") as Control
	if opponent_status:
		opponent_status.anchor_left = 1.0
		opponent_status.anchor_right = 1.0
		opponent_status.offset_left = -gutter - status_width
		opponent_status.offset_right = -gutter
	if player_status:
		player_status.anchor_left = 0.0
		player_status.anchor_right = 0.0
		player_status.offset_left = gutter
		player_status.offset_right = gutter + status_width
	if message_panel:
		message_panel.anchor_left = 0.0
		message_panel.anchor_right = 1.0
		message_panel.offset_left = gutter + status_width + INFO_ROW_GAP
		message_panel.offset_right = -gutter
	if action_tray:
		action_tray.anchor_left = 0.0
		action_tray.anchor_right = 1.0
		action_tray.offset_left = gutter
		action_tray.offset_right = -gutter

	var narrow := size.x < 860.0
	var icon_extent := 23.0 if narrow else 27.0
	var font_size := 17 if narrow else 19
	var separation := 4 if narrow else 6
	for button_name in ACTION_BUTTON_NAMES:
		var button := find_child(String(button_name), true, false) as Button
		if not button:
			continue
		var content := button.get_node_or_null(^"ActionContent") as HBoxContainer
		var icon := button.get_node_or_null(^"ActionContent/ActionIcon") as TextureRect
		var label := button.get_node_or_null(^"ActionContent/ActionLabel") as Label
		if content:
			content.add_theme_constant_override(&"separation", separation)
		if icon:
			icon.custom_minimum_size = Vector2(icon_extent, icon_extent)
		if label:
			label.add_theme_font_size_override(&"font_size", font_size)


func _sync_action_button_materials() -> void:
	for button_name in ACTION_BUTTON_NAMES:
		var button := find_child(String(button_name), true, false) as Button
		if not button:
			continue
		var content := button.get_node_or_null(^"ActionContent") as Control
		if content:
			content.modulate = DISABLED_CONTENT if button.disabled else ENABLED_CONTENT
		for layer_name in [&"UpperShine", &"SpecularLine", &"LowerShade"]:
			var layer := button.get_node_or_null(NodePath(String(layer_name))) as CanvasItem
			if layer:
				layer.modulate = DISABLED_MATERIAL if button.disabled else ENABLED_MATERIAL
