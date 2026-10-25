extends RefCounted
class_name HabitatLayout

const SpriteLibrary = preload("res://scripts/cozy_mystic_sprite_library.gd")

enum Kind { AIR, GROUND, PERCH_LOW, FUNGAL_GROUND, FUNGAL_PERCH, PERCH_STABLE }

const MIN_SPACING := 18.0
const SATURATED_SPACING := 7.0
const AIR_CANDIDATE_COUNT := 84
const SURFACE_STEP := SATURATED_SPACING
const VISUAL_CLEARANCE := 3.0
const MOTION_CLEARANCE := 5.0
const OVERLAP_PENALTY := 1000.0

static func species_kind(species: int) -> int:
	match species:
		SpriteLibrary.Species.WISP, SpriteLibrary.Species.MOTH:
			return Kind.AIR
		SpriteLibrary.Species.BEETLE, SpriteLibrary.Species.LARVA:
			return Kind.GROUND
		SpriteLibrary.Species.SPORE:
			return Kind.FUNGAL_GROUND
		SpriteLibrary.Species.CRYSTAL:
			return Kind.PERCH_STABLE
	return -1


static func profiles_for_species(species: int) -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	for profile in all_profiles():
		if profile["eligible_species"].has(species):
			profiles.append(profile)
	return profiles


static func all_profiles() -> Array[Dictionary]:
	var ground_points := ground_surface_points()
	return [
		_air_profile("air_west", Rect2(38.0, 112.0, 172.0, 92.0), [SpriteLibrary.Species.WISP, SpriteLibrary.Species.MOTH]),
		_air_profile("air_center", Rect2(212.0, 104.0, 216.0, 94.0), [SpriteLibrary.Species.WISP, SpriteLibrary.Species.MOTH]),
		_air_profile("air_east", Rect2(430.0, 112.0, 172.0, 92.0), [SpriteLibrary.Species.WISP, SpriteLibrary.Species.MOTH]),
		_surface_profile("ground_main", Kind.GROUND, Vector2(22.0, 618.0), ground_points, [SpriteLibrary.Species.BEETLE, SpriteLibrary.Species.LARVA, SpriteLibrary.Species.CRYSTAL]),
		_ground_bank_profile("ground_bank_west", PackedVector2Array([
			Vector2(28.0, _surface_y_at_points(ground_points, 28.0)), Vector2(48.0, 283.0), Vector2(74.0, 275.0),
			Vector2(101.0, 273.0), Vector2(128.0, 279.0), Vector2(151.0, _surface_y_at_points(ground_points, 151.0)),
		])),
		_ground_bank_profile("ground_bank_center_west", PackedVector2Array([
			Vector2(180.0, _surface_y_at_points(ground_points, 180.0)), Vector2(203.0, 282.0), Vector2(231.0, 276.0),
			Vector2(259.0, 278.0), Vector2(284.0, _surface_y_at_points(ground_points, 284.0)),
		])),
		_ground_bank_profile("ground_bank_center_east", PackedVector2Array([
			Vector2(344.0, _surface_y_at_points(ground_points, 344.0)), Vector2(367.0, 280.0), Vector2(398.0, 272.0),
			Vector2(426.0, 277.0), Vector2(450.0, _surface_y_at_points(ground_points, 450.0)),
		])),
		_ground_bank_profile("ground_bank_east", PackedVector2Array([
			Vector2(483.0, _surface_y_at_points(ground_points, 483.0)), Vector2(509.0, 281.0), Vector2(538.0, 273.0),
			Vector2(566.0, 277.0), Vector2(592.0, 286.0), Vector2(614.0, _surface_y_at_points(ground_points, 614.0)),
		])),
		_surface_profile("fungal_west", Kind.FUNGAL_GROUND, Vector2(42.0, 126.0), ground_points, [SpriteLibrary.Species.SPORE]),
		_surface_profile("fungal_east", Kind.FUNGAL_GROUND, Vector2(500.0, 608.0), ground_points, [SpriteLibrary.Species.SPORE]),
		_ledge_profile("low_perch_west", Kind.PERCH_LOW, Vector2(20.0, 236.0), 112.0, [SpriteLibrary.Species.BEETLE], "wall_shelf"),
		_ledge_profile("low_perch_east", Kind.PERCH_LOW, Vector2(506.0, 237.0), 114.0, [SpriteLibrary.Species.BEETLE], "wall_shelf"),
		# These are legacy aliases for support selection only; the low ledges above
		# are their visible geometry, so do not draw a second copy.
		_ledge_profile("stable_perch_west", Kind.PERCH_STABLE, Vector2(20.0, 236.0), 112.0, [SpriteLibrary.Species.CRYSTAL], ""),
		_ledge_profile("stable_perch_east", Kind.PERCH_STABLE, Vector2(506.0, 237.0), 114.0, [SpriteLibrary.Species.CRYSTAL], ""),
		_ledge_profile("root_perch_west", Kind.PERCH_LOW, Vector2(112.0, 263.0), 128.0, [SpriteLibrary.Species.BEETLE], "root_branch", [132.0, 220.0]),
		_ledge_profile("root_perch_east", Kind.PERCH_LOW, Vector2(398.0, 264.0), 130.0, [SpriteLibrary.Species.BEETLE], "root_branch", [418.0, 508.0]),
		_ledge_profile("mineral_shelf_center", Kind.PERCH_STABLE, Vector2(246.0, 270.0), 150.0, [SpriteLibrary.Species.CRYSTAL], "mineral_shelf", [258.0, 321.0, 384.0]),
		_mushroom_profile("fungal_perch_west", 82.0, 1.2),
		_mushroom_profile("fungal_perch_small", 204.0, 0.72),
		_mushroom_profile("fungal_perch_east", 546.0, 1.45),
		_mushroom_profile("fungal_perch_lilac", 445.0, 0.82),
		_mushroom_profile("fungal_perch_center", 296.0, 0.95),
		_mushroom_profile("fungal_perch_center_east", 372.0, 1.08),
	]


