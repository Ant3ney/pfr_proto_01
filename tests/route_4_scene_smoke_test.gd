extends Node

const ROUTE_SCENE := preload("res://overworld/route_0/route_0.tscn")
const WILD_BATTLE_SCENE_PATH := "res://battle/route_0_wild_battle_scene.tscn"
const WILD_ENCOUNTER_PATH := "res://battle/encounters/wild_fletchling_route_0_v1.tres"
const GATEHOUSE_PATH := (
	"res://art/environments/new_bouffalant_city/city_interiors/gatehouse_interior.tscn"
)
const TRAINER_SEQUENCE: Array[Dictionary] = [
	{
		"name": &"TrainerKyle",
		"encounter_id": "trainer-kyle-lake-v1",
		"level": 3,
	},
	{
		"name": &"DeliveryWorker",
		"encounter_id": "trainer-delivery-worker-city-v1",
		"level": 3,
	},
	{
		"name": &"PoliceOfficer",
		"encounter_id": "trainer-police-officer-city-v1",
		"level": 4,
	},
	{
		"name": &"Businessman",
		"encounter_id": "trainer-businessman-city-v1",
		"level": 4,
	},
	{
		"name": &"Backpacker",
		"encounter_id": "trainer-backpacker-city-v1",
		"level": 5,
	},
	{
		"name": &"Tourist",
		"encounter_id": "trainer-tourist-city-v1",
		"level": 5,
	},
	{
		"name": &"Jogger",
		"encounter_id": "trainer-jogger-city-v1",
		"level": 6,
	},
]

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var route := ROUTE_SCENE.instantiate() as Node3D
	_check(route != null, "Route 0 should instantiate as a 3D level.")
	if route == null:
		_finish()
		return
	var route_trainers := route.get_node_or_null(^"RouteTrainers") as Node3D
	if route_trainers != null:
		# This fixture validates static authoring. Keep the trainers from starting
		# a sight encounter while their placement and battle data are inspected.
		route_trainers.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(route)
	await get_tree().process_frame

	var start := route.get_node_or_null(^"Route0Start") as Marker3D
	var player := route.get_node_or_null(^"Player") as PlayerCharacter
	_check(start != null, "Route 0 should expose its named start marker.")
	_check(player != null, "Route 0 should contain the playable character.")
	if start != null and player != null:
		_check(
			player.global_position.is_equal_approx(start.global_position),
			"The authored player spawn should match Route0Start."
		)

	var camera := route.get_node_or_null(^"Camera3D") as Camera3D
	var sun := route.get_node_or_null(^"Sun") as DirectionalLight3D
	var environment := route.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	_check(camera != null and camera.current and camera.far >= 80.0, "The route should have a camera sized for its full depth.")
	_check(sun != null and sun.shadow_enabled, "The outdoor route should use one shadow-casting sun.")
	_check(environment != null and environment.environment != null, "The route should provide its bright outdoor environment.")

	var ground := route.get_node_or_null(^"GroundTiles") as Node3D
	_check(ground != null and ground.get_child_count() == 96, "Route 0 should use a complete 8 x 12 grid of 4 m ground modules.")
	var path_count := 0
	if ground != null:
		for tile: Node in ground.get_children():
			if String(tile.name).begins_with("Path_"):
				path_count += 1
			_check(tile is Node3D and (tile as Node3D).scale.is_equal_approx(Vector3.ONE), "Ground modules should remain at unit scale.")
		_check(path_count == 21, "The meadow should contain the authored 21-module winding dirt route.")

	var fields := route.get_node_or_null(^"TallGrassFields") as Node3D
	_check(fields != null and fields.get_child_count() == 5, "Route 0 should contain five readable tall-grass fields.")
	if fields != null:
		for field: Node in fields.get_children():
			_check(field is TallGrassEncounterZone, "Every tall-grass field should use the reusable rnd feature.")
			if field is TallGrassEncounterZone:
				var zone := field as TallGrassEncounterZone
				_check(zone.battle_scene_path == WILD_BATTLE_SCENE_PATH, "Every field should use the concrete Route 0 wild battle.")
				_check(zone.encounter_chance_per_check > 0.0, "Every field should have a non-zero encounter chance.")
				_check(zone.scale.is_equal_approx(Vector3.ONE), "Tall-grass patches should keep their art at unit scale.")

	var trees := route.get_node_or_null(^"Vegetation/Trees") as Node3D
	var bushes := route.get_node_or_null(^"Vegetation/Bushes") as Node3D
	var hedges := route.get_node_or_null(^"Vegetation/Hedges") as Node3D
	var plants := route.get_node_or_null(^"Vegetation/Plants") as Node3D
	_check(trees != null and trees.get_child_count() >= 20, "Route 0 should be framed by a substantial tree family.")
	_check(bushes != null and bushes.get_child_count() >= 16, "Route 0 should include varied bushes and shrubs.")
	_check(hedges != null and hedges.get_child_count() >= 5, "Route 0 should use hedges as readable vegetation borders.")
	_check(plants != null and plants.get_child_count() >= 20, "Route 0 should include sparse flower and plant clusters.")
	for family in [trees, bushes, hedges, plants]:
		if family == null:
			continue
		for decoration: Node in family.get_children():
			_check(
				decoration is Node3D and (decoration as Node3D).scale.is_equal_approx(Vector3.ONE),
				"Placed vegetation should retain the environment pack's calibrated unit scale."
			)

	var boundaries := route.get_node_or_null(^"TerrainBoundaries") as Node3D
	_check(boundaries != null and boundaries.get_child_count() == 4, "The playable meadow should have four unobtrusive edge colliders.")
	var navigation_region := route.get_node_or_null(^"NavigationRegion3D") as NavigationRegion3D
	_check(
		navigation_region != null and navigation_region.navigation_mesh != null,
		"Route 0 should provide navigation for standard trainer approaches."
	)
	_validate_trainer_sequence(route_trainers)
	var trainer_chokepoints := route.get_node_or_null(^"TrainerChokepoints") as Node3D
	_check(
		trainer_chokepoints != null
		and trainer_chokepoints.find_children(
			"TrainerGate*", "StaticBody3D", false, false
		).size() == TRAINER_SEQUENCE.size() * 2,
		"Route 0 should force the player through all seven trainer sight checkpoints."
	)
	var completion_gate := route.get_node_or_null(
		^"Route0CompletionGate"
	) as RNDRouteCompletionGate
	_check(
		completion_gate != null and completion_gate.route_index == 0,
		"Route 0 should have a physical far-end goal that unlocks Route 1."
	)
	if route_trainers != null and player != null:
		for trainer_value: Node in route_trainers.get_children():
			var trainer := trainer_value as PFRCharacter
			var behavior := (
				trainer.npc_behavior as TrainerBehavior
				if trainer != null
				else null
			)
			if trainer == null or behavior == null:
				continue
			var forward: Vector3 = behavior.call("_get_forward_direction", trainer)
			player.global_position = trainer.global_position + forward * 1.5
			for _physics_sync in 2:
				await get_tree().physics_frame
			var detected_player: PlayerCharacter = behavior.call(
				"_detect_player", trainer, forward
			)
			_check(
				detected_player == player,
				"%s's mandatory checkpoint should keep its sight ray unobstructed."
				% trainer.name
			)
		if start != null:
			player.global_transform = start.global_transform

	var return_gateway := route.get_node_or_null(^"Route0ReturnGateway") as Route4Gateway
	_check(return_gateway != null, "Route 0 should have an interactive red return object at its start.")
	_check(
		route.get_node_or_null(^"ExitToGatehouse") == null,
		"Route 0 should not use an oversensitive contact exit at its start."
	)
	if return_gateway != null:
		_check(return_gateway.destination_scene_path == GATEHOUSE_PATH, "The red return object should target the Gate Building interior.")
		_check(return_gateway.destination_spawn_marker == &"Route0ReturnSpawn", "The red return object should use the rear-room return marker.")
		_check(
			return_gateway.accent_color.r > return_gateway.accent_color.g
			and return_gateway.accent_color.r > return_gateway.accent_color.b,
			"The Route 0 return object should be authored red."
		)
		if start != null:
			_check(
				return_gateway.position.distance_to(start.position) <= 5.0,
				"The red return object should remain clearly available at the Route 0 start."
			)

	var encounter := load(WILD_ENCOUNTER_PATH) as Resource
	_check(encounter != null and encounter.has_method("validate"), "Route 0 should provide an authored battle encounter resource.")
	if encounter != null and encounter.has_method("validate"):
		_check(
			(encounter.call("validate") as PackedStringArray).is_empty(),
			"The Route 0 wild encounter should satisfy the battle data contract."
		)
	var battle_packed := load(WILD_BATTLE_SCENE_PATH) as PackedScene
	var battle_preview := battle_packed.instantiate() if battle_packed != null else null
	_check(battle_preview != null, "The concrete Route 0 wild battle scene should instantiate.")
	if battle_preview != null:
		var provider := battle_preview.get_node_or_null(^"EncounterProvider")
		var provided_encounter: Variant = provider.get("encounter") if provider != null else null
		_check(
			provided_encounter is Resource
			and String((provided_encounter as Resource).get("encounter_id"))
				== "wild-fletchling-route-0-v1",
			"The concrete battle provider should own the exact encounter requested by tall grass."
		)
		battle_preview.free()
	_finish()


