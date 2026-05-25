# Trader Credit

A Road to Vostok mod that adds a per-trader credit system. Sell your loot directly to traders for local credit, then spend it on future purchases — no bartering required.

## Overview

Each trader maintains a separate credit balance. Credit is earned by selling items, spent when buying, and can decay over time. Your credit capacity grows as you complete trader tasks, giving task progression a tangible economic payoff.

**Key features:**

- Sell items from your inventory to a trader for credit (at a configurable tax rate)
- Credit is trader-local — credit earned with one trader can only be spent there
- Credit capacity unlocked per completed task (configurable)
- Task completion awards an immediate credit bonus on top of raising the cap
- Credit decays each in-game day, encouraging spending over hoarding
- Death penalty reduces balances; permadeath wipes them entirely
- **Buyback system** — any items you sell (for credit or via barter) are held by the trader for a configurable window; repurchase them using credit, inventory items, or a mix of both
- All settings tunable in-game via MCM (Mod Configuration Menu)

## Requirements

- **Road to Vostok** (Godot 4.x build)
- **Metro Mod Loader** — provides the hook system this mod depends on
- **Mod Configuration Menu (MCM)** — optional but recommended; without it, all defaults apply

## Installation

### From a release (recommended)

1. Download `TraderCredit.vmz` from the [latest release](https://github.com/fallenrayne/rtv-trader-credit/releases/latest).
2. Place the `.vmz` file in your Road to Vostok mods directory.
3. Enable the mod in the game's mod manager and launch the game.

### From source (dev mode)

1. Copy the `TraderCredit/` folder into your Road to Vostok mods directory.
2. In the game's mod manager, enable **Dev Mode** — this is required for the game to load mods from plain folders rather than packaged `.vmz` files.
3. Enable the mod and launch the game.

### Building the VMZ (contributors)

1. Copy `build.local.ps1.example` to `build.local.ps1` and set `$modsDir` to your Road to Vostok mods folder.
2. Run `.\build.ps1` from a PowerShell prompt in the repo root.

This packages `TraderCredit/` into `releases/TraderCredit.vmz` and, if `build.local.ps1` is present, copies the VMZ directly to your mods folder for immediate testing.

Settings appear under **Trader Credit** in the MCM sidebar once in-game.

## How It Works

### Credit Cap

You start with zero credit capacity with every trader. Each completed trader task raises the cap by a configurable amount (default: 500 per task). A hard ceiling (`Max Credit Cap`) can optionally cap total capacity regardless of task count.

### Earning Credit

Open the trader interface and select items from your inventory. Items must match what the trader normally deals in (configurable). Click **Sell for Credit** below the deal section to receive the item's barter value minus a sell tax (default: 30%).

### Spending Credit

When the barter value of what the trader is offering exceeds what you're giving back, the deficit is compared against your credit balance. If you have enough, the Accept button becomes active and the purchase is automatically completed using credit.

### Task Bonus

On task completion, a one-time credit bonus is deposited in addition to the cap increase. Bonus amounts are per-difficulty: Easy, Intermediate, and Hard each have their own configurable value.

### Decay

Credit balances shrink by a percentage each in-game day (compounded). The default rate of 5%/day leaves ~77% after 5 days and ~36% after 20 days. A decay floor prevents balances from falling below a set percentage of the cap.

### Death Penalty

On non-permadeath death, a percentage of every trader's balance is lost. On permadeath, all balances and task counts are wiped.

### Buyback

Any items you sell to a trader — whether for credit or through a normal barter trade — are held in a buyback list for a configurable number of in-game days. A **Buyback** tab appears alongside the Supply tab in the trader interface — if TraderTabs is installed the tab integrates into its bar; otherwise toggle buttons appear above the supply panel.

Each buyback item shows a color-coded countdown badge: green (plenty of time), yellow (3 days or fewer), red (1 day or fewer). Expired items are removed the next time you open the interface with that trader.

To repurchase, switch to the Buyback tab, select the items you want back, and click **Buy Back Selected**. The cost is what you originally received plus a small fee (default: 5%). You can offset the cost by selecting inventory items as a trade-in — the credit shortfall drops accordingly, and any offered inventory items that meet the rarity threshold are themselves added to the buyback list.

Only items at or above a configurable rarity (default: Uncommon) are eligible for buyback.

## Configuration

All settings are in the **Mod Configuration Menu** under **Trader Credit**.

### Credit Cap

| Setting | Default | Description |
|---|---|---|
| Credit Per Task | 500 | Credit cap unlocked per completed trader task |
| Max Credit Cap | 0 (off) | Hard ceiling on cap regardless of tasks; 0 = no limit |

### Penalties & Decay

| Setting | Default | Description |
|---|---|---|
| Death Penalty | On | Lose a % of credit on death |
| Death Penalty % | 10% | Percentage lost per death (permadeath always wipes all) |
| Credit Decay | On | Balances shrink each in-game day |
| Decay Rate (% / day) | 5% | Compounded daily loss rate |
| Decay Floor (%) | 0 (off) | Minimum balance as % of cap; decay stops here |

### Trading

| Setting | Default | Description |
|---|---|---|
| Item Restriction | Trader Only | Which items count for credit sales |
| Sell Tax (%) | 30% | Deducted from barter value when selling for credit |

### Task Bonus

| Setting | Default | Description |
|---|---|---|
| Task Bonus | On | Award credit on task completion |
| Easy Task Bonus | 100 | Credit awarded for Easy tasks |
| Intermediate Task Bonus | 250 | Credit awarded for Intermediate tasks |
| Hard Task Bonus | 500 | Credit awarded for Hard tasks |

### Buyback

| Setting | Default | Description |
|---|---|---|
| Buyback | On | Enable or disable the buyback system entirely |
| Expiry (days) | 7 | How many in-game days a sold item stays in the buyback list |
| Max Entries | 20 | Maximum buyback items held per trader |
| Fee (%) | 5 | Extra percentage added to the repurchase cost above the original sale price |
| Min. Rarity | Uncommon | Items below this rarity are not added to the buyback list |

## Save Data

Credit state is saved to `user://trader_credit.tres`. This file is separate from the main game save — it persists across play sessions and is updated automatically.

## License

MIT — see [LICENSE](LICENSE).
