# Architecture — Ka0s Range Master

The engineer's hub for this addon. Each mandated section summarizes and links out; the detail lives
in the topic docs registered under [Documentation map](#documentation-map) (documentation-§3).

## Overview

Ka0s Range Master draws player-built range **containers**: one unit each (`target`, `focus`, `pet`,
`mouseover`, every enemy nameplate, or every enemy nameplate but the target's), showing a range bracket as a number, a band label, an
indicator and a row of spell chips, with an optional caption naming it, colored by a shared **band set**. The design and the plan of
record are `docs/superpowers/specs/2026-11-18-rangemaster-design.md` and
`docs/superpowers/plans/2026-11-18-rangemaster-v0.1.0.md`.

**State of the tree: v0.1.0 as built, plan Tasks 1 to 8.** The born-compliant shell every Ka0s
addon shares (the Ace3 addon object, AceDB with its migration runner, the LibKa0s setup files, the
slash surface, the launcher, the stand-down latch and the diagnostics report), and on it the range
engine, the band sets, the container registry and its presets, the renderer, the four anchor modes,
the visibility and sound rules, Test mode and Sim mode, and the settings pages (General with its
Presets tab, Containers, Band sets, Profiles). On top of it the spell-driven dynamic bands
(`docs/superpowers/plans/2026-11-19-dynamic-bands.md`): a band may carry a spell rule decided each
tick by the class's anchor spells, with its yards as the fallback, and schema v2 converts every
stored set. The addon has not been run in a client yet: every in-game check in
`docs/smoke-tests.md` is still owed.

**The design is dictated by one client fact.** The game answers "is this unit within reach of
spell or item X", never "how far". The range engine asks LibRangeCheck-3.0 (vendored,
`libs/LibRangeCheck-3.0/`) for the narrowest bracket those answers allow, behind `pcall` and an
`issecretvalue` check (`NS.Compat.IsSecret`), and one shared ticker publishes `RANGE_UPDATED` on
change. A secret or failed answer reads as *unknown*, never as out of range.

### The components

| Component | Files | What it does |
|---|---|---|
| Range engine | `modules/Range.lua` (`NS.Range`), `modules/Ticker.lua` (`NS.Ticker`), `core/Compat.lua` | A guarded, memoized bracket per unit token per tick; the per-class anchor spells resolved at rebuild and asked once per spell per unit per tick (shared with the chips); one adaptive ticker that sends `RANGE_UPDATED` on change |
| Band set picks | `modules/BandSetChoice.lua` (`NS.BandSetChoice`) | Each character's assigned band set per profile and its own Band set and Friendly band set per container, in `db.char`; with no pick, the character's assignment (written at its first load on the profile, R4-RM-01), and only while none is written the old chain: its class default set (by `origin`), then the container's profile field unless it is another class's set, then the first set that is no other class's |
| Band sets | `modules/BandSets.lua` (`NS.BandSets`), `defaults/BandSetPresets.lua` | Named, shared, normalized bands of yards, each of which may carry a spell, dead-zone or beyond rule (its yards then the fallback); `Resolve` turns a bracket into a band, `ForUnit` picks the friendly override; a set remembers the preset it came from (`origin`), so `Diff`, `RestorePreset` and `CopyFrom` can compare with it, restore it or copy from it |
| Containers and presets | `modules/ContainerManager.lua` (`NS.CM`), `modules/Presets.lua` (`NS.Presets`) | The container registry's one writer and its coalesced, combat-held apply; Simple, Intermediate (Range Text), Intermediate (Range Numbers), Advanced, Expert and Ka0s, with a one-level Undo |
| Rendering | `modules/Container.lua` (`NS.Container`), `modules/Style.lua`, `modules/Elements_*.lua` | One pooled instance per enabled container (one per plate for `nameplates` and `nameplatesExceptTarget`), repainted only on a band or text change |
| Anchors | `modules/Anchors.lua` (`NS.Anchors`), `modules/Anchors_*.lua`, `modules/FrameProviders.lua`, `modules/FramePicker.lua` | Free on screen, on a unit frame, on a nameplate (own plate or every plate), at the cursor |
| Behavior and modes | `modules/Visibility.lua`, `modules/Sounds.lua`, `modules/Preview.lua`, `modules/Sim.lua` | The visibility rules, the debounced band sounds, Test mode's placeholder and Sim mode's distance sweep |
| Settings | `settings/*.lua` | The schema runtime, the slash descriptor and the pages (below, and `docs/settings-panel.md`) |

How each one works, its seams and its edge cases: `docs/data-flow.md`, *Components*.

### Libraries

Everything is vendored under `libs/`: LibStub and CallbackHandler, the Ace3 stack, LibSharedMedia,
LibDataBroker and LibDBIcon (the launcher), LibKa0s v1.113.0 (whole, its icons and sounds pruned to
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

**How the seed lists are maintained (clients-§10).** Both per-client lists in
`defaults/SpellSeeds.lua` are hand-kept, a short list per class of long-stable spell IDs (rank 1 on
Forever), and **re-validated** against each client's own DB2 on wago.tools by `tools/seeds/seeds.py`,
the contract `docs/validate-seeds.md` (`/dev-copilot:validate-seeds RangeMaster retail|forever`). A
run pins one `wow` or `wowf` build and checks every shipped id's name, class, rank (Forever) and
range (SpellMisc `RangeIndex` into SpellRange) against what the code asks of its list: a ladder rung
has no min range, a melee anchor reaches no farther than `MELEE_REACH_YD`, a role's longest reach
meets its preset band's far edge, a `tier<N>` anchor reaches N yd (the class presets' tier bands,
RangeMaster#20), the Forever hunter's anchors fit the dead zone. Rulings are data
(`tools/seeds/<flavor>_rulings.json`), and each run is a frozen bundle under `docs/seed-research/`;
the first, 2026-11-25 (wow 12.1.5.70961, wowf 1.60.1.71091), took Throw and Heroic Throw out of the
ladders, where neither could ever be a rung. `docs/smoke-tests.md` RANGE-5 still checks every seed resolves in a
client. A stale ID cannot report a wrong range: the range engine trusts a spell only while it is
known and usable, so an ID the client does not know is skipped.

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
band set, seeds the creating character's own class (or spec) preset band set alone on a profile with none (R4-RM-02), points a container at the default
set when its `bandSet` names none, and sets `seeded` to `false` when absent.

- **Band set picks and assignments** (`db.char`, not the profile): `bandSetChoice[<profile>][<container id>]`
  and `bandSetAssigned[<profile>]`. Runtime writer `modules/BandSetChoice.lua` (`Set`, `Assign`,
  `EnsureAssigned`, `Forget`, `CopyContainer`, `CopyProfile`, `ForgetProfile`, `Prepare`, schema v5's
  `Migrate` and v6's `MigrateAssigned`). It holds the band set each character is assigned on each profile
  and the Band set and Friendly band set each character picked. `EnsureAssigned` runs in the load pass
  and, for a character whose default waits on its spec, from `PLAYER_ENTERING_WORLD` and the spell and
  spec events; it may create the character's class set there, through `NS.BandSets.Create`.
  `NS.BandSets.ForUnit(container, unit, id)` reads them (`docs/schema.md`, The character store).
- **Band sets**: `bandSets`, `bandSetOrder`, `nextBandSetId`. Runtime writer `modules/BandSets.lua`
  (`Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `SetBandSound`, `SetBandRule`, `RestorePreset`, `CopyFrom`,
  `RestoreSnapshot`); its
  seed routine `BandSets.Seed` and its
  per-set repair `BandSets.NormalizeSet` are shared with the load pass, and its v1 -> v2 conversion
  `BandSets.ConvertSet` with the migration ladder (`docs/schema.md`). `Delete` also moves the
  `bandSet` / `bandSetFriendly` references of the containers that used the deleted set, through the
  container registry's writer `NS.CM.SetField` (architecture-§5), and clears or moves every character's
  pick on it, and moves every character's assignment on it to where the containers went, through
  `NS.BandSetChoice.Forget`. The Band
  sets page writes through `SetField` (match rule, unknown label and color), `SetBand` (an edge, a
  label, a color; an edge that would leave a band without width is refused), `AddBand` and
  `RemoveBand`, each normalizing after the write, and `SetBandRule` (a band's rule: Defined by, Role,
  Spell IDs), which touches no edge and so normalizes nothing.
- **A set remembers its preset** (RangeMaster#21): `set.origin` is the preset key it was made from
  (`"paladin"`, `"melee_ranged"`), or nil. `Create` from a key and the seed store it, `Duplicate` copies
  it, a set made from a bands array (New's Blank) has none, and `CopyFrom` sets it to the source preset
  or to the source set's own origin. Schema step 4 back-fills it by name on sets stored before
  (`docs/schema.md`). A preset is still copied, never referenced: `Diff(id)` builds a fresh copy of the
  origin and lists what differs (`{ band?, field, mine, preset }`, sounds never counted, nil with no
  origin on this client), `IsModified` is a non-empty `Diff`, and `RestorePreset(id, keepSounds)` takes
  the fresh copy's bands, match rule and unknown label and color, keeping the name, id and containers.
  `PresetKeys()` lists each preset once (`classes`: `CLASS_KEYS`, Hunter included; `general`: the rest
  of `ORDER`), and `PresetSet(key)` is a copy stored nowhere, which the Band sets page shows while a
  preset is viewed read-only. The page takes `Snapshot()` before a restore or a copy, and `/rm bands
  undo` puts back that one set (`settings/BandSetDialogs.lua`).
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
| `BANDSETS_CHANGED` | `Ka0s_RangeMaster_BandSetsChanged` | `modules/BandSets.lua` (every writer: `Create`, `Delete`, `Duplicate`, `Rename`, `Normalize`, `SetField`, `SetBand`, `AddBand`, `RemoveBand`, `SetBandSound`, `SetBandRule`, `RestorePreset`, `CopyFrom`, `RestoreSnapshot`; never the load pass) | none | the renderer (`Repaint`) and `settings/BandSets.lua` (a redraw of the pages, coalesced to the next frame) |
| `ANCHORS_CHANGED` | `Ka0s_RangeMaster_AnchorsChanged` | `modules/Range.lua` (the debounced rebuild, only when a band rule's resolved anchor spell, its reported range, or the anchor a druid's form puts in use moved) | none | the renderer (`Repaint`); the Band sets page (`settings/BandSets.lua`, a redraw for the spell bands' read-out) |
| `MODE_CHANGED` | `Ka0s_RangeMaster_ModeChanged` | `core/RangeMaster.lua` (`NS.SetTestMode`, `NS.SetSimMode`) | `mode` (`"test"` or `"sim"`), `on`, `why` | `modules/Preview.lua` (what the displays draw), `modules/Sim.lua` (starts or stops the sweep) and `settings/Presets.lua` (the preset picker repaints its Test mode buttons while shown) |

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
| `PLAYER_REGEN_DISABLED` | `addon:OnCombatChanged` | combat ends Test mode, Sim mode, a frame pick and a preset picker's preview (`NS.PresetPickerCombat`), the range ticker goes to 20 Hz, and every container's visibility is asked again (bracketed `combatEdge`) |
| `PLAYER_REGEN_ENABLED` | `addon:OnCombatChanged` | the leave edge; the ticker back to 10 Hz, every container's visibility asked again, and a container apply combat held runs (`NS.CM.FlushPending("regen")`), then every anchor write onto a unit frame combat held (`NS.Anchors.FlushDeferred`) |
| `PLAYER_TARGET_CHANGED` | `addon:OnUnitChanged` | a unit change on `"target"`: `NS.Container.UnitChanged`, then `NS.Anchors.UnitChanged` (an own-plate container moves to the new unit's plate, and every plate's eligibility for the plate containers is asked again, since a retarget moves the plate a `nameplatesExceptTarget` container skips), then `NS.Ticker.Changed` |
| `PLAYER_FOCUS_CHANGED` | `addon:OnUnitChanged` | the same on `"focus"`; registered only where `NS.Compat.IsEventValid` knows it (`ifValid`) |
| `UPDATE_MOUSEOVER_UNIT` | `addon:OnUnitChanged` | the same on `"mouseover"` |
| `UNIT_PET` | `addon:OnPetChanged` | the same on `"pet"`, for the player's own pet only, and `NS.Range.Rebuild()` |
| `NAME_PLATE_UNIT_ADDED` | `addon:OnNamePlateChanged` | `NS.Plates.Added(token)` (the plate tracked, its instances built, a re-check a frame later), then the same unit change on the plate's token |
| `UNIT_FACTION` | `addon:OnUnitFaction` | the same on the unit named, a reaction change (the band set follows `bandSetFriendly`, and `NS.Anchors.UnitChanged` moves a plate into or out of a hostile-only `nameplates` container); `ifValid` |
| `UNIT_SPELLCAST_START`, `_STOP`, `_FAILED`, `_INTERRUPTED`, `_SUCCEEDED`, `_CHANNEL_START`, `_CHANNEL_STOP`, `_EMPOWER_START`, `_EMPOWER_STOP` | `addon:OnPlateCast` | `NS.Plates.CastChanged(unit)`: for a tracked plate token only (anything else returns after one table read), every container on that plate set to *Cast bar while casting, else nameplate* is placed again from whether its cast bar is shown (the bar's own OnShow/OnHide hooks settle it when the event arrives first), per-plate and own-plate, in combat too (no secure frame). Event-driven, never polled; each `ifValid` (the empower pair is Retail's) |
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
target of its own while a first-run show waits out combat, the one-time skin notice holds another
while it is owed through combat (`core/SkinSetup.lua`), and the first-run preset picker a third while its show waits out combat (`settings/Presets.lua`, `NS.MaybeShowPresetPicker`); each is a tracked `NS.NewBusTarget()`, so the stand-down drops all three.

## Taint Notes

The addon's one hook is a `HookScript` on a nameplate cast bar's `OnShow` and `OnHide` (`modules/Anchors_Nameplate.lua`, once per bar, under `pcall`, for *Cast bar while casting*), and its handler only re-anchors this addon's own frames. Every frame it draws is its own, plain and unprotected: the renderer's
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
never a real plate, and nothing measures it. It keeps an enemy nameplate's look under every skin
(skinning-§9 Preview stand-ins, owner ruling U-24 of 2026-11-20): only the container beside it
follows the skin.

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
- A set's `origin` on a profile stored before schema v4 is a guess by name: a set still named after one
  preset (case-blind, trimmed) gets that preset, and a renamed one, or a name two presets share, gets
  none and so has no origin line and no Restore. Copy bands from a preset gives it one.
- A set is never synced to its preset: when an addon update changes a preset, a set made from it reads
  `· modified` (the differences are the update's), and Restore takes the new preset. An origin whose
  preset this client lacks (a Retail class key on a profile opened on WoW Forever) is kept, but shows no
  origin line and no Restore there. A sound never counts as a difference, because no preset carries one.
- The Undo after Copy bands from or Restore preset is `/rm bands undo`, named in the chat line: neither
  the addon nor LibKa0s has a clickable chat link. It is one level, per profile and this session only,
  puts back only the set that was written, and is refused once that set is deleted.
- A shipped preset viewed on the Band sets page is read-only: it is never seeded into the profile and a
  first edit never makes a copy (the owner, 2026-11-25). While one is viewed, every `bandSet.*` write is
  refused; `/rm get bandSet.*` still reads the selected set of yours.
- The picker's group names (Your band sets, Shipped presets · Classes, Shipped presets · General) are
  disabled rows, not true headers: AceGUI's dropdown takes one item type for every row.
- The preset picker (a window shaped as AuraMaster's: a dropdown, each pick previewed on the real
  screen in test mode, Apply / Not now) has no style switch and no Empty preset, which this addon's
  presets do not have; a disabled addon that is enabled later is not offered it on first run.
- Sim mode's sweep moves every container through one simulated distance; it does not simulate a
  unit's reaction, class or existence.
- A container on a nameplate is anchored to the plate (or, with Attach to part on Cast bar, to the
  plate's cast bar) but stays a child of `UIParent`: it does not take the plate's scale or fade, and
  it draws in its own strata, outside the plate. A nameplate composites as one unit (EllesmereUI's
  `EllesmereUINameplates_CastOverlay.lua` and `EUI_MythicTimer_KickPlates.lua` record it, live-verified
  there), so no strata or level on a `UIParent` frame can slip between a plate and that plate's own
  cast bar: with EllesmereUI's cast bar left on its plate, Frame strata Background has been seen to
  draw over it (the owner, 2026-11-20). With EllesmereUI's **Casts In Front of Nameplates** on, the
  cast bar leaves the plate for a `UIParent` frame at `HIGH`, and any Frame strata below High puts the
  container under it. Whether Frame level 1 at Background reaches under a plate drawn in the same
  strata is unconfirmed (smoke check ANCHOR-11 records it). Attach to part on Cast bar (or Cast bar
  while casting, else nameplate) moves the container off the bar instead.
- *Cast bar while casting* is decided on both clients by whether the plate's cast bar is shown: the bar's own `OnShow` / `OnHide` (hooked once per bar) place the container, and the cast events only nudge it. No cast read (`UnitCastingInfo` / `UnitChannelInfo`) is made. The unlocked preview nameplate draws no cast bar.
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
- A spell band trusts the anchor's own answer, and whether `C_Spell.IsSpellInRange` follows range
  talents, and whether `C_Spell.GetSpellInfo` reports the talented range, are undocumented on both
  clients (WoW Forever's reported range was measured talented: 41 yd with Hawk Eye 3/3, RANGE-6;
  Retail and RANGE-7 still open). If the reported range is the base one, the Bands page read-out and Sim show the base
  number while the band still follows the spell (`docs/midnight-quirks.md`; smoke checks RANGE-6,
  RANGE-7, RANGE-10).
- A dead-zone (gap) band holds by rule only where the ranged anchor reports a minimum range (the
  WoW Forever hunter's 8 yd); on Retail no ranged anchor has one, so a gap band there falls to its
  yards. In combat on a unit the player cannot attack the interact check is refused, so the dead
  zone is confirmed by LibRangeCheck's bracket alone.
- Harmful anchors give no answer on a friendly unit, so a friendly container reads its yards unless
  its set has a friendly spell band. Melee reach is the client's own, so against a large boss or a
  player the melee band follows the spell, not 5 yd.
- `beyond` holds whenever no spell band's anchor says true and the farthest one says false past its
  reach (a nearer band with no answer, a class with no melee spell, does not stop it), even while the
  bracket is short of the beyond band's fallback edge, and it beats a yard band whose yards match too
  (the owner's rulings, 2026-11-19: a Forever caster's 30 yd spell out of range reads OOR at 30-40,
  and an Evoker's 25-30 yd friend is not NEAR). Two exceptions read *unknown* instead, never out of
  range on a guess: a bracket that still reaches into a gap band's yards (an unconfirmed dead zone),
  and a min-range anchor's false with no bracket at its min (Auto Shot, Throw or Charge may only be
  saying "too close").
- For a friendly unit in combat LibRangeCheck answers from spells only, and a Retail Priest, Paladin
  or Druid has none under 40 yd, so the Healer set reads FAR from 0 to 40 there (NEAR needs the
  out-of-combat checks); a class with no friendly spell (Warrior, Hunter, Death Knight, Demon Hunter;
  Forever Warrior, Hunter, Rogue) reads *unknown* on a friend in combat. LibRangeCheck's own
  restriction (the cross-validation review, 2026-11-19).
- A role's candidates are ordered at rebuild by the range the client reports; a buff that stretches a
  ranged spell for a few seconds (Spatial Paradox, Sniper Shot) is read through that spell's own
  in-range answer, but does not reorder the candidates until the next rebuild.
- A character's band set is assigned at its first load on a profile, by class, and by spec only for
  Devourer (Caster 40); a later spec change never moves it (R4-RM-01), so a Demon Hunter who respecs
  picks its set with **Use for this character**. A Devourer whose spec the client cannot read at load
  is assigned at the first event that can. Deleting a set with no replacement named moves every
  character's assignment on it to the profile's first set, which may be another class's: that
  character picks its own again with **Use for this character** (the assignment is never cleared, so
  a deleted class set is never re-created behind the player's back). A profile made before R4-RM-02
  keeps every set the older seed gave it (the owner: "New profiles only").
- A tier band (`tier10` ... `tier30`) asks a spell the class learns at some level or through a talent
  (Shadowstep, Felblade, Skull Bash, WoW Forever's Drain Life); until it is learned, and while it is
  unusable (WoW Forever's spell 20271 with no seal up, Charge in combat), the band reads its yards.

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
| `midnight-quirks.md` | Present | Clients includes Retail (documentation-§3): the vendored `client-quirks` catalog block, then the addon's own section |
| `forever-quirks.md` | Present | Clients includes Forever (documentation-§3, forever-quirks-§1): the vendored `forever-quirks` catalog block, then the addon's own WoW Forever section |
| `compat-layer.md` | Present | `core/Compat.lua` publishes the range reads, the two band-set unit reads, the anchors' four frame reads, the band rules' anchor reads (with `OverrideSpell` and the spec read `PlayerSpecID`) and the per-client ladder, 23 shims by documentation-§3's count as measured on 2026-11-20, nineteen of them addon-specific beyond what LibKa0s supplies, over the three-or-more threshold |
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

| Doc | Covers |
|---|---|
| `validate-seeds.md` | The seed-validation contract `/dev-copilot:validate-seeds RangeMaster <flavor>` runs: the tool, its checks and the code each stands for, the ruling precedent, the steps and the gate |
| `seed-research/` | Frozen per-build bundles written by `tools/seeds/seeds.py` (`SOURCES.md`, `candidates.json`, `DIFF.md`, `RULINGS.md`, a hand-written `ANALYSIS.md`, gzipped `raw/` tables); the dated bundles are not enumerated |

## Documented deviations

| Rule | What differs | Why | Decided | Re-check trigger |
|---|---|---|---|---|
| `skinning-§9` (*Every option default follows the skin*) | A container's looks start as its own: Font flags `OUTLINE` on the caption, number and text, and every `colorFromSkin`, `shadowFromSkin` and the border's `textureFromSkin` off (`NS.CONTAINER_TEMPLATE`). Each can still be ticked. | The R-2 pass of 2026-11-20 turned the presets' white captions gold and drew borders on the frameless Ka0s preset under four skins. The owner restored the looks on 2026-11-23. Schema v3 takes back what the retired step wrote. | 2026-11-23 | The owner names these options. A collection-wide follow-the-skin sweep or audit is not a trigger |
| `options-ui-§14` (*The band is ONE ROW*) | The Band sets header draws a second row under the picker row (`settings/BandSets.lua`, `ORIGIN_H`): the origin line, with **Restore <Preset> preset…** on a set of yours from a preset, or **Use this preset…** and **Copy into a set of mine…** on a viewed preset. The picker row itself keeps the picker, New…, Duplicate, Copy bands from… and Delete…. | The owner's approved band set manager mockup (RangeMaster#21, 2026-11-25) puts the origin and Restore under the picker. `General` cannot hold them: it is drawn disabled while a preset is viewed, and Use this preset… is the one way out of that view. | 2026-11-25 | The standard rules on a second band row (raised with the owner as an open evolution), or the owner moves the origin acts |

### Files over the 1500-line cap

Nothing is over the cap today; the census is measured by tests/_kit/test_layout_cap.lua.
