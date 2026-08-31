class_name RNDStretchDestination
extends Node3D

## Builds the selected gym, outdoor route, or Elite Four corridor from the
## active StretchGoalSystem destination. This is intentionally programmatic R&D
## level art; production replacements can keep the destination/battle contract.

const PlayerScene := preload("res://demo/player.tscn")
const GameUIScene := preload("res://demo/game_ui.tscn")
const PlayerCameraScript := preload("res://core/PlayerCamera.gd")
const TRAINER_SCENES: Array[PackedScene] = [
	preload("res://overworld/trainer_lake/TrainerBackpacker.tscn"),
	preload("res://overworld/trainer_lake/TrainerBusinessman.tscn"),
	preload("res://overworld/trainer_lake/TrainerDeliveryWorker.tscn"),
	preload("res://overworld/trainer_lake/TrainerJogger.tscn"),
	preload("res://overworld/trainer_lake/TrainerPoliceOfficer.tscn"),
	preload("res://overworld/trainer_lake/TrainerTourist.tscn"),
]
const POKEMON_CENTER_PATH := (
	"res://art/environments/new_bouffalant_city/pokemon_center_interior/"
	+ "pokemon_center_interior.tscn"
)

var _destination: Dictionary = {}
var _world_kind := "route"
var _world_length := 70.0
var _start_position := Vector3.ZERO
var _title_label: Label
var _progress_label: Label
var _balance_label: Label


