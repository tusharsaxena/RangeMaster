# Testing

How to verify Ka0s Range Master (testing-§6). What to install first is root `DEPENDENCIES.md`; this
page is how to run it. Every command runs from the repo root.

## The green commit gate

All four must pass before **every** commit (testing-§4):

| Check | Command | Expected |
|---|---|---|
| Headless suite | `lua tests/run.lua` | every suite green; exits non-zero on any failure |
| Headless suite, as WoW Forever | `KA0S_KIT_CLIENT=forever lua tests/run.lua` | the same, under the kit's `forever` profile. The addon serves Retail and WoW Forever, so both runs gate (clients-§6); `tests/test_compat.lua` asserts the client answer each profile gives, and the kit's `test_client_globals` suite checks the tracked source against both clients' API sets |
| Lint | `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` | `0 warnings / 0 errors` |
| Seed tool | `python3 -m pytest -q -p no:cacheprovider tools/seeds` | every case passes; no network (the seed-validation contract's own gate, `docs/validate-seeds.md`) |
| Syntax-check one file | `luac -p path/to/file.lua` | no output |

The kit bounds the suite on load; `luacheck` loads no kit, so it runs through the bounded runner
(testing-§15). `tests/_kit/run-automated-tests.sh --suite lint --suite tests --no-bundle` runs lint and
the Retail suite and writes nothing; with `KA0S_KIT_CLIENT=forever` in front, its `tests` suite runs as
WoW Forever.

## The four out-of-game suites and their checkpoints

There are two checkpoints — the run and the commit it gates, and the release tag — and a suite's
answer differs between them (automated-tests-§3):

| Suite | Command | Run + commit | Release tag |
|---|---|---|---|
| `lint` | `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` | **gates** | **gates** |
| `tests` | `lua tests/run.lua`, then `KA0S_KIT_CLIENT=forever lua tests/run.lua` | **gates**, both profiles | **gates**, both profiles |
| `perf` | `lua tests/perf.lua` | does not gate — recorded | **gates** — must be `pass` |
| `complexity` | `bash tests/_kit/run-automated-tests.sh --suite complexity` (lizard over the kit's sighted shadow) | does not gate — recorded | **gates** — `pass` with zero functions above CCN 15 and no blind or crashed file |

`perf` and `complexity` never fail a run and never block a commit (performance-§9, performance-§10): a
threshold that fails a run teaches everyone to reach for `--no-verify`. The **tag** is a separate
checkpoint: `/dev-copilot:bump-version` cuts the release only when the release run's `manifest.json`
shows all four suites at `pass`, `suites.complexity.warnings` at `0` and `blindFiles` at `0`. A
**skip** there is **not evaluated**, never a pass. The runner's own exit code is unchanged. Recording
those runs is `docs/automated-tests/README.md`.

**The complexity suite is sighted.** lizard loses whole Lua functions over `#` and a handful of bare
words, so the runner never runs it over the tree: it measures a sanitized shadow built by
`tests/_kit/lizard_sighted.lua` and compares each file's `function` tokens with what lizard lists. The
kit's `test_lizard_sighted` suite pins the sanitizer.

## What the headless suite is

`tests/run.lua` loads the vendored LibKa0s files in `LibKa0s.xml` order, then the vendored
LibRangeCheck-3.0 (its own TOC line, which `Loader.tocFiles` skips), then the addon's own files
straight from `RangeMaster.toc` (testing-§9), on the mock from `tests/wow_mock.lua` (a thin extender
over the kit's `mock_base.lua`). It mirrors the in-game lifecycle (`OnInitialize`, then `OnEnable`)
and runs the declared suite list through `Kit.run`, which fails the run on a suite on disk but not
declared, or declared but missing. Every kit suite is declared by its directory.

It proves what can be proved without a client: the setup files' descriptors and their degradation
stubs (loaded for real with LibKa0s absent, `tests/degraded_env.lua`), the schema and its write seam,
the latch and the disabled state, the range engine over a scripted LibRangeCheck and Compat ladder
(secrets, raises, a unit vanishing mid-tick), the ticker's rate and stop, the anchor resolver and its
rebuild triggers, the band-set normalizer and resolver with its spell, dead-zone and beyond rules (the
owner's Hawk Eye case among them), the v1 -> v2 band-rule migration, the container registry and the presets, the renderer's elements, the four anchor modes
(screen drag, unit frames missing and then loaded, combat-held writes, nameplate recycling, the
cursor), the visibility and sound rules, Test mode and Sim mode, the slash surface, the launcher, the
skin seam, the settings pages and their selection-relative rows, and the documentation gates. The
anchor suites share `tests/anchors_env.lua` and the settings suites `tests/settings_env.lua`. It
cannot see a real range, a secret value the client returns, taint or drawn frames: that is the smoke
suite, `docs/smoke-tests.md`.

Suites named by the rules that mandate them: `tests/test_surface_parity.lua` (testing-§8: every
degradation stub carries the live surface), `tests/test_vendor_sync.lua` (testing-§11: delegates to the
kit's `vendor_sync.lua` against the tag on `CLAUDE.md`'s Bundles line) and `tests/test_disabled.lua`
(slash-commands-§7, the ten steps). The kit's own suites are wired too: `test_prose`, `test_eol`,
`test_layout_cap`, `test_diagnostics_contract`, `test_lizard_sighted`, `test_skin_values`,
`test_skin_switch` and `test_client_globals`.

## The case inventory

`docs/test-cases.md` is generated: `lua tests/run.lua --list > docs/test-cases.md`. Its Total is the
authoritative pass count, and the README's `[tests]` badge equals it (testing-§5). Regenerate both in
the change that adds or removes a case.

## In-game

`docs/smoke-tests.md` holds the checks only a client can make, by theme, each with a `Result:` line.
In-game perf captures are `/rm perf` and are recorded with `/dev-copilot:wow-perf-analysis` into
`docs/perf-analysis/`.
