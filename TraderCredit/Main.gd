extends Node

# ============================================================
# Trader Credit — Main.gd
# Autoload registered as TraderCreditMain.
#
# Thin coordinator: owns the lifecycle, hooks, and input
# interception. Business logic lives in CreditLedger; UI
# construction and state live in CreditUI; grid-reading
# utilities live in GridHelper.
# ============================================================

const GridHelper       = preload("res://mods/TraderCredit/GridHelper.gd")
const LedgerScene      = preload("res://mods/TraderCredit/CreditLedger.gd")
const UIScene          = preload("res://mods/TraderCredit/CreditUI.gd")
const TraderLayout     = preload("res://mods/TraderCredit/TraderLayout.gd")
const BuybackLedgerScene = preload("res://mods/TraderCredit/BuybackLedger.gd")
const BuybackUIScene   = preload("res://mods/TraderCredit/BuybackUI.gd")

var _game_data = preload("res://Resources/GameData.tres")

var _ledger: Node         = null   # CreditLedger instance
var _ui: Node             = null   # CreditUI instance
var _buyback_ledger: Node = null   # BuybackLedger instance
var _buyback_ui: Node     = null   # BuybackUI instance
var _config               = null
var _was_dead: bool         = false
var _credit_poll_timer: float = 0.0
var _buyback_tab_active: bool = false
var _buyback_poll_timer: float = 0.0
var _pending_buyback_sells: Array = []


func _ready() -> void:
	_config = get_tree().root.get_node_or_null("TraderCreditConfig")

	_ledger = LedgerScene.new()
	_ledger.name = "TraderCreditLedger"
	add_child(_ledger)

	_ui = UIScene.new()
	_ui.name = "TraderCreditUI"
	add_child(_ui)

	_buyback_ledger = BuybackLedgerScene.new()
	_buyback_ledger.name = "TraderCreditBuybackLedger"
	add_child(_buyback_ledger)

	_buyback_ui = BuybackUIScene.new()
	_buyback_ui.name = "TraderCreditBuybackUI"
	add_child(_buyback_ui)

	_buyback_ui.buyback_tab_activated.connect(_on_buyback_tab_activated)
	_buyback_ui.supply_tab_activated.connect(_on_supply_tab_activated)

	_ledger.load_state()
	_buyback_ledger.load_state()
	Engine.set_meta("TraderCredit", self)

	if Engine.has_meta("RTVModLib"):
		var lib = Engine.get_meta("RTVModLib")
		if lib._is_ready:
			_on_lib_ready()
		else:
			lib.frameworks_ready.connect(_on_lib_ready)

	print("[TraderCredit] Loaded")


func _process(delta: float) -> void:
	if _game_data.isDead and not _was_dead:
		_was_dead = true
		_on_player_died()
	elif not _game_data.isDead and _was_dead:
		_was_dead = false
		_ledger.load_state()

	if _ui.injected:
		_credit_poll_timer -= delta
		if _credit_poll_timer <= 0.0:
			_credit_poll_timer = 0.1
			var iface = GridHelper.get_interface(get_tree())
			if iface and iface.trader:
				_refresh_credit_panel(iface)

	if _buyback_tab_active and _buyback_ui.injected:
		_buyback_poll_timer -= delta
		if _buyback_poll_timer <= 0.0:
			_buyback_poll_timer = 0.1
			_refresh_buyback_button()


# Intercepts left-clicks before Interface.gd can swallow them.
func _input(event: InputEvent) -> void:
	if not _ui.injected:
		return
	if not (event is InputEventMouseButton):
		return
	var mbe: InputEventMouseButton = event
	if not mbe.pressed or mbe.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos := mbe.position

	if is_instance_valid(_ui.sell_button) \
			and _ui.sell_button.visible \
			and not _ui.sell_button.disabled \
			and _ui.sell_button.get_global_rect().has_point(pos):
		_execute_sell()
		get_viewport().set_input_as_handled()
	elif is_instance_valid(_ui.buy_back_button) \
			and _ui.buy_back_button.visible \
			and not _ui.buy_back_button.disabled \
			and _ui.buy_back_button.get_global_rect().has_point(pos):
		var iface = GridHelper.get_interface(get_tree())
		if iface and iface.trader:
			_execute_buyback(iface)
		get_viewport().set_input_as_handled()
	elif _buyback_tab_active and _buyback_ui.injected and _buyback_ui.try_click(pos):
		get_viewport().set_input_as_handled()
	else:
		var iface = GridHelper.get_interface(get_tree())
		if iface and iface.trader and is_instance_valid(iface.acceptButton) \
				and not iface.acceptButton.disabled \
				and iface.acceptButton.get_global_rect().has_point(pos):
			if _ui.pending_buy_cost > 0.0:
				_execute_credit_buy(iface)
				get_viewport().set_input_as_handled()
			elif _config.buyback_enabled:
				_snapshot_offer_for_buyback(iface)
				call_deferred("_commit_pending_buyback", iface.trader.traderData.name)


