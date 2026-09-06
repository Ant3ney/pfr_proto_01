@tool
extends SceneTree

const CITY_SCENE_PATH := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(Engine.is_editor_hint(), "The preview check must run in editor mode.")
	var editor_filesystem := EditorInterface.get_resource_filesystem()
	while editor_filesystem != null and editor_filesystem.is_scanning():
		await process_frame
	var packed := load(CITY_SCENE_PATH) as PackedScene
	_check(packed != null, "The New Bouffalant City wrapper should load.")
	if packed == null:
		_finish()
		return

	var city := packed.instantiate()
	root.add_child(city)
	await process_frame
	await process_frame

	var residents := city.get_node_or_null(^"TownResidents")
	_check(residents != null, "The city should retain its TownResidents group.")
	if residents != null:
		_check(residents.get_child_count() == 7, "All seven residents should load in the editor.")
		for child: Node in residents.get_children():
			var resident_script := child.get_script() as Script
			_check(
				resident_script != null
					and resident_script.resource_path == "res://game/actors/character/pfr_character.gd",
				"%s should remain a PFRCharacter." % child.name
			)
			var art_pack := child.get("character_art_asset_pack") as Resource
			var desired_scene := (
				art_pack.get("character_scene") as PackedScene
				if art_pack != null
				else null
			)
			var preview := child.get_node_or_null(^"Visual/CharacterArt") as Node3D
			_check(preview != null, "%s should have editor-visible character art." % child.name)
			_check(
				preview != null and preview.owner == null,
				"%s's editor preview should remain non-persistent." % child.name
			)
			_check(
				preview != null
					and desired_scene != null
					and preview.scene_file_path == desired_scene.resource_path,
				"%s's preview should match its assigned character art pack." % child.name
			)
			_check(
				not child.is_in_group(&"pfr_characters")
					and not child.is_physics_processing(),
				"%s should not run gameplay processing in the editor." % child.name
			)

	root.remove_child(city)
	city.free()
	for _frame in 3:
		await process_frame
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print(
			"PFRCharacter editor preview smoke test passed: all seven level-configured "
			+ "town residents display their assigned art without running gameplay."
		)
		quit(0)
		return
	for failure in _failures:
		push_error("PFRCharacter editor preview smoke test failed: %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
