extends Node2D
class_name GardenController

const CreatureScene: PackedScene = preload("res://scenes/creature.tscn")
const SelectorScript = preload("res://scripts/process_selector.gd")
const MAX_VISIBLE_CREATURES := SelectorScript.MAX_VISIBLE_CREATURES
const SnapshotParserScript = preload("res://scripts/snapshot_parser.gd")
const SpriteLibrary = preload("res://scripts/cozy_mystic_sprite_library.gd")
const HabitatLayoutScript = preload("res://scripts/habitat_layout.gd")
const DEFAULT_FIELD := Rect2(Vector2(20.0, 88.0), Vector2(600.0, 224.0))

signal representation_changed(represented_count: int)
signal selection_changed(identity: String)

@export_range(0, MAX_VISIBLE_CREATURES, 1) var creature_limit := MAX_VISIBLE_CREATURES
@export var field_rect := DEFAULT_FIELD
@export var show_composition_debug := false

var _selector: ProcessSelector
var _creature_layer: Node2D
var _creatures: Dictionary = {}
var _latest_processes: Array[Dictionary] = []
var _separation_creatures: Array[ProcessCreature] = []
var _separation_forces: Array[Vector2] = []
var _separation_radii: Array[float] = []
var _selected_identity := ""
var _is_reconciling := false
var profiling_enabled := false
var _last_profile_usec: Dictionary = {}
var visual_renderer := ProcessCreature.RENDERER_LEGACY


func _ready() -> void:
	_selector = SelectorScript.new()
	_creature_layer = get_node("Creatures") as Node2D
	_creature_layer.y_sort_enabled = true


func _process(delta: float) -> void:
	update_separation(delta)
	if show_composition_debug:
		queue_redraw()


func _draw() -> void:
	if not show_composition_debug:
		return
	var occupants: Array[Dictionary] = []
	for creature_value in _creatures.values():
		var creature := creature_value as ProcessCreature
		if creature.state != ProcessCreature.State.DESPAWNING:
			occupants.append(creature.get_layout_occupant())
	for index in range(occupants.size()):
		var bounds: Rect2 = occupants[index]["bounds"]
		var overlaps := false
		for other_index in range(index):
			var previous_bounds: Rect2 = occupants[other_index]["bounds"]
			if bounds.intersects(previous_bounds):
				overlaps = true
				draw_rect(previous_bounds, Color("#e28c9c"), false, 1.0)
		draw_rect(bounds, Color("#e28c9c") if overlaps else Color("#76e1d3"), false, 1.0)


func reconcile_processes(processes: Array[Dictionary]) -> void:
	if profiling_enabled:
		_last_profile_usec.clear()
	var copy_start_usec := Time.get_ticks_usec() if profiling_enabled else 0
	_latest_processes.clear()
	for process in processes:
		_latest_processes.append(process.duplicate(true))
	if profiling_enabled:
		_last_profile_usec["process_copy_usec"] = Time.get_ticks_usec() - copy_start_usec
	_reconcile_latest()


func get_creature_count() -> int:
	# Includes despawning nodes so transitions cannot push the live node count over the cap.
	return _creatures.size()


func get_creature_identities() -> Array[String]:
	var identities: Array[String] = []
	for identity in _creatures:
		identities.append(str(identity))
	identities.sort()
	return identities


func get_creature(identity: String) -> ProcessCreature:
	return _creatures.get(identity) as ProcessCreature


func get_selected_identity() -> String:
	return _selected_identity


func get_selected_creature() -> ProcessCreature:
	return get_creature(_selected_identity) if not _selected_identity.is_empty() else null


func get_last_profile_usec() -> Dictionary:
	return _last_profile_usec.duplicate()


func get_composition_metrics() -> Dictionary:
	var occupants: Array[Dictionary] = []
	for creature_value in _creatures.values():
		var creature := creature_value as ProcessCreature
		if creature.state == ProcessCreature.State.DESPAWNING and creature.get_lifecycle_progress() <= 0.05:
			continue
		occupants.append(creature.get_layout_occupant())
	var interface_regions: Array[Rect2] = [
		Rect2(0.0, 0.0, 640.0, 82.0),
		Rect2(403.0, 234.0, 224.0, 115.0),
	]
	return HabitatLayoutScript.analyze_composition(occupants, interface_regions)


