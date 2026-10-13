extends Node2D
class_name ProcessCreature

enum State { SPAWNING, IDLE, WANDERING, ACTIVE, DESPAWNING }

signal despawn_finished(identity: String, creature: ProcessCreature)

const BODY_PALETTE := [
	Color("#55d5c2"),
	Color("#60a8df"),
	Color("#9b88d8"),
	Color("#54c99a"),
]
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
var state := State.SPAWNING
var movement_bounds := Rect2(Vector2(20.0, 88.0), Vector2(600.0, 224.0))
var is_selected := false

var _body_color := BODY_PALETTE[0]
var _visual: CreatureVisual
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
	_refresh_visuals()


func _process(delta: float) -> void:
	advance_simulation(delta)


func set_movement_bounds(bounds: Rect2) -> void:
	movement_bounds = bounds
	position = _clamp_position(position)
	_target_position = _clamp_position(_target_position)


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	if _visual != null:
		_visual.set_selected(value)


func set_separation_force(force: Vector2) -> void:
	if not is_finite(force.x) or not is_finite(force.y):
		_separation_target = Vector2.ZERO
		return
	_separation_target = force.limit_length(1.0)


func get_separation_force() -> Vector2:
	return _separation_target


func get_visual_center_position() -> Vector2:
	return position + Vector2(0.0, _float_offset)


func get_separation_radius() -> float:
	if _visual == null:
		return 14.0 * _ram_scale
	return maxf(12.0 * _visual.scale.x, 14.0 * _visual.scale.y)


func get_float_offset() -> float:
	return _float_offset


func get_territory_center() -> Vector2:
	return _territory_center


func get_territory_radius() -> float:
	return _territory_radius


func contains_local_point(local_point: Vector2) -> bool:
	if state == State.DESPAWNING or _visual == null:
		return false
	var body_point := _visual.transform.affine_inverse() * local_point
	var normalized := Vector2(body_point.x / 12.0, body_point.y / 14.0)
	return normalized.length_squared() <= 1.0


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
	_body_color = BODY_PALETTE[posmod(hash(identity), BODY_PALETTE.size())]
	if _visual != null:
		_visual.set_body_color(_body_color)


func advance_simulation(delta: float) -> void:
	if process_identity.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	_breath_phase = fposmod(_breath_phase + delta * _breath_frequency, TAU)
	_float_phase = fposmod(_float_phase + delta * _float_frequency, TAU)
	_float_offset = sin(_float_phase) * 1.8
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


func get_activity_level() -> float:
	return _activity_level


func get_ram_scale() -> float:
	return _ram_scale


func get_effective_movement_bounds() -> Rect2:
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
	_base_speed = _random.randf_range(8.0, 13.0)
	_pause_min = _random.randf_range(0.65, 1.0)
	_pause_max = _pause_min + _random.randf_range(0.65, 1.2)
	_wander_distance = _random.randf_range(22.0, 42.0)
	_territory_radius = _random.randf_range(20.0, 45.0)
	_breath_frequency = _random.randf_range(1.65, 2.45)
	_breath_phase = _random.randf_range(0.0, TAU)
	_float_frequency = _random.randf_range(0.75, 1.45)
	_float_phase = _random.randf_range(0.0, TAU)
	_float_offset = sin(_float_phase) * 1.8
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
			if _move_toward_destination(delta, 1.0 + _activity_level * 0.65):
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
		if _move_toward_destination(delta, 1.0):
			state = State.IDLE
			_is_moving = false
			_pause_remaining = _next_pause()


func _apply_separation(delta: float) -> void:
	if _separation_level.length_squared() <= 0.0001:
		return
	var displacement := _separation_level.limit_length(1.0) * (12.0 * delta)
	position = _clamp_position(position + displacement)


func _move_toward_destination(delta: float, speed_factor: float) -> bool:
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
	return _random.randf_range(_pause_min, _pause_max) * activity_shortening


func _clamp_position(value: Vector2) -> Vector2:
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
	var memory_mib := maxf(float(memory_bytes) / 1_048_576.0, 0.0)
	var normalized := log(1.0 + memory_mib / 16.0) / log(1.0 + 2048.0 / 16.0)
	return lerpf(MIN_RAM_SCALE, MAX_RAM_SCALE, clampf(normalized, 0.0, 1.0))


func _refresh_visuals() -> void:
	if _visual == null:
		return
	var breath := sin(_breath_phase)
	var horizontal_breath := 1.0 + breath * 0.018
	var vertical_breath := 1.0 - breath * 0.025
	var lifecycle_scale := lerpf(0.18, 1.0, _transition_progress)
	_visual.position = Vector2(0.0, _float_offset)
	_visual.scale = Vector2(
		_ram_scale * horizontal_breath * lifecycle_scale,
		_ram_scale * vertical_breath * lifecycle_scale
	)
	var brightness := 0.94 + (breath + 1.0) * 0.035 + _activity_level * 0.08
	_visual.self_modulate = Color(brightness, brightness, brightness, _transition_progress)
	_set_selection_visual(is_selected)


func _set_selection_visual(value: bool) -> void:
	if _visual != null:
		_visual.set_selected(value)
