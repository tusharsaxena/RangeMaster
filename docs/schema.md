# Schema — Ka0s Range Master

What is persisted, every default, and the migration path (savedvariables).

## SavedVariables

Two globals, both declared in `RangeMaster.toc` and `.luacheckrc`:

- **`RangeMasterDB`** — AceDB-3.0 (`core/Database.lua`), with profiles. The defaults tree is
  `defaults/Profile.lua`'s `NS.defaults`.
- **`RangeMasterPerfDB`** — the perf harness's capture ring (`core/PerfSetup.lua`, performance-§5),
  outside AceDB so no profile copy, reset or switch carries a capture.

## The profile (`db.profile`)

| Key | Default | Row | Notes |
|---|---|---|---|
| `enabled` | `true` | Enable Range Master | the stored half of the `disabled` hold (slash-commands-§7) |
| `visibility` | `"always"` | General visibility | the composer's four values: always, in combat, out of combat, never |
| `scale` | `1.0` | Master scale | 0.5–2 |
| `alpha` | `1.0` | Master opacity | 0–1 |
| `locked` | `true` | Lock frame | the displays start locked |
| `skin.source` | `"ka0s"` | Skin source | `ka0s` or `eui` (skinning-§2) |
| `skin.skin` | the client's default skin | Skin | WoW Forever on Forever, Ka0s Default on Retail (`NS.DEFAULT_SKIN`) |
| `skin.ignorePanel` | `true` | Ignore settings panel | on by default (skinning-§3) |
| `skin.ignoreFonts` | `false` | Ignore fonts | |
| `skin.font` | `""` | Font | an LSM key over the skin's own; empty keeps the skin's |
| `skin.texture` | `""` | Texture | likewise |
| `skin.outline` | `"hud"` | Font outline | `all`, `hud` or `off` |
| `skin.pickerSeen` | `false` | (none drawn) | the first-run skin picker's memory |

## The registries (`db.profile`, not AceDB defaults)

Two structural registries and their bookkeeping live in the profile too, created and repaired by
`core/Database.lua`'s load pass, `Database.PrepareProfile`, never by AceDB's defaults: no schema row
addresses them, and an AceDB default with no row is a setting nobody can reach (architecture-§5).

| Key | Fresh profile | Writer | Notes |
|---|---|---|---|
| `bandSets` | the four presets | `modules/BandSets.lua` | `[id] = NS.BANDSET_TEMPLATE` shape: `name`, `matchBy` (`"max"`/`"min"`), `unknown = { label = "?", color }`, `bands = { { from, to, label, frameColor, textColor, indicatorColor, sound }, ... }` |
| `bandSetOrder` | `{ 1, 2, 3, 4 }` | `modules/BandSets.lua` | the first id is the **default set**; the seed puts the class default first |
| `nextBandSetId` | `5` | `modules/BandSets.lua` | the id counter, bumped past the highest stored id on load |
| `containers` | `{}` | `modules/ContainerManager.lua` (`NS.CM`) | `[id] = NS.CONTAINER_TEMPLATE` shape (design spec 5.2) |
| `containerOrder` | `{}` | likewise | rebuilt on load to hold exactly the stored ids |
| `nextContainerId` | `1` | likewise | |
| `seeded` | `false` | `NS.CM.MarkSeeded` (reached through `NS.Presets.MarkPickerSeen`) | whether the first-run preset picker has shown on this profile (set as it shows, and by any preset applied) |

The preset band sets (`defaults/BandSetPresets.lua`), each `matchBy = "max"`:

| Key | Bands |
|---|---|
| `melee_ranged` | 0-5 MELEE, 5-20 CLOSE, 20-30 MID, 30-40 LONG, 40+ OOR |
| `caster40` | 0-8 CLOSE, 8-30 MID, 30-40 LONG, 40+ OOR |
| `healer` | 0-30 NEAR, 30-40 FAR, 40+ OOR (meant as a friendly override) |
| `hunter` | WoW Forever: 0-5 MELEE, 5-8 DEAD, 8-35 AUTO, 35+ OOR. Retail: 0-5 MELEE, 5-40 RANGED, 40+ OOR |