func get_visual_renderer() -> String:
	return visual_renderer


func set_visual_renderer(mode: String) -> bool:
	if mode != ProcessCreature.RENDERER_LEGACY and mode != ProcessCreature.RENDERER_COZY_MYSTIC and mode != ProcessCreature.RENDERER_SYNTHETIC_LIFE:
		return false
	if mode == ProcessCreature.RENDERER_COZY_MYSTIC and not SpriteLibrary.load_all():
		push_error("Cozy Mystic sprite resources failed validation; LEGACY remains active")
		return false
	if mode == ProcessCreature.RENDERER_SYNTHETIC_LIFE:
		var synthetic_script := load("res://scripts/synthetic_life_visual.gd")
		if synthetic_script == null:
			push_error("Synthetic Life renderer script is unavailable; current renderer remains active")
			return false
	visual_renderer = mode
	for creature_value in _creatures.values():
		var creature := creature_value as ProcessCreature
		if not creature.set_visual_renderer(mode):
			visual_renderer = ProcessCreature.RENDERER_LEGACY
			for rollback_value in _creatures.values():
				(rollback_value as ProcessCreature).set_visual_renderer(visual_renderer)
			return false
	return true


func clear_for_source_change() -> void:
	_latest_processes.clear()
	_is_reconciling = false
	_set_selected_identity("")
	for identity in _creatures.keys():
		var creature := _creatures[identity] as ProcessCreature
		if creature.despawn_finished.is_connected(_on_creature_despawn_finished):
			creature.despawn_finished.disconnect(_on_creature_despawn_finished)
		if creature.get_parent() != null:
			creature.get_parent().remove_child(creature)
		creature.queue_free()
	_creatures.clear()
	representation_changed.emit(0)


func select_at(local_position: Vector2) -> String:
	var global_point := to_global(local_position)
	var best: ProcessCreature
	var best_y := -INF
	var best_z := -INF
	var best_order := -1
	for child in _creature_layer.get_children():
		var creature := child as ProcessCreature
		if creature == null or creature.state == ProcessCreature.State.DESPAWNING:
			continue
		if not creature.contains_local_point(creature.to_local(global_point)):
			continue
		var order := creature.get_index()
		if (
			creature.z_index > best_z
			or (
				creature.z_index == best_z
				and (
					creature.position.y > best_y
					or (is_equal_approx(creature.position.y, best_y) and order > best_order)
				)
			)
		):
			best = creature
			best_y = creature.position.y
			best_z = creature.z_index
			best_order = order
	_set_selected_identity(best.process_identity if best != null else "")
	return _selected_identity


func clear_selection() -> void:
	_set_selected_identity("")


func update_separation(_delta: float = 0.0) -> void:
	_separation_creatures.clear()
	_separation_forces.clear()
	_separation_radii.clear()
	for identity in _creatures:
		var creature := _creatures[identity] as ProcessCreature
		if creature.state == ProcessCreature.State.DESPAWNING:
			continue
		_separation_creatures.append(creature)
		_separation_forces.append(Vector2.ZERO)
		_separation_radii.append(creature.get_separation_radius())

	for first_index in range(_separation_creatures.size()):
		var first := _separation_creatures[first_index]
		for second_index in range(first_index + 1, _separation_creatures.size()):
			var second := _separation_creatures[second_index]
			var offset := first.get_visual_center_position() - second.get_visual_center_position()
			var distance_squared := offset.length_squared()
			var separation_distance := clampf(
				_separation_radii[first_index] + _separation_radii[second_index] + 6.0,
				24.0,
				52.0
			)
			if distance_squared >= separation_distance * separation_distance:
				continue
			var distance := sqrt(distance_squared)
			var direction := (
				offset / distance
				if distance > 0.001
				else _coincident_pair_direction(first, second)
			)
			var strength := clampf((separation_distance - distance) / separation_distance, 0.0, 1.0)
			_separation_forces[first_index] += direction * strength
			_separation_forces[second_index] -= direction * strength

	for index in range(_separation_creatures.size()):
		_separation_creatures[index].set_separation_force(_separation_forces[index])