# ==============================================================
# Hook registration
# ==============================================================

func _on_lib_ready() -> void:
	var lib = Engine.get_meta("RTVModLib")
	lib.hook("interface-open-post",          _on_interface_open)
	lib.hook("interface-close-pre",          _on_interface_close)
	lib.hook("interface-calculatedeal-post", _on_calculate_deal)
	lib.hook("trader-completetask-post",     _on_task_completed)
	_ledger.apply_decay_all(_get_current_day())
	print("[TraderCredit] Hooks registered")


# ==============================================================
# Hook callbacks
# ==============================================================

func _on_interface_open() -> void:
	_ledger.load_state()
	_buyback_ledger.load_state()
	var iface = GridHelper.get_interface(get_tree())
	if not iface or not iface.trader:
		return

	if not _ui.is_valid():
		_ui.reset()

	if not _ui.injected:
		var deal_section := GridHelper.find_deal_section(iface)
		if deal_section == null:
			push_warning("[TraderCredit] Could not find deal section — UI not injected")
			return
		_ui.inject(iface, deal_section)

	_ui.show_wrapper()
	_ui.show_sell_mode()

	if _config.decay_enabled:
		_ledger.apply_decay_for_trader(iface.trader.traderData.name, _get_current_day())

	_refresh_credit_panel(iface)

	if _config.buyback_enabled:
		var trader_name: String = iface.trader.traderData.name
		_buyback_ledger.prune_expired(trader_name, _get_current_day())
		_buyback_ui.cleanup()
		_buyback_ui.inject(iface)
		if _buyback_ui.injected:
			call_deferred("_deferred_repopulate_buyback", trader_name, iface)


func _on_interface_close() -> void:
	_ui.pending_buy_cost         = 0.0
	_ui.pending_credit_shortfall = 0.0
	_ui.update_pending_cost(0.0)
	_ui.hide_wrapper()
	if Engine.has_meta("TraderCreditLayout"):
		Engine.remove_meta("TraderCreditLayout")
	_buyback_ui.cleanup()
	_buyback_tab_active = false


func _on_calculate_deal() -> void:
	if not _ui.injected:
		return

	_ui.pending_buy_cost         = 0.0
	_ui.pending_credit_shortfall = 0.0
	_ui.update_pending_cost(0.0)

	var iface = GridHelper.get_interface(get_tree())
	if not iface or not iface.trader or not is_instance_valid(iface.acceptButton):
		return

	var trader_name: String = iface.trader.traderData.name
	var balance: float      = _ledger.get_balance(trader_name)
	var raw_tax              = iface.trader.get("tax")
	var tax: float   = (float(raw_tax) * 0.01 + 1.0) if raw_tax != null else 1.0
	var supply_cost := GridHelper.get_supply_cost(iface, tax)
	var offer_value := GridHelper.get_raw_offer_value(iface)
	var deficit     := supply_cost - offer_value

	if deficit > 0.0 and balance >= deficit:
		_ui.pending_buy_cost = deficit
		_ui.update_pending_cost(deficit)
		# Defer so TraderTabs' CalculateDeal (which fires this hook inside super()) doesn't
		# re-disable the accept button after we enable it.
		call_deferred("_deferred_enable_accept")
	elif deficit > 0.0:
		_ui.pending_credit_shortfall = deficit - balance

	_refresh_credit_panel(iface)


func _deferred_enable_accept() -> void:
	if _ui.pending_buy_cost <= 0.0:
		return
	var iface = GridHelper.get_interface(get_tree())
	if iface and is_instance_valid(iface.acceptButton):
		iface.acceptButton.disabled = false


func _on_task_completed(_task_data = null) -> void:
	var lib = Engine.get_meta("RTVModLib") if Engine.has_meta("RTVModLib") else null
	if lib == null:
		return
	var trader_node = lib._caller
	if not is_instance_valid(trader_node):
		return
	if not "traderData" in trader_node or trader_node.traderData == null:
		return
	var trader_name: String = trader_node.traderData.name
	_ledger.set_task_count(trader_name, trader_node.tasksCompleted.size())
	var new_cap: int = _ledger.get_cap(trader_name)
	print("[TraderCredit] Task complete for %s — cap now %d" % [trader_name, new_cap])
	Loader.Message(
		"Credit cap with %s raised to %d" % [trader_name, new_cap],
		Color(0.35, 0.85, 1.0)
	)

	if _config.task_bonus_enabled and _task_data != null:
		_award_task_bonus(trader_name, _task_data)

	var iface = GridHelper.get_interface(get_tree())
	if iface and iface.trader and _ui.injected:
		_refresh_credit_panel(iface)


