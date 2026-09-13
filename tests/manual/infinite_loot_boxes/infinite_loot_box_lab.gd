extends Control

## Developer-only loot-box lab. Every opening uses the production reward roll
## and roulette, but the player's balance is restored immediately afterward.

const LootBoxScene := preload(
	"res://game/economy/loot_boxes/loot_box_roulette.tscn"
)
const MAX_RECENT_PRIZES := 4

@onready var _selected_tier: Label = %SelectedTier
@onready var _selected_details: Label = %SelectedDetails
@onready var _open_button: Button = %OpenButton
@onready var _status: Label = %Status
@onready var _recent_prizes_label: Label = %RecentPrizes

var _offers: Array[Dictionary] = []
var _tier_buttons: Array[Button] = []
var _selected_index := 0
var _opened_count := 0
var _recent_prizes: Array[String] = []
var _roulette: LootBoxRoulette
var _opening := false


func _ready() -> void:
	_tier_buttons = [%Tier1, %Tier2, %Tier3, %Tier4, %Tier5, %Tier6]
	_offers = ShopSystem.get_loot_box_catalog()
	for index in _tier_buttons.size():
		_tier_buttons[index].pressed.connect(select_tier.bind(index))
	_open_button.pressed.connect(open_selected_box)
	if _offers.is_empty():
		_open_button.disabled = true
		_status.text = "No loot-box offers are available."
		return
	select_tier(_offers.size() - 1)
	_open_button.grab_focus()


func _input(event: InputEvent) -> void:
	if _opening or is_instance_valid(_roulette):
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var pressed_key := key_event.physical_keycode
	if pressed_key == KEY_NONE:
		pressed_key = key_event.keycode
	var tier_index := -1
	match pressed_key:
		KEY_1:
			tier_index = 0
		KEY_2:
			tier_index = 1
		KEY_3:
			tier_index = 2
		KEY_4:
			tier_index = 3
		KEY_5:
			tier_index = 4
		KEY_6:
			tier_index = 5
		KEY_SPACE:
			open_selected_box()
			get_viewport().set_input_as_handled()
			return
	if tier_index >= 0 and tier_index < _offers.size():
		open_tier(tier_index)
		get_viewport().set_input_as_handled()


func get_opened_count() -> int:
	return _opened_count


func get_selected_box_id() -> String:
	if _offers.is_empty():
		return ""
	return String(_offers[_selected_index].get("id", ""))


func get_active_roulette() -> LootBoxRoulette:
	return _roulette


func select_tier(index: int) -> void:
	if _offers.is_empty():
		return
	_selected_index = clampi(index, 0, _offers.size() - 1)
	for button_index in _tier_buttons.size():
		_tier_buttons[button_index].button_pressed = button_index == _selected_index
	var offer := _offers[_selected_index]
	_selected_tier.text = "%s  •  %s" % [
		String(offer.get("tier", "Tier")),
		String(offer.get("name", "Loot Box")).to_upper(),
	]
	_selected_details.text = (
		"Lv. %d prize  •  10%% high-quality chance\n%s"
		% [
			int(offer.get("level", 1)),
			String(offer.get("quality_label", "Premium Pokémon")),
		]
	)
	_open_button.text = "OPEN %s — FREE  ∞" % String(
		offer.get("name", "Loot Box")
	).to_upper()


func open_tier(index: int) -> Dictionary:
	select_tier(index)
	return open_selected_box()


func open_selected_box() -> Dictionary:
	if _opening or is_instance_valid(_roulette):
		return {"ok": false, "error": "Finish the current loot-box reveal first."}
	if _offers.is_empty():
		return {"ok": false, "error": "No loot-box offers are available."}
	_opening = true
	_open_button.disabled = true
	var offer := _offers[_selected_index]
	var result := _buy_without_spending(offer)
	if not bool(result.get("ok", false)):
		_opening = false
		_open_button.disabled = false
		_status.text = String(result.get("error", "The loot box could not open."))
		return result

	var summary := (result.get("summary", {}) as Dictionary).duplicate(true)
	# The roulette heading should describe this scene's free opening rather than
	# the production shop price that was used to choose the tier.
	summary["price"] = 0
	_opened_count += 1
	_record_prize(summary)
	_roulette = LootBoxScene.instantiate() as LootBoxRoulette
	if _roulette == null:
		_opening = false
		_open_button.disabled = false
		_status.text = "Prize awarded, but the roulette could not be displayed."
		return {"ok": false, "error": _status.text, "summary": summary}
	_roulette.spin_duration = 2.4
	_roulette.closed.connect(_on_roulette_closed)
	add_child(_roulette)
	_roulette.present(summary)
	_opening = false
	_status.text = "Opening box #%d…" % _opened_count
	return {"ok": true, "summary": summary}


func _buy_without_spending(offer: Dictionary) -> Dictionary:
	var original_balance := EconomySystem.get_balance()
	var price := int(offer.get("price", 0))
	if original_balance < price:
		EconomySystem.grant_money(price - original_balance)
	var result := ShopSystem.buy_loot_box(String(offer.get("id", "")))
	_restore_balance(original_balance)
	return result


func _restore_balance(target_balance: int) -> void:
	var current_balance := EconomySystem.get_balance()
	if current_balance > target_balance:
		EconomySystem.spend_money(current_balance - target_balance)
	elif current_balance < target_balance:
		EconomySystem.grant_money(target_balance - current_balance)


func _record_prize(summary: Dictionary) -> void:
	var quality_marker := "★" if bool(summary.get("high_quality", false)) else "•"
	_recent_prizes.push_front("%s  %s  •  Lv. %d  •  %s" % [
		quality_marker,
		String(summary.get("pokemon_name", "Pokémon")),
		int(summary.get("level", 1)),
		String(summary.get("quality", "PRIZE")),
	])
	if _recent_prizes.size() > MAX_RECENT_PRIZES:
		_recent_prizes.resize(MAX_RECENT_PRIZES)
	_recent_prizes_label.text = "RECENT  " + "     ".join(_recent_prizes)


func _on_roulette_closed() -> void:
	_roulette = null
	_open_button.disabled = false
	_status.text = (
		"%d free box%s opened. Every reward is in temporary storage for this run."
		% [_opened_count, "" if _opened_count == 1 else "es"]
	)
	_open_button.grab_focus.call_deferred()
