extends Node

# ============================================================
# Trader Credit — Main.gd
# Autoload registered as TraderCreditMain.
#
# How it works:
#   - The "Deal" section of the trader UI gains a second "Credit"
#     tab. Switching to it lets you sell selected items for
#     trader-specific credit instead of bartering.
#   - Credit can only be spent at the same trader.
#   - Credit cap scales with completed tasks for that trader.
#   - Credit decays by a small % per in-game day.
#   - Dying removes a % of credit (configurable).
#
# All settings are read from the TraderCreditConfig autoload,
# which is backed by MCM (falls back to defaults if MCM absent).
#
# Save file: user://trader_credit.cfg
# ============================================================

const SAVE_PATH := "user://trader_credit.cfg"

var _game_data = preload("res://Resources/GameData.tres")

# ---- Credit state (persisted) ----
var _credit: Dictionary = {}           # trader_name -> float
var _tasks_completed: Dictionary = {}  # trader_name -> int
var _last_decay_day: Dictionary = {}   # trader_name -> int

# ---- UI state (reset on respawn) ----
var _deal_tab_btn: Button = null
var _credit_tab_btn: Button = null
var _active_tab: int = 0
var _deal_section: Node = null         # original Deal node, reparented into wrapper
var _credit_panel: Control = null
var _credit_balance_label: Label = null
var _credit_earn_label: Label = null
var _credit_warn_label: Label = null
var _sell_credit_button: Button = null
var _ui_injected: bool = false
var _credit_buy_cost: float = 0.0  # credit owed on next accept click (0 = not a credit deal)

# ---- Internal ----
var _lib = null
var _config = null
var _was_dead: bool = false


func _ready() -> void:
	_config = get_tree().root.get_node("TraderCreditConfig")
	_load_save()
	Engine.set_meta("TraderCredit", self)

	if Engine.has_meta("RTVModLib"):
		var lib = Engine.get_meta("RTVModLib")
		if lib._is_ready:
			_on_lib_ready()
		else:
			lib.frameworks_ready.connect(_on_lib_ready)

	print("[TraderCredit] Loaded")


func _process(_delta: float) -> void:
	if _game_data.isDead and not _was_dead:
		_was_dead = true
		_on_player_died()
	elif not _game_data.isDead and _was_dead:
		_was_dead = false
		_load_save()


# Intercept left-clicks in our button rects before Interface.gd can swallow them.
func _input(event: InputEvent) -> void:
	if not _ui_injected:
		return
	if not (event is InputEventMouseButton):
		return
	var mbe: InputEventMouseButton = event
	if not mbe.pressed or mbe.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos := mbe.position
	if is_instance_valid(_deal_tab_btn) and _deal_tab_btn.get_global_rect().has_point(pos):
		print("[TraderCredit] _input: Barter tab clicked rect=%s" % _deal_tab_btn.get_global_rect())
		_switch_tab(0)
		get_viewport().set_input_as_handled()
	elif is_instance_valid(_credit_tab_btn) and _credit_tab_btn.get_global_rect().has_point(pos):
		print("[TraderCredit] _input: Credit tab clicked rect=%s" % _credit_tab_btn.get_global_rect())
		_switch_tab(1)
		get_viewport().set_input_as_handled()
	elif is_instance_valid(_sell_credit_button) and _active_tab == 1 and not _sell_credit_button.disabled and _sell_credit_button.get_global_rect().has_point(pos):
		print("[TraderCredit] _input: Sell for Credit clicked")
		_on_sell_credit_pressed()
		get_viewport().set_input_as_handled()
	elif _credit_buy_cost > 0.0:
		var iface = _get_interface()
		if iface and iface.trader and is_instance_valid(iface.acceptButton) \
				and not iface.acceptButton.disabled \
				and iface.acceptButton.get_global_rect().has_point(pos):
			var trader_name: String = iface.trader.traderData.name
			var cost := _credit_buy_cost
			_credit_buy_cost = 0.0
			if get_credit(trader_name) >= cost:
				spend_credit(trader_name, cost)
				iface.CompleteDeal()
				if is_instance_valid(iface.trader) and iface.trader.has_method("PlayTraderTrade"):
					iface.trader.PlayTraderTrade()
				iface.ResetTrading()
				print("[TraderCredit] credit buy: spent %.0f at %s" % [cost, trader_name])
				Loader.Message("Spent %d credit at %s" % [int(cost), trader_name], Color(0.35, 0.85, 1.0))
			else:
				iface.acceptButton.disabled = true
				Loader.Message("Not enough credit — balance changed.", Color.ORANGE)
			get_viewport().set_input_as_handled()


