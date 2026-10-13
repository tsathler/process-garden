extends Control

const ProcessRegistryScript = preload("res://scripts/process_registry.gd")

var _registry: ProcessRegistry
var _garden: GardenController
var _status_label: Label
var _counts_label: Label
var _error_label: Label
var _details_panel: PanelContainer
var _details_name_label: Label
var _details_pid_label: Label
var _details_metrics_label: Label
var _details_state_label: Label
var _refresh_timer: Timer
var _last_monitored_count := 0
var _last_represented_count := 0
var _last_connection_state := ""


func _ready() -> void:
	_registry = ProcessRegistryScript.new()
	_registry.connection_state_changed.connect(_on_connection_state_changed)
	_garden = get_node("Garden") as GardenController
	_garden.representation_changed.connect(_on_representation_changed)
	_garden.selection_changed.connect(_on_selection_changed)
	var client := get_node("SnapshotClient") as SnapshotClient
	client.snapshot_received.connect(_on_snapshot_received)
	client.request_failed.connect(_on_request_failed)
	_build_overlay()
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.25
	_refresh_timer.timeout.connect(_refresh_status)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if route_pointer_click(mouse_event.position):
		get_viewport().set_input_as_handled()


func route_pointer_click(viewport_position: Vector2) -> bool:
	if (
		_details_panel != null
		and _details_panel.visible
		and _details_panel.get_global_rect().has_point(viewport_position)
	):
		return false
	var canvas_to_garden := _garden.get_global_transform_with_canvas().affine_inverse()
	_garden.select_at(canvas_to_garden * viewport_position)
	return true


func _build_overlay() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.02
	panel.anchor_top = 0.025
	panel.anchor_right = 0.98
	panel.offset_bottom = 63.0
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	var identity_column := VBoxContainer.new()
	identity_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_column.add_theme_constant_override("separation", 1)
	row.add_child(identity_column)
	var title := Label.new()
	title.text = "PROCESS GARDEN"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#d5fff4"))
	identity_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "SUBTERRANEAN DIGITAL ECOSYSTEM"
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", Color("#71969c"))
	identity_column.add_child(subtitle)

	var status_column := VBoxContainer.new()
	status_column.alignment = BoxContainer.ALIGNMENT_END
	status_column.add_theme_constant_override("separation", 2)
	row.add_child(status_column)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_font_size_override("font_size", 12)
	status_column.add_child(_status_label)
	_counts_label = Label.new()
	_counts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counts_label.add_theme_font_size_override("font_size", 10)
	_counts_label.add_theme_color_override("font_color", Color("#9bb7b6"))
	status_column.add_child(_counts_label)

	_error_label = Label.new()
	_error_label.anchor_left = 0.02
	_error_label.anchor_top = 0.92
	_error_label.anchor_right = 0.98
	_error_label.anchor_bottom = 0.99
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_label.add_theme_font_size_override("font_size", 9)
	_error_label.add_theme_color_override("font_color", Color("#e7ad8b"))
	add_child(_error_label)
	_build_details_panel()


