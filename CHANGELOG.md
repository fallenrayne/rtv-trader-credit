# Changelog

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