# ==============================================================
# Hook registration
# ==============================================================

func _on_lib_ready() -> void:
	_lib = Engine.get_meta("RTVModLib")
	_lib.hook("interface-open-post",          _on_interface_open)
	_lib.hook("interface-close-pre",          _on_interface_close)
	_lib.hook("interface-calculatedeal-post", _on_calculate_deal)
	_lib.hook("trader-completetask-post",     _on_task_completed)
	_apply_decay_all()
	print("[TraderCredit] Hooks registered")


# ==============================================================
# Death handling
# ==============================================================

func _on_player_died() -> void:
	if not _config.death_penalty_enabled:
		return

	if _game_data.permadeath:
		_credit.clear()
		_tasks_completed.clear()
		_last_decay_day.clear()
		_save()
		print("[TraderCredit] Permadeath — all credit wiped")
		return

	var factor: float = 1.0 - float(_config.death_penalty_percent) / 100.0
	for trader_name in _credit:
		_credit[trader_name] = floor(_credit[trader_name] * factor)
	_save()
	print("[TraderCredit] Death penalty — %.0f%% credit lost" % _config.death_penalty_percent)


# ==============================================================
# Task completion — updates credit cap
# ==============================================================

func _on_task_completed(_task_data = null) -> void:
	if _lib == null:
		return
	var trader_node = _lib._caller
	if trader_node == null or not is_instance_valid(trader_node):
		return
	if not "traderData" in trader_node or trader_node.traderData == null:
		return

	var trader_name: String = trader_node.traderData.name
	# Read the authoritative count from the Trader node so we never drift.
	var vanilla_count: int = trader_node.tasksCompleted.size()
	_tasks_completed[trader_name] = max(_tasks_completed.get(trader_name, 0) + 1, vanilla_count)
	_save()
	print("[TraderCredit] Task complete for %s — cap now %d" % [trader_name, get_credit_cap(trader_name)])


# ==============================================================
# Credit management (public API)
# ==============================================================

func get_credit(trader_name: String) -> float:
	return _credit.get(trader_name, 0.0)


func get_credit_cap(trader_name: String) -> int:
	return _tasks_completed.get(trader_name, 0) * _config.credit_per_task


func get_remaining_cap(trader_name: String) -> float:
	return max(0.0, float(get_credit_cap(trader_name)) - get_credit(trader_name))


func add_credit(trader_name: String, amount: float) -> float:
	var cap := float(get_credit_cap(trader_name))
	var current := get_credit(trader_name)
	var added := min(amount, cap - current)
	added = max(0.0, added)
	_credit[trader_name] = current + added
	_save()
	return added


func spend_credit(trader_name: String, amount: float) -> bool:
	var current := get_credit(trader_name)
	if amount > current:
		return false
	_credit[trader_name] = current - amount
	_save()
	return true


# ==============================================================
# Decay
# ==============================================================

func _apply_decay_all() -> void:
	if not _config.decay_enabled:
		return
	var current_day := _get_current_day()
	for trader_name in _credit.keys():
		_apply_decay_for_trader(trader_name, current_day)


func _apply_decay_for_trader(trader_name: String, current_day: int) -> void:
	if not _config.decay_enabled or current_day <= 0:
		return
	var last_day: int = _last_decay_day.get(trader_name, current_day)
	var days_elapsed := current_day - last_day
	if days_elapsed <= 0:
		return

	# Compound decay: credit *= (1 - rate)^days
	var rate: float = float(_config.decay_rate_per_day) / 100.0
	var factor: float = pow(1.0 - rate, days_elapsed)
	_credit[trader_name] = floor(_credit.get(trader_name, 0.0) * factor)
	_last_decay_day[trader_name] = current_day
	_save()


func _get_current_day() -> int:
	return int(Simulation.day)


# ==============================================================
# Interface helpers
# ==============================================================

