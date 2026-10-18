extends Node2D
class_name ProcessCreature

const SpriteLibrary = preload("res://scripts/cozy_mystic_sprite_library.gd")
const CozyVisualScript = preload("res://scripts/cozy_mystic_visual.gd")
const HabitatLayout = preload("res://scripts/habitat_layout.gd")

enum State { SPAWNING, IDLE, WANDERING, ACTIVE, DESPAWNING }

const RENDERER_LEGACY := "legacy"
const RENDERER_COZY_MYSTIC := "cozy_mystic"

signal despawn_finished(identity: String, creature: ProcessCreature)

const SPAWN_DURATION_SECONDS := 0.42
const DESPAWN_DURATION_SECONDS := 0.42
const ACTIVITY_THRESHOLD := 0.28
const MIN_RAM_SCALE := 0.85
const MAX_RAM_SCALE := 1.35
const MAX_VISUAL_RADIUS := 18.0

var process_identity := ""
var process_name := ""
var process_pid := 0
var cpu_percent: Variant = null
var memory_rss_bytes := 0
var species: int = SpriteLibrary.Species.WISP
var state := State.SPAWNING
var movement_bounds := Rect2(Vector2(20.0, 88.0), Vector2(600.0, 224.0))
var is_selected := false
var visual_renderer := RENDERER_LEGACY
var habitat_id := ""
var habitat_kind := -1
var habitat_profile: Dictionary = {}

var _visual: CreatureVisual
var _cozy_visual: CozyMysticVisual
var _random := RandomNumberGenerator.new()
var _base_speed := 10.0
var _pause_min := 0.7
var _pause_max := 1.8
var _wander_distance := 28.0
var _territory_center := Vector2.ZERO
var _territory_radius := 32.0
var _breath_frequency := 2.0
var _breath_phase := 0.0
var _float_frequency := 1.1
var _float_phase := 0.0
var _float_offset := 0.0
var _float_amplitude := 1.8
var _activity_level := 0.0
var _target_activity := 0.0
var _ram_scale := MIN_RAM_SCALE
var _target_ram_scale := MIN_RAM_SCALE
var _separation_target := Vector2.ZERO
var _separation_level := Vector2.ZERO
var _target_position := Vector2.ZERO
var _pause_remaining := 0.0
var _is_moving := false
var _transition_progress := 1.0
var _lifecycle_tween: Tween
var _animation_generation := 0


func _ready() -> void:
	_visual = get_node("Visual") as CreatureVisual
	_visual.set_species(_legacy_species_for(species))
	_apply_renderer_visibility()
	if visual_renderer == RENDERER_COZY_MYSTIC:
		set_visual_renderer(RENDERER_COZY_MYSTIC)
	_refresh_visuals()


func _process(delta: float) -> void:
	advance_simulation(delta)


func set_movement_bounds(bounds: Rect2) -> void:
	movement_bounds = bounds
	position = _clamp_position(position)
	_target_position = _clamp_position(_target_position)


func configure_habitat(profile: Dictionary, contact_position: Vector2) -> void:
	if profile.is_empty():
		return
	habitat_profile = profile.duplicate(true)
	habitat_id = str(profile["id"])
	habitat_kind = int(profile["kind"])
	if habitat_kind == HabitatLayout.Kind.AIR:
		movement_bounds = profile["area"]
	_territory_center = contact_position
	position = _clamp_position(contact_position)
	_target_position = position
	_territory_center = position


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	if _visual != null:
		_visual.set_selected(value)
	if _cozy_visual != null:
		_cozy_visual.set_selected(value)


func set_visual_renderer(mode: String) -> bool:
	if mode != RENDERER_LEGACY and mode != RENDERER_COZY_MYSTIC:
		return false
	if mode == visual_renderer and (mode == RENDERER_LEGACY or _cozy_visual != null):
		return true
	if mode == RENDERER_COZY_MYSTIC and not SpriteLibrary.load_all():
		push_error("Cozy Mystic renderer unavailable; retaining LEGACY renderer")
		return false
	if mode == RENDERER_COZY_MYSTIC and not _ensure_cozy_visual():
		push_error("Could not create Cozy Mystic visual; retaining LEGACY renderer")
		return false
	if _cozy_visual != null and mode == RENDERER_COZY_MYSTIC:
		if not _cozy_visual.configure(process_identity, species):
			push_error("Cozy Mystic creature setup failed; retained LEGACY renderer")
			return false
	visual_renderer = mode
	_apply_renderer_visibility()
	_refresh_visuals()
	return true


