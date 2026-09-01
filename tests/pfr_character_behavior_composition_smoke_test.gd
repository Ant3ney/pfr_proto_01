extends Node

const DefaultArtPack: PFRCharacterArtAssetPack = preload(
	"res://art/characters/za_city_adult_a_01/za_city_adult_a_01.tres"
)


class CountingBehavior:
	extends NPCBehavior

	var process_count := 0


	func process_behavior(
		_character: CharacterBody3D,
		_controller: NPCController
	) -> void:
		process_count += 1


	func get_interaction_prompt(
		_character: CharacterBody3D,
		_controller: NPCController,
		_interactor: PlayerCharacter
	) -> String:
		return "Direct behavior"


var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var character := PFRCharacter.new()
	character.name = "DirectlyComposedCharacter"
	character.character_art_asset_pack = DefaultArtPack
	var direct_behavior := CountingBehavior.new()
	character.npc_behavior = direct_behavior
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.6
	collision.position = Vector3(0.0, 0.8, 0.0)
	collision.shape = capsule
	character.add_child(collision)
	add_child(character)
	await get_tree().process_frame

	_check(
		character.controller != null,
		"A newly added PFRCharacter should create its movement controller."
	)
	_check(
		character.npc_behavior == direct_behavior,
		"PFRCharacter should expose the directly assigned NPC behavior."
	)
	_check(
		character.controller.npc_behavior == direct_behavior,
		"The legacy controller mirror should follow the direct behavior."
	)
	_check(
		character.get_interaction_prompt(null) == "Direct behavior",
		"Interaction dispatch should call the direct behavior."
	)
	var process_count_before := direct_behavior.process_count
	character._physics_process(0.0)
	_check(
		direct_behavior.process_count == process_count_before + 1,
		"One character physics update should process the direct behavior once."
	)

	var direct_usage := _property_usage(character, &"npc_behavior")
	var legacy_usage := _property_usage(character.controller, &"npc_behavior")
	_check(
		bool(direct_usage & PROPERTY_USAGE_EDITOR)
		and bool(direct_usage & PROPERTY_USAGE_STORAGE),
		"PFRCharacter.npc_behavior should be editable and serialized."
	)
	_check(
		bool(legacy_usage & PROPERTY_USAGE_STORAGE)
		and not bool(legacy_usage & PROPERTY_USAGE_EDITOR),
		"NPCController.npc_behavior should remain serialized but hidden from new authoring."
	)

	var legacy_character := PFRCharacter.new()
	var legacy_controller := NPCController.new()
	var legacy_behavior := TownNpcBehavior.new()
	legacy_controller.npc_behavior = legacy_behavior
	legacy_character.controller = legacy_controller
	_check(
		legacy_character.npc_behavior == legacy_behavior,
		"Assigning a legacy controller should migrate its nested behavior."
	)

	character.queue_free()
	legacy_character.free()
	await get_tree().process_frame
	if _failures.is_empty():
		print(
			"PFRCharacter behavior composition smoke test passed: direct Inspector "
			+ "authoring, one-update dispatch, and legacy migration verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("PFRCharacter behavior composition smoke test failed: %s" % failure)
	get_tree().quit(1)


func _property_usage(object: Object, property_name: StringName) -> int:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return int(property.get("usage", 0))
	return 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
