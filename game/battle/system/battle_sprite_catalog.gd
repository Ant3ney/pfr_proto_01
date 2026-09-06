class_name BattleSpriteCatalog
extends RefCounted

## Exact-match, lazy-loading access to the generated battle sprite catalog.
##
## The catalog index contains metadata only. At most one front atlas and one
## back atlas are retained here, corresponding to the active opponent/player.
## Missing forms and shiny requests deliberately resolve to the neutral
## placeholder; this class never guesses a related form.

const CATALOG_PATH := "res://art/battle/sprites/generated/catalog.json"
const PLACEHOLDER_PATH := "res://art/battle/sprites/placeholder.svg"
const ANIMATION_NAME := &"idle"
const PLAYER_STYLE := "ani-back"
const OPPONENT_STYLE := "ani"
const SUPPORTED_SCHEMA_VERSION := 1
const SUPPORTED_GENERATOR_VERSION := 1

var _entries: Dictionary = {}
var _summary: Dictionary = {}
var _active_assets: Dictionary = {}
var _last_error := ""


func initialize(catalog_path: String = CATALOG_PATH) -> bool:
	_entries.clear()
	_summary.clear()
	_active_assets.clear()
	_last_error = ""
	var catalog := _read_json(catalog_path)
	if catalog.is_empty():
		return _fail("Battle sprite catalog could not be read: %s" % catalog_path)
	if int(catalog.get("schemaVersion", -1)) != SUPPORTED_SCHEMA_VERSION:
		return _fail("Battle sprite catalog schema is incompatible.")
	var generator_value: Variant = catalog.get("generator", {})
	if typeof(generator_value) != TYPE_DICTIONARY:
		return _fail("Battle sprite catalog generator metadata is missing.")
	if int((generator_value as Dictionary).get("version", -1)) != SUPPORTED_GENERATOR_VERSION:
		return _fail("Battle sprite catalog generator version is incompatible.")
	if not bool(catalog.get("complete", false)):
		return _fail("Battle sprite catalog is incomplete.")
	var entries_value: Variant = catalog.get("entries", [])
	if typeof(entries_value) != TYPE_ARRAY:
		return _fail("Battle sprite catalog entries are invalid.")
	for value: Variant in entries_value as Array:
		if typeof(value) != TYPE_DICTIONARY:
			return _fail("Battle sprite catalog contains a non-object entry.")
		var entry := (value as Dictionary).duplicate(true)
		var sprite_id := String(entry.get("id", ""))
		var style := String(entry.get("style", ""))
		if not _valid_exact_id(sprite_id) or style not in [PLAYER_STYLE, OPPONENT_STYLE]:
			return _fail("Battle sprite catalog contains an invalid identity.")
		var key := _entry_key(style, sprite_id)
		if _entries.has(key):
			return _fail("Battle sprite catalog repeats %s." % key)
		_entries[key] = entry
	_summary = (
		(catalog.get("totals", {}) as Dictionary).duplicate(true)
		if typeof(catalog.get("totals", {})) == TYPE_DICTIONARY
		else {}
	)
	return true


func has_exact(sprite_id: String, player_side: bool) -> bool:
	return _entries.has(_entry_key(_style_for_side(player_side), sprite_id))


func load_active(
	sprite_id: String,
	player_side: bool,
	shiny: bool = false,
	approved_sprite_override: String = ""
) -> Dictionary:
	if _entries.is_empty() and not initialize():
		return {}
	var side := _side_key(player_side)
	release_active(player_side)
	var asset := _resolve_asset(
		sprite_id,
		player_side,
		shiny,
		approved_sprite_override
	)
	if not asset.is_empty():
		_active_assets[side] = asset
	return asset.duplicate(true)


