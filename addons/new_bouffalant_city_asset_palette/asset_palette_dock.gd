@tool
extends VBoxContainer

const CollisionProfiles := preload("res://art/environments/new_bouffalant_city/reference_city_pack/collision/collision_profiles.gd")
const RuntimeContract := preload("res://art/environments/new_bouffalant_city/reference_city_pack/runtime_contract.gd")

signal placement_toggled(enabled: bool)
signal place_at_origin_requested
signal rotation_changed(degrees: float)
signal open_showcase_requested
signal open_ground_workspace_requested

const ALL_CATEGORIES := "All Categories"
const THUMBNAIL_ICON_SIZE := Vector2i(112, 112)
const THUMBNAIL_COLUMN_WIDTH := 140
const THUMBNAIL_DIRECTORY := (
	"res://addons/new_bouffalant_city_asset_palette/thumbnails"
)

var _assets: Array[Dictionary] = []
var _selected_asset: Dictionary = {}
var _resource_previewer: EditorResourcePreview
var _default_thumbnail: Texture2D
var _thumbnail_cache := {}
var _thumbnail_failures := {}
var _thumbnail_requests := {}
var _video_adapter_name := "Unknown adapter"
var _rendering_method := "unknown renderer"

var _search: LineEdit
var _category: OptionButton
var _result_count: Label
var _renderer_status: Label
var _asset_list: ItemList
var _details: Label
var _snap: OptionButton
var _height: SpinBox
var _prefer_surfaces: CheckButton
var _continuous: CheckButton
var _rotation_value: Label
var _place_toggle: Button
var _place_origin: Button
var _status: Label


func initialize(
	assets: Array[Dictionary],
	resource_previewer: EditorResourcePreview,
	default_thumbnail: Texture2D,
	video_adapter_name: String,
	rendering_method: String,
	_unsafe_intel_vulkan_renderer: bool
) -> void:
	_assets = assets
	_resource_previewer = resource_previewer
	_default_thumbnail = default_thumbnail
	_video_adapter_name = video_adapter_name
	_rendering_method = rendering_method
	if (
		_resource_previewer != null
		and not _resource_previewer.preview_invalidated.is_connected(_on_preview_invalidated)
	):
		_resource_previewer.preview_invalidated.connect(_on_preview_invalidated)
	_build_interface()
	_populate_categories()
	_refresh_assets()


func get_selected_asset() -> Dictionary:
	return _selected_asset


func get_snap_step() -> float:
	return float(_snap.get_item_metadata(_snap.selected))


func get_height() -> float:
	return _height.value


func get_prefer_surfaces() -> bool:
	return _prefer_surfaces.button_pressed


func get_continuous_placement() -> bool:
	return _continuous.button_pressed


func get_rotation_degrees() -> float:
	return float(_rotation_value.get_meta("degrees", 0.0))


func is_placement_active() -> bool:
	return _place_toggle.button_pressed


func get_thumbnail_status() -> Dictionary:
	var status := _visible_thumbnail_status()
	status["queued"] = _thumbnail_requests.size()
	return status


func set_placement_active(enabled: bool) -> void:
	_place_toggle.set_pressed_no_signal(enabled)
	_update_place_button()


func start_placement_for_asset(asset_id: String) -> bool:
	for index in range(_asset_list.item_count):
		var asset: Dictionary = _asset_list.get_item_metadata(index)
		if String(asset.get("id", "")) != asset_id:
			continue
		_asset_list.select(index)
		_asset_list.ensure_current_is_visible()
		_select_list_index(index)
		set_placement_active(true)
		placement_toggled.emit(true)
		return true
	return false


func set_rotation_degrees(degrees: float) -> void:
	var normalized := fposmod(degrees, 360.0)
	_rotation_value.set_meta("degrees", normalized)
	_rotation_value.text = "%d°" % int(normalized)
	rotation_changed.emit(normalized)


