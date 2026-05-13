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

const GridHelper  = preload("res://TraderCredit/GridHelper.gd")
const LedgerScene = preload("res://TraderCredit/CreditLedger.gd")
const UIScene     = preload("res://TraderCredit/CreditUI.gd")

var _game_data = preload("res://Resources/GameData.tres")

var _ledger: Node = null   # CreditLedger instance
var _ui: Node     = null   # CreditUI instance
var _config       = null
var _was_dead: bool = false


func _ready() -> void:
	_config = get_tree().root.get_node("TraderCreditConfig")

	_ledger = LedgerScene.new()
	_ledger.name = "TraderCreditLedger"
	add_child(_ledger)

	_ui = UIScene.new()
	_ui.name = "TraderCreditUI"
	add_child(_ui)

	_ledger.load_state()
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
		_ledger.load_state()


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

	if is_instance_valid(_ui.barter_tab_btn) and _ui.barter_tab_btn.get_global_rect().has_point(pos):
		_ui.switch_tab(0)
		get_viewport().set_input_as_handled()
	elif is_instance_valid(_ui.credit_tab_btn) and _ui.credit_tab_btn.get_global_rect().has_point(pos):
		_ui.switch_tab(1)
		get_viewport().set_input_as_handled()
	elif is_instance_valid(_ui.sell_button) and _ui.active_tab == 1 \
			and not _ui.sell_button.disabled \
			and _ui.sell_button.get_global_rect().has_point(pos):
		_execute_sell()
		get_viewport().set_input_as_handled()
	elif _ui.pending_buy_cost > 0.0:
		var iface = GridHelper.get_interface(get_tree())
		if iface and iface.trader and is_instance_valid(iface.acceptButton) \
				and not iface.acceptButton.disabled \
				and iface.acceptButton.get_global_rect().has_point(pos):
			_execute_credit_buy(iface)
			get_viewport().set_input_as_handled()


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

	if _config.decay_enabled:
		_ledger.apply_decay_for_trader(iface.trader.traderData.name, _get_current_day())

	_refresh_credit_panel(iface)


func _on_interface_close() -> void:
	_ui.pending_buy_cost = 0.0
	_ui.switch_tab(0)


func _on_calculate_deal() -> void:
	if not _ui.injected:
		return

	_ui.pending_buy_cost = 0.0

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
		# Defer so TraderTabs' CalculateDeal (which fires this hook inside super()) doesn't
		# re-disable the accept button after we enable it.
		call_deferred("_deferred_enable_accept")

	if _ui.active_tab == 1:
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

	if _ledger.get_balance(trader_name) >= cost:
		_ledger.spend_credit(trader_name, cost)
		iface.CompleteDeal()
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

	for element in GridHelper.get_sellable_elements(iface, trader_name, _config.item_restriction):
		iface.inventoryGrid.Pick(element)
		element.queue_free()

	var credit_value: float = floor(offer_value * (1.0 - float(_config.sell_tax) / 100.0))
	var actual: float = _ledger.add_credit(trader_name, credit_value)

	if is_instance_valid(iface.trader) and iface.trader.has_method("PlayTraderTrade"):
		iface.trader.PlayTraderTrade()

	var msg := "Earned %d credit with %s" % [int(actual), trader_name]
	if actual < credit_value:
		msg += " (cap reached)"
	Loader.Message(msg, Color(0.35, 0.85, 1.0))

	iface.ResetTrading()
	_refresh_credit_panel(iface)


# ==============================================================
# Panel refresh
# ==============================================================

func _refresh_credit_panel(iface) -> void:
	if not iface or not iface.trader:
		return

	var trader_name: String = iface.trader.traderData.name

	# Catch up task count for players who installed the mod after completing tasks.
	_ledger.sync_task_count(trader_name, iface.trader.tasksCompleted.size())

	_ui.update_panel(
		_ledger.get_balance(trader_name),
		_ledger.get_cap(trader_name),
		_ledger.get_remaining_cap(trader_name),
		GridHelper.get_offer_value(iface, trader_name, _config.item_restriction),
		GridHelper.get_supply_selected_count(iface),
		float(_config.sell_tax)
	)


# ==============================================================
# Utilities
# ==============================================================

func _get_current_day() -> int:
	return int(Simulation.day)
