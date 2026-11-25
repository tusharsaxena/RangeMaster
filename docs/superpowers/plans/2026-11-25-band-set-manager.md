# Plan: band set manager (RangeMaster#21)

- **Spec:** `docs/superpowers/specs/2026-11-25-band-set-manager-design.md`.
- **Branch:** `feat/2026-11-25-band-set-manager`.
- **Where it's built:** a scratch clone at `~/ka0s-scratch/rmbands/RangeMaster`. The live repo is left alone, because the
  game loads it. The lead brings the branch over with
  `git fetch ~/ka0s-scratch/rmbands/RangeMaster feat/2026-11-25-band-set-manager:feat/2026-11-25-band-set-manager`.
- **State is git.** An item is done when a commit whose subject starts `<ID>: ` is on the branch.

| ID | Milestone | Item | Depends on |
|---|---|---|---|
| BS-PLAN | M0 | this plan and the spec | – |
| BS-01 | M1 | Model: `origin`, the migration, PresetKeys, Diff, IsModified, RestorePreset, CopyFrom; tests | BS-PLAN |
| BS-02 | M2 | Settings: header row, grouped picker, origin banner, read-only preset view | BS-01 |
| BS-03 | M2 | Dialogs: New, Copy bands from, Restore; Undo line; Add band and Remove band side by side | BS-02 |
| BS-04 | M3 | Docs, locales, smoke rows, full gate on both kit profiles | BS-03 |
| BS-REV | M4 | Independent review, then a fix pass | BS-04 |

**Checkpoints:**
- **After M1:** the gate is green on both profiles.
- **After M3:** the full gate is green.
- **After M4:** the lead re-runs the gate and pushes the feature branch.

**Merging** waits for the owner's go-ahead after smoke.

**Resume:**
1. Run `git log --format=%s master..feat/2026-11-25-band-set-manager` in the clone to see which IDs are done.
2. Read `git status` and either continue or stash any uncommitted work.
3. Relaunch the workflow with `resumeFromRunId`, or brief a fresh builder from the spec for the missing IDs.