func set_hover_position(position: Variant) -> void:
	if position is Vector3:
		var point: Vector3 = position
		_status.text = "Next: (%.2f, %.2f, %.2f)" % [point.x, point.y, point.z]
		_status.remove_theme_color_override("font_color")
	elif is_placement_active():
		_status.text = "Aim at the placement plane or an upward-facing collider."


func show_message(message: String, is_error := false) -> void:
	_status.text = message
	if is_error:
		_status.add_theme_color_override("font_color", Color(1.0, 0.42, 0.35))
	else:
		_status.remove_theme_color_override("font_color")


func _build_interface() -> void:
	name = "Bouffalant Assets"
	custom_minimum_size = Vector2(330.0, 460.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.text = "New Bouffalant City"
	heading.add_theme_font_size_override("font_size", 18)
	add_child(heading)

	var intro := Label.new()
	intro.text = "Search the 158-asset catalog, then place scene instances directly in the 3D viewport."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)

	_renderer_status = Label.new()
	_renderer_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_renderer_status.text = "Renderer: %s (%s)" % [
		_video_adapter_name, _rendering_method
	]
	add_child(_renderer_status)

	_search = LineEdit.new()
	_search.placeholder_text = "Search title, ID, kind, or category…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_filter_changed)
	add_child(_search)

	_category = OptionButton.new()
	_category.fit_to_longest_item = false
	_category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category.item_selected.connect(_on_category_selected)
	add_child(_category)

	_result_count = Label.new()
	add_child(_result_count)

	_asset_list = ItemList.new()
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list.custom_minimum_size.y = 340.0
	_asset_list.allow_reselect = true
	_asset_list.icon_mode = ItemList.ICON_MODE_TOP
	_asset_list.fixed_icon_size = THUMBNAIL_ICON_SIZE
	_asset_list.fixed_column_width = THUMBNAIL_COLUMN_WIDTH
	_asset_list.max_columns = 2
	_asset_list.max_text_lines = 2
	_asset_list.same_column_width = true
	_asset_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_asset_list.item_selected.connect(_on_asset_selected)
	_asset_list.item_activated.connect(_on_asset_activated)
	_asset_list.resized.connect(_update_thumbnail_columns)
	add_child(_asset_list)

	_details = Label.new()
	_details.custom_minimum_size.y = 76.0
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_details)

	add_child(HSeparator.new())

	var placement_heading := Label.new()
	placement_heading.text = "Placement"
	placement_heading.add_theme_font_size_override("font_size", 16)
	add_child(placement_heading)

	var snap_row := HBoxContainer.new()
	var snap_label := Label.new()
	snap_label.text = "XZ snap"
	snap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snap_row.add_child(snap_label)
	_snap = OptionButton.new()
	_add_snap_option("0.5 m", 0.5)
	_add_snap_option("2 m", 2.0)
	_add_snap_option("4 m", 4.0)
	snap_row.add_child(_snap)
	add_child(snap_row)

	var height_row := HBoxContainer.new()
	var height_label := Label.new()
	height_label.text = "Fallback Y"
	height_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	height_row.add_child(height_label)
	_height = SpinBox.new()
	_height.min_value = -1000.0
	_height.max_value = 1000.0
	_height.step = 0.5
	_height.value = 0.0
	_height.allow_greater = true
	_height.allow_lesser = true
	_height.suffix = " m"
	height_row.add_child(_height)
	add_child(height_row)

	_prefer_surfaces = CheckButton.new()
	_prefer_surfaces.text = "Prefer upward-facing colliders"
	_prefer_surfaces.tooltip_text = (
		"Place on a collider under the mouse when its surface faces upward; "
		+ "otherwise use the fallback Y plane."
	)
	_prefer_surfaces.button_pressed = true
	add_child(_prefer_surfaces)

	_continuous = CheckButton.new()
	_continuous.text = "Keep placing after each click"
	_continuous.button_pressed = true
	add_child(_continuous)

	var rotation_row := HBoxContainer.new()
	var rotate_left := Button.new()
	rotate_left.text = "↶ 90°"
	rotate_left.tooltip_text = "Rotate counter-clockwise (Q while placing)"
	rotate_left.pressed.connect(_rotate.bind(-90.0))
	rotation_row.add_child(rotate_left)
	_rotation_value = Label.new()
	_rotation_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rotation_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotation_row.add_child(_rotation_value)
	var rotate_right := Button.new()
	rotate_right.text = "90° ↷"
	rotate_right.tooltip_text = "Rotate clockwise (E while placing)"
	rotate_right.pressed.connect(_rotate.bind(90.0))
	rotation_row.add_child(rotate_right)
	add_child(rotation_row)
	set_rotation_degrees(0.0)

	_place_toggle = Button.new()
	_place_toggle.toggle_mode = true
	_place_toggle.text = "Place in 3D View"
	_place_toggle.tooltip_text = (
		"Enable, then left-click in a 3D viewport. Press Q/E to rotate and Escape "
		+ "or right-click to stop."
	)
	_place_toggle.toggled.connect(_on_placement_toggled)
	add_child(_place_toggle)

	_place_origin = Button.new()
	_place_origin.text = "Add at Scene Origin"
	_place_origin.tooltip_text = "Add the selected asset at X = 0, Z = 0 and the fallback Y height."
	_place_origin.pressed.connect(_on_place_origin_pressed)
	add_child(_place_origin)

	_status = Label.new()
	_status.text = "Select an asset to begin."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	add_child(HSeparator.new())

	var browser_row := HBoxContainer.new()
	var ground_button := Button.new()
	ground_button.text = "Ground Grid"
	ground_button.tooltip_text = "Open the 2 × 2 m cobble GridMap workspace."
	ground_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground_button.pressed.connect(func() -> void: open_ground_workspace_requested.emit())
	browser_row.add_child(ground_button)
	var showcase_button := Button.new()
	showcase_button.text = "Metric Browser"
	showcase_button.tooltip_text = "Open the complete 158-asset scale-reference scene."
	showcase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase_button.pressed.connect(func() -> void: open_showcase_requested.emit())
	browser_row.add_child(showcase_button)
	add_child(browser_row)