func _build_details_panel() -> void:
	_details_panel = PanelContainer.new()
	_details_panel.name = "ProcessDetails"
	_details_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_details_panel.anchor_left = 0.67
	_details_panel.anchor_top = 0.66
	_details_panel.anchor_right = 0.98
	_details_panel.anchor_bottom = 0.97
	_details_panel.custom_minimum_size = Vector2(190.0, 104.0)
	_details_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_details_panel.visible = false
	add_child(_details_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	_details_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	column.add_child(title_row)
	_details_name_label = Label.new()
	_details_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_name_label.add_theme_font_size_override("font_size", 13)
	_details_name_label.add_theme_color_override("font_color", Color("#d5fff4"))
	title_row.add_child(_details_name_label)
	var close_button := Button.new()
	close_button.name = "CloseDetails"
	close_button.text = "×"
	close_button.tooltip_text = "Close process details"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(22.0, 20.0)
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.pressed.connect(_on_close_details_pressed)
	title_row.add_child(close_button)

	_details_pid_label = Label.new()
	_details_pid_label.add_theme_font_size_override("font_size", 10)
	_details_pid_label.add_theme_color_override("font_color", Color("#9bb7b6"))
	column.add_child(_details_pid_label)
	_details_metrics_label = Label.new()
	_details_metrics_label.add_theme_font_size_override("font_size", 11)
	_details_metrics_label.add_theme_color_override("font_color", Color("#c6dedd"))
	column.add_child(_details_metrics_label)
	_details_state_label = Label.new()
	_details_state_label.add_theme_font_size_override("font_size", 9)
	_details_state_label.add_theme_color_override("font_color", Color("#7de0bf"))
	column.add_child(_details_state_label)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0b1222e8")
	style.border_color = Color("#2b4e54")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _on_snapshot_received(snapshot: Dictionary) -> void:
	var accepted := _registry.accept_snapshot(
		snapshot, Time.get_unix_time_from_system(), Time.get_ticks_msec()
	)
	if not accepted["accepted"]:
		return
	_garden.reconcile_processes(_registry.get_records())
	_refresh_status()
	_refresh_details()


func _on_request_failed(category: String, detail: String) -> void:
	_registry.note_request_problem("%s: %s" % [category, detail])
	_refresh_status()


func _on_representation_changed(represented_count: int) -> void:
	_last_monitored_count = _registry.get_process_count_in_snapshot()
	_last_represented_count = represented_count
	_refresh_status()


func _on_connection_state_changed(_state: String) -> void:
	_refresh_status()
	_refresh_details()


func _on_selection_changed(_identity: String) -> void:
	_refresh_details()


func _on_close_details_pressed() -> void:
	_garden.clear_selection()


func _refresh_status() -> void:
	var state: Dictionary = _registry.update_connection_state(
		Time.get_unix_time_from_system(), Time.get_ticks_msec()
	)
	var freshness := "waiting for collector"
	if state["has_snapshot"]:
		freshness = "data %.1fs old" % state["age_seconds"]
	var state_color := Color("#7de0bf")
	if state["state"] == ProcessRegistry.STATE_CONNECTING:
		state_color = Color("#a3bac0")
	elif state["state"] == ProcessRegistry.STATE_STALE:
		state_color = Color("#e9be78")
	elif state["state"] == ProcessRegistry.STATE_DISCONNECTED:
		state_color = Color("#df8f9d")
	_status_label.text = "%s  ·  %s" % [str(state["state"]).to_upper(), freshness]
	_status_label.add_theme_color_override("font_color", state_color)
	_counts_label.text = "%d monitored  ·  %d represented" % [
		_last_monitored_count,
		_last_represented_count,
	]
	_error_label.text = _registry.get_last_problem()
	if _last_connection_state != str(state["state"]):
		_last_connection_state = str(state["state"])
		_refresh_details()


func _refresh_details() -> void:
	if _details_panel == null:
		return
	var creature := _garden.get_selected_creature()
	if creature == null:
		_details_panel.visible = false
		return
	_details_panel.visible = true
	var process_name := creature.process_name
	if process_name.length() > 26:
		process_name = process_name.left(23) + "…"
	_set_label_text(_details_name_label, process_name)
	_set_label_text(_details_pid_label, "PID %d" % creature.process_pid)
	var cpu_text := "—"
	if creature.cpu_percent != null:
		cpu_text = "%.1f%%" % float(creature.cpu_percent)
	var memory_mib := float(creature.memory_rss_bytes) / 1_048_576.0
	_set_label_text(_details_metrics_label, "CPU %s   ·   RAM %.1f MiB" % [cpu_text, memory_mib])

	var state_text := "LIVE · latest accepted metrics"
	var state_color := Color("#7de0bf")
	if creature.state == ProcessCreature.State.DESPAWNING:
		state_text = "LEAVING GARDEN · last known metrics"
		state_color = Color("#e9be78")
	elif _registry.connection_state == ProcessRegistry.STATE_STALE:
		state_text = "STALE · last valid metrics"
		state_color = Color("#e9be78")
	elif _registry.connection_state == ProcessRegistry.STATE_DISCONNECTED:
		state_text = "OFFLINE · last valid metrics"
		state_color = Color("#df8f9d")
	elif _registry.connection_state == ProcessRegistry.STATE_CONNECTING:
		state_text = "WAITING FOR COLLECTOR"
		state_color = Color("#a3bac0")
	_set_label_text(_details_state_label, state_text)
	_details_state_label.add_theme_color_override("font_color", state_color)


func _set_label_text(label: Label, value: String) -> void:
	if label.text != value:
		label.text = value
