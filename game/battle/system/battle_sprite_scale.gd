class_name BattleSpriteScale
extends RefCounted

## Converts form-specific Pokédex dimensions into a camera-safe battle-sprite
## footprint. PokeAPI exposes height and weight but no width, so the animation's
## verified alpha aspect supplies the native silhouette and weight applies only
## a restrained horizontal bulk correction.

const PLAYER_REFERENCE_GEOMETRIC_M := 2.05
const OPPONENT_REFERENCE_GEOMETRIC_M := 1.90
const PLAYER_MIN_VISIBLE_HEIGHT_M := 0.88
const OPPONENT_MIN_VISIBLE_HEIGHT_M := 0.85
const PLAYER_MAX_VISIBLE_SIZE_M := Vector2(5.88, 3.06)
const OPPONENT_MAX_VISIBLE_SIZE_M := Vector2(6.55, 2.88)
const PLAYER_FALLBACK_HEIGHT_M := 2.35
const OPPONENT_FALLBACK_HEIGHT_M := 2.15
const SMALL_HEIGHT_EXPONENT := 0.50
const LARGE_HEIGHT_EXPONENT := 0.32
const REFERENCE_MASS_KG := 30.0
const MASS_ASPECT_EXPONENT := 0.08
const MIN_BULK_FACTOR := 0.85
const MAX_BULK_FACTOR := 1.18
const MIN_EFFECTIVE_ASPECT := 0.45
const MAX_EFFECTIVE_ASPECT := 2.80


static func calculate(
	pokedex_height_dm: int,
	pokedex_weight_hg: int,
	native_alpha_aspect: float,
	player_side: bool,
	horizontal_fit: float = 1.0
) -> Dictionary:
	var native_aspect := _safe_aspect(native_alpha_aspect)
	var safe_horizontal_fit := _safe_horizontal_fit(horizontal_fit)
	if pokedex_height_dm <= 0 or pokedex_weight_hg < 0:
		return _fallback(native_aspect, player_side, safe_horizontal_fit)

	var height_m := float(pokedex_height_dm) * 0.1
	var weight_kg := float(pokedex_weight_hg) * 0.1
	var height_curve := (
		pow(height_m, SMALL_HEIGHT_EXPONENT)
		if height_m < 1.0
		else pow(height_m, LARGE_HEIGHT_EXPONENT)
	)
	var bulk_factor := 1.0
	if pokedex_weight_hg > 0:
		var expected_mass := REFERENCE_MASS_KG * pow(maxf(height_m, 0.2), 2.0)
		bulk_factor = clampf(
			pow(weight_kg / expected_mass, MASS_ASPECT_EXPONENT),
			MIN_BULK_FACTOR,
			MAX_BULK_FACTOR
		)
	var effective_aspect := clampf(
		native_aspect * bulk_factor,
		MIN_EFFECTIVE_ASPECT,
		MAX_EFFECTIVE_ASPECT
	)
	var geometric_size := _reference_geometric_size(player_side) * height_curve
	var aspect_root := sqrt(effective_aspect)
	var visible_size := Vector2(
		geometric_size * aspect_root,
		geometric_size / aspect_root
	)
	visible_size = _fit_camera_bounds(
		visible_size,
		player_side,
		true,
		safe_horizontal_fit
	)

	return {
		"source": "pokedex",
		"pokedex_height_dm": pokedex_height_dm,
		"pokedex_weight_hg": pokedex_weight_hg,
		"pokedex_height_m": height_m,
		"pokedex_weight_kg": weight_kg,
		"height_curve": height_curve,
		"bulk_factor": bulk_factor,
		"native_aspect": native_aspect,
		"effective_aspect": effective_aspect,
		"horizontal_fit": safe_horizontal_fit,
		"visible_width_m": visible_size.x,
		"visible_height_m": visible_size.y,
		"width_scale": effective_aspect / native_aspect,
	}


static func _fallback(
	native_aspect: float,
	player_side: bool,
	horizontal_fit: float
) -> Dictionary:
	var visible_height := (
		PLAYER_FALLBACK_HEIGHT_M
		if player_side
		else OPPONENT_FALLBACK_HEIGHT_M
	)
	var visible_size := _fit_camera_bounds(
		Vector2(visible_height * native_aspect, visible_height),
		player_side,
		false,
		horizontal_fit
	)
	return {
		"source": "fallback",
		"pokedex_height_dm": 0,
		"pokedex_weight_hg": 0,
		"pokedex_height_m": 0.0,
		"pokedex_weight_kg": 0.0,
		"height_curve": 1.0,
		"bulk_factor": 1.0,
		"native_aspect": native_aspect,
		"effective_aspect": native_aspect,
		"horizontal_fit": horizontal_fit,
		"visible_width_m": visible_size.x,
		"visible_height_m": visible_size.y,
		"width_scale": 1.0,
	}


static func _fit_camera_bounds(
	visible_size: Vector2,
	player_side: bool,
	apply_minimum_height: bool,
	horizontal_fit: float
) -> Vector2:
	var result := visible_size
	if apply_minimum_height:
		var minimum_height := (
			PLAYER_MIN_VISIBLE_HEIGHT_M
			if player_side
			else OPPONENT_MIN_VISIBLE_HEIGHT_M
		)
		if result.y < minimum_height:
			result *= minimum_height / maxf(result.y, 0.001)
	var maximum := (
		PLAYER_MAX_VISIBLE_SIZE_M
		if player_side
		else OPPONENT_MAX_VISIBLE_SIZE_M
	)
	maximum.x *= horizontal_fit
	var fit := minf(1.0, minf(
		maximum.x / maxf(result.x, 0.001),
		maximum.y / maxf(result.y, 0.001)
	))
	return result * fit


static func _reference_geometric_size(player_side: bool) -> float:
	return (
		PLAYER_REFERENCE_GEOMETRIC_M
		if player_side
		else OPPONENT_REFERENCE_GEOMETRIC_M
	)


static func _safe_aspect(value: float) -> float:
	if not is_finite(value) or value <= 0.0:
		return 1.0
	return value


static func _safe_horizontal_fit(value: float) -> float:
	if not is_finite(value) or value <= 0.0:
		return 1.0
	return clampf(value, 0.01, 1.0)