func set_separation_force(force: Vector2) -> void:
	if not is_finite(force.x) or not is_finite(force.y):
		_separation_target = Vector2.ZERO
		return
	_separation_target = force.limit_length(1.0)


func get_separation_force() -> Vector2:
	return _separation_target


func get_visual_center_position() -> Vector2:
	if _visual != null:
		return position + _visual.position
	return position + Vector2(0.0, _float_offset)


func get_separation_radius() -> float:
	var opaque := SpriteLibrary.opaque_bounds(species)
	var conservative_scale := maxf(_ram_scale, _target_ram_scale)
	return maxf(float(opaque.size.x), float(opaque.size.y)) * (34.0 / float(SpriteLibrary.FRAME_SIZE)) * conservative_scale * 0.5


func get_visual_occupancy_bounds(margin: float = 3.0) -> Rect2:
	var conservative_scale := maxf(_ram_scale, _target_ram_scale)
	var supported := not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR
	var image_origin := position if supported else get_visual_center_position()
	return SpriteLibrary.visual_bounds_at(species, image_origin, supported, conservative_scale, margin)


func get_layout_occupant() -> Dictionary:
	var supported := not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR
	return {
		"identity": process_identity,
		"species": species,
		"habitat_id": habitat_id,
		"supported": supported,
		"requires_support": species != SpriteLibrary.Species.WISP and species != SpriteLibrary.Species.MOTH,
		"bounds": get_visual_occupancy_bounds(HabitatLayout.VISUAL_CLEARANCE + HabitatLayout.MOTION_CLEARANCE),
	}


func get_float_offset() -> float:
	return _float_offset


func get_territory_center() -> Vector2:
	return _territory_center


func get_territory_radius() -> float:
	return _territory_radius


func get_species_name() -> String:
	return SpriteLibrary.species_name(species)


func contains_local_point(local_point: Vector2) -> bool:
	if state == State.DESPAWNING:
		return false
	if visual_renderer == RENDERER_COZY_MYSTIC and _cozy_visual != null:
		var cozy_point := _cozy_visual.transform.affine_inverse() * local_point
		return _cozy_visual.contains_body_point(cozy_point)
	if _visual == null:
		return false
	var body_point := _visual.transform.affine_inverse() * local_point
	return _visual.contains_body_point(body_point)


func set_process_record(record: Dictionary, identity: String) -> void:
	if process_identity != identity:
		_reset_for_identity(identity)
	process_identity = identity
	process_name = str(record["name"])
	process_pid = int(record["pid"])
	cpu_percent = record["cpu_percent"]
	memory_rss_bytes = maxi(int(record["memory_rss_bytes"]), 0)
	_target_activity = _activity_from_cpu(cpu_percent, process_pid)
	_target_ram_scale = _scale_for_memory(memory_rss_bytes)


func advance_simulation(delta: float) -> void:
	if process_identity.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	_breath_phase = fposmod(_breath_phase + delta * _breath_frequency, TAU)
	_float_phase = fposmod(_float_phase + delta * _float_frequency, TAU)
	_float_offset = (
		sin(_float_phase) * _float_amplitude
		if habitat_profile.is_empty() or habitat_kind == HabitatLayout.Kind.AIR
		else 0.0
	)
	var smoothing := 1.0 - exp(-delta / 0.75)
	_activity_level = lerpf(_activity_level, _target_activity, smoothing)
	_ram_scale = move_toward(_ram_scale, _target_ram_scale, delta * 0.8)
	var separation_smoothing := 1.0 - exp(-delta / 0.24)
	_separation_level = _separation_level.lerp(_separation_target, separation_smoothing)

	if state == State.DESPAWNING:
		_refresh_visuals()
		return

	if state != State.SPAWNING:
		_update_behavior(delta)
	_apply_separation(delta)
	_refresh_visuals()


