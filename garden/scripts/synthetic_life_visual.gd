extends Node2D
class_name SyntheticLifeVisual

enum Family { WISP, BEETLE, SPORE, CRYSTAL, MOTH, LARVA }
const FAMILY_NAMES: Array[String] = ["Wisp", "Beetle", "Spore", "Crystal", "Moth", "Larva"]
const FAMILY_COUNT := 6

const CPU_MAX_PERCENT := 100.0
const RAM_PREVIEW_MAX_BYTES := 8.0 * 1024.0 * 1024.0 * 1024.0
const MIN_MASS_SCALE := 0.85
const MAX_MASS_SCALE := 1.35
const CPU_SMOOTH_SECONDS := 0.45
const RAM_SMOOTH_SECONDS := 0.9
const REDRAW_INTERVAL_SECONDS := 1.0 / 30.0
const BASE_PULSE_HZ := 0.32
const MAX_PULSE_HZ := 2.4

const SILHOUETTE := Color("#050b13")
const MEMBRANE_DARK := Color("#0a3540")
const MEMBRANE := Color("#167b82")
const MEMBRANE_LIGHT := Color("#42dfca")
const ENERGY := Color("#a6ffe7")
const FILAMENT := Color("#55cdbd")
const BEETLE_PLATE := Color("#9d7652")
const BEETLE_HIGHLIGHT := Color("#d2a878")
const SPORE_BODY := Color("#745b88")
const SPORE_LIGHT := Color("#d8a8e8")
const CRYSTAL_BODY := Color("#397ca1")
const CRYSTAL_LIGHT := Color("#9bdfff")
const MOTH_BODY := Color("#496c8e")
const MOTH_LIGHT := Color("#a6e2e7")
const LARVA_BODY := Color("#a45e47")
const LARVA_LIGHT := Color("#f2a176")
var species := Family.WISP
var _target_activity := 0.0
var _target_mass_scale := MIN_MASS_SCALE
var _activity := 0.0
var _mass_scale := MIN_MASS_SCALE
var _phase := 0.0
var _redraw_elapsed := 0.0
var _selected := false
var _cached_outline := PackedVector2Array()
var _cached_bounds := Rect2()
var _moth_wings: Array[PackedVector2Array] = []
var _draw_scale := 1.0


func _ready() -> void:
	_update_family_cache()
	set_process(true)


func set_metrics(cpu_percent: Variant, memory_rss_bytes: int) -> void:
	_target_activity = _normalize_cpu(cpu_percent)
	_target_mass_scale = _scale_for_memory(memory_rss_bytes)


func set_species(family_index: int) -> bool:
	if family_index < 0 or family_index >= FAMILY_COUNT:
		return false
	species = family_index
	_update_family_cache()
	queue_redraw()
	return true


func get_species_name() -> String:
	return FAMILY_NAMES[species] if species >= 0 and species < FAMILY_COUNT else "Unknown"


func get_silhouette_outline() -> PackedVector2Array:
	return _cached_outline


