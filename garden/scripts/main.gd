extends Control

const ProcessRegistryScript = preload("res://scripts/process_registry.gd")
const DemoSnapshotSourceScript = preload("res://scripts/demo_snapshot_source.gd")

const SOURCE_REAL := "REAL"
const SOURCE_DEMO := "DEMO"
const COLOR_TEXT := Color("#f2f7fd")
const COLOR_MUTED := Color("#91acc2")
const COLOR_ACCENT := Color("#76e1d3")
const COLOR_CONNECTED := Color("#91e9c7")
const COLOR_STALE := Color("#e8c773")
const COLOR_DISCONNECTED := Color("#e28c9c")
const COLOR_WAITING := Color("#a9bfd0")

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
var _empty_state_label: Label
var _refresh_timer: Timer
var _source_mode_option: OptionButton
var _renderer_mode_option: OptionButton
var _demo_controls: HBoxContainer
var _demo_scenario_option: OptionButton
var _demo_seed_input: SpinBox
var _demo_source: DemoSnapshotSource
var _source_mode := SOURCE_REAL
var _demo_population := 150
var _demo_seed := 2025
var _last_monitored_count := 0
var _last_represented_count := 0
var _last_connection_state := ""
var _renderer_error := ""


func _ready() -> void:
	_registry = _new_registry()
	_garden = get_node("Garden") as GardenController
	_garden.representation_changed.connect(_on_representation_changed)
	_garden.selection_changed.connect(_on_selection_changed)
	var client := get_node("SnapshotClient") as SnapshotClient
	client.snapshot_received.connect(_on_snapshot_received)
	client.request_failed.connect(_on_request_failed)
	_build_overlay()
	_renderer_mode_option.select(
		1 if _garden.get_visual_renderer() == ProcessCreature.RENDERER_COZY_MYSTIC else 0
	)
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.25
	_refresh_timer.timeout.connect(_refresh_status)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_refresh_status()


func _new_registry() -> ProcessRegistry:
	var registry := ProcessRegistryScript.new() as ProcessRegistry
	registry.connection_state_changed.connect(_on_connection_state_changed)
	return registry


func set_source_mode(mode: String) -> bool:
	if mode != SOURCE_REAL and mode != SOURCE_DEMO:
		return false
	if mode == _source_mode:
		return true
	var client := get_node("SnapshotClient") as SnapshotClient
	client.set_polling_enabled(false)
	if _demo_source != null:
		_demo_source.stop()
	_reset_source_state()
	_source_mode = mode
	_source_mode_option.select(0 if mode == SOURCE_REAL else 1)
	_demo_controls.visible = mode == SOURCE_DEMO
	if mode == SOURCE_DEMO:
		_start_demo_source()
	else:
		client.set_polling_enabled(true)
	_refresh_status()
	_refresh_details()
	return true


func _reset_source_state() -> void:
	_registry = _new_registry()
	_last_monitored_count = 0
	_last_represented_count = 0
	_garden.clear_for_source_change()


func _start_demo_source() -> void:
	if _demo_source == null:
		_demo_source = DemoSnapshotSourceScript.new() as DemoSnapshotSource
		_demo_source.name = "DemoSnapshotSource"
		_demo_source.snapshot_generated.connect(_on_snapshot_received)
		add_child(_demo_source)
	_demo_source.configure(_demo_population, _demo_seed)
	_demo_source.start()


func _restart_demo_source() -> void:
	if _source_mode != SOURCE_DEMO or _demo_source == null:
		return
	_demo_source.stop()
	_reset_source_state()
	_demo_source.configure(_demo_population, _demo_seed)
	_demo_source.start()


func _on_source_mode_selected(index: int) -> void:
	set_source_mode(SOURCE_DEMO if _source_mode_option.get_item_id(index) == 1 else SOURCE_REAL)


func _on_renderer_mode_selected(index: int) -> void:
	var mode := (
		ProcessCreature.RENDERER_COZY_MYSTIC
		if _renderer_mode_option.get_item_id(index) == 1
		else ProcessCreature.RENDERER_LEGACY
	)
	if not _garden.set_visual_renderer(mode):
		_renderer_error = "Cozy Mystic assets unavailable · LEGACY renderer retained"
		_renderer_mode_option.select(0)
	else:
		_renderer_error = ""
	_refresh_status()


