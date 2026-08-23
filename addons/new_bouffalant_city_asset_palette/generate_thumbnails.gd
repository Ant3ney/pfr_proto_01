extends SceneTree

const CATALOG_PATH := (
	"res://art/environments/new_bouffalant_city/reference_city_pack/catalog.json"
)
const OUTPUT_DIRECTORY := (
	"res://addons/new_bouffalant_city_asset_palette/thumbnails"
)
const THUMBNAIL_SIZE := Vector2i(192, 192)
const CAMERA_FOV_DEGREES := 32.0
const CAMERA_DIRECTION := Vector3(1.0, 0.72, 1.0)

var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D


func _init() -> void:
	call_deferred("_generate")


func _generate() -> void:
	var assets := _load_assets()
	if assets.is_empty():
		quit(1)
		return

	var requested_ids := {}
	for asset_id in OS.get_cmdline_user_args():
		requested_ids[String(asset_id)] = true

	var output_path := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path)
	if directory_error != OK:
		push_error(
			"[Bouffalant Thumbnail Generator] Could not create %s (error %d)."
			% [output_path, directory_error]
		)
		quit(1)
		return

	_create_render_stage()
	await process_frame

	var generated := 0
	var failed := 0
	for asset in assets:
		var asset_id := String(asset.get("id", ""))
		if not requested_ids.is_empty() and not requested_ids.has(asset_id):
			continue
		var error := await _render_asset(asset)
		if error == OK:
			generated += 1
			print(
				"Generated Bouffalant thumbnail %d: %s"
				% [generated, asset_id]
			)
		else:
			failed += 1

	print(
		"Bouffalant thumbnail generation complete: %d generated, %d failed."
		% [generated, failed]
	)
	quit(0 if failed == 0 and generated > 0 else 1)


func _load_assets() -> Array[Dictionary]:
	var assets: Array[Dictionary] = []
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("[Bouffalant Thumbnail Generator] Could not open the catalog.")
		return assets

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("[Bouffalant Thumbnail Generator] Catalog JSON is invalid.")
		return assets

	for value in parsed.get("assets", []):
		if value is Dictionary:
			assets.append(value)
	return assets


func _create_render_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ThumbnailViewport"
	_viewport.size = THUMBNAIL_SIZE
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.075, 0.105, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.84, 0.94, 1.0)
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_color = Color(1.0, 0.91, 0.78, 1.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = false
	_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-24.0, 148.0, 0.0)
	fill_light.light_color = Color(0.62, 0.76, 1.0, 1.0)
	fill_light.light_energy = 0.75
	fill_light.shadow_enabled = false
	_viewport.add_child(fill_light)

	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV_DEGREES
	_camera.current = true
	_viewport.add_child(_camera)

	_stage = Node3D.new()
	_stage.name = "AssetStage"
	_viewport.add_child(_stage)


func _render_asset(asset: Dictionary) -> Error:
	var asset_id := String(asset.get("id", ""))
	var model_path := String(asset.get("model_path", ""))
	var packed_scene := ResourceLoader.load(
		model_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed_scene == null:
		push_error(
			"[Bouffalant Thumbnail Generator] Could not load %s (%s)."
			% [asset_id, model_path]
		)
		return ERR_CANT_OPEN

	var instance := packed_scene.instantiate() as Node3D
	if instance == null:
		push_error(
			"[Bouffalant Thumbnail Generator] %s has no Node3D root."
			% asset_id
		)
		return ERR_INVALID_DATA

	_stage.add_child(instance)
	await process_frame
	var bounds := _calculate_bounds(instance)
	if bounds.size.length_squared() <= 0.000001:
		push_error(
			"[Bouffalant Thumbnail Generator] %s has no renderable bounds."
			% asset_id
		)
		instance.queue_free()
		await process_frame
		return ERR_INVALID_DATA

	_frame_camera(bounds)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for _frame in range(3):
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var save_path := "%s/%s.png" % [OUTPUT_DIRECTORY, asset_id]
	var save_error := image.save_png(ProjectSettings.globalize_path(save_path))
	if save_error != OK:
		push_error(
			"[Bouffalant Thumbnail Generator] Could not save %s (error %d)."
			% [save_path, save_error]
		)

	instance.queue_free()
	await process_frame
	return save_error


func _calculate_bounds(instance: Node3D) -> AABB:
	var bounds := AABB()
	var has_bounds := false
	var stage_inverse := _stage.global_transform.affine_inverse()
	var visual_nodes := instance.find_children("*", "VisualInstance3D", true, false)
	if instance is VisualInstance3D:
		visual_nodes.push_front(instance)

	for value in visual_nodes:
		var visual := value as VisualInstance3D
		if visual == null or not visual.visible:
			continue
		var visual_bounds := visual.get_aabb()
		if visual_bounds.size.length_squared() <= 0.000001:
			continue
		var to_stage := stage_inverse * visual.global_transform
		for endpoint_index in range(8):
			var point := to_stage * visual_bounds.get_endpoint(endpoint_index)
			if has_bounds:
				bounds = bounds.expand(point)
			else:
				bounds = AABB(point, Vector3.ZERO)
				has_bounds = true
	return bounds


func _frame_camera(bounds: AABB) -> void:
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 0.25)
	var half_fov := deg_to_rad(CAMERA_FOV_DEGREES * 0.5)
	var distance := radius / sin(half_fov) * 1.12
	var direction := CAMERA_DIRECTION.normalized()
	_camera.position = center + direction * distance
	_camera.near = maxf(0.01, distance - radius * 1.5)
	_camera.far = maxf(100.0, distance + radius * 4.0)
	_camera.look_at(center, Vector3.UP)
