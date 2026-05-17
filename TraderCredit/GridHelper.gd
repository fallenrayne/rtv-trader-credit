extends Node

# Static helpers for reading trader UI node trees.
# Loaded as a script constant — no instance needed.


static func get_interface(tree: SceneTree):
	var scene := tree.current_scene
	if not scene:
		return null
	return scene.get_node_or_null("Core/UI/Interface")


# Walks up from acceptButton to its direct child-of-iface ancestor.
static func find_deal_section(iface) -> Node:
	if not iface or not is_instance_valid(iface.acceptButton):
		return null
	var node = iface.acceptButton
	while node and node != iface and node.get_parent() != iface:
		node = node.get_parent()
	if node == null or node == iface:
		return null
	return node


# Total value of selected trader-supply items, including the trader's tax markup.
static func get_supply_cost(iface, tax: float) -> float:
	var total := 0.0
	var tt = iface.get_node_or_null("TT_TraderTabs")
	if tt and tt.has_method("get_all_grids"):
		for grid in tt.get_all_grids():
			if not is_instance_valid(grid):
				continue
			for el in grid.get_children():
				if el.selected and el.has_method("Value"):
					total += float(el.Value()) * tax
	elif is_instance_valid(iface.supplyGrid):
		for el in iface.supplyGrid.get_children():
			if el.selected and el.has_method("Value"):
				total += float(el.Value()) * tax
	return total


# Number of selected items on the trader's supply side.
static func get_supply_selected_count(iface) -> int:
	var n := 0
	var tt = iface.get_node_or_null("TT_TraderTabs")
	if tt and tt.has_method("get_all_grids"):
		for grid in tt.get_all_grids():
			if not is_instance_valid(grid):
				continue
			for el in grid.get_children():
				if el.selected:
					n += 1
	elif is_instance_valid(iface.supplyGrid):
		for el in iface.supplyGrid.get_children():
			if el.selected:
				n += 1
	return n


# Raw total value of selected player-inventory items (no restriction filter).
static func get_raw_offer_value(iface) -> float:
	var total := 0.0
	if not iface.inventoryGrid:
		return total
	for el in iface.inventoryGrid.get_children():
		if el.selected and el.has_method("Value"):
			total += float(el.Value())
	return total


# Filtered total value of selected player-inventory items, respecting item_restriction.
static func get_offer_value(iface, trader_name: String, item_restriction: String) -> float:
	var total := 0.0
	if not iface.inventoryGrid:
		return total
	for el in iface.inventoryGrid.get_children():
		if not el.selected or not el.has_method("Value"):
			continue
		if item_restriction == "trader_only" and not is_item_accepted_by_trader(el, trader_name):
			continue
		total += float(el.Value())
	return total


# Filtered list of sellable inventory elements, respecting item_restriction.
static func get_sellable_elements(iface, trader_name: String, item_restriction: String) -> Array:
	var result: Array = []
	if not iface.inventoryGrid:
		return result
	for el in iface.inventoryGrid.get_children():
		if not el.selected or not el.has_method("Value"):
			continue
		if item_restriction == "trader_only" and not is_item_accepted_by_trader(el, trader_name):
			continue
		result.append(el)
	return result


# Returns true when the item carries the trader's pool flag (or the flag is absent, meaning it's
# accepted by default). Traders set a boolean property named after themselves (lowercased) on
# items they don't deal in; absent flag = universally accepted.
static func is_item_accepted_by_trader(element, trader_name: String) -> bool:
	if not element.slotData or not element.slotData.itemData:
		return false
	var flag := trader_name.to_lower()
	var item_data = element.slotData.itemData
	if not (flag in item_data):
		return true
	return bool(item_data.get(flag))
