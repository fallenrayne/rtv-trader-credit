# Changelog

## 1.2.0

- **New:** Buyback system — items sold for credit are held by the trader for a configurable window (default 7 days) and can be repurchased at any time during that window.
- **New:** Buyback tab added to the trader interface. Integrates into TraderTabs' tab bar if installed; otherwise adds Supply/Buyback toggle buttons above the supply panel.
- **New:** Repurchase items using credit, inventory items as a trade-in offset, or a mix of both.
- **New:** Each buyback item shows a color-coded expiry badge (green / yellow / red) indicating days remaining.
- **New:** MCM settings for buyback: enable/disable, expiry days, max entries per trader, repurchase fee %, and minimum item rarity.
- **Fix:** Switching from the Supply tab to the Buyback tab now clears any active supply item selection, preventing the vanilla accept button from executing a supply trade instead of a buyback.

## 1.1.1

- **Fix:** "Deselect items to sell." message no longer appears when the player has trader supply items selected alongside inventory items — the sell button being disabled already communicates this.
- **Fix:** Info label now shows "Need X more credit" when the player selects trader items but has insufficient credit to cover the deficit.
- **Fix:** "Will spend X credit" and "Need X more credit" messages now clear correctly when the player clicks Reset, instead of remaining stale.

## 1.1.0

- **Change:** Removed the Barter/Credit tab toggle. The credit sell button now appears directly below the deal section in the standard barter view — no tab switching required.
- **Fix:** Deal section height is now measured correctly using the accept button's rendered position, so the sell button always lands below the deal items rather than overlapping them.
- **Polish:** Credit balance and sell-preview info (earn amount, cap warning, buy-cost notice) share a single compact row at the top of the credit area.

## 1.0.2

- **Fix:** Sell button now reliably enables when items are selected, even without trader supply items selected.
- **Fix:** Null guards on supply grid prevent crashes when used alongside mods that replace or clear the supply grid (e.g. TraderImprovements).

## 1.0.1

- **Fix:** Credit data is now isolated per save slot when the [MultiSaveSlots](https://modworkshop.net/mod/56735) mod is installed. Previously all slots shared the same credit file.
- **Fix:** Credit data is reloaded when the trader window opens, preventing stale data when switching save slots.
- **Migration:** If you have a `trader_credit.cfg` from 1.0.0, it will be automatically converted to the new `trader_credit.tres` format on first load. No manual steps required.
- **New:** Auto-update checking via the mod loader.

## 1.0.0

- Initial release.
- Sell items to traders for credit instead of rubles.
- Spend credit when buying from traders (covers the deficit between your barter offer and the asking price).
- Credit cap scales with completed tasks per trader.
- Configurable sell tax, credit per task, cap maximum, death penalty, and credit decay.
- Task completion bonuses.