static func ground_surface_points() -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(0, 300), Vector2(34, 294), Vector2(61, 289), Vector2(91, 294),
			Vector2(126, 300), Vector2(158, 297), Vector2(194, 293), Vector2(226, 297),
			Vector2(263, 302), Vector2(296, 298), Vector2(332, 291), Vector2(368, 296),
			Vector2(403, 300), Vector2(438, 296), Vector2(473, 292), Vector2(508, 297),
			Vector2(543, 302), Vector2(580, 296), Vector2(610, 291), Vector2(640, 288),
		]
	)


static func ledge_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile in all_profiles():
		if profile.get("draw_structure", false):
			result.append(profile)
	return result


static func mushroom_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile in all_profiles():
		if profile.has("mushroom_center"):
			result.append(profile)
	return result


static func ground_bank_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for profile in all_profiles():
		if bool(profile.get("ground_bank", false)):
			result.append(profile)
	return result


static func ground_bank_polygon(profile: Dictionary) -> PackedVector2Array:
	var top: PackedVector2Array = profile["points"]
	if top.size() < 2:
		return PackedVector2Array()
	var result := top.duplicate()
	result.append(Vector2(top[top.size() - 1].x, ground_surface_y(top[top.size() - 1].x)))
	result.append(Vector2(top[0].x, ground_surface_y(top[0].x)))
	return result


static func mushroom_cap_polygon(profile: Dictionary) -> PackedVector2Array:
	var center: Vector2 = profile["mushroom_center"]
	var size := float(profile["mushroom_size"])
	return PackedVector2Array(
		[
			center + Vector2(-13, -12) * size, center + Vector2(-10, -19) * size,
			center + Vector2(-5, -23) * size, center + Vector2(5, -23) * size,
			center + Vector2(11, -18) * size, center + Vector2(14, -11) * size,
			center + Vector2(9, -9) * size, center + Vector2(-10, -9) * size,
		]
	)


