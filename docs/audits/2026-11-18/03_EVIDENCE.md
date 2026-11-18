# 03 — Evidence: Ka0s Range Master

Standard v2.113.0 (2026-11-16). Repo HEAD `1e3654e`. Every `file:line` below was re-read at HEAD before it was written, and the quoted text is what the line holds. Every count states the command that produced it and its scope.

## E1 — Kind and standard source

```
$ dev-copilot-profile
profile=wow
kind=addon
name=RangeMaster
reason=toc:## Interface
$ git -C ../WowAddonStandards status --porcelain        # (empty)
$ git -C ../WowAddonStandards rev-parse HEAD
1f5767f338ce7ecd3d7a2b698baee8920eea0400
$ git -C ../WowAddonStandards ls-remote origin refs/heads/master
1f5767f338ce7ecd3d7a2b698baee8920eea0400	refs/heads/master
$ diff -q <fetch>/{AUDIT.md,standards/STANDARDS.md,standards/ADDONS.md} ../WowAddonStandards/…   # (empty)
$ diff -rq <fetch>/standards/standards ../WowAddonStandards/standards/standards               # (empty)
```
`standards/STANDARDS.md:1`: `# Ka0s WoW Addon Standard (v2.113.0, 2026-11-16)`. 31 section files fetched from the Sections list.

## E2 — Lint and suites (bounded runner)

```
$ ~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
Total: 0 warnings / 0 errors in 111 files          exit=0
$ ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
602 passed, 0 failed, 1 skipped, 603 total          exit=0
$ KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
602 passed, 0 failed, 1 skipped, 603 total          exit=0
```
The skip (both profiles, line 565 of the output): `diagnostics contract: an addon that opts out lands the report and leaves logging off — this addon keeps the default …`.
`.luacheckrc:9-10`: `exclude_files = { "libs/", "tests/_kit/", "docs/audits/", "docs/reviews/", "docs/revendor/",` / `"docs/automated-tests/", "_dev/" }`; `.luacheckrc:48`: `files["tests/"] = {`. No top-level `ignore`.

## E3 — Vendored LibKa0s drift (anti-patterns #45/#48)

Provenance: `CLAUDE.md:38` `Bundles [LibKa0s](https://github.com/tusharsaxena/LibKa0s) v1.105.0 (MIT).`; `CLAUDE.md:39` `LibKa0s icons: chevron-down, chevron-up, clear, close, confirm, copy, eye, info, move, reset, settings, volume-high.` No `LibKa0s sounds:` line.

```
$ git -C ../LibKa0s archive v1.105.0 LibKa0s testkit | tar -x -C $T
$ diff -r $T/LibKa0s libs/LibKa0s ; echo rc=$?        # rc=1, 215 lines
$ grep -v 'media/icons' diff_lib.txt
Only in $T/LibKa0s/media/sounds: callout
$ grep -c 'Only in .*RangeMaster' diff_lib.txt        # 0
$ diff -r $T/testkit tests/_kit ; echo rc=$?          # rc=0, empty
```
Every other line is `Only in $T/LibKa0s/media/icons…` for an undeclared icon. `git ls-files libs/LibKa0s/media/icons` lists exactly the twelve declared `.tga` plus `LICENSE-open-iconic.txt`. Sounds: no line means `none`, and nothing ships. Clean.
README greps: `grep -n 'Bundles \[LibKa0s\]' README.md` → none; library-inventory headings → none; `README.md:5` `![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)` (bare).

## E4 — RM-01: the vendored quirks block is gone

