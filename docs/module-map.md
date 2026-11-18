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
| `core/Compat.lua` | The client seam (`IsForever`, `IsRetail`, `ClientKey`, `ForClient`), the secret guards and `GetSpellInfo`, routed from `LibKa0s-Compat-1.0` with library-absent stand-ins; the range reads (`IsEventValid`, `IsSpellKnown`, `IsSpellUsable`, `SpellInRange`, `ItemInRange`, `InteractInRange`, `CanAttack`), the band sets' unit reads (`IsFriend`, `PlayerClass`) and the per-client `RangeLadder` (`docs/compat-layer.md`) |
| `core/EnvSetup.lua` | `LibKa0s-Env-1.0`: `NS.Meta(field)` and `NS.Version()` |
| `core/MediaSetup.lua` | `LibKa0s-Media-1.0`: `NS.Icon`, `NS.MediaFont`, the one `RegisterLSM`. LOAD-BEARING: before Constants |
| `core/Constants.lua` | Fallback media, `FONT_MONO`, the logo paths, `BRAND`, `MINIMAP_PATH`, `INDICATOR_PATH`, the band color ramp and `HexColor`, `LAYERS` |
| `core/State.lua` | Session-only state: `debug`, `testMode`, `simMode`, `rejectedEvents` |
| `core/CoreSetup.lua` | `LibKa0s-Core-1.0`: `NS.Print` / `NS.Printf`, `SafeToString`, `ResolveColor`, `SafeRegister*`, `SKIN`, the one `NS.MakeCloseButton` wrapper. LOAD-BEARING |
| `core/SkinSetup.lua` | `LibKa0s-Skin-1.0`: the owner registered at load, the skin choice seam, the first-run picker (preview in Test mode) and `/rm skin`. LOAD-BEARING |
| `core/Bus.lua` | `LibKa0s-Bus-1.0`: `NS.bus`, the strict `NS.MSG` catalog, tracked `NS.NewBusTarget()`. LOAD-BEARING |
| `core/LifecycleSetup.lua` | `LibKa0s-Lifecycle-1.0`: the one latch, `StandDown` / `StandUp`, `NS.SyncEnabledHold`. LOAD-BEARING: before PerfSetup |
| `core/PerfSetup.lua` | `LibKa0s-Perf-1.0`: `NS.Perf`, the declared buckets, `RangeMasterPerfDB`. LOAD-BEARING |
| `core/PoolSetup.lua` | `LibKa0s-Pool-1.0`: `NS.Pool`, the library's pool or a local copy of its eight members (the array and the keyed shapes) |
| `core/Data.lua` | `NS.GetSetting`, the minimap row's inverted storage, `NS.GetLSM` |
| `core/Database.lua` | AceDB, the profile backfill, the migration runner, the registries' load pass (`PrepareProfile`) |
| `core/DebugLogSetup.lua` | `LibKa0s-DebugLog-1.0`: `NS.DebugLog`, `NS.Debug` and its gates, the diagnostics brand and sections. LOAD-BEARING |
| `core/LauncherSetup.lua` | `LibKa0s-Launcher-1.0`: one broker object registered twice, menu Enabled · Locked · Test mode · Sim mode |
| `core/RangeMaster.lua` | The AceAddon; `OnInitialize` / `OnEnable`; the lifecycle events; Test mode and Sim mode's one writer each; the profile callbacks. LOAD-BEARING: reclaims `NS.Print` |

## Defaults, modules, settings

