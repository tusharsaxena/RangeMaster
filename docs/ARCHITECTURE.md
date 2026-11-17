# Architecture — Ka0s Range Master

The engineer's hub for this addon. Each mandated section summarizes and links out; the detail lives
in the topic docs registered under [Documentation map](#documentation-map) (documentation-§3).

## Overview

Ka0s Range Master draws player-built range **containers**: one unit each (`target`, `focus`, `pet`,
`mouseover`, or every enemy nameplate), showing a range bracket as a number, a band label, an
indicator and a row of spell chips, colored by a shared **band set**. The design and the plan of
record are `docs/superpowers/specs/2026-11-18-rangemaster-design.md` and
`docs/superpowers/plans/2026-11-18-rangemaster-v0.1.0.md`.

**State of the tree: the v0.1.0 scaffold (plan Task 1).** What exists is the born-compliant shell
every Ka0s addon shares: the Ace3 addon object, AceDB with its migration runner, the LibKa0s setup
files, the Master controls and Skin tabs, the slash surface, the launcher, the stand-down latch, the
diagnostics report, and the two session preview modes (Test mode, Sim mode) with their one writer
each. The range engine, the data model, the containers, the anchors and the settings pages for them
arrive in plan Tasks 2 to 8; each section below says where a later task plugs in.

**The design is dictated by one client fact.** The game answers "is this unit within reach of
spell or item X", never "how far". The range engine (Task 2) asks LibRangeCheck-3.0 (vendored,
`libs/LibRangeCheck-3.0/`) for the narrowest bracket those answers allow, behind `pcall` and an
`issecretvalue` check (`NS.Compat.IsSecret`), and one shared ticker publishes `RANGE_UPDATED` on
change. A secret or failed answer reads as *unknown*, never as out of range.

### Libraries

Everything is vendored under `libs/`: LibStub and CallbackHandler, the Ace3 stack, LibSharedMedia,
LibDataBroker and LibDBIcon (the launcher), LibKa0s v1.105.0 (whole, its icons and sounds pruned to
`CLAUDE.md`'s declarations) and LibRangeCheck-3.0 MINOR 39 (commit and source in root
`DEPENDENCIES.md`). Which LibKa0s modules are wired, one setup file each: `docs/module-map.md`.

## Module Map

Every non-vendored file, its responsibility and the TOC load order: `docs/module-map.md`. In short:
`locales/enUS.lua` first; `core/` holds the namespace, the compat seam, the LibKa0s setup files,
the stand-down latch, the database and the AceAddon entry (`core/RangeMaster.lua`); `defaults/`
the AceDB defaults; `modules/` the diagnostics sections; `settings/` the schema runtime, the slash
descriptor, the options descriptor and the pages.

### Per-client features

All features serve both clients. The client is asked only through `core/Compat.lua`'s routing of
`LibKa0s-Compat-1.0` (clients-§3); no file reads a `WOW_PROJECT_*` global or decides the client from
an interface number (`tests/test_compat.lua` pins that). Per-client range ladders and spell seeds
arrive with the range engine as per-client data (plan Task 2, clients-§5).

## Settings Schema

One schema row per setting, `NS.Schema`, driving the panel, the slash CLI and the resets through one
write seam, `NS.SetByPath` (architecture-§5), on `LibKa0s-Schema-1.0` (`settings/Schema.lua`). The
rows today are the composed Master controls (`settings/General.lua`) and the Skin tab's skip-render
rows. The full shape, every default and the migration path: `docs/schema.md`.

**Structural registries.** None yet. The container registry (`containers`, `containerOrder`,
`nextContainerId`, its one writer `modules/ContainerManager.lua`) and the band-set registry
(`bandSets`, `bandSetOrder`, `nextBandSetId`, its one writer `modules/BandSets.lua`) arrive in plan
Tasks 3 and 4.

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
| `RANGE_UPDATED` | `Ka0s_RangeMaster_RangeUpdated` | `modules/Ticker.lua` (Task 2) | `unit, state, minYd, maxYd` | the containers watching that unit (Task 5) |
| `CONTAINERS_CHANGED` | `Ka0s_RangeMaster_ContainersChanged` | `modules/ContainerManager.lua` (Task 4) | none | the renderer and the settings pages |
| `BANDSETS_CHANGED` | `Ka0s_RangeMaster_BandSetsChanged` | `modules/BandSets.lua` (Task 3) | none | the renderer and the settings pages |
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
| `PLAYER_ENTERING_WORLD` | `addon:OnEnterWorld` | a traced world-entry edge |
| `PLAYER_REGEN_DISABLED` | `addon:OnCombatChanged` | combat ends Test mode and Sim mode (bracketed `combatEdge`) |
| `PLAYER_REGEN_ENABLED` | `addon:OnCombatChanged` | the leave edge |

The range engine's events (target, focus, pet, mouseover, nameplate and spell changes, design spec
section 5.1) join this list in plan Task 2. The skin picker holds one `PLAYER_REGEN_ENABLED` target of
its own while a first-run show waits out combat (`core/SkinSetup.lua`).

## Taint Notes

The scaffold draws no secure frame and hooks nothing. The rules the range work is built to: every
range API call is wrapped in `pcall` and every result checked with `NS.Compat.IsSecret`; no
`SetPoint` or `SetParent` on a frame anchored to a secure frame in combat (queued for
`PLAYER_REGEN_ENABLED`); the options panel refuses to open in combat and a page shown in combat is
covered by the library's lock (options-ui-§2). Preview modes end on `PLAYER_REGEN_DISABLED`, while
secure writes are still allowed.

## Known Limitations

- The scaffold shows no range display yet: Test mode and Sim mode switch, announce `MODE_CHANGED`
  and refuse in combat, but draw nothing until the renderer lands (plan Task 7).
- `/rm resetposition` and the Reset position button report 0 displays until the container registry
  exists (plan Tasks 4 and 6).
- On a load where LibKa0s is missing, the bus's degraded stub keeps no stand-down record, so a disable
  leaves bus subscriptions live there (the untracked-target stub, `core/Bus.lua`).

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
| `compat-layer.md` | Not applicable | `core/Compat.lua` routes `LibKa0s-Compat-1.0` members and carries their library-absent stand-ins; it publishes no addon-specific shim beyond what LibKa0s supplies, under the three-or-more threshold |
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