func _on_demo_scenario_selected(index: int) -> void:
	_demo_population = _demo_scenario_option.get_item_id(index)
	_restart_demo_source()


func _on_demo_seed_changed(value: float) -> void:
	_demo_seed = int(value)
	_restart_demo_source()


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
	panel.name = "ObservatoryHeader"
	panel.anchor_left = 0.02
	panel.anchor_top = 0.025
	panel.anchor_right = 0.98
	panel.offset_bottom = 82.0
	panel.add_theme_stylebox_override("panel", _make_panel_style(false))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 13)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var identity_column := VBoxContainer.new()
	identity_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_column.add_theme_constant_override("separation", 1)
	row.add_child(identity_column)
	var title := Label.new()
	title.text = "PROCESS GARDEN"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	identity_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "LIVING SYSTEM  ·  FIELD OBSERVATORY"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	identity_column.add_child(subtitle)

	var status_column := VBoxContainer.new()
	status_column.alignment = BoxContainer.ALIGNMENT_END
	status_column.add_theme_constant_override("separation", 2)
	row.add_child(status_column)
	var connection_row := HBoxContainer.new()
	connection_row.add_theme_constant_override("separation", 5)
	status_column.add_child(connection_row)
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_font_size_override("font_size", 11)
	connection_row.add_child(_status_label)
	_source_mode_option = OptionButton.new()
	_source_mode_option.name = "SourceMode"
	_source_mode_option.add_item("REAL", 0)
	_source_mode_option.add_item("DEMO", 1)
	_source_mode_option.select(0)
	_source_mode_option.custom_minimum_size = Vector2(72.0, 24.0)
	_source_mode_option.tooltip_text = "Choose live Windows processes or simulated demo data"
	_style_control(_source_mode_option, true)
	_source_mode_option.item_selected.connect(_on_source_mode_selected)
	connection_row.add_child(_source_mode_option)
	_renderer_mode_option = OptionButton.new()
	_renderer_mode_option.name = "VisualRenderer"
	_renderer_mode_option.add_item("LEGACY", 0)
	_renderer_mode_option.add_item("COZY", 1)
	_renderer_mode_option.select(0)
	_renderer_mode_option.custom_minimum_size = Vector2(76.0, 24.0)
	_renderer_mode_option.tooltip_text = "Compare the legacy visual with Cozy Mystic sprites"
	_style_control(_renderer_mode_option, true)
	_renderer_mode_option.item_selected.connect(_on_renderer_mode_selected)
	connection_row.add_child(_renderer_mode_option)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 5)
	status_column.add_child(info_row)
	_counts_label = Label.new()
	_counts_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counts_label.add_theme_font_size_override("font_size", 10)
	_counts_label.add_theme_color_override("font_color", COLOR_MUTED)
	info_row.add_child(_counts_label)
	_demo_controls = HBoxContainer.new()
	_demo_controls.name = "DemoSettings"
	_demo_controls.add_theme_constant_override("separation", 3)
	_demo_controls.visible = false
	info_row.add_child(_demo_controls)
	_demo_scenario_option = OptionButton.new()
	_demo_scenario_option.name = "DemoScenario"
	_demo_scenario_option.add_item("50", 50)
	_demo_scenario_option.add_item("150", 150)
	_demo_scenario_option.add_item("300", 300)
	_demo_scenario_option.add_item("500", 500)
	_demo_scenario_option.select(1)
	_demo_scenario_option.custom_minimum_size = Vector2(68.0, 22.0)
	_demo_scenario_option.tooltip_text = "Number of simulated processes"
	_style_control(_demo_scenario_option, true)
	_demo_scenario_option.item_selected.connect(_on_demo_scenario_selected)
	_demo_controls.add_child(_demo_scenario_option)
	var seed_label := Label.new()
	seed_label.text = "SEED"
	seed_label.add_theme_font_size_override("font_size", 9)
	seed_label.add_theme_color_override("font_color", COLOR_MUTED)
	_demo_controls.add_child(seed_label)
	_demo_seed_input = SpinBox.new()
	_demo_seed_input.name = "DemoSeed"
	_demo_seed_input.min_value = 0.0
	_demo_seed_input.max_value = 2_147_483_647.0
	_demo_seed_input.step = 1.0
	_demo_seed_input.value = _demo_seed
	_demo_seed_input.custom_minimum_size = Vector2(76.0, 22.0)
	_demo_seed_input.tooltip_text = "Repeat a demo scenario with the same seed"
	_style_control(_demo_seed_input, false)
	_demo_seed_input.value_changed.connect(_on_demo_seed_changed)
	_demo_controls.add_child(_demo_seed_input)

	_error_label = Label.new()
	_error_label.anchor_left = 0.02
	_error_label.anchor_top = 0.92
	_error_label.anchor_right = 0.98
	_error_label.anchor_bottom = 0.99
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_error_label.add_theme_font_size_override("font_size", 10)
	_error_label.add_theme_color_override("font_color", COLOR_STALE)
	add_child(_error_label)
	_empty_state_label = Label.new()
	_empty_state_label.name = "GardenEmptyState"
	_empty_state_label.anchor_left = 0.18
	_empty_state_label.anchor_top = 0.45
	_empty_state_label.anchor_right = 0.82
	_empty_state_label.anchor_bottom = 0.55
	_empty_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_state_label.add_theme_font_size_override("font_size", 12)
	_empty_state_label.add_theme_color_override("font_color", COLOR_MUTED)
	_empty_state_label.visible = false
	add_child(_empty_state_label)
	_build_details_panel()