| File | Responsibility |
|---|---|
| `defaults/Profile.lua` | `NS.defaults`: the Master controls, the skin choice, the global schema stamp and `minimap`; `NS.CONTAINER_TEMPLATE`, `NS.BANDSET_TEMPLATE`, `NS.BAND_TEMPLATE` |
| `defaults/SpellSeeds.lua` | `NS.SpellSeeds[client][classFile] = { chips, ladder }`: the per-client, per-class spell seeds; data only |
| `defaults/BandSetPresets.lua` | `NS.BandSetPresets`: the four preset band sets (the Hunter set per client), `ORDER`, `DefaultFor(classFile)`; data only |
| `modules/BandSets.lua` | `NS.BandSets`: the band-set registry's writer (`Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `RestoreSnapshot`), `Snapshot`, `List`, `Get`, `DefaultId`, `Resolve`, `ForUnit`, and the load pass's `Seed` and `NormalizeSet`; sender of `BANDSETS_CHANGED` |
| `modules/Range.lua` | `NS.Range`: `Get` (the guarded LibRangeCheck bracket, the per-tick memo by unit token, Forever's ladder fallback), `InSpellRange`, `BeginTick`, `SetPerfParent`, `Rebuild`. LOAD-BEARING: before Ticker |
| `modules/Ticker.lua` | `NS.Ticker`: the watch list, the one adaptive `C_Timer` ticker, `RANGE_UPDATED` on change, `Removed` for a plate going away; `StandDown` / `StandUp` |
| `modules/ContainerManager.lua` | `NS.CM`: the container registry's writer (`Create`, `Delete`, `Duplicate`, `Rename`, `UniqueName`, `CopySettings`, `Clear`, `Snapshot`, `RestoreSnapshot`), `List`, `Get`, the coalesced, combat-deferred `RequestApply` / `FlushPending`; sender of `CONTAINERS_CHANGED` |
| `modules/Presets.lua` | `NS.Presets`: `Apply` (Simple, Intermediate, Advanced, through `NS.CM`), the one-level `Undo` / `CanUndo`, `Describe` for the preset cards, `OOR_SOUND` |
| `modules/Style.lua` | `NS.Style`: a setting's color (band, fixed, class), the HUD face through the skin's `S.HudFont`, measured text width, edge strips, the media border, frame levels over a root. LOAD-BEARING: before the element files |
| `modules/Elements_Number.lua` | `NS.Elements.Number`: `Format` (the six formats, `40+`, the unknown label) and the number element |
| `modules/Elements_Text.lua` | `NS.Elements.Text`: the band label element |
| `modules/Elements_Indicator.lua` | `NS.Elements.Indicator`: the shapes (this addon's art), the bar (LibKa0s-Widgets' `W.Bar`) and the spell icon |
| `modules/Elements_Spells.lua` | `NS.Elements.Spells`: the spell chips, pooled per element, colored by each spell's own answer |
| `modules/Container.lua` | `NS.Container`: the renderer: one pooled instance per enabled container (`Acquire`, `Get`, `ForEach`, `Sync`, `Repaint`, `StandDown`; `inst:Render`, `inst:Update`, `inst:Release`), the `RANGE_UPDATED` fan-out by unit |
| `modules/Diagnostics.lua` | The `/rm diagnostics` report's sections |
| `settings/Schema.lua` | `LibKa0s-Schema-1.0` instance and its runtime-completing stub: `NS.SetByPath`, `NS.FindSchemaRow`, `NS.ApplyDefault`, `NS.SchemaForPage`, `NS.ValidateSchema`. LOAD-BEARING |
| `settings/Slash.lua` | `NS.COMMANDS` and the `LibKa0s-Slash-1.0` descriptor. LOAD-BEARING |
| `settings/OptionsSetup.lua` | `LibKa0s-Options-1.0`: `NS.Helpers`, eager category registration, the reset vetoes. LOAD-BEARING |
| `settings/About.lua` | The landing page's spec, drawn by `BuildLandingPage` |
| `settings/General.lua` | The General page: Master controls (composed) and the Skin tab |
| `settings/Profiles.lua` | The Profiles sub-page (AceDBOptions) |

## LibKa0s modules: wired and vendored

Wired, one setup file each: Core, Env, Compat, Media, Skin, Bus, Lifecycle, Perf, DebugLog, Launcher,
Schema (in `settings/Schema.lua`), Slash, Options, Pool (`core/PoolSetup.lua`: the container
instances and the spell chips). Widgets is read where it is drawn, as the library's optional
widgets are: `W.Bar` for the bar indicator (`modules/Elements_Indicator.lua`, a flat strip without
it); its drag strip and test strip arrive with plan Tasks 6 and 7. Vendored but not yet wired
(normal: adoption is per module): Sim (Sim mode's distance sweep, Task 7), Tooltip, Role, Item, Glow,
Callout, Charts, IconBrowser, Toast and WaypointArrow.

## Media

`media/logos/` (the addon logo, layout-§4) and `media/textures/indicators/` (the indicator shapes:
`dot`, `ring`, `square`, `diamond`, `triangle`, each a white 64x64 uncompressed 32-bit TGA tinted at
draw time; `tests/test_container_render.lua` checks the headers).

## Tests

`tests/run.lua` (the load list, the lifecycle kick and the suite list), `tests/wow_mock.lua` (a thin
extender over the kit's base mock), `tests/degraded_env.lua` (a second environment with LibKa0s
absent), `tests/mock_menu.lua` (the context-menu stand-in), `tests/perf.lua` (offline scenarios,
outside the gate), `tests/client_globals_allow.lua` (the kit gate's allowlist) and one
`tests/test_*.lua` per seam. `tests/_kit/` is vendored and never edited.
