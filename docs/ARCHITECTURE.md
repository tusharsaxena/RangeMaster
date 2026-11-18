# Architecture — Ka0s Range Master

The engineer's hub for this addon. Each mandated section summarizes and links out; the detail lives
in the topic docs registered under [Documentation map](#documentation-map) (documentation-§3).

## Overview

Ka0s Range Master draws player-built range **containers**: one unit each (`target`, `focus`, `pet`,
`mouseover`, or every enemy nameplate), showing a range bracket as a number, a band label, an
indicator and a row of spell chips, colored by a shared **band set**. The design and the plan of
record are `docs/superpowers/specs/2026-11-18-rangemaster-design.md` and
`docs/superpowers/plans/2026-11-18-rangemaster-v0.1.0.md`.

**State of the tree: the scaffold, the range engine, the data model, the container registry, the renderer and the anchors (plan Tasks 1 to 6).** What exists is the
born-compliant shell every Ka0s addon shares (the Ace3 addon object, AceDB with its migration runner,
the LibKa0s setup files, the Master controls and Skin tabs, the slash surface, the launcher, the
stand-down latch, the diagnostics report, and the two session preview modes with their one writer
each), plus the range engine: `modules/Range.lua` (`NS.Range`), `modules/Ticker.lua` (`NS.Ticker`,
the one ticker and the sender of `RANGE_UPDATED`), the range reads and the per-client ladder in
`core/Compat.lua`, and the per-client spell seeds in `defaults/SpellSeeds.lua`; plus the data model:
the container and band-set templates (`defaults/Profile.lua`), the four preset band sets
(`defaults/BandSetPresets.lua`), the band-set registry and its resolver (`modules/BandSets.lua`) and
the registries' load pass (`core/Database.lua`'s `PrepareProfile`); plus the container registry's
writer (`modules/ContainerManager.lua`, `NS.CM`) and the three container presets
(`modules/Presets.lua`, `NS.Presets`); plus the renderer (`modules/Container.lua`, `NS.Container`,
with `modules/Style.lua` and the four `modules/Elements_*.lua`); plus the anchors
(`modules/Anchors.lua` and its four mode files, `modules/FrameProviders.lua`,
`modules/FramePicker.lua`, `NS.Anchors`, `NS.Plates`), which put each container free on screen, on a
unit frame, on a nameplate or at the cursor. The behavior and modes and the settings pages arrive in
plan Tasks 7 and 8, and each section below says where a later task plugs in.

**The design is dictated by one client fact.** The game answers "is this unit within reach of
spell or item X", never "how far". The range engine asks LibRangeCheck-3.0 (vendored,
`libs/LibRangeCheck-3.0/`) for the narrowest bracket those answers allow, behind `pcall` and an
`issecretvalue` check (`NS.Compat.IsSecret`), and one shared ticker publishes `RANGE_UPDATED` on
change. A secret or failed answer reads as *unknown*, never as out of range.

### The range engine

`NS.Range.Get(unit)` answers `state, minYd, maxYd`: `"none"` (no such unit), `"unknown"` (it exists
and nothing could bound it: no answer, a raise, a secret) or `"known"` (`minYd` a number, `maxYd` a
number or nil for open-ended). It is memoized per tick and keyed by unit token, never by GUID (a GUID
can be secret on 12.x), so N containers on one unit cost one query per tick. On WoW Forever, when
LibRangeCheck answers nothing for a unit that exists, the Compat ladder is walked instead
(`NS.Compat.RangeLadder()`: items at the three reliable yards 20/30/35, the duel and follow interact
distances race-adjusted, known seed spells); in combat on a unit the player cannot attack it asks the
spell rungs only, because the client refuses item and interact checks there. `NS.Range.InSpellRange`
asks `C_Spell.IsSpellInRange` only for a spell the player knows.

