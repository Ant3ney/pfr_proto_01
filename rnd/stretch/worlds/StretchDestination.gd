class_name RNDStretchDestination
extends Node3D

## Builds gyms, the Champion corridor, and Routes 1–39 from Stretchman's
## active destination. Generated routes use a deterministic winding centerline,
## continuous biome walls, real tall-grass encounter fields, and trainer gates
## perpendicular to the local path. The authored Route 0 is a separate scene.

const Content := preload("res://rnd/stretch/StretchContent.gd")
const PlayerScene := preload("res://demo/player.tscn")
const GameUIScene := preload("res://demo/game_ui.tscn")
const PlayerCameraScript := preload("res://core/PlayerCamera.gd")
const TallGrassScene := preload("res://rnd/tall_grass_encounter_zone.tscn")
const CompletionGateScene := preload(
	"res://rnd/stretch/worlds/route_completion_gate.tscn"
)
const TRAINER_SCENES: Array[PackedScene] = [
	preload("res://overworld/trainer_lake/TrainerBackpacker.tscn"),
	preload("res://overworld/trainer_lake/TrainerBusinessman.tscn"),
	preload("res://overworld/trainer_lake/TrainerDeliveryWorker.tscn"),
	preload("res://overworld/trainer_lake/TrainerJogger.tscn"),
	preload("res://overworld/trainer_lake/TrainerPoliceOfficer.tscn"),
	preload("res://overworld/trainer_lake/TrainerTourist.tscn"),
]
const STRETCHMAN_HUB_SCENE_PATH := (
	"res://art/environments/new_bouffalant_city/city_interiors/"
	+ "miare_station_concourse.tscn"
)
const ROUTE_PATH_WIDTH := 9.2
const ROUTE_WALL_HEIGHT := 2.1
const ROUTE_WALL_THICKNESS := 0.6
const TRAINER_GATE_GAP := 0.9

var _destination: Dictionary = {}
var _world_kind := "route"
var _world_length := 70.0
var _world_width := 14.0
var _start_position := Vector3.ZERO
var _route_index := -1
var _route_layout: Dictionary = {}
var _route_points: Array[Vector3] = []
var _route_trainer_positions: Array[Vector3] = []
var _route_trainer_directions: Array[Vector3] = []
var _title_label: Label
var _progress_label: Label
var _balance_label: Label


func _ready() -> void:
	_destination = StretchGoalSystem.get_active_destination()
	if _destination.is_empty():
		# Direct editor runs get a representative generated route without
		# mutating unlock progression.
		_destination = Content.get_destination("route", 1)
		_destination["kind"] = "route"
	_world_kind = String(_destination.get("kind", "route"))
	if _world_kind not in ["gym", "route", "champion"]:
		_world_kind = "route"
	if _world_kind == "route":
		_prepare_generated_route()
	else:
		_world_length = 36.0 if _world_kind == "gym" else 82.0
		_world_width = 14.0
		_start_position = Vector3(0.0, 0.0, _world_length * 0.5 - 5.0)

	_build_environment()
	_build_level_geometry()
	_build_player_and_camera()
	_build_hud()
	_spawn_trainers()
	_update_progress_text()
	StretchGoalSystem.balance_changed.connect(_on_balance_changed)


func _prepare_generated_route() -> void:
	_route_index = int(_destination.get("index", 1))
	_route_layout = Content.get_route_layout(_route_index)
	_world_length = float(_destination.get("world_length", 76))
	_world_width = float(_destination.get("world_width", 18))
	_build_route_centerline()
	_start_position = _route_points[0] if not _route_points.is_empty() else Vector3.ZERO
	_build_route_trainer_samples()
	set_meta("route_index", _route_index)
	set_meta("route_biome", String(_destination.get("biome", "route")))
	set_meta("route_world_length", _world_length)
	set_meta("route_world_width", _world_width)
	set_meta("route_path_width", ROUTE_PATH_WIDTH)
	set_meta("route_path_points", _route_points.duplicate())
	set_meta("mandatory_trainer_count", _route_trainer_positions.size())


