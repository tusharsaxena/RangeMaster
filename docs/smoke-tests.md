# Smoke tests — Ka0s Range Master

The in-client checks the headless suite cannot make. Run them from a clean `/reload`, with debug
logging off unless a check says to turn it on. Record each check on its `Result:` line (date, client,
pass or the failure seen). IDs are `<THEME>-<n>`; a new check takes the next free number in its theme,
and a retired number is never reused. Run every theme on **both clients**, Retail and WoW Forever,
unless a check names one.

## Index

| ID range | Theme | What it covers |
|---|---|---|
| INSTALL-1..3 | Install | load, reload, first run and the first-run skin picker |
| SLASH-1..4 | Slash | help, the schema CLI, disabled refusals |
| PANEL-1..4 | Panel | the landing page, General's two tabs, combat lock |
| PROFILE-1..2 | Profiles | the Profiles page and `/rm profile` |
| STATE-1..3 | State | enable and disable, the latch, the launcher menu |
| MODES-1..4 | Modes | Test mode and Sim mode: start, refuse in combat, end on combat |
| COMBAT-1 | Combat | the settings panel under combat lockdown |
| DIAG-1..3 | Diagnostics | the console, the report, the perf verb |
| DEGRADED-1 | Degraded | the library-absent install |
| LOC-1 | Non-English client | a deDE or frFR client |
| RANGE-1..5 | Range engine | brackets, unknown, the Forever ladder, the ticker's rate and stop, the seed spells |
| DRAW-1..5 | Containers | brackets drawn, unknown gray, elements and order, the skin face, disable |
| ANCHOR-1..8 | Anchors | screen drag, unit frames (Blizzard, EllesmereUI, custom, missing), combat, nameplates, cursor, the picker |

The remaining range-display themes (BANDS, SOUND) join with plan Tasks 7 and 8.

## Before you start

Install the addon folder as `Interface\AddOns\RangeMaster`. Use a character with at least one ranged
spell. Keep the chat frame visible; every line the addon prints starts with a cyan `[RM]`.

## Install

- **INSTALL-1. Loads on both clients.** Log in on Retail, then on WoW Forever, with only Range Master
  enabled → it appears in the AddOns list with its crosshair icon; no Lua error. Result:
- **INSTALL-2. First-run skin picker.** On a new profile, log in → two seconds in, the skin picker
  shows with its eye lit, and Test mode is on while it is up; closing it turns Test mode back off, and
  it does not show again on the next `/reload`. Result:
- **INSTALL-3. Reload is quiet.** `/reload` → no chat line from the addon, no error. Result:

## Slash

- **SLASH-1. Help.** `/rm help` → the version line and every verb, `/rangemaster` named as an alias.
  Result:
- **SLASH-2. The schema CLI.** `/rm list` → `Available settings`, `[general]`, then `path = value` rows;
  `/rm set scale 1.5` echoes `scale = 1.50x`; `/rm reset scale` returns it. Result:
- **SLASH-3. Disabled refusals.** `/rm disable`, then `/rm test` → one line, `Ka0s Range Master is
  disabled — enable it with /rm enable`; `/rm list` still answers; `/rm enable` restores. Result:
- **SLASH-4. Bare `/rm`.** `/rm` → the settings panel opens, enabled or disabled. Result:

## Panel

- **PANEL-1. Landing page.** Settings → AddOns → Ka0s Range Master → the logo, the Notes line and the
  slash command list; reopening does not stack a second copy. Result:
- **PANEL-2. Master controls.** General → **Master controls** is the first tab, **Skin** the second;
  the rows read Enable Range Master, General visibility, Master scale, Master opacity, Lock frame,
  Debug console, Minimap button, Test mode, Sim mode, then Reset position and Reset all settings.
  Result:
- **PANEL-3. Defaults.** Change Master scale, untick Minimap button, press **Defaults** → scale is back
  to 1.00x and the minimap button stays hidden. Result:
- **PANEL-4. Tooltips.** Hover a row, a tab and the Defaults button near each screen edge → each
  tooltip sits beside the panel (rows) or above its control (chrome), never on the cursor. Result:

## Profiles

- **PROFILE-1. Switch.** Create a profile on the Profiles page, untick Enable Range Master there, switch
  back to Default → the addon is enabled again (the latch follows the profile). Result:
- **PROFILE-2. `/rm profile`.** `/rm profile` lists profiles; `/rm profile Default` switches; an
  unknown name is refused with the list and nothing is created. Result:

## State

- **STATE-1. Disable stands down.** Turn debug logging on (`/rm debug on`), `/rm disable` → a
  `[Lifecycle] stood down` line in the console; `/rm diagnostics` shows `stood down` in its events
  section. Result:
