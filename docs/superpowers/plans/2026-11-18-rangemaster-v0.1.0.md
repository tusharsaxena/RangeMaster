# Ka0s Range Master v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Ka0s Range Master v0.1.0: user-built range containers for target, focus, pet, mouseover and all nameplates, on Retail and WoW Forever, compliant with the Ka0s WoW Addon Standard.

**Architecture:** Ace3 addon scaffolded by the Ka0s NEW_ADDON.md playbook on vendored LibKa0s. One range engine (`modules/Range.lua`) wraps LibRangeCheck-3.0 behind a per-client Compat layer and a per-tick unit memo; one shared ticker publishes `RANGE_UPDATED`; containers (sole writer `ContainerManager`) render elements coloured by shared band sets and attach through four anchor modes.

**Tech Stack:** Lua 5.1, Ace3, LibStub, CallbackHandler-1.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0, LibKa0s v1.105.0, LibRangeCheck-3.0 (MINOR 39, GitHub main), luacheck, lizard, Ka0s test kit.

**Spec:** `docs/superpowers/specs/2026-11-18-rangemaster-design.md` (read it first; this plan argues from it).

## Checkpoint ledger (resume from the first row that is not `done`)

| # | Task | Status | Commit | Pushed |
|---|---|---|---|---|
| 0 | Repo, labels, branch, spec, research, plan | done | d140c26 + this | yes |
| 1 | Scaffold (born compliant) + vendor LibKa0s + LibRangeCheck | done | 30b77b8 + 6ed49cb + b6d243f + `Scaffold: review fixes` | yes |
| 2 | Range engine, Compat, spell seeds, ticker | done | aef104b + `Task 2: review fixes` | yes |
| 3 | Data model, band sets, migrations | done | 5415e55 + `Task 3: review fixes` | yes |
| 4 | ContainerManager + presets | done | 54a9721 + `Task 4: review fixes` | yes |
| 5 | Container rendering + elements | done | 6a50bdf + `Task 5: review fixes` | no |
| 6 | Anchors (screen, frame, nameplate, cursor) | done | `Anchors: screen, unit frame (Blizzard, EllesmereUI, custom), nameplate, cursor` | no |
| 7 | Visibility, sounds, lock, Test mode, Sim mode | todo | | |
| 8 | Settings pages + slash verbs | todo | | |
| 9 | Docs set, roster row, automated-test + audit bundles, GitHub issues | todo | | |
| 10 | Whole-branch review + fixes, push, await merge go-ahead | todo | | |

Resume rule: an agent picking this up reads this ledger, runs `git log --oneline` on
`feat/v0.1.0-initial-build`, and re-runs the gate below before continuing. Each task updates its
row (status, short SHA) in the same commit that finishes it. Push after tasks 1, 5, 8 and 10.

**Gate (every task):** from the repo root,
`~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` → `0 warnings / 0 errors`;
`lua tests/run.lua` and `KA0S_KIT_CLIENT=forever lua tests/run.lua` → all suites green.

## Global Constraints

- Clients `Retail · Forever`: one unsuffixed `RangeMaster.toc`, `## Interface: 120105, 16001`, no load-gating line.
- TOC `## Title: Ka0s Range Master`, `## Author: add1kted2ka0s`, `## Version: 0.1.0`, `## X-License: MIT`, `## SavedVariables: RangeMasterDB, RangeMasterPerfDB`, `## OptionalDeps` includes `EllesmereUI`; `# X-Curse-Project-ID` commented out (unpublished).
- Slash: `/rm` and `/rangemaster`. Namespace `NS`; addon object via AceAddon `RangeMaster`.
- No root or `docs/` CHANGELOG; history lives in README `## Version History`.
- Client detection only in `core/Compat.lua` (interface 16000–19999 or `WOW_PROJECT_CAMELOT` = Forever); no `WOW_PROJECT_ID == 1` checks anywhere.
- Every range API call wrapped in `pcall`; every result passed through `issecretvalue`; secret/error → `"unknown"`, never out of range.
- Cache/memo keys are unit tokens, never GUIDs.
- No `SetPoint`/`SetParent` on frames anchored to secure frames in combat; queue for `PLAYER_REGEN_ENABLED`. Cursor and nameplate containers are our own frames and may move.
- One ticker for the whole addon; no per-container OnUpdate. Cursor follow uses one shared OnUpdate for all cursor containers.
- Unit-frame providers: `blizzard`, `ellesmere`, `custom` only. Never read `EllesmereUIDB`.
- Band colour ramp `#4ade80 #a3e635 #facc15 #fb923c #ef4444`, unknown `#9ca3af`, unknown label `?`.
- Sounds: settle 0.2 s, gap ≥ 1 s, silent on first band after unit change; none for `nameplates` containers.
- Ticker: 10 Hz out of combat, 20 Hz in combat, stopped when nothing live.
- Commits end with the session attribution trailer; prefix none (`AD-*` prefixes are for LibKa0s adoption only).

