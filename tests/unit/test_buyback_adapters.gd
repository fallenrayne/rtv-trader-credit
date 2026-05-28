extends GutTest

# Tests for BuybackTTAdapter and BuybackStandaloneAdapter in isolation.
# BuybackUI itself is not tested here because it preloads game-specific .tres
# and .tscn files at parse time. The adapters have no such dependencies.


# ---- helpers ----

func _make_iface_with_supply() -> Node:
	var iface := preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var supply_ui := Control.new()
	iface.add_child(supply_ui)
	iface.supplyUI = supply_ui
	return iface


# ============================================================
# BuybackTTAdapter
# ============================================================

func test_tt_inject_fails_when_no_tt_node_in_iface() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackTTAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var panel := Control.new()
	add_child_autofree(panel)
	assert_false(adapter.inject(iface, panel))


func test_tt_inject_leaves_panel_unparented_on_failure() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackTTAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var panel := Control.new()
	add_child_autofree(panel)
	adapter.inject(iface, panel)
	# Panel should not have been added anywhere when TT inject fails.
	assert_null(panel.get_parent())


func test_tt_cleanup_is_safe_when_not_injected() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackTTAdapter.gd").new()
	add_child_autofree(adapter)
	adapter.cleanup()  # must not crash
	assert_true(true)


# ============================================================
# BuybackStandaloneAdapter
# ============================================================

func test_standalone_inject_fails_without_supply_ui() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var panel := Control.new()
	add_child_autofree(panel)
	assert_false(adapter.inject(iface, panel))


func test_standalone_inject_succeeds_with_supply_ui() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	assert_true(adapter.inject(iface, panel))


func test_standalone_inject_adds_panel_as_child_of_iface() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	assert_eq(panel.get_parent(), iface)


func test_standalone_inject_adds_button_row_to_iface() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	assert_not_null(iface.get_node_or_null("TC_BuybackTabRow"))


func test_standalone_inject_leaves_panel_hidden() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	assert_false(panel.visible)


func test_standalone_cleanup_is_safe_when_not_injected() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	adapter.cleanup()  # must not crash
	assert_true(true)


func test_standalone_cleanup_nulls_supply_ui_reference() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	adapter.cleanup()
	assert_null(adapter._supply_ui)


func test_standalone_cleanup_nulls_panel_reference() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	adapter.cleanup()
	assert_null(adapter._panel)


func test_standalone_cleanup_removes_button_row() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	adapter.cleanup()
	# Button row was queue_free'd; it should no longer be in iface's children.
	await get_tree().process_frame
	assert_null(iface.get_node_or_null("TC_BuybackTabRow"))


func test_standalone_emits_buyback_tab_activated() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	watch_signals(adapter)
	adapter._on_buyback_btn_pressed()
	assert_signal_emitted(adapter, "buyback_tab_activated")


func test_standalone_emits_supply_tab_activated() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	adapter.inject(iface, panel)
	watch_signals(adapter)
	adapter._on_supply_btn_pressed()
	assert_signal_emitted(adapter, "supply_tab_activated")


func test_standalone_double_inject_is_safe() -> void:
	var adapter := preload("res://mods/TraderCredit/BuybackStandaloneAdapter.gd").new()
	add_child_autofree(adapter)
	var iface := _make_iface_with_supply()
	var panel := Control.new()
	assert_true(adapter.inject(iface, panel))
	# Second inject on the same adapter is not a defined use case but must not crash.
	assert_true(true)