func _build_route_centerline() -> void:
	_route_points.clear()
	var point_count := maxi(roundi(_world_length / 11.0) + 1, 8)
	var half_length := _world_length * 0.5
	var maximum_amplitude := maxf(
		_world_width * 0.5 - ROUTE_PATH_WIDTH * 0.5 - ROUTE_WALL_THICKNESS - 0.8,
		2.2
	)
	var primary_turns := 1.75 + float(_route_index % 4) * 0.45
	var secondary_turns := 4.0 + float(_route_index % 5) * 0.35
	var phase := float(_route_index) * 0.731
	for point_index in point_count:
		var progress := float(point_index) / float(maxi(point_count - 1, 1))
		var edge_fade := sin(progress * PI)
		var primary := sin(progress * TAU * primary_turns + phase) * 0.72
		var secondary := sin(progress * TAU * secondary_turns - phase * 0.43) * 0.28
		var x_position := (primary + secondary) * maximum_amplitude * edge_fade
		var z_position := lerpf(half_length - 5.0, -half_length + 5.0, progress)
		_route_points.append(Vector3(x_position, 0.0, z_position))


func _build_route_trainer_samples() -> void:
	_route_trainer_positions.clear()
	_route_trainer_directions.clear()
	var trainer_count := int(_destination.get("trainer_count", 4))
	for trainer_index in trainer_count:
		var progress := float(trainer_index + 1) / float(trainer_count + 1)
		_route_trainer_positions.append(_sample_route(progress))
		_route_trainer_directions.append(_sample_route_direction(progress))


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	match _world_kind:
		"gym":
			environment.background_color = Color(0.07, 0.10, 0.16)
			environment.ambient_light_color = Color(0.45, 0.58, 0.82)
		"champion":
			environment.background_color = Color(0.035, 0.025, 0.07)
			environment.ambient_light_color = Color(0.56, 0.42, 0.72)
		_:
			environment.background_color = _route_color("sky", Color(0.34, 0.66, 0.92))
			environment.ambient_light_color = _route_color("ambient", Color(0.78, 0.88, 1.0))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -28.0 + float(_route_index % 5) * 7.0, 0.0)
	sun.light_color = (
		_route_color("accent", Color(1.0, 0.93, 0.80)).lightened(0.48)
		if _world_kind == "route"
		else Color(1.0, 0.93, 0.80)
	)
	sun.light_energy = 1.05 if _world_kind == "route" else 0.85
	sun.shadow_enabled = true
	add_child(sun)


func _build_level_geometry() -> void:
	if _world_kind == "route":
		_build_route_dungeon()
	else:
		_build_linear_challenge_geometry()

	var entry_marker := Marker3D.new()
	entry_marker.name = "EntrySpawn"
	entry_marker.position = _start_position
	if _world_kind == "route" and not _route_points.is_empty():
		entry_marker.rotation.y = _yaw_for_direction(_sample_route_direction(0.0))
	add_child(entry_marker)