func _validate_trainer_sequence(trainer_root: Node3D) -> void:
	_check(trainer_root != null, "Route 0 should own its ordered trainer group.")
	if trainer_root == null:
		return
	_check(
		trainer_root.get_child_count() == TRAINER_SEQUENCE.size(),
		"Route 0 should contain all seven prototype trainers."
	)
	var trainer_positions: Array[Vector3] = []
	var previous_level := 0
	for sequence_index in TRAINER_SEQUENCE.size():
		var expected := TRAINER_SEQUENCE[sequence_index]
		var trainer := trainer_root.get_child(sequence_index) as PFRCharacter
		_check(trainer != null, "Trainer position %d should contain a PFRCharacter." % (sequence_index + 1))
		if trainer == null:
			continue
		var expected_name := expected.name as StringName
		var expected_encounter_id := String(expected.encounter_id)
		var expected_level := int(expected.level)
		_check(trainer.name == expected_name, "Route trainer %d should be %s." % [sequence_index + 1, expected_name])
		_check(
			int(trainer.get_meta("route_order", -1)) == sequence_index + 1,
			"%s should retain route order %d." % [expected_name, sequence_index + 1]
		)
		_check(
			int(trainer.get_meta("difficulty_level", -1)) == expected_level,
			"%s should advertise its authored level %d." % [expected_name, expected_level]
		)
		_check(
			expected_level >= previous_level,
			"Route trainer difficulty should never decrease while moving deeper into Route 0."
		)
		previous_level = expected_level
		var behavior := trainer.npc_behavior as TrainerBehavior
		_check(
			behavior != null and behavior.encounter_id == expected_encounter_id,
			"%s should preserve stable encounter ID %s." % [expected_name, expected_encounter_id]
		)
		_check(
			behavior != null
			and behavior.automatic_sight_encounter
			and not behavior.is_highly_aggro(),
			"%s should use one-time standard sight aggression, not Stretchman Highly Aggro."
			% expected_name
		)
		_validate_trainer_battle_level(behavior, expected_name, expected_level)
		_check(trainer.scale.is_equal_approx(Vector3.ONE), "%s should remain at unit scale." % expected_name)
		_check(is_zero_approx(trainer.position.y), "%s should stand on the route surface." % expected_name)
		trainer_positions.append(trainer.position)

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for first_index in trainer_positions.size():
		var position := trainer_positions[first_index]
		min_x = minf(min_x, position.x)
		max_x = maxf(max_x, position.x)
		min_z = minf(min_z, position.z)
		max_z = maxf(max_z, position.z)
		for second_index in range(first_index + 1, trainer_positions.size()):
			_check(
				position.distance_to(trainer_positions[second_index]) >= 4.0,
				"Route trainers should be scattered rather than overlapping."
			)
	_check(max_x - min_x >= 10.0, "Route trainers should be scattered across the route's width.")
	_check(max_z - min_z >= 30.0, "Route trainers should span the route from entrance to far end.")


