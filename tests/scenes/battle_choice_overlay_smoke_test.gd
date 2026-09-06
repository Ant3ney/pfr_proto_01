extends Node

const CHOICE_OVERLAY := preload("res://game/battle/ui/battle_choice_overlay.tscn")
const DESIGN_SIZE := Vector2(960.0, 540.0)
const WIDE_PHONE_SIZE := Vector2(1170.0, 540.0)

var _failures: Array[String] = []
var _host: Control
var _overlay
var _chosen_moves: Array[int] = []
var _chosen_switches: Array[String] = []


func _ready() -> void:
	_host = Control.new()
	_host.size = DESIGN_SIZE
	add_child(_host)
	_overlay = CHOICE_OVERLAY.instantiate()
	_host.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.move_chosen.connect(func(move_index: int) -> void: _chosen_moves.append(move_index))
	_overlay.switch_chosen.connect(func(member_id: String) -> void: _chosen_switches.append(member_id))
	await _settle_layout()

	await _test_moves_are_request_ordered_typed_and_compact()
	await _test_switches_are_request_driven_and_forced_safe()
	await _test_full_bench_thumbnails_remain_compact()
	await _test_phone_width_geometry()
	await _test_compact_modal_ctas()

	if _failures.is_empty():
		print(
			"Battle choice overlay smoke test passed: move and switch trays are "
			+ "request-driven, typed, front-sprite illustrated, 56 px compact, "
			+ "forced-switch safe, and modal CTAs remain centered and explicit."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Battle choice overlay smoke test failed: %s" % failure)
	get_tree().quit(1)


func _test_moves_are_request_ordered_typed_and_compact() -> void:
	var request := {
		"moves": [
			_move(3, "tackle", "Tackle", 34, 35, false),
			_move(1, "waterpulse", "Water Pulse", 0, 20, true),
			_move(4, "dragonbreath", "Dragon Breath", 17, 20, false),
			_move(2, "scaryface", "Scary Face", 10, 10, false),
			_move(99, "gust", "Ignored Fifth Move", 35, 35, false),
		],
	}
	_overlay.show_moves(request)
	await _settle_layout()
	var buttons := _dynamic_buttons()
	_check(buttons.size() == 4, "Move tray should render at most four server moves.")
	if buttons.size() < 4:
		return

	var indices: Array[int] = []
	for button in buttons:
		indices.append(int(button.get_meta("battle_move_index", -1)))
	_check(indices == [3, 1, 4, 2], "Move buttons should preserve exact server order and moveIndex values; got %s." % [indices])
	_check(buttons[0].text.begins_with("Tackle\n"), "The first move should retain its server display name.")
	_check("NORMAL" in buttons[0].text, "Tackle should show its mapped Normal type.")
	_check("PP 34/35" in buttons[0].text, "Tackle should show exact current and maximum PP.")
	_check("WATER" in buttons[1].text, "Water Pulse should show its mapped Water type.")
	_check("PP 0/20" in buttons[1].text, "Disabled moves should retain exact PP.")
	_check("[LOCKED]" in buttons[1].text, "Disabled moves should have an explicit locked label.")
	_check(buttons[1].disabled, "The server-disabled move should be a disabled Button.")
	_check(not _overlay.dim.visible, "Move choices must not dim the battlefield.")
	_check(_overlay.cancel_button.visible, "The move tray should include Back.")
	_check(_overlay.cancel_button.text.contains("BACK"), "The voluntary tray CTA should be labelled Back.")
	_check_tray_geometry(DESIGN_SIZE)
	_check_button_state_styles(buttons[0], "move")
	_check_button_state_styles(_overlay.cancel_button, "Back")

	buttons[1].pressed.emit()
	_check(_chosen_moves.is_empty(), "A disabled move must not emit move_chosen even if its pressed signal is invoked.")
	buttons[0].pressed.emit()
	_check(_chosen_moves == [3], "An enabled move should emit its exact typed moveIndex; got %s." % [_chosen_moves])
	_check(not _overlay.visible, "Choosing an enabled move should close the tray.")


func _test_switches_are_request_driven_and_forced_safe() -> void:
	var request := {
		"switchOptions": [
			{"memberId": "member-c"},
			{"memberId": "member-b"},
		],
	}
	var snapshot := {
		"parties": {
			"player": [
				_member("member-a", "Palkia", 90, 100),
				_member("member-b", "Hoothoot", 18, 24),
				_member("member-c", "Vespiquen", 7, 31, "BeeQueen"),
				_member("not-returned", "Luxray", 30, 30),
			],
		},
	}

	_overlay.show_switches(request, snapshot, false)
	await _settle_layout()
	var buttons := _dynamic_buttons()
	_check(buttons.size() == 2, "Switch tray should render only returned member IDs.")
	if buttons.size() >= 2:
		_check(
			String(buttons[0].get_meta("battle_switch_member_id", "")) == "member-c"
				and String(buttons[1].get_meta("battle_switch_member_id", "")) == "member-b",
			"Switch choices should preserve the server's memberId order."
		)
		_check("BeeQueen" in buttons[0].text and "HP 7/31" in buttons[0].text, "Switch labels should preserve nickname casing and show authoritative HP.")
		_check("Hoothoot" in buttons[1].text and "HP 18/24" in buttons[1].text, "Each switch label should show name and HP.")
		_check_switch_thumbnail(buttons[0], "vespiquen")
		_check_switch_thumbnail(buttons[1], "hoothoot")
	_check(_overlay.cancel_button.visible, "A voluntary switch should expose Back.")
	var released_button: Button = buttons[0] if not buttons.is_empty() else null
	_overlay.hide_overlay()
	_check(not _overlay.visible, "A voluntary switch should be cancellable.")
	if released_button != null:
		_check(
			released_button.icon == null,
			"Closing the switch tray should release its thumbnail texture reference."
		)

	_overlay.show_switches(
		{"switchOptions": [{"memberId": "missing-form"}]},
		{"parties": {"player": [
			_member("missing-form", "Missing Form", 12, 12, "", "definitely-missing-form"),
		]}},
		false
	)
	await _settle_layout()
	var missing_buttons := _dynamic_buttons()
	_check(missing_buttons.size() == 1, "A returned unsupported exact form should still have a switch card.")
	if missing_buttons.size() == 1:
		_check(missing_buttons[0].icon != null, "An unsupported exact form should show the neutral thumbnail.")
		_check(
			bool(missing_buttons[0].get_meta("battle_switch_thumbnail_placeholder", false))
			and String(missing_buttons[0].get_meta(
				"battle_switch_thumbnail_placeholder_reason", ""
			)) == "exact_sprite_missing",
			"Unsupported exact forms must use the neutral placeholder without substituting art."
		)
	_overlay.force_hide()

	_overlay.show_switches(request, snapshot, true)
	await _settle_layout()
	buttons = _dynamic_buttons()
	_check(not _overlay.cancel_button.visible, "A forced switch must not expose Back.")
	_overlay.hide_overlay()
	_check(_overlay.visible, "hide_overlay must not cancel a forced switch.")
	if buttons.size() >= 2:
		buttons[1].pressed.emit()
	_check(_chosen_switches == ["member-b"], "Switch choice should emit the exact returned memberId; got %s." % [_chosen_switches])
	_check(not _overlay.visible, "Choosing a forced replacement should close the tray.")


func _test_full_bench_thumbnails_remain_compact() -> void:
	var member_specs := [
		["member-mothim", "Mothim", "mothim", 23, 23],
		["member-hoothoot", "Hoothoot", "hoothoot", 18, 24],
		["member-vespiquen", "Vespiquen", "vespiquen", 31, 31],
		["member-luxray", "Luxray", "luxray", 28, 35],
		["member-pelipper", "Pelipper", "pelipper", 29, 34],
	]
	var switch_options: Array[Dictionary] = []
	var members: Array[Dictionary] = []
	for spec: Array in member_specs:
		switch_options.append({"memberId": String(spec[0])})
		members.append(_member(
			String(spec[0]),
			String(spec[1]),
			int(spec[3]),
			int(spec[4]),
			"",
			String(spec[2])
		))
	_overlay.show_switches(
		{"switchOptions": switch_options},
		{"parties": {"player": members}},
		false
	)
	await _settle_layout()
	var buttons := _dynamic_buttons()
	_check(buttons.size() == 5, "A full five-member bench should fit in the compact switch tray.")
	for index in mini(buttons.size(), member_specs.size()):
		var sprite_id := String(member_specs[index][2])
		_check_switch_thumbnail(buttons[index], sprite_id)
		_check(
			buttons[index].position.x >= -0.01
			and buttons[index].position.x + buttons[index].size.x <= _overlay.options.size.x + 0.01,
			"%s switch card should remain inside the options row." % sprite_id
		)
	_check_tray_geometry(DESIGN_SIZE)
	_overlay.force_hide()


func _test_phone_width_geometry() -> void:
	_host.size = WIDE_PHONE_SIZE
	await _settle_layout()
	_overlay.show_moves({
		"moves": [
			_move(1, "tackle", "Tackle", 35, 35, false),
			_move(2, "gust", "Gust", 35, 35, false),
			_move(3, "hypnosis", "Hypnosis", 20, 20, false),
			_move(4, "peck", "Peck", 35, 35, false),
		],
	})
	await _settle_layout()
	_check_tray_geometry(WIDE_PHONE_SIZE)
	var buttons := _dynamic_buttons()
	for button in buttons:
		_check(button.size.y >= 40.0, "%s should retain a 40 px touch target at wide-phone aspect." % button.text.get_slice("\n", 0))
	_overlay.force_hide()
	_host.size = DESIGN_SIZE
	await _settle_layout()


func _test_compact_modal_ctas() -> void:
	_overlay.show_forfeit_confirmation()
	await _settle_layout()
	_check(_overlay.dim.visible, "Forfeit confirmation should dim the battlefield.")
	_check(_overlay.cancel_button.visible and _overlay.confirm_button.visible, "Forfeit confirmation should show Keep Battling and Forfeit.")
	_check(not _overlay.retry_button.visible and not _overlay.return_button.visible and not _overlay.continue_button.visible, "Forfeit confirmation should hide unrelated CTAs.")
	_check_modal_geometry("forfeit")

	_overlay.show_error({"message": "The request timed out.", "retriable": true, "can_return": true})
	await _settle_layout()
	_check(_overlay.retry_button.visible and _overlay.return_button.visible, "A retriable error should expose Retry and Return.")
	_check(not _overlay.cancel_button.visible and not _overlay.confirm_button.visible and not _overlay.continue_button.visible, "Error modal should hide unrelated CTAs.")
	_check_modal_geometry("error")

	_overlay.show_result({"winner": "player"})
	await _settle_layout()
	_check(_overlay.continue_button.visible, "A result should expose Continue.")
	_check(not _overlay.cancel_button.visible and not _overlay.confirm_button.visible and not _overlay.retry_button.visible and not _overlay.return_button.visible, "Result modal should hide unrelated CTAs.")
	_check(_overlay.title_label.text == "VICTORY", "Player result should show Victory.")
	_check_modal_geometry("result")
	_overlay.force_hide()


func _check_tray_geometry(viewport_size: Vector2) -> void:
	var gutter := maxf(16.0, viewport_size.x * 0.015)
	var expected_left := gutter
	var expected_right := viewport_size.x - gutter
	_check(is_equal_approx(_overlay.panel.position.x, expected_left), "Tray left edge should match the ActionTray's %.2f px responsive gutter at %.0f px width; got %.2f." % [gutter, viewport_size.x, _overlay.panel.position.x])
	_check(is_equal_approx(_overlay.panel.position.x + _overlay.panel.size.x, expected_right), "Tray right edge should match the ActionTray's responsive gutter at %.0f px width." % viewport_size.x)
	_check(is_equal_approx(_overlay.panel.position.y, viewport_size.y - 60.0), "Tray top should use a -60 px bottom offset.")
	_check(is_equal_approx(_overlay.panel.size.y, 56.0), "Tray should be exactly 56 px high; got %.2f." % _overlay.panel.size.y)
	_check(is_equal_approx(_overlay.panel.position.y + _overlay.panel.size.y, viewport_size.y - 4.0), "Tray should finish 4 px above the viewport bottom.")
	for button in _dynamic_buttons():
		_check(button.size.y >= 40.0, "%s should retain a 40 px touch target; got %.2f." % [button.text.get_slice("\n", 0), button.size.y])


func _check_modal_geometry(label: String) -> void:
	_check(_overlay.dim.visible, "%s modal should use the dim layer." % label.capitalize())
	_check(_overlay.panel.size.y <= 200.0, "%s modal should remain compact, not the former 400 px height; got %.2f." % [label.capitalize(), _overlay.panel.size.y])
	_check(is_equal_approx(_overlay.panel.position.x + _overlay.panel.size.x * 0.5, DESIGN_SIZE.x * 0.5), "%s modal should be horizontally centered." % label.capitalize())
	_check(is_equal_approx(_overlay.panel.position.y + _overlay.panel.size.y * 0.5, DESIGN_SIZE.y * 0.5), "%s modal should be vertically centered." % label.capitalize())


func _check_button_state_styles(button: Button, label: String) -> void:
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		_check(button.get_theme_stylebox(state) is StyleBoxFlat, "%s should have a deliberate StyleBoxFlat %s state." % [label, state])


func _check_switch_thumbnail(button: Button, sprite_id: String) -> void:
	_check(button.icon != null, "%s switch card should include a Pokémon thumbnail." % sprite_id)
	if button.icon == null:
		return
	_check(
		button.icon.get_size() == Vector2(32.0, 32.0),
		"%s thumbnail should fit the compact 32 px image well; got %s."
		% [sprite_id, str(button.icon.get_size())]
	)
	_check(
		String(button.get_meta("battle_switch_sprite_id", "")) == sprite_id,
		"%s switch card should retain its exact sprite identity." % sprite_id
	)
	_check(
		String(button.get_meta("battle_switch_thumbnail_style", "")) == "ani",
		"%s switch card should use the front-facing ani GIF style." % sprite_id
	)
	_check(
		not bool(button.get_meta("battle_switch_thumbnail_placeholder", true)),
		"Supported sprite %s should not use the neutral placeholder." % sprite_id
	)
	_check(
		String(button.get_meta("battle_switch_thumbnail_atlas_path", ""))
		== "res://art/battle/sprites/generated/ani/%s.png" % sprite_id,
		"%s switch card should come from its exact generated front atlas." % sprite_id
	)
	_check(
		button.icon.get_image().get_used_rect().has_area(),
		"%s switch thumbnail should contain visible pixels." % sprite_id
	)


func _dynamic_buttons() -> Array[Button]:
	var result: Array[Button] = []
	for child in _overlay.options.get_children():
		if child is Button and bool(child.get_meta("battle_option_dynamic", false)):
			result.append(child as Button)
	return result


func _move(index: int, id: String, display_name: String, pp: int, max_pp: int, disabled: bool) -> Dictionary:
	return {
		"moveIndex": index,
		"id": id,
		"name": display_name,
		"pp": pp,
		"maxPp": max_pp,
		"disabled": disabled,
	}


func _member(
	id: String,
	species: String,
	hp: int,
	max_hp: int,
	nickname := "",
	sprite_id := ""
) -> Dictionary:
	return {
		"memberId": id,
		"species": species,
		"nickname": nickname if not nickname.is_empty() else species,
		"hp": hp,
		"maxHp": max_hp,
		"spriteId": sprite_id if not sprite_id.is_empty() else species.to_lower().replace(" ", "-"),
	}


func _settle_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