func begin_despawn() -> void:
	if state == State.DESPAWNING or process_identity.is_empty():
		return
	_cancel_lifecycle_tween()
	state = State.DESPAWNING
	_is_moving = false
	_animation_generation += 1
	var generation := _animation_generation
	_lifecycle_tween = create_tween()
	_lifecycle_tween.tween_method(
		_set_transition_progress,
		_transition_progress,
		0.0,
		DESPAWN_DURATION_SECONDS
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_lifecycle_tween.finished.connect(_finish_despawn.bind(generation))


func cancel_despawn() -> void:
	if state != State.DESPAWNING:
		return
	_cancel_lifecycle_tween()
	_animation_generation += 1
	state = State.SPAWNING
	_is_moving = false
	_start_spawn_tween(_transition_progress, _animation_generation)


func get_state_name() -> String:
	return State.keys()[state]


func get_lifecycle_progress() -> float:
	return _transition_progress


func get_activity_level() -> float:
	return _activity_level


func get_ram_scale() -> float:
	return _ram_scale


func get_effective_movement_bounds() -> Rect2:
	if not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR:
		var range_x: Vector2 = habitat_profile["range_x"]
		var first_y := HabitatLayout.surface_y_at(habitat_profile, range_x.x)
		var last_y := HabitatLayout.surface_y_at(habitat_profile, range_x.y)
		var top := minf(first_y, last_y)
		var bottom := maxf(first_y, last_y)
		var surface_points: PackedVector2Array = habitat_profile.get("points", PackedVector2Array())
		for surface_point in surface_points:
			if surface_point.x >= range_x.x and surface_point.x <= range_x.y:
				top = minf(top, surface_point.y)
				bottom = maxf(bottom, surface_point.y)
		top -= 1.0
		bottom += 1.0
		return Rect2(range_x.x, top, range_x.y - range_x.x, bottom - top)
	var margin := MAX_VISUAL_RADIUS * MAX_RAM_SCALE
	var size := Vector2(
	maxf(movement_bounds.size.x - margin * 2.0, 0.0),
		maxf(movement_bounds.size.y - margin * 2.0, 0.0)
	)
	return Rect2(movement_bounds.position + Vector2.ONE * margin, size)


func _reset_for_identity(identity: String) -> void:
	_cancel_lifecycle_tween()
	_animation_generation += 1
	process_identity = identity
	_random.seed = posmod(hash(identity), 2_147_483_646) + 1
	species = SpriteLibrary.species_for_identity(identity)
	if _visual != null:
		_visual.set_species(_legacy_species_for(species))
	if _cozy_visual != null:
		_cozy_visual.configure(identity, species)
	_base_speed = _random.randf_range(8.0, 13.0)
	_pause_min = _random.randf_range(0.65, 1.0)
	_pause_max = _pause_min + _random.randf_range(0.65, 1.2)
	_wander_distance = _random.randf_range(22.0, 42.0)
	_territory_radius = _random.randf_range(20.0, 45.0)
	_breath_frequency = _random.randf_range(1.65, 2.45)
	_breath_phase = _random.randf_range(0.0, TAU)
	_float_frequency = _random.randf_range(0.75, 1.45)
	_float_amplitude = _float_amplitude_for_species(species)
	_float_phase = _random.randf_range(0.0, TAU)
	_float_offset = (
		sin(_float_phase) * _float_amplitude
		if habitat_profile.is_empty() or habitat_kind == HabitatLayout.Kind.AIR
		else 0.0
	)
	_activity_level = 0.0
	_target_activity = 0.0
	_ram_scale = MIN_RAM_SCALE
	_target_ram_scale = MIN_RAM_SCALE
	_transition_progress = 0.0
	_pause_remaining = _random.randf_range(_pause_min, _pause_max)
	_is_moving = false
	_target_position = _clamp_position(position)
	_territory_center = position
	_separation_target = Vector2.ZERO
	_separation_level = Vector2.ZERO
	is_selected = false
	state = State.SPAWNING
	_start_spawn_tween(0.0, _animation_generation)


func _start_spawn_tween(from_progress: float, generation: int) -> void:
	_transition_progress = clampf(from_progress, 0.0, 1.0)
	_refresh_visuals()
	_lifecycle_tween = create_tween()
	_lifecycle_tween.tween_method(
		_set_transition_progress,
		_transition_progress,
		1.0,
		SPAWN_DURATION_SECONDS
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lifecycle_tween.finished.connect(_finish_spawn.bind(generation))


func _finish_spawn(generation: int) -> void:
	if generation != _animation_generation or state != State.SPAWNING:
		return
	_transition_progress = 1.0
	_lifecycle_tween = null
	state = State.ACTIVE if _activity_level >= ACTIVITY_THRESHOLD else State.IDLE
	_pause_remaining = _next_pause()
	_refresh_visuals()


func _finish_despawn(generation: int) -> void:
	if generation != _animation_generation or state != State.DESPAWNING:
		return
	_transition_progress = 0.0
	_lifecycle_tween = null
	_refresh_visuals()
	despawn_finished.emit(process_identity, self)


func _cancel_lifecycle_tween() -> void:
	if _lifecycle_tween != null and _lifecycle_tween.is_valid():
		_lifecycle_tween.kill()
	_lifecycle_tween = null


func _set_transition_progress(value: float) -> void:
	_transition_progress = clampf(value, 0.0, 1.0)
	_refresh_visuals()


func _update_behavior(delta: float) -> void:
	if process_pid != 0 and _activity_level >= ACTIVITY_THRESHOLD:
		state = State.ACTIVE
		if _is_moving:
			if _move_toward_destination(
				delta, _species_speed_factor() * (1.0 + _activity_level * 0.65)
			):
				_is_moving = false
				_pause_remaining = _next_pause()
		else:
			_pause_remaining -= delta
			if _pause_remaining <= 0.0:
				_choose_destination()
				_is_moving = true
		return

	if state == State.ACTIVE:
		state = State.IDLE
		_is_moving = false
		_pause_remaining = _next_pause()
	if state == State.IDLE:
		_pause_remaining -= delta
		if _pause_remaining <= 0.0:
			state = State.WANDERING
			_choose_destination()
			_is_moving = true
	elif state == State.WANDERING:
		if _move_toward_destination(delta, _species_speed_factor()):
			state = State.IDLE
			_is_moving = false
			_pause_remaining = _next_pause()


func _apply_separation(delta: float) -> void:
	if _separation_level.length_squared() <= 0.0001:
		return
	var separation := _separation_level
	if not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR:
		separation.y = 0.0
	var displacement := separation.limit_length(1.0) * (12.0 * delta)
	position = _clamp_position(position + displacement)


func _move_toward_destination(delta: float, speed_factor: float) -> bool:
	if not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR:
		var next_x := move_toward(
			position.x, _target_position.x, _base_speed * speed_factor * delta
		)
		position = _clamp_position(Vector2(next_x, position.y))
		return absf(position.x - _target_position.x) <= 0.8
	var distance := position.distance_to(_target_position)
	if distance <= 0.8:
		position = _target_position
		return true
	position = position.move_toward(
		_target_position, _base_speed * speed_factor * delta
	)
	position = _clamp_position(position)
	return position.distance_to(_target_position) <= 0.8


func _choose_destination() -> void:
	if not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR:
		var range_x: Vector2 = habitat_profile["range_x"]
		var horizontal_distance := _random.randf_range(
			0.0, minf(_wander_distance, _territory_radius * 0.7)
		)
		var direction := -1.0 if _random.randf() < 0.5 else 1.0
		var candidate_x := clampf(
			position.x + horizontal_distance * direction, range_x.x, range_x.y
		)
		candidate_x = clampf(
			candidate_x,
			maxf(range_x.x, _territory_center.x - _territory_radius),
			minf(range_x.y, _territory_center.x + _territory_radius)
		)
		if absf(candidate_x - position.x) < 2.0:
			candidate_x = clampf(position.x - direction * 4.0, range_x.x, range_x.y)
		_target_position = _clamp_position(Vector2(candidate_x, position.y))
		return
	var angle := _random.randf_range(0.0, TAU)
	var distance := _random.randf_range(0.0, minf(_wander_distance, _territory_radius * 0.7))
	var candidate := position + Vector2(cos(angle), sin(angle)) * distance
	var home_offset := _territory_center - position
	if home_offset.length() > _territory_radius * 0.6:
		candidate += home_offset.normalized() * minf(home_offset.length() * 0.18, 8.0)
	var territory_offset := candidate - _territory_center
	if territory_offset.length() > _territory_radius:
		candidate -= territory_offset.normalized() * minf(
			(territory_offset.length() - _territory_radius) * 0.55,
			8.0
		)
	_target_position = _clamp_position(candidate)
	if position.distance_to(_target_position) < 2.0:
		var local_angle := _random.randf_range(0.0, TAU)
		var local_distance := _random.randf_range(3.0, minf(12.0, _territory_radius * 0.5))
		_target_position = _clamp_position(
			position + Vector2(cos(local_angle), sin(local_angle)) * local_distance
		)


func _next_pause() -> float:
	var activity_shortening := 1.0 - _activity_level * 0.5
	return (
		_random.randf_range(_pause_min, _pause_max)
		* activity_shortening
		* _species_pause_factor()
	)


func _species_speed_factor() -> float:
	match species:
		SpriteLibrary.Species.BEETLE:
			return 1.16
		SpriteLibrary.Species.SPORE:
			return 0.9
		SpriteLibrary.Species.CRYSTAL:
			return 0.78
		SpriteLibrary.Species.MOTH:
			return 1.08
		SpriteLibrary.Species.LARVA:
			return 0.92
	return 1.0


func _species_pause_factor() -> float:
	match species:
		SpriteLibrary.Species.BEETLE:
			return 0.82
		SpriteLibrary.Species.SPORE:
			return 1.18
		SpriteLibrary.Species.CRYSTAL:
			return 1.24
		SpriteLibrary.Species.MOTH:
			return 0.9
		SpriteLibrary.Species.LARVA:
			return 1.12
	return 1.0


func _float_amplitude_for_species(value: int) -> float:
	match value:
		SpriteLibrary.Species.WISP:
			return 2.25
		SpriteLibrary.Species.BEETLE:
			return 1.15
		SpriteLibrary.Species.SPORE:
			return 1.65
		SpriteLibrary.Species.CRYSTAL:
			return 0.9
		SpriteLibrary.Species.MOTH:
			return 2.3
		SpriteLibrary.Species.LARVA:
			return 0.8
	return 1.8


func _clamp_position(value: Vector2) -> Vector2:
	if not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR:
		var range_x: Vector2 = habitat_profile["range_x"]
		var margin := float(habitat_profile.get("margin", 0.0))
		var minimum_x := maxf(range_x.x + margin, _territory_center.x - _territory_radius)
		var maximum_x := minf(range_x.y - margin, _territory_center.x + _territory_radius)
		if minimum_x > maximum_x:
			minimum_x = range_x.x
			maximum_x = range_x.y
		var supported_x := clampf(value.x, minimum_x, maximum_x)
		return Vector2(supported_x, HabitatLayout.surface_y_at(habitat_profile, supported_x))
	var bounds := get_effective_movement_bounds()
	return Vector2(
		clampf(value.x, bounds.position.x, bounds.end.x),
		clampf(value.y, bounds.position.y, bounds.end.y)
	)


func _activity_from_cpu(value: Variant, pid: int) -> float:
	if pid == 0 or value == null:
		return 0.0
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	var cpu := float(value)
	if not is_finite(cpu) or cpu <= 1.0:
		return 0.0
	return clampf(cpu / 60.0, 0.0, 1.0)


func _scale_for_memory(memory_bytes: int) -> float:
	return scale_for_memory_bytes(memory_bytes)


static func scale_for_memory_bytes(memory_bytes: int) -> float:
	var memory_mib := maxf(float(memory_bytes) / 1_048_576.0, 0.0)
	var normalized := log(1.0 + memory_mib / 16.0) / log(1.0 + 2048.0 / 16.0)
	return lerpf(MIN_RAM_SCALE, MAX_RAM_SCALE, clampf(normalized, 0.0, 1.0))


func _refresh_visuals() -> void:
	if _visual == null:
		return
	var breath := sin(_breath_phase)
	var breath_strength := _species_breath_strength()
	var horizontal_breath := 1.0 + breath * 0.018 * breath_strength
	var vertical_breath := 1.0 - breath * 0.025 * breath_strength
	var lifecycle_scale := lerpf(0.18, 1.0, _transition_progress)
	_visual.rotation = _species_rotation()
	_visual.scale = Vector2(
		_ram_scale * horizontal_breath * lifecycle_scale,
		_ram_scale * vertical_breath * lifecycle_scale
	)
	var visual_y := _float_offset
	if not habitat_profile.is_empty() and habitat_kind != HabitatLayout.Kind.AIR:
		var bottom_extent := 0.0
		if visual_renderer == RENDERER_COZY_MYSTIC:
			bottom_extent = SpriteLibrary.support_offset(species, _visual.scale.y)
		else:
			bottom_extent = (
				CreatureVisual.body_bottom_extent(_legacy_species_for(species))
				* _visual.scale.y
			)
		visual_y = -bottom_extent
	_visual.position = Vector2(0.0, visual_y)
	var glow_wave := sin(_breath_phase * _species_glow_frequency())
	var brightness := 0.94 + (glow_wave + 1.0) * _species_glow_strength() + _activity_level * 0.08
	_visual.self_modulate = Color(brightness, brightness, brightness, _transition_progress)
	if _cozy_visual != null:
		_cozy_visual.position = _visual.position
		_cozy_visual.rotation = _visual.rotation
		_cozy_visual.scale = _visual.scale * (CozyMysticVisual.DISPLAY_SIZE / float(SpriteLibrary.FRAME_SIZE))
		_cozy_visual.modulate = Color(brightness, brightness, brightness, _transition_progress)
		_cozy_visual.set_activity(_activity_level)
	_set_selection_visual(is_selected)


func _apply_renderer_visibility() -> void:
	if _visual != null:
		_visual.visible = visual_renderer == RENDERER_LEGACY
	if _cozy_visual != null:
		_cozy_visual.visible = visual_renderer == RENDERER_COZY_MYSTIC
		_cozy_visual.set_playback_active(visual_renderer == RENDERER_COZY_MYSTIC)


func _ensure_cozy_visual() -> bool:
	if _cozy_visual != null:
		return true
	_cozy_visual = CozyVisualScript.new() as CozyMysticVisual
	if _cozy_visual == null:
		return false
	_cozy_visual.name = "CozyVisual"
	add_child(_cozy_visual)
	return true


func _legacy_species_for(value: int) -> int:
	match value:
		SpriteLibrary.Species.BEETLE:
			return CreatureVisual.Species.BEETLE
		SpriteLibrary.Species.SPORE:
			return CreatureVisual.Species.SPORE
		SpriteLibrary.Species.CRYSTAL:
			return CreatureVisual.Species.CRYSTAL
		SpriteLibrary.Species.MOTH:
			return CreatureVisual.Species.WISP
		SpriteLibrary.Species.LARVA:
			return CreatureVisual.Species.BEETLE
	return CreatureVisual.Species.WISP


func _species_breath_strength() -> float:
	match species:
		SpriteLibrary.Species.BEETLE:
			return 0.72
		SpriteLibrary.Species.SPORE:
			return 1.35
		SpriteLibrary.Species.CRYSTAL:
			return 0.48
		SpriteLibrary.Species.MOTH:
			return 0.9
		SpriteLibrary.Species.LARVA:
			return 1.15
	return 0.9


func _species_glow_frequency() -> float:
	return 0.55 if species == SpriteLibrary.Species.CRYSTAL else 1.0


func _species_glow_strength() -> float:
	return 0.055 if species == SpriteLibrary.Species.CRYSTAL else 0.035


func _species_rotation() -> float:
	match species:
		SpriteLibrary.Species.BEETLE:
			return sin(_breath_phase * 2.6) * 0.045 * (0.6 + _activity_level)
		SpriteLibrary.Species.SPORE:
			return sin(_breath_phase * 0.45) * 0.018
		SpriteLibrary.Species.CRYSTAL:
			return sin(_breath_phase * 0.7) * 0.012
		SpriteLibrary.Species.MOTH:
			return sin(_breath_phase * 1.8) * 0.025 * (0.6 + _activity_level)
		SpriteLibrary.Species.LARVA:
			return sin(_breath_phase * 1.3) * 0.02
	return sin(_breath_phase * 0.8) * 0.02


func _set_selection_visual(value: bool) -> void:
	if _visual != null:
		_visual.set_selected(value)
	if _cozy_visual != null:
		_cozy_visual.set_selected(value)