func _award_task_bonus(trader_name: String, task_data) -> void:
	var difficulty: String = str(task_data.get("difficulty", ""))
	var bonus: int = 0
	match difficulty:
		"Easy":         bonus = _config.task_bonus_easy
		"Intermediate": bonus = _config.task_bonus_intermediate
		"Hard":         bonus = _config.task_bonus_hard
		_:
			print("[TraderCredit] Unknown task difficulty '%s' — no bonus awarded" % difficulty)
			return

	if bonus <= 0:
		return

	var actual: float = _ledger.add_credit(trader_name, float(bonus))
	var msg := "Task bonus: +%d credit with %s" % [int(actual), trader_name]
	if actual < float(bonus):
		msg += " (cap reached)"
	Loader.Message(msg, Color(0.35, 0.85, 1.0))
	print("[TraderCredit] Task bonus awarded: %.0f credit to %s (%s task)" % [actual, trader_name, difficulty])


# ==============================================================
# Death handling
# ==============================================================

func _on_player_died() -> void:
	if not _config.death_penalty_enabled:
		return
	_ledger.apply_death_penalty(_game_data.permadeath, float(_config.death_penalty_percent))
	if _game_data.permadeath:
		print("[TraderCredit] Permadeath — all credit wiped")
	else:
		print("[TraderCredit] Death penalty — %.0f%% credit lost" % _config.death_penalty_percent)


# ==============================================================
# Transaction helpers
# ==============================================================

func _execute_credit_buy(iface) -> void:
	var trader_name: String = iface.trader.traderData.name
	var cost: float = _ui.pending_buy_cost
	_ui.pending_buy_cost = 0.0
	_ui.update_pending_cost(0.0)

	if _ledger.get_balance(trader_name) >= cost:
		if _config.buyback_enabled:
			_snapshot_offer_for_buyback(iface)
		_ledger.spend_credit(trader_name, cost)
		iface.CompleteDeal()
		if _config.buyback_enabled:
			_commit_pending_buyback(trader_name)
		if is_instance_valid(iface.trader) and iface.trader.has_method("PlayTraderTrade"):
			iface.trader.PlayTraderTrade()
		iface.ResetTrading()
		print("[TraderCredit] credit buy: spent %.0f at %s" % [cost, trader_name])
		Loader.Message("Spent %d credit at %s" % [int(cost), trader_name], Color(0.35, 0.85, 1.0))
		_refresh_credit_panel(iface)
	else:
		iface.acceptButton.disabled = true
		Loader.Message("Not enough credit — balance changed.", Color.ORANGE)


func _execute_sell() -> void:
	var iface = GridHelper.get_interface(get_tree())
	if not iface or not iface.trader:
		return

	var trader_name: String = iface.trader.traderData.name
	var offer_value := GridHelper.get_offer_value(iface, trader_name, _config.item_restriction)
	if offer_value <= 0:
		return

	if _ledger.get_remaining_cap(trader_name) <= 0.0:
		Loader.Message(
			"Credit limit reached with %s. Complete more tasks to raise it." % trader_name,
			Color.ORANGE
		)
		return

	var sell_tax_factor: float = 1.0 - float(_config.sell_tax) / 100.0
	for element in GridHelper.get_sellable_elements(iface, trader_name, _config.item_restriction):
		if _config.buyback_enabled and element.slotData != null:
			var item_credit: float = floor(float(element.Value()) * sell_tax_factor)
			_buyback_ledger.add_entry(trader_name, element.slotData, item_credit, _get_current_day())
		iface.inventoryGrid.Pick(element)
		element.queue_free()

	var credit_value: float = floor(offer_value * sell_tax_factor)
	var actual: float = _ledger.add_credit(trader_name, credit_value)

	if is_instance_valid(iface.trader) and iface.trader.has_method("PlayTraderTrade"):
		iface.trader.PlayTraderTrade()

	var msg := "Earned %d credit with %s" % [int(actual), trader_name]
	if actual < credit_value:
		msg += " (cap reached)"
	Loader.Message(msg, Color(0.35, 0.85, 1.0))

	iface.ResetTrading()
	_refresh_credit_panel(iface)

	if _config.buyback_enabled and _buyback_ui.injected:
		call_deferred("_deferred_repopulate_buyback", trader_name, iface)