func _add_snap_option(label: String, value: float) -> void:
	_snap.add_item(label)
	_snap.set_item_metadata(_snap.item_count - 1, value)


func _populate_categories() -> void:
	_category.clear()
	_category.add_item(ALL_CATEGORIES)
	_category.select(0)
	var seen := {}
	for asset in _assets:
		var category := String(asset.get("category", "Uncategorized"))
		if not seen.has(category):
			seen[category] = true
			_category.add_item(category)


func _refresh_assets() -> void:
	var previous_id := String(_selected_asset.get("id", ""))
	var query := _search.text.strip_edges().to_lower()
	var selected_category := _category.get_item_text(_category.selected)
	var selected_index := -1
	_asset_list.clear()

	for asset in _assets:
		var category := String(asset.get("category", "Uncategorized"))
		if selected_category != ALL_CATEGORIES and category != selected_category:
			continue

		var search_text := "%s %s %s %s" % [
			asset.get("title", ""),
			asset.get("id", ""),
			asset.get("kind", ""),
			category,
		]
		if not query.is_empty() and not search_text.to_lower().contains(query):
			continue

		var resource_path := String(asset.get("model_path", ""))
		var item_index := _asset_list.add_item(
			String(asset.get("title", asset.get("id", "Asset"))),
			_thumbnail_for_path(resource_path)
		)
		_asset_list.set_item_metadata(item_index, asset)
		_asset_list.set_item_tooltip(item_index, _asset_tooltip(asset))
		if String(asset.get("id", "")) == previous_id:
			selected_index = item_index

	_update_result_count()
	if _asset_list.item_count == 0:
		_selected_asset = {}
		_details.text = "No catalog assets match this filter."
		_update_action_availability()
		return

	if selected_index < 0:
		selected_index = 0
	_asset_list.select(selected_index)
	_select_list_index(selected_index)
	call_deferred("_request_visible_thumbnails")


