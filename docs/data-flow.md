# Data flow — Ka0s Range Master

The core mechanic as a pipeline. The README's `## How it works` is the player-facing view of the same
pipeline; the two must not contradict each other.

## The range pipeline (plan Tasks 2 to 5)

```
consumer ─► NS.Ticker.Watch(unit)     a count per unit token; the first live unit starts the ticker
game events (target, focus, pet, mouseover, nameplate added)
  ─► NS.Ticker.Refresh(unit)          re-read now, between ticks; restarts a stopped ticker
NAME_PLATE_UNIT_REMOVED
  ─► NS.Ticker.Removed(token)         "none" at once: the token still resolves while the event runs
the ticker (one C_Timer.NewTicker, 10 Hz idle / 20 Hz in combat, stopped while no watched unit exists)
  ─► each tick: NS.Range.BeginTick()  the per-tick memo goes stale
  ─► NS.Range.Get(unit), once per unit however many consumers watch it
        no unit                        → "none"
        pcall(LibRangeCheck:GetRange(unit, true, nil, 0)); raised or secret → "unknown"
                                       (maxCacheAge 0: the library's own 0.1 s cache, keyed by
                                       token when the GUID is a secret, is never read)
        no answer, on WoW Forever      → the Compat ladder walk (spell rungs only on a friendly
                                         unit in combat; a spell rung only while it is usable)
        still no answer                → "unknown"
        otherwise                      → "known", minYd, maxYd (maxYd nil: open-ended)
  ─► RANGE_UPDATED (unit, state, minYd, maxYd)   sent only when the triple moved
  ─► each container watching the unit: NS.BandSets.Resolve → band index → recolor and re-text
                                      only on change                          (plan Tasks 3 to 5)
SPELLS_CHANGED ─► NS.Range.Rebuild()  0.5 s after the last one: the ladder and the known-spell cache
```

Everything above the band resolve exists (plan Task 2); nothing watches a unit until the containers
arrive (plan Task 5).

## Startup and the latch (plan Task 1)

```
login ─► OnInitialize: InitDB → RunMigrations → ApplySkinChoice → slash → launcher
      ─► OnEnable: SyncEnabledHold (the latch, from the stored `enabled`)
                   ─► if up: RegisterLifecycleEvents
                   ─► CreateOptionsPanel (eager category) ─► MaybeShowSkinPicker
```

- **Settings.** Every write, from the panel or `/rm set`, goes through `NS.SetByPath`: validate,
  store, one `[Set]` debug line, the row's `onChange`. `enabled`'s onChange moves the latch.
- **The latch.** `core/LifecycleSetup.lua` holds two named holds, `disabled` (the stored switch) and
  `perf` (a capture's suspended arm). The first hold taken runs `StandDown` (both modes end, the skin
  picker goes down, the lifecycle events unregister, the range ticker and the pending spell rebuild
  are canceled, and every tracked bus subscription unregisters); the last released runs `StandUp`,
  which re-registers from the settings as they are then and re-reads every watched unit.
- **The preview modes.** `NS.SetTestMode` and `NS.SetSimMode` are the one writer of each. A start is
  refused in combat and while stood down; a change sends `MODE_CHANGED (mode, on)` and refreshes an
  open panel. `PLAYER_REGEN_DISABLED` ends both (`addon:OnCombatChanged`, bracketed `combatEdge`).
- **Profiles.** A switch, copy or reset is traced once, the skin picker goes down unmarked, the new
  profile is migrated and backfilled, its skin applied, the latch re-read, and the panel refreshed.
