# Smoke tests — Ka0s Range Master

The in-client checks the headless suite cannot make. Run them from a clean `/reload`, with debug
logging off unless a check says to turn it on. Record each check on its `Result:` line (date, client,
pass or the failure seen). IDs are `<THEME>-<n>`; a new check takes the next free number in its theme,
and a retired number is never reused. Run every theme on **both clients**, Retail and WoW Forever,
unless a check names one. The anchors are run as a matrix, one result per mode and client
([Anchors](#anchors)).

## Index

| ID range | Theme | What it covers |
|---|---|---|
| INSTALL-1..5 | Install | load, reload, the first-run prompts, an upgrade keeping stored looks, the one move onto the skin |
| SLASH-1..8 | Slash | help, the schema CLI, disabled refusals, the container, band-set, pick and preset verbs |
| PANEL-1..4 | Panel | the landing page, General's three tabs, Defaults, tooltips |
| PROFILE-1..3 | Profiles | the Profiles page, `/rm profile`, a profile's own containers |
| STATE-1..3 | State | enable and disable, the latch, the launcher menu |
| MODES-1..8 | Modes | Test mode and Sim mode: start, refuse in combat, end on combat, placeholders, the sweep, the step panel on every start |
| COMBAT-1 | Combat | the settings panel under combat lockdown |
| DIAG-1..4 | Diagnostics | the console, the report, the perf verb, the copy window's close-only title bar |
| DEGRADED-1 | Degraded | the library-absent install |
| LOC-1 | Non-English client | a deDE or frFR client |
| RANGE-1..18 | Range engine | brackets, unknown, the Forever ladder, the ticker's rate and stop, the seed spells; the anchor probes: reported ranges under talents, rank IDs, the talent event, overrides, Auto Shot unarmed |
| DRAW-1..12 | Containers drawn | brackets drawn, unknown gray, elements and order, the skin face, disable, the Bar dot's border and gloss, Fixed colors, outline and shadow, the border and the spell chips following the skin, Class mode in test mode, High Contrast's HUD shadow |
| CONT-1..14 | Containers page | New container (no band preview), the rail, Position, Duplicate / Delete / Copy settings from, Defaults, Color from, the Dot tab and its Style tiles, Border opacity, the caption's positions, the caption's styling, one line, the skin companion rows, the Style tiles' Scope, the frame picker's label |
| BANDS-1..11 | Band sets page | the picker, the Bands editor (no band ribbon), shared sets, the friendly override, the unknown label; spell bands: the rule controls, the read-out, the owner's Hawk Eye case, the dead zone, the v1 -> v2 conversion, the band rail |
| PRESET-1..5 | Presets | the first-run picker, Apply on an empty profile, Apply over containers with Undo, what each of the six shows, the dropdown's selected row |
| ANCHOR-1..13 | Anchors | every mode on both clients: screen, unit frames (Blizzard, EllesmereUI, custom, missing), own nameplate, all nameplates, cursor, the picker, all nameplates except target, the drag strip's marks, the cast bar part, Frame strata and Frame level on a plate, the preview nameplate, the drag strip's right-click |
| VIS-1..3 | Visibility | combat and reaction rules, out-of-combat opacity, the master rows |
| SOUND-1..2 | Sounds | the debounced band sound, none on nameplates |

## Before you start

Install the addon folder as `Interface\AddOns\RangeMaster`. Use a character with at least one ranged
spell, and stand near a training dummy. Keep the chat frame visible; every line the addon prints
starts with a cyan `[RM]`. Most checks need a container: apply a preset (General → Presets, or
`/rm preset simple`) or make one with **New container** on the Containers page or `/rm new`.

## Install

- **INSTALL-1. Loads on both clients.** Log in on Retail, then on WoW Forever, with only Range Master
  enabled → it appears in the AddOns list with its crosshair icon; no Lua error. Result: PASS (owner, 2026-11-24, both clients)
- **INSTALL-2. First-run prompts, one at a time.** On a new profile, log in → the preset picker
  window shows first (**Choose a preset**: dropdown, Apply / Not now); the skin picker does not show
  beside it.
  Press **Not now** → the skin picker shows with its eye lit, and Test mode is on while it is up;
  closing it turns Test mode back off. Neither shows again on the next `/reload`. Result: PASS (owner, 2026-11-24, both clients)
- **INSTALL-3. Reload is quiet.** `/reload` → no chat line from the addon, no error. Result: PASS (owner, 2026-11-24, both clients)
- **INSTALL-4. An upgrade keeps the look.** With containers made on a build before the frame
  defaults (schema v0: no Border opacity, no dot style), and a second profile holding some too,
  install this build and log in → every stored container looks as it did: a full-opacity border, no
  background where it had none, the plain dot at the size it had (the art fills its box as the old
  dot did); Frame → Border reads Border opacity 100% and Dot →
  Style has Plain picked. Switch to the other profile → the same. A container made now takes the
  new look (25% border, background, matte). Result: PASS (owner, 2026-11-24, both clients)
- **INSTALL-5. An upgrade moves the untouched looks onto the skin, once.** On a build before LibKa0s
  v1.108.0, keep two containers: one as it was made, the other with its Number's Font flags on Thick
  outline, its caption on (Color from Fixed) with a red swatch and its Font shadow ticked. Install this
  build, log in, pick WoW Default (General → Skin) → the first container's caption takes the skin's
  label gold, its border the skin's tooltip edge, its text the skin's outline; the second keeps its
  thick outline, red caption and shadow, and its Display rows read Use the skin's color and Use the
  skin's shadow unticked. Untick Use the skin's color on the first container's caption, `/reload` →
  it stays unticked (the move ran once). A second profile moves the same way the first time it is
  loaded. Result:

## Slash

- **SLASH-1. Help.** `/rm help` → the version line and every verb, `/rangemaster` named as an alias.
  Result: PASS (owner, 2026-11-24, both clients)
- **SLASH-2. The schema CLI.** `/rm list` → `Available settings`, `[general]`, then `path = value` rows;
  `/rm set scale 1.5` echoes `scale = 1.50x`; `/rm reset scale` returns it. Result: PASS (owner, 2026-11-24, both clients)
- **SLASH-3. Disabled refusals.** `/rm disable`, then `/rm test` → one line, `Ka0s Range Master is
  disabled — enable it with /rm enable`; `/rm list` still answers; `/rm enable` restores. Result: PASS (owner, 2026-11-24, both clients)
- **SLASH-4. Bare `/rm`.** `/rm` → the settings panel opens, enabled or disabled. Result: PASS (owner, 2026-11-24, both clients)
- **SLASH-5. Container verbs.** `/rm new focus` → a Focus container is made and selected;
  `/rm containers` lists `1. Focus (focus, screen)` with a `*` on the selected one; `/rm new boss1` →
  the usage line, nothing made; `/rm select 1` and `/rm select focus` both select it; `/rm delete 1`
  asks first (the same popup as the panel's Delete) and, on Yes, deletes it and selects its neighbor. Result: PASS (owner, 2026-11-24, both clients)
- **SLASH-6. `container.` paths.** With a container selected, `/rm set container.unit pet` → the
  Containers page (if open) shows Pet, and the container tracks the pet; `/rm get container.unit`
  reads `pet`. Delete every container, then `/rm set container.unit focus` → refused with a line
  naming `/rm new`. Result: PASS (owner, 2026-11-24, both clients)
- **SLASH-7. Band-set verbs.** `/rm bands` → the band sets, the selected one marked, then the
  selected set's ribbon; `/rm bands 2` selects the second; `/rm set bandSet.unknown.label ??` changes
  its unknown label; `/rm bands nosuchset` → `No band set 'nosuchset'`. Result: PASS (owner, 2026-11-24, both clients)
- **SLASH-8. Preset, pick and position verbs.** `/rm preset` opens the preset picker. On a profile
  with no containers, `/rm unlock` prints a line pointing at `/rm preset`.
  `/rm preset simple` on a profile with containers →
  the same confirm as the Presets tab; `/rm preset undo` puts them back; `/rm preset nope` → the usage
  line. `/rm pick` starts the frame picker for the selected container (ANCHOR-8). `/rm resetposition`
  → every free-on-screen container moves back near the center and the line says how many. Result: PASS (owner, 2026-11-24, both clients)

## Panel

- **PANEL-1. Landing page.** Settings → AddOns → Ka0s Range Master → the logo, the Notes line and the
  slash command list; reopening does not stack a second copy. The sidebar lists General, Containers,
  Band sets and Profiles under it, in that order. Result: PASS (owner, 2026-11-24, both clients)
- **PANEL-2. General's tabs.** General → **Master controls** is the first tab, **Presets** the second
  and **Skin** the third; Master controls' rows read Enable Range Master, General visibility, Master
  scale, Master opacity, Lock frame, Debug console, Minimap button, Test mode, Sim mode, then Reset
  position and Reset all settings. Result: PASS (owner, 2026-11-24, both clients)
- **PANEL-3. Defaults.** Change Master scale, untick Minimap button, press **Defaults** → scale is back
  to 1.00x and the minimap button stays hidden. Result: PASS (owner, 2026-11-24, both clients)
- **PANEL-4. Tooltips.** Hover a row, a tab and the Defaults button near each screen edge → each
  tooltip sits beside the panel (rows) or above its control (chrome), never on the cursor. Result: PASS (owner, 2026-11-24, both clients)

## Profiles

- **PROFILE-1. Switch.** Create a profile on the Profiles page, untick Enable Range Master there, switch
  back to Default → the addon is enabled again (the latch follows the profile). Result: PASS (owner, 2026-11-24, both clients)
- **PROFILE-2. `/rm profile`.** `/rm profile` lists profiles; `/rm profile Default` switches; an
  unknown name is refused with the list and nothing is created. Result: PASS (owner, 2026-11-24, both clients)
- **PROFILE-3. Containers are per profile.** Apply Simple on Default, create and switch to a new
  profile → no container shows and the preset welcome popup is offered; switch back → the four
  Simple containers return, and **Undo last preset** prints `No preset to undo.` (the switch dropped
  the slot). Result: PASS (owner, 2026-11-24, both clients)

## State

- **STATE-1. Disable stands down.** Turn debug logging on (`/rm debug on`), `/rm disable` → a
  `[Lifecycle] stood down` line in the console, and every container disappears; `/rm diagnostics`
  shows `stood down` in its events section. Result: PASS (owner, 2026-11-24, both clients)
- **STATE-2. Launcher left-click.** Click the minimap button → the settings open, enabled or disabled.
  Result: PASS (owner, 2026-11-24, both clients)
- **STATE-3. Launcher menu.** Right-click → the menu reads Enabled, Locked, Test mode, Sim mode and
  Open skin selector; while disabled every entry but Enabled is grayed, and Enabled turns the addon
  back on. Result: PASS (owner, 2026-11-24, both clients)

## Modes

- **MODES-1. Test mode.** With debug logging on, tick **Test mode** → a `[Mode] test on (settings)`
  line in the console and every container shows `20–25`; `/rm test` turns it off. Result: PASS (owner, 2026-11-24, both clients)
- **MODES-2. Sim mode.** `/rm sim` → Sim mode on; the launcher menu shows it checked; `/rm sim off`
  ends it. Result: PASS (owner, 2026-11-24, both clients)
- **MODES-3. Refused in combat.** Enter combat (attack a training dummy), then `/rm test` → one gray
  line `Cannot start a preview mode during combat.`; nothing turns on. Result: PASS (owner, 2026-11-24, both clients)
- **MODES-4. Combat ends both.** Start Test mode, then Sim mode, then enter combat → both turn off at
  the pull (the boxes untick on an open panel), and the displays read the live range again. Result: PASS (owner, 2026-11-24, both clients)
- **MODES-5. Placeholders everywhere.** With no target, apply the Expert preset and tick **Test
  mode** → every container shows `20–25` with an amber `TEST` strip on its top edge: the four free
  on screen, the own-plate one and the all-nameplates one (no plate on screen) at their screen points,
  the in-combat ones out of combat. Untick → each goes back to what its rules say. Result: PASS (owner, 2026-11-24, both clients)
- **MODES-6. The sweep.** `/rm sim` → the `Range Master - SIM` step panel opens and every container
  walks `0–1` out to `50+` and back over about 20 s, each band's color in turn, with a cyan `SIM`
  strip; the Expert preset's target plays its out-of-range chime once on the way out. At the end
  the panel closes and Sim mode unticks. `/rm sim status`, `/rm sim pause`, `/rm sim resume` and
  `/rm sim stop` answer in chat. Result: PASS (owner, 2026-11-24, both clients)
- **MODES-7. One at a time.** With Sim mode running, `/rm test` → one gray line `Cannot start Test
  mode while Sim mode runs.` Result: PASS (owner, 2026-11-24, both clients)
- **MODES-8. Every start shows the step panel (FB2-RM-01, LibKa0s v1.113.0, Sim minor 5;
  preview-mode, standard v2.120.0).** Start the sweep each of these ways, letting it end (or
  `/rm sim stop`) between them: `/rm sim`, `/rm sim on`, `/rm sim start sweep`, the Master controls
  **Sim mode** box, the launcher's right-click **Sim mode** entry, and `/rm sim panel` then the
  panel's own **Start** row → every time the `Range Master - SIM` step panel opens with the sweep
  running, and it carries no close mark (Escape leaves it up). Mid-run, `/rm sim restart` → the
  panel is still up and the sweep starts over. **Fail:** a sweep running with no step panel, or a
  close mark on it while it runs. Result:

## Combat

- **COMBAT-1. Panel lock.** Enter combat, open the settings from the AddOns sidebar → the page is
  covered with one gray notice, the window stays open, and it draws when combat ends. `/rm config` in
  combat is refused with a gray line. Result: PASS (owner, 2026-11-24, both clients)

## Diagnostics

- **DIAG-1. Console.** `/rm debug` → the console window opens with Copy, Clear and close marks drawn
  (not a multiplication sign); logging stays off until `/rm debug on`. Result: PASS (owner, 2026-11-24, both clients)
- **DIAG-2. Report.** `/rm diagnostics` → one chat line naming the line count; the console holds the
  report between `Ka0s Range Master diagnostics` markers, sections state, lifecycle, settings, events,
  rejected and ui, and no `section ... failed` line. Result: PASS (owner, 2026-11-24, both clients)
- **DIAG-3. Perf.** `/rm perf` → the step panel opens, its close mark drawn; a start and a cancel leave
  no hold (`/rm diagnostics` lifecycle shows `holds: none`). Result: PASS (owner, 2026-11-24, both clients)
- **DIAG-4. The copy window is a companion: close only (FB-RM-01, LibKa0s v1.112.0; standalone-windows
  *A companion window carries no settings mark*, standard v2.119.0).** `/rm debug`, then its Copy mark
  → the copy window's title bar carries the close mark alone, no gear; the console behind it still
  carries its gear. The close mark closes the copy window and leaves the console up. **Fail:** a gear on
  the copy window, a blank mark, or a Lua error naming a file under `libs/LibKa0s/`. Result:

## Degraded

- **DEGRADED-1. Library absent.** Rename `libs/LibKa0s` and `/reload` → one chat line saying the LibKa0s
  library is missing; `/rm help` still lists the verbs; `/rm list` names the missing library; no Lua
  error. Put the folder back afterward. Result: PASS (owner, 2026-11-24, both clients)

## Non-English client

The addon's own seams that a client language could reach, enumerated from the code:

- It reads no localized `_G` string (no chat format, `ITEM_*` or tooltip constant). The only `_G`
  reads are frame lookups by global name (`modules/FrameProviders.lua`, the Sim step panel), and a
  frame's global name is not localized.
- It matches or parses no tooltip line.
- It keys off no display string where an id exists: the client is asked through
  `LibKa0s-Compat-1.0`, spells are keyed by spell id (`defaults/SpellSeeds.lua`) and classes by class
  token. A spell's name is read only beside its id, for the Sim sweep's range, and its icon for the
  chips; neither is compared with a string.
- The one name lookup is the Expert preset reusing a band set called `Healer`, which is this
  addon's own English string, the same on every client.
- It writes no header, token or key another tool parses, apart from the diagnostics report's markers,
  which carry the brand in English on every client by design.

- **LOC-1. A deDE or frFR client.** Log in on a German (deDE) or French (frFR) client, open the
  settings, run `/rm help`, `/rm list`, `/rm test`, `/rm preset simple` and `/rm diagnostics`, and
  target a dummy. Pass: every line the addon prints is the English source text (the addon ships
  English only, and `NS.L` falls back to the key), the settings rows read in English, the containers
  draw a bracket and the spell chips their icons, and the report's markers name `Ka0s Range Master`.
  Fail: a Lua error on load or on any verb; a `%s` or `%d` left unformatted in a line (a format
  string that did not match); a blank label where a row should be; a chip with no icon; or a missing
  report section. Signing off without the client: the headless suite's `tests/test_locale.lua`
  (every `L["…"]` key defined, every value its own key) and `tests/test_compat.lua` (no client
  decided from anything but LibKa0s-Compat) stand in for the string half, and INSTALL-1 on an English
  client covers the load; the client is the only witness for the spell data a localized client
  returns. Result: PASS (owner, 2026-11-24, both clients)

## Range engine

RANGE-1 to RANGE-4 are run through a target container. RANGE-5 needs only the chat frame.

- **RANGE-1. Brackets.** Target a training dummy and walk away from it → the bracket widens in steps
  (`0–5`, `5–8`, … `40+`), never a single exact yard; it never flashes out of range while you stand
  still. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-2. Unknown, not out of range.** In combat, target a friendly player and walk away → the
  bracket either follows (spell checks) or reads unknown `?`; it never reads out of range while the
  player stands next to you. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-3. Forever ladder (WoW Forever only).** On a character with no ranged spell (a fresh
  warrior), target a dummy → brackets land on 10, 20, 28, 30 and 35 yd edges only. A Tauren's
  edges are 8 and 25 yd for the two interact rungs. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-4. Ticker.** `/rm debug on`, `/rm perf`: with a container on target the `ticker.tick`
  bucket fills; clear the target → it stops filling (the ticker stopped); enter combat → it fills
  twice as fast. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-5. Seed spells resolve.** For your class, paste the `chips` and `ladder` IDs from
  `defaults/SpellSeeds.lua` (this client's block) into
  `/run for _, id in ipairs({ 133, 116 }) do print(id, C_Spell.GetSpellName(id)) end` → every ID
  prints a spell name, none prints `nil`. Result: PASS (owner, 2026-11-24, both clients)

RANGE-6 to RANGE-11 are the anchor probes of the dynamic-bands plan (2026-11-19, D7): each answers a
question the headless suite cannot, and the answer is written on the `Result:` line as printed. Target
a training dummy for each. The spell IDs are the anchors in `defaults/SpellSeeds.lua` (`anchors`).

- **RANGE-6. Reported range under Hawk Eye (WoW Forever, Hunter).** With Hawk Eye at 0/3, run
  `/dump C_Spell.GetSpellInfo(3044).maxRange, C_Spell.GetSpellInfo(75).maxRange`; spend all three
  points and run it again → write both pairs down. 35, 35 then 41, 41 means the client reports the
  talented range; 35 both times means it reports the base range only, and the Bands page read-out
  shows the base number while the band itself still follows the spell. Result: 2026-11-19, the
  owner's level-27ish hunter at Hawk Eye 3/3 printed `41` for both (0/3 not measured): WoW Forever
  reports the talented range. Pass.
- **RANGE-7. Auto Shot reaches 41 yd with Hawk Eye (WoW Forever, Hunter).** Hawk Eye 3/3, stand about
  38 yd from the dummy (the bracket reads `35–40`) and run `/dump C_Spell.IsSpellInRange(75, "target")`
  → `true`; with Hawk Eye 0/3 at the same spot → `false`. This is the answer the AUTO band rests on.
  Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-8. Rank IDs (WoW Forever).** On a hunter who has learned Arcane Shot rank 2, run
  `/dump C_Spell.GetSpellInfo("Arcane Shot").spellID` (the current rank's ID), then
  `/dump C_SpellBook.IsSpellKnown(3044), C_Spell.IsSpellInRange(3044, "target")` and the same with the
  printed ID, in range of the dummy → write down all four answers. The addon asks by the current
  rank's ID (`Compat.CurrentSpellID`), so the printed ID must answer `true, true`; the rank-1 answers
  show whether the old ID still works. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-9. Which event a talent point fires (WoW Forever).** Before spending a Hawk Eye point, run
  `/run local f=CreateFrame("Frame") for _,e in ipairs({"CHARACTER_POINTS_CHANGED","PLAYER_TALENT_UPDATE","TRAIT_CONFIG_UPDATED","SPELLS_CHANGED"}) do pcall(f.RegisterEvent,f,e) end f:SetScript("OnEvent",function(_,e,a) print(e,a) end)`,
  then spend the point → write down every event name it prints, in order. The addon rebuilds on all
  four; at least one must print. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-10. Astral Influence (Retail, Balance Druid).** Without Astral Influence (197524), run
  `/dump C_Spell.GetSpellInfo(5176).maxRange`; take the talent and run it again → write down both
  (the base is 40). Then, with the talent, stand about 43 yd from the dummy and run
  `/dump C_Spell.IsSpellInRange(5176, "target")` → `true`. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-11. Overrides and an unarmed Auto Shot.** Retail: on a class whose ranged anchor has an
  override (a talent that replaces the spell), run `/dump C_Spell.GetOverrideSpell(<anchor ID>)` and
  `/dump C_SpellBook.IsSpellKnown(<that ID>)` → write down whether the override counts as known (the
  addon uses an override only when it does). WoW Forever, Hunter: unequip the ranged weapon and run
  `/dump C_Spell.IsSpellUsable(75)` → write down the answer (false means the ranged band falls back
  to Arcane Shot, which a hunter under level 6 does not have). Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-12. A melee true far away (WoW Forever, Hunter).** Target a mob at 10, 25, 45 and 80 yd →
  never MELEE (the owner saw MELEE at 41-45 and 45-100 before the fix); walk into melee → MELEE. Also
  on a Warrior or Rogue: never MELEE past 8 yd. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-13. An unusable anchor passes on (WoW Forever, Warrior).** With a thrown weapon equipped,
  in combat (Charge unusable), a target at 32 yd reads OOR, and at 20 yd MID; out of combat in Battle
  Stance the same. Rogue with a bow and Throw known: 32 yd reads OOR. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-14. Talented reach on a later spell (WoW Forever).** Shadow Priest with Shadow Reach (or
  Warlock with Grim Reach): `/rm bands` read-out names Mind Blast (Corruption) at 36 yd; a target at
  33 yd reads CAST, not OOR. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-15. Retail melee spells that reach (Demon Hunter, Hunter, Shaman).** Vengeance with
  Improved Disrupt: the read-out names Fracture or Shear, and a target at 9 yd is not MELEE. Survival
  in Aspect of the Eagle: a target at 30 yd is not MELEE. Enhancement in Ascendance: a target at
  15 yd is not MELEE. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-16. Spell IDs added in the review.** `/dump C_SpellBook.IsSpellKnown(<id>)` on the class
  that should know it: Forever Paladin L6+ 679 (Holy Strike); Retail Resto Shaman 77472; Holy Priest
  14914; Devourer 473662 and 1226019; Vengeance 263642 or 203782, and 228477. A new Devourer profile
  starts on Caster 40. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-17. Dead targets and restricted content.** A dead hostile target and a dead friend: write
  down what the container shows (OOR would mean the anchor answered false on a corpse). In a Mythic+
  key or an encounter on Retail, the bands still change with distance. Result: PASS (owner, 2026-11-24, both clients)
- **RANGE-18. The hunter's dead zone (WoW Forever).** On a hunter (level 12+, Wing Clip learned) with
  the Hunter preset and band 1's Spell IDs empty, Settings > Band sets, band 1 (MELEE) reads "Now: Wing
  Clip (2974), melee range". Target a hostile mob and step back from melee: in melee it reads MELEE;
  at 5-8 yd it reads DEAD, in its color, and Format Range reads `5–8` (never `0–5` or `5–10`) while DEAD shows;
  walk slowly across the 8 yd edge: no spot reads `5–10 ?`;
  past 8 yd, RANGE (band 3, AUTO before 2026-11-24), and Format Range
  never writes a figure under 8 there (`8–10`, not `5–10`). Every format agrees with the band (About
  stays between 5 and 8 in the dead zone). Try it in and out of combat. Result:

## Containers drawn

- **DRAW-1. Brackets, never a distance.** Target a dummy and walk away → the number steps through
  brackets (`0–5`, `5–20`, …) and reads `40+` past the last check; the border and the number change
  color as the band does. Result: PASS (owner, 2026-11-24, both clients)
- **DRAW-2. Unknown is gray.** Target a unit the client will not range (far out of sight, or a
  friendly player in combat with no friendly spell) → `?` in gray, never the out-of-range red. Result: PASS (owner, 2026-11-24, both clients)
- **DRAW-3. Elements and order.** Turn on text, a dot and spell chips, drag them into a new order
  (Containers → Display → Layout → Element order; or `/rm set container.elements.order spells,text`),
  switch the direction to column → every element draws, in that order, the frame closes around them.
  The list: a hamburger handle on each element turned on, a green tick or a red cross that turns it
  on (it joins the end of the drawn ones) or off (it drops below them, dimmed, no handle). Set Size
  to Fixed size with Width 200 → the container stays 200 px wide as the number changes, the elements
  centered; back to Fit its content → it closes around them again.
  Every shape (dot, ring, square, diamond, triangle, bar, icon) draws without a missing-texture
  green. Result: PASS (owner, 2026-11-24, both clients)
- **DRAW-4. Skin face.** With an element's font left on the skin's, switch the skin (General → Skin)
  → the number's face follows at once, with no reload. Result: PASS (owner, 2026-11-24, both clients)
- **DRAW-5. Disable.** `/rm disable` → every container disappears; `/rm enable` → they come back.
  Result: PASS (owner, 2026-11-24, both clients)
- **DRAW-6. The Bar dot wears the skin's border and gloss.** Show the dot with Shape **Bar** and
  target a dummy. Under Ka0s Default the bar has no border, as before. Switch the skin (General →
  Skin) to Azeroth, High Contrast, WoW Default and WoW Midnight in turn → the bar draws that skin's
  border at once, with no reload. Under Glass → a soft shine lies over the filled part only, and it
  grows and shrinks with the fill. The fill keeps the band's color under every skin (LibKa0s v1.108.0,
  SD-RV-RM). Result: PASS (owner, 2026-11-24, both clients)
- **DRAW-7. Fixed colors follow the skin.** Show the caption (Display → Label → Show label): under
  Ka0s Default it reads the skin's gold label color, not white. Set the Number's Color from to Fixed
  color → it draws the skin's HUD text color whatever the swatch says; untick Use the skin's color →
  the swatch draws. Do the same for the Text element, the Dot, the border and the background (the
  border then takes the skin's bar edge color, the background its bar background). Switch the skin
  (General → Skin) → every part on Fixed with its companion ticked repaints at once, no reload. A part
  on Band color keeps the band's color under every skin, and one on Class color the unit's class color
  (SD-SK-RM.3, RM.4; owner U-30). Result:
- **DRAW-8. Outline and shadow follow the skin.** A new container's Number, Text and caption read
  Font flags From skin. General → Skin → Font outline **Off** → the HUD text loses its outline at once;
  **HUD text only** → it comes back. Pick a Font flags value (Thick outline) → that draws under every
  outline mode. Under a skin with a HUD shadow, a new container's text wears it; Font shadow is grayed
  while Use the skin's shadow is ticked; untick it and tick Font shadow → a black shadow one pixel down
  and right, under every skin (SD-SK-RM.1, RM.2). Result:
- **DRAW-9. The container border follows the skin's bar border.** A new container under Ka0s Default
  draws its Solid 1 px border as before. Switch to Azeroth, High Contrast, WoW Default and WoW Midnight
  → the border takes that skin's style and thickness (WoW Default the tooltip edge, 2 px), in the band
  color, at Border opacity; Display → Frame → Border style, thickness and Show border gray meanwhile.
  Untick Show border, still under Azeroth → the border stays (a skin's real border wins); untick Use
  the skin's border → the stored style draws again and Show border is the player's (SD-SK-RM.5).
  Result:
- **DRAW-10. Spell chips wear the skin's meaning colors.** Show spell chips and target a dummy: a
  chip in range draws the skin's green, out of range its red, no answer its gray. Switch the skin →
  the chips repaint in the new skin's three on the next update, with no reload (SD-SK-RM.10).
  Result:
- **DRAW-11. Class mode shows a class in test mode (FB-RM-01; options-ui-§17 *A preview shows a
  class*, standard v2.119.0).** A target container whose Number and Frame border read Color mode
  **Class**, the swatch set to something unlike your class (a dark blue). Clear your target and
  `/rm test` → the placeholder's number and border draw **your own** class color (a hunter's green),
  not the swatch. Still in test mode, target a player of another class → that class's color; target an
  NPC → the swatch. `/rm test` again to end it. Repeat with `/rm unlock` and no target → the unlocked
  placeholder draws your class too. **Fail:** the swatch with no target, or a color that does not
  follow the retarget. Result:
- **DRAW-12. High Contrast's HUD shadow is one pixel (FB-RM-01, LibKa0s v1.112.0, SkinDefsOthers
  minor 11).** A container with Use the skin's shadow ticked and Font outline on **HUD text only**.
  Switch to High Contrast → the number, text and caption wear a black shadow one pixel down and right,
  as under Azeroth, not a heavy two-pixel block. **Fail:** a doubled, two-pixel shadow under High
  Contrast. Result:

## Containers page

- **CONT-1. New container.** Containers → **New container** → a Target container is made, the banner
  picker shows it, and it draws on screen; the picker lists every container and switching it moves
  every tab to that container. General shows Name, Enable, What it tracks and the acts, and no
  Preview section: the band preview blocks are gone from the settings (plan 2026-11-19 M8; `/rm bands`
  keeps its chat ribbon). Result: PASS (owner, 2026-11-24, both clients)
- **CONT-2. The rail.** The rail reads General, Display, Visibility, Sounds. Set Unit to
  All nameplates → Sounds leaves the rail (and the page heals to General if Sounds was shown); set
  it back → Sounds returns. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-3. Position follows Attach to.** General → Position: each Attach to value (Free on screen,
  Unit frame, Nameplate, Cursor) shows only its own rows; Unit frame with Custom frame (by name)
  adds Frame name and **Pick on screen**. All nameplates shows no Attach to, only the nameplate rows
  and Friendly nameplates too. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-4. Duplicate, Delete, Copy settings from.** **Duplicate container** makes `<name> copy`
  next to it, offset on screen; **Delete container…** asks first and deletes the one it named; Copy
  settings from copies the look and rules onto the selected container but keeps its name, its label
  text, unit and placement. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-5. Defaults.** Change a row on Display and one on Visibility, press **Defaults** on the
  Display entry → only Display's tabs reset, only for the container in the banner. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-6. Color from.** Set Frame's Color from to Class color and target a player of another class →
  the border takes that player's class color; a target with no class keeps the swatch. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-7. The Dot tab.** Display's tabs read Layout, Frame, Number, Text, Label, Dot, Spell chips. Dot
  shows Show dot, Shape, Size (px), Dot color and Color from, then **Style**: six tiles (Plain, Matte,
  Glossy, Glowing, Neon, Gem), each the stored shape in that style tinted as the dot draws, the stored
  one edged in gold (Matte on a new container). Click Gem → the on-screen dot turns gem and the tile
  is edged. Change Shape to Star → the tiles redraw as stars at once; to Bar or Spell icon → the
  tiles gray, a line says Bar and Spell icon take no style, and a click does nothing; back to Hexagon
  → the tiles light again. Change Dot color (fixed) → the tiles take the new tint. Plain, Matte,
  Glossy and Gem fill the tile as the v0.1.0 dot did; Glowing and Neon draw a smaller core with the
  halo around it, nothing clipped at the tile's edge. No preview box shows on the tab. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-8. Border opacity.** On a new container, Frame → Border shows **Border opacity** at 25%, the
  border drawn faint over a background; drag it to 100% → the border is solid, in every Color from
  mode. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-9. The caption's text and positions.** Display → Label: the tab shows Show label, Label
  text, Position, Align, Gap (px), then the Font block; a new container has Show label off and draws
  no caption. Tick **Show label** → a caption reading the container's name shows above its elements,
  inside its border; rename the container on General → the caption follows. Type a Label text and
  press Enter → the caption reads it; clear it → the name again. Position Bottom, Left, Right → the
  caption moves to that side and the container grows to hold it, the elements and the caption
  centered on each other; Align shows only for Top and Bottom, where Left / Center / Right moves the
  caption along the edge. Raise Gap (px) → the space between the caption and the elements widens.
  `/rm unlock` with the caption on Top → the drag strip sits above the border, clear of the caption.
  Turn every element off → the caption alone, with no gap. Set Layout's Size to Fixed size → the box
  keeps its width and height, the caption inside it. Position lists Inside and Outside for each side:
  Outside top / bottom / left / right → the caption sits beyond the border, Gap (px) off the edge, and
  the container shrinks to its elements; Align moves an outside top or bottom caption along the edge.
  `/rm unlock` with Outside top → the drag strip sits above the caption, not over it; `/rm test` while
  locked → the TEST strip sits above it too. Untick Show label → the caption goes and the
  container shrinks back. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-10. The caption's styling.** With the caption on: change the Font block's face, size,
  outline and Font shadow → the caption takes each at once and the container resizes to the new
  width; leave the face on Skin and switch the skin → the caption's face follows. Color from Fixed
  with Use the skin's color unticked and a swatch → that color; Band → the caption takes the band's text color as the target moves
  between bands; Class with a player targeted → that player's class color, the swatch when the target
  has no class. Copy settings from a container with a styled caption → the style and position come
  over and the destination keeps its own Label text. Result:
- **CONT-11. One line, Align, Band span.** A container with Number and Text on (any preset that
  shows both, or an existing one: the load pass turns Number and text on one line on) reads as one
  line, "28+ OOR", the label in its band color, with no gap between them; Display → Layout → Number
  and text on one line off → two elements again. Align Left / Center / Right with Size → Fixed size
  at 200 px → the line sits left, centered, right. Number → Format → Band span: a Forever hunter with
  Hawk Eye reads 8–41 in AUTO, 0–5 in MELEE, 41+ in OOR, instead of the 5 yd steps. Result: PASS (owner, 2026-11-24, both clients)
- **CONT-12. The skin companion rows.** Display → Number (and Text, Label): after the color pair and
  Font flags, the block ends with Use the skin's color and Use the skin's shadow, both ticked; Font
  flags leads with From skin, picked; the Font picker has no companion (its Skin's font value is the
  skin's). Frame → Border ends with Use the skin's border and Use the skin's color, then Border
  opacity; Frame → Background and Dot each end their color pair with Use the skin's color. Hover each
  Use the skin's color → its tooltip says it is read while Color from is Fixed color. `/rm set
  container.elements.number.colorFromSkin false` unticks the row. Result:
- **CONT-13. The Style tiles follow the Scope.** With General → Skin → Scope → Ignore settings panel
  ticked (the default), open Display → Dot: the Style tiles draw the stock dark fill and brown edges,
  as the stock labels beside them. Untick it → the tiles take the skin's input fill and edge at once,
  the picked one edged in the accent; switch the skin → they repaint; tick it again → stock, live
  (SD-SK-RM.12). Result:
- **CONT-14. The frame picker's label.** Position → On the unit frame → Unit frames from Custom →
  **Pick on screen**: the hint by the pointer draws in the skin's accent color and the skin's body
  face (WoW Default's, Azeroth's Open Sans), not the client's large gold font (SD-SK-RM.9). Result:

## Band sets page

- **BANDS-1. The picker.** Band sets → the banner lists the four preset sets, the default one marked
  `(default)`; **New band set** makes and selects one; **Duplicate band set** makes `<name> copy`;
  **Delete band set…** asks first and moves its containers to the default set; deleting the last set
  prints `The last band set cannot be deleted.` Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-2. The Bands editor.** Bands → a rail of the bands on the left, no ribbon above it; change
  a band's **Up to** → the next band starts there and the rail entries follow; **Add band** splits a
  band off the open-ended last one; **Remove band** removes one, and the last band left cannot be
  removed. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-3. Shared.** Put two containers on one set and change a band's Frame color → both change
  at once, without a reload. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-4. Friendly override.** On a target container set Friendly band set to Healer, target an
  enemy and then a friendly player → the bands switch to Healer's on the friendly one. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-5. Unknown label.** Set Unknown label to `--` and Unknown color to blue, target a unit the
  client will not range → `--` in blue. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-6. The rule controls.** Bands → every band shows **Defined by** first (Yards, Spell, Dead
  zone, Beyond the last spell band); pick Spell on a yard band → **Role** and **Spell IDs** appear, the
  heading gains `(Spell: Ranged)` (`(Spell: Melee)` on the first band) and the slider reads **Fallback
  (yards)**; type `abc` in Spell IDs → a chat line refuses it and the stored list is kept; clear the
  box → the class's own anchors are used again. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-7. The read-out follows the spellbook.** On a spell band the read-out reads `Now: <spell>
  (<ID>), <min>–<max> yd`; on a band whose role this character has no learned anchor for it reads
  `Not learned: using <yards> yd`. Shift a druid out of Cat Form with the page open → the melee band's
  read-out turns to `Not learned` without a reload; learn a spell or spend a talent point → it
  updates the same way. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-8. The owner's case: Hawk Eye at 35–41 yd paints AUTO (WoW Forever, Hunter).** Hawk Eye 3/3,
  a target container on the Hunter set (MELEE, DEAD, AUTO, OOR). Back away from the dummy from 30 yd
  → the display stays AUTO through the `35–40` bracket out to about 41 yd, and turns OOR only past
  that; with Hawk Eye 0/3 the same walk turns OOR at about 35 yd. The yards on the set never change.
  Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-9. Melee and the dead zone (WoW Forever, Hunter).** Same container: stand at the dummy →
  MELEE; step back to about 6 yd → DEAD; past 8 yd → AUTO. Target a friendly player in combat at 6 yd
  → the display never reads DEAD on a guess (the interact check is refused there): it reads its
  fallback band or `?`. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-10. The v1 -> v2 conversion.** With a profile saved on a build before the dynamic bands
  (schema 1), log in on this build → every band set is still there with the same edges, labels,
  colors and sounds; the Hunter, Caster 40 and Melee / Ranged sets show Spell and Dead zone rules on
  their bands, a custom set's last band reads Beyond the last spell band, and a set used only as a
  Friendly band set has a `(Spell: Friendly)` band. Result: PASS (owner, 2026-11-24, both clients)
- **BANDS-11. The band rail.** Band sets → Bands on the Hunter set → a rail on the left lists
  `1 MELEE · 0–5 yd`, `2 DEAD · 5–8 yd`, ... each led by a square of its frame color, the labels inside
  the rail's border (none runs past its right edge), and beside it band 1's heading and controls
  only. Hover an entry → its tooltip is the band's full heading. Click band 3 → band 3's controls
  show, its entry white and highlighted, the others gold; change its Label → the page redraws and
  band 3 stays selected, its entry showing the new label; drag its Fallback → its entry's span and the
  next one's follow and band 3 stays selected. Change its Frame color → its chip follows. Remove band
  on band 3 → band 4 (now 3) is selected; Remove band on the last band → the one before it is
  selected. **Add band** → the new band is selected. Pick another band set in the banner → band 1 of
  that set is selected. Close and reopen the panel → the selection is kept; `/reload` → band 1. Enter
  combat with the page open → the lock covers the rail and a click on it does nothing. With a skin
  on (General > Skin) → the rail pane and entries take the skin like the Containers page's rail.
  Result: PASS (owner, 2026-11-24, both clients)

## Presets

- **PRESET-1. First-run picker.** On a new profile the **Choose a preset** window opens above the
  center, the containers unlocked and test mode on (its two toggles say so), and Simple's four
  displays already on screen with the status line showing, no pick needed. The dropdown lists five:
  Simple, Intermediate (Range Text), Intermediate (Range Numbers), Advanced, Expert. Pick **Expert**
  → six displays; pick **Simple** → four, and the Band sets page lists no Healer set Expert's pick
  made. In every preset each unit sits at the same home: target and focus side by side below the
  center, pet and mouseover under them, the two nameplate containers (each beside its preview
  nameplate) in a third row; no two drag strips overlap. **Not now** → your own displays are back, test mode off, the lock as it was,
  then the skin picker opens. On another new profile pick **Intermediate (Range Text)** and **Apply** → kept with
  no confirm on an empty profile, displays locked, test mode off. The window does not return after a
  `/reload`; `/rm preset` opens it again. Entering combat while a pick is previewed puts your own
  displays back; entering combat before it shows holds it until combat ends. The gear opens General
  → Presets. Result: PASS (owner, 2026-11-24, both clients)
- **PRESET-2. Apply on an empty profile.** With no container, **Apply Simple…** → applied at once, no
  confirm: four containers (Target, Focus, Pet, Mouseover) free on screen, and a chat line naming
  `/rm preset undo`. Result: PASS (owner, 2026-11-24, both clients)
- **PRESET-3. Apply over containers, then Undo.** With containers, **Apply Expert…** → a confirm
  naming the preset and how many displays it replaces; **Cancel** changes nothing; **Apply** leaves
  six containers (target, focus, pet and mouseover free on screen, target on its own plate, one on
  every other plate, friend or foe). **Undo last preset** puts the earlier ones back. Result: PASS (owner, 2026-11-24, both clients)
- **PRESET-4. What each preset shows.** (Every preset container shows for any unit, friend or foe:
  target a friendly player and every display still shows; in Expert and Ka0s target, focus and
  mouseover read the Healer set on friends. Every preset container on a nameplate attaches to
  the cast bar while casting, at offsets 0.) Ka0s: five containers, target, focus, pet and mouseover
  with the number above the band name (stacked, not one line) and no border or background (the
  only preset without the faint frame), on the class's own band set (Hunter on a hunter, even
  when another set is the default), shown for any unit, the Healer set on
  friends for target, focus and mouseover, no sound (only Expert sounds), and the target plate showing the
  number alone. Apply each in turn from General → Presets; every one puts
  target, focus, pet and mouseover free on screen at their homes, each with its name (Target, Focus,
  Pet, Mouseover) as a caption above its border, on a faint band-tinted background with a faint
  border, and differs only in what they show: Simple a matte dot; Intermediate (Range Text) the
  band's name (MELEE, LONG, ...); Intermediate (Range Numbers) the range number; Advanced dot, number
  and name; Expert all three with spell chips, plus the two nameplate containers (shown out of
  combat too: target a hostile mob out of combat → the target-plate container shows under its plate,
  and every other plate, friendly ones too, wears a dot; no caption on either),
  the out-of-range chime on target and the Healer set as the friendly override on target, focus and
  mouseover. `/rm preset text`, `/rm preset numbers` and `/rm preset expert` reach the same; `/rm
  preset intermediate` prints the usage line. Result: PASS (owner, 2026-11-24, both clients)
- **PRESET-5. The dropdown's selected row stands apart (FB2-RM-01, amended by FB2-RM-02 for the
  owner's ruling of 2026-11-24: gold in every skin; LibKa0s v1.113.0, WidgetsDropdown minor 4;
  skinning-§4 *A selected entry reads apart*, standard v2.120.0).** `/rm preset`, pick
  **Intermediate (Range Text)**, then open the dropdown again → its row is Ka0s Default's gold and
  plainly a different color from the five other rows. `/rm skin`, choose **Azeroth**, then
  **Obsidian**, and open the dropdown again under each → the selected row is the same gold in both,
  not the skin's accent and unlike the other rows. On WoW Forever, under the default **WoW Forever**
  skin → the selected row is gold too, not the skin's tan accent. Put the skin back when done.
  **Fail:** a selected row the same color as the rows around it, or in a skin's accent rather than
  gold. Result:

## Anchors

Set a container's placement on Containers → General → Position (**Attach to**, then the rows under
it), or from chat with `/rm set container.anchor.mode frame` (`screen`, `frame`, `nameplate`,
`cursor`). Each check is a row of the matrix: run it on both clients and fill both cells.

- **ANCHOR-1. Free on screen.** With no focus and no mouseover, `/rm unlock` → every container shows
  (focus and mouseover on the placeholder range, a `nameplates` one through its stand-in, no amber
  strip); entering combat puts each back on its own visibility rules, leaving combat shows them again,
  `/rm lock` hides the ones with no unit. A drag strip (name, then ?, gear, X) shows above every
  container: the gear opens it on the Containers page, the X disables it with one chat line. Drag a
  free-on-screen one, then `/reload` → it is where it was dropped. With the Expert preset and its
  mouseover container set to Cursor, the mouseover (cursor) and target-plate containers sit still at their screen points while unlocked,
  not on the cursor or a plate, and drag; each container on a nameplate (and the `nameplates`
  stand-in) sits beside a red preview nameplate named for whose plate it stands for, its drag strip
  above the plate, and dragging the strip moves both; a container on a unit frame stays on it with
  its name grayed and does not drag (its Position tab reads Unit frame anchor point, This container
  anchor point, X offset, Y offset, and each moves it on the frame); the `nameplates` stand-in wears one strip, a real plate's instance none.
  With Test mode on, each drag strip ends in TEST and no amber strip shows beside it; `/rm lock`
  brings the amber strip back on each display (Sim mode: SIM, the cyan strip). Entering combat
  puts the cursor container back on the cursor and drops the strips of the non-screen ones.
  `/rm lock` hides the strips; in combat a drag does not start. `/rm resetposition` puts them back
  near the center.
- **ANCHOR-2. Blizzard unit frames.** Target, focus and pet containers on Unit frames from Blizzard sit
  just above TargetFrame, FocusFrame and PetFrame; a mouseover container on a unit frame follows the
  cursor (mouseover has no frame). On WoW Forever, a client with no focus frame leaves the focus
  container hidden with one `[Anchor]` debug line, and no error.
- **ANCHOR-3. EllesmereUI unit frames.** With EllesmereUI Unit Frames enabled and its target, focus
  and pet frames on, Unit frames from EllesmereUI → each sits on EllesmereUI's frame from login, with
  no `/reload`. With EllesmereUI off, the container is hidden and the console shows one `[Anchor]`
  line.
- **ANCHOR-4. Custom frame, missing, and combat.** Type a frame name that does not exist in Frame
  name → hidden, one `[Anchor]` line. Enter combat with a container waiting for a frame that loads
  late → no `ADDON_ACTION_BLOCKED`; it attaches after combat. Changing a unit-frame container's
  offset in combat moves it after combat, not during.
- **ANCHOR-5. Own nameplate.** A target container on Nameplate sits under the target's plate, follows
  a retarget, hides when the plate leaves the screen, and comes back with it. Unlocked, it sits
  under its preview nameplate instead; changing Nameplate anchor point, This container anchor point
  or the offsets moves it against the preview at once, and `/rm lock` with a target puts it on the
  real plate in the same place. In Test mode, locked, the container on the target's plate wears the
  amber strip on its top edge and BugSack shows no *Can't measure restricted regions* error.
- **ANCHOR-6. All nameplates.** An All nameplates container draws on every hostile plate in a pack
  and on none of the friendly ones; with Friendly nameplates too on, friendly plates too. Pulling a
  pack and killing it (plates recycling fast) raises no error. In an instance, friendly plates
  (forbidden) draw nothing and raise nothing. On WoW Forever, a plate's container appears on the
  plate, not at the screen's corner, when the plate first shows.
- **ANCHOR-7. Cursor.** A mouseover container on Cursor follows the cursor while hovering a unit and
  hides when hovering nothing; with the UI scale changed, it stays on the cursor; its X and Y offset
  rows move it relative to the cursor.
- **ANCHOR-8. Frame picker.** `/rm pick` (or **Pick on screen**) → an outline follows the named frame
  under the cursor; Enter attaches the selected container to it (`Attached to <name>.`), with
  Unit frames from set to Custom frame (by name); Escape cancels; a mouse click during a pick reaches
  only the game (it neither picks nor cancels); entering combat ends it with no error; starting it in
  combat prints one gray line.
- **ANCHOR-9. All nameplates except target.** Beside a container on the target's own plate, an All
  nameplates except target container draws on every hostile plate but the target's, so the two never
  stack on one plate; retargeting moves the gap to the new target's plate at once, the old target's
  plate gets its copy back, and clearing the target puts a copy on every hostile plate. Expert's
  every-plate container uses this unit.
- **ANCHOR-10. The drag strip's marks (LibKa0s v1.107.0).** `/rm unlock` → each container's drag
  strip reads, left to right at its right end, `?`, gear, X, packed close together; at rest the three
  take the tint of the settings window's title-bar marks, and under the pointer the `?` and the gear
  light the header's hover color and the X lights red, as the settings window's close does. Hovering
  the strip, the `?`, the gear or the X opens its tooltip centered above the strip (below it only
  near the top of the screen), never beside it: the gear's says it opens this display's settings, the
  X's says it disables the display, keeps its settings and names Enable on the Containers page.
  Click the gear → the settings panel opens on Containers with that display selected. Click the X →
  that display disappears with one chat line; on Containers its Enable is off and every other
  setting is as it was; turning Enable back on brings it back where it was, looking the same.
- **ANCHOR-11. The cast bar part, and strata on a plate.** Run it with EllesmereUI Nameplates on, its
  Casts In Front of Nameplates (Cast Overlay) first off, then on, and once with EllesmereUI
  Nameplates off (Blizzard plates).
  1. A target container on Nameplate and an All nameplates container: Containers → Position →
     On the nameplate shows **Attach to part** for both, offering Nameplate, Cast bar and Cast bar
     while casting, else nameplate (and not for a container on screen, a unit frame or the cursor).
     **Nameplate** (the default): each sits under its plate's health bar, as before.
  2. **Cast bar** → each sits under its plate's cast bar (TOP to BOTTOM, 2 px), not under the health
     bar; with the cast bar hidden between casts it stays in the same place and does not jump. The
     same with Cast Overlay on (the bar lifted out of the plate) and on Blizzard plates (the game's
     own cast bar). Retarget, pull a pack and kill it (plates recycling): each copy stays on its own
     plate's cast bar, no error.
  3. **Cast bar while casting, else nameplate** → between casts each sits under its plate; the moment
     the mob starts a cast or a channel its copy drops under the cast bar, and when the cast ends,
     is interrupted (kick it) or fails, it goes back under the plate, with no lag of a frame or more
     and no flicker on the other plates. In combat, in a pack where several mobs cast at once, each
     copy follows its own mob. Target a mob that is already casting → the target container appears
     on the cast bar. !!AddonProfiler shows Range Master's cost only as casts start and stop, none per frame. On WoW Forever (no
     cast read in the client) the same, and a plate that comes into view mid-cast starts on the bar.
  4. A plate with no cast bar EllesmereUI or the game knows of (a friendly name-only plate with
     Friendly nameplates too) keeps its copy on the plate under every choice, no error.
  5. Frame strata **Background** on a container on a plate, a cast overlapping it: with Cast
     Overlay **on**, the cast bar draws over the container; record what draws with Cast Overlay
     **off** (expected: the container over the bar; see `docs/ARCHITECTURE.md` Known Limitations).
     Then Frame level **1** with Background, Cast Overlay off, and record again. The probe below,
     with the target's plate casting, records the numbers:
     `/run local p=C_NamePlate.GetNamePlateForUnit("target") local e=EllesmereNameplates_NS and EllesmereNameplates_NS.plates[p.namePlateUnitToken] print(p:GetFrameStrata(),p:GetFrameLevel(),e and e.cast:GetFrameStrata(),e and e.cast:GetFrameLevel())`
  6. Frame level: two screen containers overlapping in one strata, the older one on **1** → it draws
     under the newer Auto one; **100** → over it; **0** → back to Auto. Changing Frame strata on a
     container with every element on keeps the number, text and chips over the fill and the border
     (nothing drops behind the background).
- **ANCHOR-12. The preview nameplate keeps a nameplate's look.** A target container on Nameplate,
  `/rm unlock`: the red preview nameplate beside it has a dark ground, a black edge, a red health
  fill and the client's small white name line. General → Skin → pick each of two other skins (say
  WoW Default, then a dark one), with Ignore fonts off: the container beside it repaints in each
  skin, the preview nameplate does not change at all (skinning-§9 Preview stand-ins, owner U-24,
  2026-11-20). Result: PASS (owner, 2026-11-24, both clients)
- **ANCHOR-13. A right-click anywhere on the drag strip opens what its gear opens (SRC-RM-01, LibKa0s
  v1.111.0; standalone-windows *A right-click opens what the gear opens*, standard v2.118.0).** Two
  screen containers, `/rm unlock`, out of combat, the settings closed. Right-click the second
  container's strip (its name) → the settings panel opens on Containers with that display selected,
  exactly where a left click on its gear lands. Close the panel and right-click the strip's `?`, then
  the gear, then the X → each opens the same page on the same display, and the X's right-click
  disables nothing. Repeat on the first container's strip → it is the one selected. Fail: a right-click
  that opens another page or display, opens nothing, or disables the display. Result:

| Check | Mode | Retail result | WoW Forever result |
|---|---|---|---|
| ANCHOR-1 | `screen` | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-2 | `frame`, Blizzard | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-3 | `frame`, EllesmereUI | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-4 | `frame`, custom and missing, combat | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-5 | `nameplate` (own plate) | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-6 | All nameplates (per-plate) | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-7 | `cursor` | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-8 | the frame picker (`frame`, custom) | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-9 | All nameplates except target | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24) |
| ANCHOR-10 | the drag strip's marks (`screen`) | | |
| ANCHOR-11 | the three Attach to part choices, strata and level on a plate (`nameplate`, All nameplates) | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24). Passed on both clients, the owner, 2026-11-24. |
| ANCHOR-12 | the preview nameplate under a skin switch (`mockplate`) | PASS (owner, 2026-11-24) | PASS (owner, 2026-11-24). Passed on both clients, the owner, 2026-11-24. |
| ANCHOR-13 | the drag strip's right-click (`screen`) | | |

## Visibility

Set the rules on Containers → Visibility.

- **VIS-1. Combat.** Show = Only in combat → the container is hidden out of combat and shows on the
  pull; Only out of combat the reverse; no `ADDON_ACTION_BLOCKED` on either edge. Result: PASS (owner, 2026-11-24, both clients)
- **VIS-2. Reaction.** Reaction = Hostile only → shows on an enemy, hides on a friendly player; a duel
  starting (the player turning hostile) shows it without a retarget. Result: PASS (owner, 2026-11-24, both clients)
- **VIS-3. Opacity and the master rows.** Out of combat opacity 40% → faint out of combat, full in it.
  General visibility `Never` hides every container at once, `In combat` only shows them in combat;
  Master opacity and Master scale apply to every container. Result: PASS (owner, 2026-11-24, both clients)

## Sounds

- **SOUND-1. The out-of-range chime.** Apply Expert, target a dummy in range, walk out past 40 yd →
  one chime about 0.2 s after crossing; walking back and forth across the edge quickly does not
  chain chimes (at most one a second); retargeting while out of range is silent. Result: PASS (owner, 2026-11-24, both clients)
- **SOUND-2. None on nameplates.** Put a sound on every band of the all-nameplates container's set and
  pull a pack → no sound plays from it. Result: PASS (owner, 2026-11-24, both clients)

## Pending sign-off

| ID | Origin | Why it is owed |
|---|---|---|
| every check above | the v0.1.0 build, 2026-11-18 | no client pass recorded yet. Passed on both clients, the owner, 2026-11-24. |
| RANGE-1..5 | the v0.1.0 range engine (plan Task 2), 2026-11-18 | the Forever interact distances and the seed IDs are unconfirmed in a client. Passed on both clients, the owner, 2026-11-24. |
| DRAW-1..5 | the v0.1.0 renderer (plan Task 5), 2026-11-18 | no container has been drawn in a client yet. Passed on both clients, the owner, 2026-11-24. |
| ANCHOR-1..8 | the v0.1.0 anchors (plan Task 6), 2026-11-18 | no anchor has been seen in a client yet; the EllesmereUI names are read from its source, not a running client. Passed on both clients, the owner, 2026-11-24. |
| MODES-5..7, VIS-1..3, SOUND-1..2 | the v0.1.0 behavior and modes (plan Task 7), 2026-11-18 | no preview, visibility rule or sound has been seen or heard in a client yet; the chime's file id (567397) is unconfirmed on Forever. Passed on both clients, the owner, 2026-11-24. |
| SLASH-5..8, CONT-1..6, BANDS-1..5, PRESET-1..4, PROFILE-3 | the v0.1.0 settings pages and verbs (plan Task 8), 2026-11-18 | no settings page beyond General has been opened in a client yet. Passed on both clients, the owner, 2026-11-24. |
| INSTALL-4, CONT-2, CONT-7..8, PRESET-1, PRESET-3..4 | the five presets and dot styles (plan 2026-11-19-presets-and-dot-styles), 2026-11-19 | the Dot tab, the style art, Border opacity, the v0 -> v1 migration and the five presets have not been seen in a client yet. Passed on both clients, the owner, 2026-11-24. |
| INSTALL-4, CONT-1, CONT-7, CONT-9..10, BANDS-2 | the Label tab, the removed band previews and the art fill (the same plan, M7-M9), 2026-11-19 | the caption, the settings without their band previews and the redrawn halo-free art have not been seen in a client yet. INSTALL-4, CONT-1, CONT-7, CONT-9 and BANDS-2 passed on both clients, the owner, 2026-11-24; CONT-10 is still owed. |
| CONT-9, PRESET-4 | the outside caption positions and the preset defaults (the same plan, M11-M12), 2026-11-19 | the outside captions, the lifted strips, the faint preset frames and the plate containers out of combat have not been seen in a client yet. Passed on both clients, the owner, 2026-11-24. |
| ANCHOR-10 | the LibKa0s v1.107.0 re-vendor and the strip wiring (Ka0sAddonsCommonTasks 2026-11-19-ADOPTION_FEEDBACK, AF-RV-RM and AF-STRIP-RM), 2026-11-19 | the strip's new mark order, pitch, tints and the tooltip above the strip have not been seen in a client yet |
| ANCHOR-11 | the plate cast bar part and Frame level (branch feat/2026-11-20-plate-castbar), 2026-11-20 | the cast bar lookup (EllesmereUI's map, the game's `UnitFrame.castBar`), the cast events moving *Cast bar while casting*, Cast Overlay on and off, and where Background draws against a plate's cast bar have not been seen in a client yet. Passed on both clients, the owner, 2026-11-24. |
| INSTALL-5, DRAW-7..10, CONT-10, CONT-12..14 | the skin-defaults fixes (Ka0sAddonsCommonTasks 2026-11-20-LIBKA0S_94_97_99_100, SD-SK-RM: SD-SK-RM.1 to RM.6, RM.9 to RM.12, the owner's R-2 and U-30), 2026-11-20 | the HUD companions, the From skin outline, the skin's shadow and border, the chips' meaning colors, the one-time move, the tiles' Scope and the picker's label have not been seen in a client yet |
| INSTALL-5, DRAW-7..10, CONT-10, CONT-12..14 (amended) | the owner's restore of 2026-11-23 (Ka0sAddonsCommonTasks `docs/2026-11-23-R2_RESTORE_AND_PROBE_FIXES/`, R2P-RM) | wherever one of these expects a default on the skin it is superseded: each companion starts off and draws the skin's only once ticked |
| ANCHOR-12 | the review of SD-SK-RM (Ka0sAddonsCommonTasks 2026-11-20-LIBKA0S_94_97_99_100; skinning-§9 Preview stand-ins, owner U-24, in place of SD-SK-RM.7 and RM.8), 2026-11-21 | the preview nameplate's stock look under a skin switch has not been seen in a client yet. Passed on both clients, the owner, 2026-11-24. |
| DRAW-6 | the LibKa0s v1.108.0 re-vendor (Ka0sAddonsCommonTasks 2026-11-20-LIBKA0S_94_97_99_100, SD-RV-RM), 2026-11-20 | the Bar dot's skin border and Glass gloss have not been seen in a client yet. Passed on both clients, the owner, 2026-11-24. |
| RANGE-6..11, BANDS-6..10 | the spell-driven dynamic bands (plan 2026-11-19-dynamic-bands, D1-D7), 2026-11-19 | whether the client reports talented ranges and answers by rank ID, which event a talent point fires, the rule controls, the owner's Hawk Eye case and the v1 -> v2 conversion have not been seen in a client yet. Passed on both clients, the owner, 2026-11-24. |
| DIAG-4, DRAW-11, DRAW-12 | the LibKa0s v1.112.0 re-vendor and the preview stand-in (Ka0sAddonsCommonTasks 2026-11-24-FEEDBACK_BATCH, FB-RM-01), 2026-11-24 | the copy window's close-only title bar, Class mode's stand-in class in test mode and unlock, and High Contrast's one-pixel HUD shadow have not been seen in a client yet |
| MODES-8, PRESET-5 | the LibKa0s v1.113.0 re-vendor (Ka0sAddonsCommonTasks 2026-11-24-FEEDBACK_BATCH, round 2, FB2-RM-01), 2026-11-24 | the step panel on every start path and the preset dropdown's selected row in gold under every skin (Azeroth, Obsidian, WoW Forever on Forever; amended by FB2-RM-02) have not been seen in a client yet |
| ANCHOR-13 | the LibKa0s v1.111.0 re-vendor (Ka0sAddonsCommonTasks 2026-11-23-STRIP_RIGHT_CLICK, SRC-RM-01), 2026-11-23 | the strip's right-click on the band and each mark, now the gear's own action with no `onRightClick` (DragHandle minor 17), has not been seen in a client yet |
| RANGE-18 | the hunter dead-zone fix (RM-DZ-02, then branch feat/2026-11-24-rangemaster-wingclip, RM-DZ-03), 2026-11-24 | Wing Clip (2974) as the Forever hunter's melee anchor and the dead zone's number pulled in to 8 yd: whether MELEE holds in melee, DEAD at 5-8 yd reading `5–8`. |