static func mushroom_stem_rect(profile: Dictionary) -> Rect2:
	var center: Vector2 = profile["mushroom_center"]
	var size := float(profile["mushroom_size"])
	return Rect2(center + Vector2(-2.5, -14.0) * size, Vector2(5.0, 14.0) * size)


static func ledge_polygon(profile: Dictionary) -> PackedVector2Array:
	var origin: Vector2 = profile["ledge_origin"]
	var width := float(profile["ledge_width"])
	var surface: PackedVector2Array = profile["points"]
	return PackedVector2Array(
		[
			surface[0], surface[1],
			surface[1] + Vector2(0.0, 4.0),
			origin + Vector2(width - 10.0, 8.0),
			origin + Vector2(width * 0.58, 5.0),
			origin + Vector2(width * 0.43, 10.0),
			origin + Vector2(12.0, 7.0),
			origin + Vector2(0.0, 3.0),
		]
	)


static func structure_polygon(profile: Dictionary) -> PackedVector2Array:
	var origin: Vector2 = profile["ledge_origin"]
	var width := float(profile["ledge_width"])
	var points: PackedVector2Array = profile["points"]
	var style := str(profile.get("structure_style", "wall_shelf"))
	if style == "root_branch":
		var left := points[0]
		var right := points[1]
		return PackedVector2Array(
			[
				left, right, right + Vector2(1.0, 3.0),
				origin + Vector2(width * 0.76, 11.0),
				origin + Vector2(width * 0.51, 8.0),
				origin + Vector2(width * 0.29, 12.0),
				left + Vector2(-2.0, 6.0),
			]
		)
	if style == "mineral_shelf":
		var left_x := origin.x + 8.0
		var right_x := origin.x + width - 8.0
		var base_left := ground_surface_y(left_x)
		var base_right := ground_surface_y(right_x)
		return PackedVector2Array(
			[
				Vector2(left_x, base_left), points[0], points[1], Vector2(right_x, base_right),
				Vector2(right_x - 6.0, base_right - 2.0),
				Vector2(origin.x + width * 0.68, base_right + 4.0),
				Vector2(origin.x + width * 0.46, base_left + 2.0),
				Vector2(origin.x + width * 0.24, base_left + 6.0),
			]
		)
	return ledge_polygon(profile)


static func root_branch_twigs(profile: Dictionary) -> Array[PackedVector2Array]:
	var supports := support_foot_points(profile)
	var surface: PackedVector2Array = profile["points"]
	var result: Array[PackedVector2Array] = []
	for index in range(mini(supports.size(), surface.size())):
		result.append(PackedVector2Array([surface[index] + Vector2(0.0, 5.0), supports[index]]))
	return result