func _build_silhouette_outline() -> PackedVector2Array:
	match species:
		Family.BEETLE:
			return PackedVector2Array([
				Vector2(-4.0, -42.0), Vector2(15.0, -35.0), Vector2(29.0, -22.0), Vector2(33.0, -3.0),
				Vector2(26.0, 19.0), Vector2(13.0, 34.0), Vector2(0.0, 40.0), Vector2(-13.0, 34.0),
				Vector2(-26.0, 19.0), Vector2(-33.0, -3.0), Vector2(-29.0, -22.0), Vector2(-15.0, -35.0)
			])
		Family.SPORE:
			return PackedVector2Array([
				Vector2(-8.0, 42.0), Vector2(-8.0, 8.0), Vector2(-24.0, 5.0), Vector2(-42.0, 2.0),
				Vector2(-49.0, -4.0), Vector2(-44.0, -12.0), Vector2(-31.0, -20.0), Vector2(-16.0, -25.0),
				Vector2(-10.0, -37.0), Vector2(10.0, -37.0), Vector2(16.0, -25.0), Vector2(31.0, -20.0),
				Vector2(44.0, -12.0), Vector2(49.0, -4.0), Vector2(42.0, 2.0), Vector2(24.0, 5.0),
			Vector2(8.0, 8.0), Vector2(8.0, 42.0)
			])
		Family.CRYSTAL:
			return PackedVector2Array([
				Vector2(-4.0, -51.0), Vector2(12.0, -37.0), Vector2(10.0, -19.0), Vector2(26.0, -8.0),
				Vector2(17.0, 8.0), Vector2(22.0, 25.0), Vector2(7.0, 44.0), Vector2(-8.0, 31.0),
			Vector2(-25.0, 26.0), Vector2(-17.0, 8.0), Vector2(-29.0, -8.0), Vector2(-12.0, -20.0),
			Vector2(-18.0, -38.0)
			])
		Family.MOTH:
			return PackedVector2Array([
				Vector2(-5.0, -9.0), Vector2(-30.0, -44.0), Vector2(-44.0, -39.0), Vector2(-25.0, -4.0),
				Vector2(-46.0, 27.0), Vector2(-34.0, 42.0), Vector2(-5.0, 13.0), Vector2(5.0, 13.0),
				Vector2(34.0, 42.0), Vector2(46.0, 27.0), Vector2(25.0, -4.0), Vector2(44.0, -39.0),
			Vector2(30.0, -44.0), Vector2(5.0, -9.0)
			])
		Family.LARVA:
			return PackedVector2Array([
				Vector2(-43.0, 26.0), Vector2(-37.0, 9.0), Vector2(-27.0, -5.0), Vector2(-14.0, -16.0),
				Vector2(0.0, -23.0), Vector2(14.0, -26.0), Vector2(29.0, -23.0), Vector2(42.0, -14.0),
				Vector2(47.0, 0.0), Vector2(42.0, 16.0), Vector2(29.0, 27.0), Vector2(13.0, 31.0),
			Vector2(-5.0, 29.0), Vector2(-22.0, 32.0), Vector2(-36.0, 36.0)
			])
		_:
			return _membrane_contour(Vector2(0.0, -9.0), 46.0, 52.0, 0.0)


func get_local_visual_bounds() -> Rect2:
	return _cached_bounds


func _update_family_cache() -> void:
	_cached_outline = _build_silhouette_outline()
	if _cached_outline.is_empty():
		_cached_bounds = Rect2()
		return
	var minimum := _cached_outline[0]
	var maximum := _cached_outline[0]
	for point in _cached_outline:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	_cached_bounds = Rect2(minimum, maximum - minimum)
	_moth_wings.clear()
	if species == Family.MOTH:
		_moth_wings = _build_moth_wings()


func _build_moth_wings() -> Array[PackedVector2Array]:
	return [
		PackedVector2Array([Vector2(-4.0, -5.0), Vector2(-13.0, -19.0), Vector2(-25.0, -38.0), Vector2(-39.0, -46.0), Vector2(-49.0, -39.0), Vector2(-47.0, -26.0), Vector2(-35.0, -12.0), Vector2(-19.0, -2.0), Vector2(-4.0, 8.0)]),
		PackedVector2Array([Vector2(4.0, -5.0), Vector2(13.0, -19.0), Vector2(25.0, -38.0), Vector2(39.0, -46.0), Vector2(49.0, -39.0), Vector2(47.0, -26.0), Vector2(35.0, -12.0), Vector2(19.0, -2.0), Vector2(4.0, 8.0)]),
		PackedVector2Array([Vector2(-5.0, 5.0), Vector2(-19.0, 11.0), Vector2(-36.0, 21.0), Vector2(-47.0, 32.0), Vector2(-40.0, 43.0), Vector2(-27.0, 41.0), Vector2(-14.0, 30.0), Vector2(-4.0, 16.0)]),
		PackedVector2Array([Vector2(5.0, 5.0), Vector2(19.0, 11.0), Vector2(36.0, 21.0), Vector2(47.0, 32.0), Vector2(40.0, 43.0), Vector2(27.0, 41.0), Vector2(14.0, 30.0), Vector2(4.0, 16.0)])
	]


func contains_local_point(point: Vector2) -> bool:
	return get_local_visual_bounds().has_point(point)


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	queue_redraw()


