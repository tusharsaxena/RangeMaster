# Architecture — Ka0s Range Master

The engineer's hub for this addon. Each mandated section summarizes and links out; the detail lives
in the topic docs registered under [Documentation map](#documentation-map) (documentation-§3).

## Overview

Ka0s Range Master draws player-built range **containers**: one unit each (`target`, `focus`, `pet`,
`mouseover`, or every enemy nameplate), showing a range bracket as a number, a band label, an
indicator and a row of spell chips, with an optional caption naming it, colored by a shared **band set**. The design and the plan of
record are `docs/superpowers/specs/2026-11-18-rangemaster-design.md` and
`docs/superpowers/plans/2026-11-18-rangemaster-v0.1.0.md`.

**State of the tree: v0.1.0 as built, plan Tasks 1 to 8.** The born-compliant shell every Ka0s
addon shares (the Ace3 addon object, AceDB with its migration runner, the LibKa0s setup files, the
slash surface, the launcher, the stand-down latch and the diagnostics report), and on it the range
engine, the band sets, the container registry and its presets, the renderer, the four anchor modes,
the visibility and sound rules, Test mode and Sim mode, and the settings pages (General with its
Presets tab, Containers, Band sets, Profiles). The addon has not been run in a client yet: every
in-game check in `docs/smoke-tests.md` is still owed.

**The design is dictated by one client fact.** The game answers "is this unit within reach of
spell or item X", never "how far". The range engine asks LibRangeCheck-3.0 (vendored,
`libs/LibRangeCheck-3.0/`) for the narrowest bracket those answers allow, behind `pcall` and an
`issecretvalue` check (`NS.Compat.IsSecret`), and one shared ticker publishes `RANGE_UPDATED` on
change. A secret or failed answer reads as *unknown*, never as out of range.

### The components

| Component | Files | What it does |
|---|---|---|
| Range engine | `modules/Range.lua` (`NS.Range`), `modules/Ticker.lua` (`NS.Ticker`), `core/Compat.lua` | A guarded, memoized bracket per unit token per tick; one adaptive ticker that sends `RANGE_UPDATED` on change |
| Band sets | `modules/BandSets.lua` (`NS.BandSets`), `defaults/BandSetPresets.lua` | Named, shared, normalized bands of yards, each of which may carry a spell, dead-zone or beyond rule (its yards then the fallback); `Resolve` turns a bracket into a band, `ForUnit` picks the friendly override |
| Containers and presets | `modules/ContainerManager.lua` (`NS.CM`), `modules/Presets.lua` (`NS.Presets`) | The container registry's one writer and its coalesced, combat-held apply; Simple, Intermediate (Range Text), Intermediate (Range Numbers), Advanced and Expert, with a one-level Undo |
| Rendering | `modules/Container.lua` (`NS.Container`), `modules/Style.lua`, `modules/Elements_*.lua` | One pooled instance per enabled container (one per plate for `nameplates`), repainted only on a band or text change |
| Anchors | `modules/Anchors.lua` (`NS.Anchors`), `modules/Anchors_*.lua`, `modules/FrameProviders.lua`, `modules/FramePicker.lua` | Free on screen, on a unit frame, on a nameplate (own plate or every plate), at the cursor |
| Behavior and modes | `modules/Visibility.lua`, `modules/Sounds.lua`, `modules/Preview.lua`, `modules/Sim.lua` | The visibility rules, the debounced band sounds, Test mode's placeholder and Sim mode's distance sweep |
| Settings | `settings/*.lua` | The schema runtime, the slash descriptor and the pages (below, and `docs/settings-panel.md`) |

How each one works, its seams and its edge cases: `docs/data-flow.md`, *Components*.

### Libraries

