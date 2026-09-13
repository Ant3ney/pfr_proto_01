class_name LoadingBattleSprite
extends TextureRect

## Lightweight atlas player for the eight staged loading-battle animations.

var _frames: Array[Dictionary] = []
var _frame_index := 0
var _elapsed_ms := 0.0
var _atlas: Texture2D


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func configure(style: String, sprite_id: String) -> bool:
	set_process(false)
	texture = null
	_frames.clear()
	_frame_index = 0
	_elapsed_ms = 0.0
	if style not in ["ani", "ani-back"] or sprite_id not in [
		"charmander", "froakie", "treecko", "ditto", "wobbuffet"
	]:
		return false
	if style == "ani-back" and sprite_id not in ["charmander", "froakie", "treecko"]:
		return false
	var base_path := "res://art/battle/sprites/generated/%s/%s" % [style, sprite_id]
	var manifest_file := FileAccess.open(base_path + ".json", FileAccess.READ)
	if manifest_file == null:
		return false
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var frame_values: Variant = (parsed as Dictionary).get("frames")
	if typeof(frame_values) != TYPE_ARRAY or (frame_values as Array).is_empty():
		return false
	_atlas = load(base_path + ".png") as Texture2D
	if not is_instance_valid(_atlas):
		return false
	for value: Variant in frame_values as Array:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var frame := value as Dictionary
		var region_value: Variant = frame.get("region")
		if typeof(region_value) != TYPE_DICTIONARY:
			return false
		var region := region_value as Dictionary
		_frames.append({
			"region": Rect2(
				float(region.get("x", 0)),
				float(region.get("y", 0)),
				float(region.get("width", 1)),
				float(region.get("height", 1))
			),
			"duration_ms": maxf(float(frame.get("durationMs", 100)), 16.0),
		})
	_show_frame(0)
	set_process(_frames.size() > 1)
	return true


func _process(delta: float) -> void:
	if _frames.is_empty():
		return
	_elapsed_ms += delta * 1000.0
	var guard := 0
	while _elapsed_ms >= float(_frames[_frame_index].duration_ms) and guard < _frames.size():
		_elapsed_ms -= float(_frames[_frame_index].duration_ms)
		_frame_index = (_frame_index + 1) % _frames.size()
		guard += 1
	_show_frame(_frame_index)


func _show_frame(index: int) -> void:
	if index < 0 or index >= _frames.size() or not is_instance_valid(_atlas):
		return
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = _atlas
	atlas_texture.region = _frames[index].region
	texture = atlas_texture