func _build_route_dungeon() -> void:
	var ground_color := _route_color("ground", Color(0.22, 0.54, 0.24))
	var path_color := _route_color("path", Color(0.53, 0.36, 0.20))
	var wall_color := _route_color("wall", Color(0.13, 0.38, 0.16))
	_add_box(
		"Floor",
		Vector3(0.0, -0.1, 0.0),
		Vector3(_world_width, 0.2, _world_length),
		ground_color,
		true
	)
	_build_navigation_region(_world_width * 0.5 - 0.35)
	_build_outer_boundaries(wall_color)

	var path_root := Node3D.new()
	path_root.name = "DirtPath"
	add_child(path_root)
	var wall_root := Node3D.new()
	wall_root.name = "RouteWalls"
	add_child(wall_root)
	for segment_index in range(_route_points.size() - 1):
		var start := _route_points[segment_index]
		var end := _route_points[segment_index + 1]
		var direction := (end - start).normalized()
		var normal := Vector3(direction.z, 0.0, -direction.x)
		var midpoint := (start + end) * 0.5
		var segment_length := start.distance_to(end)
		var yaw := _yaw_for_direction(direction)
		_add_box(
			"PathSegment%02d" % (segment_index + 1),
			midpoint + Vector3.UP * 0.012,
			Vector3(ROUTE_PATH_WIDTH, 0.026, segment_length + 1.0),
			path_color,
			false,
			yaw,
			path_root
		)
		for side_value in [-1.0, 1.0]:
			var side := float(side_value)
			_add_box(
				"RouteWall%02d%s" % [segment_index + 1, "L" if side < 0.0 else "R"],
				midpoint + normal * side * (
					ROUTE_PATH_WIDTH * 0.5 + ROUTE_WALL_THICKNESS * 0.5
				) + Vector3.UP * (ROUTE_WALL_HEIGHT * 0.5),
				Vector3(ROUTE_WALL_THICKNESS, ROUTE_WALL_HEIGHT, segment_length + 2.2),
				wall_color,
				true,
				yaw,
				wall_root
			)

	_build_route_decorations()
	_build_route_grass_fields()
	_build_trainer_chokepoints()
	_build_route_completion_gate()


func _build_linear_challenge_geometry() -> void:
	var floor_color := (
		Color(0.09, 0.075, 0.15)
		if _world_kind == "champion"
		else Color(0.16, 0.21, 0.30)
	)
	_add_box(
		"Floor",
		Vector3(0.0, -0.1, 0.0),
		Vector3(_world_width, 0.2, _world_length),
		floor_color,
		true
	)
	_build_navigation_region(6.7)
	var wall_color := (
		Color(0.12, 0.075, 0.19)
		if _world_kind == "champion"
		else Color(0.12, 0.16, 0.22)
	)
	_build_outer_boundaries(wall_color)
	if _world_kind == "champion":
		_build_champion_gates()
	else:
		_build_gym_markings()
	_build_trainer_chokepoints()


func _build_outer_boundaries(color: Color) -> void:
	var half_width := _world_width * 0.5
	_add_box(
		"WestBoundary",
		Vector3(-half_width - 0.15, 1.2, 0.0),
		Vector3(0.3, 2.4, _world_length),
		color,
		true
	)
	_add_box(
		"EastBoundary",
		Vector3(half_width + 0.15, 1.2, 0.0),
		Vector3(0.3, 2.4, _world_length),
		color,
		true
	)
	_add_box(
		"NorthBoundary",
		Vector3(0.0, 1.2, -_world_length * 0.5 - 0.15),
		Vector3(_world_width, 2.4, 0.3),
		color,
		true
	)
	_add_box(
		"SouthBoundary",
		Vector3(0.0, 1.2, _world_length * 0.5 + 0.15),
		Vector3(_world_width, 2.4, 0.3),
		color,
		true
	)


