# Analysis — 20261118-034419

- **Addon:** RangeMaster 0.1.0
- **Verdict:** green
- **Commit:** 6ed49cb (feat/v0.1.0-initial-build)
- **Previous run:** none — this is the first

## Headline

The first automated-test record of the v0.1.0 scaffold: all four suites pass on a clean tree
(`manifest.json`, `"dirty": false`), with no function above CCN 15 and no blind or crashed file. It is
the baseline later releases diff against; there is nothing to act on.

## Suites

| Suite | Status | Result | Artifact | Moved since none |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 61 files | [`lint.txt`](lint.txt) | first run |
| tests | pass | 354 passed, 1 skipped, 0 failed, 355 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | first run |
| perf | pass | 4 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | first run |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | first run |

| Metric | Value |
|---|---|
| Total NLOC | 6632 |
| Functions | 1081 |
| Avg NLOC / function | 5.6 |
| Avg CCN | 1.9 |
| Max CCN | 14 |
| Avg tokens / function | 42.3 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 0 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

The tests suite ran under the kit's default Retail profile; the one skip is the kit's
`test_diagnostics_contract` opt-out case, which does not apply because this addon keeps the default
(a report turns logging on), as `tests.txt` states. The WoW Forever profile is held by the commit gate
(`KA0S_KIT_CLIENT=forever lua tests/run.lua`, 354 passed, 1 skipped at this commit), which this
runner's `tests` suite does not record.

## What moved

First run — nothing to diff against; every figure above is a baseline reading.

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

- **Answer:** Not applicable
- **Asked:** 2026-11-18, by hand (the scaffold's first record, not a version bump)
- **Files reviewed:** `core/RangeMaster.lua` (Test mode and Sim mode's writers), `tests/test_modes.lua`,
  `tests/test_skin_picker_preview.lua`
- **Commits since the previous release touching them:** none; there is no previous release
- **Note:** the scaffold carries the two mode switches and their suites but no test-mode placeholder
  data and no simulator scenario yet; both arrive with the renderer and LibKa0s-Sim in plan Task 7,
  and the v0.1.0 release run owes this section again then.

## Actions

None.
