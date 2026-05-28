extends Node

const _AUDIO_LIB  = preload("res://Resources/AudioLibrary.tres")
const _AUDIO_INST = preload("res://Resources/AudioInstance2D.tscn")

# Owns the Buyback tab — a vanilla Grid populated with recently sold items.
# Handles two injection paths:
#   TT installed : adds a tab to TraderTabs' existing tab bar and injects
#                  our panel into its grids_container.
#   TT absent    : creates two toggle Buttons above iface.supplyUI and overlays
#                  our panel at the same position/size.
#
# Instantiated as a child node of TraderCreditMain.

signal buyback_tab_activated
signal supply_tab_activated

# Node references — valid only while injected.
var injected: bool     = false
var _is_tt: bool       = false
var _tt_node           = null
var _tab_bar           = null   # TT's TabBar (TT path) or our button row Control (standalone)
var _tab_index: int    = -1     # only used for TT path
var _panel: Control    = null   # container for scroll + grid
var _grid              = null   # vanilla Grid node
var _supply_ui         = null   # iface.supplyUI (standalone only, for show/hide)
var _btn_supply        = null   # standalone Supply button
var _btn_buyback       = null   # standalone Buyback button

# Deferred sizing — supply_ui.size is (0,0) at inject time because layout
# hasn't run yet.  _process polls until size is non-zero, then applies bounds.
var _needs_standalone_reposition: bool = false
var _iface_ref                         = null
var _supply_header                     = null   # vanilla Header child hidden while our tabs are active
var _supply_content: Array             = []     # supply_ui content children hidden in buyback mode
var _buyback_active: bool              = false  # true while the buyback panel is the active tab

# Maps grid-child instance_id -> buyback entry index.
var _entry_map: Dictionary = {}

var _config = null


func _ready() -> void:
	_config = get_tree().root.get_node_or_null("TraderCreditConfig")


func _process(_delta: float) -> void:
	if _needs_standalone_reposition:
		_try_apply_standalone_bounds()
	elif injected and not _is_tt:
		# Short-circuit when supply UI is hidden — no visible nodes to fight.
		if not is_instance_valid(_supply_ui) or not _supply_ui.visible:
			return
		# Re-enforce hiding of game nodes that get re-shown by game code.
		if is_instance_valid(_supply_header) and _supply_header.visible:
			_supply_header.hide()
		if _buyback_active:
			for child in _supply_content:
				if is_instance_valid(child) and child.visible:
					child.hide()


func _on_supply_ui_visibility_changed() -> void:
	if not injected or not is_instance_valid(_supply_ui):
		return
	var supply_vis: bool = _supply_ui.visible
	if _is_tt:
		if not supply_vis:
			if is_instance_valid(_panel):
				_panel.hide()
		elif is_instance_valid(_tab_bar) and _tab_bar.current_tab == _tab_index:
			if is_instance_valid(_panel):
				_panel.show()
	else:
		if is_instance_valid(_tab_bar):
			_tab_bar.visible = supply_vis
		if not supply_vis:
			if is_instance_valid(_panel):
				_panel.hide()
		else:
			# supplyUI just became visible — re-hide the vanilla header we replaced.
			if is_instance_valid(_supply_header):
				_supply_header.hide()
			if _buyback_active and is_instance_valid(_panel):
				_panel.show()


# ---- Lifecycle ----

func inject(iface) -> void:
	if injected:
		return
	_tt_node = iface.get_node_or_null("TT_TraderTabs")

	if _tt_node != null:
		_inject_tt(iface)
	else:
		_inject_standalone(iface)