`NS.Ticker` holds the watch list (a count per unit token) and the one `C_Timer.NewTicker`: 10 Hz out of
combat, 20 Hz in combat (re-armed on the combat edge), stopped while no watched unit exists and
restarted by the event that brings one back. Each tick reads every watched unit once and sends
`RANGE_UPDATED` only for a unit whose triple changed; mouseover, which has no "cleared" event, is
re-read through `UnitExists` every tick. `NS.Ticker.Changed(unit)` is the unit-change read: a
different unit now sits behind the token, so the triple is sent even when it did not move. A read
whose triple did not move reaches the `NS.Ticker.OnSteady` listeners instead (the renderer re-asks
its spell chips there). The stand-down cancels the ticker and the debounced spell
rebuild; the stand-up re-reads and re-announces every watched unit. Pipeline: `docs/data-flow.md`.

### Band sets

A band set is a named, ordered list of yard bands shared by every container that picks it
(`modules/BandSets.lua`, `NS.BandSets`). `Resolve(setId, state, minYd, maxYd)` turns a range triple
into a band index: `"none"` answers nil, `"unknown"` answers `"unknown"` (the set's own label and
gray), `"known"` picks by the far bound (`matchBy = "max"`, a band holds `(from, to]`, an open-ended
bracket reads as infinitely far) or the near one (`"min"`, `[from, to)`). Every stored set is
normalized on each write and on load (sorted, contiguous from 0, last band open-ended, no zero-width
band, at least one band), so `Resolve` is total over [0, infinity). `ForUnit(container, unit)` picks
the container's `bandSetFriendly` when it is set, exists and `NS.Compat.IsFriend` says the unit is
friendly, else its `bandSet`, else the default. The default set is the first in `bandSetOrder`; the
first-run seed puts the class default there (`NS.BandSetPresets.DefaultFor`). Deleting a set moves
every container on it to the named replacement or the default (a friendly override on it falls away
unless a replacement was named), and the last set cannot be deleted. The Hunter preset is two lists,
one per client, picked once at load (clients-§5): WoW Forever's has the 5-8 yd Auto Shot dead zone.

### Containers and presets

