# Settings panel — Ka0s Range Master

Settings → AddOns → **Ka0s Range Master**, built by `LibKa0s-Options-1.0` from the schema
(`settings/OptionsSetup.lua`). The category registers eagerly at load; each page's body builds on its
first show (options-ui-§5). Every page but the landing page and Profiles is a tab strip
(options-ui-§13). Opening the panel in combat is refused with a gray line, and a page shown in combat
by the sidebar is covered by the library's lock (options-ui-§2).

| Page | Covers |
|---|---|
| Ka0s Range Master (landing) | The logo, the TOC Notes line and the slash command list (`settings/About.lua`) |
| General | Master controls, the presets and the skin (`settings/General.lua`, `settings/Presets.lua`) |
| Containers | One range container at a time: a banner picker with New container, and a nav rail of five entries (`settings/Containers*.lua`) |
| Band sets | One band set at a time: a banner picker with New band set, its General tab and the Bands editor (`settings/BandSets.lua`) |
| Profiles | AceDB profiles: switch, copy, delete, reset (`settings/Profiles.lua`) |

Every Containers and Band sets row is selection-relative, `container.<field>` or `bandSet.<field>`
(`docs/schema.md`), so `/rm get` and `/rm set` reach the item the banner shows, through the registry's
own writer.

## General

### Master controls

Composed by `H.MasterControls` from one declaration; the words and the order are the library's
(options-ui-§15).

| Row | Schema key | Behavior |
|---|---|---|
| Enable Range Master | `enabled` | moves the `disabled` hold on the one latch (`NS.SyncEnabledHold`); off stands the addon down |
| General visibility | `visibility` | always, in combat, out of combat or never; asked by every container on each render and at once on a write (`modules/Visibility.lua`) |
| Master scale | `scale` | scales every display |
| Master opacity | `alpha` | fades every display |
| Lock frame | `locked` | locked displays cannot be dragged; unlocked, every screen container shows its drag strip (`NS.Anchors.RefreshLock`) and, out of combat, every container shows, an absent unit on the placeholder range, each wears the drag strip (name, settings mark, close mark), and a cursor or own-plate container waits at its screen point (`NS.Container.RefreshLock`) |
| Debug console | `state.debugConsole` | session-only; shows or hides the console window |
| Minimap button | `global.minimap.shown` | stored in the global store under LibDBIcon's `hide`, inverted; survives every reset (launcher-§3) |
| Test mode | `state.testMode` | session-only; placeholders on every display; refused in combat and ended by it (`NS.SetTestMode`) |
| Sim mode | `state.sim` | session-only; the launcher's pair, `NS.IsSimMode` / `NS.ToggleSimMode`, same as `/rm sim` |
| Reset position (button) | — | `NS.ResetPositions`, the same handler as `/rm resetposition`: every screen container back at its new-container point |
| Reset all settings (button) | — | confirms, then `NS.Helpers.RestoreAllDefaults`, the same as `/rm resetall` |

The header **Defaults** button restores every General row on this profile except the minimap row.

### Presets

A host tab (options-ui-§13) between Master controls and Skin: one card per preset (Simple,
Intermediate, Advanced), each its `NS.Presets.Describe` lines and an **Apply <name>…** button, then
**Undo last preset**. Apply goes through `NS.ConfirmPreset`: a profile with containers is asked first
(the popup names the preset and the count it replaces); an empty one applies at once. `/rm preset`
takes the same route.

### The preset picker