func _thumbnail_for_path(path: String) -> Texture2D:
	return _thumbnail_cache.get(path, _default_thumbnail) as Texture2D


func _request_visible_thumbnails() -> void:
	for index in range(_asset_list.item_count):
		var asset: Dictionary = _asset_list.get_item_metadata(index)
		var path := String(asset.get("model_path", ""))
		if (
			path.is_empty()
			or _thumbnail_cache.has(path)
			or _thumbnail_failures.has(path)
			or _thumbnail_requests.has(path)
		):
			continue
		var bundled_thumbnail := ResourceLoader.load(
			_thumbnail_path(asset), "Texture2D"
		) as Texture2D
		if bundled_thumbnail != null:
			_thumbnail_cache[path] = bundled_thumbnail
			_asset_list.set_item_icon(index, bundled_thumbnail)
			continue
		if _resource_previewer == null:
			_thumbnail_failures[path] = true
			continue
		_thumbnail_requests[path] = true
		_resource_previewer.queue_resource_preview(
			path, self, &"_on_resource_preview_ready", path
		)
	_update_result_count()


func _thumbnail_path(asset: Dictionary) -> String:
	return THUMBNAIL_DIRECTORY.path_join("%s.png" % asset.get("id", ""))


func _on_resource_preview_ready(
	path: String,
	preview: Texture2D,
	thumbnail_preview: Texture2D,
	userdata: Variant
) -> void:
	var requested_path := String(userdata)
	_thumbnail_requests.erase(requested_path)
	var texture := preview if preview != null else thumbnail_preview
	if texture != null:
		_thumbnail_cache[requested_path] = texture
		_thumbnail_failures.erase(requested_path)
	else:
		_thumbnail_failures[requested_path] = true

	for index in range(_asset_list.item_count):
		var asset: Dictionary = _asset_list.get_item_metadata(index)
		if String(asset.get("model_path", "")) == requested_path:
			_asset_list.set_item_icon(index, _thumbnail_for_path(requested_path))

	if path != requested_path:
		push_warning(
			"[Bouffalant Assets] Preview callback path changed from %s to %s."
			% [requested_path, path]
		)
	_update_result_count()


func _on_preview_invalidated(path: String) -> void:
	_thumbnail_cache.erase(path)
	_thumbnail_failures.erase(path)
	_thumbnail_requests.erase(path)
	if _is_path_visible(path):
		for index in range(_asset_list.item_count):
			var asset: Dictionary = _asset_list.get_item_metadata(index)
			if String(asset.get("model_path", "")) == path:
				_asset_list.set_item_icon(index, _default_thumbnail)
		call_deferred("_request_visible_thumbnails")


func _is_path_visible(path: String) -> bool:
	for index in range(_asset_list.item_count):
		var asset: Dictionary = _asset_list.get_item_metadata(index)
		if String(asset.get("model_path", "")) == path:
			return true
	return false


func _visible_thumbnail_status() -> Dictionary:
	var ready := 0
	var failed := 0
	for index in range(_asset_list.item_count):
		var asset: Dictionary = _asset_list.get_item_metadata(index)
		var path := String(asset.get("model_path", ""))
		if _thumbnail_cache.has(path):
			ready += 1
		elif _thumbnail_failures.has(path):
			failed += 1
	return {
		"total": _asset_list.item_count,
		"ready": ready,
		"failed": failed,
		"complete": ready + failed,
	}


func _update_result_count() -> void:
	if _asset_list == null:
		return
	var status := _visible_thumbnail_status()
	var suffix := "thumbnails %d/%d" % [status.complete, status.total]
	if status.failed > 0:
		suffix += " (%d fallback)" % status.failed
	_result_count.text = "%d of %d assets • %s" % [
		_asset_list.item_count,
		_assets.size(),
		suffix,
	]


func _update_thumbnail_columns() -> void:
	if _asset_list == null:
		return
	_asset_list.max_columns = maxi(
		1, int(_asset_list.size.x / float(THUMBNAIL_COLUMN_WIDTH))
	)


