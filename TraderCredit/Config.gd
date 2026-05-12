extends Node

# ============================================================
# Trader Credit — Config.gd
# MCM-backed configuration. Registered as the "TraderCreditConfig"
# autoload so Main.gd can read settings from it at any time.
#
# If MCM is not installed the defaults are used silently.
# Settings file: user://MCM/TraderCredit/config.ini
# ============================================================

const MOD_ID   := "TraderCredit"
const MOD_NAME := "Trader Credit"
const FILE_PATH := "user://MCM/TraderCredit"

# ---- Public settings (read directly by Main.gd) ----
var credit_per_task:       int   = 500
var death_penalty_enabled: bool  = true
var death_penalty_percent: float = 10.0
var decay_enabled:         bool  = true
var decay_rate_per_day:    float = 5.0
var item_restriction:      String = "trader_only"  # "trader_only" | "any"
var sell_tax:              float = 30.0

var _mcm_helpers = null


func _ready() -> void:
	name = "TraderCreditConfig"
	_mcm_helpers = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")

	var config := ConfigFile.new()

	# ---- Categories (control display order in the MCM sidebar) ----
	config.set_value("Category", "Credit Cap",       {"menu_pos": 1})
	config.set_value("Category", "Penalties & Decay", {"menu_pos": 2})
	config.set_value("Category", "Trading",           {"menu_pos": 3})

	# ---- Credit Cap ----
	config.set_value("Int", "credit_per_task", {
		"name"     = "Credit Per Task",
		"tooltip"  = "How much credit cap you unlock per completed trader task. "
				   + "With 10 tasks done and the default 500, your cap is 5000 credit.",
		"default"  = 500,
		"value"    = 500,
		"minRange" = 100,
		"maxRange" = 5000,
		"category" = "Credit Cap",
		"menu_pos" = 1,
	})

	# ---- Penalties & Decay ----
	config.set_value("Bool", "death_penalty_enabled", {
		"name"     = "Death Penalty",
		"tooltip"  = "When ON, dying removes a percentage of your credit balance "
				   + "with every trader. Permadeath always wipes all credit.",
		"default"  = true,
		"value"    = true,
		"category" = "Penalties & Decay",
		"menu_pos" = 1,
	})

	config.set_value("Float", "death_penalty_percent", {
		"name"     = "Death Penalty %",
		"tooltip"  = "Percentage of credit lost per non-permadeath death. "
				   + "10 = lose 10 % of each trader's balance on death.",
		"default"  = 10.0,
		"value"    = 10.0,
		"minRange" = 0.0,
		"maxRange" = 100.0,
		"category" = "Penalties & Decay",
		"menu_pos" = 2,
	})

	config.set_value("Bool", "decay_enabled", {
		"name"     = "Credit Decay",
		"tooltip"  = "When ON, credit balances shrink each in-game day. "
				   + "Encourages spending credit rather than banking it indefinitely.",
		"default"  = true,
		"value"    = true,
		"category" = "Penalties & Decay",
		"menu_pos" = 3,
	})

	config.set_value("Float", "decay_rate_per_day", {
		"name"     = "Decay Rate (% / day)",
		"tooltip"  = "Percentage of credit lost per in-game day (compounded). "
				   + "5 % / day leaves ~77 % after 5 days, ~36 % after 20 days.",
		"default"  = 5.0,
		"value"    = 5.0,
		"minRange" = 0.0,
		"maxRange" = 25.0,
		"category" = "Penalties & Decay",
		"menu_pos" = 4,
	})

	# ---- Trading ----
	config.set_value("Dropdown", "item_restriction", {
		"name"     = "Item Restriction",
		"tooltip"  = "Trader Only: only items the trader normally deals in earn credit "
				   + "(Doctor accepts medical supplies, Gunsmith accepts weapons/ammo). "
				   + "Any: all selected items earn credit regardless of trader.",
		"default"  = 0,
		"value"    = 0,
		"options"  = ["Trader Only", "Any"],
		"category" = "Trading",
		"menu_pos" = 1,
	})

	config.set_value("Float", "sell_tax", {
		"name"     = "Sell Tax (%)",
		"tooltip"  = "Percentage deducted from an item's barter value when converting "
				   + "to credit. 30 = you receive 70 % of the item's value as credit.",
		"default"  = 30.0,
		"value"    = 30.0,
		"minRange" = 0.0,
		"maxRange" = 75.0,
		"category" = "Trading",
		"menu_pos" = 2,
	})

	_merge_schema(config, FILE_PATH + "/config.ini")

	if _mcm_helpers == null:
		# MCM not installed — apply defaults and stop here.
		_apply(config)
		return

	_mcm_helpers.CheckConfigurationHasUpdated(MOD_ID, config, FILE_PATH + "/config.ini")
	_apply(config)

	_mcm_helpers.RegisterConfiguration(
		MOD_ID,
		MOD_NAME,
		FILE_PATH,
		"Sell items to traders for local credit — usable only with that trader.",
		{"config.ini" = _apply}
	)


# Applies config values to the public properties Main.gd reads.
# MCM can call this at any time when the player saves settings in-game.
func _apply(config: ConfigFile) -> void:
	# Force a fresh disk read — MCM sometimes passes a stale in-memory
	# config to the callback.
	var fresh := ConfigFile.new()
	if fresh.load(FILE_PATH + "/config.ini") == OK:
		config = fresh

	credit_per_task       = int(  config.get_value("Int",      "credit_per_task",       {"value": 500  })["value"])
	death_penalty_enabled = bool( config.get_value("Bool",     "death_penalty_enabled",  {"value": true })["value"])
	death_penalty_percent = float(config.get_value("Float",    "death_penalty_percent",  {"value": 10.0 })["value"])
	decay_enabled         = bool( config.get_value("Bool",     "decay_enabled",          {"value": true })["value"])
	decay_rate_per_day    = float(config.get_value("Float",    "decay_rate_per_day",     {"value": 5.0  })["value"])
	sell_tax              = float(config.get_value("Float",    "sell_tax",               {"value": 30.0 })["value"])

	var restriction_idx   = int(  config.get_value("Dropdown", "item_restriction",       {"value": 0    })["value"])
	item_restriction = "trader_only" if restriction_idx == 0 else "any"


# Migrates an existing config file forward when new keys are added in an
# update. Preserves every "value" the player already set, adds new keys
# at their defaults, and removes keys that no longer exist.
func _merge_schema(fresh: ConfigFile, path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	if not FileAccess.file_exists(path):
		fresh.save(path)
		return

	var disk := ConfigFile.new()
	if disk.load(path) != OK:
		fresh.save(path)
		return

	# For every key in the in-memory schema, if the same key exists on disk
	# and the user has a "value" saved there, carry that value forward.
	for section in fresh.get_sections():
		for key in fresh.get_section_keys(section):
			if not disk.has_section_key(section, key):
				continue
			var schema_entry = fresh.get_value(section, key)
			var disk_entry   = disk.get_value(section, key)
			if schema_entry is Dictionary and disk_entry is Dictionary and disk_entry.has("value"):
				schema_entry["value"] = disk_entry["value"]
				fresh.set_value(section, key, schema_entry)
			elif not (schema_entry is Dictionary):
				fresh.set_value(section, key, disk_entry)

	fresh.save(path)