func _validate_trainer_battle_level(
	behavior: TrainerBehavior,
	trainer_name: StringName,
	expected_level: int
) -> void:
	if behavior == null:
		return
	var battle_packed := load(behavior.battle_scene_path) as PackedScene
	var battle_preview := battle_packed.instantiate() if battle_packed != null else null
	_check(battle_preview != null, "%s should have an importable battle scene." % trainer_name)
	if battle_preview == null:
		return
	var provider := battle_preview.get_node_or_null(^"EncounterProvider")
	var encounter := (
		provider.get("encounter") as BattleEncounterDefinition
		if provider != null
		else null
	)
	_check(encounter != null, "%s's battle scene should provide encounter data." % trainer_name)
	if encounter != null:
		_check(not encounter.members.is_empty(), "%s should have at least one opponent." % trainer_name)
		for member in encounter.members:
			_check(
				member != null and member.level == expected_level,
				"%s's party should match authored difficulty level %d."
				% [trainer_name, expected_level]
			)
	battle_preview.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print(
			"Route 0 scene smoke test passed: modular terrain, winding path, navigation, seven "
			+ "mandatory standard trainer checkpoints in Lv. 3-6 order, a far-end unlock goal, "
			+ "red Gate Building return, vegetation, and five encounter fields verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Route 0 scene smoke test failed: %s" % failure)
	get_tree().quit(1)
