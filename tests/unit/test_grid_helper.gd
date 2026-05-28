extends GutTest

const GridHelper = preload("res://mods/TraderCredit/GridHelper.gd")


# ---- helpers ----

func _make_el(value: int, sel: bool, slot: SlotData = null) -> MockElement:
	var el := MockElement.new()
	el._value  = value
	el.selected = sel
	el.slotData = slot
	return el


func _make_slot(flag: String = "", flag_val: bool = true) -> SlotData:
	var item := MockItemData.new()
	if flag != "":
		item.set(flag, flag_val)
	var slot := SlotData.new()
	slot.itemData = item
	return slot


func _iface_with_inventory(elements: Array) -> Node:
	var iface = preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var grid := Node.new()
	iface.add_child(grid)
	iface.inventoryGrid = grid
	for el in elements:
		grid.add_child(el)
	return iface


func _iface_with_supply(elements: Array) -> Node:
	var iface = preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var grid := Node.new()
	iface.add_child(grid)
	iface.supplyGrid = grid
	for el in elements:
		grid.add_child(el)
	return iface


# ==============================================================
# is_item_accepted_by_trader
# ==============================================================

func test_accepted_when_trader_flag_absent() -> void:
	# "medic" is not a declared property on MockItemData — absent flag means universal acceptance.
	var el := _make_el(100, true, _make_slot())
	assert_true(GridHelper.is_item_accepted_by_trader(el, "Medic"))


func test_accepted_when_trader_flag_true() -> void:
	var el := _make_el(100, true, _make_slot("generalist", true))
	assert_true(GridHelper.is_item_accepted_by_trader(el, "Generalist"))


func test_rejected_when_trader_flag_false() -> void:
	var el := _make_el(100, true, _make_slot("doctor", false))
	assert_false(GridHelper.is_item_accepted_by_trader(el, "Doctor"))


func test_rejected_when_slot_data_null() -> void:
	var el := _make_el(100, true)  # slotData = null
	assert_false(GridHelper.is_item_accepted_by_trader(el, "Generalist"))


func test_rejected_when_item_data_null() -> void:
	var slot := SlotData.new()  # slot.itemData left null
	var el := _make_el(100, true, slot)
	assert_false(GridHelper.is_item_accepted_by_trader(el, "Generalist"))


# ==============================================================
# get_offer_value
# ==============================================================

func test_offer_value_any_restriction_sums_all_selected() -> void:
	var iface := _iface_with_inventory([
		_make_el(200, true,  _make_slot("doctor", false)),  # doctor rejects it, but mode is "any"
		_make_el(300, true,  _make_slot()),
		_make_el(100, false, _make_slot()),                 # unselected — excluded
	])
	assert_eq(GridHelper.get_offer_value(iface, "Doctor", "any"), 500.0)


func test_offer_value_trader_only_includes_accepted_items() -> void:
	var iface := _iface_with_inventory([
		_make_el(200, true, _make_slot("doctor", true)),
		_make_el(300, true, _make_slot("doctor", true)),
	])
	assert_eq(GridHelper.get_offer_value(iface, "Doctor", "trader_only"), 500.0)


func test_offer_value_trader_only_excludes_rejected_items() -> void:
	var iface := _iface_with_inventory([
		_make_el(200, true, _make_slot("doctor", false)),  # Doctor rejects this
		_make_el(300, true, _make_slot("doctor", true)),
	])
	assert_eq(GridHelper.get_offer_value(iface, "Doctor", "trader_only"), 300.0)


func test_offer_value_excludes_unselected_items() -> void:
	var iface := _iface_with_inventory([
		_make_el(500, false, _make_slot()),  # not selected
	])
	assert_eq(GridHelper.get_offer_value(iface, "Generalist", "any"), 0.0)


func test_offer_value_null_grid_returns_zero() -> void:
	var iface = preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	# inventoryGrid left null
	assert_eq(GridHelper.get_offer_value(iface, "Generalist", "any"), 0.0)


# ==============================================================
# get_supply_cost
# ==============================================================

func test_supply_cost_multiplies_selected_by_tax() -> void:
	var iface := _iface_with_supply([
		_make_el(100, true),
		_make_el(200, true),
	])
	assert_almost_eq(GridHelper.get_supply_cost(iface, 1.1), 330.0, 0.01)


func test_supply_cost_excludes_unselected() -> void:
	var iface := _iface_with_supply([
		_make_el(100, true),
		_make_el(200, false),
	])
	assert_eq(GridHelper.get_supply_cost(iface, 1.0), 100.0)


func test_supply_cost_null_grid_returns_zero() -> void:
	var iface = preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	assert_eq(GridHelper.get_supply_cost(iface, 1.1), 0.0)


# ==============================================================
# get_supply_selected_count
# ==============================================================

func test_supply_selected_count() -> void:
	var iface := _iface_with_supply([
		_make_el(100, true),
		_make_el(100, false),
		_make_el(100, true),
	])
	assert_eq(GridHelper.get_supply_selected_count(iface), 2)


func test_supply_selected_count_none_selected() -> void:
	var iface := _iface_with_supply([
		_make_el(100, false),
		_make_el(100, false),
	])
	assert_eq(GridHelper.get_supply_selected_count(iface), 0)


# ==============================================================
# get_sellable_elements
# ==============================================================

func test_sellable_elements_any_returns_all_selected() -> void:
	var a := _make_el(100, true,  _make_slot("doctor", false))
	var b := _make_el(200, true,  _make_slot())
	var c := _make_el(300, false, _make_slot())  # not selected
	var iface := _iface_with_inventory([a, b, c])
	var result: Array = GridHelper.get_sellable_elements(iface, "Doctor", "any")
	assert_eq(result.size(), 2)
	assert_true(result.has(a))
	assert_true(result.has(b))


func test_sellable_elements_trader_only_filters_rejected() -> void:
	var a := _make_el(100, true, _make_slot("gunsmith", false))  # Gunsmith rejects this
	var b := _make_el(200, true, _make_slot("gunsmith", true))
	var iface := _iface_with_inventory([a, b])
	var result: Array = GridHelper.get_sellable_elements(iface, "Gunsmith", "trader_only")
	assert_eq(result.size(), 1)
	assert_true(result.has(b))


func test_sellable_elements_empty_when_nothing_selected() -> void:
	var iface := _iface_with_inventory([
		_make_el(100, false, _make_slot()),
	])
	var result: Array = GridHelper.get_sellable_elements(iface, "Generalist", "any")
	assert_eq(result.size(), 0)


# ==============================================================
# find_deal_section
# ==============================================================

func test_find_deal_section_direct_child() -> void:
	# acceptButton is a direct child of a node that is itself a direct child of iface.
	var iface = preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var section := Node.new()
	var btn     := Node.new()
	section.add_child(btn)
	iface.add_child(section)
	iface.acceptButton = btn
	assert_eq(GridHelper.find_deal_section(iface), section)


func test_find_deal_section_nested_button() -> void:
	# acceptButton nested several levels deep — should still return iface's direct child.
	var iface = preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	var section    := Node.new()
	var container  := Node.new()
	var btn        := Node.new()
	container.add_child(btn)
	section.add_child(container)
	iface.add_child(section)
	iface.acceptButton = btn
	assert_eq(GridHelper.find_deal_section(iface), section)


func test_find_deal_section_null_button_returns_null() -> void:
	var iface = preload("res://stubs/MockIface.gd").new()
	add_child_autofree(iface)
	# acceptButton left null
	assert_null(GridHelper.find_deal_section(iface))