func _build_route_decorations() -> void:
	var decorations := Node3D.new()
	decorations.name = "BiomeDecorations"
	add_child(decorations)
	var decor_style := String(_route_layout.get("decor", "trees"))
	var foliage := _route_color("foliage", Color(0.10, 0.45, 0.16))
	var accent := _route_color("accent", Color(0.75, 0.9, 0.45))
	for point_index in range(1, _route_points.size() - 1):
		var point := _route_points[point_index]
		var direction := (
			_route_points[point_index + 1] - _route_points[point_index - 1]
		).normalized()
		var normal := Vector3(direction.z, 0.0, -direction.x)
		for side_value in [-1.0, 1.0]:
			var side := float(side_value)
			var position := point + normal * side * (ROUTE_PATH_WIDTH * 0.5 + 1.15)
			var suffix := "%02d%s" % [point_index, "L" if side < 0.0 else "R"]
			match decor_style:
				"rocks":
					_add_sphere("Rock%s" % suffix, position + Vector3.UP * 0.65, 0.75, accent.darkened(0.35), decorations)
				"reeds":
					_add_cylinder("Reed%s" % suffix, position + Vector3.UP * 0.85, 0.11, 1.7, foliage, decorations)
				"vents":
					_add_cylinder("Vent%s" % suffix, position + Vector3.UP * 0.6, 0.42, 1.2, accent.darkened(0.32), decorations)
					_add_sphere("Glow%s" % suffix, position + Vector3.UP * 1.35, 0.28, accent, decorations)
				"pillars":
					_add_box("Pillar%s" % suffix, position + Vector3.UP * 1.25, Vector3(0.55, 2.5, 0.55), accent.darkened(0.4), false, 0.0, decorations)
				"mushrooms":
					_add_cylinder("Stem%s" % suffix, position + Vector3.UP * 0.45, 0.12, 0.9, Color(0.78, 0.72, 0.64), decorations)
					_add_sphere("Cap%s" % suffix, position + Vector3.UP * 0.95, 0.42, accent, decorations)
				"bamboo":
					_add_cylinder("Bamboo%s" % suffix, position + Vector3.UP * 1.55, 0.16, 3.1, foliage, decorations)
				"crystals":
					_add_box("Crystal%s" % suffix, position + Vector3.UP * 0.9, Vector3(0.5, 1.8, 0.5), accent, false, 0.45, decorations)
				"flowers":
					_add_cylinder("FlowerStem%s" % suffix, position + Vector3.UP * 0.42, 0.07, 0.84, foliage, decorations)
					_add_sphere("Flower%s" % suffix, position + Vector3.UP * 0.88, 0.28, accent, decorations)
				"pines":
					_add_cylinder("PineTrunk%s" % suffix, position + Vector3.UP * 0.8, 0.2, 1.6, Color(0.25, 0.16, 0.10), decorations)
					_add_sphere("PineCrown%s" % suffix, position + Vector3.UP * 2.0, 0.9, foliage, decorations)
				_:
					_add_cylinder("TreeTrunk%s" % suffix, position + Vector3.UP * 0.78, 0.2, 1.55, Color(0.30, 0.18, 0.08), decorations)
					_add_sphere("TreeCrown%s" % suffix, position + Vector3.UP * 1.95, 0.86, foliage, decorations)


func _build_route_grass_fields() -> void:
	var fields := Node3D.new()
	fields.name = "TallGrassFields"
	add_child(fields)
	var field_count := int(_destination.get("grass_fields", 4))
	var wild_encounter := Content.get_route_wild_encounter(_route_index)
	for field_index in field_count:
		var progress := float(field_index + 1) / float(field_count + 1)
		# Offset grass away from the exact trainer checkpoints while preserving
		# a complete path-crossing patch like Route 0.
		progress = clampf(progress + (0.035 if field_index % 2 == 0 else -0.035), 0.08, 0.92)
		var field := TallGrassScene.instantiate() as TallGrassEncounterZone
		if field == null:
			continue
		field.name = "Route%dGrass%02d" % [_route_index, field_index + 1]
		field.position = _sample_route(progress)
		field.rotation.y = _yaw_for_direction(_sample_route_direction(progress))
		field.battle_scene_path = Content.BATTLE_SCENE_PATH
		field.encounter_id = String(wild_encounter.get("encounter_id", ""))
		field.encounter_name = String(wild_encounter.get("display_name", "Wild Pokemon"))
		field.random_seed = _route_index * 100 + field_index + 1
		fields.add_child(field)


func _build_champion_gates() -> void:
	for gate_index in 5:
		var z_position := 20.0 - gate_index * 13.0
		for side_value in [-1.0, 1.0]:
			var side := float(side_value)
			_add_box(
				"GatePillar%d%s" % [gate_index, "L" if side < 0.0 else "R"],
				Vector3(side * 4.7, 1.6, z_position),
				Vector3(0.65, 3.2, 0.65),
				Color(0.62, 0.43, 0.10),
				false
			)
		_add_box(
			"GateLintel%d" % gate_index,
			Vector3(0.0, 3.0, z_position),
			Vector3(9.8, 0.35, 0.65),
			Color(0.72, 0.52, 0.14),
			false
		)


