extends Node

# Owns all UI state and construction for the credit system.
# Instantiated as a child node of TraderCreditMain.
#
# Call inject() once per interface open, switch_tab() on tab clicks,
# and update_panel() whenever credit-relevant state changes.

var injected: bool = false
var active_tab: int = 0
var pending_buy_cost: float = 0.0

# Exposed so Main can hit-test them in _input.
var barter_tab_btn: Button = null
var credit_tab_btn: Button = null
var sell_button: Button = null

var _wrapper: Control = null
var _deal_section: Node = null
var _credit_panel: Control = null
var _balance_label: Label = null
var _earn_label: Label = null
var _warn_label: Label = null
var _buy_cost_label: Label = null


func is_valid() -> bool:
	return (
		is_instance_valid(barter_tab_btn) and
		is_instance_valid(credit_tab_btn) and
		is_instance_valid(_deal_section)  and
		is_instance_valid(_credit_panel)  and
		is_instance_valid(sell_button)
	)


func reset() -> void:
	injected         = false
	active_tab       = 0
	pending_buy_cost = 0.0
	barter_tab_btn   = null
	credit_tab_btn   = null
	sell_button      = null
	_wrapper         = null
	_deal_section    = null
	_credit_panel    = null
	_balance_label   = null
	_earn_label      = null
	_warn_label      = null
	_buy_cost_label  = null


func show_wrapper() -> void:
	if is_instance_valid(_wrapper):
		_wrapper.visible = true


func hide_wrapper() -> void:
	if is_instance_valid(_wrapper):
		_wrapper.visible = false


func inject(iface, section: Node) -> void:
	if injected:
		return

	# Derive wrapper rect from Trader portrait and Character panel positions.
	var trader_node  = iface.get_node_or_null("Trader")
	var portrait     = trader_node.get_node_or_null("Panel") if trader_node else null
	var character    = iface.get_node_or_null("Character")
	var trader_pos: Vector2 = trader_node.position if trader_node else Vector2(768, 128)
	var portrait_h:  float  = portrait.size.y      if portrait    else 384.0
	var character_y: float  = character.position.y if character   else 768.0
	var wrapper_w:   float  = 384.0
	var wrapper_y:   float  = trader_pos.y + portrait_h + 20.0
	var wrapper_h:   float  = character_y - wrapper_y

	var wrapper := Control.new()
	wrapper.name     = "TraderCreditWrapper"
	wrapper.position = Vector2(trader_pos.x, wrapper_y)
	wrapper.size     = Vector2(wrapper_w, wrapper_h)
	wrapper.z_index  = 100
	iface.add_child(wrapper)
	_wrapper = wrapper

	# Tab row pinned to the top of the wrapper.
	var tab_row := HBoxContainer.new()
	tab_row.name     = "TraderCreditTabRow"
	tab_row.position = Vector2(0, 0)
	tab_row.size     = Vector2(wrapper_w, 32)
	tab_row.add_theme_constant_override("separation", 4)
	wrapper.add_child(tab_row)

	var barter_btn := Button.new()
	barter_btn.name                  = "BarterTab"
	barter_btn.text                  = "Barter"
	barter_btn.custom_minimum_size   = Vector2(60, 28)
	barter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barter_btn.focus_mode            = Control.FOCUS_NONE
	barter_btn.mouse_filter          = Control.MOUSE_FILTER_STOP
	tab_row.add_child(barter_btn)
	barter_tab_btn = barter_btn

	var credit_btn := Button.new()
	credit_btn.name                  = "CreditTab"
	credit_btn.text                  = "Credit"
	credit_btn.custom_minimum_size   = Vector2(60, 28)
	credit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credit_btn.focus_mode            = Control.FOCUS_NONE
	credit_btn.mouse_filter          = Control.MOUSE_FILTER_STOP
	tab_row.add_child(credit_btn)
	credit_tab_btn = credit_btn

	# Content area below the tab row.
	var content_y := 32.0
	var content_h := wrapper_h - 32.0

	# Pull the deal section out of the Trader VBoxContainer into our wrapper.
	section.reparent(wrapper)
	_hide_deal_label(section)
	section.set_anchor(SIDE_LEFT,   0.0)
	section.set_anchor(SIDE_RIGHT,  0.0)
	section.set_anchor(SIDE_TOP,    0.0)
	section.set_anchor(SIDE_BOTTOM, 0.0)
	section.position = Vector2(0, content_y)
	# Use the section's minimum content height so we don't stretch the game's UI.
	var panel_h: float = section.get_combined_minimum_size().y
	if panel_h <= 0.0:
		panel_h = section.size.y
	section.size = Vector2(wrapper_w, panel_h)
	_deal_section = section

	var credit_panel := _build_credit_panel()
	credit_panel.visible  = false
	credit_panel.position = Vector2(0, content_y)
	credit_panel.size     = Vector2(wrapper_w, panel_h)
	wrapper.add_child(credit_panel)
	_credit_panel = credit_panel

	var buy_cost_label := Label.new()
	buy_cost_label.name = "CreditBuyCost"
	buy_cost_label.add_theme_font_size_override("font_size", 13)
	buy_cost_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	buy_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_cost_label.position = Vector2(0, content_y + panel_h + 5.0)
	buy_cost_label.size     = Vector2(wrapper_w, 20)
	buy_cost_label.visible  = false
	wrapper.add_child(buy_cost_label)
	_buy_cost_label = buy_cost_label

	call_deferred("_reposition_buy_cost_label")
	switch_tab(0)
	injected = true


