extends GutTest

var _ledger: Node
var _config: Node


func before_each() -> void:
	_config = preload("res://stubs/MockConfig.gd").new()
	_config.name = "TraderCreditConfig"
	get_tree().root.add_child(_config)
	_ledger = preload("res://mods/TraderCredit/CreditLedger.gd").new()
	add_child_autofree(_ledger)


func after_each() -> void:
	if is_instance_valid(_config):
		_config.queue_free()


# --- balance ---

func test_add_credit_within_cap() -> void:
	_ledger.set_task_count("Generalist", 2)   # cap = 1000
	var added := _ledger.add_credit("Generalist", 300.0)
	assert_eq(added, 300.0)
	assert_eq(_ledger.get_balance("Generalist"), 300.0)


func test_add_credit_clamps_to_cap() -> void:
	_ledger.set_task_count("Generalist", 1)   # cap = 500
	var added := _ledger.add_credit("Generalist", 800.0)
	assert_eq(added, 500.0)
	assert_eq(_ledger.get_balance("Generalist"), 500.0)


func test_add_credit_zero_tasks_adds_nothing() -> void:
	var added := _ledger.add_credit("Generalist", 100.0)
	assert_eq(added, 0.0)


func test_spend_credit_success() -> void:
	_ledger.set_task_count("Generalist", 2)
	_ledger.add_credit("Generalist", 400.0)
	assert_true(_ledger.spend_credit("Generalist", 250.0))
	assert_eq(_ledger.get_balance("Generalist"), 150.0)


func test_spend_credit_insufficient_balance() -> void:
	_ledger.set_task_count("Generalist", 2)
	_ledger.add_credit("Generalist", 100.0)
	assert_false(_ledger.spend_credit("Generalist", 200.0))
	assert_eq(_ledger.get_balance("Generalist"), 100.0)


# --- cap ceiling ---

func test_credit_cap_max_applies() -> void:
	_config.credit_cap_max = 300
	_ledger.set_task_count("Generalist", 10)  # would be 5000 without ceiling
	assert_eq(_ledger.get_cap("Generalist"), 300)


func test_credit_cap_max_zero_means_unlimited() -> void:
	_config.credit_cap_max = 0
	_ledger.set_task_count("Generalist", 10)
	assert_eq(_ledger.get_cap("Generalist"), 5000)


# --- remaining cap ---

func test_get_remaining_cap() -> void:
	_ledger.set_task_count("Generalist", 2)   # cap = 1000
	_ledger.add_credit("Generalist", 300.0)
	assert_eq(_ledger.get_remaining_cap("Generalist"), 700.0)


func test_get_remaining_cap_at_zero_when_full() -> void:
	_ledger.set_task_count("Generalist", 1)   # cap = 500
	_ledger.add_credit("Generalist", 500.0)
	assert_eq(_ledger.get_remaining_cap("Generalist"), 0.0)


# --- decay ---

func test_decay_one_day() -> void:
	_ledger.set_task_count("Generalist", 10)
	_ledger.add_credit("Generalist", 1000.0)
	_config.decay_rate_per_day = 10.0
	_ledger.apply_decay_for_trader("Generalist", 1)  # anchor
	_ledger.apply_decay_for_trader("Generalist", 2)  # 1 day → 1000 * 0.9 = 900
	assert_eq(_ledger.get_balance("Generalist"), 900.0)


func test_decay_compound_multiple_days() -> void:
	_ledger.set_task_count("Generalist", 10)
	_ledger.add_credit("Generalist", 1000.0)
	_config.decay_rate_per_day = 10.0
	_ledger.apply_decay_for_trader("Generalist", 1)
	_ledger.apply_decay_for_trader("Generalist", 3)  # 2 days → floor(1000 * 0.81) = 810
	assert_eq(_ledger.get_balance("Generalist"), 810.0)


func test_decay_floor_prevents_going_below_minimum() -> void:
	_ledger.set_task_count("Generalist", 2)  # cap = 1000
	_ledger.add_credit("Generalist", 50.0)
	_config.decay_rate_per_day = 90.0        # aggressive
	_config.decay_floor_percent = 20.0       # floor = 200 (20 % of 1000)
	_ledger.apply_decay_for_trader("Generalist", 1)
	_ledger.apply_decay_for_trader("Generalist", 2)  # 50*0.1=5, clamped to floor 200
	assert_eq(_ledger.get_balance("Generalist"), 200.0)


func test_decay_disabled_leaves_balance_unchanged() -> void:
	_config.decay_enabled = false
	_ledger.set_task_count("Generalist", 2)
	_ledger.add_credit("Generalist", 500.0)
	_ledger.apply_decay_for_trader("Generalist", 1)
	_ledger.apply_decay_for_trader("Generalist", 10)
	assert_eq(_ledger.get_balance("Generalist"), 500.0)


func test_decay_same_day_is_noop() -> void:
	_ledger.set_task_count("Generalist", 2)
	_ledger.add_credit("Generalist", 500.0)
	_config.decay_rate_per_day = 50.0
	_ledger.apply_decay_for_trader("Generalist", 5)  # anchor on day 5
	_ledger.apply_decay_for_trader("Generalist", 5)  # same day again
	assert_eq(_ledger.get_balance("Generalist"), 500.0)


# --- death penalty ---

func test_death_penalty_reduces_all_balances() -> void:
	_ledger.set_task_count("Generalist", 10)
	_ledger.set_task_count("Doctor", 10)
	_ledger.add_credit("Generalist", 1000.0)
	_ledger.add_credit("Doctor", 500.0)
	_ledger.apply_death_penalty(false, 10.0)
	assert_eq(_ledger.get_balance("Generalist"), 900.0)
	assert_eq(_ledger.get_balance("Doctor"), 450.0)


func test_permadeath_wipes_credit_and_tasks() -> void:
	_ledger.set_task_count("Generalist", 5)
	_ledger.add_credit("Generalist", 1000.0)
	_ledger.apply_death_penalty(true, 10.0)
	assert_eq(_ledger.get_balance("Generalist"), 0.0)
	assert_eq(_ledger.get_cap("Generalist"), 0)


func test_death_penalty_disabled_leaves_balance_unchanged() -> void:
	_config.death_penalty_enabled = true  # flag is checked by caller (Main.gd), not ledger
	_ledger.set_task_count("Generalist", 2)
	_ledger.add_credit("Generalist", 300.0)
	# Passing 0 % penalty → no change
	_ledger.apply_death_penalty(false, 0.0)
	assert_eq(_ledger.get_balance("Generalist"), 300.0)


# --- task sync ---

func test_sync_task_count_advances_when_behind() -> void:
	_ledger.set_task_count("Generalist", 3)
	assert_true(_ledger.sync_task_count("Generalist", 5))
	assert_eq(_ledger.get_cap("Generalist"), 2500)


func test_sync_task_count_does_not_regress() -> void:
	_ledger.set_task_count("Generalist", 5)
	assert_false(_ledger.sync_task_count("Generalist", 3))
	assert_eq(_ledger.get_cap("Generalist"), 2500)


func test_sync_task_count_equal_is_noop() -> void:
	_ledger.set_task_count("Generalist", 4)
	assert_false(_ledger.sync_task_count("Generalist", 4))
	assert_eq(_ledger.get_cap("Generalist"), 2000)
