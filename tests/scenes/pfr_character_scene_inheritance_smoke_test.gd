extends Node

const BASE_CHARACTER_SCENE_PATH := "res://game/actors/character/pfr_character.tscn"
const RESIDENT_BASE_SCENE_PATH := "res://game/actors/npcs/residents/resident_base.tscn"
const TRAINER_BASE_SCENE_PATH := "res://game/actors/npcs/trainers/trainer_base.tscn"
const NAVIGATION_TEST_SCENE_PATH := "res://tests/manual/navigation_test.tscn"
const CHARACTER_SCENES := [
	{
		"label": "Player",
		"path": "res://game/actors/player/player.tscn",
		"capsule_radius": 0.32,
		"player": true,
	},
	{
		"label": "Town NPC",
		"path": "res://game/actors/npcs/residents/resident_base.tscn",
		"capsule_radius": 0.28,
	},
	{
		"label": "Pokemon Center healer",
		"path": "res://game/actors/npcs/services/pokemon_center_healer/pokemon_center_healer.tscn",
		"capsule_radius": 0.28,
	},
	{
		"label": "Stretchman",
		"path": "res://game/actors/npcs/residents/stretchman/stretchman.tscn",
		"base_path": RESIDENT_BASE_SCENE_PATH,
		"capsule_radius": 0.28,
	},
	{
		"label": "Trainer base",
		"path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
	{
		"label": "Trainer Kyle",
		"path": "res://game/actors/npcs/trainers/presets/trainer_kyle.tscn",
		"base_path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
	{
		"label": "Delivery Worker",
		"path": "res://game/actors/npcs/trainers/presets/trainer_delivery_worker.tscn",
		"base_path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
	{
		"label": "Police Officer",
		"path": "res://game/actors/npcs/trainers/presets/trainer_police_officer.tscn",
		"base_path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
	{
		"label": "Businessman",
		"path": "res://game/actors/npcs/trainers/presets/trainer_businessman.tscn",
		"base_path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
	{
		"label": "Backpacker",
		"path": "res://game/actors/npcs/trainers/presets/trainer_backpacker.tscn",
		"base_path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
	{
		"label": "Tourist",
		"path": "res://game/actors/npcs/trainers/presets/trainer_tourist.tscn",
		"base_path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
	{
		"label": "Jogger",
		"path": "res://game/actors/npcs/trainers/presets/trainer_jogger.tscn",
		"base_path": TRAINER_BASE_SCENE_PATH,
		"capsule_radius": 0.32,
	},
]

var _failures: Array[String] = []


func _ready() -> void:
	var base_scene := load(BASE_CHARACTER_SCENE_PATH) as PackedScene
	_check(base_scene != null, "The shared PFRCharacter scene should load.")
	if base_scene != null:
		var base_character := base_scene.instantiate() as PFRCharacter
		_check(base_character != null, "The shared scene root should be a PFRCharacter.")
		if base_character != null:
			_check_common_structure(base_character, 0.32, "Shared PFRCharacter")
			base_character.free()

	for spec: Dictionary in CHARACTER_SCENES:
		_check_character_scene(spec)
	_check_navigation_fixture_uses_base_scene()

	if _failures.is_empty():
		print(
			"PFRCharacter scene inheritance smoke test passed: player, reusable NPCs, "
			+ "all trainer prefabs, and the navigation fixture share one scene foundation."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("PFRCharacter scene inheritance smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check_character_scene(spec: Dictionary) -> void:
	var label := String(spec.get("label", "Character"))
	var path := String(spec.get("path", ""))
	var packed := load(path) as PackedScene
	_check(packed != null, "%s scene should load from %s." % [label, path])
	if packed == null:
		return

	var inherited_scene := packed.get_state().get_node_instance(0)
	var expected_base_path := String(spec.get("base_path", BASE_CHARACTER_SCENE_PATH))
	_check(
		inherited_scene != null
			and inherited_scene.resource_path == expected_base_path,
		"%s should inherit directly from %s." % [label, expected_base_path]
	)

	var character := packed.instantiate() as PFRCharacter
	_check(character != null, "%s should instantiate as a PFRCharacter." % label)
	if character == null:
		return
	_check_common_structure(
		character,
		float(spec.get("capsule_radius", 0.32)),
		label
	)
	_check(
		character.get_node_or_null(^"Visual/CharacterArt") == null,
		"%s should select art through its asset pack instead of serializing a second model."
		% label
	)
	if bool(spec.get("player", false)):
		_check(character is PlayerCharacter, "The Player scene should retain PlayerCharacter behavior.")
		_check(
			character.controller is PlayerController,
			"The Player scene should retain its PlayerController input source."
		)
	else:
		_check(character.controller != null, "%s should retain its NPC controller." % label)
	character.free()


func _check_common_structure(
	character: PFRCharacter,
	expected_radius: float,
	label: String
) -> void:
	var collision := character.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var visual := character.get_node_or_null(^"Visual") as Node3D
	_check(collision != null, "%s should inherit the shared collision node." % label)
	_check(visual != null, "%s should inherit the shared Visual pivot." % label)
	_check(
		collision != null
			and collision.shape is CapsuleShape3D
			and is_equal_approx(
				(collision.shape as CapsuleShape3D).radius,
				expected_radius
			),
		"%s should preserve its %.2f m capsule radius." % [label, expected_radius]
	)


func _check_navigation_fixture_uses_base_scene() -> void:
	var packed := load(NAVIGATION_TEST_SCENE_PATH) as PackedScene
	_check(packed != null, "The navigation test scene should load.")
	if packed == null:
		return
	var fixture := packed.instantiate()
	var npc := fixture.get_node_or_null(^"NPC") as PFRCharacter
	_check(npc != null, "The navigation fixture NPC should remain a PFRCharacter.")
	if npc != null:
		_check(
			npc.scene_file_path == BASE_CHARACTER_SCENE_PATH,
			"The inline navigation fixture NPC should instance the shared PFRCharacter scene."
		)
	fixture.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