func _build_gym_markings() -> void:
	_add_cylinder("ArenaRing", Vector3(0.0, 0.015, -5.0), 5.2, 0.03, Color(0.65, 0.19, 0.18))
	_add_cylinder("ArenaCenter", Vector3(0.0, 0.035, -5.0), 3.9, 0.04, Color(0.18, 0.23, 0.34))


func _build_trainer_chokepoints() -> void:
	# Two collision segments leave only a 0.9 m opening across the local path.
	# The player capsule is forced through the trainer's exact forward ray; the
	# winding corridor walls prevent going around either end.
	var half_gap := TRAINER_GATE_GAP * 0.5
	var gate_color := (
		_route_color("wall", Color(0.13, 0.31, 0.12)).lightened(0.08)
		if _world_kind == "route"
		else (Color(0.22, 0.11, 0.31) if _world_kind == "champion" else Color(0.20, 0.25, 0.34))
	)
	var encounters := StretchGoalSystem.get_active_encounters()
	for encounter_index in encounters.size():
		var trainer_position := _trainer_position(encounter_index)
		var direction := _trainer_direction(encounter_index)
		var normal := Vector3(direction.z, 0.0, -direction.x)
		var corridor_half_width := ROUTE_PATH_WIDTH * 0.5 if _world_kind == "route" else 6.85
		var segment_width := corridor_half_width - half_gap
		var segment_center := half_gap + segment_width * 0.5
		var gate_center := trainer_position - direction * 0.65
		var yaw := _yaw_for_direction(direction)
		for side_value in [-1.0, 1.0]:
			var side := float(side_value)
			_add_box(
				"TrainerGate%d%s" % [encounter_index + 1, "L" if side < 0.0 else "R"],
				gate_center + normal * side * segment_center + Vector3.UP * 0.7,
				Vector3(segment_width, 1.4, 0.38),
				gate_color,
				true,
				yaw
			)


func _build_route_completion_gate() -> void:
	if _route_points.is_empty():
		return
	var gate := CompletionGateScene.instantiate() as RNDRouteCompletionGate
	if gate == null:
		return
	gate.name = "RouteCompletionGate"
	gate.position = _route_points.back()
	gate.rotation.y = _yaw_for_direction(_sample_route_direction(1.0))
	gate.configure(_route_index)
	gate.completion_attempted.connect(_on_route_completion_attempted)
	add_child(gate)


func _build_navigation_region(half_width: float) -> void:
	var half_length := _world_length * 0.5 - 0.35
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.set_vertices(PackedVector3Array([
		Vector3(-half_width, 0.0, -half_length),
		Vector3(-half_width, 0.0, half_length),
		Vector3(half_width, 0.0, half_length),
		Vector3(half_width, 0.0, -half_length),
	]))
	navigation_mesh.add_polygon(PackedInt32Array([3, 2, 0]))
	navigation_mesh.add_polygon(PackedInt32Array([0, 2, 1]))
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.navigation_mesh = navigation_mesh
	add_child(region)


func _build_player_and_camera() -> void:
	var player := PlayerScene.instantiate() as PlayerCharacter
	player.name = "Player"
	player.position = _start_position
	add_child(player)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.set_script(PlayerCameraScript)
	camera.position = _start_position + Vector3(0.0, 8.0, 7.0)
	camera.current = true
	camera.near = 0.15
	camera.far = maxf(120.0, _world_length + 24.0)
	camera.set("target_path", NodePath("../Player"))
	camera.set("offset", Vector3(0.0, 9.0, 7.0))
	camera.set("camera_distance", 6.0)
	camera.set("camera_pitch_degrees", 18.0)
	camera.set("camera_fov_degrees", 52.0)
	camera.set("look_height", 0.72)
	add_child(camera)

	var game_ui := GameUIScene.instantiate()
	game_ui.name = "GameUI"
	add_child(game_ui)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StretchDestinationHUD"
	layer.layer = 20
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "HeaderPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16.0
	panel.offset_top = 14.0
	panel.offset_right = -16.0
	panel.offset_bottom = 88.0
	layer.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.text = String(_destination.get("name", "Stretch Destination"))
	labels.add_child(_title_label)
	_progress_label = Label.new()
	labels.add_child(_progress_label)
	_balance_label = Label.new()
	_balance_label.text = StretchGoalSystem.format_money(StretchGoalSystem.get_balance())
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_balance_label.custom_minimum_size = Vector2(150.0, 0.0)
	row.add_child(_balance_label)
	var return_button := Button.new()
	return_button.text = "Return to Stretchman"
	return_button.custom_minimum_size = Vector2(190.0, 48.0)
	return_button.pressed.connect(_return_to_stretchman)
	row.add_child(return_button)