```
$ grep -c VENDORED docs/midnight-quirks.md                       # 0
$ grep -n '^#' docs/midnight-quirks.md
1:# Midnight quirks — Ka0s Range Master
$ git show 6ed49cb:docs/midnight-quirks.md | grep -n 'VENDORED\|^## ' | head -3
5:<!-- BEGIN VENDORED: quirks catalog v2.113.0 (source: WowAddonStandards) -->
8:## Client quirks
267:<!-- END VENDORED -->        (and 269: ## RangeMaster-specific quirks)
$ git show a756304 --stat -- docs/midnight-quirks.md
 docs/midnight-quirks.md | 321 ++++++++----------------------------------------
 1 file changed, 48 insertions(+), 273 deletions(-)
$ for r in AbsorbTracker AuraMaster; do grep -c VENDORED ../$r/docs/midnight-quirks.md; done   # 6, 6
```
`docs/midnight-quirks.md:3`: `This file has two parts: the collection's client-quirks catalog, vendored whole from the Ka0s WoW Addon Standard between the markers below and never edited here, and then this addon's own quirks under \`## RangeMaster-specific quirks` (ends there; the next line is blank).
`docs/midnight-quirks.md:5`: `The client behaviors this addon's code works around and the vendored catalog above does not carry.`
RM-01a — `docs/ARCHITECTURE.md:256`: ``| `midnight-quirks.md` | Present | Always (documentation-§3): the vendored `client-quirks` catalog block, then the addon's own section |``.
Rule: client-quirks-§1, "Every addon's `docs/midnight-quirks.md` (documentation-§3) is two parts: the vendored block … then the addon's own section."

## E5 — RM-02: README H1

`README.md:1`: `# Range Master`. documentation-§1 item 1: "**H1 title** — `# Ka0s <Name>`. **MUST**." `core/Constants.lua:32`: `C.BRAND = "Ka0s Range Master"`.

## E6 — RM-03: `tests/test_disabled.lua` against slash-commands-§7's ten steps

`tests/run.lua:163`: `"test_disabled",` (listed, inside the gate).
```
$ grep -n -i 'red under' tests/test_disabled.lua       # (no output)
```
| Step | Covering line | Verdict |
|---|---|---|
| 1 Baseline `R_on`, `T_on`, `F_on`; `R_on` non-empty | `:84` `test("disabled 1: the enabled addon registers something to stand down from"`; `bringUp()` (`:68-79`) returns `regSet()` only | partial: no `T_on`, no `F_on` |
| 2 Disable through the write seam | `:81` `local function disable() NS.SetByPath("enabled", false) end` | covered |
| 3 Registration set empty, count and name | `:105-111` `assertEqual(#after, 0, "survivors of the stand-down:\n  " .. joined(after))` | covered; no `-- red under:` |
| 4 No timer now or for the rest of the run | `:113-122` `assertEqual(#addonTimers(), 0, …)` at the disable only | partial |
| 5 Every frame in `F_on` hidden | `:124` `test("disabled 5: a preview mode cannot be started while disabled, …"` asserts refusals | missing |
| 6 Fire every `R_on` event, combat entry by name, zero writes/prints/shows, reach ≥1 per event | `:146` `assertTrue(sawCombat, …)`; `:162` `assertTrue(M.__fireUnconditional(f.target, f.event) >= 1, …)`; `:164-167` the three zero assertions | covered; no `-- red under:` |
| 7 Every `NS.COMMANDS` row; perf-hold-alone refusal line | `:186-204` dispatches every row (one-line refusal at `:200`); no case takes the `perf` hold alone | partial |
| 8 Launcher L/R click, zero writes and zero shows, *Enabled* live | `:263-266` left click writes nothing; `:274` grayed entries; no `__shownFrames` assertion in the case | partial |
| 9 Restore `R_on`, plus a setting changed while disabled reflected in the rebuilt set | `:292-296` changes `locked`, which no registration depends on | partial |
| 10 Latch, both orders | `:314-335` both orders | covered; no `-- red under:` |

Header `tests/test_disabled.lua:8-9`: `-- the standard numbers them, and each is falsifiable: drop the stand-down's unregister and steps 3, 6` / `-- and 9 go red.` Rule: slash-commands-§7, "The suite **MUST** carry testing-§12's falsification comment on at least steps 3, 6 and 10".

## E7 — Disabled-state registration census (TOC-derived load list, 57 authored `.lua`)

