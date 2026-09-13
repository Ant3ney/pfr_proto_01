extends Node

const POKEMON_CENTER_PATH := (
	"res://game/world/levels/new_bouffalant_city/interiors/"
	+ "pokemon_center/pokemon_center_interior.tscn"
)


class BattleLossReturnWatcher:
	extends Node

	var failures: Array[String] = []


	func run() -> void:
		_check(
			String(BattleSystem.call(
				"_return_scene_path_for_result",
				{"winner": "player", "reason": "all_pokemon_fainted"}
			)).is_empty(),
			"A win should retain the battle's ordinary return destination."
		)
		_check(
			String(BattleSystem.call(
				"_return_scene_path_for_result",
				{"winner": "tie", "reason": "turn_limit"}
			)).is_empty(),
			"A tie should retain the battle's ordinary return destination."
		)
		_check(
			String(BattleSystem.call(
				"_return_scene_path_for_result",
				{"winner": "opponent", "reason": "forfeit"}
			)).is_empty(),
			"Running from battle should retain the battle's ordinary return destination."
		)

		BattleSystem.reset_for_testing()
		BattleSystem.set("_encounter_id", "battle-loss-center-smoke")
		BattleSystem.set("_result", {
			"winner": "opponent",
			"reason": "all_pokemon_fainted",
		})
		BattleSystem.call("_set_state", BattleSystem.State.ENDED)
		_check(
			BattleSystem.continue_after_result(),
			"Continuing from an opponent victory should begin the return transition."
		)
		await _wait_for_return()

		var center := get_tree().current_scene
		_check(
			center != null and center.scene_file_path == POKEMON_CENTER_PATH,
			"A lost battle should return to the main New Buffalant City Pokemon Center."
		)
		if center != null and center.scene_file_path == POKEMON_CENTER_PATH:
			_check(
				center.find_child("Player", true, false) is PlayerCharacter,
				"The returned Pokemon Center should contain the player."
			)
			_check(
				center.find_child("PokemonCenterHealer", true, false) != null,
				"The loss destination should be the staffed main clinic."
			)
			_check(
				center.find_child("EntrySpawn", true, false) is Marker3D,
				"The loss destination should retain its safe entry marker."
			)
		_check(
			BattleSystem.get_state() == BattleSystem.State.IDLE,
			"BattleSystem should return to IDLE after the Pokemon Center reveals."
		)
		_check(
			GameInstance.is_player_movement_enabled(),
			"Player movement should resume after the Pokemon Center reveals."
		)

		if failures.is_empty():
			print(
				"Battle-loss return smoke test passed: non-forfeit defeats return to "
				+ "the staffed New Buffalant City Pokemon Center."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("Battle-loss return smoke test failed: %s" % failure)
		get_tree().quit(1)


	func _wait_for_return() -> void:
		for _frame in 600:
			var scene := get_tree().current_scene
			if (
				scene != null
				and scene.scene_file_path == POKEMON_CENTER_PATH
				and not GameInstance.is_battle_return_in_progress()
			):
				return
			await get_tree().process_frame


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


func _ready() -> void:
	if get_tree().root.has_node(^"BattleLossReturnWatcher"):
		return
	var watcher := BattleLossReturnWatcher.new()
	watcher.name = "BattleLossReturnWatcher"
	get_tree().root.add_child.call_deferred(watcher)
	watcher.run.call_deferred()
