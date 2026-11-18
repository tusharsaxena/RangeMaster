# Analysis — 20261118-091529

- **Addon:** RangeMaster 0.1.0
- **Verdict:** green
- **Commit:** 87a5620 (feat/v0.1.0-initial-build)
- **Previous run:** 20261118-083858

## Headline

The v0.1.0 release run, refreshed after the first standards audit's fixes (`manifest.json`,
`"release": "0.1.0"`, `"dirty": false`), passes all four suites with no function above CCN 15 and no
blind or crashed file, so it still meets the release gate (`automated-tests-§3`). The headless suite
passes under both kit profiles at 610 passed, 1 skipped, 0 failed each. The audit fixes added 8 cases
(603 → 611) and moved no gate. Nothing blocks the tag.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261118-083858 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 111 files | [`lint.txt`](lint.txt) | none |
| tests | pass | 610 passed, 1 skipped, 0 failed, 611 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 603 → 611 total; skips 1 → 1 |
| perf | pass | 13 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | none in allocation |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | Max CCN 15 → 15; warnings 0 → 0 |

| Metric | Value |
|---|---|
| Total NLOC | 16612 |
| Functions | 2568 |
| Avg NLOC / function | 5.9 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 46.7 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 0 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

The complexity run is sighted (`blindFiles` and `crashedFiles` both present and 0). The same two
functions as last run sit at CCN 15, on the limit and not warned on: `BandSets.Resolve`
(`modules/BandSets.lua`) and the anonymous mock-builder in `tests/wow_mock.lua`. No function the audit
fixes touched came near the limit.

The tests suite ran under the kit's default Retail profile. The one skip is the kit's
`test_diagnostics_contract` opt-out case, which does not apply: this addon keeps the default and its
report turns logging on. The Clients value is Retail · Forever, so the suite was also run under
`KA0S_KIT_CLIENT=forever lua tests/run.lua` at the same commit: 610 passed, 0 failed, 1 skipped, 611
total. That run writes no bundle, so the figure is recorded here only.

## What moved

- **lint:** still 0/0 over 111 files; no file added or removed.
- **tests:** 603 → 611 cases (+8): four in `test_disabled.lua` (the combat-owed skin notice, step 5's
  hidden frames, the perf-hold refusal, the container made while disabled; the step-4 and step-8
  assertions are folded into existing cases), one in `test_range.lua` (a rebuild asked while stood down),
  one in `test_container_manager.lua` (the `seeded` sentinel's one writer) and two in `test_docs.lua`
  (the README H1 and the vendored quirks block). Failures 0 → 0, skips 1 → 1.
- **perf:** 13 scenarios, as before. Allocation per iteration did not move in any scenario. Timings
  moved within run-to-run noise (`combatEdge` 0.00082 → 0.00113 ms/iter, `container.render` 0.07431 →
  0.08224), and `perf.txt` says the timings orient within a run rather than compare across runs.
- **complexity:** NLOC 16345 → 16612 and functions 2538 → 2568, from the new cases and the small
  helpers the fixes added (`NS.RefusalLine`, `NS.DropSkinNoticeWait`, `CM.MarkSeeded`,
  `Range.RunOwedRebuild`). Avg NLOC 5.8 → 5.9; Avg CCN, Max CCN, warnings and band files unchanged.

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

- **Answer:** Unchanged
- **Asked:** 2026-11-18, by hand (the audit-fix refresh of the v0.1.0 release run)
- **Files reviewed:** `modules/Preview.lua`, `modules/Sim.lua`, `core/RangeMaster.lua`
- **Commits since the previous release run touching them:** 0
- **Note:** the 20261118-083858 run refreshed this section; the audit fixes did not touch Test mode's
  placeholder or the Sim sweep.

## Actions

None.
