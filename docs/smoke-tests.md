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

The range-display themes (RANGE, ANCHOR, BANDS, SOUND, NAMEPLATE) join with plan Tasks 2 to 8.

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

## Pending sign-off

| ID | Origin | Why it is owed |
|---|---|---|
| every check above | the v0.1.0 scaffold, 2026-11-18 | no client pass recorded yet |