# ==============================================================
# Panel refresh
# ==============================================================

func _refresh_credit_panel(iface) -> void:
	if not iface or not iface.trader:
		return

	var trader_name: String = iface.trader.traderData.name

	# Catch up task count for players who installed the mod after completing tasks.
	_ledger.sync_task_count(trader_name, iface.trader.tasksCompleted.size())

	# Suppress offer/barter info while the buyback tab is active — inventory
	# selections there are partial payment, not a sell action.
	var offer_val: float = 0.0
	var supply_cnt: int  = 0
	if not _buyback_tab_active:
		offer_val  = GridHelper.get_offer_value(iface, trader_name, _config.item_restriction)
		supply_cnt = GridHelper.get_supply_selected_count(iface)

	_ui.update_panel(
		_ledger.get_balance(trader_name),
		_ledger.get_cap(trader_name),
		_ledger.get_remaining_cap(trader_name),
		offer_val,
		supply_cnt,
		float(_config.sell_tax)
	)


# ==============================================================
# Buyback
# ==============================================================

func _on_buyback_tab_activated() -> void:
	_buyback_tab_active = true
	_ui.show_buyback_mode(0.0)
	var iface = GridHelper.get_interface(get_tree())
	if iface and iface.has_method("ResetTrading"):
		iface.ResetTrading()
	_refresh_buyback_button()


func _on_supply_tab_activated() -> void:
	_buyback_tab_active = false
	_ui.show_sell_mode()
	var iface = GridHelper.get_interface(get_tree())
	if iface and iface.trader:
		_refresh_credit_panel(iface)


func _refresh_buyback_button() -> void:
	var iface = GridHelper.get_interface(get_tree())
	if not iface or not iface.trader:
		return
	var trader_name: String = iface.trader.traderData.name
	var selected: Array = _buyback_ui.get_selected()
	if selected.is_empty():
		_ui.show_buyback_mode(0.0)
		_ui.set_buyback_info("")
		return
	var entries: Array = _buyback_ledger.get_entries(trader_name)
	var total_cost := 0.0
	for item in selected:
		var idx: int = item["idx"]
		if idx < entries.size():
			total_cost += _buyback_ledger.get_buyback_cost(entries[idx])

	# Subtract value of any selected inventory items (after sell tax).
	var sell_tax_factor: float = 1.0 - float(_config.sell_tax) / 100.0
	var offer_value := 0.0
	if is_instance_valid(iface.inventoryGrid):
		for el in iface.inventoryGrid.get_children():
			if el.get("selected") == true and el.get("slotData") != null:
				offer_value += float(el.Value()) * sell_tax_factor
	var credit_needed: float = max(0.0, total_cost - offer_value)
	var balance: float = _ledger.get_balance(trader_name)
	var can_afford: bool = balance >= credit_needed
	_ui.show_buyback_mode(total_cost, can_afford)

	# Info label — shows breakdown or what's missing.
	if not can_afford:
		var shortfall: float = credit_needed - balance
		_ui.set_buyback_info("Need %d more credit" % int(shortfall), Color(1.0, 0.65, 0.1))
	elif offer_value > 0.0 and credit_needed <= 0.0:
		_ui.set_buyback_info("Items cover full cost", Color(0.45, 1.0, 0.45))
	elif offer_value > 0.0:
		_ui.set_buyback_info("Items offset %d cr → using %d credit" % [int(offer_value), int(credit_needed)], Color(0.75, 0.95, 0.75))
	else:
		_ui.set_buyback_info("")


