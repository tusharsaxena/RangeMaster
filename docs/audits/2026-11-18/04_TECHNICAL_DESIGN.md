# 04 — Technical design: Ka0s Range Master

Remediation design for the 2026-11-18 audit (standard v2.113.0). Keyed to the IDs in `02_DEVIATIONS.md`. Nothing here is applied by the audit.

## RM-04 — the skin-notice retry stands down with the addon (Medium)

**Files:** `core/SkinSetup.lua`, `tests/test_disabled.lua`.

Replace the 5 s `C_Timer.After` poll with the deferral shape the same file already uses for the first-run picker:

- In `NS.MaybeShowSkinNotice`, on `why == "combat"`: if no `noticeTarget` is held, take `NS.NewBusTarget()` and `NS.SafeRegisterEvent(noticeTarget, "PLAYER_REGEN_ENABLED", …)`; the handler drops the target (`UnregisterAllEvents`, nil) and calls `NS.MaybeShowSkinNotice()` again.
- A `dropNoticeDeferral()` beside `dropPickerDeferral()`, called from `NS.HideSkinPicker()` (already in `StandDown`, `core/LifecycleSetup.lua:58`), so the stand-down releases it. Being a tracked target, `NS.BusStandDown()` also covers it.
- Delete `NOTICE_RETRY`, `noticeWaiting` and the comment at `:287` that describes the poll.

Why this shape: it is the one sanctioned survivor kind (a single `PLAYER_REGEN_ENABLED` for a combat-deferred action) and it is released on stand-down; the library documents "the host asks again after it [combat]" and "No timer".

Risk: a login in combat that never leaves combat before logout never shows the notice that session, which is the same as today. Test: a step-4 case that enters combat (`InCombatLockdown` mocked true), calls `NS.MaybeShowSkinNotice()` with the notice owed, disables, and asserts no addon timer and no addon registration survive, then fires `PLAYER_REGEN_ENABLED` and asserts zero SavedVariables writes. `-- red under: restore the C_Timer.After poll`.

## RM-03 — complete the conformance suite (Low)

**File:** `tests/test_disabled.lua` only.

- `bringUp()` returns `R_on`, `T_on` (`addonTimers()`), `F_on` (the addon's shown frames from `M.__shownFrames()`, library-owned filtered as for timers). Bring up with at least one enabled container so `F_on` is non-empty, and assert that.
- New step-5 case: after `disable()`, every frame in `F_on` reports `IsShown() == false`.
- Step 4: after the last case of the file, re-assert `#addonTimers() == 0` while disabled (or a dedicated case that runs the other steps' actions while disabled and then checks). RM-04's case lands here.
- Step 7: write `enabled = true`, `NS.Perf.Suspend()`, dispatch `test`, assert one line equal to `Not available during a performance capture.` and no match on `NS.Slash:DisabledLine()`; release.
- Step 8: assert `#M.__shownFrames()` unchanged across both clicks and the menu open; assert `menu:Find("Enabled").enabled` before clicking it.
- Step 9: change a setting that shapes registrations while disabled (for example delete the Advanced preset's nameplate container, or switch a container's unit) and assert the rebuilt set differs from `R_on` accordingly.
- Add `-- red under:` comments on steps 3, 6 and 10 (e.g. `-- red under: drop addon:UnregisterLifecycleEvents() from StandDown`, `-- red under: drop NS.BusStandDown()`, `-- red under: make Perf.Resume release every hold`), and fix the header's "3, 6 and 9".

Then regenerate `docs/test-cases.md` and the README `[tests]` badge in the same change (testing-§5).

## RM-01 / RM-01a — restore the vendored quirks block (Low)

**File:** `docs/midnight-quirks.md`.

Run `/dev-copilot:wow-revendor-standards` to rewrite the block at the standard's current version (v2.113.0), or restore lines 1-269 of `git show 6ed49cb:docs/midnight-quirks.md` as the block and heading. Keep the six entries `a756304` wrote, under `## RangeMaster-specific quirks`, and drop any one the block now carries (none of the six appears to: they are range-API specific). RM-01a needs no edit once the block is back. Consider a docs-suite assertion (`tests/test_docs.lua`) that the file carries exactly one `BEGIN VENDORED` and one `END VENDORED` marker, so a future doc rewrite cannot drop it silently.

## RM-02 — README H1 (Low)

`README.md:1` → `# Ka0s Range Master`. Player-facing only; no other file moves.

## RM-05 — one writer for the containers registry (Low)

**Files:** `modules/ContainerManager.lua`, `modules/Presets.lua`, `docs/ARCHITECTURE.md`, `docs/schema.md`, `tests/test_presets.lua`.

Add `CM.MarkSeeded()` (the `p.seeded = true` write and its debug line) to the registry writer; `Presets.MarkPickerSeen` calls it. Update the hub's Containers bullet and the `docs/schema.md` row for `seeded` to name `NS.CM.MarkSeeded` as the writer reached by `NS.Presets.MarkPickerSeen`. Behavior is unchanged; the existing preset suite pins it.

## RM-06 — roster row (Low, upstream)

In `WowAddonStandards/standards/ADDONS.md`, add: `| Ka0s Range Master | ../../RangeMaster/ | https://github.com/tusharsaxena/RangeMaster | Retail · Forever | Enabled · Locked · Test mode · Sim mode | test | next to Test mode |`. A standards-repo change, made there, not here.

## RM-07 — citations and counts (Low)

- `DEPENDENCIES.md:39`: `(\`MINOR_VERSION\` in \`libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua\`)`.
- `docs/ARCHITECTURE.md` Conditional table: date the trigger counts ("27 commands in `NS.COMMANDS` as measured on 2026-11-18", likewise the shim and message counts); `:58` "Containers with its rail entries (`docs/settings-panel.md`)". `/dev-copilot:sync-docs` converts these.

## RM-08 — seed provenance (Low)

Either derive both per-client lists from wago.tools (`SpellName`, `SpellRange`/`SpellMisc` for range) at pinned `wow` and `wowf` builds into a dated `docs/` bundle, or add one sentence to `docs/ARCHITECTURE.md` → Per-client features saying how the lists are kept (hand-picked, checked by `docs/smoke-tests.md` per client). The second is the minimum.

## RM-09, RM-10 — no code

RM-09: future spec/plan pairs share one `<topic>`; existing files are not renamed. RM-10: open `docs/revendor/` with the first re-vendor.

## Ordering constraints

RM-04 before RM-03 (RM-03's step-4 case is RM-04's test). RM-01 is independent and the cheapest. RM-05 touches `docs/ARCHITECTURE.md` alongside RM-07; do them in one doc change.
