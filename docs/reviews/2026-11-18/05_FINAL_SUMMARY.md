# RangeMaster v0.1.0: final summary (2026-11-18)

This summary is written on the assumption that every check in `03_SMOKE_TESTS.md` has passed and
every task in `04_EXECUTION_PLAN.md` has landed.

## Headline

The fixes in this cycle make Range Master's displays appear reliably at login. Before them, a
player who had unticked *Ignore settings panel* saw no displays after a reload. The fixes also stop
the frame picker from clicking the frame you pick, and make overlapping displays (crowded
nameplates, the cursor display) stack cleanly instead of bleeding into each other. Spell chips now
follow whichever character is logged in. Two extra writers are gone: band-set deletes go through the
container registry, and `/rm delete` asks before it deletes. Finally, the perf evidence now proves
that the hot paths' instrumentation costs nothing while capture is off.

## Counts

Critical fixed: 0, High fixed: 1, Medium fixed: 5, Low fixed: 7.

C-06 (F-004) needs an owner decision at checkpoint 3. If the editor route is chosen instead, F-004 is
deferred to a feature issue.

## Changes by theme

- **A. First draw**
  - **What changed:** Login requests one container apply.
  - **Why:** The first apply depended on the skin's callback (F-001; C-01).
  - **Files:** `core/RangeMaster.lua`, `tests/test_container_render.lua`.
- **B. Picker**
  - **What changed:** Enter picks and Escape cancels.
  - **Why:** Mouse clicks passed through to the game's frames (F-002; C-02).
  - **Files:** `modules/FramePicker.lua`, `locales/enUS.lua`, `settings/Containers.lua`.
- **C. Layering**
  - **What changed:** Each display has its own level base. The renderer's strata is read from the
    row's values.
  - **Why:** Overlapping displays interleaved, and the renderer allowed dialog tiers
    (F-003, F-013; C-03, C-04).
  - **Files:** `core/Constants.lua`, `modules/Container.lua`.
- **D. One writer**
  - **What changed:** A band-set delete goes through `CM.SetField`.
  - **Why:** It wrote container fields directly (F-006; C-05).
  - **Files:** `modules/BandSets.lua`.
- **E. Chips per character**
  - **What changed:** The seeds are resolved at render time until the player chooses a list.
  - **Why:** Chips were fixed to the creating character's class (F-004; C-06).
  - **Files:** `modules/ContainerManager.lua`, `modules/Container.lua`,
    `modules/Elements_Spells.lua`, `modules/Elements_Indicator.lua`, `modules/Presets.lua`,
    `docs/ARCHITECTURE.md`, `docs/schema.md`.
- **F. Evidence**
  - **What changed:** A dormant-bracket call-count scenario was added.
  - **Why:** The old scenario compared dormant against armed on a non-hot path (F-005; C-07).
  - **Files:** `tests/perf.lua`.
- **G. Cleanup**
  - **What changed:** Two lines localized, `/rm delete` confirms, the clamp is cleared on detach,
    `Ticker.Removed` removed, the Retail ladder build removed, and one comment fixed
    (F-007 to F-012; C-08 to C-13).
  - **Files:** `core/SkinSetup.lua`, `settings/Schema.lua`, `settings/Slash.lua`,
    `modules/Anchors_Screen.lua`, `modules/Ticker.lua`, `modules/Range.lua`, `core/Constants.lua`,
    `locales/enUS.lua`.

## API and behavior changes

- `/rm pick` and *Pick on screen*: Enter picks and Escape cancels. Mouse clicks no longer pick or
  cancel.
- `/rm delete <n|name>` now shows a confirmation popup.
- `NS.Ticker.Removed` was removed (it was internal).
- New locale keys: the picker's Enter and Escape lines, the skin reload line, and the schema-stub line.

## Saved-variable and migration notes

There is no schema bump while v0.1.0 is unreleased. If C-06 ships after a release, add a
`SCHEMA_STEPS` entry that clears any chip list equal to its class seed.

## Deprecated-API migrations

None.

## Performance impact

No measured before and after figures yet. C-07 adds call counts, and C-07's in-client capture
records the bucket figures. Fill this section from those records, never from an estimate.

## Test and complexity movement

The pass count was 610 (with 1 skip, 611 total) before. After C-01 and C-10 it is expected to be
612, less any case C-11 retires. `docs/test-cases.md` and the README badge move in the same commits.
No watch-list entry is expected to move. The next release's regeneration confirms that.

## Known follow-ups

- A chip-list editor (an `O.IdList`-style row) as a feature issue.
- Add the roster row for RangeMaster to `WowAddonStandards/standards/ADDONS.md` (design spec 5.8).
  Until then, `scripts/roster_clients.py` cannot resolve it.

## Verification evidence

The completed `03_SMOKE_TESTS.md` sign-off table, and the commit range of tasks T1 to T10 on
`feat/v0.1.0-initial-build`.

## Suggested PR description

```
RangeMaster v0.1.0 review fixes (docs/reviews/2026-11-18)

- Draw stored containers at login regardless of skin settings (F-001)
- Frame picker: Enter picks, Escape cancels; clicks no longer reach the frame underneath (F-002)
- Per-instance frame-level base so overlapping displays stack whole; strata from the row values (F-003, F-013)
- Spell chips resolve the current character's class seeds until a list is chosen (F-004)
- Dormant-bracket call-count perf scenario on the hot paths (F-005)
- Band-set delete reassigns containers through CM.SetField (F-006)
- Localize two chat lines; /rm delete confirms; clear screen clamp on detach (F-007, F-008, F-009)
- Remove unreachable Ticker.Removed and the unused Retail ladder build; fix stale comment (F-010..F-012)
```