func _get_interface():
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.get_node_or_null("Core/UI/Interface")


# Walks up from acceptButton until we reach a direct child of iface.
# That node is the "Deal" section container.
func _find_deal_section(iface) -> Node:
	if not iface or not is_instance_valid(iface.acceptButton):
		return null
	var node = iface.acceptButton
	while node and node.get_parent() != iface:
		node = node.get_parent()
	return node


# ==============================================================
# Hook callbacks
# ==============================================================

func _on_interface_open() -> void:
	var iface = _get_interface()
	if not iface or not iface.trader:
		return
	if not _ui_nodes_valid():
		_reset_ui_state()

	if not _ui_injected:
		_inject_ui(iface)

	if _config.decay_enabled:
		_apply_decay_for_trader(iface.trader.traderData.name, _get_current_day())

	_update_credit_tab(iface)


func _on_interface_close() -> void:
	_credit_buy_cost = 0.0
	_switch_tab(0)


func _on_calculate_deal() -> void:
	if not is_instance_valid(_deal_section):
		print("[TraderCredit] _on_calculate_deal: deal_section invalid, skipping")
		return

	_credit_buy_cost = 0.0

	var iface = _get_interface()
	if not iface or not iface.trader:
		return
	if not is_instance_valid(iface.acceptButton):
		print("[TraderCredit] _on_calculate_deal: acceptButton invalid")
		return

	var trader_name: String = iface.trader.traderData.name
	var balance := get_credit(trader_name)

	var raw_tax = iface.trader.get("tax")
	var tax: float = (float(raw_tax) * 0.01 + 1.0) if raw_tax != null else 1.0

	var request_val := 0.0
	var supply_selected := 0
	# TraderTabs replaces iface.supplyGrid with its own TT_TraderTabs node.
	var tt = iface.get_node_or_null("TT_TraderTabs")
	if tt and tt.has_method("get_all_grids"):
		for grid in tt.get_all_grids():
			for el in grid.get_children():
				if el.selected:
					supply_selected += 1
					if el.has_method("Value"):
						request_val += float(el.Value()) * tax
	elif iface.supplyGrid:
		for el in iface.supplyGrid.get_children():
			if el.selected:
				supply_selected += 1
				if el.has_method("Value"):
					request_val += float(el.Value()) * tax

	var offer_val := 0.0
	if iface.inventoryGrid:
		for el in iface.inventoryGrid.get_children():
			if el.selected and el.has_method("Value"):
				offer_val += float(el.Value())

	var deficit := request_val - offer_val
	print("[TraderCredit] calc: supply_sel=%d req=%.0f offer=%.0f deficit=%.0f balance=%.0f accept_disabled=%s tax=%.2f" % [
		supply_selected, request_val, offer_val, deficit, balance,
		str(iface.acceptButton.disabled), tax
	])

	if deficit > 0.0 and balance >= deficit:
		_credit_buy_cost = deficit
		# Defer so TraderTabs' CalculateDeal (which calls super first, firing this hook)
		# doesn't re-disable the button after we enable it.
		call_deferred("_deferred_apply_credit_enable")
		print("[TraderCredit] credit buy will enable: cost=%.0f" % deficit)

	if _active_tab == 1:
		_update_credit_tab(iface)


func _deferred_apply_credit_enable() -> void:
	if _credit_buy_cost <= 0.0:
		return
	var iface = _get_interface()
	if iface and is_instance_valid(iface.acceptButton):
		iface.acceptButton.disabled = false
		print("[TraderCredit] credit buy: accept enabled")


func _ui_nodes_valid() -> bool:
	return (
		is_instance_valid(_deal_tab_btn) and
		is_instance_valid(_credit_tab_btn) and
		is_instance_valid(_deal_section) and
		is_instance_valid(_credit_panel) and
		is_instance_valid(_sell_credit_button)
	)


func _reset_ui_state() -> void:
	_ui_injected = false
	_active_tab = 0
	_deal_tab_btn = null
	_credit_tab_btn = null
	_deal_section = null
	_credit_panel = null
	_credit_balance_label = null
	_credit_earn_label = null
	_credit_warn_label = null
	_sell_credit_button = null
	_credit_buy_cost = 0.0


