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
| `bandSets` | one set: the creating character's class (or spec) preset (R4-RM-02), Melee / Ranged for an unreadable class or one this client has no preset for, Caster 40 for a Devourer (spec 1480). Other sets join as characters are assigned or pick them (The character store, below); a profile seeded before R4-RM-02 keeps the five the older seed gave | `modules/BandSets.lua` | `[id] = NS.BANDSET_TEMPLATE` shape: `name`, `matchBy` (`"max"`/`"min"`), `unknown = { label = "?", color }`, `bands = { { from, to, label, frameColor, textColor, indicatorColor, sound, rule }, ... }` (`rule`: below), and `origin` (schema v4: below) |
| `bandSetOrder` | `{ 1 }` | `modules/BandSets.lua` | the first id is the **default set**; the seed puts the class default (or the spec's override) first |
| `nextBandSetId` | `6` (`5` in the four-set cases) | `modules/BandSets.lua` | the id counter, bumped past the highest stored id on load |
| `containers` | `{}` | `modules/ContainerManager.lua` (`NS.CM`) | `[id] = NS.CONTAINER_TEMPLATE` shape (design spec 5.2) |
| `containerOrder` | `{}` | likewise | rebuilt on load to hold exactly the stored ids |
| `nextContainerId` | `1` | likewise | |
| `seeded` | `false` | `NS.CM.MarkSeeded` (reached through `NS.Presets.MarkPickerSeen`) | whether the first-run preset picker has shown on this profile (set as it shows, and by any preset applied) |

**A set's origin (schema v4, RangeMaster#21).** `set.origin` is the key of the preset the set was made
from (`"paladin"`, `"melee_ranged"`, any `NS.BandSets.PresetKeys()` key), or nil. The seed and
`Create(name, key)` store it (`Create(name, nil)` is the Melee / Ranged copy, so `"melee_ranged"`),
`Duplicate` copies it, a set made from a bands array (`Create(name, {})`, the New dialog's Blank) has
none, and `CopyFrom` sets it to the source preset or to the source set's own origin. It is not in
`NS.BANDSET_TEMPLATE`, so the load pass fills nothing: `NormalizeSet` drops a non-string origin and keeps
any string, even a key this client has no preset for (a Retail class key on WoW Forever), so the profile
still works when it goes back. `Diff`, `IsModified` and `RestorePreset` read it; with no preset for it on
this client they answer nil, false and false.

**A band's rule (schema v2).** `band.rule` is nil (a yard band), `{ type = "spell", role, spells }`,
`{ type = "gap" }` or `{ type = "beyond" }`. `role` is `"melee"`, `"ranged"`, `"friendly"` or a tier role,
`"tier10"`, `"tier13"`, `"tier15"`, `"tier20"`, `"tier25"` or `"tier30"` (`core/Constants.lua` `TIER_ROLES`,
RangeMaster#20: the class's spells that reach that many yards, such as the WoW Forever paladin's spell
20271 and Hammer of Justice for `tier10`). The tier roles came with the class presets and need no ladder
step: a stored rule is read as it was, and a class with no list for a tier reads that band's yards. `spells`
is nil (the class's anchors for the role, `defaults/SpellSeeds.lua`) or a list of spell IDs that
overrides them. A rule names a role, not a spell, so one set serves every class in a shared profile.
`from`/`to` stay finite yards: they are the band's fallback, used when its anchor is not learned,
unusable or gives no answer, and for labels. How a set with rules is read is in `modules/BandSets.lua`'s
header (`Resolve`). The load pass keeps the rule as stored. A rule it cannot read (another type, a spell
rule with no role) makes the band a yard band.

The preset band sets (`defaults/BandSetPresets.lua`), each `matchBy = "max"`. Each band is shown as
yards, then its rule in brackets; a band with no bracket is a yard band:

| Key | Bands |
|---|---|
| `melee_ranged` | 0-5 MELEE [spell(melee)], 5-20 CLOSE, 20-30 MID, 30-40 LONG [spell(ranged)], 40+ OOR [beyond] |
| `caster40` | 0-8 CLOSE, 8-40 CAST [spell(ranged)], 40+ OOR [beyond] |
| `healer` | 0-30 NEAR, 30-40 FAR [spell(friendly)], 40+ OOR [beyond] (meant as a friendly override) |
| `hunter` | WoW Forever: 0-5 MELEE [spell(melee)], 5-8 DEAD [gap], 8-35 RANGE [spell(ranged)], 35+ OOR [beyond]. Retail: 0-5 MELEE [spell(melee)], 5-40 RANGED [spell(ranged)], 40+ OOR [beyond] |

**The class presets** (RangeMaster#20), one list per client in `<CLASS>_BY_CLIENT`, the key the
lowercase class token. The bands sit at the class's range tiers in that client's DB2
(`docs/validate-seeds.md`); a class WoW Forever lacks has no Forever list and no key there:

| Key | Retail | WoW Forever |
|---|---|---|
| `warrior` | 0-5 MELEE [melee], 5-8 CLOSE, 8-25 CHARGE [tier25], 25-30 RANGE [ranged], 30+ OOR [beyond] | the same |
| `paladin` | 0-5 MELEE [melee], 5-10 HAMMER [tier10], 10-30 RANGE [ranged], 30+ OOR [beyond] | 0-5 MELEE [melee], 5-10 JUDGE [tier10], 10-30 RANGE [ranged], 30+ OOR [beyond] |
| `hunter` | the Hunter set above | the Hunter set above |
| `rogue` | 0-5 MELEE [melee], 5-25 STEP [tier25], 25-30 RANGE [ranged], 30+ OOR [beyond] | 0-5 MELEE [melee], 5-8 CLOSE, 8-30 RANGE [ranged], 30+ OOR [beyond] |
| `priest` | 0-8 CLOSE, 8-40 CAST [ranged], 40+ OOR [beyond] | 0-8 CLOSE, 8-30 CAST [ranged], 30+ OOR [beyond] |
| `deathknight` | 0-5 MELEE [melee], 5-15 FREEZE [tier15], 15-30 RANGE [ranged], 30+ OOR [beyond] | (none) |
| `shaman` | 0-5 MELEE [melee], 5-30 SHEAR [tier30], 30-40 CAST [ranged], 40+ OOR [beyond] | 0-5 MELEE [melee], 5-20 SHOCK [tier20], 20-30 CAST [ranged], 30+ OOR [beyond] |
| `mage` | 0-8 CLOSE, 8-40 CAST [ranged], 40+ OOR [beyond] | 0-8 CLOSE, 8-20 BLAST [tier20], 20-30 CAST [tier30], 30-35 LONG [ranged], 35+ OOR [beyond] |
| `warlock` | 0-8 CLOSE, 8-40 CAST [ranged], 40+ OOR [beyond] | 0-8 CLOSE, 8-20 DRAIN [tier20], 20-30 CAST [ranged], 30+ OOR [beyond] |
| `monk` | 0-5 MELEE [melee], 5-40 RANGE [ranged], 40+ OOR [beyond] | (none) |
| `druid` | 0-5 MELEE [melee], 5-13 BASH [tier13], 13-40 RANGE [ranged], 40+ OOR [beyond] | 0-5 MELEE [melee], 5-30 RANGE [ranged], 30+ OOR [beyond] |
| `demonhunter` | 0-5 MELEE [melee], 5-15 BLADE [tier15], 15-30 RANGE [ranged], 30+ OOR [beyond] | (none) |
| `evoker` | 0-8 CLOSE, 8-25 CAST [ranged], 25+ OOR [beyond] | (none) |

Class defaults (`NS.BandSetPresets.DefaultFor(classFile, specID)`, the spec from `NS.Compat.PlayerSpecID`): a spec that plays unlike its class comes first, so Devourer (the Demon Hunter's 25 yd Intellect spec, 1480) → `caster40`; then the class's own preset on the running client; a class the client lacks, or an unreadable one → `melee_ranged`. Healer is the friendly override, no class's default. The first-run seed stores the class default alone (R4-RM-02; before, it added the class's own preset after a spec override and then `ORDER`, `melee_ranged`, `caster40`, `healer`, `hunter`); `ORDER` is now the Band sets picker's Shipped presets · General list. `NS.BandSets.Create(name, key)` takes any key the client has (`NS.BandSetPresets.CLASS_KEYS`). `NS.BandSetPresets.SpecDependent(classFile)` says whether a class's default waits on its spec (Demon Hunter, where the client has its preset).

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
| `container.bandSet` | `0` = no pick: this character's default (`db.char`, above the global store) | this character's pick, not the profile field; without a character scope the profile field, whose `nil` is filled with `DefaultId()` on create and on load |
| `container.bandSetFriendly` | `0` = Same as Band set (`false` stored as this character's pick) | with no pick the row shows the profile's `bandSetFriendly`; nil uses `bandSet` for every reaction |
| `container.elements.number.font`, `container.elements.text.font`, `container.label.font` | `Skin` = `""` stored | `""` is the skin's face (`modules/Style.lua`) |
| `container.frame.border.texture` | `Solid` = `""` stored | `""` draws the solid edge strips |

The selection itself (`NS.State.selectedContainer`, `selectedBandSet`) is session state; an unset or
stale one reads the first container, or the default band set. `NS.ValidateSchema` resolves every such
path against its template. The template gained `elements.number.shadow` and `elements.text.shadow`
(`false`) for the composed Font block's Font shadow, and the `label` section (the caption naming the
container, plan 2026-11-19 M7): `enabled = false`, `text = ""` (the container's name), `position =
"top"`, `align = "center"`, `gap = 2`, `font = ""`, `size = 12`, `outline = "OUTLINE"` (`"@skin"` from
LibKa0s v1.108.0, below), `shadow = false`, `colorMode = "fixed"`, `color` white. The load pass
backfills them; the caption is off, so a
stored container draws as before and no migration step is needed. `label.position` (M11) takes eight
values: `top`, `bottom`, `left`, `right` are INSIDE the container (what M7 stored, so a stored value
keeps its meaning) and `outsideTop`, `outsideBottom`, `outsideLeft`, `outsideRight` sit beyond its
border; an unknown value reads as inside top (`NS.Container.CaptionSide`).

Later template fields, backfilled by the load pass with no migration step: `anchor.level = 0`
(Frame level; 0 is Auto, 1..100 a fixed place in the strata), `layout.sizing = "fit"` with
`width = 120` and `height = 28`, `layout.joinText = true` (the number writes the band's label on its
line, so a stored container showing both Number and Text draws them as one line after the
backfill), `layout.align = "center"` (`left`, `center`, `right`), and `nameplate.attachTo = "plate"`
(`plate`, `castbar`, `castbarWhenCasting`). `unit` also takes `nameplatesExceptTarget`, and
`elements.number.format` takes `band` (the drawn band's span).

**Every look starts on the skin** (LibKa0s v1.108.0; skinning-§9, *Every option default follows the
skin*, the owner's R-2 of 2026-11-20). The Font flags of `label`, `elements.number` and
`elements.text` default to `"@skin"` (the From skin value, drawn through `S.FontFlags`: the skin's
Font outline), and the template carries a `<key>FromSkin` companion for every swatch, shadow and
border style, each `true`:

| Field | Draws while on |
|---|---|
| `label.colorFromSkin` | `hud.label` (`S.HudLabelColor`), while Color from is Fixed color |
| `elements.number.colorFromSkin`, `elements.text.colorFromSkin`, `elements.indicator.colorFromSkin` | `hud.text` (`S.HudTextColor`), while Color from is Fixed color |
| `label.shadowFromSkin`, `elements.number.shadowFromSkin`, `elements.text.shadowFromSkin` | the skin's HUD shadow; Font shadow is not read |
| `frame.border.textureFromSkin` | `S.BarBorder`: a skin's real bar border style and thickness (Azeroth, High Contrast, WoW Default, WoW Midnight) over Border style, thickness and Show border; a skin's None leaves the stored three |
| `frame.border.colorFromSkin` | `bar.border`, while Color from is Fixed color |
| `frame.background.colorFromSkin` | `bar.bg`, while Color from is Fixed color |

Band color and Class color come ahead of every color companion: the band color is the range's
meaning (the owner's U-30 of 2026-11-20) and a class color is the unit's. The faces take no
companion: `font = ""` is already the skin's face. A stored container moves once (Migrations, below).

## The character store (`db.char`)

AceDB's character scope holds each character's band set assignment and picks (`modules/BandSetChoice.lua`,
the store's one runtime writer; spec `docs/superpowers/specs/2026-11-26-band-set-per-character-design.md`,
then R4-RM-01 in Ka0sAddonsCommonTasks `docs/2026-11-26-OWNER_FEEDBACK_ROUND4/`). There are no
defaults: an absent key is "no pick" or "not assigned yet".

| Key | Shape | Notes |
|---|---|---|
| `bandSetAssigned[<profile name>]` | a set id, or absent | the band set this character uses on that profile wherever a container has no pick of its own (schema v6) |
| `bandSetChoice[<profile name>][<container id>].hostile` | a set id, or absent | this character's Band set for that container; absent: no pick |
| `bandSetChoice[<profile name>][<container id>].friendly` | a set id, `false`, or absent | a set id is the Friendly band set; `false` is Same as Band set; absent: the profile's `bandSetFriendly` |

The profile's name comes first because container ids repeat across profiles. **The assignment** is
written once, at the character's first load on a profile (`EnsureAssigned`, from the load pass): the
first set in `bandSetOrder` whose `origin` is `DefaultFor(class, spec)`, an edited or renamed copy
included, else a new set made from that preset. A class whose default waits on its spec
(`SpecDependent`: a Devourer) is not assigned while the spec reads nil; `PLAYER_ENTERING_WORLD` and the
spell and spec events try again. The seed cannot wait, so a Devourer's new profile is seeded with the
Demon Hunter set; when the deferred write finds that set alone, unmodified and no other character's, it
turns it into Caster 40 in place (`NS.BandSets.ReplaceWithPreset`, its id kept), so the profile holds
the one set (R4-REV). It then never moves by itself, not on a respec, a profile swap or a
login: **Use for this character** on the Band sets page (`Assign`) changes it (and releases this
character's `hostile` picks on the set it used until then, so the containers the v5 step pinned to the
old default follow the new one; a pick on any other set stays), and a delete of the set
moves it to where the delete moved the containers (the set it names, else the profile's first set),
except the deleting character's own, which never lands on another class's set: it takes its spec or
class set, else the first set that is no class's, and the delete's target only when none is left
(R4-REV). An
assignment that names no set (a hand edit) is dropped by the load pass, which then assigns afresh. This
reverses the per-character spec's C3 ("nothing is written back") for the hostile set.

**Which set a container uses.** Hostile: this character's pick; else its assignment; else, while none is
written, the old chain: this character's class default, the first set in
`bandSetOrder` whose `origin` is `DefaultFor(class, spec)`, else `DefaultFor(class)`; else the
container's `bandSet`, unless its `origin` is another class's preset; else the first set in the order
that is not another class's preset (a rogue on a profile a paladin seeded gets Melee / Ranged, never
the Paladin set); else the default set. "(default)" on the Band sets page, the Containers row's
**Default band set (X)** and the set the Band sets page opens on are the same chain without a
container: the assignment. Friendly: this character's pick (`false`: the hostile set);
else the container's `bandSetFriendly`; else the hostile set. A band set delete clears every
character's picks on it, or moves them to the set the delete names. Every character's store is reached
through `db.sv.char`. A container copy or duplicate copies the picks. A profile copy carries the picks
and the assignments to the new profile's name, and a profile reset or delete forgets them. The load
pass (`NS:RunMigrations`, after `PrepareProfile`) drops the current character's picks that name a
container or a set that no longer exists. The Band sets page's Used by line counts the other
characters assigned the set or picking it. Without a character scope (the no-AceDB fallback) there is
no assignment and the container's two fields are the selection, as before.

## The global store (`db.global`)

| Key | Default | Notes |
|---|---|---|
| `schemaVersion` | `0` | the migration stamp; 0, never the current version (savedvariables-§1) |
| `minimap.hide` | `false` | LibDBIcon's own key; the `global.minimap.shown` row inverts onto it (launcher-§3), and no `shown` key is ever stored (anti-pattern #81) |
| `skinNotice` | absent | the one-time skin notice's record, written by the library through `core/SkinSetup.lua` |

## Session-only, never persisted

`NS.State.debug`, `NS.State.testMode`, `NS.State.simMode`, `NS.State.rejectedEvents`
(`core/State.lua`) and the two selections, `NS.State.selectedContainer` and `selectedBandSet`
(`settings/Schema.lua`), the preset the Band sets page is viewing, `NS.State.viewedPreset` (`settings/Schema.lua`),
the band sets' one-level Undo slot (`settings/BandSetDialogs.lua`, dropped on a profile change), and the composed session rows `state.debugConsole`, `state.testMode` and
`state.sim`, whose rows carry their own get/set.

## Migrations

`core/Database.lua`'s ladder has six steps, so `NS.SCHEMA_VERSION` is 6 (the declared default stays 0).
**v0 -> v1, the frame defaults:** a new container draws its border at 25% (`frame.border.alpha`, new)
over a background (`frame.background.enabled` now true) with a matte dot; so that an existing one keeps
its look, the step writes `frame.border.alpha = 1`, `frame.background.enabled = false` and
`elements.indicator.style = "plain"`, where unset, onto every container already stored (making a
section a hand-edited container lacks, so the load pass cannot fill it from the new template), in every profile (`db.profiles`, `db.sv.profiles` and the
active profile). A fresh install climbs it against a profile with no container.

**v1 -> v2, band rules** (plan 2026-11-19-dynamic-bands, D4): every stored band set, custom ones
included, in every profile, is normalized and then converted to rule bands by
`NS.BandSets.ConvertSet`. In band order:

- the last, open-ended band gets `beyond`;
- a first band ending at 5 yd or less gets `spell(melee)`;
- a band from 5 to 8 yd with a band after it gets `gap`;
- the outermost band whose far edge is 20 to 45 yd gets `spell(ranged)`. It gets `spell(friendly)`
  instead in a set that is used only as a friendly override (some container's `bandSetFriendly`, and
  no container's own `bandSet`) or is named Healer. Only the outermost such band gets the rule,
  because the first band that holds wins and a nearer spell band would take every true;
- any other band stays a yard band.

No yard moves, because the yards are the fallback. A band that already carries a rule table keeps it,
so the step is idempotent. A fresh install climbs it against a profile with no band set, and the load
pass then seeds the presets, which carry their rules.

The runner climbs from `db.global.schemaVersion`, advances the stamp
only past a step that returned, and on a raising step prints one line and leaves the stamp where it
was. After the ladder, the active profile is backfilled from the defaults with `== nil` tests, so a
stored `false` survives (savedvariables-§5), and the registries' load pass runs (above).

**Step 3, own looks back** (the owner, 2026-11-23). From 2026-11-20 until then, never released, a step
outside the ladder moved stored looks onto the skin and recorded `skin.defaultsFollowSkin`. Step 3 runs
over every stored profile carrying that record: Font flags `"@skin"` go back to `"OUTLINE"`, a companion
that is on beside the template's own value goes off (one on beside a picked value stays), and the record
is cleared. A profile without the record is untouched.

**Step 4, band set origins** (RangeMaster#21, 2026-11-25). Over every stored profile, a band set with no
`origin` whose name, trimmed and case-blind, is the localized name of exactly one preset on this client
(`NS.BandSets.PresetKeys()`, the class presets and the general ones) gets that preset's key. A set that
already has an origin, a renamed set, and a name two presets share are left alone, so the step is
idempotent. A fresh install climbs it against a profile with no band set; the seed then stores each
set's origin itself.

**Step 5, band set picks per character** (the owner, 2026-11-26). The character that loads first after
the update gets, for every container of every stored profile, the container's `bandSet` as its own
`db.char.bandSetChoice` pick, where it has none. The exception is a set whose `origin` is another
class's preset, which is not pinned. The paladin keeps its Paladin set, and a hunter that loads first
still gets the Hunter set. `bandSetFriendly` is not copied, because an absent friendly pick already
reads it. Characters that load later have no pick and use their class default. Without a character
scope the step changes nothing. **A known trade-off:** data from before step 5 does not record which
character chose a set, so a generic set (Caster 40, say) is pinned on whichever character loads first.
If the paladin chose Caster 40 and the hunter loads first, the hunter keeps Caster 40 and the paladin
reads its Paladin set until it picks again.

**Step 6, the band set assigned to each character** (R4-RM-01, the owner's round 4, 2026-11-26). It
makes the loading character's `db.char.bandSetAssigned` table. It writes no assignment: `sv.char` holds
no class, so each character's first load on each profile writes its own (`EnsureAssigned`). Existing
profiles keep every set they hold; nothing is pruned (the owner: "New profiles only"). Without a
character scope the step changes nothing.
