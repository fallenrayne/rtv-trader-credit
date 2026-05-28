extends Node

# Handles the standalone injection path for the buyback panel (no TraderTabs present).
# Owns: button row (TC_BuybackTabRow), supplyUI visibility signal,
#       supply header/content enforcement, and panel repositioning.
# Does NOT own _panel — BuybackUI holds the lifetime; this class holds a reference.

signal buyback_tab_activated
signal supply_tab_activated

var _panel: Control    = null
var _supply_ui         = null
var _iface_ref         = null
var _tab_bar: Control  = null   # the TC_BuybackTabRow Control
var _btn_supply: Button  = null
var _btn_buyback: Button = null
var _supply_header     = null
var _supply_content: Array = []
var _buyback_active: bool  = false
var _needs_reposition: bool = false


func inject(iface, panel: Control) -> bool:
	var supply_ui = iface.get("supplyUI")
	if supply_ui == null:
		push_warning("[TraderCredit] BuybackStandaloneAdapter: supplyUI not found — buyback tab skipped")
		return false

	_supply_ui = supply_ui
	_iface_ref = iface
	_panel     = panel

	var btn_h: float = 26.0
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

	iface.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.z_index = 9
	panel.hide()

	supply_ui.visibility_changed.connect(_on_supply_ui_visibility_changed)
	_needs_reposition = true
	return true


func cleanup() -> void:
	if is_instance_valid(_supply_ui) \
			and _supply_ui.visibility_changed.is_connected(_on_supply_ui_visibility_changed):
		_supply_ui.visibility_changed.disconnect(_on_supply_ui_visibility_changed)

	if is_instance_valid(_tab_bar):
		_tab_bar.queue_free()

	if is_instance_valid(_supply_header):
		_supply_header.show()
	_supply_header = null
	for child in _supply_content:
		if is_instance_valid(child):
			child.show()
	_supply_content.clear()

	_supply_ui      = null
	_iface_ref      = null
	_tab_bar        = null
	_btn_supply     = null
	_btn_buyback    = null
	_panel          = null  # BuybackUI owns the node
	_buyback_active = false
	_needs_reposition = false


func _process(_delta: float) -> void:
	if _needs_reposition:
		_try_apply_standalone_bounds()
		return
	if not is_instance_valid(_supply_ui) or not _supply_ui.visible:
		return
	if is_instance_valid(_supply_header) and _supply_header.visible:
		_supply_header.hide()
	if _buyback_active:
		for child in _supply_content:
			if is_instance_valid(child) and child.visible:
				child.hide()


func _on_supply_ui_visibility_changed() -> void:
	if not is_instance_valid(_supply_ui):
		return
	var supply_vis: bool = _supply_ui.visible
	if is_instance_valid(_tab_bar):
		_tab_bar.visible = supply_vis
	if not supply_vis:
		if is_instance_valid(_panel):
			_panel.hide()
	else:
		if is_instance_valid(_supply_header):
			_supply_header.hide()
		if _buyback_active and is_instance_valid(_panel):
			_panel.show()


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


func _try_apply_standalone_bounds() -> void:
	if not is_instance_valid(_supply_ui) or not is_instance_valid(_iface_ref):
		_needs_reposition = false
		return

	var su_size: Vector2 = Vector2.ZERO
	var content_candidates: Array = []
	for child in _supply_ui.get_children():
		if child is Control and child.size.x > 0 and child.position.y >= 0:
			if su_size == Vector2.ZERO:
				su_size = child.size
			content_candidates.append(child)
	if su_size.x <= 0:
		var sg = _iface_ref.get("supplyGrid")
		if sg and sg is Control:
			su_size = sg.size

	if su_size.x <= 0 or su_size.y <= 0:
		return  # layout not settled yet — try next frame

	_supply_content   = content_candidates
	_needs_reposition = false
	if not is_instance_valid(_panel) or not is_instance_valid(_tab_bar):
		return

	var su_pos: Vector2 = _supply_ui.global_position - _iface_ref.global_position

	var header_offset: Vector2 = Vector2.ZERO
	var btn_h: float           = 26.0
	var btn_w: float           = su_size.x / 2.0
	for child in _supply_ui.get_children():
		if child is Control and child.position.y < 0 and child.size.x > 0 and child.size.y > 0:
			_supply_header = child
			child.hide()
			header_offset = child.position
			btn_h         = child.size.y
			btn_w         = child.size.x / 2.0
			break

	_tab_bar.position = su_pos + header_offset
	_tab_bar.size     = Vector2(btn_w * 2.0, btn_h)
	if is_instance_valid(_btn_supply):
		_btn_supply.size = Vector2(btn_w, btn_h)
	if is_instance_valid(_btn_buyback):
		_btn_buyback.position = Vector2(btn_w, 0)
		_btn_buyback.size     = Vector2(btn_w, btn_h)

	_panel.position = su_pos
	_panel.size     = su_size