func _spawn_trainers() -> void:
	var encounters := StretchGoalSystem.get_active_encounters()
	for encounter_index in encounters.size():
		var encounter := encounters[encounter_index]
		var encounter_id := String(encounter.get("encounter_id", ""))
		if StretchGoalSystem.is_encounter_defeated(encounter_id):
			continue
		var trainer := TRAINER_SCENES[encounter_index % TRAINER_SCENES.size()].instantiate() as PFRCharacter
		if trainer == null or not _configure_existing_trainer(trainer, encounter):
			if trainer:
				trainer.free()
			continue
		trainer.position = _trainer_position(encounter_index)
		var look_direction := -_trainer_direction(encounter_index)
		trainer.rotation.y = atan2(-look_direction.x, -look_direction.z)
		trainer.set_meta("route_progress", float(encounter_index + 1) / float(encounters.size() + 1))
		add_child(trainer)


func _configure_existing_trainer(
	trainer: PFRCharacter,
	encounter: Dictionary
) -> bool:
	trainer.prepare_runtime_composition()
	var trainer_behavior := trainer.npc_behavior as TrainerBehavior
	if trainer_behavior == null:
		# Dynamic destinations can repair a stripped release-exported behavior
		# before the character enters the tree.
		trainer_behavior = TrainerBehavior.new()
		trainer.npc_behavior = trainer_behavior

	var encounter_id := String(encounter.get("encounter_id", "")).strip_edges()
	var battle_scene_path := String(encounter.get("battle_scene_path", "")).strip_edges()
	if encounter_id.is_empty() or battle_scene_path.is_empty():
		push_error("Stretch destination encounter data is incomplete.")
		return false

	var challenge_dialog := Dialog.new()
	challenge_dialog.character_name = String(encounter.get("display_name", "Trainer"))
	challenge_dialog.dialog_lines = [
		"This route has no shortcuts. Clear my checkpoint to keep climbing!",
	]
	trainer_behavior.automatic_sight_encounter = true
	trainer_behavior.aggression_mode = TrainerBehavior.AggressionMode.HIGHLY_AGGRO
	trainer_behavior.dialog = challenge_dialog
	trainer_behavior.battle_scene_path = battle_scene_path
	trainer_behavior.encounter_id = encounter_id
	trainer_behavior.detection_distance = 8.0
	trainer_behavior.ray_height = 0.8
	trainer_behavior.detection_collision_mask = 1
	trainer_behavior.stopping_buffer = 0.15
	trainer_behavior.arrival_distance = 0.15
	trainer.name = _safe_node_name(challenge_dialog.character_name)
	trainer.set_meta("stretch_encounter_id", encounter_id)
	return true


func _safe_node_name(value: String) -> String:
	var safe := value.replace("/", "-").replace("@", "-").replace(":", "-")
	return safe if not safe.is_empty() else "Trainer"


func _trainer_position(encounter_index: int) -> Vector3:
	match _world_kind:
		"gym":
			return Vector3(0.0, 0.0, -8.0)
		"champion":
			return Vector3(0.0, 0.0, 19.0 - encounter_index * 13.0)
		_:
			return (
				_route_trainer_positions[encounter_index]
				if encounter_index >= 0 and encounter_index < _route_trainer_positions.size()
				else Vector3.ZERO
			)


