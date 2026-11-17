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
| `combatEdge` | `addon:OnCombatChanged` (`core/RangeMaster.lua`) | ends the preview modes at the pull and re-arms the range ticker at the edge's rate |
| `ticker.tick` | the ticker's callback (`modules/Ticker.lua`) | a fresh memo and one read of every watched unit, 10 or 20 times a second while a watched unit exists: the addon's steady cost, bounded by units, never by containers |
| `range.get` | `NS.Range.Get` on a memo miss (`modules/Range.lua`) | LibRangeCheck's `GetRange` behind the guards, and on Forever the ladder walk |

`range.get` is declared `within = "ticker.tick"`: every tick runs it there. An event's forced refresh
runs it at top level, so each call passes the parent it observed to `Perf.Note` (the ticker names
`"ticker.tick"` through `NS.Range.SetPerfParent` for the length of its pass, `false` otherwise), and the
record reports the mix rather than a reader summing two totals that overlap.

## Taking a capture

`/rm perf` opens the step panel, which offers only the next legal step. The suspended arm takes the
`perf` hold on the same latch `/rm disable` uses (`core/LifecycleSetup.lua`), so a capture's inert
half is exactly the disabled state, and a resume never stands up an addon the player switched off.
Captures land in `RangeMasterPerfDB`, outside AceDB, and are recorded into `docs/perf-analysis/` with
`/dev-copilot:wow-perf-analysis`.

## Offline scenarios

`lua tests/perf.lua` runs deterministic offline scenarios (allocations per pass, never wall-clock
time) outside the commit gate, recorded by the automated-test runner's `perf` suite: the combat edge,
the settings read, a range read on a memo miss (`range.get`, asserted not to allocate) and on a hit,
the ticker's tick at the design spec's load (ten containers over target, focus, pet and mouseover
plus twenty plates, 24 units: `ticker.tick` with nothing moving, asserted near-free, and
`ticker.tick.moving` with every unit moving every tick), and the zero-overhead scenario that proves a
dormant bracket costs nothing an armed one does not. LibRangeCheck's own `GetRange` answers a fixed
bracket there: its cost is the library's. Offline numbers are never cited as in-game evidence; in-game captures are their own
store.

## What it cannot resolve

The harness measures this addon's Lua time and allocations. It cannot attribute the client's own
cost of the range checks LibRangeCheck makes, and it cannot see frame-time differences under 0.1 ms
per frame on a busy client.
