class_name InventoryService
extends Node

## Owns persistent bag quantities, one-time gifts, and held-item transfers.

signal progression_changed
signal inventory_changed

const MAX_ITEM_QUANTITY := 999_999
const XP_SHARE_ITEM_KEY := "exp-share"

var _item_quantities: Dictionary = {}
var _claimed_gifts: Dictionary = {}
var _last_error := ""


func get_item_count(item_key: String) -> int:
	return int(_item_quantities.get(item_key.strip_edges(), 0))


func get_item_inventory() -> Dictionary:
	return _item_quantities.duplicate(true)


func has_claimed_gift(gift_id: String) -> bool:
	return _claimed_gifts.has(gift_id.strip_edges())


func get_claimed_gift_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _claimed_gifts.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func can_add_item(item_key: String, quantity := 1) -> bool:
	var normalized_key := item_key.strip_edges()
	return (
		quantity > 0
		and ShopSystem.has_item(normalized_key)
		and get_item_count(normalized_key) <= MAX_ITEM_QUANTITY - quantity
	)


func add_item(item_key: String, quantity := 1) -> Dictionary:
	_last_error = ""
	var normalized_key := item_key.strip_edges()
	if not ShopSystem.has_item(normalized_key):
		return _failure("Unknown inventory item: %s" % normalized_key)
	if quantity <= 0:
		return _failure("Item quantity must be at least one.")
	if not can_add_item(normalized_key, quantity):
		return _failure("There is no room for that item in the bag.")
	var updated_quantity := get_item_count(normalized_key) + quantity
	_item_quantities[normalized_key] = updated_quantity
	_emit_change()
	return {
		"ok": true,
		"summary": {
			"kind": "item_added",
			"id": normalized_key,
			"quantity": quantity,
			"total": updated_quantity,
		},
	}


func claim_unique_item(gift_id: String, item_key: String) -> Dictionary:
	_last_error = ""
	var normalized_gift_id := gift_id.strip_edges()
	var normalized_item_key := item_key.strip_edges()
	if not _is_progress_key(normalized_gift_id):
		return _failure("That world gift has an invalid ID.")
	var item := ShopSystem.get_item_offer(normalized_item_key)
	if item.is_empty():
		return _failure("That world gift references an unknown item.")
	var summary := {
		"kind": "unique_item_gift",
		"gift_id": normalized_gift_id,
		"id": normalized_item_key,
		"name": String(item.get("name", normalized_item_key)),
	}
	if _claimed_gifts.has(normalized_gift_id):
		summary["newly_claimed"] = false
		return {"ok": true, "summary": summary}
	if not can_add_item(normalized_item_key):
		return _failure("There is no room for that item in the bag.")
	_item_quantities[normalized_item_key] = get_item_count(normalized_item_key) + 1
	_claimed_gifts[normalized_gift_id] = true
	summary["newly_claimed"] = true
	summary["quantity"] = get_item_count(normalized_item_key)
	_emit_change()
	return {"ok": true, "summary": summary}


func discard_item(item_key: String, quantity := 1) -> Dictionary:
	_last_error = ""
	var normalized_key := item_key.strip_edges()
	var item := ShopSystem.get_item_offer(normalized_key)
	if item.is_empty():
		return _failure("Unknown inventory item: %s" % normalized_key)
	if quantity <= 0:
		return _failure("Discard quantity must be at least one.")
	var current_quantity := get_item_count(normalized_key)
	if current_quantity < quantity:
		return _failure("You only have %d of that item in the bag." % current_quantity)
	var remaining := current_quantity - quantity
	if remaining == 0:
		_item_quantities.erase(normalized_key)
	else:
		_item_quantities[normalized_key] = remaining
	_emit_change()
	return {
		"ok": true,
		"summary": {
			"kind": "discarded_item",
			"id": normalized_key,
			"name": String(item.get("name", normalized_key)),
			"quantity": quantity,
			"remaining": remaining,
		},
	}


func give_item_to_pokemon(item_key: String, pcl_id: String) -> Dictionary:
	_last_error = ""
	var normalized_key := item_key.strip_edges()
	var item := ShopSystem.get_item_offer(normalized_key)
	if item.is_empty():
		return _failure("Unknown held item: %s" % normalized_key)
	var bag_quantity := get_item_count(normalized_key)
	if bag_quantity <= 0:
		return _failure("You do not have that item in the bag.")
	var pcl := CollectionSystem.get_pcl(pcl_id)
	if pcl.is_empty():
		return _failure(CollectionSystem.get_last_error())
	var previous_key := String(pcl.get("heldItem", ""))
	if previous_key == normalized_key:
		return _failure("That Pokemon is already holding this item.")
	if not previous_key.is_empty():
		if not ShopSystem.has_item(previous_key):
			return _failure("The Pokemon is holding an unknown item.")
		if get_item_count(previous_key) >= MAX_ITEM_QUANTITY:
			return _failure("There is no bag room for the Pokemon's current item.")
	if not CollectionSystem.set_held_item(pcl_id, normalized_key):
		return _failure(CollectionSystem.get_last_error())
	if bag_quantity == 1:
		_item_quantities.erase(normalized_key)
	else:
		_item_quantities[normalized_key] = bag_quantity - 1
	if not previous_key.is_empty():
		_item_quantities[previous_key] = get_item_count(previous_key) + 1
	_emit_change()
	return {
		"ok": true,
		"summary": {
			"kind": "held_item_equipped",
			"pcl_id": pcl_id,
			"item_key": normalized_key,
			"item_name": String(item.get("name", normalized_key)),
			"replaced_item_key": previous_key,
		},
	}


