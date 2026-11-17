# Performance — Ka0s Range Master

How much this addon costs, how it is measured, and what the measurements can and cannot resolve
(performance). The probe, the record schema and the step panel are `LibKa0s-Perf-1.0`'s; the shared
protocol and the record contract live with the library (its `docs/record-schema.md`), and this page
points there rather than restating them.

## What is bracketed

`core/PerfSetup.lua` declares the buckets, in report order; each is reached by a real bracket of the
shape `local t0 = Perf.on and debugprofilestop() ... if t0 then Perf.Note(key, ...) end`
(performance-§2), which costs one upvalue read, one field read and one boolean test while capture is
off.

| Bucket | Bracket | Why |
|---|---|---|
| `combatEdge` | `addon:OnCombatChanged` (`core/RangeMaster.lua`) | the scaffold's one event-driven path: ends the preview modes at the pull |

The range engine's hot paths join with plan Task 2: `tickerTick` (the shared ticker's pass) and
`rangeGet` (one unit's range read, `within = "tickerTick"`). That ticker, 10 Hz idle and 20 Hz in
combat, is where this addon's steady cost will live, and it is bounded to the units a display watches.

## Taking a capture

`/rm perf` opens the step panel, which offers only the next legal step. The suspended arm takes the
`perf` hold on the same latch `/rm disable` uses (`core/LifecycleSetup.lua`), so a capture's inert
half is exactly the disabled state, and a resume never stands up an addon the player switched off.
Captures land in `RangeMasterPerfDB`, outside AceDB, and are recorded into `docs/perf-analysis/` with
`/dev-copilot:wow-perf-analysis`.

## Offline scenarios

`lua tests/perf.lua` runs deterministic offline scenarios (allocations per pass, never wall-clock
time) outside the commit gate, recorded by the automated-test runner's `perf` suite: the combat edge,
the settings read, and the zero-overhead scenario that proves a dormant bracket costs nothing an armed
one does not. Offline numbers are never cited as in-game evidence; in-game captures are their own
store.

## What it cannot resolve

The harness measures this addon's Lua time and allocations. It cannot attribute the client's own
cost of the range checks LibRangeCheck makes, and it cannot see frame-time differences under 0.1 ms
per frame on a busy client.