# ==============================================================
# UI injection — tabbed Deal section
# ==============================================================

func _inject_ui(iface) -> void:
	if _ui_injected:
		return

	var deal_section := _find_deal_section(iface)
	if deal_section == null:
		push_warning("[TraderCredit] Could not find deal section — UI not injected")
		return

	# Compute wrapper rect from the Trader portrait panel and Character node.
	var trader_node = iface.get_node_or_null("Trader")
	var portrait    = trader_node.get_node_or_null("Panel") if trader_node else null
	var character   = iface.get_node_or_null("Character")
	var trader_pos: Vector2  = trader_node.position if trader_node else Vector2(768, 128)
	var portrait_h:  float   = portrait.size.y      if portrait    else 384.0
	var character_y: float   = character.position.y if character   else 768.0
	var wrapper_w:   float   = 384.0
	var wrapper_y:   float   = trader_pos.y + portrait_h + 20.0
	var wrapper_h:   float   = character_y - wrapper_y

	# Plain Control added directly to iface so no Container overrides our rect.
	var wrapper := Control.new()
	wrapper.name     = "TraderCreditWrapper"
	wrapper.position = Vector2(trader_pos.x, wrapper_y)
	wrapper.size     = Vector2(wrapper_w, wrapper_h)
	wrapper.z_index  = 100
	iface.add_child(wrapper)

	print("[TraderCredit] inject: wrapper pos=%s size=%s" % [wrapper.position, wrapper.size])

	# Tab row pinned to the top of the wrapper.
	var tab_row := HBoxContainer.new()
	tab_row.name     = "TraderCreditTabRow"
	tab_row.position = Vector2(0, 0)
	tab_row.size     = Vector2(wrapper_w, 32)
	tab_row.add_theme_constant_override("separation", 4)
	wrapper.add_child(tab_row)

	var deal_btn := Button.new()
	deal_btn.name                   = "DealTab"
	deal_btn.text                   = "Barter"
	deal_btn.custom_minimum_size    = Vector2(60, 28)
	deal_btn.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	deal_btn.focus_mode             = Control.FOCUS_NONE
	deal_btn.mouse_filter           = Control.MOUSE_FILTER_STOP
	deal_btn.pressed.connect(_switch_tab.bind(0))
	tab_row.add_child(deal_btn)
	_deal_tab_btn = deal_btn

	var credit_btn := Button.new()
	credit_btn.name                  = "CreditTab"
	credit_btn.text                  = "Credit"
	credit_btn.custom_minimum_size   = Vector2(60, 28)
	credit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credit_btn.focus_mode            = Control.FOCUS_NONE
	credit_btn.mouse_filter          = Control.MOUSE_FILTER_STOP
	credit_btn.pressed.connect(_switch_tab.bind(1))
	tab_row.add_child(credit_btn)
	_credit_tab_btn = credit_btn

	_switch_tab(0)

	# Content area below the tab row — deal section and credit panel share this rect.
	var content_y := 32.0
	var content_h := wrapper_h - 32.0

	# Pull deal section out of the Trader VBoxContainer into our wrapper.
	deal_section.reparent(wrapper)
	_hide_deal_label(deal_section)
	deal_section.set_anchor(SIDE_LEFT,   0.0)
	deal_section.set_anchor(SIDE_RIGHT,  0.0)
	deal_section.set_anchor(SIDE_TOP,    0.0)
	deal_section.set_anchor(SIDE_BOTTOM, 0.0)
	deal_section.position = Vector2(0, content_y)
	deal_section.size     = Vector2(wrapper_w, content_h)
	_deal_section = deal_section

	# Credit panel: same x/width as deal section but capped shorter — the credit
	# content (3 labels + button) doesn't need the full content area, and
	# stretching it to the Character panel border looks too tall.
	var credit_panel := _build_credit_panel()
	credit_panel.visible  = false
	credit_panel.position = Vector2(0, content_y)
	credit_panel.size     = Vector2(wrapper_w, min(content_h, 160.0))
	wrapper.add_child(credit_panel)
	_credit_panel = credit_panel

	_ui_injected = true
	_debug_wrapper_deferred(wrapper, tab_row)


