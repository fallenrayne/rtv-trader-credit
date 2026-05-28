extends GutTest

var _ledger: Node
var _config: Node


func _make_slot(path: String, rarity: int = 1, condition: float = 0.9, amount: int = 1) -> SlotData:
	var item := MockItemData.new()
	item.set("resource_path", path)  # native Resource property; can't assign via GDScript member access
	item.rarity = rarity
	var slot := SlotData.new()
	slot.itemData  = item
	slot.condition = condition
	slot.amount    = amount
	return slot


func before_each() -> void:
	_config = preload("res://stubs/MockConfig.gd").new()
	_ledger = preload("res://mods/TraderCredit/BuybackLedger.gd").new()
	add_child_autofree(_ledger)
	_ledger._config = _config  # inject directly — avoids stale-node issues with tree lookup


func after_each() -> void:
	if is_instance_valid(_config):
		_config.free()


# --- rarity filter ---

func test_below_rarity_threshold_not_tracked() -> void:
	_config.buyback_min_rarity = 1
	_ledger.add_entry("Generalist", _make_slot("res://items/junk.tres", 0), 100.0, 1)
	assert_eq(_ledger.get_entries("Generalist").size(), 0)


func test_at_rarity_threshold_is_tracked() -> void:
	_config.buyback_min_rarity = 1
	_ledger.add_entry("Generalist", _make_slot("res://items/pistol.tres", 1), 100.0, 1)
	assert_eq(_ledger.get_entries("Generalist").size(), 1)


func test_above_rarity_threshold_is_tracked() -> void:
	_config.buyback_min_rarity = 1
	_ledger.add_entry("Generalist", _make_slot("res://items/legendary.tres", 2), 200.0, 1)
	assert_eq(_ledger.get_entries("Generalist").size(), 1)


func test_min_rarity_zero_tracks_everything() -> void:
	_config.buyback_min_rarity = 0
	_ledger.add_entry("Generalist", _make_slot("res://items/junk.tres", 0), 10.0, 1)
	assert_eq(_ledger.get_entries("Generalist").size(), 1)


func test_null_slot_data_is_ignored() -> void:
	_ledger.add_entry("Generalist", null, 100.0, 1)
	assert_eq(_ledger.get_entries("Generalist").size(), 0)


# --- entry fields ---

func test_entry_stores_correct_fields() -> void:
	var slot := _make_slot("res://items/pistol.tres", 1, 0.75, 3)
	_ledger.add_entry("Generalist", slot, 150.0, 5)
	var entries: Array = _ledger.get_entries("Generalist")
	assert_eq(entries.size(), 1)
	var e: Dictionary = entries[0]
	assert_eq(e["resource_path"], "res://items/pistol.tres")
	assert_eq(e["condition"],     0.75)
	assert_eq(e["amount"],        3)
	assert_eq(e["credit_paid"],   150.0)
	assert_eq(e["sell_day"],      5)


# --- max entries ---

func test_max_entries_cap_enforced() -> void:
	_config.buyback_max_entries = 3
	for i in range(5):
		_ledger.add_entry("Generalist", _make_slot("res://items/item_%d.tres" % i), 100.0, 1)
	assert_eq(_ledger.get_entries("Generalist").size(), 3)


func test_oldest_entry_dropped_when_full() -> void:
	_config.buyback_max_entries = 2
	_ledger.add_entry("Generalist", _make_slot("res://items/a.tres"), 10.0, 1)
	_ledger.add_entry("Generalist", _make_slot("res://items/b.tres"), 20.0, 1)
	_ledger.add_entry("Generalist", _make_slot("res://items/c.tres"), 30.0, 1)
	var entries: Array = _ledger.get_entries("Generalist")
	# newest-first: c, b — a dropped
	assert_eq(entries[0]["resource_path"], "res://items/c.tres")
	assert_eq(entries[1]["resource_path"], "res://items/b.tres")


func test_entries_are_per_trader() -> void:
	_ledger.add_entry("Generalist", _make_slot("res://items/a.tres"), 100.0, 1)
	_ledger.add_entry("Doctor",     _make_slot("res://items/b.tres"), 100.0, 1)
	assert_eq(_ledger.get_entries("Generalist").size(), 1)
	assert_eq(_ledger.get_entries("Doctor").size(),     1)
	assert_eq(_ledger.get_entries("Gunsmith").size(),   0)


