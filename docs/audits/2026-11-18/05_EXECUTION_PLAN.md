# 05 — Execution plan: Ka0s Range Master

From the 2026-11-18 audit (standard v2.113.0). Figures here match `02_DEVIATIONS.md`: 10 roots (0 High, 1 Medium, 8 Low, 1 Info), 11 including RM-01a; 6 MUST roots, 7 with dependents. Each step ends on the green gate: `ka0s-bounded lua tests/run.lua`, the same under `KA0S_KIT_CLIENT=forever`, and `ka0s-bounded luacheck .`.

## Sprint 1 — the runtime fix

- [ ] **RM-04** — `core/SkinSetup.lua`: replace the `NOTICE_RETRY` `C_Timer.After` poll with a tracked-target `PLAYER_REGEN_ENABLED` deferral; release it in `NS.HideSkinPicker()`; delete `NOTICE_RETRY` and `noticeWaiting`.
- [ ] **RM-04** — `tests/test_disabled.lua`: the combat-deferred notice case (no timer, no registration after disable; zero SavedVariables writes on the later `PLAYER_REGEN_ENABLED`), with its `-- red under:` line.

## Sprint 2 — the conformance suite

- [ ] **RM-03** — baseline `T_on` and `F_on`; assert `F_on` non-empty.
- [ ] **RM-03** — step-5 case: every frame in `F_on` hidden after disable.
- [ ] **RM-03** — step 4 "for the rest of the run" assertion.
- [ ] **RM-03** — step 7: the `perf`-hold-alone refusal line, `Not available during a performance capture.`
- [ ] **RM-03** — step 8: zero shows on both clicks and the menu; *Enabled* live before the click.
- [ ] **RM-03** — step 9: a registration-shaping setting changed while disabled.
- [ ] **RM-03** — `-- red under:` on steps 3, 6, 10; header text corrected.
- [ ] **RM-03** — regenerate `docs/test-cases.md`; update the README `[tests]` badge in the same commit.

## Sprint 3 — docs and structure

- [ ] **RM-01** (closes **RM-01a**) — restore the vendored client-quirks block (v2.113.0) and the `## RangeMaster-specific quirks` heading in `docs/midnight-quirks.md`; optional marker assertion in `tests/test_docs.lua`.
- [ ] **RM-02** — `README.md:1` → `# Ka0s Range Master`.
- [ ] **RM-05** — `CM.MarkSeeded()` in `modules/ContainerManager.lua`; `Presets.MarkPickerSeen` calls it; hub and `docs/schema.md` name it.
- [ ] **RM-07** — `DEPENDENCIES.md:39` by symbol; date or rule-ify the hub's Tier 2 counts and "five rail entries".
- [ ] **RM-08** — the seed-list maintenance sentence in `docs/ARCHITECTURE.md` → Per-client features (or a dated DB2 bundle).

## Sprint 4 — outside this repo, and nothing-to-do items

- [ ] **RM-06** — in WowAddonStandards, add the Range Master row to `standards/ADDONS.md` (Clients `Retail · Forever`; launcher `Enabled · Locked · Test mode · Sim mode`; skin preview `test`; Sim mode `next to Test mode`).
- [ ] **RM-09** — note only: the next spec/plan pair shares a `<topic>`.
- [ ] **RM-10** — note only: open `docs/revendor/` at the first re-vendor.
- [ ] Owed at adoption (not graded): LibKa0s #79, #86, #87, #92 — revisit when the addon adopts the report seam, title-bar strip, sample characters, `extraEntries` or the Tooltip placers.

## Exit

Re-run this audit after Sprint 3; expected result: RM-01 through RM-05, RM-07 and RM-08 closed, RM-06 closed once the upstream row lands.