func _set_selected_identity(identity: String) -> void:
	if _selected_identity == identity:
		return
	var previous := get_creature(_selected_identity)
	if previous != null:
		previous.set_selected(false)
	_selected_identity = identity
	var current := get_creature(_selected_identity)
	if current != null:
		current.set_selected(true)
	selection_changed.emit(_selected_identity)


func _coincident_pair_direction(first: ProcessCreature, second: ProcessCreature) -> Vector2:
	var first_is_lower := first.process_identity < second.process_identity
	var lower_identity := first.process_identity if first_is_lower else second.process_identity
	var upper_identity := second.process_identity if first_is_lower else first.process_identity
	var pair_hash := posmod(hash(lower_identity + ":" + upper_identity), 4096)
	var angle := float(pair_hash) / 4096.0 * TAU
	var direction := Vector2(cos(angle), sin(angle))
	return direction if first_is_lower else -direction


func _reconcile_latest() -> void:
	if _is_reconciling or _selector == null or _creature_layer == null:
		return
	_is_reconciling = true
	var selected_identities := _creatures.keys()
	var selector_start_usec := Time.get_ticks_usec() if profiling_enabled else 0
	var visible_limit := mini(maxi(creature_limit, 0), MAX_VISIBLE_CREATURES)
	var selected := _selector.select_processes(
		_latest_processes, selected_identities, visible_limit
	)
	if profiling_enabled:
		_last_profile_usec["selector_usec"] = Time.get_ticks_usec() - selector_start_usec
	var creature_reconcile_start_usec := Time.get_ticks_usec() if profiling_enabled else 0
	var desired: Dictionary = {}
	for process in selected:
		var identity := SnapshotParserScript.identity_key(process)
		desired[identity] = process

	for identity in _creatures.keys():
		var creature := _creatures[identity] as ProcessCreature
		if desired.has(identity):
			if creature.state == ProcessCreature.State.DESPAWNING:
				creature.cancel_despawn()
			creature.set_process_record(desired[identity], identity)
		else:
			creature.begin_despawn()

	var occupied: Array[Dictionary] = []
	for creature_value in _creatures.values():
		var existing_creature := creature_value as ProcessCreature
		occupied.append(existing_creature.get_layout_occupant())
	var identities: Array[String] = []
	for identity in desired:
		identities.append(str(identity))
	identities.sort()
	for identity in identities:
		if _creatures.has(identity) or _creatures.size() >= visible_limit:
			continue
		var process: Dictionary = desired[identity]
		var species := SpriteLibrary.species_for_identity(identity)
		var memory_bytes := maxi(int(process.get("memory_rss_bytes", 0)), 0)
		var visual_scale: float = ProcessCreature.scale_for_memory_bytes(memory_bytes)
		var placement := HabitatLayoutScript.choose_placement_with_envelopes(
			identity, species, occupied, visual_scale
		)
		if placement.is_empty():
			push_error("No compatible habitat placement for process identity %s" % identity)
			continue
		var creature := CreatureScene.instantiate() as ProcessCreature
		creature.set_movement_bounds(field_rect)
		creature.despawn_finished.connect(_on_creature_despawn_finished)
		_creature_layer.add_child(creature)
		_creatures[identity] = creature
		creature.set_process_record(process, identity)
		creature.configure_habitat(placement["profile"], placement["position"])
		if not creature.set_visual_renderer(visual_renderer):
			visual_renderer = ProcessCreature.RENDERER_LEGACY
			for existing_value in _creatures.values():
				(existing_value as ProcessCreature).set_visual_renderer(visual_renderer)
		occupied.append(creature.get_layout_occupant())

	if profiling_enabled:
		_last_profile_usec["creature_reconcile_usec"] = (
			Time.get_ticks_usec() - creature_reconcile_start_usec
		)
	_is_reconciling = false
	representation_changed.emit(_creatures.size())


func _on_creature_despawn_finished(identity: String, creature: ProcessCreature) -> void:
	if not _creatures.has(identity) or _creatures[identity] != creature:
		return
	if creature.state != ProcessCreature.State.DESPAWNING:
		return
	_creatures.erase(identity)
	if _selected_identity == identity:
		_set_selected_identity("")
	if creature.get_parent() != null:
		creature.get_parent().remove_child(creature)
	creature.queue_free()
	_reconcile_latest()
