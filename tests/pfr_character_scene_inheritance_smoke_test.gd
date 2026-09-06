extends Node

const BASE_CHARACTER_SCENE_PATH := "res://core/PFRCharacter.tscn"
const NAVIGATION_TEST_SCENE_PATH := "res://demo/navigation_test.tscn"
const CHARACTER_SCENES := [
	{
		"label": "Player",
		"path": "res://demo/player.tscn",
		"capsule_radius": 0.32,
		"player": true,
	},
	{
		"label": "Town NPC",
		"path": "res://overworld/town_npcs/town_npc.tscn",
		"capsule_radius": 0.28,
	},
	{
		"label": "Pokemon Center healer",
		"path": "res://overworld/pokemon_center/PokemonCenterHealer.tscn",
		"capsule_radius": 0.28,
	},
	{
		"label": "Stretchman",
		"path": "res://rnd/stretch/npc/stretchman.tscn",
		"capsule_radius": 0.3,
	},
	{
		"label": "Trainer Kyle",
		"path": "res://overworld/trainer_lake/TrainerKyle.tscn",
		"capsule_radius": 0.32,
	},
	{
		"label": "Delivery Worker",
		"path": "res://overworld/trainer_lake/TrainerDeliveryWorker.tscn",
		"capsule_radius": 0.32,
	},
	{
		"label": "Police Officer",
		"path": "res://overworld/trainer_lake/TrainerPoliceOfficer.tscn",
		"capsule_radius": 0.32,
	},
	{
		"label": "Businessman",
		"path": "res://overworld/trainer_lake/TrainerBusinessman.tscn",
		"capsule_radius": 0.32,
	},
	{
		"label": "Backpacker",
		"path": "res://overworld/trainer_lake/TrainerBackpacker.tscn",
		"capsule_radius": 0.32,
	},
	{
		"label": "Tourist",
		"path": "res://overworld/trainer_lake/TrainerTourist.tscn",
		"capsule_radius": 0.32,
	},
	{
		"label": "Jogger",
		"path": "res://overworld/trainer_lake/TrainerJogger.tscn",
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
	_check(
		inherited_scene != null
			and inherited_scene.resource_path == BASE_CHARACTER_SCENE_PATH,
		"%s should inherit directly from the shared PFRCharacter scene." % label
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