# --- expiry / prune ---

func test_prune_removes_expired_entry() -> void:
	_config.buyback_expiry_days = 7
	_ledger.add_entry("Generalist", _make_slot("res://items/old.tres"), 100.0, 1)
	_ledger.prune_expired("Generalist", 8)   # 7 days elapsed → expired
	assert_eq(_ledger.get_entries("Generalist").size(), 0)


func test_prune_keeps_unexpired_entry() -> void:
	_config.buyback_expiry_days = 7
	_ledger.add_entry("Generalist", _make_slot("res://items/recent.tres"), 100.0, 5)
	_ledger.prune_expired("Generalist", 8)   # 3 days elapsed → still valid
	assert_eq(_ledger.get_entries("Generalist").size(), 1)


func test_prune_on_exact_expiry_day_removes_entry() -> void:
	_config.buyback_expiry_days = 7
	_ledger.add_entry("Generalist", _make_slot("res://items/edge.tres"), 100.0, 1)
	_ledger.prune_expired("Generalist", 8)   # 7 days elapsed = exactly expired
	assert_eq(_ledger.get_entries("Generalist").size(), 0)


func test_prune_empty_trader_is_safe() -> void:
	_ledger.prune_expired("Generalist", 10)  # no entries — should not crash
	assert_eq(_ledger.get_entries("Generalist").size(), 0)


func test_days_remaining_mid_window() -> void:
	_config.buyback_expiry_days = 7
	var entry := {"sell_day": 3, "credit_paid": 100.0}
	assert_eq(_ledger.days_remaining(entry, 6), 4)   # 7 - (6-3) = 4


func test_days_remaining_clamps_to_zero_when_expired() -> void:
	_config.buyback_expiry_days = 7
	var entry := {"sell_day": 1, "credit_paid": 100.0}
	assert_eq(_ledger.days_remaining(entry, 20), 0)


func test_days_remaining_on_sell_day_is_full_window() -> void:
	_config.buyback_expiry_days = 7
	var entry := {"sell_day": 5, "credit_paid": 100.0}
	assert_eq(_ledger.days_remaining(entry, 5), 7)


# --- cost calculation ---

func test_buyback_cost_includes_fee() -> void:
	_config.buyback_fee_percent = 10.0
	var entry := {"credit_paid": 100.0, "sell_day": 1}
	assert_eq(_ledger.get_buyback_cost(entry), 110)


func test_buyback_cost_no_fee() -> void:
	_config.buyback_fee_percent = 0.0
	var entry := {"credit_paid": 200.0, "sell_day": 1}
	assert_eq(_ledger.get_buyback_cost(entry), 200)


func test_buyback_cost_rounds_up() -> void:
	_config.buyback_fee_percent = 10.0
	var entry := {"credit_paid": 105.0, "sell_day": 1}
	# 105 * 1.1 = 115.5 → ceil → 116
	assert_eq(_ledger.get_buyback_cost(entry), 116)


# --- remove ---

func test_remove_entry_by_index() -> void:
	_ledger.add_entry("Generalist", _make_slot("res://items/x.tres"), 50.0, 1)
	_ledger.remove_entry("Generalist", 0)
	assert_eq(_ledger.get_entries("Generalist").size(), 0)


func test_remove_entry_preserves_others() -> void:
	_ledger.add_entry("Generalist", _make_slot("res://items/a.tres"), 10.0, 1)
	_ledger.add_entry("Generalist", _make_slot("res://items/b.tres"), 20.0, 1)
	# entries are newest-first: [b, a]; remove index 1 (a)
	_ledger.remove_entry("Generalist", 1)
	var entries: Array = _ledger.get_entries("Generalist")
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["resource_path"], "res://items/b.tres")


func test_remove_entry_out_of_bounds_is_safe() -> void:
	_ledger.remove_entry("Generalist", 99)  # no crash
	assert_eq(_ledger.get_entries("Generalist").size(), 0)


func test_get_entries_returns_copy() -> void:
	_ledger.add_entry("Generalist", _make_slot("res://items/a.tres"), 50.0, 1)
	var entries: Array = _ledger.get_entries("Generalist")
	entries.clear()
	assert_eq(_ledger.get_entries("Generalist").size(), 1)
