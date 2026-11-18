# Data flow — Ka0s Range Master

The core mechanic as a pipeline. The README's `## How it works` is the player-facing view of the same
pipeline; the two must not contradict each other.

## The range pipeline (plan Tasks 2 to 5)

```
consumer ─► NS.Ticker.Watch(unit)     a count per unit token; the first live unit starts the ticker
game events (target, focus, pet, mouseover, nameplate added, UNIT_FACTION): a unit change
  ─► NS.Container.UnitChanged(unit)   its instances forget the band, set, colors and chip answers
  ─► NS.Ticker.Changed(unit)          re-read now, between ticks, and sent even when the triple did
                                      not move; restarts a stopped ticker
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
  ─► RANGE_UPDATED (unit, state, minYd, maxYd)   sent only when the triple moved (or on Changed)
  ─► else NS.Ticker.OnSteady(unit)    the renderer: an instance with spell chips asks each again and
                                      renders only when an answer moved (an edge inside a bracket)
  ─► modules/Container.lua: the instances watching that unit, and no other (bucket container.render)
        NS.Range.InSpellRange per spell chip → inst:Render(state, minYd, maxYd, spellResults)
        NS.BandSets.ForUnit (the friendly override) → NS.BandSets.Resolve → band index
        band or set changed → recolor the border, the fill and every element (else nothing)
        text changed        → SetText (else nothing); a cell's width moved → re-layout
SPELLS_CHANGED ─► NS.Range.Rebuild()  0.5 s after the last one: the ladder and the known-spell cache
```

Every container instance watches its unit through `NS.Ticker.Watch` when it is acquired and
`Unwatch`es it when it goes back to the pool, so the ticker runs exactly while a drawn container has
a live unit. A `nameplates` container watches through its per-plate instances, one per eligible plate
token, each watched from `NAME_PLATE_UNIT_ADDED` (`NS.Plates.Added`) until `_REMOVED` parks it.

## Placement (plan Task 6)

```
CONTAINERS_CHANGED ─► NS.Container.Sync ─► inst:Apply ─► NS.Anchors.Apply(inst, c)
     screen     stored point on UIParent; unlocked: drag strip ─► drag stop ─► NS.CM.SetPosition
     frame      NS.FrameProviders.Resolve ─► found: SetPoint on it (held in combat → PLAYER_REGEN_ENABLED)
                                          └► missing: hidden, one debug line ─► ADDON_LOADED /
                                             PLAYER_ENTERING_WORLD ─► Retry
     nameplate  NS.Plates.Get(unit) ─► on the plate, or hidden; re-placed on the unit change and plates
     plates     (nameplates container) NS.Plates.SyncAll ─► one instance per hostile plate (all with
                includeFriendly)
     cursor     one shared OnUpdate while a cursor container is shown ─► GetCursorPosition / scale
NAME_PLATE_UNIT_ADDED ─► NS.Plates.Added ─► track (forbidden: nil) ─► instances built, own plates placed
                      └► next frame: the same again (a plate populated late)
NAME_PLATE_UNIT_REMOVED ─► NS.Plates.Removed ─► instances parked; own-plate container on that plate
                           frame hidden ─► next frame: placed again ─► NS.Ticker.Removed
```

## Container writes (plan Task 4)

```
NS.CM.Create / Delete / Duplicate / Rename / CopySettings / RestoreSnapshot, NS.Presets.Apply / Undo
  ─► the registry written at once
  ─► NS.CM.RequestApply()             one zero-delay C_Timer per frame, however many writes
  ─► next frame: FlushPending         in combat: held (one debug line) until PLAYER_REGEN_ENABLED
  ─► CONTAINERS_CHANGED               once; the renderer and the settings pages (Task 8)
  ─► NS.Container.Sync()              an instance for every enabled container (Acquire: the pooled
                                      frame, its settings applied, its unit watched), back to the
                                      pool for a deleted or disabled one
BANDSETS_CHANGED ─► NS.Container.Repaint()   every instance repaints from its last triple
the skin's OnLooksChanged ─► NS.CM.RequestApply()   the HUD face follows the skin, next frame,
                                                    held through combat like every apply
```

A stood-down addon arms no timer; the stand-up asks for one apply.

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
