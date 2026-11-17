# Data flow — Ka0s Range Master

The core mechanic as a pipeline. The README's `## How it works` is the player-facing view of the same
pipeline; the two must not contradict each other.

## The range pipeline (plan Tasks 2 to 5)

```
game events (target, focus, pet, mouseover, nameplates, spells changed)
  ─► NS.Ticker.Watch(unit)            one shared C_Timer ticker, 10 Hz idle / 20 Hz in combat
  ─► each tick: NS.Range.BeginTick()  the per-tick memo cleared
  ─► NS.Range.Get(unit)               pcall(LibRangeCheck:GetRange(unit, true)), issecretvalue
                                      checked; secret or error → "unknown"; no unit → "none"
  ─► RANGE_UPDATED (unit, state, minYd, maxYd)   sent only when the bracket moved
  ─► each container watching the unit: NS.BandSets.Resolve → band index → recolor and re-text
                                      only on change
```

None of this exists in the scaffold. It is the plan of record, and each stage arrives with its task.

## What exists today (plan Task 1)

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
  picker goes down, the lifecycle events and every tracked bus subscription unregister); the last
  released runs `StandUp`, which re-registers from the settings as they are then.
- **The preview modes.** `NS.SetTestMode` and `NS.SetSimMode` are the one writer of each. A start is
  refused in combat and while stood down; a change sends `MODE_CHANGED (mode, on)` and refreshes an
  open panel. `PLAYER_REGEN_DISABLED` ends both (`addon:OnCombatChanged`, bracketed `combatEdge`).
- **Profiles.** A switch, copy or reset is traced once, the skin picker goes down unmarked, the new
  profile is migrated and backfilled, its skin applied, the latch re-read, and the panel refreshed.