func switch_tab(idx: int) -> void:
	active_tab = idx
	if is_instance_valid(_deal_section):
		_deal_section.visible = (idx == 0)
	if is_instance_valid(_credit_panel):
		_credit_panel.visible = (idx == 1)
	if is_instance_valid(_buy_cost_label) and idx != 0:
		_buy_cost_label.visible = false
	_style_tab(barter_tab_btn, idx == 0)
	_style_tab(credit_tab_btn, idx == 1)


func update_pending_cost(cost: float) -> void:
	if not is_instance_valid(_buy_cost_label):
		return
	if cost > 0.0 and active_tab == 0:
		_buy_cost_label.text    = "Will spend %d credit" % int(cost)
		_buy_cost_label.visible = true
	else:
		_buy_cost_label.visible = false


func _style_tab(btn: Button, active: bool) -> void:
	if not is_instance_valid(btn):
		return
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left  = 3
	style.corner_radius_top_right = 3
	style.content_margin_left   = 4.0
	style.content_margin_right  = 4.0
	style.content_margin_top    = 4.0
	style.content_margin_bottom = 4.0
	if active:
		style.bg_color  = Color(0.25, 0.6, 0.85, 0.45)
		btn.modulate    = Color(1, 1, 1, 1.0)
	else:
		style.bg_color  = Color(0.1, 0.1, 0.1, 0.45)
		btn.modulate    = Color(1, 1, 1, 0.55)
	btn.add_theme_stylebox_override("normal",   style)
	btn.add_theme_stylebox_override("hover",    style)
	btn.add_theme_stylebox_override("pressed",  style)
	btn.add_theme_stylebox_override("focus",    style)


func update_panel(
	balance: float, cap: int, remaining: float,
	offer_value: float, req_count: int, sell_tax: float
) -> void:
	if not is_instance_valid(_balance_label):
		return

	var credit_value: float = floor(offer_value * (1.0 - sell_tax / 100.0))
	var can_sell := offer_value > 0 and req_count == 0 and cap > 0
	var would_exceed := (balance + credit_value) > float(cap)

	# Balance line
	if cap == 0:
		_balance_label.text = "Credit: — (complete tasks to unlock)"
	else:
		_balance_label.text = "Credit: %d / %d" % [int(balance), cap]

	# Earn preview
	if can_sell:
		_earn_label.text = "Selected: +%d credit" % int(min(credit_value, remaining))
	else:
		_earn_label.text = ""

	# Warning / hint
	if not can_sell:
		if cap == 0:
			_warn_label.text = "Complete trader tasks to earn credit capacity."
		elif req_count > 0:
			_warn_label.text = "Deselect trader items to sell for credit."
		else:
			_warn_label.text = "Select items from your inventory to sell."
	elif would_exceed:
		_warn_label.text = "Exceeds your credit limit — partial credit only."
	else:
		_warn_label.text = ""

	# Sell button
	if is_instance_valid(sell_button):
		sell_button.disabled = not can_sell
		if can_sell:
			sell_button.text = "Sell for Credit (+%d)" % int(min(credit_value, remaining))
		else:
			sell_button.text = "Sell for Credit"


# ---- Private helpers ----

func _reposition_buy_cost_label() -> void:
	if not is_instance_valid(_deal_section) or not is_instance_valid(_buy_cost_label):
		return
	var section_bottom: float = _deal_section.position.y + _deal_section.size.y
	_buy_cost_label.position = Vector2(0, section_bottom + 5.0)


func _hide_deal_label(node: Node) -> void:
	for child in node.get_children():
		if child is Label and child.text == "Deal":
			child.visible = false
			return
		_hide_deal_label(child)


func _build_credit_panel() -> Control:
	var margin := MarginContainer.new()
	margin.name = "CreditPanel"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var balance_label := Label.new()
	balance_label.name = "CreditBalance"
	balance_label.add_theme_font_size_override("font_size", 14)
	balance_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	balance_label.text = "Credit: —"
	vbox.add_child(balance_label)
	_balance_label = balance_label

	var earn_label := Label.new()
	earn_label.name = "CreditEarn"
	earn_label.add_theme_font_size_override("font_size", 13)
	earn_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	earn_label.text = ""
	vbox.add_child(earn_label)
	_earn_label = earn_label

	var warn_label := Label.new()
	warn_label.name = "CreditWarn"
	warn_label.add_theme_font_size_override("font_size", 12)
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
	warn_label.text = ""
	warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(warn_label)
	_warn_label = warn_label

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.name     = "SellForCredit"
	btn.text     = "Sell for Credit"
	btn.disabled = true
	vbox.add_child(btn)
	sell_button = btn

	return margin