func _build_details_panel() -> void:
	_details_panel = PanelContainer.new()
	_details_panel.name = "ProcessDetails"
	_details_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_details_panel.anchor_left = 0.63
	_details_panel.anchor_top = 0.65
	_details_panel.anchor_right = 0.98
	_details_panel.anchor_bottom = 0.97
	_details_panel.custom_minimum_size = Vector2(218.0, 118.0)
	_details_panel.add_theme_stylebox_override("panel", _make_panel_style(true))
	_details_panel.visible = false
	add_child(_details_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 11)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_bottom", 8)
	_details_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 4)
	column.add_child(title_row)
	_details_name_label = Label.new()
	_details_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_name_label.add_theme_font_size_override("font_size", 14)
	_details_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_details_name_label.clip_text = true
	title_row.add_child(_details_name_label)
	var close_button := Button.new()
	close_button.name = "CloseDetails"
	close_button.text = "×"
	close_button.tooltip_text = "Close process details"
	close_button.focus_mode = Control.FOCUS_ALL
	close_button.custom_minimum_size = Vector2(22.0, 20.0)
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.add_theme_color_override("font_color", COLOR_MUTED)
	close_button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	_style_control(close_button, true)
	close_button.pressed.connect(_on_close_details_pressed)
	title_row.add_child(close_button)

	_details_pid_label = Label.new()
	_details_pid_label.add_theme_font_size_override("font_size", 10)
	_details_pid_label.add_theme_color_override("font_color", COLOR_ACCENT)
	column.add_child(_details_pid_label)
	_details_metrics_label = Label.new()
	_details_metrics_label.add_theme_font_size_override("font_size", 11)
	_details_metrics_label.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(_details_metrics_label)
	_details_state_label = Label.new()
	_details_state_label.add_theme_font_size_override("font_size", 9)
	_details_state_label.add_theme_color_override("font_color", COLOR_CONNECTED)
	column.add_child(_details_state_label)


