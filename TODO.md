# Trader Credit — TODO

## Bugs
- [x] Credit panel is taller than the Barter panel — they should match height

## UX / Polish
- [x] Credit-buy mode is invisible — when the accept button is enabled by credit,
      show the cost somewhere near it (e.g. "Will spend 340 credit") so the player
      knows what's happening before they click
- [ ] Silent decay — show a message on interface open when a balance has decayed
      since the last visit (e.g. "Your credit with [Trader] decayed to 240")
- [x] Tab buttons have no active state — the selected tab only dims the other one;
      use a proper pressed/highlighted style so the active tab is obvious

## Config
- [x] Add `decay_floor` setting — a minimum balance below which decay stops
      (e.g. never decay below 20% of cap); prevents decay from silently zeroing out
- [x] Add `credit_cap_max` setting — an optional hard ceiling on credit regardless
      of how many tasks the player has completed

## Features
- [ ] **Item buyback** — when you sell something for credit, the trader holds it for a
      configurable number of in-game days before it re-enters general stock. A "Buyback" tab
      lets you repurchase it at cost (or cost + small fee) during that window
- [x] **Task completion credit bonus** — on task complete, award a one-time credit bonus
      (configurable, separate from the cap increase). Closes the loop: tasks raise the cap
      AND partially fill it, making the task → credit → spend cycle feel cohesive

## i18n
- [ ] All user-facing strings are hardcoded in English — extract them into a translation
      file so the mod can be localized (Godot uses `.po`/`.translation` files; check
      whether RTV's mod loader supports `TranslationServer` or if a simpler string-table
      approach is needed)

## Robustness
- [x] `CreditLedger._config` is fetched in `_ready()` with no null guard — add a
      fallback so the mod doesn't silently break if `TraderCreditConfig` isn't in
      the tree yet
- [ ] `load_state()` is only called on respawn — if the player can load a different
      save slot mid-session, credit state won't refresh; hook into save-slot changes
      if the game exposes that event
