# Module map — Ka0s Range Master

Every non-vendored file, its one-line responsibility, in TOC load order (`RangeMaster.toc`). The
folder order is `libs/*` → `locales/*` → `core/*` → `defaults/*` → `modules/*` → `settings/*`
(layout-§1); inside each folder the order is dependency-correct, and every load-bearing position
carries a `# LOAD-BEARING:` note at its TOC line (toc-file-§5). `tests/test_loadorder.lua` holds the
runner's load list to the TOC.

## Locales

| File | Responsibility |
|---|---|
| `locales/enUS.lua` | `NS.L` with its key-echo fallback; the generated key set. LOAD-BEARING: first, every file reads `NS.L` |

## Core

| File | Responsibility |
|---|---|
| `core/Namespace.lua` | `NS.name`, the fallback `NS.version`, the cyan `[RM]` `NS.PREFIX`. LOAD-BEARING |
| `core/Compat.lua` | The client seam (`IsForever`, `IsRetail`, `ClientKey`, `ForClient`), the secret guards and `GetSpellInfo`, routed from `LibKa0s-Compat-1.0` with library-absent stand-ins; the range reads (`IsEventValid`, `IsSpellKnown`, `IsSpellUsable`, `SpellInRange`, `ItemInRange`, `InteractInRange`, `CanAttack`) and the per-client `RangeLadder` (`docs/compat-layer.md`) |
| `core/EnvSetup.lua` | `LibKa0s-Env-1.0`: `NS.Meta(field)` and `NS.Version()` |
| `core/MediaSetup.lua` | `LibKa0s-Media-1.0`: `NS.Icon`, `NS.MediaFont`, the one `RegisterLSM`. LOAD-BEARING: before Constants |
| `core/Constants.lua` | Fallback media, `FONT_MONO`, the logo paths, `BRAND`, `MINIMAP_PATH`, the band color ramp, `LAYERS` |
| `core/State.lua` | Session-only state: `debug`, `testMode`, `simMode`, `rejectedEvents` |
| `core/CoreSetup.lua` | `LibKa0s-Core-1.0`: `NS.Print` / `NS.Printf`, `SafeToString`, `ResolveColor`, `SafeRegister*`, `SKIN`, the one `NS.MakeCloseButton` wrapper. LOAD-BEARING |
| `core/SkinSetup.lua` | `LibKa0s-Skin-1.0`: the owner registered at load, the skin choice seam, the first-run picker (preview in Test mode) and `/rm skin`. LOAD-BEARING |
| `core/Bus.lua` | `LibKa0s-Bus-1.0`: `NS.bus`, the strict `NS.MSG` catalog, tracked `NS.NewBusTarget()`. LOAD-BEARING |
| `core/LifecycleSetup.lua` | `LibKa0s-Lifecycle-1.0`: the one latch, `StandDown` / `StandUp`, `NS.SyncEnabledHold`. LOAD-BEARING: before PerfSetup |
| `core/PerfSetup.lua` | `LibKa0s-Perf-1.0`: `NS.Perf`, the declared buckets, `RangeMasterPerfDB`. LOAD-BEARING |
| `core/Data.lua` | `NS.GetSetting`, the minimap row's inverted storage, `NS.GetLSM` |
| `core/Database.lua` | AceDB, the profile backfill, the migration runner |
| `core/DebugLogSetup.lua` | `LibKa0s-DebugLog-1.0`: `NS.DebugLog`, `NS.Debug` and its gates, the diagnostics brand and sections. LOAD-BEARING |
| `core/LauncherSetup.lua` | `LibKa0s-Launcher-1.0`: one broker object registered twice, menu Enabled · Locked · Test mode · Sim mode |
| `core/RangeMaster.lua` | The AceAddon; `OnInitialize` / `OnEnable`; the lifecycle events; Test mode and Sim mode's one writer each; the profile callbacks. LOAD-BEARING: reclaims `NS.Print` |

## Defaults, modules, settings

| File | Responsibility |
|---|---|
| `defaults/Profile.lua` | `NS.defaults`: the Master controls, the skin choice, the global schema stamp and `minimap` |
| `defaults/SpellSeeds.lua` | `NS.SpellSeeds[client][classFile] = { chips, ladder }`: the per-client, per-class spell seeds; data only |
| `modules/Range.lua` | `NS.Range`: `Get` (the guarded LibRangeCheck bracket, the per-tick memo by unit token, Forever's ladder fallback), `InSpellRange`, `BeginTick`, `SetPerfParent`, `Rebuild`. LOAD-BEARING: before Ticker |
| `modules/Ticker.lua` | `NS.Ticker`: the watch list, the one adaptive `C_Timer` ticker, `RANGE_UPDATED` on change, `Removed` for a plate going away; `StandDown` / `StandUp` |
| `modules/Diagnostics.lua` | The `/rm diagnostics` report's sections |
| `settings/Schema.lua` | `LibKa0s-Schema-1.0` instance and its runtime-completing stub: `NS.SetByPath`, `NS.FindSchemaRow`, `NS.ApplyDefault`, `NS.SchemaForPage`, `NS.ValidateSchema`. LOAD-BEARING |
| `settings/Slash.lua` | `NS.COMMANDS` and the `LibKa0s-Slash-1.0` descriptor. LOAD-BEARING |
| `settings/OptionsSetup.lua` | `LibKa0s-Options-1.0`: `NS.Helpers`, eager category registration, the reset vetoes. LOAD-BEARING |
| `settings/About.lua` | The landing page's spec, drawn by `BuildLandingPage` |
| `settings/General.lua` | The General page: Master controls (composed) and the Skin tab |
| `settings/Profiles.lua` | The Profiles sub-page (AceDBOptions) |

## LibKa0s modules: wired and vendored

Wired, one setup file each: Core, Env, Compat, Media, Skin, Bus, Lifecycle, Perf, DebugLog, Launcher,
Schema (in `settings/Schema.lua`), Slash, Options. Vendored but not yet wired (normal: adoption is per
module): Pool (the container instances, plan Task 5), Widgets (the drag strip and test strip, Tasks 5
to 7), Sim (Sim mode's distance sweep, Task 7), Tooltip, Role, Item, Glow, Callout, Charts,
IconBrowser, Toast and WaypointArrow.

## Tests

`tests/run.lua` (the load list, the lifecycle kick and the suite list), `tests/wow_mock.lua` (a thin
extender over the kit's base mock), `tests/degraded_env.lua` (a second environment with LibKa0s
absent), `tests/mock_menu.lua` (the context-menu stand-in), `tests/perf.lua` (offline scenarios,
outside the gate), `tests/client_globals_allow.lua` (the kit gate's allowlist) and one
`tests/test_*.lua` per seam. `tests/_kit/` is vendored and never edited.
