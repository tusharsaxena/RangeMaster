# Analysis — 20261118-100423

- **Addon:** RangeMaster 0.1.0
- **Verdict:** green
- **Commit:** 856a672 (feat/v0.1.0-initial-build)
- **Previous run:** 20261118-091529

## Headline

The v0.1.0 release run, refreshed after the review fixes (`manifest.json`, `"release": "0.1.0"`,
`"dirty": false`), passes all four suites. No function is above CCN 15 and no file is blind or
crashed, so it still meets the release gate (`automated-tests-§3`). The headless suite passes under
both kit profiles at 619 passed, 1 skipped, 0 failed each. The review fixes added 9 cases
(611 → 620 total) and moved no gate. Nothing blocks the tag.

## Suites

| Suite | Status | Result | Artifact | Moved since 20261118-091529 |
|---|---|---|---|---|
| lint | pass | 0 warnings / 0 errors in 111 files | [`lint.txt`](lint.txt) | none |
| tests | pass | 619 passed, 1 skipped, 0 failed, 620 total | [`tests.txt`](tests.txt) · [`test-cases.md`](test-cases.md) | 611 → 620 total; skips 1 → 1 |
| perf | pass | 13 scenarios | [`perf.txt`](perf.txt) · [`perf.json`](perf.json) | none in allocation |
| complexity | pass | see below | [`complexity.txt`](complexity.txt) | Max CCN 15 → 15; warnings 0 → 0 |

| Metric | Value |
|---|---|
| Total NLOC | 16813 |
| Functions | 2601 |
| Avg NLOC / function | 5.9 |
| Avg CCN | 2.1 |
| Max CCN | 15 |
| Avg tokens / function | 46.8 |
| Warnings (CCN > 15) | 0 |
| Warning rate (`Fun Rt` / `nloc Rt`) | 0.00 / 0.00 |
| Files in the 1000–1500 band | 0 |
| Files over the 1500 cap | 0 |
| Blind files (parity mismatch) | 0 |
| Crashed files (lizard raised) | 0 |

The complexity run is sighted (`blindFiles` and `crashedFiles` both present and 0). The same two
functions as last run sit at CCN 15, on the limit and not warned on: `BandSets.Resolve`
(`modules/BandSets.lua`) and the anonymous mock-builder in `tests/wow_mock.lua`. The review fixes did
not touch `BandSets.Resolve`.

The tests suite ran under the kit's default Retail profile. The one skip is the kit's
`test_diagnostics_contract` opt-out case, which does not apply: this addon keeps the default and its
report turns logging on. The Clients value is Retail · Forever, so the suite was also run with
`KA0S_KIT_CLIENT=forever tests/_kit/run-automated-tests.sh --suite tests --no-bundle` at the same
commit: 619 passed, 0 failed, 1 skipped, 620 total. That run writes no bundle, so the figure is
recorded here only.

## What moved

- **lint:** still 0/0 over 111 files; no file added or removed.
- **tests:** 611 → 620 cases, 610 → 619 passing (+9): the
  login first draw and the logged-in class's chips in `test_container_render.lua`; per-instance level
  bases and the strata whitelist in `test_layers.lua`; the picker's ignored mouse press in
  `test_anchors_frame.lua` (its left-click and right-click cases now drive Enter and Escape); the
  band-set delete through `NS.CM.SetField` in `test_bandsets.lua`; the cleared screen clamp in
  `test_anchors_screen.lua`; chips following the character in `test_container_manager.lua`; and the
  lazy ladder in `test_range.lua`. Failures 0 → 0, skips 1 → 1.
- **perf:** 13 scenarios, as before. Bytes per iteration did not move in any scenario except
  `probeOverheadOn`, 0.3 → 0.0. The new dormant-bracket check (call counts with capture off over the
  moving tick and the combat edge, with an armed control) is an assertion inside the renderer
  scenario block and adds no row. It passed: `perf.txt` lists no failed assertion. Timings roughly
  doubled across the board (`container.render` 0.08224 → 0.16533 ms/iter, `combatEdge` 0.00113 →
  0.00161). The run queued behind other bounded runs on a busy machine, and `perf.txt` says timings
  orient within a run rather than across runs.
- **complexity:** NLOC 16612 → 16813 and functions 2568 → 2601, from the new cases and the small
  helpers the fixes added (`NS.CM.SpellChips`, `NS.ConfirmDeleteContainer`, `Range.__rebuildCount`).
  Avg tokens 46.7 → 46.8. Avg NLOC, Avg CCN, Max CCN, warnings and band files unchanged.

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

- **Answer:** Current
- **Asked:** 2026-11-18, by hand (the review-fix refresh of the v0.1.0 release run)
- **Files reviewed:** `modules/Preview.lua`, `modules/Sim.lua`, `core/RangeMaster.lua`
- **Commits since the previous release run touching them:** 1 (856a672 touches `core/RangeMaster.lua`
  only, for the login apply and a comment; Test mode's placeholder and the Sim sweep are unchanged)
- **Note:** the review fixes changed no preview or simulation data.

## Actions

1. In-game smoke checks owed for the review fixes, listed in
   `docs/reviews/2026-11-18/03_SMOKE_TESTS.md`: the first draw at login on the default skin
   (F-001), the Enter/Escape picker (F-002, `docs/smoke-tests.md` ANCHOR-8), and overlapping displays
   (F-003). New here; owned by the review findings.
2. The spell-chip list editor (F-004's deferred alternative) is not yet filed as an issue. New here.
