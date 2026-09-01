class_name RouteZeroDungeonRuntime
extends Node3D

## Adds dungeon checkpoint geometry and the persistent far-end goal to the
## hand-authored meadow that was formerly called Route 4. The original modular
## terrain, turns, grass, vegetation, and seven standard trainers remain intact.

const CompletionGateScene := preload(
	"res://rnd/stretch/worlds/route_completion_gate.tscn"
)
const ROUTE_HALF_WIDTH := 16.0
const TRAINER_GAP_HALF_WIDTH := 0.55
const GATE_HEIGHT := 1.25
const GATE_DEPTH := 0.42
const CHECKPOINT_X_OFFSETS := {
	# These two authored positions have decorative collision directly south of
	# the trainer. Small, path-safe offsets preserve the composition while
	# keeping the forced checkpoint sight ray unobstructed.
	1: 1.5,
	7: -0.75,
}


func _ready() -> void:
	_build_trainer_chokepoints()
	_build_completion_gate()


func _build_trainer_chokepoints() -> void:
	if get_node_or_null(^"TrainerChokepoints") != null:
		return
	var trainers := get_node_or_null(^"RouteTrainers") as Node3D
	if trainers == null:
		return
	var gates := Node3D.new()
	gates.name = "TrainerChokepoints"
	add_child(gates)
	for trainer_value: Node in trainers.get_children():
		var trainer := trainer_value as PFRCharacter
		if trainer == null:
			continue
		var route_order := int(trainer.get_meta("route_order", trainer.get_index() + 1))
		trainer.position.x += float(CHECKPOINT_X_OFFSETS.get(route_order, 0.0))
		var checkpoint_position := trainer.position
		var behavior := trainer.npc_behavior as TrainerBehavior
		var encounter_id: String = (
			behavior.encounter_id if behavior != null else ""
		)
		trainer.rotation.y = PI
		trainer.set_meta("route_checkpoint_position", checkpoint_position)
		if GameInstance.has_consumed_standard_trainer_sight_encounter(encounter_id):
			# Once its one-time forced sight has been consumed, the standard
			# trainer waits beside the lane for manual rematches and leaves the
			# narrow checkpoint opening traversable.
			var side := -1.0 if checkpoint_position.x > 0.0 else 1.0
			trainer.position += Vector3(side * 1.65, 0.0, -1.15)
		var gate_z := checkpoint_position.z + 0.68
		var left_end := checkpoint_position.x - TRAINER_GAP_HALF_WIDTH
		var right_start := checkpoint_position.x + TRAINER_GAP_HALF_WIDTH
		_add_gate_segment(
			gates,
			"TrainerGate%dL" % route_order,
			-ROUTE_HALF_WIDTH,
			left_end,
			gate_z
		)
		_add_gate_segment(
			gates,
			"TrainerGate%dR" % route_order,
			right_start,
			ROUTE_HALF_WIDTH,
			gate_z
		)


func _add_gate_segment(
	parent: Node3D,
	node_name: String,
	start_x: float,
	end_x: float,
	z_position: float
) -> void:
	var width := end_x - start_x
	if width <= 0.05:
		return
	var center := Vector3((start_x + end_x) * 0.5, GATE_HEIGHT * 0.5, z_position)
	var size := Vector3(width, GATE_HEIGHT, GATE_DEPTH)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.36, 0.16)
	material.roughness = 0.92
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.position = center
	visual.mesh = mesh
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "%sCollision" % node_name
	body.position = center
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _build_completion_gate() -> void:
	if get_node_or_null(^"Route0CompletionGate") != null:
		return
	var gate := CompletionGateScene.instantiate() as RNDRouteCompletionGate
	if gate == null:
		return
	gate.name = "Route0CompletionGate"
	gate.position = Vector3(-6.0, 0.0, -21.1)
	gate.configure(0)
	add_child(gate)