Class defaults (`NS.BandSetPresets.DefaultFor`): Hunter → `hunter`; Mage, Warlock, Priest, Evoker →
`caster40`; every other class, or an unreadable one → `melee_ranged`.

**What the load pass repairs.** A member that is not a table, or is stored under a key that is not a
positive integer, is dropped (a numeric string key is moved to its number); every member is backfilled
from its template with `== nil` tests, a section stored as a non-table is replaced by the template's,
and an array in the template (`elements.order`) is never filled index by index: a missing element
name is appended once and an unknown one dropped. Every band set is normalized (`BandSets.NormalizeSet`:
edges coerced to finite yards, a reversed pair swapped, sorted, chained so each band starts where the
one before it ends, zero-width bands dropped, the last band open-ended, at least one band, an unknown
`matchBy` read as `"max"`). A container whose `bandSet` names no set gets the default; a dangling
`bandSetFriendly` is cleared.

## The selection-relative rows (`container.<field>`, `bandSet.<field>`)

The Containers and Band sets pages' rows address a field of the SELECTED container or band set
(`settings/Schema.lua`): `container.anchor.mode` is `containers[<selected>].anchor.mode`. Each row
reads and writes through its own `get` / `set`, which reach `NS.CM.SetField` (the name `NS.CM.Rename`)
or `NS.BandSets.SetField` (the name `NS.BandSets.Rename`); none is a stored path the seam writes on its
own. Each default is the template's (`NS.CONTAINER_TEMPLATE`, `NS.BANDSET_TEMPLATE`), except where
the template holds nil:

| Path | Reads / writes | Why |
|---|---|---|
| `container.bandSet` | `0` = the default band set | the template's `nil` is filled with `DefaultId()` on create and on load |
| `container.bandSetFriendly` | `0` = none (`nil` stored) | nil uses `bandSet` for every reaction |
| `container.elements.number.font`, `container.elements.text.font` | `Skin` = `""` stored | `""` is the skin's face (`modules/Style.lua`) |
| `container.frame.border.texture` | `Solid` = `""` stored | `""` draws the solid edge strips |

The selection itself (`NS.State.selectedContainer`, `selectedBandSet`) is session state; an unset or
stale one reads the first container, or the default band set. `NS.ValidateSchema` resolves every such
path against its template. The template gained `elements.number.shadow` and `elements.text.shadow`
(`false`) for the composed Font block's Font shadow; the load pass backfills them.

## The global store (`db.global`)

| Key | Default | Notes |
|---|---|---|
| `schemaVersion` | `0` | the migration stamp; 0, never the current version (savedvariables-§1) |
| `minimap.hide` | `false` | LibDBIcon's own key; the `global.minimap.shown` row inverts onto it (launcher-§3), and no `shown` key is ever stored (anti-pattern #81) |
| `skinNotice` | absent | the one-time skin notice's record, written by the library through `core/SkinSetup.lua` |

## Session-only, never persisted

`NS.State.debug`, `NS.State.testMode`, `NS.State.simMode`, `NS.State.rejectedEvents`
(`core/State.lua`) and the two selections, `NS.State.selectedContainer` and `selectedBandSet`
(`settings/Schema.lua`), and the composed session rows `state.debugConsole`, `state.testMode` and
`state.sim`, whose rows carry their own get/set.

## Migrations

`core/Database.lua`'s ladder has one step, so `NS.SCHEMA_VERSION` is 1 (the declared default stays 0).
**v0 -> v1, the frame defaults:** a new container draws its border at 25% (`frame.border.alpha`, new)
over a background (`frame.background.enabled` now true) with a matte dot; so that an existing one keeps
its look, the step writes `frame.border.alpha = 1`, `frame.background.enabled = false` and
`elements.indicator.style = "plain"`, where unset, onto every container already stored (making a
section a hand-edited container lacks, so the load pass cannot fill it from the new template), in every profile (`db.profiles`, `db.sv.profiles` and the
active profile). A fresh install climbs it against a profile with no container. The runner climbs from `db.global.schemaVersion`, advances the stamp
only past a step that returned, and on a raising step prints one line and leaves the stamp where it
was. After the ladder, the active profile is backfilled from the defaults with `== nil` tests, so a
stored `false` survives (savedvariables-§5), and the registries' load pass runs (above).