func cleanup() -> void:
	if is_instance_valid(_tab_bar):
		if _is_tt:
			if _tab_bar.tab_changed.is_connected(_on_tab_changed):
				_tab_bar.tab_changed.disconnect(_on_tab_changed)
			if _tab_index >= 0:
				_tab_bar.remove_tab(_tab_index)
		else:
			_tab_bar.queue_free()

	if is_instance_valid(_panel):
		_panel.queue_free()

	_tt_node     = null
	_tab_bar     = null
	_tab_index   = -1
	_panel       = null
	_grid        = null
	if is_instance_valid(_supply_ui) and _supply_ui.visibility_changed.is_connected(_on_supply_ui_visibility_changed):
		_supply_ui.visibility_changed.disconnect(_on_supply_ui_visibility_changed)
	_supply_ui   = null
	_btn_supply  = null
	_btn_buyback = null
	_iface_ref    = null
	_needs_standalone_reposition = false
	_buyback_active = false
	if is_instance_valid(_supply_header):
		_supply_header.show()
	_supply_header = null
	for child in _supply_content:
		if is_instance_valid(child):
			child.show()
	_supply_content.clear()
	_entry_map.clear()
	injected = false
	_is_tt   = false


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
		slot.itemData = item_data
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


# Toggles selection on the item at screen position pos.
# Returns true if an item was hit (so caller can consume the event).
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


# Returns a list of { "idx": int, "element": Node } for selected items.
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


# ---- Private — injection ----

func _inject_tt(iface) -> void:
	var tab_bar   = _tt_node.get("tab_bar")
	var grids_ctr = _tt_node.get("grids_container")
	if tab_bar == null or grids_ctr == null:
		push_warning("[TraderCredit] TraderTabs structure changed — falling back to standalone inject")
		_inject_standalone(iface)
		return
	_is_tt = true

	tab_bar.add_tab("Buyback")
	_tab_index = tab_bar.get_tab_count() - 1

	_panel = _build_panel()
	grids_ctr.add_child(_panel)
	_grid.CreateContainerGrid(Vector2(8, 20))
	_panel.hide()

	_tab_bar = tab_bar
	if not tab_bar.tab_changed.is_connected(_on_tab_changed):
		tab_bar.tab_changed.connect(_on_tab_changed)

	injected = true


func _inject_standalone(iface) -> void:
	_is_tt = false
	_supply_ui = iface.get("supplyUI")
	if _supply_ui == null:
		push_warning("[TraderCredit] BuybackUI: supplyUI not found — buyback tab skipped")
		return
	_supply_ui.visibility_changed.connect(_on_supply_ui_visibility_changed)

	_iface_ref = iface
	var btn_h: float = 26.0

	# Button row — position and size filled in once layout has run.
	var row := Control.new()
	row.name    = "TC_BuybackTabRow"
	row.z_index = 10
	iface.add_child(row)
	_tab_bar = row

	var btn_s := Button.new()
	btn_s.name           = "TC_SupplyTab"
	btn_s.text           = "Supply"
	btn_s.toggle_mode    = true
	btn_s.button_pressed = true
	btn_s.size           = Vector2(0, btn_h)
	row.add_child(btn_s)
	_btn_supply = btn_s

	var btn_b := Button.new()
	btn_b.name           = "TC_BuybackTab"
	btn_b.text           = "Buyback"
	btn_b.toggle_mode    = true
	btn_b.button_pressed = false
	btn_b.size           = Vector2(0, btn_h)
	row.add_child(btn_b)
	_btn_buyback = btn_b

	btn_s.pressed.connect(_on_supply_btn_pressed)
	btn_b.pressed.connect(_on_buyback_btn_pressed)

	_panel = _build_panel()
	iface.add_child(_panel)
	_grid.CreateContainerGrid(Vector2(8, 20))
	# Override PRESET_FULL_RECT so explicit position/size take effect.
	# Position and size are filled in by _try_apply_standalone_bounds.
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.z_index = 9
	_panel.hide()

	injected = true
	_needs_standalone_reposition = true


