extends Control
class_name SyntheticLifeLab

const WispScript = preload("res://scripts/synthetic_wisp.gd")
const PRIMARY := Color("#ddf8f2")
const MUTED := Color("#89a7b0")
const ACCENT := Color("#62dfcf")

var _wisp: SyntheticWisp
var _cpu_slider: HSlider
var _ram_slider: HSlider
var _state_label: Label
var _cpu_value: Label
var _ram_value: Label
var _species_option: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wisp = WispScript.new() as SyntheticWisp
	_wisp.position = Vector2(320.0, 116.0)
	add_child(_wisp)
	_build_header()
	_build_controls()
	_send_metrics()
	queue_redraw()


func _process(_delta: float) -> void:
	if _state_label == null or _wisp == null:
		return
	var state := _wisp.activity_state()
	_state_label.text = "%s  ·  luminous pulse and filaments follow CPU; membrane mass follows RAM" % state
	_state_label.add_theme_color_override(
		"font_color", Color("#ffca85") if state == "Overclocked" else ACCENT
	)


func get_wisp() -> SyntheticWisp:
	return _wisp


func set_preview_metrics(cpu_percent: float, ram_mib: float) -> void:
	if _cpu_slider == null or _ram_slider == null:
		return
	_cpu_slider.value = clampf(cpu_percent, 0.0, 100.0)
	_ram_slider.value = clampf(ram_mib, 0.0, 8192.0)
	_send_metrics()


func set_preview_species(family_index: int) -> bool:
	if family_index < 0 or family_index >= SyntheticLifeVisual.FAMILY_COUNT or _wisp == null:
		return false
	if not _wisp.set_species(family_index):
		return false
	if _species_option != null:
		_species_option.select(family_index)
	return true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#080d17"))
	draw_circle(Vector2(320.0, 116.0), 154.0, Color("#0d2631", 0.22))
	draw_circle(Vector2(320.0, 116.0), 111.0, Color("#10232e", 0.16))
	draw_arc(Vector2(320.0, 116.0), 164.0, 0.0, TAU, 96, Color("#2b5961", 0.16), 1.0, true)
	draw_line(Vector2(24.0, 45.0), Vector2(616.0, 45.0), Color("#27424b", 0.55), 1.0, true)


func _build_header() -> void:
	var title := Label.new()
	title.position = Vector2(25.0, 13.0)
	title.text = "SYNTHETIC LIFE SANCTUARY"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", PRIMARY)
	add_child(title)
	var subtitle := Label.new()
	subtitle.position = Vector2(26.0, 33.0)
	subtitle.text = "FIELD 01  /  PROCEDURAL ORGANISM  /  CPU ACTIVITY + RAM MASS"
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", MUTED)
	add_child(subtitle)
	_species_option = OptionButton.new()
	_species_option.name = "OrganismFamily"
	_species_option.position = Vector2(481.0, 17.0)
	_species_option.size = Vector2(133.0, 24.0)
	for family_index in range(SyntheticLifeVisual.FAMILY_NAMES.size()):
		_species_option.add_item(SyntheticLifeVisual.FAMILY_NAMES[family_index], family_index)
	_species_option.select(0)
	_species_option.item_selected.connect(_on_species_selected)
	add_child(_species_option)
	_state_label = Label.new()
	_state_label.position = Vector2(26.0, 189.0)
	_state_label.size = Vector2(588.0, 18.0)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.add_theme_font_size_override("font_size", 10)
	_state_label.add_theme_color_override("font_color", ACCENT)
	add_child(_state_label)


func _build_controls() -> void:
	var panel := PanelContainer.new()
	panel.name = "PreviewControls"
	panel.position = Vector2(23.0, 230.0)
	panel.size = Vector2(594.0, 116.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0c1721", 0.96)
	style.border_color = Color("#29434b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	var cpu_row := HBoxContainer.new()
	cpu_row.add_theme_constant_override("separation", 8)
	column.add_child(cpu_row)
	cpu_row.add_child(_make_caption("CPU", 52.0))
	_cpu_slider = _make_slider(0.0, 100.0, 1.0)
	_cpu_slider.name = "CpuSlider"
	_cpu_slider.value = 4.0
	_cpu_slider.value_changed.connect(_on_controls_changed)
	cpu_row.add_child(_cpu_slider)
	_cpu_value = _make_value_label()
	cpu_row.add_child(_cpu_value)
	var ram_row := HBoxContainer.new()
	ram_row.add_theme_constant_override("separation", 8)
	column.add_child(ram_row)
	ram_row.add_child(_make_caption("RAM", 52.0))
	_ram_slider = _make_slider(0.0, 8192.0, 64.0)
	_ram_slider.name = "RamSlider"
	_ram_slider.value = 512.0
	_ram_slider.value_changed.connect(_on_controls_changed)
	ram_row.add_child(_ram_slider)
	_ram_value = _make_value_label()
	ram_row.add_child(_ram_value)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 5)
	column.add_child(buttons)
	_add_preset_button(buttons, "Dormant", 4.0, 256.0)
	_add_preset_button(buttons, "Active", 44.0, 2048.0)
	_add_preset_button(buttons, "Overclocked", 94.0, 6144.0)
	var reset := Button.new()
	reset.text = "Reset"
	reset.add_theme_font_size_override("font_size", 9)
	reset.pressed.connect(_reset_preview)
	buttons.add_child(reset)


func _make_caption(text: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = width
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", MUTED)
	return label


func _make_value_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size.x = 48.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", PRIMARY)
	return label


func _make_slider(minimum: float, maximum: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.focus_mode = Control.FOCUS_ALL
	slider.custom_minimum_size.y = 16.0
	return slider


func _add_preset_button(parent: HBoxContainer, text: String, cpu: float, ram: float) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(_apply_preset.bind(cpu, ram))
	parent.add_child(button)


func _apply_preset(cpu: float, ram: float) -> void:
	set_preview_metrics(cpu, ram)


func _reset_preview() -> void:
	set_preview_metrics(4.0, 512.0)


func _on_controls_changed(_value: float) -> void:
	_send_metrics()


func _on_species_selected(family_index: int) -> void:
	if _wisp != null:
		_wisp.set_species(family_index)


func _send_metrics() -> void:
	if _wisp == null or _cpu_slider == null or _ram_slider == null:
		return
	var cpu := _cpu_slider.value
	var ram := _ram_slider.value
	_wisp.set_metrics(cpu, int(ram * 1_048_576.0))
	_cpu_value.text = "%d%%" % int(cpu)
	_ram_value.text = "%.1f GiB" % (ram / 1024.0)