func advance_visual(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	var smoothing_delta := minf(delta, 10.0)
	_activity = lerpf(
		_activity,
		_target_activity,
		1.0 - exp(-smoothing_delta / CPU_SMOOTH_SECONDS)
	)
	_mass_scale = lerpf(
		_mass_scale,
		_target_mass_scale,
		1.0 - exp(-smoothing_delta / RAM_SMOOTH_SECONDS)
	)
	_phase = fposmod(_phase + minf(delta, 0.25) * pulse_hz(), TAU)
	_redraw_elapsed += delta
	if _redraw_elapsed >= REDRAW_INTERVAL_SECONDS:
		_redraw_elapsed = fposmod(_redraw_elapsed, REDRAW_INTERVAL_SECONDS)
		queue_redraw()


func get_visual_parameters() -> Dictionary:
	return {
		"activity": _activity,
		"mass_scale": _mass_scale,
		"pulse_hz": pulse_hz(),
		"glow_strength": glow_strength(),
		"filament_amplitude": filament_amplitude(),
		"state": activity_state(),
	}


func activity_state() -> String:
	if _activity >= 0.8:
		return "Overclocked"
	if _activity >= 0.18:
		return "Active"
	return "Dormant"


func pulse_hz() -> float:
	return lerpf(BASE_PULSE_HZ, MAX_PULSE_HZ, _activity)


func glow_strength() -> float:
	return lerpf(0.22, 0.78, _activity)


func filament_amplitude() -> float:
	return lerpf(2.0, 15.0, _activity)


func _process(delta: float) -> void:
	advance_visual(delta)


func _draw() -> void:
	var pulse := 1.0 + sin(_phase) * (0.012 + 0.035 * _activity)
	_draw_scale = _mass_scale * 0.76 * pulse
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _draw_scale)
	var outline := _cached_outline
	draw_colored_polygon(outline, SILHOUETTE)
	draw_polyline(outline, Color("#193c46"), 4.0, true)
	match species:
		Family.BEETLE:
			_draw_beetle(outline)
		Family.SPORE:
			_draw_spore(outline)
		Family.CRYSTAL:
			_draw_crystal(outline)
		Family.MOTH:
			_draw_moth(outline)
		Family.LARVA:
			_draw_larva(outline)
		_:
			_draw_wisp()
	if _selected:
		var bounds := _cached_bounds.grow(5.0)
		draw_arc(bounds.get_center(), maxf(bounds.size.x, bounds.size.y) * 0.48, 0.0, TAU, 48, Color(ENERGY, 0.78), 1.7, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wisp() -> void:
	_draw_filaments()
	_draw_energy_field()
	_draw_membrane()
	_draw_nucleus()


func _draw_beetle(outline: PackedVector2Array) -> void:
	for leg in range(3):
		var y := -15.0 + leg * 15.0
		var endpoint_y := y + (8.0 if leg == 1 else -2.0)
		for side in [-1.0, 1.0]:
			var start := Vector2(side * 23.0, y)
			var joint := start + Vector2(side * 12.0, 4.0)
			var endpoint := Vector2(side * 39.0, endpoint_y)
			draw_line(joint, endpoint, Color(BEETLE_HIGHLIGHT, 0.88), 3.0, true)
			draw_circle(joint, 2.7, BEETLE_PLATE)
			draw_line(endpoint, endpoint + Vector2(side * 4.0, 3.0), BEETLE_HIGHLIGHT, 1.4, true)
	draw_colored_polygon(outline, Color("#344840"))
	draw_polyline(outline, Color(BEETLE_HIGHLIGHT, 0.8), 2.0, true)
	draw_arc(Vector2(0.0, -4.0), 28.0, PI + 0.25, TAU - 0.25, 36, Color(BEETLE_PLATE), 4.0, true)
	for plate in range(3):
		var center_y := -23.0 + plate * 19.0
		var width := 17.0 - absf(float(plate - 1)) * 2.0
		var plate_shape := PackedVector2Array([
			Vector2(-width, center_y - 11.0), Vector2(0.0, center_y - 15.0),
			Vector2(width, center_y - 11.0), Vector2(width + 2.0, center_y + 3.0),
			Vector2(0.0, center_y + 10.0), Vector2(-width - 2.0, center_y + 3.0)
		])
		var plate_color := BEETLE_PLATE.lightened(0.10 if plate == 1 else 0.0)
		draw_colored_polygon(plate_shape, plate_color)
		draw_polyline(plate_shape, Color("#e0bd8e", 0.64), 1.2, true)
	draw_line(Vector2(0.0, -33.0), Vector2(0.0, 32.0), Color("#29352f", 0.7), 1.4, true)
	draw_circle(Vector2(0.0, -1.0), 4.0 + _activity * 2.0, Color(ENERGY, 0.5 + _activity * 0.35))
	draw_arc(Vector2.ZERO, 12.0, -0.9 + _phase, 0.9 + _phase, 24, Color(ENERGY, glow_strength() * 0.7), 1.1, true)


func _draw_spore(outline: PackedVector2Array) -> void:
	var stem := PackedVector2Array([
		Vector2(-7.0, 38.0), Vector2(-8.0, 7.0), Vector2(-5.0, -7.0),
		Vector2(5.0, -7.0), Vector2(8.0, 7.0), Vector2(7.0, 38.0)
	])
	var cap := PackedVector2Array([
		Vector2(-47.0, -4.0), Vector2(-42.0, -13.0), Vector2(-28.0, -20.0),
		Vector2(-14.0, -25.0), Vector2(-9.0, -35.0), Vector2(0.0, -40.0),
		Vector2(9.0, -35.0), Vector2(14.0, -25.0), Vector2(28.0, -20.0),
		Vector2(42.0, -13.0), Vector2(47.0, -4.0), Vector2(37.0, 1.0),
		Vector2(19.0, 4.0), Vector2(0.0, 6.0), Vector2(-19.0, 4.0), Vector2(-37.0, 1.0)
	])
	draw_colored_polygon(stem, Color("#523e65"))
	draw_polyline(stem, Color(SPORE_LIGHT, 0.7), 1.6, true)
	draw_colored_polygon(cap, Color(SPORE_BODY))
	draw_polyline(cap, Color(SPORE_LIGHT, 0.78), 1.8, true)
	draw_polyline(PackedVector2Array([Vector2(-33.0, -3.0), Vector2(-19.0, -10.0), Vector2(0.0, -13.0), Vector2(19.0, -10.0), Vector2(33.0, -3.0)]), Color("#e9c7f1", 0.45), 1.2, true)
	for index in range(5):
		var x := -22.0 + index * 11.0
		var radius := 2.3 + (1.0 if index == 2 else 0.0)
		var glow := 0.35 + _activity * 0.5
		draw_circle(Vector2(x, -11.0 + absf(x) * 0.12), radius + 3.0, Color(SPORE_LIGHT, glow * 0.12))
		draw_circle(Vector2(x, -11.0 + absf(x) * 0.12), radius, Color(SPORE_LIGHT, glow))
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(side * 9.0, 17.0), 4.0, Color(ENERGY, 0.3 + _activity * 0.55))
		draw_arc(Vector2(side * 9.0, 17.0), 7.0, _phase + side, _phase + side + 2.1, 20, Color(SPORE_LIGHT, glow_strength() * 0.65), 1.1, true)
	# Keep the complete authored silhouette visible beneath the internal colony forms.
	draw_polyline(outline, Color(SPORE_LIGHT, 0.22), 1.0, true)