- **STATE-2. Launcher left-click.** Click the minimap button → the settings open, enabled or disabled.
  Result:
- **STATE-3. Launcher menu.** Right-click → the menu reads Enabled, Locked, Test mode, Sim mode; while
  disabled every entry but Enabled is grayed, and Enabled turns the addon back on. Result:

## Modes

- **MODES-1. Test mode.** Tick **Test mode** → `[RM] Test mode on` style confirmation in the console
  with debug on (`[Mode] test on (settings)`); `/rm test` turns it off. Result:
- **MODES-2. Sim mode.** `/rm sim` → Sim mode on; the launcher menu shows it checked; `/rm sim off`
  ends it. Result:
- **MODES-3. Refused in combat.** Enter combat (attack a training dummy), then `/rm test` → one gray
  line `Cannot start a preview mode during combat.`; nothing turns on. Result:
- **MODES-4. Combat ends both.** Start Test mode and Sim mode, then enter combat → both turn off at
  the pull (the boxes untick on an open panel). Result:

## Combat

- **COMBAT-1. Panel lock.** Enter combat, open the settings from the AddOns sidebar → the page is
  covered with one gray notice, the window stays open, and it draws when combat ends. `/rm config` in
  combat is refused with a gray line. Result:

## Diagnostics

- **DIAG-1. Console.** `/rm debug` → the console window opens with Copy, Clear and close marks drawn
  (not a multiplication sign); logging stays off until `/rm debug on`. Result:
- **DIAG-2. Report.** `/rm diagnostics` → one chat line naming the line count; the console holds the
  report between `Ka0s Range Master diagnostics` markers, sections state, lifecycle, settings, events,
  rejected and ui, and no `section ... failed` line. Result:
- **DIAG-3. Perf.** `/rm perf` → the step panel opens, its close mark drawn; a start and a cancel leave
  no hold (`/rm diagnostics` lifecycle shows `holds: none`). Result:

## Degraded

- **DEGRADED-1. Library absent.** Rename `libs/LibKa0s` and `/reload` → one chat line saying the LibKa0s
  library is missing; `/rm help` still lists the verbs; `/rm list` names the missing library; no Lua
  error. Put the folder back afterward. Result:

## Non-English client

The addon's own seams that a client language could reach, enumerated from the scaffold's code:

- It reads no localized `_G` string (no chat format, `ITEM_*` or tooltip constant).
- It matches or parses no tooltip line.
- It keys off no display string where an id exists: the client is asked through
  `LibKa0s-Compat-1.0`, and the range engine (plan Task 2) will key its spells by spell id and its
  classes by class token, never by name.
- It writes no header, token or key another tool parses, apart from the diagnostics report's markers,
  which carry the brand in English on every client by design.

- **LOC-1. A deDE or frFR client.** Log in on a German (deDE) or French (frFR) client, open the
  settings, run `/rm help`, `/rm list`, `/rm test` and `/rm diagnostics`. Pass: every line the addon
  prints is the English source text (the addon ships English only, and `NS.L` falls back to the key),
  the settings rows read in English, and the report's markers name `Ka0s Range Master`. Fail: a Lua
  error on load or on any verb; a `%s` or `%d` left unformatted in a line (a format string that did
  not match); a blank label where a row should be; or a missing report section. Signing off without
  the client: the headless suite's `tests/test_locale.lua` (every `L["…"]` key defined, every value
  its own key) and `tests/test_compat.lua` (no client decided from anything but LibKa0s-Compat) stand
  in for the string half, and INSTALL-1 on an English client covers the load; the client is the only
  witness for a Blizzard global the client localizes that a later task starts reading, so when the
  range engine lands this check is re-run on a deDE client. Result:

## Range engine

RANGE-1 to RANGE-4 are run through a target container (the Containers section below says how to make
one). RANGE-5 needs only the chat frame.

- **RANGE-1. Brackets.** Target a training dummy and walk away from it → the bracket widens in steps
  (`0–5`, `5–8`, … `40+`), never a single exact yard; it never flashes out of range while you stand
  still. Result:
- **RANGE-2. Unknown, not out of range.** In combat, target a friendly player and walk away → the
  bracket either follows (spell checks) or reads unknown `?`; it never reads out of range while the
  player stands next to you. Result:
- **RANGE-3. Forever ladder (WoW Forever only).** On a character with no ranged spell (a fresh
  warrior), target a dummy → brackets land on 10, 20, 28, 30 and 35 yd edges only. A Tauren's
  edges are 8 and 25 yd for the two interact rungs. Result:
- **RANGE-4. Ticker.** `/rm debug on`, `/rm perf`: with a container on target the `ticker.tick`
  bucket fills; clear the target → it stops filling (the ticker stopped); enter combat → it fills
  twice as fast. Result:
