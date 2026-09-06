@tool
class_name PFRWorldLevel
extends Node3D

## Shared authored-scene contract for every walkable game level.
##
## Level scripts should use get_player() and find_spawn_marker() instead of
## depending on a particular inherited-scene child layout.

@export_group("Level Identity")
@export var level_id := ""
@export var area_id := ""
@export var entry_spawn_marker: StringName = &"EntrySpawn"


func get_player() -> PlayerCharacter:
	var runtime_player := get_node_or_null(^"Runtime/Player") as PlayerCharacter
	if runtime_player != null:
		return runtime_player
	return _find_player(self)


func find_spawn_marker(marker_name: StringName) -> Marker3D:
	if marker_name.is_empty():
		return null
	var markers := get_node_or_null(^"Markers")
	if markers != null:
		var authored_marker := markers.find_child(
			String(marker_name), true, false
		) as Marker3D
		if authored_marker != null:
			return authored_marker
	return find_child(String(marker_name), true, false) as Marker3D


func _find_player(root: Node) -> PlayerCharacter:
	for child: Node in root.get_children():
		if child is PlayerCharacter:
			return child as PlayerCharacter
		var nested_player := _find_player(child)
		if nested_player != null:
			return nested_player
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for required_path in [
		^"Runtime",
		^"Environment",
		^"NavigationRegion3D/WorldGeometry",
		^"Gameplay/Actors",
		^"Gameplay/Encounters",
		^"Gameplay/Interactions",
		^"Gameplay/Transitions",
		^"Gameplay/Objectives",
		^"Markers",
		^"Backdrop",
	]:
		if get_node_or_null(required_path) == null:
			warnings.append("Missing required level node: %s" % required_path)
	if get_player() == null:
		warnings.append("Runtime must provide a PlayerCharacter.")
	if (
		not entry_spawn_marker.is_empty()
		and find_spawn_marker(entry_spawn_marker) == null
	):
		warnings.append(
			"Markers must contain the configured entry marker '%s'."
			% entry_spawn_marker
		)
	return warnings