func _asset_tooltip(asset: Dictionary) -> String:
	var performance := "Standard placement load"
	if RuntimeContract.is_performance_sensitive(asset):
		performance = "High-load asset: %s" % RuntimeContract.performance_summary(asset)
	return "%s\n%s • %s\n%s\n%s\nCollision: %s\n%s" % [
		asset.get("title", ""),
		asset.get("category", ""),
		asset.get("kind", ""),
		_dimensions_text(asset),
		performance,
		_collision_summary(asset),
		asset.get("model_path", ""),
	]


func _dimensions_text(asset: Dictionary) -> String:
	var dimensions := RuntimeContract.effective_dimensions(asset)
	if dimensions.size() != 3:
		return "Dimensions unavailable"
	var text := "%.2f × %.2f × %.2f m" % [
		float(dimensions[0]),
		float(dimensions[1]),
		float(dimensions[2]),
	]
	if RuntimeContract.is_imported_model(asset):
		text += " runtime (0.75 baked)"
	return text


func _select_list_index(index: int) -> void:
	if index < 0 or index >= _asset_list.item_count:
		return
	_selected_asset = _asset_list.get_item_metadata(index)
	var note := "Collision: %s. Author navigation and interaction boundaries per scene." % _collision_summary(_selected_asset)
	if String(_selected_asset.get("category", "")) == "Modular Ground":
		note = "Collision: 0.25 m ground slab included. Use Ground Grid for rapid 2 × 2 cobble painting."
	elif String(_selected_asset.get("category", "")) == "Complete Environment Sections":
		note = "Large source-authored section with %s; use as an assembly, not a GridMap tile." % _collision_summary(_selected_asset).to_lower()
	if RuntimeContract.is_performance_sensitive(_selected_asset):
		note += " High-load asset: %s." % RuntimeContract.performance_summary(_selected_asset)
	if RuntimeContract.uses_vulkan_safe_mesh_import(_selected_asset):
		note += (
			" Uses original mesh buffers for Vulkan stability; textures, collision, and "
			+ "normal shadow casting are retained."
		)
	_details.text = "%s\n%s • %s\n%s" % [
		_selected_asset.get("id", ""),
		_selected_asset.get("category", ""),
		_dimensions_text(_selected_asset),
		note,
	]
	_status.text = "Ready. Enable placement or add at the scene origin."
	_status.remove_theme_color_override("font_color")
	_update_action_availability()


func _collision_summary(asset: Dictionary) -> String:
	if String(asset.get("category", "")) == "Modular Ground":
		return "included ground slab"
	return CollisionProfiles.asset_profile_name(String(asset.get("id", "")))


func _update_action_availability() -> void:
	var has_asset := not _selected_asset.is_empty()
	_place_toggle.disabled = not has_asset
	_place_origin.disabled = not has_asset
	if not has_asset and _place_toggle.button_pressed:
		set_placement_active(false)
		placement_toggled.emit(false)
	_place_origin.text = "Add at Scene Origin"
	_update_place_button()


func _update_place_button() -> void:
	if _place_toggle.button_pressed:
		_place_toggle.text = "Stop Placement (Esc)"
	else:
		_place_toggle.text = "Place in 3D View"


func _rotate(delta: float) -> void:
	set_rotation_degrees(get_rotation_degrees() + delta)


func _on_filter_changed(_new_text: String) -> void:
	_refresh_assets()


func _on_category_selected(_index: int) -> void:
	_refresh_assets()


func _on_asset_selected(index: int) -> void:
	_select_list_index(index)


func _on_asset_activated(index: int) -> void:
	_select_list_index(index)
	set_placement_active(true)
	placement_toggled.emit(true)


func _on_placement_toggled(enabled: bool) -> void:
	_update_place_button()
	if enabled:
		_status.text = "Left-click to place. Q/E rotates; Escape or right-click stops."
	placement_toggled.emit(enabled)


func _on_place_origin_pressed() -> void:
	place_at_origin_requested.emit()