## Review Focus

1. Unit disappears mid-tick (target dies, mouseover leaves, plate recycles) → container hides or shows unknown, no Lua error. Test in Task 2 (`test_range_unit_vanishes`) and Task 6 (`test_nameplate_recycle`).
2. A band set deleted while containers use it → those containers move to the default set and render. Test in Task 3 (`test_bandset_delete_reassigns`).
3. Entering combat while unlocked / in Test or Sim mode / with a pending re-anchor → modes end, re-anchor queued, nothing errors. Test in Task 7 (`test_combat_ends_modes`) and Task 6 (`test_frame_anchor_deferred_in_combat`).
4. Missing or not-yet-loaded attach frame (EllesmereUI off, typo'd custom name) → container hidden, one debug line, re-resolved on `ADDON_LOADED`. Test in Task 6 (`test_frame_missing_then_loaded`).
5. Band edges with open-ended / reversed / overlapping input from the editor → normalised, `Resolve` total over [0, ∞). Test in Task 3 (`test_bandset_normalise`).

---

### Task 1: Scaffold, born compliant

**Files:** everything NEW_ADDON.md creates (TOC, `core/`, `defaults/`, `settings/`, `locales/`, `modules/`, `media/logos/rangemaster.logo.128.tga`, `libs/`, `tests/`, `docs/` trio + tier docs, `README.md`, `CLAUDE.md` stub, `DEPENDENCIES.md`, `LICENSE`, `.luacheckrc`, `.pkgmeta`). Plus `libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua` (MINOR 39 from github.com/WeakAuras/LibRangeCheck-3.0 main; record the commit SHA in `DEPENDENCIES.md`).

**Interfaces:**
- Produces: `NS` namespace, `NS.MSG` message constants (the strict `Bus.Catalog` architecture-§4 names; sent through `NS.bus`) (add `RANGE_UPDATED`, `CONTAINERS_CHANGED`, `BANDSETS_CHANGED`, `MODE_CHANGED`), `NS.Compat` with `NS.Compat.IsForever() -> boolean`, `NS.db` (AceDB), the Lifecycle latch, the options registration, launcher with entries Enabled · Locked · Test mode · Sim mode.

- [ ] **Step 1:** Run `/dev-copilot:wow-new-addon` (or follow `WowAddonStandards/NEW_ADDON.md` to the letter) for name `RangeMaster`, title `Ka0s Range Master`, slash `rm`/`rangemaster`, clients `Retail · Forever`, launcher entries `Enabled · Locked · Test mode · Sim mode`, skin preview `test`, sim checkbox `next to Test mode`, tagline "Build your own range displays for target, focus, pet, mouseover and nameplates."
- [ ] **Step 2:** Vendor LibRangeCheck-3.0 into `libs/`, list it in the TOC Libraries section after LibKa0s, add it to `.pkgmeta` ignore-nothing / `DEPENDENCIES.md`, and to `tests/wow_mock.lua` load path so suites can load it.
- [ ] **Step 3:** Gate (both clients + lint). Commit `Scaffold Ka0s Range Master v0.1.0`. Update ledger row 1. Push.

### Task 2: Range engine

**Files:** Modify `core/Compat.lua`; Create `defaults/SpellSeeds.lua`, `modules/Range.lua`, `modules/Ticker.lua`; Test `tests/test_range.lua`, `tests/test_ticker.lua`.

**Interfaces:**
- Produces:
  - `NS.Range.Get(unit: string) -> state: "known"|"unknown"|"none", minYd: number|nil, maxYd: number|nil` (memoised per tick).
  - `NS.Range.InSpellRange(spellID: number, unit: string) -> true|false|nil`.
  - `NS.Range.BeginTick()` (clears memo), `NS.Range.Rebuild()` (on `SPELLS_CHANGED`, debounced 0.5 s).
  - `NS.Compat.RangeLadder() -> { {kind="item"|"interact"|"spell", id=number, yd=number}, ... }` for the active client/class (Forever: items at 20/30/35, interact 3/4 race-adjusted).
  - `NS.SpellSeeds[client][classFile] = { chips = {spellID,...}, ladder = {spellID,...} }`, `client ∈ {"retail","forever"}`.
  - `NS.Ticker.Watch(unit)`, `NS.Ticker.Unwatch(unit)`, `NS.Ticker.Refresh(unit?)`; sends `NS.MSG.RANGE_UPDATED` with `(unit, state, min, max)` only on change.

- [ ] **Step 1: Write failing tests** `test_range.lua`: `test_known_bracket` (LRC mock returns 20,25 → `"known",20,25`); `test_open_ended` (40,nil → `"known",40,nil`); `test_secret_is_unknown` (kit secret value → `"unknown"`); `test_error_is_unknown` (LRC throws → `"unknown"`); `test_no_unit_is_none`; `test_memo_one_query_per_tick` (3 Gets on `target` → 1 LRC call); `test_range_unit_vanishes` (unit exists at Get 1, gone after BeginTick → `"none"`); `test_spell_unknown_spell_nil` (spell not known → nil); `test_forever_ladder` (under `KA0S_KIT_CLIENT=forever`, ladder yds ⊆ {20,30,35,28,10}). `test_ticker.lua`: `test_rate_combat_20hz`, `test_rate_idle_10hz`, `test_stops_when_nothing_watched`, `test_update_only_on_change`, `test_mouseover_revalidated_each_tick`.
- [ ] **Step 2:** Run both clients; expect failures (module missing).
- [ ] **Step 3:** Implement. Range consults the Compat ladder first only for brackets LRC reports nil on Forever, then LRC `GetRange(unit, true)`. Ticker is one `C_Timer.NewTicker`, restarted at the new rate on `PLAYER_REGEN_DISABLED/ENABLED`; event list per spec §5.1, `PLAYER_FOCUS_CHANGED` registered only if `C_EventUtils.IsEventValid`. Add perf buckets `range.get`, `ticker.tick` in `core/PerfSetup.lua`.
- [ ] **Step 4:** Gate. Commit `Range engine: LibRangeCheck wrapper, per-client ladder, shared ticker`. Ledger row 2.

### Task 3: Data model and band sets

**Files:** Modify `defaults/Profile.lua`, `core/Database.lua`; Create `defaults/BandSetPresets.lua`, `modules/BandSets.lua`; Test `tests/test_bandsets.lua`, `tests/test_database.lua`.

**Interfaces:**
- Produces: `NS.CONTAINER_TEMPLATE`, `NS.BANDSET_TEMPLATE` (exact shapes in spec §5.2, including `bandSetFriendly` and `indicator.spellID`); profile keys `containers, containerOrder, nextContainerId, bandSets, bandSetOrder, nextBandSetId, seeded`.
  - `NS.BandSets.Create(name, bandsOrPresetKey?) -> id`, `Delete(id, reassignTo?) -> boolean`, `Duplicate(id) -> id`, `Rename(id, name)`, `List() -> {id,...}`, `Get(id) -> table`, `DefaultId() -> id`, `Normalise(id)`.
  - `NS.BandSets.Resolve(setId, state, minYd, maxYd) -> bandIndex|"unknown"|nil` (nil when state `"none"`).
  - `NS.BandSets.ForUnit(container, unit) -> setId` (friendly + `bandSetFriendly` set → that, else `bandSet`).
  - `NS.BandSetPresets = { melee_ranged, caster40, healer, hunter }` each `{name, matchBy, bands}`; `hunter` differs per client (spec §5.2). `NS.BandSetPresets.DefaultFor(classFile) -> key`.
  - Sends `NS.MSG.BANDSETS_CHANGED`.

- [ ] **Step 1: Write failing tests:** `test_resolve_by_max` ((20,25) in melee_ranged → index of MID 20–30); `test_resolve_by_min`; `test_resolve_open_ended` ((40,nil) → OOR); `test_resolve_unknown`; `test_resolve_none_nil`; `test_bandset_normalise` (bands `{0-5, 3-20, 30-nil, 20-30}` → sorted, contiguous, last `to=nil`, `Resolve` defined for every yd in 0..100); `test_bandset_delete_reassigns` (2 containers on set B, delete B → both on `DefaultId()`); `test_for_unit_friendly_override`; `test_hunter_preset_per_client` (forever has DEAD 5–8, retail does not); `test_template_fill_missing_keys` (stored container lacking `elements.spells` gets it on load); `test_first_run_seeds_presets` (fresh profile → 4 band sets, class default chosen).
- [ ] **Step 2:** Run → fail. **Step 3:** Implement (deep-copy templates; Database fills `== nil` keys; `RunMigrations` stays at schemaVersion 0). **Step 4:** Gate, commit `Data model and shared band sets`, ledger row 3.

### Task 4: ContainerManager and presets

**Files:** Create `modules/ContainerManager.lua`, `modules/Presets.lua`; Test `tests/test_container_manager.lua`, `tests/test_presets.lua`.

**Interfaces:**
- Consumes: Task 3 templates, `NS.BandSets`.
- Produces: `NS.CM.Create(unit?, opts?) -> id`, `Delete(id)`, `Duplicate(id) -> id`, `Rename(id, name)`, `UniqueName(base) -> string`, `CopySettings(fromId, toId, sections?)`, `Snapshot() -> table`, `RestoreSnapshot(snap)`, `List() -> {id,...}`, `Get(id) -> table`, `RequestApply()` (coalesced next frame; deferred in combat until `PLAYER_REGEN_ENABLED`). Sole sender of `CONTAINERS_CHANGED`.
  - `NS.Presets.Apply(key: "simple"|"intermediate"|"advanced") -> snapshotBefore`, `NS.Presets.Undo()`, `NS.Presets.Describe(key) -> {name, count, items}`.

- [ ] **Step 1: Write failing tests:** CRUD (`test_create_defaults_unit_target`, `test_unique_name_suffix` ("Target", "Target 2"), `test_delete_removes_from_order`, `test_duplicate_deep_copy`), `test_apply_coalesced_once_per_frame`, `test_apply_deferred_in_combat`; presets: `test_simple_four_free_containers` (units target,focus,pet,mouseover; anchor.mode all `screen`; only number enabled; border colorMode `band`), `test_intermediate_shape` (target/focus/pet anchor `frame` provider `blizzard`, mouseover `cursor`; number+text+indicator(dot); `bandSetFriendly` = healer on target/focus/mouseover; `visibility.hideNoUnit`), `test_advanced_shape` (6 containers incl. target `nameplate` diamond, unit `nameplates` dot+max format, focus spells enabled with seeds, an OOR sound on target, visibility combat `in`, reaction `hostile` on nameplates), `test_preset_undo_restores`.
- [ ] **Step 2–4:** Fail, implement, gate. Commit `ContainerManager and Simple/Intermediate/Advanced presets`, ledger row 4.

### Task 5: Container rendering and elements

**Files:** Create `modules/Container.lua`, `modules/Elements_Number.lua`, `modules/Elements_Text.lua`, `modules/Elements_Indicator.lua`, `modules/Elements_Spells.lua`, `modules/Style.lua`, `media/indicators/*.tga` (dot, ring, square, diamond, triangle; white, 64×64, 32-bit); Test `tests/test_number_format.lua`, `tests/test_container_render.lua`.

**Interfaces:**
- Consumes: `NS.Range`, `NS.BandSets.Resolve/ForUnit`, `NS.CM`, Bus.
- Produces: `NS.Elements.Number.Format(fmt, state, min, max, unknownLabel) -> string`; `NS.Container.Acquire(id) -> inst`, `inst:Render(state, min, max, spellResults)`, `inst:Release()`, `inst.bandIndex`; `NS.Container.ForEach(fn)`; layout builder honours `elements.order`, `layout.direction/spacing/padding/scale/alpha`; Style applies LSM fonts/borders and the LibKa0s skin.

- [ ] **Step 1: Write failing tests:** formats on (20,25): range `20–25`, max `25`, min `20`, under `<25`, approx `~22` (floor of mid 22.5), suffix `25 yd`; open (40,nil) → `40+` for every format; unknown → `?`. Render: `test_text_set_only_on_change` (spy SetText called once for two identical renders), `test_recolour_only_on_band_change`, `test_color_modes` (band / fixed / class), `test_element_order_row_and_column`, `test_hidden_elements_not_created`, `test_friendly_uses_friendly_set`.
- [ ] **Step 2–4:** Fail, implement (subscribe to `RANGE_UPDATED`; per-unit fan-out to containers watching that unit), gate. Commit `Container rendering: number, text, indicator, spell chips`, ledger row 5. Push.

### Task 6: Anchors

**Files:** Create `modules/Anchors.lua` (dispatcher), `modules/Anchors_Screen.lua`, `modules/Anchors_Frame.lua`, `modules/FrameProviders.lua`, `modules/FramePicker.lua`, `modules/Anchors_Nameplate.lua`, `modules/Anchors_Cursor.lua`; Test `tests/test_anchors_*.lua`.

**Interfaces:**
- Produces: `NS.Anchors.Apply(inst, container)`; `NS.FrameProviders.Resolve(provider, unit, customName) -> frame|nil` with providers `blizzard` (`TargetFrame`, `FocusFrame`, `PetFrame`; mouseover → nil, caller falls back to cursor) and `ellesmere` (names verified against the installed EllesmereUIUnitFrames under `_retail_` and `_forever_`; document them in `docs/compat-layer.md`); `NS.FramePicker.Start(cb(frameName))`; nameplate manager `NS.Plates.Get(unit) -> plate|nil`, `NS.Plates.ForEachHostile(fn(token, plate))`, one-frame re-check after `NAME_PLATE_UNIT_ADDED`, forbidden plates skipped, target plate identified by frame comparison.

- [ ] **Step 1: Write failing tests:** `test_screen_drag_saves_point`, `test_frame_blizzard_target`, `test_frame_missing_then_loaded` (hidden + 1 debug line, resolves on `ADDON_LOADED`), `test_frame_anchor_deferred_in_combat`, `test_mouseover_frame_falls_back_to_cursor`, `test_nameplate_own_plate_follows_target_change`, `test_nameplates_instance_per_hostile_plate`, `test_nameplates_friendly_toggle`, `test_nameplate_recycle` (REMOVED → instance released, no error on stale token), `test_forbidden_plate_skipped`, `test_cursor_single_onupdate` (3 cursor containers → 1 OnUpdate script).
- [ ] **Step 2–4:** Fail, implement, gate. Commit `Anchors: screen, unit frame (Blizzard, EllesmereUI, custom), nameplate, cursor`, ledger row 6.

### Task 7: Behaviour and modes

**Files:** Create `modules/Visibility.lua`, `modules/Sounds.lua`, `modules/Preview.lua` (Test mode), `modules/Sim.lua`; Test `tests/test_visibility.lua`, `tests/test_sounds.lua`, `tests/test_modes.lua`.

**Interfaces:**
- Produces: `NS.Visibility.Evaluate(container, unit) -> shown: boolean, alpha: number`; `NS.Sounds.OnBand(inst, bandIndex, now)` (per-instance state `{band, since, lastPlay, first}`); `NS.Preview.SetTestMode(on)`, `NS.Sim.SetSimMode(on)` (LibKa0s-Sim; distance sweep 0→50→0 yd over 20 s); both refuse in combat and end on `PLAYER_REGEN_DISABLED`; both drive the real render path via a fake `Range` source.

- [ ] **Step 1: Write failing tests:** visibility matrix (combat any/in/out × reaction any/hostile/friendly × hideNoUnit) + `oocAlpha`; sounds `test_settle_200ms`, `test_gap_1s`, `test_silent_first_band`, `test_no_sound_for_nameplates`; modes `test_test_mode_placeholders_all_containers`, `test_sim_sweeps_bands`, `test_refuse_in_combat`, `test_combat_ends_modes`, `test_launcher_and_slash_same_handler`.
- [ ] **Step 2–4:** Fail, implement, gate. Commit `Visibility rules, band sounds, Test and Sim modes`, ledger row 7.

### Task 8: Settings pages and slash verbs

**Files:** Modify `settings/Schema.lua`, `settings/Slash.lua`, `settings/General*.lua`; Create `settings/Containers.lua`, `settings/Containers_Display.lua`, `settings/Containers_Indicator.lua`, `settings/Containers_Visibility.lua`, `settings/Containers_Sounds.lua`, `settings/BandSets.lua`, `settings/Presets.lua`; Test `tests/test_settings_*.lua`, `tests/test_slash.lua`.

**Interfaces:**
- Consumes: everything above. Pages per spec §5.6 and the mockup (boards 2, 3, 5): Containers banner picker + `New container`, rail General · Display · Indicator · Visibility · Sounds (Sounds hidden for `nameplates`), live band preview; Band sets picker + New/Duplicate, distance ribbon, drag-to-reorder band rows (from, to, label, frame/text/indicator colour each with class-colour companion, sound), match-by, unknown label; General › Presets tab with three cards and Apply (confirm) + Undo; first-run preset picker when `seeded == false`.
- Produces: schema paths `container.<key>` and `bandSet.<key>` resolved against the selected item; slash verbs `containers`, `select <n|name>`, `new [unit]`, `delete <n>`, `pick`, `bands`, `preset <key>`, `test`, `sim` plus the reserved set.

- [ ] **Step 1: Write failing tests:** surface parity for every new row; `test_container_paths_get_set` (`/rm set container.unit focus` changes the selected container); `test_bandset_paths_get_set`; `test_sounds_section_hidden_for_nameplates`; `test_preset_apply_confirms`; `test_first_run_picker_once`; `test_open_in_combat_refused`; slash `test_new_unit_arg`, `test_select_by_name`, `test_preset_verb`.
- [ ] **Step 2–4:** Fail, implement, gate. Commit `Settings: Containers, Band sets, Presets pages and slash verbs`, ledger row 8. Push.

### Task 9: Docs, roster, bundles, issues

- [ ] **Step 1:** Fill every doc NEW_ADDON.md requires with real content (`docs/ARCHITECTURE.md`, `testing.md`, `smoke-tests.md` covering each anchor mode × client, `scope.md`, `module-map.md`, `schema.md`, `settings-panel.md`, `data-flow.md`, `common-tasks.md`, `debug.md`, `midnight-quirks.md`, `compat-layer.md`, `test-cases.md`, `performance.md`); README Version History `0.1.0`.
- [ ] **Step 2:** Run `tests/_kit/run-automated-tests.sh --release 0.1.0` (expect all four suites pass, zero functions > CCN 15); write the automated-tests bundle; run `/dev-copilot:wow-standards-audit` for the first `docs/audits/<date>/` bundle and fix every deviation it reports that is in scope.
- [ ] **Step 3:** Roster: in `WowAddonStandards`, on branch `feat/rangemaster-roster`, add the row from spec §5.8; commit; push; do not merge.
- [ ] **Step 4:** GitHub issues (Ka0s style, `gh issue create` with `state:*`, `severity:*`, `bug|enhancement`): one enhancement per Task 2–8 feature (closed `state:done` when merged), plus deferred, `state:triaged`: import/export strings; ElvUI / SUF / Cell providers; party/raid/arena/boss units; Edit Mode integration; finer distance estimator.
- [ ] **Step 5:** Gate, commit `docs: full doc set, first automated-test and audit bundles`, ledger row 9.

### Task 10: Review and hand-off

- [ ] **Step 1:** Run the WoW-specific whole-addon review (`dev-copilot:review`), triage findings, fix in-scope ones test-first.
- [ ] **Step 2:** Gate; push branch; open a PR `feat/v0.1.0-initial-build → master` (body ends with the PR attribution). **Do not merge** until the owner says go.
- [ ] **Step 3 (after go-ahead):** merge, close Task issues as `state:done`, delete `feat/v0.1.0-initial-build` (local + remote), the WowAddonStandards roster branch after its merge, and any worktrees/stashes from this run.