`NS.CM` (`modules/ContainerManager.lua`) is the container registry's one runtime writer: `Create(unit?,
opts?)` (a deep copy of the template on the default band set, the class's spell-chip seeds from
`defaults/SpellSeeds.lua`, `opts` merged over it but never over the checked positional unit, a
screen container staggered by id), `Delete`,
`Duplicate` (after its source, `"<name> copy"`, a screen copy offset), `Rename`, `UniqueName`
(`Target`, `Target 2`, case-insensitive), `CopySettings` (never name, enabled, unit or anchor),
`Clear`, and `Snapshot` / `RestoreSnapshot`, which carry both registries, ids included, the band-set
half through `NS.BandSets.Snapshot` / `RestoreSnapshot`. A restore never rewinds either id counter
(each keeps the higher of its own and the snapshot's), so an id is never reused. Every write calls `RequestApply`, which
arms one zero-delay `C_Timer`: a whole preset announces `CONTAINERS_CHANGED` once, on the next frame.
A flush under combat lockdown is held (one debug line) and runs on `PLAYER_REGEN_ENABLED`; a stood-down
addon arms no timer, and the stand-up asks for one apply. A profile switch, copy or reset (the
three AceDB callbacks, `adoptProfile` in `core/RangeMaster.lua`) replaces the registry whole, so it
asks for one apply too.

`NS.Presets.Apply(key)` (`simple`, `intermediate`, `advanced`) snapshots, clears and creates through
`NS.CM`, and answers the snapshot; `Undo` restores it (one level). The Undo slot belongs to the
profile it was taken on: `adoptProfile` calls `ForgetUndo` on a switch, copy or reset. Simple: target, focus, pet and
mouseover free on screen, number and band-colored border. Intermediate: target, focus and pet on their
Blizzard unit frames, mouseover on the cursor, number + text + dot, hidden with no unit, the Healer set
as the friendly override on target, focus and mouseover (reused by name, else created). Advanced:
Intermediate with spell chips on focus and sounds on target (its set's out-of-range band gets
`NS.Presets.OOR_SOUND` through `NS.BandSets.SetBandSound` when it has no sound), plus target on its own nameplate (diamond + number) and
every hostile nameplate (dot + the `max` number), both in combat only. `Describe(key)` feeds the
preset cards (plan Task 8).

### Rendering

`NS.Container` (`modules/Container.lua`) keeps one instance per enabled container, from a
LibKa0s-Pool-1.0 keyed pool (`core/PoolSetup.lua`) keyed by container id. `CONTAINERS_CHANGED` runs
`Sync`: `Acquire(id)` for every enabled container (the pooled frame, its settings applied, its unit
watched through `NS.Ticker.Watch`) and back to the pool for a deleted or disabled one; a release
parks the one object, drops its watch and forgets what it drew. `BANDSETS_CHANGED` repaints every
instance from its last triple, and the skin's `OnLooksChanged` asks for an apply
(`NS.CM.RequestApply`, the next frame and held through combat) so the HUD face follows the skin.
`RANGE_UPDATED` reaches the instances watching that unit and no other (bucket `container.render`);
each asks its spell chips' answers (`NS.Range.InSpellRange`) and renders. A unit change (a retarget,
a new focus, mouseover or pet, a plate token handed to a new plate, `UNIT_FACTION`) runs
`NS.Container.UnitChanged`, which makes the instances on that token forget what they drew, then
`NS.Ticker.Changed`, so the band set is resolved again for the new unit's reaction, the class color
is the new unit's and every chip is asked again, whatever the bracket did. On a read whose triple did
not move (`NS.Ticker.OnSteady`) an instance with chips asks each again and renders only when an
answer moved, because a spell's range edge can fall inside one LibRangeCheck bracket.

A render resolves the band (`NS.BandSets.ForUnit`, then `Resolve`) and recolors the border, the fill
and every element only when the band index or the set changed; an element sets its text only when
the string changed, and the layout runs on an apply or when a cell's width moved. An unknown range
draws the set's unknown label (`?`) in its gray, never a band; no unit hides a container that hides
with no unit. Colors read `band` (the band's frame, text or indicator color), `fixed` (the swatch) or
`class` (the TRACKED unit's class color, the swatch's alpha kept, an unresolvable class falling
through to the swatch; options-ui-§17, because a range container describes its unit; the Task 8
color rows declare `classColorSource = "unit"`). The elements follow
`elements.order` along `layout.direction`, from the padding, `spacing` apart, centered across; only
an enabled element is ever built, and one turned off is hidden. The number writes the bracket in one
of six formats and `40+` for an open-ended one, never an invented far bound. The indicator draws
this addon's shape art (`media/textures/indicators/`), LibKa0s-Widgets' data bar (fuller the nearer
the band, empty when unknown) or a spell icon. The spell chips are an array pool per element, each
chip colored by its own answer and repainted only when that answer moves. Placement is
`NS.Anchors.Apply` (below). A `nameplates` container has no single instance: it owns one per eligible
plate, from a second keyed pool (`AcquirePlate`, `ReleasePlate`, `GetPlate`, `ForEachPlate`), each
watching its plate token; which plates get one is the plate registry's call. Frames stack by
`NS.Constants.LAYERS` (the HUD strata; fill, border and overlay offset over the root).

### Anchors

`NS.Anchors.Apply(inst, container)` (`modules/Anchors.lua`) picks the mode and hands the instance to
that mode's file, detaching the old one first; a mode may hide the instance while what it belongs on
is missing (`inst:SetAnchorHidden`), and the renderer tells the anchors each show and hide
(`ShownChanged`). The five modes:

- **screen** (`modules/Anchors_Screen.lua`): the stored point on `UIParent`. While `locked` is false
  each screen container wears LibKa0s-Widgets' drag strip (`RefreshLock`, from the Master controls'
  `locked` row); a drag ends in `NS.CM.SetPosition`, the registry's own writer, rounded to whole
  pixels, and cannot start in combat. `NS.ResetPositions` (`/rm resetposition`, the Reset position
  button) puts every screen container back at the new-container point (`NS.CM.ResetPosition`).
- **frame** (`modules/Anchors_Frame.lua`): on a unit frame from `NS.FrameProviders`
  (`modules/FrameProviders.lua`): `blizzard` (TargetFrame, FocusFrame, PetFrame), `ellesmere`
  (EllesmereUIUnitFrames_Target, _Focus, _Pet, read as globals, never `EllesmereUIDB`) or `custom` (a
  global frame name, typed or picked). A missing frame hides the container at its screen point with
  one debug line, and is looked for again on `ADDON_LOADED` and `PLAYER_ENTERING_WORLD`. No anchor
  write onto a unit frame happens in combat: it is held and runs on `PLAYER_REGEN_ENABLED`
  (`FlushDeferred`). Mouseover has no frame from either addon, so a mouseover container with no custom
  frame follows the cursor instead.
- **nameplate** (`modules/Anchors_Nameplate.lua`): on the unit's own plate
  (`NS.Plates.Get(unit)`), at the container's `nameplate` point, re-placed on a unit change and on a
  plate coming or going; pet has no plate in practice, so it is hidden.
- **plates**: a `nameplates` container's per-plate instance, on its plate. `NS.Plates` tracks every
  plate token from `NAME_PLATE_UNIT_ADDED` / `_REMOVED`; a plate is hostile through
  `NS.Compat.CanAttack`, and a container with `nameplate.includeFriendly` takes every plate. A plate
  is identified by its frame, never through `UnitIsUnit`: a removed token's plate is compared with
  the frame an own-plate container sits on, which is hidden at once, and looked for again a frame
  later. Every `ADDED` is re-checked one frame later (WoW Forever can announce a plate before it is
  populated). A forbidden plate never comes back from `NS.Compat`'s plate reads, so it is never
  touched.
- **cursor** (`modules/Anchors_Cursor.lua`): one shared driver frame, its `OnUpdate` armed only while
  a cursor container is shown, places each at `GetCursorPosition()` over `UIParent`'s effective
  scale plus the stored offset (bucket `cursor.follow`).

`NS.FramePicker.Start(onPick)` (`modules/FramePicker.lua`) is the custom provider's click-to-pick: an
overlay outlines the nearest named ancestor of the frame under the cursor; left click picks it, right
click or Escape cancels. It is refused in combat and the combat edge cancels one in progress. The
`pick` verb and the panel's button that call it arrive with plan Task 8.

### Libraries

Everything is vendored under `libs/`: LibStub and CallbackHandler, the Ace3 stack, LibSharedMedia,
LibDataBroker and LibDBIcon (the launcher), LibKa0s v1.105.0 (whole, its icons and sounds pruned to
`CLAUDE.md`'s declarations) and LibRangeCheck-3.0 MINOR 39 (commit and source in root
`DEPENDENCIES.md`). Which LibKa0s modules are wired, one setup file each: `docs/module-map.md`.

## Module Map

Every non-vendored file, its responsibility and the TOC load order: `docs/module-map.md`. In short:
`locales/enUS.lua` first; `core/` holds the namespace, the compat seam, the LibKa0s setup files,
the stand-down latch, the database and the AceAddon entry (`core/RangeMaster.lua`); `defaults/`
the AceDB defaults, the templates and the data tables; `modules/` the band sets, the range engine
and its ticker, the container registry and presets, the renderer with its style and element files,
and the diagnostics sections; `settings/` the schema runtime, the slash
descriptor, the options descriptor and the pages.

### Per-client features

All features serve both clients. The client is asked only through `core/Compat.lua`'s routing of
`LibKa0s-Compat-1.0` (clients-§3); no file reads a `WOW_PROJECT_*` global or decides the client from
an interface number (`tests/test_compat.lua` pins that). What differs per client is data, picked by
`NS.Compat.ClientKey()` at call time (clients-§5): the range ladder (`core/Compat.lua`, Forever only:
items and interact distances; spells on both) and the spell seeds (`defaults/SpellSeeds.lua`, keyed
`[client][classFile]`; Forever has no Death Knight, Monk, Demon Hunter or Evoker). Forever's
`PLAYER_FOCUS_CHANGED` is registered only where `NS.Compat.IsEventValid` says the client knows it.

## Settings Schema

One schema row per setting, `NS.Schema`, driving the panel, the slash CLI and the resets through one
write seam, `NS.SetByPath` (architecture-§5), on `LibKa0s-Schema-1.0` (`settings/Schema.lua`). The
rows today are the composed Master controls (`settings/General.lua`) and the Skin tab's skip-render
rows. The full shape, every default and the migration path: `docs/schema.md`.

**Structural registries.** Two, both in the profile, with one load pass between them,
`core/Database.lua`'s `Database.PrepareProfile` (called from `NS:RunMigrations`, so only from
`InitDB` and the three AceDB profile callbacks): it re-keys and backfills every member from its
template, rebuilds each order array, bumps each counter past the highest stored id, normalizes every
band set, seeds the four preset band sets on a profile with none, points a container at the default
set when its `bandSet` names none, and sets `seeded` to `false` when absent.

- **Band sets**: `bandSets`, `bandSetOrder`, `nextBandSetId`. Runtime writer `modules/BandSets.lua`
  (`Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `SetBandSound`, `RestoreSnapshot`); its
  seed routine `BandSets.Seed` and its
  per-set repair `BandSets.NormalizeSet` are shared with the load pass. `Delete` also rewrites the
  `bandSet` / `bandSetFriendly` references of the containers that used the deleted set; no
  `container.*` row exists yet, and when Task 8 adds `container.bandSet` that write goes through the
  helper (architecture-§5, "a row wins over a key").
