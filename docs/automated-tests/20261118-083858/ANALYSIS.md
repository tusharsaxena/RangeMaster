# Analysis — 20261118-083858

- **Addon:** RangeMaster 0.1.0
- **Verdict:** green
- **Commit:** a756304 (feat/v0.1.0-initial-build)
- **Previous run:** 20261118-034419

## Headline

The v0.1.0 release run (`manifest.json`, `"release": "0.1.0"`, `"dirty": false`) passes all four
suites with no function above CCN 15 and no blind or crashed file, so it meets the release gate
(`automated-tests-§3`). The headless suite passes under both kit profiles, Retail in this bundle and
WoW Forever run alongside it, at 602 passed, 1 skipped, 0 failed each. Since the scaffold baseline the
addon has roughly doubled (Tasks 2 to 8 landed): 355 to 603 cases, 4 to 13 perf scenarios, and Max CCN
went from 14 to 15, which is at the limit, not over it. Nothing blocks the tag.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261118-034419 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 111 files | [`lint.txt`](lint.txt) | files 61 → 111; still 0/0 |
| tests | pass | 602 passed, 1 skipped, 0 failed, 603 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 355 → 603 total; skips 1 → 1 |
| perf | pass | 13 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | 4 → 13 scenarios |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | Max CCN 14 → 15; warnings 0 → 0 |

| Metric | Value |
|---|---|
| Total NLOC | 16345 |
| Functions | 2538 |
| Avg NLOC / function | 5.8 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 46.5 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 0 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

The complexity run is sighted (`blindFiles` and `crashedFiles` both present and 0). Two functions sit
at CCN 15, exactly on the limit and so not warned on (`complexity.txt`):
`BandSets.Resolve` (`modules/BandSets.lua:161-175`) and the anonymous mock-builder in
`tests/wow_mock.lua:14-112`. Neither is a finding today, but the next branch added to
`BandSets.Resolve` would trip the release gate.

The tests suite ran under the kit's default Retail profile. The one skip is the kit's
`test_diagnostics_contract` opt-out case (`tests.txt`, line 565): it does not apply, because this addon
keeps the default and its report turns logging on. The addon's Clients value is Retail · Forever, so
the headless suite was also run under `KA0S_KIT_CLIENT=forever lua tests/run.lua` at the same commit:
602 passed, 0 failed, 1 skipped, 603 total. That run writes no bundle, so the figure is recorded here
only.

## What moved

- **lint:** still 0/0; the file count went from 61 to 111 because the range engine, band sets,
  containers, renderer, anchors, visibility, sounds, modes and settings pages landed. The
  `.luacheckrc` exclusions did not change (7 paths, listed in `RESULTS.md`).
- **tests:** 355 → 603 cases (+248). Failures 0 → 0, skips 1 → 1 (same kit case).
- **perf:** 4 → 13 scenarios. Of the four baseline scenarios, `settingsRead` did not move
  (0.00047 ms/iter), and `combatEdge` (0.00016 → 0.00082 ms/iter), `probeOverheadOff`
  (0.00017 → 0.00079) and `probeOverheadOn` (0.00031 → 0.00103) rose. Those brackets now run over a
  fully loaded addon, and `perf.txt` says the timings are for orientation within a run, not for
  comparison across runs. Allocation on the baseline scenarios did not move (0.0, 0.0, 0.0, 0.3
  bytes/iter). The nine new scenarios cover the range engine (`range.get`, `range.get.hit`), the
  ticker (`ticker.tick`, `ticker.tick.moving`), rendering (`render.quiet`, `container.render`,
  `render.plates.quiet`, `render.plates`) and `cursor.follow`. The quiet paths allocate little
  (`render.quiet` 36.8, `render.plates.quiet` 7.4 bytes/iter). The full repaints allocate the most:
  `container.render` 3357.4 (ten containers) and `render.plates` 6714.0 (twenty plate instances)
  bytes/iter (`perf.json`). `tests/perf.lua` builds both as the worst case, a new band on every
  instance on every tick, so this is a reading to watch in the in-game capture, not a gate.
- **complexity:** NLOC 6632 → 16345 and functions 1081 → 2538, which is growth. Avg NLOC 5.6 → 5.8
  and Avg CCN 1.9 → 2.1 rose slightly. Max CCN went 14 → 15. Warnings, band files and over-cap
  files stayed at 0.

## Complexity watch list

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|

None.

## Preview and simulation data

- **Answer:** Refreshed
- **Asked:** 2026-11-18, by hand (this release run, plan Task 9 Step 2; not via `/dev-copilot:bump-version`)
- **Files reviewed:** `modules/Preview.lua` (Test mode's placeholder, `NS.Preview.PLACEHOLDER` =
  `{ "known", 20, 25 }`), `modules/Sim.lua` (the 0 to 50 to 0 yd sweep on LibKa0s-Sim-1.0, 5 yd a step,
  1 s a step), `core/RangeMaster.lua` (the two mode writers), `tests/test_modes.lua`,
  `tests/test_skin_picker_preview.lua`
- **Commits since the previous release touching them:** 2 (there is no previous release; counted since
  the scaffold record `6ed49cb`): `9ad54b6` *Visibility rules, band sounds, Test and Sim modes* and
  `960e0ac` *Task 7: review fixes*
- **Note:** the scaffold record said the v0.1.0 release run owed this section once Test mode's
  placeholder and the Sim scenario arrived. Both arrived in Task 7, were written against the Task 3
  default band sets and the Task 5/6 render and anchor paths they drive, and are covered by
  `tests/test_modes.lua`.

## Actions

None.
