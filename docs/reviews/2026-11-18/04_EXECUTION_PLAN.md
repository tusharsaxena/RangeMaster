# RangeMaster v0.1.0: execution plan (2026-11-18)

Change IDs come from `02_PROPOSED_CHANGES.md`, and finding IDs from `01_FINDINGS.md`. There are no
upstream findings, so there is no cross-repo milestone.

## Milestones

### M1: The core flow (C-01)

- **Task T1** (lua-fixer): C-01 / F-001, with its new test case. Files: `core/RangeMaster.lua`,
  `tests/test_container_render.lua`, `docs/test-cases.md`, `README.md` (badge).
- **Done when:** Both kit profiles are green with the new case, luacheck is 0/0, and the inventory and
  badge read 611.

### M2: Correctness and design (C-03, C-04, C-05, C-10)

- **Task T2** (lua-refactorer): C-03 and C-04 / F-003, F-013. Files: `core/Constants.lua`,
  `modules/Container.lua`, `tests/test_layers.lua` (if a level assertion needs the new names).
- **Task T3** (lua-fixer): C-05 / F-006. Files: `modules/BandSets.lua`, `tests/test_bandsets.lua`.
- **Task T4** (lua-fixer): C-10 / F-009. Files: `modules/Anchors_Screen.lua`,
  `tests/test_anchors_screen.lua`, `docs/test-cases.md`, `README.md`.
- **Done when:** The gate is green, the inventory and badge match the new count, and smoke tests
  C-03, C-05 and C-10 pass in client.

### M3: UX (C-02, C-09)

- **Task T5** (ux-cleanup): C-02 / F-002. Files: `modules/FramePicker.lua`, `locales/enUS.lua`,
  `settings/Containers.lua`, picker tests.
- **Task T6** (ux-cleanup): C-09 / F-008. Files: `settings/Slash.lua`, `tests/test_slash.lua`.
- **Done when:** The gate is green and smoke tests C-02 and C-09 pass.

### M4: Spell chips per character (C-06)

- **Task T7** (lua-refactorer): C-06 / F-004. Files: `modules/ContainerManager.lua`,
  `modules/Container.lua`, `modules/Elements_Spells.lua`, `modules/Elements_Indicator.lua`,
  `modules/Presets.lua`, `docs/ARCHITECTURE.md`, `docs/schema.md`, tests.
- **Done when:** The gate is green and smoke test C-06 passes on two classes.

### M5: Evidence and cleanup (C-07, C-08, C-11, C-12, C-13)

- **Task T8** (test-author): C-07 / F-005. Files: `tests/perf.lua`.
- **Task T9** (lua-fixer): C-08 / F-007. Files: `core/SkinSetup.lua`, `settings/Schema.lua`,
  `locales/enUS.lua`.
- **Task T10** (lua-fixer): C-11, C-12 and C-13 / F-010, F-011, F-012. Files: `modules/Ticker.lua`,
  `core/RangeMaster.lua`, `modules/Range.lua`, `defaults/SpellSeeds.lua` (optional),
  `core/Constants.lua`.
- **Done when:** The gate is green, `lua tests/perf.lua` exits 0 with the new dormant scenario, and
  the inventory and badge are current.

## Critical path and concurrency map

- `core/RangeMaster.lua`: T1 and T10. Serialize, T1 first.
- `core/Constants.lua`: T2 and T10. Serialize.
- `modules/Container.lua`: T2 and T7. Serialize, T2 first.
- `locales/enUS.lua`: T5 and T9. Serialize.
- `settings/Containers.lua`: T5 only. `settings/Slash.lua`: T6 only.
- `docs/test-cases.md` and `README.md`: every task that moves the count (T1, T4, possibly T5, T7 and
  T10). Regenerate them at the end of each task, never in parallel.
- **Parallelizable:** T3 (BandSets), T6 (Slash) and T8 (perf.lua) have file sets disjoint from
  everything else.

## Checkpoints

1. After M1: a human confirms C-01 in client (the first-draw regression is the release blocker).
2. After M2: check the layering change (C-03) visually before the UX work builds on it.
3. Before M4: an owner decision on C-06. The alternative is the chip-list editor as a feature
   issue.
4. Before release: `/dev-copilot:bump-version` regenerates `docs/automated-tests/`. Do not
   regenerate it here.

## Commit strategy

One commit per task. Suggested subjects:

- T1 `Containers: request the first apply at login, not through the skin callback (F-001)`
- T2 `Containers: per-instance level base; strata from the row's values (F-003, F-013)`
- T3 `BandSets: reassign containers through CM.SetField on delete (F-006)`
- T4 `Anchors: clear the screen clamp on detach (F-009)`
- T5 `FramePicker: confirm with Enter, cancel with Escape; clicks pass through untouched (F-002)`
- T6 `Slash: /rm delete asks first (F-008)`
- T7 `Spell chips: resolve the current character's seeds until a list is chosen (F-004)`
- T8 `perf: dormant-bracket call-count scenario over the hot paths (F-005)`
- T9 `Locale: route the skin reload line and the schema-stub line through NS.L (F-007)`
- T10 `Cleanup: drop Ticker.Removed, the Retail ladder build, a stale layers comment (F-010, F-011, F-012)`