func _trainer_direction(encounter_index: int) -> Vector3:
	if _world_kind != "route":
		return Vector3(0.0, 0.0, -1.0)
	return (
		_route_trainer_directions[encounter_index]
		if encounter_index >= 0 and encounter_index < _route_trainer_directions.size()
		else Vector3(0.0, 0.0, -1.0)
	)


func _sample_route(progress: float) -> Vector3:
	if _route_points.is_empty():
		return Vector3.ZERO
	if _route_points.size() == 1:
		return _route_points[0]
	var scaled := clampf(progress, 0.0, 1.0) * float(_route_points.size() - 1)
	var lower := mini(floori(scaled), _route_points.size() - 2)
	return _route_points[lower].lerp(_route_points[lower + 1], scaled - float(lower))


func _sample_route_direction(progress: float) -> Vector3:
	if _route_points.size() < 2:
		return Vector3(0.0, 0.0, -1.0)
	var scaled := clampf(progress, 0.0, 1.0) * float(_route_points.size() - 1)
	var lower := mini(floori(scaled), _route_points.size() - 2)
	return (_route_points[lower + 1] - _route_points[lower]).normalized()


func _yaw_for_direction(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)


func _update_progress_text() -> void:
	if not is_instance_valid(_progress_label):
		return
	var encounters := StretchGoalSystem.get_active_encounters()
	var defeated := 0
	for encounter in encounters:
		if StretchGoalSystem.is_encounter_defeated(String(encounter.get("encounter_id", ""))):
			defeated += 1
	if defeated >= encounters.size() and not encounters.is_empty():
		_progress_label.text = (
			"All trainers defeated — reach the glowing far-end gate to unlock Route %d."
			% (_route_index + 1)
			if _world_kind == "route" and _route_index < Content.ROUTE_COUNT - 1
			else "Challenge complete — return to Stretchman when ready."
		)
	else:
		_progress_label.text = "Opponents defeated: %d / %d" % [defeated, encounters.size()]


func _on_route_completion_attempted(result: Dictionary) -> void:
	if not is_instance_valid(_progress_label):
		return
	if not bool(result.get("ok", false)):
		_progress_label.text = String(result.get("error", "The route exit is sealed."))
		return
	var next_route := int(result.get("next_route", -1))
	_progress_label.text = (
		"All 40 routes complete!"
		if next_route < 0
		else "Route %d complete — Route %d is now available from Stretchman."
		% [_route_index, next_route]
	)


func _return_to_stretchman() -> void:
	GameInstance.set_player_movement_enabled(true)
	GameInstance.transfer_to_scene(STRETCHMAN_HUB_SCENE_PATH, &"StretchmanReturnSpawn")


func _on_balance_changed(balance: int) -> void:
	if is_instance_valid(_balance_label):
		_balance_label.text = StretchGoalSystem.format_money(balance)


func _route_color(key: String, fallback: Color) -> Color:
	var value := String(_route_layout.get(key, "")).strip_edges()
	return Color.from_string("#%s" % value, fallback) if not value.is_empty() else fallback


func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	color: Color,
	with_collision: bool,
	rotation_y := 0.0,
	parent: Node3D = null
) -> MeshInstance3D:
	var target: Node3D = parent if parent != null else self
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position
	mesh_instance.rotation.y = rotation_y
	mesh_instance.mesh = mesh
	target.add_child(mesh_instance)
	if not with_collision:
		return mesh_instance
	var body := StaticBody3D.new()
	body.name = "%sCollision" % node_name
	body.position = position
	body.rotation.y = rotation_y
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	target.add_child(body)
	return mesh_instance


func _add_cylinder(
	node_name: String,
	position: Vector3,
	radius: float,
	height: float,
	color: Color,
	parent: Node3D = null
) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	(parent if parent != null else self).add_child(instance)
	return instance


func _add_sphere(
	node_name: String,
	position: Vector3,
	radius: float,
	color: Color,
	parent: Node3D = null
) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	(parent if parent != null else self).add_child(instance)
	return instance
