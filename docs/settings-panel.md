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
| Containers | One range container at a time: a banner picker with New container, and a nav rail of four entries: General, Display, Visibility, Sounds (`settings/Containers*.lua`) |
| Band sets | One band set at a time, or a shipped preset viewed read-only: a header with the grouped picker, New…, Duplicate, Copy bands from… and Delete…, the origin line under it, the General tab and the Bands editor (`settings/BandSets.lua`); the New, Copy bands from and Restore dialogs (`settings/BandSetDialogs.lua`) |
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
Intermediate (Range Text), Intermediate (Range Numbers), Advanced, Expert, Ka0s), each its `NS.Presets.Describe` lines and an **Apply <name>…** button, then
**Undo last preset**. Apply goes through `NS.ConfirmPreset`: a profile with containers is asked first
(the popup names the preset and the count it replaces); an empty one applies at once. `/rm preset`
takes the same route.

### The preset picker

A standalone window (`settings/Presets.lua`, shaped as AuraMaster's `settings/PresetPicker.lua`),
shown once per profile while `seeded` is false (marked seen as it shows, held through combat) and on
demand from a bare `/rm preset`. Title **Choose a preset** with the settings and close marks, the
owner line, a LibKa0s dropdown of the six presets (`Simple - 4 containers`, ..., `Expert - 6 containers`, `Ka0s - 5 containers`), a one-line
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
**Sounds** entry is not listed for a `nameplates` or `nameplatesExceptTarget` container, and the rail heals to General when the
selection moves to one. No page draws a band preview: General's Preview section and the Band sets
page's band ribbon were removed (plan 2026-11-19 M8); `/rm bands` keeps its chat ribbon
(`NS.BandRibbon`, which only that verb calls now).

| Entry (page key) | Tabs | Rows |
|---|---|---|
| General (`containers`) | General, Position | Name, Enable this container; What it tracks: Unit, Band set, Friendly band set (both are this character's pick, `modules/BandSetChoice.lua`: Band set's first entry, **Default band set (<name>)**, is no pick and names the set this character then uses: its assignment on this profile, chosen with **Use for this character** on the Band sets page (R4-RM-01); only while none is written, its class set when the profile has one, else the container's own set unless that is another class's, else the first set that is no class's), then Duplicate container, Delete container… (confirmed) and Copy settings from. Position: Attach to, Frame strata and Frame level (every mode; Frame level 0 is Auto, 1 the lowest in the strata, up to 100), then the rows of the chosen placement only (`shownWhen`, options-ui-§22), read as AuraMaster's Position tab: what it attaches to's anchor point and This container anchor point side by side, then X and Y side by side. On the unit frame: Unit frames from, Frame name for a custom frame, **Pick on screen**, Unit frame anchor point, This container anchor point, X offset, Y offset. On screen: Screen anchor point, This container anchor point, X position, Y position. At the cursor: This container anchor point, X offset, Y offset. On the nameplate: Attach to part (Nameplate; Cast bar: EllesmereUI's cast bar, else the game's own, else the plate; or Cast bar while casting, else nameplate, which moves between the two as the unit's casts start and stop), Nameplate anchor point, This container anchor point, X offset, Y offset (and Friendly nameplates too for All nameplates and All nameplates except target); while unlocked a preview nameplate shows where the container sits on one |
| Display (`containers_display`) | Layout, Frame, Number, Text, Label, Dot, Spell chips | Direction, Spacing, Padding, Container scale, then Number and text on one line (`container.layout.joinText`, on by default: the number writes the band's label too, "28+ OOR", and the Text element takes no cell), Align (`container.layout.align`: Left, Center, Right) and Container opacity, Size (`container.layout.sizing`: Fit its content, or Fixed size) with Width and Height (grayed while it fits its content), then **Element order**: a LibKa0s-Widgets `ReorderList` shaped as MultiMeters' Columns list, one row per element (the `segment` handle, an on/off tick that writes the element's own `enabled` row, the name at the right); the elements turned on come first and only they drag (the list's `boundary`), the ones turned off sit dimmed below with no handle; a drop or a tick writes `container.elements.order` as the list shows it (options-ui-§18; on the CLI the row takes names, `number,text` putting those first); the composed border block with **Border opacity** (`container.frame.border.alpha`, 25% on a new container) as its extra, and the background pair (on for a new container); Show number and Format with the composed Font block; Show text label and Uppercase with the composed Font block; the caption naming the container (`container.label.*`, off by default): Show label, Label text (an EditBox that applies on Enter; empty shows the container's name), Position (Inside top, Outside top, Inside bottom, Outside bottom, Inside left, Outside left, Inside right, Outside right: inside sits beside the elements within the border and grows the container; outside sits beyond the border, `gap` px off its edge, and the container keeps the elements' size; `top`/`bottom`/`left`/`right` stored are the inside ones), Align (Left, Center, Right; shown for the tops and bottoms only), Gap (px), then the composed Font block (its face `Skin` = `""` stored, with the caption's color and Color from); Show dot, Shape, Size (px) and the composed Dot color pair, then **Style**: a tile per style (Plain, Matte, Glossy, Glowing, Neon, Gem), each the stored shape's art in that style, a click writing `container.elements.indicator.style` (a skipRender dropdown row on the CLI; grayed, and the tiles inert, while the shape is Bar or Spell icon); Show spell chips, Style, Size |
| Visibility (`containers_visibility`) | Visibility | Show (always, in combat, out of combat), Reaction, Hide with no unit, Out of combat opacity |
| Sounds (`containers_sounds`) | Sounds | Play band sounds, Sound channel |

Every color swatch's companion is the container's three-value **Color from** (band, fixed, class;
options-ui-§17), declared `classColorSource = "unit"`: a range container describes its unit.

Every composed block starts on the skin (LibKa0s v1.108.0, OptionsCompose minor 20; the owner's
R-2). Font flags lead with **From skin**, the default. Each swatch is followed by **Use the skin's
color** (`colorFromSkin`, on), read while Color from is Fixed color: the number, text and dot then
draw the skin's HUD text color, the caption its HUD label color, the border `bar.border` and the
background `bar.bg`; Band color and Class color are not changed by it (the band color is the range's
meaning, owner U-30). Font shadow is followed by **Use the skin's shadow** (`shadowFromSkin`, on; Font
shadow is grayed while it is on), and the border's style by **Use the skin's border** (`textureFromSkin`,
on: a skin with a real bar border draws it and grays Border style, thickness and Show border; under a
skin's None they stay the player's). The face takes no companion: its first value, Skin's font, is the
skin's own. The Dot tab's Style tiles wear the skin's input colors only with the Scope's Ignore
settings panel cleared, as the labels beside them do; it is on by default, and the tiles are stock.

## Band sets

The band set manager (RangeMaster#21, `docs/superpowers/specs/2026-11-25-band-set-manager-design.md`).

**The header** (`O.PageHeader`, one AceGUI Flow group: the banner holds at most three acts) is the
picker, then **New…**, **Duplicate**, **Copy bands from…** and **Delete…**. They act on the set whole,
so they sit above the tab strip (options-ui-§14) and none is on the General tab. Delete asks first, moves
the set's containers to the default set, and is disabled while the profile has one set.

**The picker is grouped.** Each group is led by a disabled row in the skin's heading color (AceGUI's
`SetList` takes one item type, so the groups are rows a click cannot choose). In the open list a group
row draws three points larger than a set, flush left, on a faint band of that same color (R5-RM-01),
and the New, Copy bands from and Restore dialogs' dropdowns dress theirs the same way:

| Group | Rows |
|---|---|
| Your band sets | every stored set in `bandSetOrder`: on a new profile its creator's set alone, then each set a character is assigned or the player makes (R4-RM-02); this character's assigned set `(default)` (R4-RM-01), one that differs from its preset `· modified` |
| Shipped presets · Classes | every `CLASS_KEYS` preset this client has (13 on Retail, 9 on WoW Forever, Hunter among them), each in its class color, yours `(your class)` |
| Shipped presets · General | Melee / Ranged, Caster 40, Healer |

A preset's value is `preset:<key>` (`NS.BandSets.PresetKeys`). Choosing one **views** it
(`NS.ViewPreset`, session state `NS.State.viewedPreset`, never stored and never a container's set).

**The origin line**, under the picker:

- A set of yours with an origin on this client (`set.origin`) reads `From the Paladin preset`, then
  `· modified (match rule, band 2 label and 1 more)` when `NS.BandSets.Diff` has entries, beside
  **Restore Paladin preset…**, enabled only while modified.
- A set with no origin, or one whose preset this client lacks (a Retail class key on WoW Forever), has no
  origin text: its line holds the character act alone (below), and without a character scope it has no
  line.
- A set of yours always ends the line with its character act (R4-RM-01; the owner, round 4: "One per
  character"): **Use for this character** makes it the band set this character uses on this profile,
  which every container without a band set of its own follows. A container whose Band set this character
  had on the set it used until then follows too: the v5 upgrade pinned every container's old set as the
  loading character's pick, so on an older profile those read as picks (other characters keep theirs; chat says
  `'<name>' is now this character's band set on this profile.`). On the set already assigned it reads
  **This character's band set**, disabled. A set with no origin shows the act beside `This character
  uses this band set.` or `This character uses <name>.` The page opens on the assigned set after a
  login or a profile change (the selection is session state, never stored). Without a character scope
  (the no-AceDB fallback) there is no act.
- A viewed preset reads `A shipped preset: read-only. Make it yours to use it on a container or to edit
  it.`, beside **Use this preset…** (the New dialog, prefilled with the preset and its name) and **Copy
  into a set of mine…** (Copy bands from, the preset as the source and a dropdown of your sets as the
  target).

**While a preset is viewed**, both tabs show its values with every control disabled, Duplicate, Copy
bands from and Delete are disabled and New… stays enabled. Every `bandSet.*` write (`/rm set`,
`/rm reset`, the header **Defaults**) is refused with `A shipped preset is being viewed, and it is
read-only: choose one of your band sets first (/rm bands lists them).` Choosing a set of yours, `/rm
bands N` or a profile change ends the view.

**The dialogs** are one companion window (`settings/BandSetDialogs.lua`: MODAL, toplevel, clamped,
close mark only, skinned; Escape, Cancel, the Settings panel closing and a profile change take it down).

| Dialog | Controls | Writes |
|---|---|---|
| New band set | Name (unique through `UniqueName`; it follows the start until typed in), then Start from: (•) A shipped preset, a dropdown of every preset (the classes in class order, then the general ones), starting on your class; ( ) A copy of one of my sets, a dropdown; ( ) Blank: one open-ended band; Create, Cancel | `Create(name, key)`, `Duplicate` then `Rename`, or `Create(name, {})`; the new set is selected |
| Copy bands from | Into (the current set, or a dropdown of yours from Copy into a set of mine…); From (your other sets, then every preset); Bands (always on), Sounds on enter (on), Match rule and unknown label and color (off); the summary, `Paladin's 4 bands are replaced by Mage's 5. Its name and the containers using it stay.`; Copy, Cancel | `CopyFrom(id, source, opts)`, never into itself |
| Restore Paladin preset | `Put 'Paladin' back to the Paladin preset. What changes:`, then one line per `Diff` entry (`Band 2 label: HOLY -> JUDGE`), eight at most, then `and N more`; Keep my sounds (on); Restore, Cancel | `RestorePreset(id, keepSounds)`; refused aloud when the set has no preset on this client or already matches it |

**Undo.** Before Copy or Restore the dialog takes `NS.BandSets.Snapshot()`, and the chat line names the
verb: `Restored 'Paladin' to the Paladin preset. /rm bands undo puts it back.` (or `Copied the bands of
'Mage' into 'Paladin'. ...`). `/rm bands undo` (`NS.UndoBandSets`) puts back only the set that was
written, so a set made, edited or deleted since is left as it is. One level, per profile, this session;
refused when that set has been deleted since. The addon and LibKa0s have no chat-link pattern, so the
Undo is the verb the line names, as `/rm preset undo` is after a preset.

**General**: Name, Match band by, and the Unknown range subsection (Unknown label, Unknown color, a
palette swatch with no class companion), then the containers using the set.
**Bands** (a host editor, with no band ribbon above it) is a side-tab group (`O.SideTabs`, the nav
rail's look drawn inside the content, 170 px wide): a rail on the left with one entry per band,
`1 MELEE · 0–5 yd` (place, label, span) led by a chip of the band's frame color and with the band's
heading as its tooltip, and beside it only the selected band's heading and controls; **Add band**
and **Remove band** share one row under the rail (Remove band acts on the selected band and is
disabled while the set has one band), then the sounds note. The rail is the tab's second level, in the scroll
(options-ui-§13: one tab divided by like subjects; no third level). The band selected is session
state (`NS.State.selectedBand`, never persisted): it survives a redraw, **Add band** selects the new
band, **Remove band** selects its neighbor (the band after it, else the one before), an index the set
no longer has clamps to the last band, and another band set opens on band 1. A rail click is refused
in combat by the library. The selected band's controls: **Defined by** first (Yards, Spell, Dead zone,
Beyond the last spell band; written through `NS.BandSets.SetBandRule`), then the yard slider, Label,
Frame / Text / Dot color and Sound on enter. A spell
band adds **Role** (Melee, Ranged, Friendly, then the class's range tiers, "10 yd tier" to "30 yd tier", `core/Constants.lua` `TIER_ROLES`), **Spell IDs** (comma-separated, empty for the class's
anchors; a part that is not a whole ID refuses the entry aloud) and a read-out note naming the spell a
tick asks (`NS.Range.AnchorFor`) and the range the client reports ("Now: Arcane Shot (3044), 8-41 yd",
"melee range", "range not reported"), or "Not learned: using 5-30 yd" when nothing resolves. On a band
with a rule the slider reads **Fallback (yards)**; a yard band keeps **Up to (yards)**. A band's heading
carries its rule ("(Spell: Ranged)", "(Dead zone)", "(Beyond the last spell band)"). The page redraws on
`BANDSETS_CHANGED` and on `ANCHORS_CHANGED` (a talent, form, level or spell change, a band's own Spell IDs
list included), coalesced to the next frame. The bands are ordered
by their edges (`modules/BandSets.lua` normalizes every write), so a band moves by moving its edge and
there is no reorder control (options-ui-§18 binds a list whose order is the setting; this one's is
derived). The band colors are palette swatches (options-ui-§17's one exemption): each identifies a
band, so none takes a class-color companion; class color is the container's own Color from. A band's
controls are path-less (options-ui-§13 host editor), so `/rm get|set` does not reach them; every
band-set name is unique (`NS.BandSets.UniqueName`), and a name two sets still share (a hand-edited
SavedVariables file) is refused by `/rm bands` as ambiguous. The header **Defaults** restores the match rule and the unknown label and
color; the name and the bands are kept (its tooltip points to Restore preset for the bands), and it is
refused while a preset is viewed.

## The launcher

One LibDataBroker launcher object registered with LibDBIcon (`core/LauncherSetup.lua`), labeled
`Ka0s Range Master`, with the 128 logo. Left-click opens the settings; right-click opens the menu:
**Enabled**, **Locked**, **Test mode**, **Sim mode**, each the matching slash verb's own handler, and
the library's *Open skin selector*. While disabled, every entry but Enabled is grayed. There is no
Show window entry and no key binding: the addon has no primary window.
