@tool
extends EditorPlugin

const AssetPaletteDock := preload("res://addons/new_bouffalant_city_asset_palette/asset_palette_dock.gd")
const CATALOG_PATH := (
	"res://art/environments/new_bouffalant_city/reference_city_pack/catalog.json"
)
const SHOWCASE_PATH := "res://tests/manual/new_bouffalant_city/building_ground_metric_showcase.tscn"
const GROUND_WORKSPACE_PATH := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
const ASSET_CONTAINER_NAME := "NewBouffalantCityAssets"
const ASSET_CONTAINER_META := "new_bouffalant_city_asset_container"
const ASSET_ID_META := "new_bouffalant_city_asset_id"
const MAX_RAY_DISTANCE := 100000.0

var _editor_dock: EditorDock
var _scroll_container: ScrollContainer
var _palette: VBoxContainer
var _last_hover_position: Variant = null


func _enter_tree() -> void:
	var assets := _load_assets()
	var video_adapter_name := String(RenderingServer.get_video_adapter_name())
	var rendering_method := String(RenderingServer.get_current_rendering_method())
	var editor_theme := get_editor_interface().get_editor_theme()
	var default_thumbnail: Texture2D = null
	if editor_theme.has_icon(&"PackedScene", &"EditorIcons"):
		default_thumbnail = editor_theme.get_icon(&"PackedScene", &"EditorIcons")
	_palette = AssetPaletteDock.new()
	_palette.initialize(
		assets,
		get_editor_interface().get_resource_previewer(),
		default_thumbnail,
		video_adapter_name,
		rendering_method,
		false
	)
	_palette.placement_toggled.connect(_on_placement_toggled)
	_palette.place_at_origin_requested.connect(_place_at_origin)
	_palette.rotation_changed.connect(_on_rotation_changed)
	_palette.open_showcase_requested.connect(_open_showcase)
	_palette.open_ground_workspace_requested.connect(_open_ground_workspace)

	_editor_dock = EditorDock.new()
	_editor_dock.title = "Bouffalant Assets"
	_editor_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_editor_dock.available_layouts = (
		EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	)
	_scroll_container = ScrollContainer.new()
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.add_child(_palette)
	_editor_dock.add_child(_scroll_container)
	_scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_dock(_editor_dock)

	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()

	if assets.is_empty():
		_palette.show_message("Could not load the environment catalog.", true)
		_show_toast("New Bouffalant City catalog could not be loaded.", true)


func _build() -> bool:
	return true


func _exit_tree() -> void:
	if is_instance_valid(_editor_dock):
		remove_dock(_editor_dock)
		_editor_dock.queue_free()
	_editor_dock = null
	_scroll_container = null
	_palette = null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _placement_active():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		_last_hover_position = _placement_position(camera, event.position)
		_palette.set_hover_position(_last_hover_position)
		update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_stop_placement("Placement stopped.")
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_Q:
			_palette.set_rotation_degrees(_palette.get_rotation_degrees() - 90.0)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_E:
			_palette.set_rotation_degrees(_palette.get_rotation_degrees() + 90.0)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_stop_placement("Placement stopped.")
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.button_index == MOUSE_BUTTON_LEFT:
			var position := _placement_position(camera, event.position)
			if position is Vector3:
				_place_selected_asset(position)
			else:
				_palette.show_message("No valid placement point under the cursor.", true)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if not _placement_active():
		return

	var cursor := overlay.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, overlay.size).has_point(cursor):
		return

	var color := Color(0.35, 0.94, 0.62, 0.95)
	overlay.draw_circle(cursor, 7.0, Color(color, 0.18))
	overlay.draw_arc(cursor, 9.0, 0.0, TAU, 32, color, 2.0, true)
	overlay.draw_line(cursor + Vector2(-14.0, 0.0), cursor + Vector2(14.0, 0.0), color, 1.5)
	overlay.draw_line(cursor + Vector2(0.0, -14.0), cursor + Vector2(0.0, 14.0), color, 1.5)

	var asset: Dictionary = _palette.get_selected_asset()
	var overlay_text := String(asset.get("title", "Place asset"))
	if _last_hover_position is Vector3:
		var point: Vector3 = _last_hover_position
		overlay_text += "  (%.2f, %.2f, %.2f)" % [point.x, point.y, point.z]
	overlay.draw_string(
		overlay.get_theme_default_font(),
		cursor + Vector2(15.0, -12.0),
		overlay_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		overlay.get_theme_default_font_size(),
		color
	)


func _load_assets() -> Array[Dictionary]:
	var assets: Array[Dictionary] = []
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("[Bouffalant Assets] Could not open %s." % CATALOG_PATH)
		return assets

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("[Bouffalant Assets] Catalog JSON is invalid.")
		return assets

	var catalog: Dictionary = parsed
	var catalog_assets: Array = catalog.get("assets", [])
	for value in catalog_assets:
		if value is Dictionary:
			var asset: Dictionary = value
			assets.append(asset)

	if assets.size() != int(catalog.get("asset_count", -1)):
		push_error(
			"[Bouffalant Assets] Catalog declared %d assets but loaded %d."
			% [int(catalog.get("asset_count", -1)), assets.size()]
		)
		assets.clear()
	return assets