func load_front_thumbnail(
	sprite_id: String,
	shiny: bool = false,
	approved_sprite_override: String = "",
	thumbnail_size := Vector2i(32, 32)
) -> Dictionary:
	## Extract one small still from the exact front-facing GIF atlas without
	## retaining that atlas in the active player/opponent cache. Switch menus can
	## therefore show a full party without holding six animation atlases.
	if _entries.is_empty() and not initialize():
		return {}
	if thumbnail_size.x <= 0 or thumbnail_size.y <= 0:
		_fail("Battle sprite thumbnail dimensions must be positive.")
		return {}

	var asset := _resolve_asset(
		sprite_id,
		false,
		shiny,
		approved_sprite_override
	)
	if asset.is_empty():
		return {}
	var sprite_frames := asset.get("sprite_frames") as SpriteFrames
	if sprite_frames == null or sprite_frames.get_frame_count(ANIMATION_NAME) <= 0:
		_fail("Battle sprite thumbnail source has no frame.")
		return {}
	var frame_texture := sprite_frames.get_frame_texture(ANIMATION_NAME, 0) as AtlasTexture
	if frame_texture == null or frame_texture.atlas == null:
		_fail("Battle sprite thumbnail source is not an atlas frame.")
		return {}
	var atlas_image := frame_texture.atlas.get_image()
	if atlas_image == null or atlas_image.is_empty():
		_fail("Battle sprite thumbnail atlas pixels could not be read.")
		return {}

	var frame_region := Rect2i(
		roundi(frame_texture.region.position.x),
		roundi(frame_texture.region.position.y),
		roundi(frame_texture.region.size.x),
		roundi(frame_texture.region.size.y)
	)
	frame_region = frame_region.intersection(Rect2i(Vector2i.ZERO, atlas_image.get_size()))
	if not frame_region.has_area():
		_fail("Battle sprite thumbnail frame region is empty.")
		return {}
	var frame_image := atlas_image.get_region(frame_region)

	var frame_metadata_value: Variant = asset.get("frame_metadata", [])
	if (
		typeof(frame_metadata_value) != TYPE_ARRAY
		or (frame_metadata_value as Array).is_empty()
		or typeof((frame_metadata_value as Array)[0]) != TYPE_DICTIONARY
	):
		_fail("Battle sprite thumbnail alpha bounds are missing.")
		return {}
	var metadata := (frame_metadata_value as Array)[0] as Dictionary
	var bounds_value: Variant = metadata.get("alpha_bounds", {})
	if typeof(bounds_value) != TYPE_DICTIONARY:
		_fail("Battle sprite thumbnail alpha bounds are invalid.")
		return {}
	var bounds := bounds_value as Dictionary
	var crop := Rect2i(
		roundi(float(bounds.get("x", 0.0))),
		roundi(float(bounds.get("y", 0.0))),
		maxi(1, roundi(float(bounds.get("width", frame_image.get_width())))),
		maxi(1, roundi(float(bounds.get("height", frame_image.get_height()))))
	)
	crop = crop.intersection(Rect2i(Vector2i.ZERO, frame_image.get_size()))
	if not crop.has_area():
		_fail("Battle sprite thumbnail has no visible pixels.")
		return {}

	var cropped := frame_image.get_region(crop)
	if cropped.is_compressed() and cropped.decompress() != OK:
		_fail("Battle sprite thumbnail pixels could not be decompressed.")
		return {}
	cropped.convert(Image.FORMAT_RGBA8)
	var fit_scale := minf(
		float(thumbnail_size.x) / float(cropped.get_width()),
		float(thumbnail_size.y) / float(cropped.get_height())
	)
	var fitted_size := Vector2i(
		maxi(1, roundi(float(cropped.get_width()) * fit_scale)),
		maxi(1, roundi(float(cropped.get_height()) * fit_scale))
	)
	cropped.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_NEAREST)
	var thumbnail_image := Image.create(
		thumbnail_size.x,
		thumbnail_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	thumbnail_image.fill(Color.TRANSPARENT)
	# Center horizontally and ground every silhouette on the same lower edge.
	var destination := Vector2i(
		(thumbnail_size.x - fitted_size.x) / 2,
		thumbnail_size.y - fitted_size.y
	)
	thumbnail_image.blit_rect(
		cropped,
		Rect2i(Vector2i.ZERO, fitted_size),
		destination
	)
	var thumbnail_texture := ImageTexture.create_from_image(thumbnail_image)
	return {
		"texture": thumbnail_texture,
		"sprite_id": String(asset.get("sprite_id", sprite_id)),
		"style": OPPONENT_STYLE,
		"frame_index": 0,
		"atlas_path": String(asset.get("atlas_path", "")),
		"is_placeholder": bool(asset.get("is_placeholder", false)),
		"placeholder_reason": String(asset.get("placeholder_reason", "")),
	}


func release_active(player_side: bool) -> void:
	_active_assets.erase(_side_key(player_side))


func release_all() -> void:
	_active_assets.clear()


func active_atlas_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for side in ["player", "opponent"]:
		if not _active_assets.has(side):
			continue
		var asset := _active_assets[side] as Dictionary
		var atlas_path := String(asset.get("atlas_path", ""))
		if not atlas_path.is_empty():
			paths.append(atlas_path)
	return paths


func catalog_summary() -> Dictionary:
	return _summary.duplicate(true)


func get_last_error() -> String:
	return _last_error


func _resolve_asset(
	sprite_id: String,
	player_side: bool,
	shiny: bool,
	approved_sprite_override: String
) -> Dictionary:
	if not approved_sprite_override.is_empty():
		return _load_override(approved_sprite_override, sprite_id, player_side)
	if shiny:
		return _load_placeholder(sprite_id, player_side, "shiny_not_approved")
	if not _valid_exact_id(sprite_id):
		return _load_placeholder(sprite_id, player_side, "invalid_exact_sprite_id")
	var asset := _load_catalog_asset(sprite_id, player_side)
	if asset.is_empty():
		return _load_placeholder(sprite_id, player_side, "exact_sprite_missing")
	return asset


func _load_catalog_asset(sprite_id: String, player_side: bool) -> Dictionary:
	var style := _style_for_side(player_side)
	var key := _entry_key(style, sprite_id)
	if not _entries.has(key):
		return {}
	var entry := _entries[key] as Dictionary
	var manifest_path := String(entry.get("manifest", ""))
	var manifest := _read_json(manifest_path)
	if manifest.is_empty():
		_fail("Battle sprite manifest could not be read: %s" % manifest_path)
		return {}
	if (
		int(manifest.get("schemaVersion", -1)) != SUPPORTED_SCHEMA_VERSION
		or String(manifest.get("id", "")) != sprite_id
		or String(manifest.get("style", "")) != style
	):
		_fail("Battle sprite manifest identity is incompatible: %s" % manifest_path)
		return {}
	var atlas_value: Variant = manifest.get("atlas", {})
	if typeof(atlas_value) != TYPE_DICTIONARY:
		_fail("Battle sprite manifest lacks atlas metadata: %s" % manifest_path)
		return {}
	var atlas_path := String((atlas_value as Dictionary).get("path", ""))
	var atlas_resource := ResourceLoader.load(
		atlas_path,
		"Texture2D",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Texture2D
	if atlas_resource == null:
		_fail("Battle sprite atlas could not be loaded: %s" % atlas_path)
		return {}
	return _asset_from_manifest(
		manifest,
		atlas_resource,
		atlas_path,
		false,
		""
	)


func _asset_from_manifest(
	manifest: Dictionary,
	atlas: Texture2D,
	atlas_path: String,
	is_placeholder: bool,
	placeholder_reason: String
) -> Dictionary:
	var frames_value: Variant = manifest.get("frames", [])
	if typeof(frames_value) != TYPE_ARRAY or (frames_value as Array).is_empty():
		_fail("Battle sprite frame metadata is missing: %s" % atlas_path)
		return {}
	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation(&"default"):
		sprite_frames.rename_animation(&"default", ANIMATION_NAME)
	else:
		sprite_frames.add_animation(ANIMATION_NAME)
	sprite_frames.set_animation_loop(ANIMATION_NAME, true)
	# A 1000 FPS base makes each duration multiplier equal one millisecond.
	sprite_frames.set_animation_speed(ANIMATION_NAME, 1000.0)
	var frame_metadata: Array[Dictionary] = []
	var content_width := 1.0
	var minimum_alpha_x := INF
	var maximum_alpha_right := -INF
	for value: Variant in frames_value as Array:
		if typeof(value) != TYPE_DICTIONARY:
			_fail("Battle sprite frame metadata contains a non-object entry.")
			return {}
		var frame := value as Dictionary
		var region_value: Variant = frame.get("region", {})
		var bounds_value: Variant = frame.get("alphaBounds", {})
		if typeof(region_value) != TYPE_DICTIONARY or typeof(bounds_value) != TYPE_DICTIONARY:
			_fail("Battle sprite frame bounds are invalid.")
			return {}
		var region := region_value as Dictionary
		var alpha_bounds := bounds_value as Dictionary
		content_width = maxf(
			content_width,
			maxf(1.0, float(alpha_bounds.get("width", 1.0)))
		)
		minimum_alpha_x = minf(minimum_alpha_x, float(alpha_bounds.get("x", 0.0)))
		maximum_alpha_right = maxf(
			maximum_alpha_right,
			float(alpha_bounds.get("x", 0.0)) + float(alpha_bounds.get("width", 1.0))
		)
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = atlas
		atlas_texture.region = Rect2(
			float(region.get("x", 0)),
			float(region.get("y", 0)),
			float(region.get("width", 1)),
			float(region.get("height", 1))
		)
		atlas_texture.filter_clip = true
		var duration_ms := maxf(1.0, float(frame.get("durationMs", 100.0)))
		sprite_frames.add_frame(ANIMATION_NAME, atlas_texture, duration_ms)
		frame_metadata.append({
			"duration_ms": duration_ms,
			"alpha_bounds": alpha_bounds.duplicate(true),
		})
	var canvas_value: Variant = manifest.get("canvas", {})
	var canvas: Dictionary = (
		(canvas_value as Dictionary).duplicate(true)
		if typeof(canvas_value) == TYPE_DICTIONARY
		else {"width": 1, "height": 1}
	)
	var canvas_width := maxf(1.0, float(canvas.get("width", 1.0)))
	return {
		"sprite_id": String(manifest.get("id", "")),
		"style": String(manifest.get("style", "")),
		"sprite_frames": sprite_frames,
		"frame_metadata": frame_metadata,
		"canvas": canvas,
		"content_width": content_width,
		"content_left_extent": maxf(0.0, canvas_width * 0.5 - minimum_alpha_x),
		"content_right_extent": maxf(0.0, maximum_alpha_right - canvas_width * 0.5),
		"content_height": maxf(1.0, float(manifest.get("contentHeight", 1.0))),
		"atlas_path": atlas_path,
		"is_placeholder": is_placeholder,
		"placeholder_reason": placeholder_reason,
	}


func _load_placeholder(sprite_id: String, player_side: bool, reason: String) -> Dictionary:
	var texture := ResourceLoader.load(
		PLACEHOLDER_PATH,
		"Texture2D",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Texture2D
	if texture == null:
		_fail("Neutral battle sprite placeholder could not be loaded.")
		return {}
	return _single_frame_asset(
		texture,
		PLACEHOLDER_PATH,
		sprite_id,
		_style_for_side(player_side),
		true,
		reason
	)


func _load_override(override_path: String, sprite_id: String, player_side: bool) -> Dictionary:
	if not _valid_override_path(override_path):
		return _load_placeholder(sprite_id, player_side, "invalid_sprite_override")
	var texture := ResourceLoader.load(
		override_path,
		"Texture2D",
		ResourceLoader.CACHE_MODE_IGNORE
	) as Texture2D
	if texture == null:
		return _load_placeholder(sprite_id, player_side, "sprite_override_load_failed")
	return _single_frame_asset(
		texture,
		override_path,
		sprite_id,
		_style_for_side(player_side),
		false,
		""
	)


func _single_frame_asset(
	texture: Texture2D,
	texture_path: String,
	sprite_id: String,
	style: String,
	is_placeholder: bool,
	reason: String
) -> Dictionary:
	var width := maxi(1, texture.get_width())
	var height := maxi(1, texture.get_height())
	var manifest := {
		"id": sprite_id,
		"style": style,
		"canvas": {"width": width, "height": height},
		"contentHeight": height,
		"frames": [{
			"region": {"x": 0, "y": 0, "width": width, "height": height},
			"durationMs": 1000,
			"alphaBounds": {"x": 0, "y": 0, "width": width, "height": height},
		}],
	}
	return _asset_from_manifest(
		manifest,
		texture,
		texture_path,
		is_placeholder,
		reason
	)


func _read_json(file_path: String) -> Dictionary:
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _valid_override_path(file_path: String) -> bool:
	if not file_path.begins_with("res://") or file_path.contains(".."):
		return false
	var extension := file_path.get_extension().to_lower()
	return extension in ["png", "webp", "svg"] and ResourceLoader.exists(file_path, "Texture2D")


func _valid_exact_id(sprite_id: String) -> bool:
	if sprite_id.is_empty() or sprite_id != sprite_id.to_lower():
		return false
	for character in sprite_id:
		if not (
			(character >= "a" and character <= "z")
			or (character >= "0" and character <= "9")
			or character == "-"
		):
			return false
	return true


func _entry_key(style: String, sprite_id: String) -> String:
	return "%s/%s" % [style, sprite_id]


func _style_for_side(player_side: bool) -> String:
	return PLAYER_STYLE if player_side else OPPONENT_STYLE


func _side_key(player_side: bool) -> String:
	return "player" if player_side else "opponent"


func _fail(message: String) -> bool:
	_last_error = message
	push_error(message)
	return false