func _debug_wrapper_deferred(wrapper: Control, tab_row: HBoxContainer) -> void:
	await get_tree().process_frame
	print("[TraderCredit] post-layout: wrapper pos=%s size=%s tab_row.global_pos=%s tab_row.size=%s" % [
		wrapper.position, wrapper.size, tab_row.global_position, tab_row.size
	])


func _hide_deal_label(node: Node) -> void:
	for child in node.get_children():
		if child is Label and child.text == "Deal":
			child.visible = false
			print("[TraderCredit] hid vanilla Deal label: %s" % child.get_path())
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

	# Current credit balance
	var balance_label := Label.new()
	balance_label.name = "CreditBalance"
	balance_label.add_theme_font_size_override("font_size", 14)
	balance_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	balance_label.text = "Credit: —"
	vbox.add_child(balance_label)
	_credit_balance_label = balance_label

	# Earn preview (how much the current selection would earn)
	var earn_label := Label.new()
	earn_label.name = "CreditEarn"
	earn_label.add_theme_font_size_override("font_size", 13)
	earn_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	earn_label.text = ""
	vbox.add_child(earn_label)
	_credit_earn_label = earn_label

	# Warning / hint text
	var warn_label := Label.new()
	warn_label.name = "CreditWarn"
	warn_label.add_theme_font_size_override("font_size", 12)
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1))
	warn_label.text = ""
	warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(warn_label)
	_credit_warn_label = warn_label

	# Flexible spacer pushes the button to the bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Sell for Credit button
	var btn := Button.new()
	btn.name = "SellForCredit"
	btn.text = "Sell for Credit"
	btn.disabled = true
	btn.pressed.connect(_on_sell_credit_pressed)
	vbox.add_child(btn)
	_sell_credit_button = btn

	return margin


func _switch_tab(idx: int) -> void:
	_active_tab = idx
	if is_instance_valid(_deal_section):
		_deal_section.visible = (idx == 0)
	if is_instance_valid(_credit_panel):
		_credit_panel.visible = (idx == 1)
	# Visual feedback: dim the inactive button
	if is_instance_valid(_deal_tab_btn):
		_deal_tab_btn.modulate = Color(1, 1, 1, 1.0) if idx == 0 else Color(1, 1, 1, 0.5)
	if is_instance_valid(_credit_tab_btn):
		_credit_tab_btn.modulate = Color(1, 1, 1, 1.0) if idx == 1 else Color(1, 1, 1, 0.5)
	if idx == 1:
		var iface = _get_interface()
		if iface and iface.trader:
			_update_credit_tab(iface)
	print("[TraderCredit] tab switched to %d" % idx)


func _update_credit_tab(iface) -> void:
	if not iface or not iface.trader:
		return
	if not is_instance_valid(_credit_balance_label):
		return

	var trader_name: String = iface.trader.traderData.name

	# Sync from vanilla in case tasks were completed before the mod was installed.
	# This is safe here because trader data is always loaded before the UI updates.
	var vanilla_count: int = iface.trader.tasksCompleted.size()
	if vanilla_count > _tasks_completed.get(trader_name, 0):
		_tasks_completed[trader_name] = vanilla_count
		_save()
		print("[TraderCredit] seeded %s tasks from vanilla: %d" % [trader_name, vanilla_count])
	var current      := get_credit(trader_name)
	var cap          := get_credit_cap(trader_name)
	var offer_value  := _selected_offer_value(iface, trader_name)
	var req_count    := _selected_request_count(iface)
	var credit_value: float = floor(offer_value * (1.0 - float(_config.sell_tax) / 100.0))
	var remaining    := get_remaining_cap(trader_name)

	# Balance line
	if cap == 0:
		_credit_balance_label.text = "Credit: — (complete tasks to unlock)"
	else:
		_credit_balance_label.text = "Credit: %d / %d" % [int(current), cap]

	# Earn preview line
	var can_sell := offer_value > 0 and req_count == 0 and cap > 0
	if can_sell:
		var actual_earn := min(credit_value, remaining)
		_credit_earn_label.text = "Selected: +%d credit" % int(actual_earn)
	else:
		_credit_earn_label.text = ""

	# Warning / hint line
	var would_exceed := (current + credit_value) > float(cap)
	if not can_sell:
		if cap == 0:
			_credit_warn_label.text = "Complete trader tasks to earn credit capacity."
		elif req_count > 0:
			_credit_warn_label.text = "Deselect trader items to sell for credit."
		else:
			_credit_warn_label.text = "Select items from your inventory to sell."
	elif would_exceed:
		_credit_warn_label.text = "Exceeds your credit limit — partial credit only."
	else:
		_credit_warn_label.text = ""

	# Button
	if is_instance_valid(_sell_credit_button):
		_sell_credit_button.disabled = not can_sell
		if can_sell:
			_sell_credit_button.text = "Sell for Credit (+%d)" % int(min(credit_value, remaining))
		else:
			_sell_credit_button.text = "Sell for Credit"