func _try_apply_standalone_bounds() -> void:
	if not is_instance_valid(_supply_ui) or not is_instance_valid(_iface_ref):
		_needs_standalone_reposition = false
		return

	var su_size: Vector2 = Vector2.ZERO
	var content_candidates: Array = []
	for child in _supply_ui.get_children():
		if child is Control and child.size.x > 0 and child.position.y >= 0:
			if su_size == Vector2.ZERO:
				su_size = child.size
			content_candidates.append(child)
	# Fallback: supplyGrid.
	if su_size.x <= 0:
		var sg = _iface_ref.get("supplyGrid")
		if sg and sg is Control:
			su_size = sg.size

	if su_size.x <= 0 or su_size.y <= 0:
		return  # layout not settled yet — try next frame

	_supply_content = content_candidates  # assign only on success to prevent duplicate entries
	_needs_standalone_reposition = false
	if not is_instance_valid(_panel) or not is_instance_valid(_tab_bar):
		return

	var su_pos: Vector2 = _supply_ui.global_position - _iface_ref.global_position

	# Find the vanilla Header child (positioned above content, y < 0).
	# Hide it permanently while our mod is active — our button row replaces it
	# visually, and the "Supply" label / count badge are its children.
	var header_offset: Vector2 = Vector2.ZERO
	var btn_h: float           = 26.0
	var btn_w: float           = su_size.x / 2.0
	for child in _supply_ui.get_children():
		if child is Control and child.position.y < 0 and child.size.x > 0 and child.size.y > 0:
			_supply_header = child
			child.hide()
			header_offset = child.position         # e.g. (0, -32)
			btn_h         = child.size.y           # e.g. 32
			btn_w         = child.size.x / 2.0     # e.g. 96
			break

	_tab_bar.position = su_pos + header_offset    # e.g. (192, 96)
	_tab_bar.size     = Vector2(btn_w * 2.0, btn_h)
	if is_instance_valid(_btn_supply):
		_btn_supply.size = Vector2(btn_w, btn_h)
	if is_instance_valid(_btn_buyback):
		_btn_buyback.position = Vector2(btn_w, 0)
		_btn_buyback.size     = Vector2(btn_w, btn_h)

	_panel.position = su_pos
	_panel.size     = su_size


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
		grid.set("stretch_mode", 1)  # TextureRect.STRETCH_TILE
		grid.set("self_modulate", Color(1, 1, 1, 0.25))
	scroll.add_child(grid)
	# CreateContainerGrid is called after this panel is added to the scene tree.

	_grid = grid
	return panel


# ---- Private — tab handling (TT path) ----

func _on_tab_changed(idx: int) -> void:
	if idx == _tab_index:
		# TT hides grids_container for non-supply tabs (e.g. Tasks). Re-show it
		# here so our panel — which lives inside it — is actually visible.
		if is_instance_valid(_tt_node):
			var grids_ctr = _tt_node.get("grids_container")
			if grids_ctr != null:
				grids_ctr.show()
		# Hide TT's grids before showing ours (TT returns early on unmapped tabs
		# without hiding them first).
		if _tt_node != null and _tt_node.has_method("get_all_grids"):
			for g in _tt_node.get_all_grids():
				g.hide()

		if is_instance_valid(_panel):
			_panel.show()

		emit_signal("buyback_tab_activated")
	else:
		if is_instance_valid(_panel):
			_panel.hide()

		emit_signal("supply_tab_activated")


# ---- Private — tab handling (standalone path) ----

func _on_supply_btn_pressed() -> void:
	_buyback_active = false
	if is_instance_valid(_btn_supply):
		_btn_supply.button_pressed = true
	if is_instance_valid(_btn_buyback):
		_btn_buyback.button_pressed = false
	if is_instance_valid(_panel):
		_panel.hide()
	for child in _supply_content:
		if is_instance_valid(child):
			child.show()
	emit_signal("supply_tab_activated")


func _on_buyback_btn_pressed() -> void:
	_buyback_active = true
	if is_instance_valid(_btn_supply):
		_btn_supply.button_pressed = false
	if is_instance_valid(_btn_buyback):
		_btn_buyback.button_pressed = true
	for child in _supply_content:
		if is_instance_valid(child):
			child.hide()
	if is_instance_valid(_panel):
		_panel.show()
	emit_signal("buyback_tab_activated")


# ---- Private — overlay ----

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


# ---- Utility ----

func _play_select_sound() -> void:
	var click = _AUDIO_INST.instantiate()
	add_child(click)
	if click.has_signal("finished"):
		click.finished.connect(click.queue_free)
	click.PlayInstance(_AUDIO_LIB.UIClick)


func days_remaining(entry: Dictionary, current_day: int) -> int:
	var expiry: int = _config.buyback_expiry_days if _config != null else 7
	return max(0, expiry - (current_day - int(entry["sell_day"])))
