extends Node

# Owns all UI state and construction for the credit system.
# Instantiated as a child node of TraderCreditMain.
#
# Call inject() once per interface open, update_panel() whenever
# credit-relevant state changes, and update_pending_cost() when a
# credit-buy deficit is calculated.

const TraderLayout = preload("res://mods/TraderCredit/TraderLayout.gd")

var injected: bool = false
var pending_buy_cost: float = 0.0
var pending_credit_shortfall: float = 0.0
var _needs_reposition: bool = false
var _layout = null

var sell_button: Button = null

var _wrapper: Control = null
var _deal_section: Node = null
var _balance_label: Label = null
var _info_label: Label = null   # right-aligned on the balance row; earn/warn/pending-buy


func is_valid() -> bool:
	return (
		is_instance_valid(_deal_section)  and
		is_instance_valid(_balance_label) and
		is_instance_valid(sell_button)
	)


func _process(_delta: float) -> void:
	if _needs_reposition and _layout != null and _layout.refresh_deal_height():
		_needs_reposition = false
		_reposition_sell_area()


func reset() -> void:
	injected                  = false
	pending_buy_cost          = 0.0
	pending_credit_shortfall  = 0.0
	_needs_reposition         = false
	_layout           = null
	sell_button       = null
	_wrapper          = null
	_deal_section     = null
	_balance_label    = null
	_info_label       = null


func show_wrapper() -> void:
	if is_instance_valid(_wrapper):
		_wrapper.visible = true


func hide_wrapper() -> void:
	if is_instance_valid(_wrapper):
		_wrapper.visible = false


func inject(iface, section: Node) -> void:
	if injected:
		return

	_layout = TraderLayout.new()
	_layout.measure(iface)
	Engine.set_meta("TraderCreditLayout", _layout)

	var wrapper_x: float = _layout.panel_x
	var wrapper_y: float = _layout.portrait_bot_y + 20.0
	var wrapper_w: float = _layout.panel_w
	var wrapper_h: float = _layout.character_top_y - wrapper_y

	var wrapper := Control.new()
	wrapper.name     = "TraderCreditWrapper"
	wrapper.position = Vector2(wrapper_x, wrapper_y)
	wrapper.size     = Vector2(wrapper_w, wrapper_h)
	wrapper.z_index  = 100
	iface.add_child(wrapper)
	_wrapper = wrapper

	# Balance label — left side of the top row.
	var balance_label := Label.new()
	balance_label.name = "CreditBalance"
	balance_label.add_theme_font_size_override("font_size", 14)
	balance_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	balance_label.text     = "Credit: —"
	balance_label.position = Vector2(0, 0)
	balance_label.size     = Vector2(wrapper_w, 20)
	wrapper.add_child(balance_label)
	_balance_label = balance_label

	# Info label — right side of the same top row (earn preview / warn / pending buy).
	var info_label := Label.new()
	info_label.name = "CreditInfo"
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.text     = ""
	info_label.position = Vector2(0, 0)
	info_label.size     = Vector2(wrapper_w, 20)
	wrapper.add_child(info_label)
	_info_label = info_label

	# Deal section sits directly below the balance/info row.
	var content_y := 24.0
	section.reparent(wrapper)
	_hide_deal_label(section)
	section.set_anchor(SIDE_LEFT,   0.0)
	section.set_anchor(SIDE_RIGHT,  0.0)
	section.set_anchor(SIDE_TOP,    0.0)
	section.set_anchor(SIDE_BOTTOM, 0.0)
	section.position = Vector2(0, content_y)
	_deal_section    = section
	_layout.deal_section = section
	_layout.deal_top_y   = content_y

	print("[TraderCredit] inject — section '%s'  size=%s  min_size=%s" \
		% [section.name, section.size, section.get_combined_minimum_size()])

	# Sell button — placeholder; _reposition_sell_area() moves it below the deal section.
	var btn := Button.new()
	btn.name     = "SellForCredit"
	btn.text     = "Sell for Credit"
	btn.disabled = true
	btn.position = Vector2(0, content_y)
	btn.size     = Vector2(wrapper_w, 26)
	wrapper.add_child(btn)
	sell_button = btn

	_needs_reposition = true
	injected = true


func update_pending_cost(cost: float) -> void:
	pending_buy_cost = cost
	if not is_instance_valid(_info_label):
		return
	if cost > 0.0:
		_info_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
		_info_label.text = "Will spend %d credit" % int(cost)
	else:
		_info_label.text = ""


func update_panel(
	balance: float, cap: int, remaining: float,
	offer_value: float, req_count: int, sell_tax: float
) -> void:
	if not is_instance_valid(_balance_label):
		return

	var credit_value: float = floor(offer_value * (1.0 - sell_tax / 100.0))
	var can_sell := offer_value > 0 and req_count == 0 and cap > 0
	var would_exceed := (balance + credit_value) > float(cap)
	if req_count == 0:
		pending_credit_shortfall = 0.0
		pending_buy_cost = 0.0

	# Balance line.
	if cap == 0:
		_balance_label.text = "Credit: — (complete tasks to unlock)"
	else:
		_balance_label.text = "Credit: %d / %d" % [int(balance), cap]

	# Right-aligned info — only update when no pending buy is displayed there.
	if pending_buy_cost <= 0.0 and is_instance_valid(_info_label):
		if can_sell and would_exceed:
			_info_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
			_info_label.text = "+%d credit (cap reached)" % int(remaining)
		elif can_sell:
			_info_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
			_info_label.text = "Selected: +%d credit" % int(min(credit_value, remaining))
		elif pending_credit_shortfall > 0.0:
			_info_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
			_info_label.text = "Need %d more credit" % int(pending_credit_shortfall)
		else:
			_info_label.text = ""

	# Sell button.
	if is_instance_valid(sell_button):
		sell_button.disabled = not can_sell
		if can_sell:
			sell_button.text = "Sell for Credit (+%d)" % int(min(credit_value, remaining))
		else:
			sell_button.text = "Sell for Credit"


# ---- Private helpers ----

func _reposition_sell_area() -> void:
	if _layout == null or not is_instance_valid(_deal_section):
		return
	var btn_y: float = _layout.below_deal_y(3.0)
	print("[TraderCredit] _reposition_sell_area — deal_bot_y=%.0f  btn_y=%.0f" \
		% [_layout.deal_bot_y, btn_y])
	if is_instance_valid(sell_button):
		sell_button.position = Vector2(0, btn_y)


func _hide_deal_label(node: Node) -> void:
	for child in node.get_children():
		if child is Label and child.text == "Deal":
			child.visible = false
			return
		_hide_deal_label(child)
