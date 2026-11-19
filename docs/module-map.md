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
| `core/Compat.lua` | The client seam (`IsForever`, `IsRetail`, `ClientKey`, `ForClient`), the secret guards and `GetSpellInfo`, routed from `LibKa0s-Compat-1.0` with library-absent stand-ins; the range reads (`IsEventValid`, `IsSpellKnown`, `IsSpellUsable`, `SpellInRange`, `ItemInRange`, `InteractInRange`, `CanAttack`), the band sets' unit reads (`IsFriend`, `PlayerClass`), the anchors' frame reads (`NamePlateForUnit`, `PlateToken`, `NamePlates`, `GetMouseFocus`) and the per-client `RangeLadder` (`docs/compat-layer.md`) |
| `core/EnvSetup.lua` | `LibKa0s-Env-1.0`: `NS.Meta(field)` and `NS.Version()` |
| `core/MediaSetup.lua` | `LibKa0s-Media-1.0`: `NS.Icon`, `NS.MediaFont`, the one `RegisterLSM`. LOAD-BEARING: before Constants |
| `core/Constants.lua` | Fallback media, `FONT_MONO`, the logo paths, `BRAND`, `MINIMAP_PATH`, `INDICATOR_PATH`, the band color ramp and `HexColor`, `LAYERS` (the HUD and the picker strata, the level ladder and the per-instance `BASE` / `STRIDE` / `SLOTS`) |
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
| `core/RangeMaster.lua` | The AceAddon; `OnInitialize` / `OnEnable`; the lifecycle events (routing the unit and plate events to the renderer, the anchors and the ticker); Test mode and Sim mode's one writer each; `NS.ResetPositions`; the profile callbacks. LOAD-BEARING: reclaims `NS.Print` |

## Defaults, modules, settings

