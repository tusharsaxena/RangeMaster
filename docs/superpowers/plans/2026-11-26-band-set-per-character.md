# Plan: the band set a container uses is the character's own

- **Spec:** `docs/superpowers/specs/2026-11-26-band-set-per-character-design.md`.
- **Branch:** `feat/2026-11-26-band-set-per-character`.
- **Where it's built:** a scratch clone at `~/ka0s-scratch/rmbs/RangeMaster`. The live repo is left alone,
  because the game loads it.
- **State is git.** An item is done when a commit whose subject starts `<ID>: ` is on the branch.

| ID | Milestone | Item | Depends on |
|---|---|---|---|
| BSC-PLAN | M0 | this plan and the spec | – |
| BSC-1 | M1 | `modules/BandSetChoice.lua`: the store, the resolution, `ForUnit` with the id, the rows' read and write, delete, copy and profile events, the load-pass prune, schema v5. Tests come first: two characters sharing one profile keep separate selections; a new character gets its class preset; a deleted set falls back; friendly nil follows hostile; the migration keeps the current character's choice | BSC-PLAN |
| BSC-2 | M2 | Docs (README, `docs/settings-panel.md`, `docs/schema.md`, `docs/ARCHITECTURE.md`, `docs/module-map.md`) and new unrun rows in `docs/smoke-tests.md` | BSC-1 |
| BSC-REV | M3 | Independent review, then a fix pass | BSC-2 |

**The gate before every commit:**
- `ka0s-bounded lua tests/run.lua`, run once plain and once with `KA0S_KIT_CLIENT=forever`.
- `ka0s-bounded luacheck .`, with 0 warnings and 0 errors.
- `python3 -m pytest -q -p no:cacheprovider tools/seeds`.
- `tests/perf.lua` on both clients.
- Every file under 1500 lines.
- CCN 15 or lower for every new or changed function.

**Checkpoints:**
- **After M1 and after M2:** the gate is green on both profiles.
- **After M3:** the lead re-runs the gate and pushes the feature branch.

**Merging** waits for the owner's go-ahead after smoke.

**Resume:**
1. Run `git log --format=%s master..feat/2026-11-26-band-set-per-character` in the clone to see which IDs are done.
2. Read `git status`, then continue or stash any uncommitted work.
3. Brief a fresh builder from the spec for the missing IDs.