static func support_foot_points(profile: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var support_x: Array = profile.get("support_x", [])
	for x_value in support_x:
		var x := float(x_value)
		result.append(Vector2(x, ground_surface_y(x)))
	return result


static func choose_placement(
	identity: String, species: int, occupied_positions: Array[Vector2]
) -> Dictionary:
	var profiles := profiles_for_species(species)
	var best_profile: Dictionary = {}
	var best_position := Vector2.ZERO
	var best_clearance := -INF
	var best_tie := -1
	for profile in profiles:
		var candidates := candidate_positions(profile)
		for candidate_index in range(candidates.size()):
			var candidate := candidates[candidate_index]
			var clearance := nearest_distance(candidate, occupied_positions)
			var tie := stable_hash("%s|%s|%d" % [identity, profile["id"], candidate_index])
			if clearance > best_clearance or (is_equal_approx(clearance, best_clearance) and tie > best_tie):
				best_clearance = clearance
				best_tie = tie
				best_profile = profile
				best_position = candidate
	if best_profile.is_empty():
		return {}
	return {
		"profile": best_profile,
		"position": best_position,
		"clearance": best_clearance,
		"spacing_saturated": best_clearance < MIN_SPACING,
	}


static func choose_placement_with_envelopes(
	identity: String, species: int, occupied: Array[Dictionary], ram_scale: float = 1.35
) -> Dictionary:
	var profiles := profiles_for_species(species)
	var best_profile: Dictionary = {}
	var best_position := Vector2.ZERO
	var best_score := -INF
	var best_overlap_area := INF
	var best_tie := -1
	for profile in profiles:
		var candidates := candidate_positions(profile)
		for candidate_index in range(candidates.size()):
			var candidate := candidates[candidate_index]
			var bounds := SpriteLibrary.visual_bounds_at(
				species, candidate, int(profile["kind"]) != Kind.AIR, ram_scale, VISUAL_CLEARANCE
			)
			var overlap_area := 0.0
			var nearest_clearance := INF
			for occupant in occupied:
				var other_bounds: Rect2 = occupant["bounds"]
				var intersection := bounds.intersection(other_bounds)
				if intersection.has_area():
					overlap_area += intersection.get_area()
				var dx := maxf(maxf(other_bounds.position.x - bounds.end.x, bounds.position.x - other_bounds.end.x), 0.0)
				var dy := maxf(maxf(other_bounds.position.y - bounds.end.y, bounds.position.y - other_bounds.end.y), 0.0)
				nearest_clearance = minf(nearest_clearance, Vector2(dx, dy).length())
			if occupied.is_empty():
				nearest_clearance = 1000.0
			var score := nearest_clearance - overlap_area * OVERLAP_PENALTY / maxf(bounds.get_area(), 1.0)
			var tie := stable_hash("%s|%s|%d" % [identity, profile["id"], candidate_index])
			if score > best_score or (is_equal_approx(score, best_score) and tie > best_tie):
				best_score = score
				best_overlap_area = overlap_area
				best_tie = tie
				best_profile = profile
				best_position = candidate
		if best_profile.is_empty():
			return {}
	var selected_bounds := SpriteLibrary.visual_bounds_at(
		species, best_position, int(best_profile["kind"]) != Kind.AIR, ram_scale, VISUAL_CLEARANCE
	)
	return {
		"profile": best_profile,
		"position": best_position,
		"bounds": selected_bounds,
		"overlap_area": best_overlap_area,
		"spacing_saturated": best_overlap_area > 0.0,
	}


static func analyze_composition(
	occupants: Array[Dictionary], excluded_regions: Array[Rect2] = []
) -> Dictionary:
	var by_surface: Dictionary = {}
	var estimated_capacity_by_surface: Dictionary = {}
	for profile in all_profiles():
		estimated_capacity_by_surface[str(profile["id"])] = estimated_capacity(profile)
	var vertical_bands := {"upper": 0, "middle": 0, "lower": 0}
	var potential_interface_intersections := 0
	var overlap_pairs := 0
	var overlap_area := 0.0
	var unsupported := 0
	for index in range(occupants.size()):
		var occupant := occupants[index]
		var bounds: Rect2 = occupant["bounds"]
		var surface_id := str(occupant.get("habitat_id", "unknown"))
		by_surface[surface_id] = int(by_surface.get(surface_id, 0)) + 1
		if bool(occupant.get("requires_support", true)) and not bool(occupant.get("supported", false)):
			unsupported += 1
		var center_y := bounds.get_center().y
		if center_y < 170.0:
			vertical_bands["upper"] = int(vertical_bands["upper"]) + 1
		elif center_y < 250.0:
			vertical_bands["middle"] = int(vertical_bands["middle"]) + 1
		else:
			vertical_bands["lower"] = int(vertical_bands["lower"]) + 1
		for exclusion in excluded_regions:
			if bounds.intersects(exclusion):
				potential_interface_intersections += 1
				break
		for other_index in range(index + 1, occupants.size()):
			var other: Dictionary = occupants[other_index]
			var other_bounds: Rect2 = other["bounds"]
			var intersection := bounds.intersection(other_bounds)
			if intersection.has_area():
				overlap_pairs += 1
				overlap_area += intersection.get_area()
	var saturated_surfaces := 0
	for surface_id in by_surface:
		if int(by_surface[surface_id]) > int(estimated_capacity_by_surface.get(surface_id, 0)):
			saturated_surfaces += 1
	return {
		"count": occupants.size(),
		"by_surface": by_surface,
		"estimated_capacity_by_surface": estimated_capacity_by_surface,
		"saturated_surfaces": saturated_surfaces,
		"vertical_bands": vertical_bands,
		"potential_interface_intersections": potential_interface_intersections,
		"overlap_pairs": overlap_pairs,
		"overlap_area": overlap_area,
		"unsupported": unsupported,
	}


static func estimated_capacity(profile: Dictionary) -> int:
	var footprint := Vector2.ZERO
	var eligible_species: Array = profile.get("eligible_species", [])
	for species_value in eligible_species:
		var bounds := SpriteLibrary.opaque_bounds(int(species_value))
		var scaled_size := Vector2(bounds.size) * (34.0 / float(SpriteLibrary.FRAME_SIZE)) * 1.35
		scaled_size += Vector2.ONE * (2.0 * (VISUAL_CLEARANCE + MOTION_CLEARANCE))
		footprint.x = maxf(footprint.x, scaled_size.x)
		footprint.y = maxf(footprint.y, scaled_size.y)
	if footprint.x <= 0.0 or footprint.y <= 0.0:
		return 0
	if int(profile["kind"]) == Kind.AIR:
		var area: Rect2 = profile["area"]
		var columns := floori(area.size.x / footprint.x)
		var rows := floori(area.size.y / footprint.y)
		return maxi(1, columns * rows)
	var range_x: Vector2 = profile["range_x"]
	return maxi(1, floori((range_x.y - range_x.x) / footprint.x) + 1)


static func candidate_positions(profile: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var kind := int(profile["kind"])
	var range_x: Vector2 = profile["range_x"]
	if kind == Kind.AIR:
		var area: Rect2 = profile["area"]
		var inset := Vector2(12.0, 10.0)
		for sample_index in range(1, AIR_CANDIDATE_COUNT + 1):
			var x_factor := _halton(sample_index, 2)
			var y_factor := _halton(sample_index, 3)
			result.append(
				area.position + inset
				+ Vector2(x_factor * (area.size.x - inset.x * 2.0), y_factor * (area.size.y - inset.y * 2.0))
			)
		return result
	var x := range_x.x
	while x <= range_x.y:
		result.append(Vector2(x, surface_y_at(profile, x)))
		x += SURFACE_STEP
	if result.is_empty():
		result.append(Vector2(range_x.x, surface_y_at(profile, range_x.x)))
	return result


static func surface_y_at(profile: Dictionary, x: float) -> float:
	var points: PackedVector2Array = profile.get("points", PackedVector2Array())
	if points.is_empty():
		return float(profile.get("surface_y", 0.0))
	if x <= points[0].x:
		return points[0].y
	for index in range(points.size() - 1):
		var first := points[index]
		var second := points[index + 1]
		if x <= second.x:
			var width := second.x - first.x
			return lerpf(first.y, second.y, (x - first.x) / maxf(width, 0.001))
	return points[points.size() - 1].y


static func ground_surface_y(x: float) -> float:
	return _surface_y_at_points(ground_surface_points(), x)


static func _surface_y_at_points(points: PackedVector2Array, x: float) -> float:
	if points.is_empty():
		return 0.0
	if x <= points[0].x:
		return points[0].y
	for index in range(points.size() - 1):
		var first := points[index]
		var second := points[index + 1]
		if x <= second.x:
			var width := second.x - first.x
			return lerpf(first.y, second.y, (x - first.x) / maxf(width, 0.001))
	return points[points.size() - 1].y


static func nearest_distance(candidate: Vector2, occupied_positions: Array[Vector2]) -> float:
	if occupied_positions.is_empty():
		return 1_000_000.0
	var nearest := INF
	for position in occupied_positions:
		nearest = minf(nearest, candidate.distance_to(position))
	return nearest


static func stable_hash(value: String) -> int:
	var result: int = 2166136261
	for byte_value in value.to_utf8_buffer():
		result = ((result ^ int(byte_value)) * 16777619) & 0x7fffffff
	return result


static func debug_color(kind: int) -> Color:
	match kind:
		Kind.AIR:
			return Color("#76e1d3")
		Kind.GROUND:
			return Color("#91e9c7")
		Kind.PERCH_LOW, Kind.PERCH_STABLE:
			return Color("#9ad8ff")
		Kind.FUNGAL_GROUND, Kind.FUNGAL_PERCH:
			return Color("#c59ce8")
	return Color("#ffffff")


static func _air_profile(identifier: String, area: Rect2, species: Array[int]) -> Dictionary:
	return {
		"id": identifier,
		"kind": Kind.AIR,
		"range_x": Vector2(area.position.x, area.end.x),
		"area": area,
		"points": PackedVector2Array(),
		"eligible_species": species,
		"margin": Vector2(12.0, 10.0),
	}


static func _surface_profile(
	identifier: String, kind: int, range_x: Vector2, points: PackedVector2Array, species: Array[int]
) -> Dictionary:
	return {
		"id": identifier,
		"kind": kind,
		"range_x": range_x,
		"points": points,
		"eligible_species": species,
		"margin": 0.0,
	}


static func _ground_bank_profile(
 identifier: String, surface: PackedVector2Array
) -> Dictionary:
	return {
		"id": identifier,
		"kind": Kind.GROUND,
		"range_x": Vector2(surface[0].x, surface[surface.size() - 1].x),
		"points": surface,
		"eligible_species": [SpriteLibrary.Species.BEETLE, SpriteLibrary.Species.LARVA, SpriteLibrary.Species.CRYSTAL],
		"margin": 0.0,
		"ground_bank": true,
	}


static func _ledge_profile(
	identifier: String,
	kind: int,
	origin: Vector2,
	width: float,
	species: Array[int],
	style: String = "wall_shelf",
	support_x: Array[float] = []
) -> Dictionary:
	var surface := PackedVector2Array(
		[origin + Vector2(20.0, -15.0), origin + Vector2(width - 20.0, -11.0)]
	)
	return {
		"id": identifier,
		"kind": kind,
		"range_x": Vector2(surface[0].x, surface[1].x),
		"points": surface,
		"eligible_species": species,
		"margin": 0.0,
		"ledge_origin": origin,
		"ledge_width": width,
		"structure_style": style,
		"support_x": support_x,
		"draw_structure": style != "",
	}


static func _mushroom_profile(identifier: String, x: float, size: float) -> Dictionary:
	var center := Vector2(x, ground_surface_y(x))
	var cap_points := mushroom_cap_polygon({"mushroom_center": center, "mushroom_size": size})
	var cap_surface := PackedVector2Array([cap_points[2], cap_points[3]])
	return {
		"id": identifier,
		"kind": Kind.FUNGAL_PERCH,
		"range_x": Vector2(cap_surface[0].x, cap_surface[1].x),
		"points": cap_surface,
		"eligible_species": [SpriteLibrary.Species.SPORE],
		"margin": 0.0,
		"mushroom_center": center,
		"mushroom_size": size,
	}


static func _halton(index: int, base: int) -> float:
	var fraction := 1.0
	var result := 0.0
	var value := index
	while value > 0:
		fraction /= float(base)
		result += fraction * float(value % base)
		value /= base
	return result