- **Containers**: `containers`, `containerOrder`, `nextContainerId`, and the first-run sentinel
  `seeded`. Runtime writer `modules/ContainerManager.lua` (`NS.CM`: `Create`, `Delete`, `Duplicate`,
  `Rename`, `CopySettings`, `Clear`, `RestoreSnapshot`), whose apply a profile switch, copy or reset
  also requests; `seeded` is written by the first-run picker
  (plan Task 8). No `container.*` row exists yet; Task 8's rows write through the seam.

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

Four messages, declared once in `core/Bus.lua` through `LibKa0s-Bus-1.0`'s strict `Catalog`; every
receiver registers on its own `NS.NewBusTarget()` (architecture-§4), and the targets are tracked so a
stand-down takes every subscription down and a stand-up replays it.

| Constant | Wire name | Sender | Payload | Consumers |
|---|---|---|---|---|
| `RANGE_UPDATED` | `Ka0s_RangeMaster_RangeUpdated` | `modules/Ticker.lua` | `unit, state, minYd, maxYd` | `modules/Container.lua`: the instances watching that unit |
| `CONTAINERS_CHANGED` | `Ka0s_RangeMaster_ContainersChanged` | `modules/ContainerManager.lua` (`FlushPending`, coalesced to the next frame, held in combat) | none | the renderer (`NS.Container.Sync`) and the settings pages (Task 8) |
| `BANDSETS_CHANGED` | `Ka0s_RangeMaster_BandSetsChanged` | `modules/BandSets.lua` (`Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `SetBandSound`, `RestoreSnapshot`; never the load pass) | none | the renderer and the settings pages |
| `MODE_CHANGED` | `Ka0s_RangeMaster_ModeChanged` | `core/RangeMaster.lua` (`NS.SetTestMode`, `NS.SetSimMode`) | `mode` (`"test"` or `"sim"`), `on` | the renderer (Task 7) |

Ten or fewer messages, so `docs/message-bus.md` is not required; this table is the register.

## Slash Commands

`/rm` and `/rangemaster`, dispatched by `LibKa0s-Slash-1.0` over `NS.COMMANDS` (`settings/Slash.lua`):
`help`, `config`, `skin`, `enable`, `disable`, `list`, `get`, `set`, `reset`, `resetall`, `profile`,
`lock`, `unlock`, `resetposition`, `test`, `sim`, `debug`, `diagnostics`, `perf`, `version`. A bare
`/rm` opens the settings panel. While the addon is disabled the reserved verbs, the schema CLI,
`diagnostics` and `profile` keep answering, and the feature verbs refuse on the collection's one line.
Each verb, its arguments and its refusals: `docs/slash-dispatch.md`.

## Event Subscriptions

`core/RangeMaster.lua` registers its events from one list (`NS.__lifecycleEvents`), each through
`NS.SafeRegisterEvent` (events-frames-taint-§1), only while the addon stands up:

| Event | Handler | Why |
|---|---|---|
| `PLAYER_ENTERING_WORLD` | `addon:OnEnterWorld` | a traced world-entry edge; `NS.Anchors.Frame.Retry` (EllesmereUI spawns its unit frames at `PLAYER_LOGIN`) |
| `PLAYER_REGEN_DISABLED` | `addon:OnCombatChanged` | combat ends Test mode, Sim mode and a frame pick, and the range ticker goes to 20 Hz (bracketed `combatEdge`) |
| `PLAYER_REGEN_ENABLED` | `addon:OnCombatChanged` | the leave edge; the ticker back to 10 Hz, and a container apply combat held runs (`NS.CM.FlushPending("regen")`), then every anchor write onto a unit frame combat held (`NS.Anchors.FlushDeferred`) |
| `PLAYER_TARGET_CHANGED` | `addon:OnUnitChanged` | a unit change on `"target"`: `NS.Container.UnitChanged`, then `NS.Ticker.Changed` |
| `PLAYER_FOCUS_CHANGED` | `addon:OnUnitChanged` | the same on `"focus"`; registered only where `NS.Compat.IsEventValid` knows it (`ifValid`) |
| `UPDATE_MOUSEOVER_UNIT` | `addon:OnUnitChanged` | the same on `"mouseover"` |
| `UNIT_PET` | `addon:OnPetChanged` | the same on `"pet"`, for the player's own pet only |
| `NAME_PLATE_UNIT_ADDED` | `addon:OnNamePlateChanged` | `NS.Plates.Added(token)` (the plate tracked, its instances built, a re-check a frame later), then the same unit change on the plate's token |
| `UNIT_FACTION` | `addon:OnUnitFaction` | the same on the unit named, a reaction change (the band set follows `bandSetFriendly`); `ifValid` |
| `NAME_PLATE_UNIT_REMOVED` | `addon:OnNamePlateChanged` | `NS.Plates.Removed(token)` (its instances parked, an own-plate container on that plate frame hidden), then `NS.Ticker.Removed(token)`: `"none"` is sent outright, because the client still resolves the token while this event dispatches and a re-read would see the plate as live |
| `SPELLS_CHANGED` | `addon:OnSpellsChanged` | `NS.Range.Rebuild()`: the ladder and the known-spell cache, debounced 0.5 s |
| `ADDON_LOADED` | `addon:OnAddonLoaded` | `NS.Anchors.Frame.Retry`: a unit frame a container waits for may exist now |

The ticker itself is a `C_Timer.NewTicker`, not an event; the stand-down cancels it with the pending
rebuild. The skin picker holds one `PLAYER_REGEN_ENABLED` target of its own while a first-run show
waits out combat (`core/SkinSetup.lua`).

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
refused in and ended by combat.

## Known Limitations

- Test mode and Sim mode switch, announce `MODE_CHANGED` and refuse in combat, but the renderer does
  not hear them yet: their placeholders and the distance sweep arrive with plan Task 7.
- Visibility is the "hide with no unit" rule (and the anchors' missing frame or plate) alone until
  plan Task 7's rules (combat, reaction, out-of-combat alpha).
- A container on a nameplate is anchored to the plate but stays a child of `UIParent`: it does not
  take the plate's scale or fade, and it draws in the HUD strata over the plates.
- The frame picker and the frame providers have no settings row or verb yet: `pick` and the
  Containers page's provider rows arrive with plan Task 8.
- Without LibKa0s-Widgets-1.0 the bar indicator draws as a flat strip in the band color, not a fill.
- The Advanced preset's out-of-range sound key (`NS.Presets.OOR_SOUND`) is not yet registered with
  LibSharedMedia, so it plays nothing until the band sounds land (plan Task 7).
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
| `slash-dispatch.md` | Present | 20 commands in `NS.COMMANDS`, over the eight-or-more threshold |
| `midnight-quirks.md` | Present | Always (documentation-§3): the vendored `client-quirks` catalog block, then the addon's own section |
| `compat-layer.md` | Present | `core/Compat.lua` publishes the range reads, the two band-set unit reads, the anchors' four frame reads and the per-client ladder, fourteen addon-specific shims beyond what LibKa0s supplies, over the three-or-more threshold |
| `message-bus.md` | Not applicable | 4 messages in `NS.MSG`; the trigger is more than ten. The table lives in `## Message Bus` above |
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