Everything is vendored under `libs/`: LibStub and CallbackHandler, the Ace3 stack, LibSharedMedia,
LibDataBroker and LibDBIcon (the launcher), LibKa0s v1.106.0 (whole, its icons and sounds pruned to
`CLAUDE.md`'s declarations) and LibRangeCheck-3.0 MINOR 39 (commit and source in root
`DEPENDENCIES.md`). Which LibKa0s modules are wired, one setup file each: `docs/module-map.md`.

## Module Map

Every non-vendored file, its responsibility and the TOC load order: `docs/module-map.md`. In short:
`locales/enUS.lua` first; `core/` holds the namespace, the compat seam, the LibKa0s setup files,
the stand-down latch, the database and the AceAddon entry (`core/RangeMaster.lua`); `defaults/`
the AceDB defaults, the templates and the data tables; `modules/` the band sets, the range engine
and its ticker, the container registry and presets, the renderer with its style and element files,
and the diagnostics sections; `settings/` the schema runtime, the slash
descriptor, the options descriptor and the pages (General with its Presets tab, Containers with
its rail entries General, Display, Visibility and Sounds, Band sets, Profiles).

### Per-client features

All features serve both clients. The client is asked only through `core/Compat.lua`'s routing of
`LibKa0s-Compat-1.0` (clients-§3); no file reads a `WOW_PROJECT_*` global or decides the client from
an interface number (`tests/test_compat.lua` pins that). What differs per client is data, picked by
`NS.Compat.ClientKey()` at call time (clients-§5): the range ladder (`core/Compat.lua`, Forever only:
items and interact distances; spells on both) and the spell seeds (`defaults/SpellSeeds.lua`, keyed
`[client][classFile]`; Forever has no Death Knight, Monk, Demon Hunter or Evoker). Forever's
`PLAYER_FOCUS_CHANGED` is registered only where `NS.Compat.IsEventValid` says the client knows it.

**How the seed lists are maintained (clients-§10).** Neither per-client list in
`defaults/SpellSeeds.lua` is derived from the client's DB2 yet. Each is hand-kept: a short list per
class of long-stable spell IDs (rank 1 on Forever), and each ID is checked in a client by
`docs/smoke-tests.md` RANGE-5 (every seed resolves on its own client). A stale ID cannot report a
wrong range: the range engine trusts a spell only while it is known and usable, so an ID the client
does not know is skipped. The first re-validation against wago.tools
(`SpellName` and `SpellRange` at a pinned `wow` and `wowf` build) freezes its run as a dated bundle
under `docs/`, and this paragraph then points at it.

## Settings Schema

One schema row per setting, `NS.Schema`, driving the panel, the slash CLI and the resets through one
write seam, `NS.SetByPath` (architecture-§5), on `LibKa0s-Schema-1.0` (`settings/Schema.lua`). The
rows are the composed Master controls (`settings/General.lua`), the Skin tab's skip-render rows, the
Containers page's `container.<field>` rows (`settings/Containers*.lua`) and the Band sets page's
`bandSet.<field>` rows (`settings/BandSets.lua`). The full shape, every default and the migration
path: `docs/schema.md`.

**Selection-relative paths.** A container or band set is made at runtime, so no row names one by id:
`container.<field>` means the SELECTED container's field and `bandSet.<field>` the selected band
set's (design spec 5.6). The selection is session state (`NS.State.selectedContainer`,
`selectedBandSet`), written only by `NS.SelectContainer` / `NS.SelectBandSet` (the page banners,
`/rm select`, `/rm bands`); an unset or stale selection reads the first in order. `NS.StampSelectionRows`
gives each such row its own `get`, `set` and `validate`: the set hands the value to the registry's
writer (`NS.CM.SetField` / `Rename`, `NS.BandSets.SetField` / `Rename`), never a raw store at a path,
so the panel, `/rm set` and every reset take one route (`tests/test_settings_containers.lua` spies
both writers over every row). The default is the registry template's; a field the template leaves
nil declares `nilAs` (0 for "no band set"), and one stored as `""` declares `emptyAs` (`Skin`,
`Solid`), because the CLI cannot type an empty value. `NS.ValidateSchema` resolves each path against
its template. A delete re-selects the deleted item's neighbor (`NS.NeighborAfterDelete`).

