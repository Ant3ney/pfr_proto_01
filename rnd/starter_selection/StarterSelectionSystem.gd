extends Node

## Owns the mandatory first-profile starter choice. CollectionSystem remains
## the PCL owner; ProgressionAutosave decides when a profile is fresh or reset.

signal starter_selected(pokemon_id: int, pcl: Dictionary)

const STARTER_LEVEL := 5
const STARTER_POKEMON_IDS: Array[int] = [4, 656, 252]
const UI_SCENE: PackedScene = preload(
	"res://rnd/starter_selection/starter_selection_ui.tscn"
)
const STARTER_CHOICES: Array[Dictionary] = [
	{
		"pokemonId": 4,
		"name": "Charmander",
		"type": "Fire",
		"generation": "Generation I",
		"region": "Kanto",
		"spriteId": "charmander",
		"color": "e66b3c",
		"level": STARTER_LEVEL,
	},
	{
		"pokemonId": 656,
		"name": "Froakie",
		"type": "Water",
		"generation": "Generation VI",
		"region": "Kalos",
		"spriteId": "froakie",
		"color": "4f9ee8",
		"level": STARTER_LEVEL,
	},
	{
		"pokemonId": 252,
		"name": "Treecko",
		"type": "Grass",
		"generation": "Generation III",
		"region": "Hoenn",
		"spriteId": "treecko",
		"color": "55b96c",
		"level": STARTER_LEVEL,
	},
]

var _selection_required := false
var _selected_starter_id := 0
var _active_ui: RNDStarterSelectionUI
var _owns_movement_lock := false


func prepare_new_profile() -> void:
	_close_ui()
	_selected_starter_id = 0
	_selection_required = true


func show_selection() -> bool:
	if not _selection_required:
		return false
	_active_ui = _ensure_ui()
	if not is_instance_valid(_active_ui):
		push_error("The starter-selection UI could not be created.")
		return false
	_acquire_movement_lock()
	_active_ui.show_choices(get_starter_choices())
	return true


func choose_starter(pokemon_id: int) -> bool:
	if not _selection_required or pokemon_id not in STARTER_POKEMON_IDS:
		return false
	if not CollectionSystem.get_collection().is_empty():
		_show_error("A starter cannot be added because this profile is not empty.")
		return false
	var pcl := CollectionSystem.add_pokemon(
		pokemon_id,
		STARTER_LEVEL,
		1.0,
		-1,
		1
	)
	if pcl.is_empty():
		_show_error(
			"Your starter could not be created: %s" % CollectionSystem.get_last_error()
		)
		return false
	_selected_starter_id = pokemon_id
	_selection_required = false
	starter_selected.emit(pokemon_id, pcl.duplicate(true))
	_close_ui()
	return true


func mark_profile_loaded(starter_pokemon_id: int) -> void:
	_selection_required = false
	_selected_starter_id = starter_pokemon_id
	_close_ui()


func is_selection_required() -> bool:
	return _selection_required


func get_selected_starter_id() -> int:
	return _selected_starter_id


func get_starter_choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for choice in STARTER_CHOICES:
		result.append(choice.duplicate(true))
	return result


func get_active_ui() -> RNDStarterSelectionUI:
	return _active_ui if is_instance_valid(_active_ui) else null


func reset_for_testing() -> void:
	_selection_required = false
	_selected_starter_id = 0
	_close_ui()


func _ensure_ui() -> RNDStarterSelectionUI:
	if is_instance_valid(_active_ui):
		return _active_ui
	_active_ui = UI_SCENE.instantiate() as RNDStarterSelectionUI
	if _active_ui == null:
		return null
	_active_ui.starter_chosen.connect(_on_starter_chosen)
	add_child(_active_ui)
	return _active_ui


func _on_starter_chosen(pokemon_id: int) -> void:
	choose_starter(pokemon_id)


func _show_error(message: String) -> void:
	if is_instance_valid(_active_ui):
		_active_ui.show_error(message)
	else:
		push_error(message)


func _acquire_movement_lock() -> void:
	_owns_movement_lock = GameInstance.is_player_movement_enabled()
	if _owns_movement_lock:
		GameInstance.set_player_movement_enabled(false)
		PlayerController.set_floating_joystick_input(Vector2.ZERO)


func _close_ui() -> void:
	if is_instance_valid(_active_ui):
		_active_ui.hide_ui()
		_active_ui.queue_free()
	_active_ui = null
	if _owns_movement_lock:
		GameInstance.set_player_movement_enabled(true)
	_owns_movement_lock = false