| File | Responsibility |
|---|---|
| `defaults/Profile.lua` | `NS.defaults`: the Master controls, the skin choice, the global schema stamp and `minimap`; `NS.CONTAINER_TEMPLATE`, `NS.BANDSET_TEMPLATE`, `NS.BAND_TEMPLATE` |
| `defaults/SpellSeeds.lua` | `NS.SpellSeeds[client][classFile] = { chips, ladder, anchors }`: the per-client, per-class spell seeds (`anchors`: the band rules' ordered melee / ranged / friendly lists, druid melee keyed by form); data only |
| `defaults/BandSetPresets.lua` | `NS.BandSetPresets`: the four preset band sets (the Hunter set per client), `ORDER`, `DefaultFor(classFile)`; data only |
| `modules/BandSets.lua` | `NS.BandSets`: the band-set registry's writer (`Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `SetField`, `SetBand`, `AddBand`, `RemoveBand`, `SetBandSound`, `RestoreSnapshot`), `UniqueName`, `Snapshot`, `List`, `Get`, `DefaultId`, `Resolve`, `ForUnit`, and the load pass's `Seed` and `NormalizeSet`; sender of `BANDSETS_CHANGED` |
| `modules/Range.lua` | `NS.Range`: `Get` (the guarded LibRangeCheck bracket, the per-tick memo by unit token, Forever's ladder fallback), `InSpellRange`, `BeginTick`, `SetPerfParent`, `Rebuild`, the preview's fake source (`SetSource`, `HasSource`). LOAD-BEARING: before Ticker |
| `modules/Ticker.lua` | `NS.Ticker`: the watch list, the one adaptive `C_Timer` ticker, `RANGE_UPDATED` on change, `Changed` for a new unit behind a token (sent even unmoved), `OnSteady` listeners for an unmoved read, `Removed` for a plate going away; `StandDown` / `StandUp` |
| `modules/ContainerManager.lua` | `NS.CM`: the container registry's writer (`Create`, `Delete`, `Duplicate`, `Rename`, `UniqueName`, `CopySettings`, `Clear`, `Snapshot`, `RestoreSnapshot`, `SetField`), `IsElementOrder`, `List`, `Get`, `SetPosition` / `ResetPosition` (a drag's result, Reset position), the coalesced, combat-deferred `RequestApply` / `FlushPending`; sender of `CONTAINERS_CHANGED` |
| `modules/Presets.lua` | `NS.Presets`: `Apply` (Simple, Intermediate (Range Text), Intermediate (Range Numbers), Advanced, Expert, through `NS.CM`), the first-run picker's `BeginPreview` / `EndPreview`, the one-level `Undo` / `CanUndo`, `Describe` for the preset cards, `OOR_SOUND`, and `PickerDue` / `MarkPickerSeen` (the writer of `profile.seeded`) |
| `modules/Style.lua` | `NS.Style`: a setting's color (band, fixed, class), the HUD face through the skin's `S.HudFont`, measured text width, edge strips, the media border, frame levels over a root. LOAD-BEARING: before the element files |
| `modules/Elements_Number.lua` | `NS.Elements.Number`: `Format` (the six formats, `40+`, the unknown label) and the number element |
| `modules/Elements_Text.lua` | `NS.Elements.Text`: the band label element |
| `modules/Elements_Indicator.lua` | `NS.Elements.Indicator`: the shapes (this addon's art), the bar (LibKa0s-Widgets' `W.Bar`) and the spell icon |
| `modules/Elements_Spells.lua` | `NS.Elements.Spells`: the spell chips, pooled per element, colored by each spell's own answer |
| `modules/Container.lua` | `NS.Container`: the renderer: one pooled instance per enabled container (`Acquire`, `Get`, `ForEach`, `Sync`, `Repaint`, `UnitChanged`, `RefreshVisibility`, `SetPreview`, `StandDown`; `inst:Render`, `inst:Update`, `inst:PollSpells`, `inst:Release`, `inst:SetAnchorHidden`) and one per plate for a `nameplates` container (`AcquirePlate`, `GetPlate`, `ReleasePlate`, `ForEachPlate`), the `RANGE_UPDATED` fan-out by unit, the spell chips' steady re-ask, the visibility and band-sound calls, the preview's stand-ins and TestStrips |
| `modules/Anchors.lua` | `NS.Anchors`: the dispatcher (`Apply`, `Detach`, `Refresh`, `ShownChanged`, `UnitChanged`, `FlushDeferred`, `RefreshLock`, `StandDown`), the mode registry and the point and offset readers. LOAD-BEARING: before the mode files |
| `modules/FrameProviders.lua` | `NS.FrameProviders`: the `blizzard`, `ellesmere` and `custom` frame names per unit (`NameFor`) and the guarded global lookup (`Resolve`, `Lookup`) |
| `modules/Anchors_Screen.lua` | The `screen` mode (`NS.Anchors.Screen`): the stored point on `UIParent`, LibKa0s-Widgets' drag strip (name, settings mark, close mark) on every container instance but a per-plate one while unlocked (`Track`, `Untrack`, `RefreshLock`), a drag saved through `NS.CM.SetPosition` |
| `modules/Anchors_Frame.lua` | The `frame` mode (`NS.Anchors.Frame`): a unit frame from the providers, a missing one hidden and retried, a write held through combat, mouseover to the cursor |
| `modules/Anchors_Nameplate.lua` | `NS.Plates`, the plate registry (`Get`, `ForEachHostile`, `Added`, `Removed`, `SyncAll`, the one-frame re-check), and the `nameplate` (own plate) and `plates` (per-plate instance) modes |
| `modules/Anchors_Cursor.lua` | The `cursor` mode (`NS.Anchors.Cursor`): one shared OnUpdate for every cursor container, armed only while one is shown |
| `modules/Anchors_Mockplate.lua` | The `mockplate` mode (`NS.Anchors.Mockplate`): unlocked out of combat, a container on a nameplate waits at its screen point beside a stand-in plate placed by its `nameplate` point and offsets (`Rect`, `Relaid`, `PLATE`) |
| `modules/FramePicker.lua` | `NS.FramePicker`: the pick-on-screen overlay, Enter picks and Escape cancels (`Start`, `Stop`, `Cancel`, `IsActive`, `NamedAncestor`), refused in and ended by combat |
| `modules/Visibility.lua` | `NS.Visibility`: `Evaluate(container, unit, state?) -> shown, alpha` (General visibility, the combat, no-unit and reaction rules, Master opacity times `oocAlpha`), the combat edge's flag (`SetCombat`, `InCombat`) |
| `modules/Sounds.lua` | `NS.Sounds`: `OnBand(inst, band, now)` (the 0.2 s settle, the 1 s gap, the silent first band, per-instance state), `Reset`, `Wants` (never a `nameplates` container), `BUILTIN` (the out-of-range chime, registered with LibSharedMedia at load) |
| `modules/Sim.lua` | `NS.Sim`: Sim mode's 0 to 50 to 0 yd sweep on LibKa0s-Sim-1.0 (an empty seam, the session, its step panel), `Source`, `IsRunning`, `RunVerb` (`/rm sim <verb>`), `SetSimMode` through the one writer |
| `modules/Preview.lua` | `NS.Preview`: what Test mode draws (the `20–25` placeholder), `Kind` (Sim wins), `Refresh`, the one caller of `NS.Range.SetSource` and `NS.Container.SetPreview`; `SetTestMode` through the one writer |
| `modules/Diagnostics.lua` | The `/rm diagnostics` report's sections |
| `settings/Schema.lua` | `LibKa0s-Schema-1.0` instance and its runtime-completing stub: `NS.SetByPath`, `NS.FindSchemaRow`, `NS.ApplyDefault`, `NS.SchemaForPage`, `NS.ValidateSchema`; the selection-relative paths (`NS.SelectedContainer`, `NS.SelectedBandSet`, `NS.SelectContainer`, `NS.SelectBandSet`, `NS.NeighborAfterDelete`, `NS.StampSelectionRows`). LOAD-BEARING |
| `settings/Slash.lua` | `NS.COMMANDS` and the `LibKa0s-Slash-1.0` descriptor. LOAD-BEARING |
| `settings/OptionsSetup.lua` | `LibKa0s-Options-1.0`: `NS.Helpers`, eager category registration, the reset vetoes. LOAD-BEARING |
| `settings/About.lua` | The landing page's spec, drawn by `BuildLandingPage` |
| `settings/General.lua` | The General page: Master controls (composed; the `locked` row shows the screen drag strips), the Presets tab and the Skin tab |
| `settings/Containers.lua` | The Containers page: the banner (picker, New container), the nav rail (`NS.RegisterContainerSection`), the General entry's rows (identity, band sets, Position) and acts (Duplicate, Delete, Copy settings from, Pick on screen); `NS.ContainerValues`, `NS.RequestPanelRefresh`, `NS.ShowContainer`, `NS.NewContainer`, `NS.DeleteContainer`, `NS.PickFrameForSelected`, `NS.BandRibbon` (the `/rm bands` chat line). LOAD-BEARING: before the entry files |
| `settings/Containers_Display.lua` | The Display entry: Layout (and the Element order drag list, `NS.CancelElementOrder`), Frame (the composed border block with Border opacity, the background pair), Number and Text (each the composed Font block), Label (the `container.label.*` caption rows and their composed Font block), Dot (its color pair composed, and the Style tiles, `NS.ReleaseStyleTiles`) and Spell chips |
| `settings/Containers_Visibility.lua` | The Visibility entry: the combat, reaction and no-unit rules and the out-of-combat opacity |
| `settings/Containers_Sounds.lua` | The Sounds entry: whether band sounds play, and the channel; not on the rail for a `nameplates` container |
| `settings/BandSets.lua` | The Band sets page: the banner (picker, New band set), General (`bandSet.*` rows and the acts) and the Bands host editor; `NS.ShowBandSet`, `NS.DeleteBandSet` |
| `settings/Presets.lua` | The General page's Presets tab (`NS.PRESETS_TAB`), `NS.ConfirmPreset`, `NS.ApplyPresetNow`, `NS.UndoPreset`, the preset picker window (`NS.MaybeShowPresetPicker`, `NS.ShowPresetPicker`, `NS.HidePresetPicker`, `NS.PresetPickerCombat`) and `NS.OpenGeneralTab` |
| `settings/Profiles.lua` | The Profiles sub-page (AceDBOptions) |

## LibKa0s modules: wired and vendored

Wired, one setup file each: Core, Env, Compat, Media, Skin, Bus, Lifecycle, Perf, DebugLog, Launcher,
Schema (in `settings/Schema.lua`), Slash, Options, Pool (`core/PoolSetup.lua`: the container
instances and the spell chips). Widgets is read where it is drawn, as the library's optional
widgets are: `W.Bar` for the bar indicator (`modules/Elements_Indicator.lua`, a flat strip without
it), the drag strip on unlocked screen containers (`modules/Anchors_Screen.lua`) and the TestStrip a
container wears in Test mode and Sim mode (`modules/Container.lua`). Sim is wired in
`modules/Sim.lua` (Sim mode's sweep, on an empty seam). Vendored but not yet wired (normal: adoption
is per module): Tooltip, Role, Item, Glow, Callout, Charts, IconBrowser, Toast and WaypointArrow.

## Media

`media/logos/` (the addon logo, layout-§4) and `media/textures/indicators/` (the indicator art:
`<shape>_<style>` for the shapes `dot`, `ring`, `square`, `diamond`, `triangle`, `hexagon`, `star` and
the styles `plain`, `matte`, `glossy`, `glowing`, `neon`, `gem`, each a white 128x128 uncompressed
32-bit TGA tinted at draw time, drawn by `tools/indicator_art.py`; plain, matte, glossy and gem fill
the box as the v0.1.0 single-file art did (the dot 87.5%), glowing and neon draw a smaller core (about
70%) so their halo fits; `tests/test_container_render.lua` checks the headers and the fill).

## Tests

`tests/run.lua` (the load list, the lifecycle kick and the suite list), `tests/wow_mock.lua` (a thin
extender over the kit's base mock), `tests/degraded_env.lua` (a second environment with LibKa0s
absent), `tests/mock_menu.lua` (the context-menu stand-in), `tests/anchors_env.lua` (the four anchor suites' shared harness), `tests/settings_env.lua` (the
settings suites' shared harness), `tests/perf.lua` (offline scenarios,
outside the gate), `tests/client_globals_allow.lua` (the kit gate's allowlist) and one
`tests/test_*.lua` per seam. `tests/_kit/` is vendored and never edited.
