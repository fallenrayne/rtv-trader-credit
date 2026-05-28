extends Node

# Thin coordinator for the buyback tab.
# Owns: panel, grid, entry map, and whichever adapter is active.
# Injection-path logic lives in BuybackTTAdapter / BuybackStandaloneAdapter.

const _AUDIO_LIB  = preload("res://Resources/AudioLibrary.tres")
const _AUDIO_INST = preload("res://Resources/AudioInstance2D.tscn")
const _TTAdapter         = preload("res://mods/TraderCredit/BuybackTTAdapter.gd")
const _StandaloneAdapter = preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd")

signal buyback_tab_activated
signal supply_tab_activated

var injected: bool = false

var _panel: Control        = null
var _grid                  = null
var _adapter: Node         = null
var _entry_map: Dictionary = {}
var _config                = null


func _ready() -> void:
	_config = get_tree().root.get_node_or_null("TraderCreditConfig")


# ---- Lifecycle ----

func inject(iface) -> void:
	if injected:
		return

	_panel = _build_panel()

	# Try TT path first; fall back to standalone if the TT structure is absent or changed.
	var tt_adapter := _TTAdapter.new()
	tt_adapter.name = "TC_BuybackTTAdapter"
	add_child(tt_adapter)

	if tt_adapter.inject(iface, _panel):
		_adapter = tt_adapter
	else:
		tt_adapter.queue_free()
		# Panel was not added to any tree — standalone adapter will add it.
		var sa_adapter := _StandaloneAdapter.new()
		sa_adapter.name = "TC_BuybackStandaloneAdapter"
		add_child(sa_adapter)
		if not sa_adapter.inject(iface, _panel):
			push_warning("[TraderCredit] BuybackUI: both TT and standalone inject failed — buyback tab unavailable")
			sa_adapter.queue_free()
			_panel.queue_free()
			_panel = null
			_grid  = null
			return
		_adapter = sa_adapter

	# Panel is in the scene tree now — safe to initialise the grid layout.
	_grid.CreateContainerGrid(Vector2(8, 20))

	_adapter.buyback_tab_activated.connect(func(): emit_signal("buyback_tab_activated"))
	_adapter.supply_tab_activated.connect(func(): emit_signal("supply_tab_activated"))
	injected = true


func cleanup() -> void:
	if is_instance_valid(_adapter):
		_adapter.cleanup()  # disconnects signals and restores game nodes before panel is freed
		_adapter.queue_free()
	_adapter = null

	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_grid  = null

	_entry_map.clear()
	injected = false


# ---- Population ----

func populate(entries: Array, iface, current_day: int) -> void:
	clear_grid()
	if _grid == null:
		return

	for i in entries.size():
		var entry: Dictionary = entries[i]
		var item_data = load(entry["resource_path"])
		if item_data == null:
			push_warning("[TraderCredit] BuybackUI: failed to load %s" % entry["resource_path"])
			continue

		var slot = SlotData.new()
		slot.itemData  = item_data
		slot.condition = entry["condition"]
		slot.amount    = entry["amount"]

		var before_count: int = _grid.get_child_count()
		iface.Create(slot, _grid, false)
		for j in range(before_count, _grid.get_child_count()):
			var new_child = _grid.get_child(j)
			if is_instance_valid(new_child):
				new_child.set_meta("_tc_entry_idx", i)
				_entry_map[new_child.get_instance_id()] = i
				_apply_expiry_overlay(new_child, days_remaining(entry, current_day))


func clear_grid() -> void:
	if _grid == null:
		return
	if _grid.has_method("ClearGrid"):
		_grid.ClearGrid()
	var children: Array = _grid.get_children()
	for child in children:
		_grid.remove_child(child)
		child.queue_free()
	_entry_map.clear()


func try_click(pos: Vector2) -> bool:
	if _grid == null:
		return false
	if not is_instance_valid(_panel) or not _panel.is_visible_in_tree():
		return false
	for child in _grid.get_children():
		if not is_instance_valid(child) or not child.has_method("State"):
			continue
		if child.get_global_rect().has_point(pos):
			var is_sel: bool = child.get("selected") == true
			child.State("Static" if is_sel else "Selected")
			_play_select_sound()
			return true
	return false


func get_selected() -> Array:
	var result: Array = []
	if _grid == null:
		return result
	for child in _grid.get_children():
		if not is_instance_valid(child):
			continue
		if child.selected and child.has_meta("_tc_entry_idx"):
			result.append({
				"idx":     child.get_meta("_tc_entry_idx"),
				"element": child,
			})
	return result


# ---- Utilities ----

func days_remaining(entry: Dictionary, current_day: int) -> int:
	var expiry: int = _config.buyback_expiry_days if _config != null else 7
	return max(0, expiry - (current_day - int(entry["sell_day"])))


func _build_panel() -> Control:
	var panel := Control.new()
	panel.name         = "TC_BuybackPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)

	var grid = load("res://Scripts/Grid.gd").new()
	grid.name = "TC_BuybackGrid"
	var tile_tex = load("res://UI/Sprites/Tile.png")
	if tile_tex:
		grid.set("texture", tile_tex)
		grid.set("stretch_mode", 1)
		grid.set("self_modulate", Color(1, 1, 1, 0.25))
	scroll.add_child(grid)

	_grid = grid
	return panel


func _apply_expiry_overlay(element: Node, days: int) -> void:
	var label := Label.new()
	label.name = "_tc_expiry"
	label.text = "%dd" % days
	label.add_theme_font_size_override("font_size", 11)

	var col: Color
	if days <= 1:
		col = Color(1.0, 0.3, 0.3)
	elif days <= 3:
		col = Color(1.0, 0.75, 0.1)
	else:
		col = Color(0.45, 1.0, 0.45)
	label.add_theme_color_override("font_color", col)

	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left   = -30
	label.offset_top    = -16
	label.offset_right  = -2
	label.offset_bottom = -2

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	label.add_theme_stylebox_override("normal", bg)

	element.add_child(label)


func _play_select_sound() -> void:
	var click = _AUDIO_INST.instantiate()
	add_child(click)
	if click.has_signal("finished"):
		click.finished.connect(click.queue_free)
	click.PlayInstance(_AUDIO_LIB.UIClick)