func _placement_active() -> bool:
	return is_instance_valid(_palette) and _palette.is_placement_active()


func _placement_position(camera: Camera3D, screen_position: Vector2) -> Variant:
	var position: Variant = null
	if _palette.get_prefer_surfaces():
		position = _walkable_surface_position(camera, screen_position)

	if not position is Vector3:
		var ray_origin := camera.project_ray_origin(screen_position)
		var ray_direction := camera.project_ray_normal(screen_position)
		position = Plane(Vector3.UP, _palette.get_height()).intersects_ray(
			ray_origin, ray_direction
		)

	if not position is Vector3:
		return null

	var point: Vector3 = position
	var snap_step: float = _palette.get_snap_step()
	point.x = snappedf(point.x, snap_step)
	point.z = snappedf(point.z, snap_step)
	point.y = snappedf(point.y, 0.5)
	return point


func _walkable_surface_position(camera: Camera3D, screen_position: Vector2) -> Variant:
	var world := camera.get_world_3d()
	if world == null:
		return null

	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * MAX_RAY_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if normal.dot(Vector3.UP) < 0.55:
		return null
	return hit.get("position", null)


func _place_at_origin() -> void:
	_place_selected_asset(Vector3(0.0, snappedf(_palette.get_height(), 0.5), 0.0))


func _place_selected_asset(world_position: Vector3) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		_palette.show_message("Open or create a 3D scene before placing assets.", true)
		return

	var asset: Dictionary = _palette.get_selected_asset()
	if asset.is_empty():
		_palette.show_message("Select a catalog asset first.", true)
		return

	var resource_path := String(asset.get("model_path", ""))
	var packed_scene := ResourceLoader.load(resource_path, "PackedScene") as PackedScene
	if packed_scene == null:
		_palette.show_message("Could not load %s." % resource_path, true)
		return

	var instance := packed_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	if instance == null:
		_palette.show_message("The selected resource does not have a Node3D root.", true)
		return

	instance.name = String(asset.get("id", "CityAsset")).to_pascal_case()
	instance.set_meta(ASSET_ID_META, asset.get("id", ""))

	var container := _find_asset_container(root)
	var new_container := container == null
	if new_container:
		container = Node3D.new()
		container.name = ASSET_CONTAINER_NAME
		container.editor_description = (
			"Instances placed by the New Bouffalant City Asset Palette. "
			+ "Keep instances at unit scale; normal placement uses 0.5 m snapping and 90° rotations."
		)
		container.set_meta(ASSET_CONTAINER_META, true)

	var world_transform := Transform3D(
		Basis(Vector3.UP, deg_to_rad(_palette.get_rotation_degrees())), world_position
	)
	if new_container:
		if root is Node3D:
			instance.transform = root.global_transform.affine_inverse() * world_transform
		else:
			instance.transform = world_transform
	else:
		instance.transform = container.global_transform.affine_inverse() * world_transform

	var undo_redo := get_undo_redo()
	undo_redo.create_action(
		"Place %s" % asset.get("title", asset.get("id", "City Asset")),
		UndoRedo.MERGE_DISABLE,
		root
	)
	if new_container:
		undo_redo.add_do_method(root, "add_child", container, true)
		undo_redo.add_do_method(container, "set_owner", root)
	undo_redo.add_do_method(container, "add_child", instance, true)
	undo_redo.add_do_method(instance, "set_owner", root)
	undo_redo.add_undo_method(container, "remove_child", instance)
	if new_container:
		undo_redo.add_undo_method(root, "remove_child", container)
		undo_redo.add_do_reference(container)
	undo_redo.add_do_reference(instance)
	undo_redo.commit_action()

	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(instance)
	_palette.show_message(
		"Placed %s at (%.2f, %.2f, %.2f)."
		% [asset.get("title", "asset"), world_position.x, world_position.y, world_position.z]
	)

	if not _palette.get_continuous_placement():
		_stop_placement("Asset placed.")


func _find_asset_container(root: Node) -> Node3D:
	for child in root.get_children():
		if child is Node3D and (
			child.name == ASSET_CONTAINER_NAME or child.get_meta(ASSET_CONTAINER_META, false)
		):
			return child
	return null


func _on_placement_toggled(enabled: bool) -> void:
	if not enabled:
		_last_hover_position = null
	update_overlays()


func _on_rotation_changed(_degrees: float) -> void:
	update_overlays()


func _stop_placement(message: String) -> void:
	_palette.set_placement_active(false)
	_palette.show_message(message)
	_last_hover_position = null
	update_overlays()


func _open_showcase() -> void:
	_stop_placement("Opening the metric browser…")
	get_editor_interface().open_scene_from_path(SHOWCASE_PATH)


func _open_ground_workspace() -> void:
	_stop_placement("Opening the modular ground workspace…")
	get_editor_interface().open_scene_from_path(GROUND_WORKSPACE_PATH)


func _show_toast(message: String, is_error := false) -> void:
	var severity := EditorToaster.SEVERITY_ERROR if is_error else EditorToaster.SEVERITY_INFO
	get_editor_interface().get_editor_toaster().push_toast(message, severity)
