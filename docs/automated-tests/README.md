# Automated test records

Every run of the four out-of-game suites, recorded. The normative rules are the standard's
[`automated-tests`](https://github.com/tusharsaxena/WowAddonStandards/blob/master/standards/standards/automated-tests.md)
section; this file is the local how-to.

## Running

```sh
tests/_kit/run-automated-tests.sh                            # all four, writes a bundle
tests/_kit/run-automated-tests.sh --release 0.1.0            # the release run, before a tag
tests/_kit/run-automated-tests.sh --suite complexity         # a subset
tests/_kit/run-automated-tests.sh --suite lint --suite tests --no-bundle   # the green gate; writes nothing
KA0S_KIT_CLIENT=forever tests/_kit/run-automated-tests.sh --suite tests --no-bundle   # the suite as WoW Forever
```

Run each through `~/.claude/dev-copilot/bin/ka0s-bounded`. The runner is **vendored** from
`LibKa0s`'s `testkit/` and is byte-identical in every Ka0s addon. Never edit `tests/_kit/` — a kit fix
goes upstream and is re-vendored, and a local patch is reverted silently by the next re-vendor.

## What gates, and what only records

There are **two checkpoints** — the run (and the commit it gates) and the release tag — and a suite's
answer differs between them:

| Suite | Command | Run + commit | Release tag |
|---|---|---|---|
| `lint` | `luacheck .` | **gates** | **gates** |
| `tests` | `lua tests/run.lua` (and `KA0S_KIT_CLIENT=forever lua tests/run.lua`) | **gates** | **gates** |
| `perf` | `lua tests/perf.lua` | no — recorded | **gates** — `pass` required |
| `complexity` | `bash tests/_kit/run-automated-tests.sh --suite complexity` (lizard `-L 1500` over the kit's sighted shadow) | no — recorded | **gates** — `pass`, zero functions above CCN 15, `blindFiles` and `crashedFiles` at 0 |

`perf` and `complexity` are **measured, recorded and diffed — they never fail a run and never block a
commit** (`performance-§9`, `performance-§10`). A threshold that fails a run teaches everyone to reach
for `--no-verify`, after which the gate protects nothing. They contribute `amber`, a signal rather than
a stop.

**At the tag all four gate** (`automated-tests-§3`, *The release gate*): `/dev-copilot:bump-version`
reads the release run's `manifest.json` and refuses unless all four suites are at `pass` with
`suites.complexity.warnings` at `0`. It is a separate checkpoint evaluated by a separate actor — this
runner's exit code is unchanged — and a `skip` there is **NOT EVALUATED**, never a pass.

**A missing tool is a skip, not a failure**, and the skip is recorded with its reason, so a green run
that measured nothing cannot be mistaken for one that measured everything.

## What is here

- **`RESULTS.md`** — one row per run across all four suites, plus the current complexity watch list.
  **One file, overwritten in place**: the git history of that single path is the trend line. Generated
  by the runner; the watch list's `Disposition` column is the one hand-written cell.
- **`<YYYYMMDD-HHMMSS>/`** — one frozen bundle per run: `manifest.json`, one file per suite, and
  `ANALYSIS.md` (the write-up). Bundles are **never edited** once written and **never pruned**.

Offline perf records live in the bundle with the run that produced them. **In-game** captures cannot
be produced by a script, so they keep their own standing store at [`../perf-analysis/`](../perf-analysis/).