- **RANGE-5. Seed spells resolve.** For your class, paste the `chips` and `ladder` IDs from
  `defaults/SpellSeeds.lua` (this client's block) into
  `/run for _, id in ipairs({ 133, 116 }) do print(id, C_Spell.GetSpellName(id)) end` → every ID
  prints a spell name, none prints `nil`. Result:

## Containers

The renderer (plan Task 5). Until the settings pages land (plan Task 8), apply a preset from chat:
`/run LibStub("AceAddon-3.0"):GetAddon("RangeMaster").Presets.Apply("simple")` (the addon object is
the namespace, so `.CM.Create("target")` makes a single container the same way).

- **DRAW-1. Brackets, never a distance.** Target a dummy and walk away → the number steps through
  brackets (`0–5`, `5–20`, …) and reads `40+` past the last check; the border and the number change
  color as the band does. Result:
- **DRAW-2. Unknown is gray.** Target a unit the client will not range (far out of sight, or a
  friendly player in combat with no friendly spell) → `?` in gray, never the out-of-range red. Result:
- **DRAW-3. Elements and order.** Turn on text, a dot and spell chips, reorder them, switch the
  direction to column → every element draws, in that order, the frame closes around them. Every
  shape (dot, ring, square, diamond, triangle, bar, icon) draws without a missing-texture green.
  Result:
- **DRAW-4. Skin face.** With an element's font left on the skin's, switch the skin (General > Skin)
  → the number's face follows at once, with no reload. Result:
- **DRAW-5. Disable.** `/rm disable` → every container disappears; `/rm enable` → they come back.
  Result:

## Anchors

The anchors (plan Task 6). Set a container's mode from chat until the Containers page lands (plan
Task 8): `/run local a = LibStub("AceAddon-3.0"):GetAddon("RangeMaster"); local c = a.CM.Get(1);
c.anchor.mode = "frame"; a.CM.RequestApply()`. Run each on Retail and on WoW Forever.

- **ANCHOR-1. Screen drag.** `/rm unlock` → a strip shows above each screen container; drag one, then
  `/reload` → it is where it was dropped. `/rm lock` hides the strips; in combat a drag does not
  start. `/rm resetposition` puts screen containers back near the center. Result:
- **ANCHOR-2. Blizzard frames.** Target, focus and pet containers on provider `blizzard` sit on
  TargetFrame, FocusFrame and PetFrame (Forever: FocusFrame only if the client has focus). Result:
- **ANCHOR-3. EllesmereUI frames.** With EllesmereUI Unit Frames enabled and its target, focus and pet
  frames on, provider `ellesmere` → each sits on EllesmereUI's frame from login, with no `/reload`.
  With the addon off, the container is hidden and `/rm debug` shows one `[Anchor]` line. Result:
- **ANCHOR-4. Combat.** Enter combat with a frame container waiting for its frame (a custom name of a
  frame that loads late) → no `ADDON_ACTION_BLOCKED`; it attaches after combat. Result:
- **ANCHOR-5. Own nameplate.** A target container in `nameplate` mode sits under the target's plate,
  follows a retarget, hides when the plate leaves the screen, and comes back with it. Result:
- **ANCHOR-6. All nameplates.** A `nameplates` container draws on every hostile plate in a pack and on
  none of the friendly ones; with `includeFriendly` on, friendly plates too. Pulling a pack and
  killing it (plates recycling fast) raises no error. In an instance, friendly plates (forbidden)
  draw nothing and raise nothing. On Forever, a plate's container appears on the plate, not at the
  screen's corner, when the plate first shows. Result:
- **ANCHOR-7. Cursor.** A mouseover container on `cursor` (or on a `blizzard` unit frame) follows the
  cursor while hovering a unit and hides when hovering nothing; with the UI scale changed, it stays
  on the cursor. Result:
- **ANCHOR-8. Frame picker.** `/run LibStub("AceAddon-3.0"):GetAddon("RangeMaster").FramePicker.Start(print)`
  → an outline follows the named frame under the cursor; left click prints its name; right click or
  Escape cancels; entering combat ends it with no error; starting it in combat prints one gray line.
  Result:

## Pending sign-off

| ID | Origin | Why it is owed |
|---|---|---|
| every check above | the v0.1.0 scaffold, 2026-11-18 | no client pass recorded yet |
| RANGE-1..5 | the v0.1.0 range engine (plan Task 2), 2026-11-18 | the Forever interact distances and the seed IDs are unconfirmed in a client |
| DRAW-1..5 | the v0.1.0 renderer (plan Task 5), 2026-11-18 | no container has been drawn in a client yet |
| ANCHOR-1..8 | the v0.1.0 anchors (plan Task 6), 2026-11-18 | no anchor has been seen in a client yet; the EllesmereUI names are read from its source, not a running client |