func _draw_crystal(outline: PackedVector2Array) -> void:
	var main_crystal := PackedVector2Array([
		Vector2(-4.0, -47.0), Vector2(9.0, -34.0), Vector2(7.0, -11.0),
		Vector2(18.0, 0.0), Vector2(10.0, 22.0), Vector2(2.0, 39.0),
		Vector2(-10.0, 23.0), Vector2(-19.0, 1.0), Vector2(-8.0, -13.0), Vector2(-15.0, -35.0)
	])
	var left_shard := PackedVector2Array([Vector2(-8.0, -19.0), Vector2(-27.0, -32.0), Vector2(-29.0, -8.0), Vector2(-17.0, 2.0)])
	var right_shard := PackedVector2Array([Vector2(9.0, -18.0), Vector2(24.0, -31.0), Vector2(27.0, -8.0), Vector2(18.0, 2.0)])
	draw_colored_polygon(outline, Color("#192e47"))
	draw_colored_polygon(left_shard, Color("#3b83a7"))
	draw_colored_polygon(right_shard, Color("#4ba5c3"))
	draw_colored_polygon(main_crystal, Color(CRYSTAL_BODY, 0.94))
	draw_polyline(main_crystal, Color(CRYSTAL_LIGHT, 0.9), 1.6, true)
	draw_line(Vector2(-4.0, -47.0), Vector2(2.0, 39.0), Color("#d4f3ff", 0.78), 1.5, true)
	draw_line(Vector2(9.0, -34.0), Vector2(-19.0, 1.0), Color(CRYSTAL_LIGHT, 0.44), 1.0, true)
	draw_line(Vector2(-8.0, -13.0), Vector2(18.0, 0.0), Color(CRYSTAL_LIGHT, 0.38), 1.0, true)
	draw_circle(Vector2(0.0, 1.0), 5.0 + _activity * 2.0, Color("#dcfbff", glow_strength()))
	draw_arc(Vector2.ZERO, 21.0 + sin(_phase) * 1.5, -0.8, 1.2, 32, Color(CRYSTAL_LIGHT, 0.42 + _activity * 0.35), 1.2, true)
	draw_polyline(outline, Color(CRYSTAL_LIGHT, 0.82), 1.7, true)


