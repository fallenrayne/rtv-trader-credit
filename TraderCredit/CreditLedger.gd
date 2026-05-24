extends Node

# Owns all credit state and business rules.
# Persisted to SAVE_PATH as a ConfigFile.
# Instantiated as a child node of TraderCreditMain.

const SAVE_PATH     := "user://trader_credit.tres"
const SAVE_PATH_OLD := "user://trader_credit.cfg"

var _balances: Dictionary = {}      # trader_name -> float
var _task_counts: Dictionary = {}   # trader_name -> int
var _last_decay_day: Dictionary = {} # trader_name -> int

var _config = null


func _ready() -> void:
	_config = get_tree().root.get_node_or_null("TraderCreditConfig")


# ---- Public read API ----

func get_balance(trader_name: String) -> float:
	return _balances.get(trader_name, 0.0)


func get_cap(trader_name: String) -> int:
	if _config == null:
		return 0
	var cap: int = _task_counts.get(trader_name, 0) * _config.credit_per_task
	if _config.credit_cap_max > 0:
		cap = min(cap, _config.credit_cap_max)
	return cap


func get_remaining_cap(trader_name: String) -> float:
	return max(0.0, float(get_cap(trader_name)) - get_balance(trader_name))


# ---- Public write API ----

func add_credit(trader_name: String, amount: float) -> float:
	var cap     := float(get_cap(trader_name))
	var current := get_balance(trader_name)
	var added   := max(0.0, min(amount, cap - current))
	_balances[trader_name] = current + added
	save_state()
	return added


func spend_credit(trader_name: String, amount: float) -> bool:
	var current := get_balance(trader_name)
	if amount > current:
		return false
	_balances[trader_name] = current - amount
	save_state()
	return true


# Writes vanilla task count when it is ahead of what we recorded (catch-up on first install).
# Returns true if the count was updated.
func sync_task_count(trader_name: String, vanilla_count: int) -> bool:
	if vanilla_count > _task_counts.get(trader_name, 0):
		_task_counts[trader_name] = vanilla_count
		save_state()
		return true
	return false


func set_task_count(trader_name: String, count: int) -> void:
	_task_counts[trader_name] = count
	save_state()


# ---- Death penalty ----

func apply_death_penalty(is_permadeath: bool, penalty_percent: float) -> void:
	if is_permadeath:
		_balances.clear()
		_task_counts.clear()
		_last_decay_day.clear()
	else:
		var factor: float = 1.0 - penalty_percent / 100.0
		for trader_name in _balances:
			_balances[trader_name] = floor(_balances[trader_name] * factor)
	save_state()


# ---- Decay ----

func apply_decay_all(current_day: int) -> void:
	for trader_name in _balances.keys():
		apply_decay_for_trader(trader_name, current_day)


func apply_decay_for_trader(trader_name: String, current_day: int) -> void:
	if _config == null or not _config.decay_enabled or current_day <= 0:
		return
	if not _last_decay_day.has(trader_name):
		_last_decay_day[trader_name] = current_day
		save_state()
		return
	var last_day: int = _last_decay_day[trader_name]
	var days_elapsed  := current_day - last_day
	if days_elapsed <= 0:
		return
	var rate: float      = float(_config.decay_rate_per_day) / 100.0
	var factor: float    = pow(1.0 - rate, days_elapsed)
	var new_balance: float = floor(_balances.get(trader_name, 0.0) * factor)

	if _config.decay_floor_percent > 0.0:
		var floor_amount: float = float(get_cap(trader_name)) * (_config.decay_floor_percent / 100.0)
		new_balance = max(new_balance, floor_amount)

	_balances[trader_name] = new_balance
	_last_decay_day[trader_name] = current_day
	save_state()


# ---- Persistence ----

func save_state() -> void:
	# Load-modify-save so buyback sections written by BuybackLedger are preserved.
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	for section in ["credit", "tasks", "decay_day"]:
		if cfg.has_section(section):
			cfg.erase_section(section)
	for trader_name in _balances:
		cfg.set_value("credit",    trader_name, _balances[trader_name])
	for trader_name in _task_counts:
		cfg.set_value("tasks",     trader_name, _task_counts[trader_name])
	for trader_name in _last_decay_day:
		cfg.set_value("decay_day", trader_name, _last_decay_day[trader_name])
	cfg.save(SAVE_PATH)


func load_state() -> void:
	_balances.clear()
	_task_counts.clear()
	_last_decay_day.clear()
	var cfg := ConfigFile.new()
	var migrating := false
	if cfg.load(SAVE_PATH) != OK:
		if cfg.load(SAVE_PATH_OLD) != OK:
			return
		migrating = true
	if cfg.has_section("credit"):
		for key in cfg.get_section_keys("credit"):
			_balances[key]      = float(cfg.get_value("credit",    key, 0.0))
	if cfg.has_section("tasks"):
		for key in cfg.get_section_keys("tasks"):
			_task_counts[key]   = int(  cfg.get_value("tasks",     key, 0))
	if cfg.has_section("decay_day"):
		for key in cfg.get_section_keys("decay_day"):
			_last_decay_day[key] = int( cfg.get_value("decay_day", key, 0))
	if migrating:
		save_state()
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove("trader_credit.cfg")
		print("[TraderCredit] Migrated save data from .cfg to .tres")