```
loadlist() { find . -maxdepth 1 -name '*.toc' -exec cat {} + | tr -d '\r' | grep -v '^#' | grep -iE '\.lua[[:space:]]*$' \
  | sed 's|\\|/|g; s/[[:space:]]*$//' | grep -v '^libs/' | sort -u; }
loadlist | wc -l                                     # 57
loadlist | xargs grep -nE 'Register(Unit)?Event|RegisterMessage|RegisterBucketEvent'
loadlist | xargs grep -nE 'Unregister(All)?Events?|UnregisterMessage|UnregisterBucket|CancelTimer|CancelAllTimers|:Cancel\(|SetScript\("OnUpdate", *nil\)'
loadlist | xargs grep -nE 'NewTicker|NewTimer|C_Timer\.After|ScheduleTimer|ScheduleRepeatingTimer|SetScript\("OnUpdate"'
```
Scope: the authored files the TOC loads; `libs/`, `tests/` excluded (they register nothing in the client).

| Registration | Undone by |
|---|---|
| `core/RangeMaster.lua:90` the lifecycle list via `NS.SafeRegisterEvent` | `core/RangeMaster.lua:99` `self:UnregisterEvent(pair[1])`, called from `StandDown` (`core/LifecycleSetup.lua:61`) |
| `modules/Container.lua:703-705`, `modules/Preview.lua:73`, `modules/Sim.lua:230`, `settings/BandSets.lua:283` `RegisterMessage` on tracked targets | `NS.BusStandDown()` (`core/LifecycleSetup.lua:63`); `tests/test_disabled.lua:300-312` proves it |
| `core/SkinSetup.lua:274`, `settings/Presets.lua:164` one-shot `PLAYER_REGEN_ENABLED` | `NS.HideSkinPicker` / `NS.HidePresetPicker` (`core/LifecycleSetup.lua:58-59`), `settings/Presets.lua:134` |

| Timer / OnUpdate | Cancelled by |
|---|---|
| `modules/Ticker.lua:125` `NewTicker` | `:99` `handle:Cancel()` (Ticker StandDown) |
| `modules/Range.lua:224` | `:223`/`:229` |
| `modules/ContainerManager.lua:109` | `:84`/`:115` |
| `modules/Anchors_Nameplate.lua:199`, `:225` | `:192`, `:248` |
| `modules/Anchors_Cursor.lua:72` | `:75` `driver:SetScript("OnUpdate", nil)` |
| `modules/FramePicker.lua:170`, `:128` | `:73`; `:128` is a 0 s `After` that re-enables keyboard propagation only out of combat |
| **`core/SkinSetup.lua:313`** `_G.C_Timer.After(NOTICE_RETRY, function()` | **nothing** (RM-04) |

## E8 — RM-04: the skin-notice poll

- `core/SkinSetup.lua:287`: `-- switch never shows it twice. In combat nothing is claimed; it asks again every NOTICE_RETRY seconds until combat ends.`
- `core/SkinSetup.lua:288`: `local NOTICE_RETRY = 5   -- seconds between asks while the player is in combat`
- `core/SkinSetup.lua:311-316`: `if why == "combat" and not noticeWaiting …` / `noticeWaiting = true` / `_G.C_Timer.After(NOTICE_RETRY, function()` / `noticeWaiting = false` / `NS.MaybeShowSkinNotice()` / `end)`
- `core/SkinSetup.lua:306`: `O.SkinNotice(nil, noticeStore, true)` — the stood-down branch; `:298` `set = function(v) local g = noticeGlobal(); if g then g.skinNotice = v end end,`.
- `core/LifecycleSetup.lua:55-64`, `StandDown`: ends modes, `NS.HideSkinPicker()`, `NS.HidePresetPicker()`, `UnregisterLifecycleEvents`, `runSteps(DOWN_STEPS)`, `NS.BusStandDown()` — no notice-retry step.
- Library contract, `libs/LibKa0s/OptionsSkinPicker.lua:1329`: `--- so every vendored copy of an addon shares it. No timer: a stand-down must leave nothing armed,`; `:1324-1326` (the `recordOnly` branch records "claimed").
- Reach: `core/RangeMaster.lua:41` `if NS.MaybeShowSkinPicker then NS.MaybeShowSkinPicker() end` from the first-run path in `OnEnable`, wrapping `NS.MaybeShowSkinNotice` (`core/SkinSetup.lua:322-323`). A login or reload in combat with the notice owed arms the poll.
- Compliant twin: `core/SkinSetup.lua:270-277` defers the picker on a tracked target's `PLAYER_REGEN_ENABLED`.