func _draw_moth(outline: PackedVector2Array) -> void:
	for index in range(_moth_wings.size()):
		var wing_side := -1.0 if index % 2 == 0 else 1.0
		var flap := sin(_phase + index * 1.4) * (0.018 + _activity * 0.055)
		draw_set_transform(Vector2.ZERO, flap * wing_side, Vector2.ONE * _draw_scale)
		var wing: PackedVector2Array = _moth_wings[index]
		draw_colored_polygon(wing, Color(MOTH_BODY, 0.23 + _activity * 0.13))
		draw_polyline(wing, Color(MOTH_LIGHT, 0.48 + _activity * 0.3), 1.25, true)
		draw_line(Vector2.ZERO, wing[1], Color(MOTH_LIGHT, 0.28), 0.8, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _draw_scale)
	draw_polyline(outline, Color(MOTH_LIGHT, 0.38), 1.1, true)
	draw_line(Vector2(0.0, -19.0), Vector2(0.0, 27.0), Color("#9ccbd5"), 4.0, true)
	draw_circle(Vector2.ZERO, 5.0 + _activity, Color(ENERGY, 0.48 + _activity * 0.4))
	for side in [-1.0, 1.0]:
		var tip := Vector2(side * (10.0 + sin(_phase + side) * 2.0), -29.0)
		draw_line(Vector2(side * 1.0, -13.0), tip, Color(MOTH_LIGHT, 0.65), 1.1, true)


func _draw_larva(outline: PackedVector2Array) -> void:
	var centers: Array[Vector2] = [
		Vector2(-31.0, 19.0), Vector2(-19.0, 7.0), Vector2(-5.0, -3.0),
		Vector2(10.0, -10.0), Vector2(25.0, -12.0), Vector2(36.0, -6.0)
	]
	draw_polyline(outline, Color(LARVA_LIGHT, 0.55), 1.5, true)
	for index in range(centers.size()):
		var center := centers[index]
		var radius := 12.0 - float(index) * 0.75
		var lift := sin(_phase * 0.7 + index * 0.82) * (1.0 + _activity * 2.4)
		center.y += lift
		draw_circle(center + Vector2(0.0, 2.0), radius + 3.0, SILHOUETTE)
		draw_circle(center, radius, LARVA_BODY.lightened(float(index) * 0.035))
		draw_arc(center, radius - 1.5, 0.1, PI - 0.1, 20, Color(LARVA_LIGHT, 0.7), 1.6, true)
		if index > 0:
			draw_line(centers[index - 1], center, Color("#452e35", 0.8), 2.0, true)
		if index > 0 and index < centers.size() - 1 and index % 2 == 0:
			for side in [-1.0, 1.0]:
				var foot := center + Vector2(side * 5.0, radius + 9.0)
				draw_line(center + Vector2(side * 3.0, radius - 1.0), foot, LARVA_LIGHT, 1.5, true)
		var glow_position := center + Vector2(0.0, -3.0)
		draw_circle(glow_position, 2.3, Color(ENERGY, 0.25 + _activity * 0.58))
	draw_arc(centers.back(), 13.0, -0.8 + _phase, 1.0 + _phase, 24, Color(LARVA_LIGHT, 0.4), 1.4, true)


func _draw_filaments() -> void:
	for strand in range(3):
		var side := float(strand - 1)
		var start := Vector2(side * 17.0, 22.0 + absf(side) * 4.0)
		var previous := start
		var length := 34.0 + absf(side) * 4.0
		for segment in range(1, 4):
			var t := float(segment) / 3.0
			var envelope := sin(t * PI)
			var sway := sin(_phase * (0.82 + strand * 0.11) + strand * 1.7 + t * 4.0)
			var position := start + Vector2(
				side * t * 13.0 + sway * filament_amplitude() * envelope,
				length * t
			)
			var alpha := 0.76 - t * 0.42
			var width := lerpf(3.0, 1.1, t) + _activity * 0.5
			draw_line(previous, position, Color(FILAMENT, alpha), width, true)
			if segment < 3:
				draw_circle(position, lerpf(2.0, 1.2, t), Color(ENERGY, alpha * 0.7))
			previous = position


