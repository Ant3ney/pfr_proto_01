class_name EconomyService
extends Node

## Owns the player's money. Shops and battle rewards request transactions but
## do not store or directly mutate the balance.

signal progression_changed
signal balance_changed(balance: int)

const CURRENT_ECONOMY_VERSION := 2
const LEGACY_STARTING_BALANCE := 5_000_000
const STARTING_BALANCE := 50
const MAX_BALANCE := 9_000_000_000_000_000

var _balance := STARTING_BALANCE
var _last_battle_reward: Dictionary = {}
var _last_error := ""


func get_balance() -> int:
	return _balance


func can_afford(amount: int) -> bool:
	return amount > 0 and _balance >= amount


func spend_money(amount: int) -> bool:
	_last_error = ""
	if amount <= 0:
		_last_error = "Transaction amount must be positive."
		return false
	if not can_afford(amount):
		_last_error = "That purchase costs %s, but you only have %s." % [
			format_money(amount),
			format_money(_balance),
		]
		return false
	_balance -= amount
	_emit_change()
	return true


func grant_money(amount: int) -> int:
	_last_error = ""
	if amount <= 0:
		return 0
	var previous_balance := _balance
	_balance = mini(_balance + amount, MAX_BALANCE)
	var granted := _balance - previous_balance
	if granted > 0:
		_emit_change()
	return granted


func record_battle_reward(summary: Dictionary) -> void:
	_last_battle_reward = summary.duplicate(true)
	progression_changed.emit()


func get_last_battle_reward() -> Dictionary:
	return _last_battle_reward.duplicate(true)


func get_last_error() -> String:
	return _last_error


func format_money(amount: int) -> String:
	var digits := str(maxi(amount, 0))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return "$" + ",".join(groups)


func get_save_data() -> Dictionary:
	return {
		"version": CURRENT_ECONOMY_VERSION,
		"balance": _balance,
		"last_battle_reward": _last_battle_reward.duplicate(true),
	}


func validate_save_data(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "Economy progression is not an object."
	var data := value as Dictionary
	var version: Variant = data.get("version", CURRENT_ECONOMY_VERSION)
	if not _is_integer(version) or int(version) < 1 or int(version) > CURRENT_ECONOMY_VERSION:
		return "Economy progression has an invalid version."
	var balance: Variant = data.get("balance")
	if not _is_integer(balance) or int(balance) < 0 or int(balance) > MAX_BALANCE:
		return "Economy progression has an invalid balance."
	if typeof(data.get("last_battle_reward", {})) != TYPE_DICTIONARY:
		return "Economy progression has an invalid battle reward."
	return ""


func load_save_data(value: Variant) -> bool:
	_last_error = validate_save_data(value)
	if not _last_error.is_empty():
		return false
	var data := value as Dictionary
	_balance = int(data.get("balance", STARTING_BALANCE))
	_last_battle_reward = (
		data.get("last_battle_reward", {}) as Dictionary
	).duplicate(true)
	_emit_change()
	return true


func reset_progress() -> void:
	_balance = STARTING_BALANCE
	_last_battle_reward.clear()
	_last_error = ""
	_emit_change()


func _emit_change() -> void:
	balance_changed.emit(_balance)
	progression_changed.emit()


func _is_integer(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		or (
			typeof(value) == TYPE_FLOAT
			and is_finite(float(value))
			and floorf(float(value)) == float(value)
		)
	)
