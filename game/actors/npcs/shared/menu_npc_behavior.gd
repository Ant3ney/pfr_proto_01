class_name MenuNpcBehavior
extends NPCBehavior

## Reusable NPC behavior that opens one Inspector-assigned menu. It has no
## knowledge of the menu's gameplay domains.

@export_group("Menu")
@export var menu_scene: PackedScene
@export var interaction_prompt := "Talk"

var _open_menu: Node


func can_interact(
	_character: CharacterBody3D,
	_controller: NPCController,
	interactor: PlayerCharacter
) -> bool:
	return (
		interactor != null
		and menu_scene != null
		and not is_instance_valid(_open_menu)
		and GameInstance.is_player_movement_enabled()
		and not GameInstance.is_battle_start_in_progress()
		and not GameInstance.is_battle_return_in_progress()
		and not GameInstance.is_scene_transfer_in_progress()
	)


func interact(
	character: CharacterBody3D,
	controller: NPCController,
	interactor: PlayerCharacter
) -> bool:
	if not can_interact(character, controller, interactor):
		return false
	_face_interactor(character, interactor)
	GameInstance.set_player_movement_enabled(false)
	_open_menu = menu_scene.instantiate()
	if _open_menu == null:
		GameInstance.set_player_movement_enabled(true)
		return false
	if _open_menu.has_signal(&"closed"):
		_open_menu.connect(&"closed", _on_menu_closed, CONNECT_ONE_SHOT)
	_open_menu.tree_exited.connect(_on_menu_tree_exited, CONNECT_ONE_SHOT)
	UIManager.add_child(_open_menu)
	return true


func get_interaction_prompt(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> String:
	return interaction_prompt.strip_edges()


func _on_menu_closed() -> void:
	_open_menu = null
	GameInstance.set_player_movement_enabled(true)


func _on_menu_tree_exited() -> void:
	_open_menu = null
	GameInstance.set_player_movement_enabled(true)


func _face_interactor(character: CharacterBody3D, interactor: PlayerCharacter) -> void:
	var visual := character.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return
	var offset := interactor.global_position - character.global_position
	offset.y = 0.0
	if offset.is_zero_approx():
		return
	var local_direction := character.global_basis.orthonormalized().inverse() * offset.normalized()
	visual.rotation.y = atan2(-local_direction.x, -local_direction.z)