func _draw_energy_field() -> void:
	var strength := glow_strength()
	var wave := (sin(_phase * 1.7) + 1.0) * 0.5
	for ring in range(4):
		var radius := 37.0 + ring * 6.0 + wave * (2.0 + _activity * 5.0)
		var color := Color(0.13, 0.78, 0.72, strength * (0.12 - ring * 0.022))
		draw_arc(Vector2(0.0, -8.0), radius, -2.75, 1.1, 48, color, 1.0 + _activity * 0.45, true)


func _draw_membrane() -> void:
	var center := Vector2(0.0, -9.0)
	var swell := 1.0 + sin(_phase * 0.8) * (0.012 + _activity * 0.022)
	draw_set_transform(center, 0.0, Vector2(_draw_scale * swell, _draw_scale * 1.1 * swell))
	draw_circle(Vector2.ZERO, 46.0, Color("#1b777e"))
	draw_circle(Vector2.ZERO, 43.5, Color(MEMBRANE_DARK))
	draw_circle(Vector2.ZERO, 39.5, Color(MEMBRANE, 0.9))
	draw_circle(Vector2(-1.5, -3.0), 30.5, Color(MEMBRANE_LIGHT, 0.11 + _activity * 0.15))
	draw_circle(Vector2.ZERO, 25.0, Color(MEMBRANE, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _draw_scale)
	draw_arc(Vector2(0.0, 10.0), 30.0, 0.2, 2.95, 36, Color(ENERGY, 0.12 + _activity * 0.14), 1.1, true)


func _membrane_contour(center: Vector2, radius_x: float, radius_y: float, offset: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(40)
	for index in range(40):
		var angle := TAU * float(index) / 40.0
		var modulation := 1.0 + 0.055 * sin(3.0 * angle + _phase + offset)
		modulation += 0.026 * sin(5.0 * angle - _phase * 0.7 + offset)
		var sharpened_x := cos(angle) * (1.0 - 0.08 * sin(angle))
		points[index] = center + Vector2(sharpened_x * radius_x, sin(angle) * radius_y) * modulation
	return points


func _draw_nucleus() -> void:
	var pulse := (sin(_phase * 1.35) + 1.0) * 0.5
	var radius := 12.0 + pulse * (1.4 + _activity * 3.0)
	draw_circle(Vector2(0.0, -11.0), radius + 10.0, Color(0.17, 0.98, 0.8, glow_strength() * 0.12))
	draw_circle(Vector2(0.0, -11.0), radius + 4.0, Color(MEMBRANE_LIGHT, 0.28 + _activity * 0.22))
	draw_circle(Vector2(0.0, -11.0), radius, Color(ENERGY, 0.78 + _activity * 0.18))
	draw_circle(Vector2(-3.0, -14.0), radius * 0.32, Color("#f2fff8", 0.9))
	draw_arc(Vector2(0.0, -11.0), radius + 7.0, _phase, _phase + 2.35, 32, Color("#c4fff0", 0.65), 1.0, true)


static func _normalize_cpu(cpu_percent: Variant) -> float:
	if cpu_percent == null:
		return 0.0
	if typeof(cpu_percent) != TYPE_INT and typeof(cpu_percent) != TYPE_FLOAT:
		return 0.0
	var value := float(cpu_percent)
	if not is_finite(value):
		return 0.0
	return clampf(value / CPU_MAX_PERCENT, 0.0, 1.0)


static func _scale_for_memory(memory_rss_bytes: int) -> float:
	var memory_bytes := clampf(float(memory_rss_bytes), 0.0, RAM_PREVIEW_MAX_BYTES)
	var normalized := log(1.0 + memory_bytes / 33_554_432.0) / log(
		1.0 + RAM_PREVIEW_MAX_BYTES / 33_554_432.0
	)
	return lerpf(MIN_MASS_SCALE, MAX_MASS_SCALE, clampf(normalized, 0.0, 1.0))