func _make_panel_style(elevated: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111b2ef2") if elevated else Color("#0b1020e8")
	style.border_color = Color("#34516a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


func _style_control(control: Control, button_like: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#172740")
	normal.border_color = Color("#34516a")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color("#203752")
	hover.border_color = COLOR_ACCENT
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(2)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color("#263f58")
	pressed.border_color = COLOR_CONNECTED
	pressed.set_border_width_all(1)
	pressed.set_corner_radius_all(2)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color("#172740")
	focus.border_color = COLOR_ACCENT
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(2)
	control.add_theme_stylebox_override("normal", normal)
	control.add_theme_stylebox_override("hover", hover)
	control.add_theme_stylebox_override("pressed", pressed)
	control.add_theme_stylebox_override("focus", focus)
	control.add_theme_color_override("font_color", COLOR_TEXT)
	control.add_theme_color_override("font_hover_color", COLOR_TEXT)
	control.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	if not button_like:
		control.add_theme_color_override("font_placeholder_color", COLOR_MUTED)


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
	if _source_mode == SOURCE_DEMO:
		_status_label.text = "DEMO · SIMULATED"
		_set_label_color(_status_label, COLOR_CONNECTED)
		_counts_label.text = "%d simulated · %d represented" % [
			_last_monitored_count,
			_last_represented_count,
		]
		_error_label.text = _renderer_error
		_refresh_empty_state(ProcessRegistry.STATE_CONNECTED)
		return
	var freshness := "waiting for collector"
	if state["has_snapshot"]:
		freshness = "data %.1fs old" % state["age_seconds"]
	var state_color := COLOR_CONNECTED
	if state["state"] == ProcessRegistry.STATE_CONNECTING:
		state_color = COLOR_WAITING
	elif state["state"] == ProcessRegistry.STATE_STALE:
		state_color = COLOR_STALE
	elif state["state"] == ProcessRegistry.STATE_DISCONNECTED:
		state_color = COLOR_DISCONNECTED
	_status_label.text = "%s  ·  %s" % [str(state["state"]).to_upper(), freshness]
	_set_label_color(_status_label, state_color)
	_counts_label.text = "%d monitored  ·  %d represented" % [
		_last_monitored_count,
		_last_represented_count,
	]
	_error_label.text = (
		_renderer_error if not _renderer_error.is_empty() else _connection_message(str(state["state"]))
	)
	_set_label_color(_error_label, state_color)
	_refresh_empty_state(str(state["state"]))
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
	_details_name_label.tooltip_text = creature.process_name
	_set_label_text(
		_details_pid_label,
		"%s  ·  PID %d" % [creature.get_species_name(), creature.process_pid]
	)
	var cpu_text := "—"
	if creature.cpu_percent != null:
		cpu_text = "%.1f%%" % float(creature.cpu_percent)
	var memory_mib := float(creature.memory_rss_bytes) / 1_048_576.0
	_set_label_text(_details_metrics_label, "CPU %s   ·   RAM %.1f MiB" % [cpu_text, memory_mib])

	var state_text := "LIVE · latest accepted metrics"
	var state_color := COLOR_CONNECTED
	if _source_mode == SOURCE_DEMO:
		state_text = "DEMO · SIMULATED METRICS"
		state_color = COLOR_CONNECTED
	elif creature.state == ProcessCreature.State.DESPAWNING:
		state_text = "LEAVING · LAST KNOWN METRICS"
		state_color = COLOR_STALE
	elif _registry.connection_state == ProcessRegistry.STATE_STALE:
		state_text = "STALE · LAST VALID METRICS"
		state_color = COLOR_STALE
	elif _registry.connection_state == ProcessRegistry.STATE_DISCONNECTED:
		state_text = "OFFLINE · LAST VALID METRICS"
		state_color = COLOR_DISCONNECTED
	elif _registry.connection_state == ProcessRegistry.STATE_CONNECTING:
		state_text = "WAITING FOR COLLECTOR"
		state_color = COLOR_WAITING
	_set_label_text(_details_state_label, state_text)
	_set_label_color(_details_state_label, state_color)


func _set_label_text(label: Label, value: String) -> void:
	if label.text != value:
		label.text = value


func _set_label_color(label: Label, value: Color) -> void:
	if label.get_theme_color("font_color") != value:
		label.add_theme_color_override("font_color", value)


func _connection_message(state: String) -> String:
	match state:
		ProcessRegistry.STATE_CONNECTING:
			return "Waiting for the local collector at 127.0.0.1:8765"
		ProcessRegistry.STATE_STALE:
			return "Snapshot delayed · showing the last valid data"
		ProcessRegistry.STATE_DISCONNECTED:
			return "Collector unavailable · retrying automatically"
	return ""


func _refresh_empty_state(state: String) -> void:
	if _empty_state_label == null:
		return
	var no_creatures := _last_represented_count == 0
	_empty_state_label.visible = no_creatures
	if not no_creatures:
		return
	if _source_mode == SOURCE_DEMO:
		_empty_state_label.text = "NO SIMULATED ORGANISMS"
	elif _last_monitored_count > 0:
		_empty_state_label.text = "NO ORGANISMS REPRESENTED"
	elif state == ProcessRegistry.STATE_CONNECTED:
		_empty_state_label.text = "NO PROCESSES DETECTED"
	elif state == ProcessRegistry.STATE_DISCONNECTED:
		_empty_state_label.text = "COLLECTOR OFFLINE"
	else:
		_empty_state_label.text = "WAITING FOR LOCAL COLLECTOR"
