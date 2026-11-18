# Automated test results

<!-- Regenerated whole by tests/_kit/run-automated-tests.sh on every run. -->
<!-- This file is OVERWRITTEN IN PLACE — the git history of this one path is the trend line. -->
<!-- Everything here is generated EXCEPT the watch list's Disposition column. -->

One row per run. The frozen evidence for each is in the dated folder beside this file;
the analysis of a given run is its `ANALYSIS.md`.

**`lint` and `tests` gate the run and gate the commit** (`testing-§4`).
**`perf` and `complexity` never fail a run and never block a commit** — they are recorded,
read and compared, not thresholded (`performance-§9`, `performance-§10`).

**The tag is gated on all four suites at `pass`, plus zero functions above CCN 15**
(`automated-tests-§3`, *The release gate*), evaluated by `/dev-copilot:bump-version` from the
`manifest.json` the release run writes — not by this script, whose exit code is unchanged.

A `skip` is a suite that did not run at all. It is never a pass, and at the release gate it is
**NOT EVALUATED** rather than passed: install the tool and re-run. A `—` is a suite that was
not selected, which is a different fact again.

The **Tests** cell reads `passed/skipped/total`.

**Commit** is the short sha the run measured and **Tree** is whether that tree was clean at the
time. Both are read from git by the runner; neither is ever typed. A **dirty** row measured bytes
that no sha can bring back, so it is kept as an experiment honestly labeled rather than dropped —
and a release record is refused outright on a dirty tree, so no release row can be one.

A row reading `unknown` in both cells was recorded before the runner emitted them. That is what
the record holds about those runs — it is not `clean`, and it is not reconstructed from git
archaeology, for the same reason a skip is never a pass (`automated-tests-§4`).

| Run | Commit | Tree | Version | Lint w/e | Files | Tests | Perf | NLOC | Funcs | Avg NLOC | Avg CCN | Max CCN | CCN warn | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| [`20261118-091529`](20261118-091529/) | `87a5620` | clean | 0.1.0 → 0.1.0 | 0/0 | 111 | 610/1/611 | pass | 16612 | 2568 | 5.9 | 2.1 | 15 | 0 | **green** |
| [`20261118-083858`](20261118-083858/) | `a756304` | clean | 0.1.0 → 0.1.0 | 0/0 | 111 | 602/1/603 | pass | 16345 | 2538 | 5.8 | 2.1 | 15 | 0 | **green** |
| [`20261118-034419`](20261118-034419/) | `6ed49cb` | clean | 0.1.0 → 0.1.0 | 0/0 | 61 | 354/1/355 | pass | 6632 | 1081 | 5.6 | 1.9 | 14 | 0 | **green** |

## Test suite

**611 cases** — 610 passed, 0 failed, 1 skipped. The generated inventory
[`20261118-091529/test-cases.md`](20261118-091529/test-cases.md) is the authority on which cases existed at this run;
`docs/test-cases.md` is that same list at HEAD.

Moved **603 → 611** since the previous run.

**1 case(s) reported a `skip`.** A skip is counted in the total and never in `passed`, and at
the release gate it is NOT EVALUATED rather than passed (`automated-tests-§3`).

## Lint

**0 warnings / 0 errors over 111 files** (`luacheck .`).

Read that figure with its scope attached: `.luacheckrc` excludes 7 path(s) from it — `libs/`, `tests/_kit/`, `docs/audits/`, `docs/reviews/`, `docs/revendor/`, `docs/automated-tests/`, `_dev/` —
so nothing under them is in the count above. A `0/0` that never moves is partly a statement about
what was never looked at, which is why the exclusions are NAMED here on every run rather than left
to whoever thinks to open `.luacheckrc`.

## Perf

**13 scenarios** from `tests/perf.lua`; the measurements are in
[`20261118-091529/perf.json`](20261118-091529/perf.json).

| `scenario` | `iters` | `ms/iter` | `total-ms` | `bytes/iter` |
|---|---|---|---|---|
| `combatEdge` | 1000 | 0.00113 | 1.133 | 0.0 |
| `settingsRead` | 10000 | 0.00047 | 4.704 | 0.0 |
| `range.get` | 10000 | 0.00076 | 7.561 | 0.0 |
| `range.get.hit` | 10000 | 0.00007 | 0.686 | 0.0 |
| `ticker.tick` | 1000 | 0.02139 | 21.394 | 16.9 |
| `ticker.tick.moving` | 1000 | 0.02680 | 26.798 | 16.4 |
| `render.quiet` | 1000 | 0.00630 | 6.302 | 36.8 |
| `container.render` | 1000 | 0.08224 | 82.244 | 3357.4 |
| `render.plates.quiet` | 1000 | 0.02442 | 24.420 | 7.4 |
| `render.plates` | 1000 | 0.16389 | 163.886 | 6714.0 |
| `cursor.follow` | 10000 | 0.00166 | 16.614 | 0.0 |
| `probeOverheadOff` | 1000 | 0.00080 | 0.801 | 0.0 |
| `probeOverheadOn` | 1000 | 0.00101 | 1.012 | 0.3 |

`perf` never fails a run and never blocks a commit — it is recorded, read and compared, not
thresholded (`performance-§9`). It does gate the **tag** (`automated-tests-§3`).

## Complexity watch list

Current as of [`20261118-091529`](20261118-091529/) — **this run's measurement, not its diff.** Max CCN **15** across 2568
functions, **0** of them warned on; 0 file(s) in the 1000–1500 band and 0 over the 1500 cap
(`layout-§1`).

Every row below is generated from this run's own `lizard` output. **The `Disposition` column is
the one authored cell in this file** (`automated-tests-§4`, *the one boundary*): it is carried
forward verbatim while its entry is unchanged, and left **blank** when the entry is new — a blank
cell is this file saying something crossed and nobody has ruled on it yet.

### Functions `lizard` warned on

| Function | CCN | Location | Disposition |
|---|---|---|---|

None.

### Files by `layout-§1` band

| Band | File | LOC | Disposition |
|---|---|---|---|

None.

`lizard` counts every `and`/`or` short-circuit as a decision, so in Lua a run of
`t.k = rec.k or D.k` defaulting lines scores high with no visible branching at all: a large CCN
here usually means *this function defaults or guards a lot of fields* rather than *this function
is tangled*, and the two want different fixes (`performance-§10`).