# ==============================================================
# Offer value helpers
# ==============================================================

func _selected_offer_value(iface, trader_name: String) -> int:
	var total := 0
	if not iface.inventoryGrid:
		return total
	for element in iface.inventoryGrid.get_children():
		if not element.selected:
			continue
		if not element.has_method("Value"):
			continue
		if _config.item_restriction == "trader_only" and not _item_accepted_by_trader(element, trader_name):
			continue
		total += int(element.Value())
	return total


# Returns true when the item has the trader's boolean pool flag set.
func _item_accepted_by_trader(element, trader_name: String) -> bool:
	if not element.slotData or not element.slotData.itemData:
		return false
	var flag := trader_name.to_lower()
	var item_data = element.slotData.itemData
	if not (flag in item_data):
		return true
	return bool(item_data.get(flag))


func _selected_request_count(iface) -> int:
	var n := 0
	if iface.supplyGrid:
		for element in iface.supplyGrid.get_children():
			if element.selected:
				n += 1
	return n


# ==============================================================
# "Sell for Credit" button handler
# ==============================================================

func _on_sell_credit_pressed() -> void:
	var iface = _get_interface()
	if not iface or not iface.trader:
		return

	var trader_name: String = iface.trader.traderData.name
	var offer_value := _selected_offer_value(iface, trader_name)
	if offer_value <= 0:
		return

	if get_remaining_cap(trader_name) <= 0.0:
		Loader.Message(
			"Credit limit reached with %s. Complete more tasks to raise it." % trader_name,
			Color.ORANGE
		)
		return

	var to_sell: Array = []
	for element in iface.inventoryGrid.get_children():
		if not element.selected:
			continue
		if not element.has_method("Value"):
			continue
		if _config.item_restriction == "trader_only" and not _item_accepted_by_trader(element, trader_name):
			continue
		to_sell.append(element)

	for element in to_sell:
		iface.inventoryGrid.Pick(element)
		element.queue_free()

	var credit_value: float = floor(offer_value * (1.0 - float(_config.sell_tax) / 100.0))
	var actual := add_credit(trader_name, credit_value)

	if is_instance_valid(iface.trader) and iface.trader.has_method("PlayTraderTrade"):
		iface.trader.PlayTraderTrade()

	var msg := "Earned %d credit with %s" % [int(actual), trader_name]
	if actual < credit_value:
		msg += " (cap reached)"
	Loader.Message(msg, Color(0.35, 0.85, 1.0))

	iface.ResetTrading()
	_update_credit_tab(iface)


# ==============================================================
# Persistence
# ==============================================================

func _save() -> void:
	var cfg := ConfigFile.new()
	for trader_name in _credit:
		cfg.set_value("credit", trader_name, _credit[trader_name])
	for trader_name in _tasks_completed:
		cfg.set_value("tasks", trader_name, _tasks_completed[trader_name])
	for trader_name in _last_decay_day:
		cfg.set_value("decay_day", trader_name, _last_decay_day[trader_name])
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_credit.clear()
	_tasks_completed.clear()
	_last_decay_day.clear()
	if cfg.has_section("credit"):
		for key in cfg.get_section_keys("credit"):
			_credit[key] = float(cfg.get_value("credit", key, 0.0))
	if cfg.has_section("tasks"):
		for key in cfg.get_section_keys("tasks"):
			_tasks_completed[key] = int(cfg.get_value("tasks", key, 0))
	if cfg.has_section("decay_day"):
		for key in cfg.get_section_keys("decay_day"):
			_last_decay_day[key] = int(cfg.get_value("decay_day", key, 0))
