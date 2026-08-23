extends Node

## Owns state and operations that apply across the entire game.

var _player_movement_enabled := true


func set_player_movement_enabled(is_enabled: bool) -> void:
	_player_movement_enabled = is_enabled


func is_player_movement_enabled() -> bool:
	return _player_movement_enabled
