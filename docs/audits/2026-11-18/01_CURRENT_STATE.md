# 01 — Current state: Ka0s Range Master

Run date 2026-11-18. First audit of this repo; deviation prefix **`RM-`** assigned here.

## What was measured

| Item | Value |
|---|---|
| Repo | `RangeMaster`, branch `feat/v0.1.0-initial-build`, HEAD `1e3654e0f461b39b9090c7ed7644ce88b9ee76e2` (2026-11-18 08:41 +0530), clean working tree |
| Kind | **Addon** (has `RangeMaster.toc`; `dev-copilot-profile` answered `profile=wow kind=addon reason=toc:## Interface`; the playbook's kind table agrees) — audited against the whole addon rule set |
| Standard | **Ka0s WoW Addon Standard v2.113.0 (2026-11-16)**, `standards/STANDARDS.md` and all 31 section files its Sections list links |
| Standard source | Network fetch from raw GitHub `master` (`AUDIT.md`, `standards/STANDARDS.md`, `standards/ADDONS.md`, 31 section files). Cross-checked against the sibling `../WowAddonStandards` checkout: clean, `HEAD` = `origin/master` = `1f5767f338ce7ecd3d7a2b698baee8920eea0400`, and `diff -q` between the fetch and the sibling empty for every file. Both sources are the same bytes. |
| Roster row | **None.** `standards/ADDONS.md` has no Range Master row, so its Clients, Launcher-menu, Skin-picker-preview and Sim-mode columns cannot be read (RM-06). The column-driven checks below were run against what the code ships, and say so. |

## Layout (layout)

- Folders `core/ defaults/ locales/ modules/ settings/`, plus `media/` (`logos/`, `textures/indicators/`), `libs/`, `tests/`, `docs/`. No `tools/`, no `Bindings.xml`, no loose root file beyond the TOC, the root doc set and the dotfiles.
- Authored Lua (default census scope, `git ls-files '*.lua' | grep -vE '^(libs/|tests/_kit/)'`): 111 files, the largest `settings/Schema.lua` at 727 lines. Nothing in the 1000–1500 band, nothing over the cap. The hub's `### Files over the 1500-line cap` census says "Nothing is over the cap today" and the kit gate `tests/_kit/test_layout_cap.lua` is declared in `tests/run.lua`.
- Own media: the two logo files (`rangemaster.logo.128.tga` is type 2 / 128×128 / 32-bit, read from the header bytes) plus five indicator shapes (`dot`, `ring`, `square`, `diamond`, `triangle`) the LibKa0s catalog does not carry.

## TOC (toc-file)

`RangeMaster.toc`: fields in the mandated order; `## Interface: 120105, 16001` (dual client, no load-gating line); `## IconTexture` names the addon's own 128 logo; `## SavedVariables: RangeMasterDB, RangeMasterPerfDB`; `EllesmereUI` in `## OptionalDeps` only; unpublished, carrying `# X-Curse-Project-ID: not published on CurseForge yet` (compliant). The listing is `#`-sectioned in the folder order, `libs\LibKa0s\LibKa0s.xml` listed once, and every load-bearing position carries a `LOAD-BEARING:` comment naming what resolves, every other a `Conventional:` one.

## Libraries (library-stack)

- Vendored: LibStub, CallbackHandler-1.0, AceAddon/AceEvent/AceTimer/AceConsole/AceDB/AceGUI/AceConfig/AceDBOptions, LibDataBroker-1.1, LibDBIcon-1.0, LibSharedMedia-3.0, LibRangeCheck-3.0 (MINOR 39, commit recorded in `DEPENDENCIES.md`), LibKa0s.
- **LibKa0s v1.105.0**, provenance line in root `CLAUDE.md:38`, `LibKa0s icons:` declaration on the next non-blank line (`CLAUDE.md:39`), no `LibKa0s sounds:` line (means `none`). `diff -r` against the sibling's `v1.105.0` tag: the ship folder differs only by undeclared icons and the undeclared `media/sounds/callout` packs; the test kit is byte-identical (03_EVIDENCE E3).
- Shared subsystems consumed through setup files, each `LibStub(..., true)` with a library-absent stub: `core/CoreSetup.lua`, `core/EnvSetup.lua`, `core/MediaSetup.lua`, `core/SkinSetup.lua`, `core/Bus.lua`, `core/LifecycleSetup.lua`, `core/PerfSetup.lua`, `core/PoolSetup.lua`, `core/DebugLogSetup.lua`, `core/LauncherSetup.lua`, `settings/Schema.lua`, `settings/Slash.lua`, `settings/OptionsSetup.lua`, and `modules/Sim.lua` (LibKa0s-Sim-1.0). No hand-built console, dispatcher, widget maker or harness. `tests/test_surface_parity.lua` pins each stub against its major.

## Patterns (architecture, savedvariables, events-frames-taint, frame-layering)

- AceAddon object `core/RangeMaster.lua`; one closed bus of four messages declared once in `core/Bus.lua` through `LibKa0s-Bus-1.0`'s strict `Catalog`, PascalCase wire names, no literal at any call site; every receiver on its own tracked `NS.NewBusTarget()`.
- Schema-as-single-source through `NS.SetByPath`; two structural registries (band sets, containers) with named writers in `docs/ARCHITECTURE.md` → Settings Schema. The containers registry's first-run sentinel `seeded` has a second writer outside its named writer (RM-05).
- AceDB defaults carry `schemaVersion = 0`; `core/Database.lua` runs the migration ladder (`NS.SCHEMA_VERSION` from the step list).
- Events: one list (`NS.__lifecycleEvents`), each registered through `NS.SafeRegisterEvent` (the LibKa0s-Core family), rejected names recorded in `NS.State.rejectedEvents`. No `hooksecurefunc` or `HookScript` anywhere in authored code.
- Frame layering: one `C.LAYERS` table in `core/Constants.lua`; three `SetFrameStrata` calls read it (or the player's strata row); one relative `SetFrameLevel`. The player strata row offers `BACKGROUND`–`HIGH` with `H.StrataTooltip`.

## Settings (options-ui, skinning)

Built on `LibKa0s-Options-1.0`: landing page, General (Master controls composed by `H.MasterControls` with Test mode and Sim mode, Presets tab, Skin tab last; no key bindings so no Keybindings tab), Containers (nav rail + tabs), Band sets, Profiles. Skins adopted (`Skin:RegisterOwner(addonName, …)` at `core/SkinSetup.lua:431`), `skin` verb directly after `config`, not in `liveVerbs`. Media pickers are `Ka0sMedia_*` (sound picker at `settings/BandSets.lua:205`; font and border rows composed). No `disabledIf`, no arrow reorder, no `LSM30_`. Display-character sweep: every non-ASCII glyph in authored strings (`–`, `—`, `…`, `·`) is in localization-§7's safe set.

## Slash (slash-commands)

`/rm` and `/rangemaster` over `NS.COMMANDS` (`settings/Slash.lua`), dispatched by `LibKa0s-Slash-1.0`; `liveVerbs` built on `SlashLib.LIVE_VERBS` plus `diagnostics` and `profile`; feature verbs refuse on the library's one line. `enable`/`disable` write `enabled` through the seam; `lock`/`unlock` present (MAY) and write `locked` through the seam.

**Disabled state.** One latch, `LibKa0s-Lifecycle-1.0`, holds `disabled` (stored) and `perf` (session, taken by `core/PerfSetup.lua` on the same latch). `StandDown` (`core/LifecycleSetup.lua:55-64`) ends both modes, hides both pickers, unregisters every lifecycle event, stands down every feature module and the bus record. Census (03_EVIDENCE E7): every `RegisterEvent`/`RegisterMessage` in the load list is either undone by the stand-down or is a one-shot `PLAYER_REGEN_ENABLED` on a tracked bus target; every ticker/timer/`OnUpdate` is cancelled by a stand-down step **except** the skin-notice combat retry `C_Timer.After` (RM-04). `tests/test_disabled.lua` ships in the green gate; its walk against the ten steps is RM-03.

## Debug (debug-logging)

`core/DebugLogSetup.lua` descriptor carries `addonName`; `diagnostics` is one `COMMANDS` row and one `debug` word, no alias; the report's sections are `modules/Diagnostics.lua`; the default (logging turns on) is kept. Slash, Options, Launcher and Lifecycle descriptors each pass `debug`; Launcher passes `debugAtEnable`. README carries `## Reporting a bug` verbatim.

## Launcher (launcher)

One LDB object via `LibKa0s-Launcher-1.0`, label `NS.Constants.BRAND` = `"Ka0s Range Master"`, toggles `isEnabled/setEnabled`, `isLocked/toggleLock`, `isTestMode/toggleTestMode`, `isSimMode/toggleSim`, each routed to the verb's handler. No host `OnClick`, no `OnTooltipShow`. The row the roster would carry is `Enabled · Locked · Test mode · Sim mode` (not recorded: RM-06).

## Preview (preview-mode)

Test mode and Sim mode are session-only, refused in combat and while stood down, ended at `PLAYER_REGEN_DISABLED`. Containers wear `Widgets.TestStrip`, docked through `KW.DockTestStrip` (`modules/Container.lua:373-389`). Sim is on `LibKa0s-Sim-1.0`; `tests/test_modes.lua` asserts `seam:Unwrapped()` is empty. The release bundle `20261118-083858` carries `## Preview and simulation data` answered *Refreshed*.

## Clients (clients)

Dual-client TOC; detection only through `NS.Compat` (`grep WOW_PROJECT_|GetBuildInfo` hits a comment only); per-client feature table in the hub; seeds as two lists keyed by `ClientKey()` (`defaults/SpellSeeds.lua`); green under both kit profiles. No DB2-derivation record for the seed lists (RM-08).

## Tests, lint, performance, automated tests

- `ka0s-bounded lua tests/run.lua`: **602 passed, 0 failed, 1 skipped, 603 total**, exit 0. Same under `KA0S_KIT_CLIENT=forever`. The skip is the kit's diagnostics opt-out case, which this addon does not take.
- `ka0s-bounded luacheck .`: **0 warnings / 0 errors in 111 files**, exit 0. `exclude_files` narrows to `libs/`, `tests/_kit/` and the frozen `docs/` stores; harness globals in `files["tests/"]`; no top-level `ignore`.
- Kit revision 57; `test_lizard_sighted`, `test_eol`, `test_layout_cap`, `test_skin_values`, `test_skin_switch` declared with `dir = "tests/_kit/"`.
- Complexity (`ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle`): pass, 0 warnings, 16345 NLOC / 2538 functions, max CCN 15 — identical to the newest bundle `20261118-083858`, which measured `a756304`, one commit behind HEAD (that commit only wrote the bundle itself). Watch list empty. Newest manifest `blindFiles` 0, `crashedFiles` 0, `release` `0.1.0`.
- Perf: `core/PerfSetup.lua`, 13 scenarios in `tests/perf.lua`, `docs/perf-analysis/README.md` present.

## Packaging and line endings (packaging, line-endings)

- `.pkgmeta` ignores every named dev-only entry; the only unaccounted root dot-entry is `.git`, which the packager never sees. No false conditional claims.
- `.gitattributes` (verbatim pin `* text=auto eol=crlf`, carve-outs `*.sh text eol=lf` and `*.py text eol=lf`, 20 `binary` lines): its 84 lines diff clean against line-endings-§5's client-bound canonical body, no tail. Working-tree agreement: **0** tracked files disagree with the pin. The vendored `tests/_kit/test_eol.lua` gate is wired.

## Root doc set (documentation-§1/§2/§7)

- `README.md`: badges in order and bare; dual-client `[wow]` badge; supported-clients sentence first; `Tests-602%2F602_passing` matches the inventory (skip excluded); no logo image; no library inventory; no numbered list; no font text; `## Usage` names `/rm skin`; `## Credits` credits Open Iconic (the only icon set shipped). **H1 is `# Range Master`, not `# Ka0s Range Master`** (RM-02).
- `CLAUDE.md`: stub shape, `## Standards compliance (read first)`, green-gate line, provenance + icons lines.
- `DEPENDENCIES.md`: runtime, development and release groups with evidence; one present-tense in-repo `path:line` (RM-07).

## docs/ (documentation-§3)

- Tier 1 all present under canonical names. Tier 2: `slash-dispatch.md`, `midnight-quirks.md`, `compat-layer.md` (18 shims by documentation-§3's own count), `profiles.md`, `debug.md`, `perf-analysis/README.md` present; `message-bus.md`, `known-limitations.md`, `taint.md` carry *Not applicable* rows whose triggers have not fired (4 messages; hub sections 27 and 32 lines). No non-canonical or retired filename.
- `## Documentation map` has the four tables; every live `.md` under `docs/` is in exactly one, no dangling row; frozen stores named once.
- **`docs/midnight-quirks.md` has lost its vendored client-quirks block**: zero `VENDORED` markers, and the own-section heading is cut mid-sentence. It was present at `6ed49cb` and removed by `a756304` (RM-01).
- Hub `docs/ARCHITECTURE.md` is 285 lines; no mandated section past ~60.

## Recorded-deviation register

`docs/ARCHITECTURE.md` → `## Documented deviations`: **None.** No root `CLAUDE.md` accepted-deviation note; `docs/scope.md` records scope only. Issue store (`gh issue list --state all`): 13 open issues, all `enhancement`, labels `state:triaged` or `state:untriaged`; no `state:will-not-do`, no `[status]` prefix, no `docs/pending/LEDGER.md`. Nothing ratified to reconcile and nothing declined without a row. `docs/revendor/` does not exist yet: the libraries were vendored at scaffold, and the store is owed at the first re-vendor.
