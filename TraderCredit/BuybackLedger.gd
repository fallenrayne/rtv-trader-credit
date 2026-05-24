extends Node

# Owns buyback state — items the player recently sold for credit that can
# be repurchased during the expiry window.
# Instantiated as a child node of TraderCreditMain.
#
# Entry schema (Dictionary):
#   resource_path : String  — res:// path to the ItemData .tres
#   condition     : float   — stored as-is (game uses 0–1 or 0–100 depending on item)
#   amount        : int     — stack size
#   credit_paid   : float   — credit the player received for this item
#   sell_day      : int     — in-game day the item was sold

const SAVE_PATH      := "user://trader_credit.tres"
const MAX_HARD_CAP   := 50   # absolute ceiling regardless of config

# trader_name -> Array[Dictionary], newest entry first
var _entries: Dictionary = {}

var _config = null
var _save_pending: bool = false


func _ready() -> void:
	_config = get_tree().root.get_node_or_null("TraderCreditConfig")


# ---- Public write API ----

func add_entry(trader_name: String, slot_data, credit_paid: float, sell_day: int) -> void:
	if slot_data == null or slot_data.itemData == null:
		return
	var min_rarity: int = _config.buyback_min_rarity if _config != null else 1
	if slot_data.itemData.rarity < min_rarity:
		return

	var entry := {
		"resource_path": slot_data.itemData.resource_path,
		"condition":     slot_data.condition,
		"amount":        slot_data.amount,
		"credit_paid":   credit_paid,
		"sell_day":      sell_day,
	}

	if not _entries.has(trader_name):
		_entries[trader_name] = []

	var arr: Array = _entries[trader_name]
	arr.push_front(entry)

	var cap: int = min(
		_config.buyback_max_entries if _config != null else 20,
		MAX_HARD_CAP
	)
	while arr.size() > cap:
		arr.pop_back()

	_schedule_save()


func remove_entry(trader_name: String, idx: int) -> void:
	if not _entries.has(trader_name):
		return
	var arr: Array = _entries[trader_name]
	if idx < 0 or idx >= arr.size():
		return
	arr.remove_at(idx)
	_schedule_save()


func prune_expired(trader_name: String, current_day: int) -> void:
	if not _entries.has(trader_name):
		return
	var expiry: int = _config.buyback_expiry_days if _config != null else 7
	var before: int = _entries[trader_name].size()
	_entries[trader_name] = _entries[trader_name].filter(
		func(e): return (current_day - int(e["sell_day"])) < expiry
	)
	if _entries[trader_name].size() < before:
		_schedule_save()


# ---- Public read API ----

func get_entries(trader_name: String) -> Array:
	return _entries.get(trader_name, []).duplicate()


func get_buyback_cost(entry: Dictionary) -> int:
	var fee: float = _config.buyback_fee_percent if _config != null else 5.0
	return int(ceil(float(entry["credit_paid"]) * (1.0 + fee / 100.0)))


func days_remaining(entry: Dictionary, current_day: int) -> int:
	var expiry: int = _config.buyback_expiry_days if _config != null else 7
	return max(0, expiry - (current_day - int(entry["sell_day"])))


# ---- Persistence ----

# Deduplicates save calls within a single frame — multiple add/remove ops in one
# transaction result in a single disk write at frame end.
func _schedule_save() -> void:
	if not _save_pending:
		_save_pending = true
		call_deferred("_flush_save")


func _flush_save() -> void:
	_save_pending = false
	save_state()


# Load-modify-save so we don't clobber credit/task sections written by CreditLedger.
func save_state() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("[TraderCredit] BuybackLedger: save aborted — could not load %s (err %d)" % [SAVE_PATH, err])
		return

	# Clear stale buyback sections.
	for section: String in cfg.get_sections():
		if section.begins_with("buyback_"):
			cfg.erase_section(section)

	for trader_name in _entries:
		var arr: Array = _entries[trader_name]
		if arr.is_empty():
			continue
		var section: String = "buyback_" + str(trader_name)
		for i in arr.size():
			cfg.set_value(section, str(i), arr[i])

	cfg.save(SAVE_PATH)


func load_state() -> void:
	_entries.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	for section: String in cfg.get_sections():
		if not section.begins_with("buyback_"):
			continue
		var trader_name: String = section.substr("buyback_".length())
		var keys: Array = cfg.get_section_keys(section)
		keys.sort_custom(func(a, b): return int(a) < int(b))
		var arr: Array = []
		for key in keys:
			var val = cfg.get_value(section, key, null)
			if val is Dictionary:
				arr.append(val)
		_entries[trader_name] = arr
