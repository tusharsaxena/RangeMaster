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

The range containers and band sets join the profile in plan Task 3: `containers`, `containerOrder`,
`nextContainerId`, `bandSets`, `bandSetOrder`, `nextBandSetId` and `seeded`, with the container and
band-set templates in the design spec, section 5.2.

## The global store (`db.global`)

| Key | Default | Notes |
|---|---|---|
| `schemaVersion` | `0` | the migration stamp; 0, never the current version (savedvariables-§1) |
| `minimap.hide` | `false` | LibDBIcon's own key; the `global.minimap.shown` row inverts onto it (launcher-§3), and no `shown` key is ever stored (anti-pattern #81) |
| `skinNotice` | absent | the one-time skin notice's record, written by the library through `core/SkinSetup.lua` |

## Session-only, never persisted

`NS.State.debug`, `NS.State.testMode`, `NS.State.simMode` and `NS.State.rejectedEvents`
(`core/State.lua`), and the composed session rows `state.debugConsole`, `state.testMode` and
`state.sim`, whose rows carry their own get/set.

## Migrations

`core/Database.lua`'s ladder is empty: v0.1.0 ships the first data shape, `NS.SCHEMA_VERSION` is 0 and
a fresh install stays stamped 0. The runner climbs from `db.global.schemaVersion`, advances the stamp
only past a step that returned, and on a raising step prints one line and leaves the stamp where it
was. After the ladder, the active profile is backfilled from the defaults with `== nil` tests, so a
stored `false` survives (savedvariables-§5). The first real step will be the first change to a stored
shape after v0.1.0 ships.