A standalone window (`settings/Presets.lua`, shaped as AuraMaster's `settings/PresetPicker.lua`),
shown once per profile while `seeded` is false (marked seen as it shows, held through combat) and on
demand from a bare `/rm preset`. Title **Choose a preset** with the settings and close marks, the
owner line, a LibKa0s dropdown of the three presets (`Simple - 4 containers`, ...), a one-line
blurb, *The skin picker opens next.* while that one is due, two toggles (**Containers:
locked/unlocked**, **Test mode: on/off**), **Apply** and **Not now**, and the footer *Change it later
on General > Presets.* Opening records the lock, unlocks and turns test mode on. A pick previews the
preset on the real screen (`NS.Presets.BeginPreview`: the player's set snapshotted once, at the first
pick). **Apply** keeps it, behind the confirm when the player has containers of their own (the Undo
slot is then the set from before the picker), locks and turns test mode off; with nothing picked it
keeps what is there. **Not now**, the close mark and Escape restore the player's set and the lock
the window found; each offers the skin picker next. The settings mark closes it the same way and
opens this tab instead, the skin picker left due. Combat starting restores a preview; a pick in
combat is refused. AceDB's `OnProfileShutdown` and `OnDatabaseShutdown` take it down with its
preview restored into the profile it was taken on, before a switch or a SavedVariables write; a
reset or a copy drops the preview instead.

### Skin

The library's `O.AppearanceTab` (skinning-§3), drawn over the `skin.*` skip-render rows: source, skin,
the Scope's Ignore settings panel and Ignore fonts, the Font and Texture overrides and the Font outline.
A pick lands through `NS.WriteSkinChoice` and the write seam.

## Containers

The band carries the page's only picker and **New container** (`O.PageBanner` with `action`). The nav
rail picks which part of the selected container is shown; each entry is its own page key, so the
header **Defaults** restores every tab of the entry on screen, for the container in the band. The
**Sounds** entry is not listed for a `nameplates` container, and the rail heals to General when the
selection moves to one.

| Entry (page key) | Tabs | Rows |
|---|---|---|
| General (`containers`) | General, Position | Name, Enable this container; What it tracks: Unit, Band set, Friendly band set; then Duplicate container, Delete container… (confirmed), Copy settings from and the band Preview. Position: Attach to and Frame strata (every mode), then the rows of the chosen placement only (`shownWhen`, options-ui-§22), read as AuraMaster's Position tab: what it attaches to's anchor point and This container anchor point side by side, then X and Y side by side. On the unit frame: Unit frames from, Frame name for a custom frame, **Pick on screen**, Unit frame anchor point, This container anchor point, X offset, Y offset. On screen: Screen anchor point, This container anchor point, X position, Y position. At the cursor: This container anchor point, X offset, Y offset. On the nameplate: Nameplate anchor point, This container anchor point, X offset, Y offset (and Friendly nameplates too for All nameplates); while unlocked a preview nameplate shows where the container sits on one |
| Display (`containers_display`) | Layout, Frame, Number, Text | Direction, Spacing, Padding, Container scale, Container opacity, Size (`container.layout.sizing`: Fit its content, or Fixed size) with Width and Height (grayed while it fits its content), then **Element order**: a LibKa0s-Widgets `ReorderList` shaped as MultiMeters' Columns list, one row per element (the `segment` handle, an on/off tick that writes the element's own `enabled` row, the name at the right); the elements turned on come first and only they drag (the list's `boundary`), the ones turned off sit dimmed below with no handle; a drop or a tick writes `container.elements.order` as the list shows it (options-ui-§18; on the CLI the row takes names, `number,text` putting those first); the composed border block and the background pair; Show number and Format with the composed Font block; Show text label and Uppercase with the composed Font block |
| Indicator (`containers_indicator`) | Indicator, Spell chips | Show indicator, Shape, Size and the composed color pair; Show spell chips, Style, Size |
| Visibility (`containers_visibility`) | Visibility | Show (always, in combat, out of combat), Reaction, Hide with no unit, Out of combat opacity |
| Sounds (`containers_sounds`) | Sounds | Play band sounds, Sound channel |

Every color swatch's companion is the container's three-value **Color from** (band, fixed, class;
options-ui-§17), declared `classColorSource = "unit"`: a range container describes its unit.

## Band sets

The band carries the band-set picker (the default set marked) and **New band set**. **General**:
Name, Match band by, and the Unknown range subsection (Unknown label, Unknown color, a palette swatch
with no class companion), then the containers using the set and **Duplicate band set** / **Delete
band set…** (confirmed; its containers move to the default set; the last set is never deleted).
**Bands** (a host editor): the distance ribbon, then per band Up to (yards), Label, Frame / Text /
Indicator color and Sound on enter, Remove band, and **Add band** at the foot. The bands are ordered
by their edges (`modules/BandSets.lua` normalizes every write), so a band moves by moving its edge and
there is no reorder control (options-ui-§18 binds a list whose order is the setting; this one's is
derived). The band colors are palette swatches (options-ui-§17's one exemption): each identifies a
band, so none takes a class-color companion; class color is the container's own Color from. A band's
controls are path-less (options-ui-§13 host editor), so `/rm get|set` does not reach them; every
band-set name is unique (`NS.BandSets.UniqueName`), and a name two sets still share (a hand-edited
SavedVariables file) is refused by `/rm bands` as ambiguous. The header **Defaults** restores the match rule and the unknown label and
color; the name and the bands are kept.

## The launcher

One LibDataBroker launcher object registered with LibDBIcon (`core/LauncherSetup.lua`), labeled
`Ka0s Range Master`, with the 128 logo. Left-click opens the settings; right-click opens the menu:
**Enabled**, **Locked**, **Test mode**, **Sim mode**, each the matching slash verb's own handler, and
the library's *Open skin selector*. While disabled, every entry but Enabled is grayed. There is no
Show window entry and no key binding: the addon has no primary window.