func _ready() -> void:
	_destination = StretchGoalSystem.get_active_destination()
	if _destination.is_empty():
		_destination = StretchGoalSystem.begin_destination("route", 1)
	_world_kind = String(_destination.get("kind", "route"))
	if _world_kind not in ["gym", "route", "champion"]:
		_world_kind = "route"
	_world_length = 36.0 if _world_kind == "gym" else (82.0 if _world_kind == "champion" else 70.0)
	_start_position = Vector3(0.0, 0.0, _world_length * 0.5 - 5.0)

	_build_environment()
	_build_level_geometry()
	_build_player_and_camera()
	_build_hud()
	_spawn_trainers()
	_update_progress_text()
	StretchGoalSystem.balance_changed.connect(_on_balance_changed)


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
			environment.background_color = Color(0.34, 0.66, 0.92)
			environment.ambient_light_color = Color(0.78, 0.88, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_energy = 0.65
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.15 if _world_kind == "route" else 0.85
	sun.shadow_enabled = true
	add_child(sun)


func _build_level_geometry() -> void:
	var floor_color := (
		Color(0.22, 0.54, 0.24)
		if _world_kind == "route"
		else (Color(0.09, 0.075, 0.15) if _world_kind == "champion" else Color(0.16, 0.21, 0.30))
	)
	_add_box("Floor", Vector3(0.0, -0.1, 0.0), Vector3(14.0, 0.2, _world_length), floor_color, true)
	_build_navigation_region()

	var wall_color := Color(0.12, 0.16, 0.22)
	if _world_kind == "champion":
		wall_color = Color(0.12, 0.075, 0.19)
	elif _world_kind == "route":
		wall_color = Color(0.13, 0.38, 0.16)
	_add_box("WestBoundary", Vector3(-7.15, 1.2, 0.0), Vector3(0.3, 2.4, _world_length), wall_color, true)
	_add_box("EastBoundary", Vector3(7.15, 1.2, 0.0), Vector3(0.3, 2.4, _world_length), wall_color, true)
	_add_box(
		"NorthBoundary",
		Vector3(0.0, 1.2, -_world_length * 0.5),
		Vector3(14.0, 2.4, 0.3),
		wall_color,
		true
	)
	_add_box(
		"SouthBoundary",
		Vector3(0.0, 1.2, _world_length * 0.5),
		Vector3(14.0, 2.4, 0.3),
		wall_color,
		true
	)

	if _world_kind == "route":
		_add_box("DirtPath", Vector3(0.0, 0.012, 0.0), Vector3(4.2, 0.025, _world_length - 1.0), Color(0.53, 0.36, 0.20), false)
		_build_route_decorations()
	elif _world_kind == "champion":
		_build_champion_gates()
	else:
		_build_gym_markings()
	_build_trainer_chokepoints()

	var entry_marker := Marker3D.new()
	entry_marker.name = "EntrySpawn"
	entry_marker.position = _start_position
	add_child(entry_marker)


func _build_route_decorations() -> void:
	for decoration_index in 8:
		var z_position := _world_length * 0.5 - 8.0 - decoration_index * 8.0
		for side_value in [-1.0, 1.0]:
			var side := float(side_value)
			var x_position: float = side * (5.0 + float(decoration_index % 2) * 0.65)
			_add_cylinder(
				"TreeTrunk%d%s" % [decoration_index, "L" if side < 0.0 else "R"],
				Vector3(x_position, 0.75, z_position),
				0.22,
				1.5,
				Color(0.30, 0.18, 0.08)
			)
			_add_sphere(
				"TreeCrown%d%s" % [decoration_index, "L" if side < 0.0 else "R"],
				Vector3(x_position, 2.05, z_position),
				0.9,
				Color(0.10, 0.42 + float(decoration_index % 3) * 0.04, 0.14)
			)


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
	# TrainerBehavior deliberately uses one forward ray. These physical gates
	# sit on the player's approach side and center the capsule on that authored
	# detection line before it can pass the trainer.
	var inner_boundary := 6.85
	var half_gap := 0.45
	var segment_width := inner_boundary - half_gap
	var segment_center := half_gap + segment_width * 0.5
	var gate_color := (
		Color(0.13, 0.31, 0.12)
		if _world_kind == "route"
		else (Color(0.22, 0.11, 0.31) if _world_kind == "champion" else Color(0.20, 0.25, 0.34))
	)
	var encounters := StretchGoalSystem.get_active_encounters()
	for encounter_index in encounters.size():
		var trainer_position := _trainer_position(encounter_index)
		var gate_z := trainer_position.z + 0.6
		_add_box(
			"TrainerGate%dL" % (encounter_index + 1),
			Vector3(-segment_center, 0.7, gate_z),
			Vector3(segment_width, 1.4, 0.35),
			gate_color,
			true
		)
		_add_box(
			"TrainerGate%dR" % (encounter_index + 1),
			Vector3(segment_center, 0.7, gate_z),
			Vector3(segment_width, 1.4, 0.35),
			gate_color,
			true
		)


func _build_navigation_region() -> void:
	var half_width := 6.7
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
	camera.far = 120.0
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
	return_button.pressed.connect(_return_to_pokemon_center)
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
		# Existing authored trainer scenes face -Z by default. The destination
		# player approaches from +Z, so rotate the whole authored trainer.
		trainer.rotation.y = PI
		add_child(trainer)


func _configure_existing_trainer(
	trainer: PFRCharacter,
	encounter: Dictionary
) -> bool:
	var trainer_controller := trainer.controller as NPCController
	# A release-exported PackedScene can overwrite the controller's constructor
	# behavior with the inherited exported null value. Runtime destinations
	# inspect trainers before add_child() can invoke PFRCharacter._ready(), so
	# repair the controller explicitly at this pre-spawn boundary.
	if trainer_controller != null:
		trainer_controller.prepare_for_character(trainer)
	var trainer_behavior := (
		trainer_controller.npc_behavior as TrainerBehavior
		if trainer_controller != null
		else null
	)
	if trainer_behavior == null:
		push_error("Authored trainer scene is missing its existing TrainerBehavior.")
		return false

	var encounter_id := String(encounter.get("encounter_id", "")).strip_edges()
	var battle_scene_path := String(encounter.get("battle_scene_path", "")).strip_edges()
	if encounter_id.is_empty() or battle_scene_path.is_empty():
		push_error("Stretch destination encounter data is incomplete.")
		return false

	var challenge_dialog := Dialog.new()
	challenge_dialog.character_name = String(encounter.get("display_name", "Trainer"))
	challenge_dialog.dialog_lines = [
		"You stepped into my line. This stretch-goal battle starts now!",
	]
	trainer_controller.automatic_sight_encounter = true
	trainer_controller.aggression_mode = TrainerBehavior.AggressionMode.HIGHLY_AGGRO
	trainer_controller.dialog = challenge_dialog
	trainer_controller.battle_scene_path = battle_scene_path
	trainer_controller.encounter_id = encounter_id
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
			return Vector3(0.0, 0.0, 18.0 - encounter_index * 14.0)


func _update_progress_text() -> void:
	var encounters := StretchGoalSystem.get_active_encounters()
	var defeated := 0
	for encounter in encounters:
		if StretchGoalSystem.is_encounter_defeated(String(encounter.get("encounter_id", ""))):
			defeated += 1
	if defeated >= encounters.size() and not encounters.is_empty():
		_progress_label.text = "Challenge complete — return to Stretchman when ready."
	else:
		_progress_label.text = "Opponents defeated: %d / %d" % [defeated, encounters.size()]


func _return_to_pokemon_center() -> void:
	GameInstance.set_player_movement_enabled(true)
	GameInstance.transfer_to_scene(POKEMON_CENTER_PATH, &"StretchmanReturnSpawn")


func _on_balance_changed(balance: int) -> void:
	if is_instance_valid(_balance_label):
		_balance_label.text = StretchGoalSystem.format_money(balance)


func _add_box(
	node_name: String,
	position: Vector3,
	size: Vector3,
	color: Color,
	with_collision: bool
) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position
	mesh_instance.mesh = mesh
	add_child(mesh_instance)
	if not with_collision:
		return
	var body := StaticBody3D.new()
	body.name = "%sCollision" % node_name
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _add_cylinder(
	node_name: String,
	position: Vector3,
	radius: float,
	height: float,
	color: Color
) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	add_child(instance)


func _add_sphere(node_name: String, position: Vector3, radius: float, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.mesh = mesh
	add_child(instance)