func take_held_item_from_pokemon(pcl_id: String) -> Dictionary:
	_last_error = ""
	var pcl := CollectionSystem.get_pcl(pcl_id)
	if pcl.is_empty():
		return _failure(CollectionSystem.get_last_error())
	var item_key := String(pcl.get("heldItem", ""))
	if item_key.is_empty():
		return _failure("That Pokemon is not holding an item.")
	var item := ShopSystem.get_item_offer(item_key)
	if item.is_empty():
		return _failure("The Pokemon is holding an unknown item.")
	if not can_add_item(item_key):
		return _failure("There is no room for that item in the bag.")
	if not CollectionSystem.set_held_item(pcl_id, ""):
		return _failure(CollectionSystem.get_last_error())
	_item_quantities[item_key] = get_item_count(item_key) + 1
	_emit_change()
	return {
		"ok": true,
		"summary": {
			"kind": "held_item_taken",
			"pcl_id": pcl_id,
			"item_key": item_key,
			"item_name": String(item.get("name", item_key)),
			"quantity": get_item_count(item_key),
		},
	}


func get_save_data() -> Dictionary:
	return {
		"item_quantities": _item_quantities.duplicate(true),
		"claimed_gifts": get_claimed_gift_ids(),
	}


func validate_save_data(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "Inventory progression is not an object."
	var data := value as Dictionary
	var quantities: Variant = data.get("item_quantities", {})
	if typeof(quantities) != TYPE_DICTIONARY:
		return "Inventory progression has invalid item quantities."
	for key: Variant in (quantities as Dictionary).keys():
		if typeof(key) != TYPE_STRING or not ShopSystem.has_item(String(key)):
			return "Inventory progression contains an unknown item."
		var quantity: Variant = (quantities as Dictionary)[key]
		if not _is_integer(quantity) or int(quantity) < 1 or int(quantity) > MAX_ITEM_QUANTITY:
			return "Inventory progression contains an invalid item quantity."
	var gifts: Variant = data.get("claimed_gifts", [])
	if typeof(gifts) != TYPE_ARRAY:
		return "Inventory progression has an invalid claimed-gift list."
	var seen_gifts: Dictionary = {}
	for gift_value: Variant in gifts as Array:
		if typeof(gift_value) != TYPE_STRING or not _is_progress_key(String(gift_value)):
			return "Inventory progression contains an invalid claimed gift."
		if seen_gifts.has(String(gift_value)):
			return "Inventory progression repeats a claimed gift."
		seen_gifts[String(gift_value)] = true
	return ""


func load_save_data(value: Variant) -> bool:
	_last_error = validate_save_data(value)
	if not _last_error.is_empty():
		return false
	var data := value as Dictionary
	_item_quantities = (
		data.get("item_quantities", {}) as Dictionary
	).duplicate(true)
	_claimed_gifts.clear()
	for gift_value: Variant in data.get("claimed_gifts", []) as Array:
		_claimed_gifts[String(gift_value)] = true
	_emit_change()
	return true


func reset_progress() -> void:
	_item_quantities.clear()
	_claimed_gifts.clear()
	_last_error = ""
	_emit_change()


func get_last_error() -> String:
	return _last_error


func _emit_change() -> void:
	inventory_changed.emit()
	progression_changed.emit()


func _failure(message: String) -> Dictionary:
	_last_error = message
	return {"ok": false, "error": message}


func _is_progress_key(value: String) -> bool:
	var normalized := value.strip_edges()
	if normalized.is_empty() or normalized.length() > 128 or normalized != value:
		return false
	for character_index in normalized.length():
		var codepoint := normalized.unicode_at(character_index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 65 and codepoint <= 90)
			or (codepoint >= 97 and codepoint <= 122)
			or codepoint in [45, 95]
		):
			return false
	return true


func _is_integer(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		or (
			typeof(value) == TYPE_FLOAT
			and is_finite(float(value))
			and floorf(float(value)) == float(value)
		)
	)