**Structural registries.** Two, both in the profile, with one load pass between them,
`core/Database.lua`'s `Database.PrepareProfile` (called from `NS:RunMigrations`, so only from
`InitDB` and the three AceDB profile callbacks): it re-keys and backfills every member from its
template, rebuilds each order array, bumps each counter past the highest stored id, normalizes every
band set, seeds the four preset band sets on a profile with none, points a container at the default
set when its `bandSet` names none, and sets `seeded` to `false` when absent.

- **Band sets**: `bandSets`, `bandSetOrder`, `nextBandSetId`. Runtime writer `modules/BandSets.lua`
  (`Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `SetBandSound`, `SetBandRule`, `RestoreSnapshot`); its
  seed routine `BandSets.Seed` and its
  per-set repair `BandSets.NormalizeSet` are shared with the load pass, and its v1 -> v2 conversion
  `BandSets.ConvertSet` with the migration ladder (`docs/schema.md`). `Delete` also moves the
  `bandSet` / `bandSetFriendly` references of the containers that used the deleted set, through the
  container registry's writer `NS.CM.SetField` (architecture-§5). The Band
  sets page writes through `SetField` (match rule, unknown label and color), `SetBand` (an edge, a
  label, a color; an edge that would leave a band without width is refused), `AddBand` and
  `RemoveBand`, each normalizing after the write, and `SetBandRule` (a band's rule: Defined by, Role,
  Spell IDs), which touches no edge and so normalizes nothing.
- **Containers**: `containers`, `containerOrder`, `nextContainerId`, and the first-run sentinel
  `seeded`. Runtime writer `modules/ContainerManager.lua` (`NS.CM`: `Create`, `Delete`, `Duplicate`,
  `Rename`, `CopySettings`, `Clear`, `RestoreSnapshot`, `SetField` for one dotted field, which
  the `container.*` rows reach, and `MarkSeeded` for `seeded`, which `NS.Presets.MarkPickerSeen`
  calls), whose apply a profile switch, copy or reset also requests.

The member shapes are `NS.CONTAINER_TEMPLATE`, `NS.BANDSET_TEMPLATE` and `NS.BAND_TEMPLATE`
(`defaults/Profile.lua`); the keys are bookkeeping with no schema row, so none is an AceDB default.
Detail: `docs/schema.md`.

**Named non-setting state.** `global.minimap` is LibDBIcon's own table (its `hide` and its saved
angle); the owner is `core/LauncherSetup.lua`, and its writers are LibDBIcon itself and
`NS.SetMinimapShown` (`core/Data.lua`), which the `global.minimap.shown` row's `set` calls.
`global.skinNotice` is the one-time skin notice's record, written by `NS.MaybeShowSkinNotice`
(`core/SkinSetup.lua`) through the library's store. Session-only state (`NS.State.debug`,
`testMode`, `simMode`, `rejectedEvents`) is never persisted (`core/State.lua`).

## Message Bus

Five messages, declared once in `core/Bus.lua` through `LibKa0s-Bus-1.0`'s strict `Catalog`; every
receiver registers on its own `NS.NewBusTarget()` (architecture-§4), and the targets are tracked so a
stand-down takes every subscription down and a stand-up replays it.

| Constant | Wire name | Sender | Payload | Consumers |
|---|---|---|---|---|
| `RANGE_UPDATED` | `Ka0s_RangeMaster_RangeUpdated` | `modules/Ticker.lua` | `unit, state, minYd, maxYd` | `modules/Container.lua`: the instances watching that unit |
| `CONTAINERS_CHANGED` | `Ka0s_RangeMaster_ContainersChanged` | `modules/ContainerManager.lua` (`FlushPending`, coalesced to the next frame, held in combat) | none | the renderer (`NS.Container.Sync`) |
| `BANDSETS_CHANGED` | `Ka0s_RangeMaster_BandSetsChanged` | `modules/BandSets.lua` (every writer: `Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `SetField`, `SetBand`, `AddBand`, `RemoveBand`, `SetBandSound`, `SetBandRule`, `RestoreSnapshot`; never the load pass) | none | the renderer (`Repaint`) and `settings/BandSets.lua` (a redraw of the pages, coalesced to the next frame) |
| `ANCHORS_CHANGED` | `Ka0s_RangeMaster_AnchorsChanged` | `modules/Range.lua` (the debounced rebuild, only when a band rule's resolved anchor spell, its reported range, or the anchor a druid's form puts in use moved) | none | the renderer (`Repaint`); the Band sets page (`settings/BandSets.lua`, a redraw for the spell bands' read-out) |
| `MODE_CHANGED` | `Ka0s_RangeMaster_ModeChanged` | `core/RangeMaster.lua` (`NS.SetTestMode`, `NS.SetSimMode`) | `mode` (`"test"` or `"sim"`), `on`, `why` | `modules/Preview.lua` (what the displays draw) and `modules/Sim.lua` (starts or stops the sweep) |

Ten or fewer messages, so `docs/message-bus.md` is not required; this table is the register.

## Slash Commands

`/rm` and `/rangemaster`, dispatched by `LibKa0s-Slash-1.0` over `NS.COMMANDS` (`settings/Slash.lua`):
`help`, `config`, `skin`, `enable`, `disable`, `list`, `get`, `set`, `reset`, `resetall`, `profile`,
`lock`, `unlock`, `resetposition`, `containers`, `select`, `new`, `delete`, `pick`, `bands`,
`preset`, `test`, `sim`, `debug`, `diagnostics`, `perf`, `version`. A bare
`/rm` opens the settings panel. While the addon is disabled the reserved verbs, the schema CLI,
`diagnostics` and `profile` keep answering, and the feature verbs refuse on the collection's one line.
Under a performance capture's `perf` hold alone a feature verb answers `Not available during a
performance capture.` instead; `NS.RefusalLine()` (`core/LifecycleSetup.lua`) picks the line by hold.
Each verb, its arguments and its refusals: `docs/slash-dispatch.md`.

## Event Subscriptions

`core/RangeMaster.lua` registers its events from one list (`NS.__lifecycleEvents`), each through
`NS.SafeRegisterEvent` (events-frames-taint-§1), only while the addon stands up:

| Event | Handler | Why |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `addon:OnEnterWorld` | a traced world-entry edge; `NS.Anchors.Frame.Retry` (EllesmereUI spawns its unit frames at `PLAYER_LOGIN`) |
| `PLAYER_REGEN_DISABLED` | `addon:OnCombatChanged` | combat ends Test mode, Sim mode and a frame pick, the range ticker goes to 20 Hz, and every container's visibility is asked again (bracketed `combatEdge`) |
| `PLAYER_REGEN_ENABLED` | `addon:OnCombatChanged` | the leave edge; the ticker back to 10 Hz, every container's visibility asked again, and a container apply combat held runs (`NS.CM.FlushPending("regen")`), then every anchor write onto a unit frame combat held (`NS.Anchors.FlushDeferred`) |
| `PLAYER_TARGET_CHANGED` | `addon:OnUnitChanged` | a unit change on `"target"`: `NS.Container.UnitChanged`, then `NS.Anchors.UnitChanged` (an own-plate container moves to the new unit's plate, and a plate token's eligibility for the `nameplates` containers is asked again), then `NS.Ticker.Changed` |
| `PLAYER_FOCUS_CHANGED` | `addon:OnUnitChanged` | the same on `"focus"`; registered only where `NS.Compat.IsEventValid` knows it (`ifValid`) |
| `UPDATE_MOUSEOVER_UNIT` | `addon:OnUnitChanged` | the same on `"mouseover"` |
| `UNIT_PET` | `addon:OnPetChanged` | the same on `"pet"`, for the player's own pet only, and `NS.Range.Rebuild()` |
| `NAME_PLATE_UNIT_ADDED` | `addon:OnNamePlateChanged` | `NS.Plates.Added(token)` (the plate tracked, its instances built, a re-check a frame later), then the same unit change on the plate's token |
| `UNIT_FACTION` | `addon:OnUnitFaction` | the same on the unit named, a reaction change (the band set follows `bandSetFriendly`, and `NS.Anchors.UnitChanged` moves a plate into or out of a hostile-only `nameplates` container); `ifValid` |
| `NAME_PLATE_UNIT_REMOVED` | `addon:OnNamePlateChanged` | `NS.Plates.Removed(token)` (its instances parked, an own-plate container on that plate frame hidden), then `NS.Ticker.Removed(token)`: `"none"` is sent outright, because the client still resolves the token while this event dispatches and a re-read would see the plate as live |
| `SPELLS_CHANGED` | `addon:OnSpellsChanged` | `NS.Range.Rebuild()`, debounced 0.5 s: the known-spell cache is taken again, the ladder dropped (rebuilt on the next Forever walk; Retail builds none), and the band rules' anchors resolved again (`ANCHORS_CHANGED` when they moved) |
| `CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED`, `ACTIVE_TALENT_GROUP_CHANGED`, `PLAYER_SPECIALIZATION_CHANGED`, `LEARNED_SPELL_IN_SKILL_LINE`, `PLAYER_LEVEL_UP`, `UPDATE_SHAPESHIFT_FORM`, `PLAYER_EQUIPMENT_CHANGED` | `addon:OnSpellsChanged` | the same rebuild: a talent, a spec, a new rank or level, a form or gear can move an anchor or its range; each `ifValid`, and `CHARACTER_POINTS_CHANGED` is never filtered on its count |
| `CVAR_UPDATE` | `addon:OnCVarUpdate` | the same rebuild, for `ShowAllSpellRanks` only (it changes what a spell name resolves to); `ifValid` |
| `ADDON_LOADED` | `addon:OnAddonLoaded` | `NS.Anchors.Frame.Retry`: a unit frame a container waits for may exist now |

LibRangeCheck-3.0's `CHECKERS_CHANGED` callback (`addon:OnCheckersChanged`, the same rebuild) is
subscribed with the events and dropped with them (`addon:SubscribeRangeLibrary`, under `pcall`, only
where the library offers its CallbackHandler surface).

The ticker itself is a `C_Timer.NewTicker`, not an event; the stand-down cancels it with the pending
rebuild, which stays owed: a `Rebuild` asked while stood down arms nothing, and the stand-up runs an
owed rebuild at once (`NS.Range.RunOwedRebuild`). The skin picker holds one `PLAYER_REGEN_ENABLED`
target of its own while a first-run show waits out combat, and the one-time skin notice holds another
while it is owed through combat (`core/SkinSetup.lua`); the stand-down drops both.

## Taint Notes

The addon hooks nothing, and every frame it draws is its own, plain and unprotected: the renderer's
container instances are `CreateFrame("Frame")` children of `UIParent`, built only on an apply, which
the container registry holds through combat (`NS.CM.FlushPending` runs it on `PLAYER_REGEN_ENABLED`;
the skin's re-apply goes through `NS.CM.RequestApply` too); a render inside combat only recolors and
re-texts frames that already exist. A Solid edge is four strips of this addon's own and reads no
size. A LibSharedMedia edge goes on a plain host frame with `BackdropTemplateMixin` mixed in and the
template's `OnSizeChanged` wiring (`OnBackdropSizeChanged`), so the edge is re-tiled each time the
layout sizes the root; the mixin reads the host's size, which is this addon's own, set from plain
numbers, never a secret geometry. The rules the range work is built to: every
range API call is wrapped in `pcall` and every result checked with `NS.Compat.IsSecret` before it is
compared (`core/Compat.lua`'s range reads, `modules/Range.lua`'s LibRangeCheck call); item and
interact checks are never made on a unit the player cannot attack while in combat; no
`SetPoint` or `SetParent` on a frame anchored to a secure frame in combat (queued for
`PLAYER_REGEN_ENABLED`); the options panel refuses to open in combat and a page shown in combat is
covered by the library's lock (options-ui-§2). Preview modes end on `PLAYER_REGEN_DISABLED`, while
secure writes are still allowed.

The anchors keep the same rules. A container is never re-parented: it stays a child of `UIParent` and
is only anchored (`SetPoint`) to a unit frame, a nameplate or the screen. An anchor onto a unit frame
(a secure frame) is never written in combat (`modules/Anchors_Frame.lua` holds it for
`PLAYER_REGEN_ENABLED`). A nameplate is no secure frame and plates come and go in combat, so the
plate instances are built, placed and parked there (the one instance work done in combat), and the
cursor follow places its own frames every frame. A forbidden plate or frame is never called: every
plate comes through `NS.Compat`'s reads, which ask `IsForbidden` first under `pcall`, and the frame
providers and the frame picker do the same. A frame that refuses the anchor (`SetPoint` raises) is
treated as missing. The frame picker toggles keyboard propagation only out of combat, and is
refused in and ended by combat. The combat edge's visibility pass only shows, hides and fades this
addon's own frames (never a `SetPoint`); the preview modes' stand-ins and screen-point fallbacks are
placed out of combat, because both modes are refused in it and ended at its start.

A region anchored to a nameplate cannot be measured: the client raises *Can't measure restricted
regions* on `GetTop` and its kin. Nothing in this addon measures a container root. LibKa0s-Widgets'
HUD-docked TestStrip measures its target to flip near the screen's top, and from Widgets minor 28
(LibKa0s v1.106.0, RangeMaster#17) every such read is guarded, so a strip docked on a root riding a
plate sits on its top edge, unflipped, and raises nothing. The nameplate anchors clear a root's
points when it leaves its plate, so `inst.anchorPlate` always says whether the root's points name
one. The unlocked preview nameplate (`modules/Anchors_Mockplate.lua`) is this addon's own frame,
never a real plate, and nothing measures it.

## Known Limitations

- Two container fields have no settings row: the spell
  chips' list (`elements.spells.list`, stored empty on create; while it is empty the chips show the
  logged-in character's class seeds for this client, resolved at render time by `NS.CM.SpellChips`,
  so an alt of another class on the shared Default profile sees its own spells) and the icon
  indicator's spell (`elements.indicator.spellID`, nil = the first chip). They keep their stored
  values and are copied by Duplicate and Copy settings from.
- A band's own fields (its edge, label, three colors, sound and rule) and Add band / Remove band are the
  Band sets page's Bands editor only: a band is one of a list the player grows, which no schema path
  can name, so `/rm get|set` reaches a band set's name, match rule and unknown label and color, not
  its bands (design spec 5.6 records this).
- The preset picker (a window shaped as AuraMaster's: a dropdown, each pick previewed on the real
  screen in test mode, Apply / Not now) has no style switch and no Empty preset, which this addon's
  presets do not have; a disabled addon that is enabled later is not offered it on first run.
- Sim mode's sweep moves every container through one simulated distance; it does not simulate a
  unit's reaction, class or existence.
- A container on a nameplate is anchored to the plate but stays a child of `UIParent`: it does not
  take the plate's scale or fade, and it draws in the HUD strata over the plates.
- Without LibKa0s-Widgets-1.0 the bar indicator draws as a flat strip in the band color, not a fill.
- The built-in out-of-range chime is a stock game sound by file id (567397, the raid warning); it is
  not yet heard on WoW Forever (`docs/smoke-tests.md`, SOUND-1).
- On a load where LibKa0s is missing, the bus's degraded stub keeps no stand-down record, so a disable
  leaves bus subscriptions live there (the untracked-target stub, `core/Bus.lua`).
- A unit LibRangeCheck will not measure because the client does not draw it (`UnitIsVisible` false)
  reads *unknown*, not out of range: the engine never guesses a distance it was not given.
- Forever's interact rungs (duel 10 yd, follow 28 yd, race-adjusted) and both clients' seed spell IDs
  (`defaults/SpellSeeds.lua`) are not yet confirmed in a client; `docs/smoke-tests.md` carries the
  checks.

## Documentation map

Every `.md` under `docs/` appears in exactly one table below (documentation-§3). Frozen and
generated directories are named once and never enumerated: `docs/audits/`, `docs/reviews/`,
`docs/automated-tests/<run>/`, `docs/perf-analysis/<run>/`, `docs/revendor/<date>-v<tag>/`,
`docs/superpowers/`.

### Required (documentation-§3, Tier 1)

| Doc | Covers |
|---|---|
| `scope.md` | What the addon does, and what it deliberately does not |
| `module-map.md` | Every non-vendored file, its one-line responsibility, and the TOC load order and why; the vendored libraries and which LibKa0s modules are wired |
| `schema.md` | The profile and global SavedVariables shape, every default, the migration path |
| `settings-panel.md` | The `Page \| Covers` table, the page → tab → row tree, per-option behavior and schema keys; the launcher |
| `data-flow.md` | The pipeline: events and settings in, the latch and the modes, what the player sees |
| `common-tasks.md` | Recipes for the changes made most often here, naming real files |

### Conditional (documentation-§3, Tier 2)

| Doc | Status | Trigger |
|---|---|---|
| `perf-analysis/README.md` | Present | The performance harness is wired (`core/PerfSetup.lua`) |
| `slash-dispatch.md` | Present | 27 commands in `NS.COMMANDS` as measured on 2026-11-18, over the eight-or-more threshold |
| `midnight-quirks.md` | Present | Always (documentation-§3): the vendored `client-quirks` catalog block, then the addon's own section |
| `compat-layer.md` | Present | `core/Compat.lua` publishes the range reads, the two band-set unit reads, the anchors' four frame reads, the band rules' three anchor reads and the per-client ladder, 21 shims by documentation-§3's count as measured on 2026-11-19, seventeen of them addon-specific beyond what LibKa0s supplies, over the three-or-more threshold |
| `message-bus.md` | Not applicable | 5 messages in `NS.MSG` as measured on 2026-11-19 (`RANGE_UPDATED`, `CONTAINERS_CHANGED`, `BANDSETS_CHANGED`, `ANCHORS_CHANGED`, `MODE_CHANGED`); the trigger is more than ten. The table lives in `## Message Bus` above |
| `profiles.md` | Present | AceDB profiles are user-visible: the Profiles sub-page is a profile control in the options UI |
| `known-limitations.md` | Not applicable | `## Known Limitations` above is under ~60 lines |
| `taint.md` | Not applicable | `## Taint Notes` above is under ~60 lines |
| `debug.md` | Present | `/rm diagnostics` (or `/rm debug diagnostics`), the report `modules/Diagnostics.lua` writes to the console |

### Verification and record (documentation-§3)

| Doc | Covers |
|---|---|
| `testing.md` | How to run the harness and lint; the green commit gate; the four suites and their checkpoints |
| `smoke-tests.md` | The in-game smoke-test suite |
| `test-cases.md` | The generated case inventory (authoritative pass count) |
| `performance.md` | The addon performance page |
| `automated-tests/README.md` | What the automated-test record is and how to produce it |
| `automated-tests/RESULTS.md` | One row per run; generated by the runner, never hand-edited apart from the watch list's `Disposition` column (automated-tests-§4) |

### Addon-specific (documentation-§3, Tier 3)

None yet.

## Documented deviations

None.

### Files over the 1500-line cap

Nothing is over the cap today; the census is measured by tests/_kit/test_layout_cap.lua.
