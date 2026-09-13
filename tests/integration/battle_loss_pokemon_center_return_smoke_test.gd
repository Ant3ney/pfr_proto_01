extends Node

const POKEMON_CENTER_PATH := (
	"res://game/world/levels/new_bouffalant_city/interiors/"
	+ "pokemon_center/pokemon_center_interior.tscn"
)


class BattleLossReturnWatcher:
	extends Node

	var failures: Array[String] = []
	var collection_change_count := 0


	func run() -> void:
		var original_collection := CollectionSystem.get_save_data()
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
		_check(
			not bool(BattleSystem.call(
				"_is_non_forfeit_defeat",
				{"winner": "opponent", "reason": "forfeit"}
			)),
			"A forfeit should not qualify for automatic loss healing."
		)

		var party := CollectionSystem.get_party()
		_check(not party.is_empty(), "The loss fixture should begin with a party.")
		for member: Dictionary in party:
			_check(
				CollectionSystem.update_instance_stats(
					String(member.get("pclID", "")),
					{"health": 0.0}
				),
				"Every loss-fixture party member should be set to fainted."
			)
		var stored_bidoof := CollectionSystem.add_pokemon(399, 3, 0.25)
		_check(not stored_bidoof.is_empty(), "The loss fixture should add a stored Pokemon.")
		CollectionSystem.collection_changed.connect(_on_collection_changed)
		collection_change_count = 0

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
		for member: Dictionary in CollectionSystem.get_party():
			_check(
				is_equal_approx(float(member["instanceStats"]["health"]), 1.0),
				"A loss return should fully heal every party member."
			)
		if not stored_bidoof.is_empty():
			var stored_after_return := CollectionSystem.get_pcl(
				String(stored_bidoof.get("pclID", ""))
			)
			_check(
				is_equal_approx(
					float(stored_after_return.get("instanceStats", {}).get("health", -1.0)),
					0.25
				),
				"Automatic loss healing should leave stored Pokemon untouched."
			)
		_check(
			collection_change_count == 1,
			"Automatic loss healing should emit one atomic collection update."
		)
		CollectionSystem.collection_changed.disconnect(_on_collection_changed)
		_check(
			CollectionSystem.load_save_data(original_collection),
			"The loss fixture should restore the original collection."
		)

		if failures.is_empty():
			print(
				"Battle-loss return smoke test passed: non-forfeit defeats return to "
				+ "the staffed New Buffalant City Pokemon Center and heal the party."
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


	func _on_collection_changed() -> void:
		collection_change_count += 1


func _ready() -> void:
	if get_tree().root.has_node(^"BattleLossReturnWatcher"):
		return
	var watcher := BattleLossReturnWatcher.new()
	watcher.name = "BattleLossReturnWatcher"
	get_tree().root.add_child.call_deferred(watcher)
	watcher.run.call_deferred()