func _execute_buyback(iface) -> void:
	var trader_name: String = iface.trader.traderData.name
	var entries: Array = _buyback_ledger.get_entries(trader_name)
	var selected: Array = _buyback_ui.get_selected()

	if selected.is_empty():
		return

	# Collect valid (idx, entry, cost, item_data) tuples — load resources here so
	# step 4 doesn't need to re-load and any bad paths fail before the transaction starts.
	var pairs: Array = []
	var total_cost := 0.0
	for item in selected:
		var idx: int = item["idx"]
		if idx >= entries.size():
			continue
		var entry: Dictionary = entries[idx]
		var item_data = load(entry["resource_path"])
		if item_data == null:
			push_warning("[TraderCredit] buyback: failed to load %s — skipping" % entry["resource_path"])
			continue
		var cost: int = _buyback_ledger.get_buyback_cost(entry)
		total_cost += cost
		pairs.append({"idx": idx, "entry": entry, "cost": cost, "item_data": item_data})

	if pairs.is_empty():
		return

	# Collect selected inventory items that will offset the cost.
	var sell_tax_factor: float = 1.0 - float(_config.sell_tax) / 100.0
	var offered_elements: Array = []
	var offer_value := 0.0
	if is_instance_valid(iface.inventoryGrid):
		for el in iface.inventoryGrid.get_children():
			if el.get("selected") == true and el.get("slotData") != null:
				offer_value += float(el.Value()) * sell_tax_factor
				offered_elements.append(el)

	var credit_shortfall: float = max(0.0, total_cost - offer_value)

	if _ledger.get_balance(trader_name) < credit_shortfall:
		Loader.Message("Not enough credit to buy back selected items.", Color.ORANGE)
		return

	# 1. Remove the original buyback entries FIRST — before anything else touches
	#    the ledger, so indices are still valid and any hooks triggered by later
	#    steps (iface.Create, etc.) see the already-updated ledger.
	var indices: Array = pairs.map(func(p): return p["idx"])
	indices.sort_custom(func(a, b): return a > b)
	for idx in indices:
		_buyback_ledger.remove_entry(trader_name, idx)

	# 2. Remove offered inventory items and capture rare+ ones in buyback ledger.
	var current_day: int = _get_current_day()
	for el in offered_elements:
		var sd = el.slotData
		if sd != null and sd.itemData != null:
			var credit_val: float = floor(float(el.Value()) * sell_tax_factor)
			if _config.buyback_enabled and sd.itemData.rarity >= _config.buyback_min_rarity:
				_buyback_ledger.add_entry(trader_name, sd, credit_val, current_day)
		if iface.inventoryGrid.has_method("Pick"):
			iface.inventoryGrid.Pick(el)
		el.queue_free()

	# 3. Spend credit and play audio.
	if credit_shortfall > 0.0:
		_ledger.spend_credit(trader_name, credit_shortfall)

	if is_instance_valid(iface.trader) and iface.trader.has_method("PlayTraderTrade"):
		iface.trader.PlayTraderTrade()

	# 4. Give bought-back items to the player (ledger is already clean at this point).
	for pair in pairs:
		var slot = SlotData.new()
		slot.itemData  = pair["item_data"]
		slot.condition = pair["entry"]["condition"]
		slot.amount    = pair["entry"]["amount"]
		iface.Create(slot, iface.inventoryGrid, true)

	# Repopulate the buyback grid with remaining entries.
	_buyback_ui.clear_grid()
	var remaining: Array = _buyback_ledger.get_entries(trader_name)
	_buyback_ui.populate(remaining, iface, _get_current_day())
	_ui.show_buyback_mode(0.0)

	var msg: String
	if offer_value > 0.0 and credit_shortfall > 0.0:
		msg = "Bought back %d item(s) using items + %d credit" % [pairs.size(), int(credit_shortfall)]
	elif offer_value > 0.0:
		msg = "Bought back %d item(s) using items (no credit needed)" % pairs.size()
	else:
		msg = "Bought back %d item(s) for %d credit" % [pairs.size(), int(credit_shortfall)]
	Loader.Message(msg, Color(0.35, 0.85, 1.0))
	print("[TraderCredit] %s" % msg)
	_refresh_credit_panel(iface)


func _snapshot_offer_for_buyback(iface) -> void:
	_pending_buyback_sells.clear()
	var sell_tax_factor: float = 1.0 - float(_config.sell_tax) / 100.0
	for el in iface.inventoryGrid.get_children():
		if el.get("selected") != true or el.slotData == null or el.slotData.itemData == null:
			continue
		var credit_val: float = floor(float(el.Value()) * sell_tax_factor)
		_pending_buyback_sells.append({"slot_data": el.slotData, "credit_paid": credit_val})


func _commit_pending_buyback(trader_name: String) -> void:
	if _pending_buyback_sells.is_empty():
		return
	var day := _get_current_day()
	for item in _pending_buyback_sells:
		_buyback_ledger.add_entry(trader_name, item["slot_data"], item["credit_paid"], day)
	_pending_buyback_sells.clear()
	if _buyback_ui.injected:
		var iface = GridHelper.get_interface(get_tree())
		if iface:
			call_deferred("_deferred_repopulate_buyback", trader_name, iface)


# ==============================================================
# Utilities
# ==============================================================

func _get_current_day() -> int:
	return int(Simulation.day)


func _deferred_repopulate_buyback(trader_name: String, iface) -> void:
	if not is_instance_valid(_buyback_ui) or not _buyback_ui.injected:
		return
	if not is_instance_valid(iface):
		return
	_buyback_ui.populate(_buyback_ledger.get_entries(trader_name), iface, _get_current_day())
