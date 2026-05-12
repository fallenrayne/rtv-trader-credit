# Trader Credit — TODO

## Bugs
- [ ] Credit panel is taller than the Barter panel — they should match height

## UX / Polish
- [ ] Credit-buy mode is invisible — when the accept button is enabled by credit,
      show the cost somewhere near it (e.g. "Will spend 340 credit") so the player
      knows what's happening before they click
- [ ] Silent decay — show a message on interface open when a balance has decayed
      since the last visit (e.g. "Your credit with [Trader] decayed to 240")
- [ ] Tab buttons have no active state — the selected tab only dims the other one;
      use a proper pressed/highlighted style so the active tab is obvious

## Config
- [ ] Add `decay_floor` setting — a minimum balance below which decay stops
      (e.g. never decay below 20% of cap); prevents decay from silently zeroing out
- [ ] Add `credit_cap_max` setting — an optional hard ceiling on credit regardless
      of how many tasks the player has completed

## Robustness
- [ ] `CreditLedger._config` is fetched in `_ready()` with no null guard — add a
      fallback so the mod doesn't silently break if `TraderCreditConfig` isn't in
      the tree yet
- [ ] `load_state()` is only called on respawn — if the player can load a different
      save slot mid-session, credit state won't refresh; hook into save-slot changes
      if the game exposes that event
