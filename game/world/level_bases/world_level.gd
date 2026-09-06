@tool
class_name PFRWorldLevel
extends Node3D

## Shared authored-scene contract for every walkable game level.
##
## Level scripts should use get_player() and find_spawn_marker() so the
## canonical level hierarchy remains explicit at call sites.

@export_group("Level Identity")
@export var level_id := ""
@export var area_id := ""
@export var entry_spawn_marker: StringName = &"EntrySpawn"


func get_player() -> PlayerCharacter:
	return get_node_or_null(^"Player") as PlayerCharacter


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


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for required_path in [
		^"Player",
		^"Player/Camera3D",
		^"Player/GameUI",
		^"Environment",
		^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid",
		^"NavigationRegion3D/WorldGeometry/Structures",
		^"NavigationRegion3D/WorldGeometry/Props",
		^"NavigationRegion3D/WorldGeometry/Boundaries",
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
		warnings.append("Player must be a direct PlayerCharacter child.")
	if (
		not entry_spawn_marker.is_empty()
		and find_spawn_marker(entry_spawn_marker) == null
	):
		warnings.append(
			"Markers must contain the configured entry marker '%s'."
			% entry_spawn_marker
		)
	return warnings
