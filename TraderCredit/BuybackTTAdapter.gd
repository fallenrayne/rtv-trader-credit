extends Node

# Handles the TraderTabs injection path for the buyback panel.
# Owns: TT tab registration, tab_changed signal, grids_container management.
# Does NOT own _panel — BuybackUI holds the lifetime; this class holds a reference.

signal buyback_tab_activated
signal supply_tab_activated

var _tt_node   = null
var _tab_bar   = null
var _tab_index: int = -1
var _panel: Control = null


func inject(iface, panel: Control) -> bool:
	var tt := iface.get_node_or_null("TT_TraderTabs")
	if tt == null:
		return false
	var tab_bar   = tt.get("tab_bar")
	var grids_ctr = tt.get("grids_container")
	if tab_bar == null or grids_ctr == null:
		push_warning("[TraderCredit] BuybackTTAdapter: TraderTabs structure changed — falling back to standalone")
		return false

	_tt_node   = tt
	_panel     = panel
	_tab_bar   = tab_bar

	tab_bar.add_tab("Buyback")
	_tab_index = tab_bar.get_tab_count() - 1
	grids_ctr.add_child(panel)
	panel.hide()

	if not tab_bar.tab_changed.is_connected(_on_tab_changed):
		tab_bar.tab_changed.connect(_on_tab_changed)

	return true


func cleanup() -> void:
	if is_instance_valid(_tab_bar):
		if _tab_bar.tab_changed.is_connected(_on_tab_changed):
			_tab_bar.tab_changed.disconnect(_on_tab_changed)
		if _tab_index >= 0:
			_tab_bar.remove_tab(_tab_index)
	_tt_node   = null
	_tab_bar   = null
	_tab_index = -1
	_panel     = null  # BuybackUI owns the node


func _on_tab_changed(idx: int) -> void:
	if idx == _tab_index:
		# TT hides grids_container for unmapped tabs without restoring it — force it visible.
		if is_instance_valid(_tt_node):
			var grids_ctr = _tt_node.get("grids_container")
			if grids_ctr != null:
				grids_ctr.show()
		# Hide all TT grids so only our panel shows.
		if _tt_node != null and _tt_node.has_method("get_all_grids"):
			for g in _tt_node.get_all_grids():
				g.hide()
		if is_instance_valid(_panel):
			_panel.show()
		emit_signal("buyback_tab_activated")
	else:
		if is_instance_valid(_panel):
			_panel.hide()
		emit_signal("supply_tab_activated")
