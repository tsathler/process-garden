extends Node2D
class_name GardenController

const CreatureScene: PackedScene = preload("res://scenes/creature.tscn")
const SelectorScript = preload("res://scripts/process_selector.gd")
const SnapshotParserScript = preload("res://scripts/snapshot_parser.gd")
const DEFAULT_FIELD := Rect2(Vector2(20.0, 88.0), Vector2(600.0, 224.0))
const MIN_CREATURE_SPACING := 23.0
const POSITION_ATTEMPTS := 32

signal representation_changed(represented_count: int)
signal selection_changed(identity: String)

@export_range(0, 60, 1) var creature_limit := 60
@export var field_rect := DEFAULT_FIELD

var _selector: ProcessSelector
var _creature_layer: Node2D
var _creatures: Dictionary = {}
var _latest_processes: Array[Dictionary] = []
var _separation_creatures: Array[ProcessCreature] = []
var _separation_forces: Array[Vector2] = []
var _selected_identity := ""
var _is_reconciling := false


func _ready() -> void:
	_selector = SelectorScript.new()
	_creature_layer = get_node("Creatures") as Node2D
	_creature_layer.y_sort_enabled = true


func _process(delta: float) -> void:
	update_separation(delta)


func reconcile_processes(processes: Array[Dictionary]) -> void:
	_latest_processes.clear()
	for process in processes:
		_latest_processes.append(process.duplicate(true))
	_reconcile_latest()


func get_creature_count() -> int:
	# Includes despawning nodes so transitions cannot push the live node count over 60.
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
	for identity in _creatures:
		var creature := _creatures[identity] as ProcessCreature
		if creature.state == ProcessCreature.State.DESPAWNING:
			continue
		_separation_creatures.append(creature)
		_separation_forces.append(Vector2.ZERO)

	for first_index in range(_separation_creatures.size()):
		var first := _separation_creatures[first_index]
		for second_index in range(first_index + 1, _separation_creatures.size()):
			var second := _separation_creatures[second_index]
			var offset := first.get_visual_center_position() - second.get_visual_center_position()
			var distance_squared := offset.length_squared()
			var separation_distance := clampf(
				(first.get_separation_radius() + second.get_separation_radius()) * 0.9,
				20.0,
				34.0
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
	var selected := _selector.select_processes(
		_latest_processes, selected_identities, mini(creature_limit, 60)
	)
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

	var occupied_positions: Array[Vector2] = []
	for creature_value in _creatures.values():
		occupied_positions.append((creature_value as ProcessCreature).position)
	var identities: Array[String] = []
	for identity in desired:
		identities.append(str(identity))
	identities.sort()
	for identity in identities:
		if _creatures.has(identity) or _creatures.size() >= mini(creature_limit, 60):
			continue
		var process: Dictionary = desired[identity]
		var creature := CreatureScene.instantiate() as ProcessCreature
		creature.set_movement_bounds(field_rect)
		creature.position = _choose_position(identity, occupied_positions, creature)
		creature.despawn_finished.connect(_on_creature_despawn_finished)
		_creature_layer.add_child(creature)
		_creatures[identity] = creature
		creature.set_process_record(process, identity)
		occupied_positions.append(creature.position)

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


func _choose_position(
	identity: String, occupied: Array[Vector2], creature: ProcessCreature
) -> Vector2:
	var random := RandomNumberGenerator.new()
	random.seed = posmod(hash(identity), 2_147_483_647) + 1
	var bounds := creature.get_effective_movement_bounds()
	var best_position := bounds.get_center()
	var best_clearance := -1.0
	for _attempt in range(POSITION_ATTEMPTS):
		var candidate := Vector2(
			random.randf_range(bounds.position.x, bounds.end.x),
			random.randf_range(bounds.position.y, bounds.end.y)
		)
		var clearance := _nearest_distance(candidate, occupied)
		if clearance >= MIN_CREATURE_SPACING:
			return candidate
		if clearance > best_clearance:
			best_clearance = clearance
			best_position = candidate
	return best_position


func _nearest_distance(candidate: Vector2, occupied: Array[Vector2]) -> float:
	if occupied.is_empty():
		return INF
	var nearest := INF
	for position in occupied:
		nearest = minf(nearest, candidate.distance_to(position))
	return nearest
