extends RefCounted

# ==============================================================
# TraderLayout — measures and exposes named layout zones on the
# trader interface screen.
#
# Usage:
#   var layout = TraderLayout.measure(iface)
#   if layout.valid:
#       my_node.position = Vector2(layout.panel_x, layout.below_deal_y)
#
# Exposed via Engine meta "TraderCreditLayout" while the trader
# interface is open, so other mods can read the same measurements
# without recalculating or conflicting.
# ==============================================================

# Whether measurement succeeded (all key nodes were found).
var valid: bool = false

# Horizontal origin and width of the centre panel (trader portrait column).
var panel_x: float = 768.0
var panel_w: float = 384.0

# Vertical zones — all relative to iface (the Interface node).
var portrait_top_y:  float = 0.0   # top of trader portrait panel
var portrait_bot_y:  float = 0.0   # bottom of trader portrait panel
var deal_top_y:      float = 0.0   # top of the vanilla deal section
var deal_bot_y:      float = 0.0   # bottom of the vanilla deal section (0 until settled)
var character_top_y: float = 0.0   # top of character stats panel (lower bound)

# The deal section node itself (for size-change watching).
var deal_section: Node = null

# Accept button — used as a reliable height anchor when deal_section.size.y is 0.
var _accept_button = null

# Human-readable sizing log — printed once per open for debugging.
var _log_lines: PackedStringArray = []


func measure(iface) -> void:
	_log("=== TraderLayout.measure ===")

	# --- Trader portrait column ---
	var trader_node = iface.get_node_or_null("Trader")
	if trader_node == null:
		_log("WARN: 'Trader' node not found — using defaults")
	else:
		panel_x = trader_node.position.x
		_log("Trader node pos: %s  size: %s" % [trader_node.position, trader_node.size])

	var portrait = trader_node.get_node_or_null("Panel") if trader_node else null
	if portrait == null:
		_log("WARN: 'Trader/Panel' not found — portrait_h defaulting to 384")
		portrait_top_y = trader_node.position.y if trader_node else 128.0
		portrait_bot_y = portrait_top_y + 384.0
	else:
		portrait_top_y = portrait.global_position.y - iface.global_position.y
		portrait_bot_y = portrait_top_y + portrait.size.y
		_log("Portrait Panel pos: %s  size: %s" % [portrait.position, portrait.size])

	# --- Character stats (lower boundary) ---
	var character = iface.get_node_or_null("Character")
	if character == null:
		_log("WARN: 'Character' node not found — defaulting character_top_y to 768")
		character_top_y = 768.0
	else:
		character_top_y = character.position.y
		_log("Character pos: %s  size: %s" % [character.position, character.size])

	# --- Deal section ---
	var section = _find_deal_section(iface)
	if section == null:
		_log("WARN: deal section not found")
	else:
		deal_section = section
		deal_top_y   = portrait_bot_y + 20.0
		var h: float = section.get_combined_minimum_size().y
		_log("Deal section node: %s" % section.name)
		_log("  get_combined_minimum_size: %s" % section.get_combined_minimum_size())
		_log("  size (pre-reparent):       %s" % section.size)
		if h > 0:
			deal_bot_y = deal_top_y + h
		# else: deal_bot_y stays 0 — caller must call refresh_deal_height() later

	_log("Zones — panel_x:%.0f  panel_w:%.0f  portrait_bot:%.0f  deal_top:%.0f  deal_bot:%.0f  char_top:%.0f" \
		% [panel_x, panel_w, portrait_bot_y, deal_top_y, deal_bot_y, character_top_y])
	_log("============================")

	valid = (trader_node != null and character != null)
	_flush_log()


# Call this after the deal section has been reparented and laid out.
# Returns true when height has been determined (via size.y or accept button fallback).
func refresh_deal_height() -> bool:
	if deal_section == null or not is_instance_valid(deal_section):
		return false
	var h: float = deal_section.size.y
	# deal_section.size.y stays 0 after reparenting into a bare Control — fall back to
	# deriving the height from the accept button's rendered global rect.
	if h <= 0 and _accept_button != null and is_instance_valid(_accept_button):
		var btn_bot: float  = _accept_button.global_position.y + _accept_button.size.y
		var sec_top: float  = deal_section.global_position.y
		var derived: float  = btn_bot - sec_top
		_log("refresh_deal_height — size.y=0, btn_bot=%.0f  sec_top=%.0f  derived=%.0f" \
			% [btn_bot, sec_top, derived])
		_flush_log()
		if derived > 0:
			deal_bot_y = deal_top_y + derived
			return true
		return false
	_log("refresh_deal_height — size.y=%.0f" % h)
	_flush_log()
	if h <= 0:
		return false
	deal_bot_y = deal_top_y + h
	return true


# Convenience: y-coordinate to start placing UI directly below the deal section.
func below_deal_y(gap: float = 8.0) -> float:
	return deal_bot_y + gap


# Available height between the deal section and the character panel.
func available_height() -> float:
	return max(0.0, character_top_y - deal_bot_y)


func _find_deal_section(iface) -> Node:
	if not iface or not is_instance_valid(iface.acceptButton):
		return null
	_accept_button = iface.acceptButton
	var node = iface.acceptButton
	while node and node != iface and node.get_parent() != iface:
		node = node.get_parent()
	if node == null or node == iface:
		return null
	return node


func _log(msg: String) -> void:
	_log_lines.append("[TraderLayout] " + msg)


func _flush_log() -> void:
	for line in _log_lines:
		print(line)
	_log_lines.clear()