## E9 — RM-05: the `seeded` sentinel's second writer

- `modules/Presets.lua:182-186`: `function Presets.MarkPickerSeen()` / `local p = NS.db and NS.db.profile` / `if type(p) == "table" and p.seeded ~= true then` / `p.seeded = true`.
- `docs/ARCHITECTURE.md:107-111`: `- **Containers**: … and the first-run sentinel` / `` `seeded`. Runtime writer `modules/ContainerManager.lua` (`NS.CM`: …`` / … / `` is written by `NS.Presets.MarkPickerSeen`.``
- Write-path grep (scope `core/ modules/ settings/ defaults/`): `git ls-files 'core/*.lua' 'modules/*.lua' 'settings/*.lua' 'defaults/*.lua' | xargs grep -nE '(db\.(profile|global|char)|\bp|\bg|\bprofile)(\.[A-Za-z_]+|\[[^]]+\])+ *= *[^=]'` → 18 hits (comment and `local` lines filtered); every other hit sits in its named writer (`modules/BandSets.lua`, `modules/ContainerManager.lua`), the load pass (`core/Database.lua`) or the named minimap row (`core/Data.lua:53-54`).

## E10 — RM-07: documentation-§6 censuses

Scope: tracked `.md` minus documentation-§3's frozen stores, `libs/`, `tests/_kit/`, and the generated `docs/test-cases.md` and `docs/automated-tests/RESULTS.md`.
```
$ git ls-files -z -- '*.md' ':!:docs/audits/**' ':!:docs/reviews/**' ':!:docs/automated-tests/*/**' \
    ':!:docs/perf-analysis/*/**' ':!:docs/revendor/*/**' ':!:docs/superpowers/**' ':!:docs/investigations/**' \
    ':!:libs/**' ':!:tests/_kit/**' ':!:docs/test-cases.md' | xargs -0 grep -nE '[A-Za-z0-9_/]+\.(lua|toc|md|xml):[0-9]+'
DEPENDENCIES.md:39:| LibRangeCheck-3.0 … MINOR 39 (`MINOR_VERSION` at `libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua:43`) | …
```
One hit. (`libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua:43` reads `local MINOR_VERSION = 39` today.)
Undated self-tree counts, finder (a superset; a hit naming its members is compliant): the same pathspec plus `':!:docs/automated-tests/RESULTS.md'`, `grep -noiE '\b([0-9]+|two|…|twenty)[- ](commands|shims|messages|files|modules|pages|tabs|rail entries|suites|verbs|scenarios|elements|anchor modes|presets|cases)\b'` → **15 hits**: `docs/ARCHITECTURE.md` 17, 58, 126, 255, 257, 258, 268; `docs/automated-tests/README.md` 39, 48; `docs/data-flow.md` 171; `docs/schema.md` 40; `docs/scope.md` 13; `docs/smoke-tests.md` 16; `docs/testing.md` 37, 59. The undated, member-less ones: `docs/ARCHITECTURE.md:255` `27 commands in NS.COMMANDS`, `:257` `18 shims by documentation-§3's count, fourteen of them addon-specific`, `:258` `4 messages in NS.MSG`, `:58` `Containers with its five rail entries`.
Retired-notation sweep (same doc scope; and authored Lua): `grep -nE '§[0-9]+\.[0-9]'` → 0 and 0.

## E11 — RM-06, RM-08, RM-09, RM-10

- RM-06: `grep -n -i 'range' WowAddonStandards/standards/ADDONS.md` → no roster row. clients-§2: "**MUST** be declared in the roster … for every addon." TOC `RangeMaster.toc:1` `## Interface: 120105, 16001`.
- RM-08: `grep -rln -i 'wago\|DB2' docs` → only `docs/superpowers/research/2026-11-18-range-research.md`, which names Blizzard API docs for build 70783, not a DB2 derivation. `defaults/SpellSeeds.lua:19-21`: `-- Forever is a vanilla world: … and vanilla spell IDs` / `-- (rank 1, …). The IDs are the classic, long-stable` / `-- ones; docs/smoke-tests.md carries the in-game check that each one resolves on both clients.`
- RM-09: `git ls-files docs/superpowers` → `plans/2026-11-18-rangemaster-v0.1.0.md`, `research/2026-11-18-range-research.md`, `specs/2026-11-18-rangemaster-design.md`.
- RM-10: `ls docs/revendor` → no such directory; `git log --oneline -- libs/LibKa0s tests/_kit` begins at the scaffold.

## E12 — Compliance evidence (selected)

- Line endings: `.gitattributes` first 84 lines (CR stripped) `diff` against line-endings-§5's client-bound body → empty, nothing after line 84; `tr -d '\r' < .gitattributes | grep -c ' binary$'` → 20; working-tree check (the bash loop over `git ls-files -z`, scope the whole tracked set) → **0**.
- Packaging (`.pkgmeta`): (a) no `NOT IGNORED`; (b) only `UNACCOUNTED — .git`; (c) no `FALSE CLAIM`.
- Generators: `git ls-files '*.py' '*.sh'` → `tests/_kit/run-automated-tests.sh` (vendored, dropped).
- Logo header: `od -An -tu1 -N18 media/logos/rangemaster.logo.128.tga` → byte 2 = 2, width 128, height 128, depth 32.
- Bus: `(Send|Register)Message\("Ka0s_` → none; wire names only at `core/Bus.lua:94,97,100,104` (`"Ka0s_RangeMaster_RangeUpdated"` …), PascalCase.
- Hooks: `hooksecurefunc|HookScript` in authored, non-test Lua → none. Client detection: `WOW_PROJECT_|GetBuildInfo` → `core/Compat.lua:12` (a comment).
- Events: `core/CoreSetup.lua:99-100` `function NS.SafeRegisterEvent(target, event, handler, rejected)` / `local ok = pcall(target.RegisterEvent, target, event, handler)` (stub arm); library arm `:128`.
- Close button: one wrapper, `core/CoreSetup.lua:151` `return lib.MakeCloseButton(parent, onClick, addonName)`; no other authored call.
- Skins: `core/SkinSetup.lua:431` `Skin:RegisterOwner(addonName, {`; literal-paint grep hits read `Style.Color`/`NS.Skin.Color` or the band's stored color, plus `modules/Elements_Spells.lua:46` `chip.icon:SetVertexColor(1, 1, 1, 1)` (an icon's identity tint).
- Shim count (documentation-§3's command): `cat core/Compat*.lua | grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.'` → 18, matching `docs/ARCHITECTURE.md:257`.
- Complexity: `ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle` → `complexity  pass — 0 warnings (fun rate 0.00), 16345 NLOC / 2538 funcs, avg NLOC 5.8, avg CCN 2.1 (max 15)` and `record: newest bundle 20261118-083858 measured a756304, 1 commit(s) behind HEAD`. `git diff --name-only a756304 HEAD` → only the bundle, `RESULTS.md` and the plan. Manifest: `blindFiles 0`, `crashedFiles 0`, `release "0.1.0"`; `ANALYSIS.md` carries `## Preview and simulation data`, answer *Refreshed*. `Kit.VERSION = 57` (`tests/_kit/framework.lua:20`); `tests/run.lua:166-170` declare `test_eol`, `test_layout_cap`, `test_lizard_sighted`, `test_skin_values`, `test_skin_switch` with `dir = "tests/_kit/"`.
- LOC census (default scope `git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`, 111 files): largest `settings/Schema.lua` 727; none ≥ 1000.
- Register: `docs/ARCHITECTURE.md` `## Documented deviations` → `None.`; `gh issue list --state all --limit 200 --json number,title,state,labels,url` → 13 open `enhancement` issues (#1–#13), labels `state:triaged`/`state:untriaged`; no `state:will-not-do`.
