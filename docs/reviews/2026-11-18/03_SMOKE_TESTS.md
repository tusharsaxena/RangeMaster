# RangeMaster v0.1.0: in-client smoke tests (2026-11-18)

This file holds what only the game client can verify. Before logging in, re-run the headless gate
once: `lua tests/run.lua`, `KA0S_KIT_CLIENT=forever lua tests/run.lua` and
`~/.claude/dev-copilot/bin/ka0s-bounded luacheck .`. Expect 0/0 lint and every case passing. With
C-01 and C-10 applied the count is 612 (610 today plus 2). C-11 may lower it.

## Pre-flight

- **Clients:** Retail (Interface 120105) and WoW Forever (16001). Run every section on both unless
  it is marked otherwise.
- **Error reporting:** `/console scriptErrors 1`. Have BugSack or an equivalent installed if you can.
- **Characters:** two characters of different classes (for example a Mage and a Warrior) on the
  default `Default` profile.
- **Combat:** a training dummy, and an area with several hostile mobs close together (for plates).
- **Setup:** enemy nameplates on (`V`).

## C-01: Stored displays draw at login whatever the skin settings (F-001)

- **Setup:** Apply the Simple preset (`/rm preset simple`) so four displays exist. Open General >
  Skin and **untick** *Ignore settings panel*. Keep the skin on the client default.
- **Steps:**
  1. `/reload`.
  2. Target any unit.
- **Expected:** The four displays are on screen right after the reload. The Target display shows a
  range as soon as you have a target.
- **Pass / Fail:** Pass if the displays appear without touching any setting. Fail if they appear
  only after a settings change.

## C-02: Keyboard-confirmed frame pick (F-002)

- **Setup:** Select a Target container. Containers > General > Attach to: Unit frame, Unit frames
  from: Custom.
- **Steps:**
  1. Click *Pick on screen*.
  2. Hover `PlayerFrame` and left-click.
  3. Press Enter.
  4. Repeat steps 1 and 2 over an action button with a spell on it, then press Escape.
- **Expected:** At step 2 the left-click neither picks nor changes the picker. The game's normal
  click still happens (for example you target yourself). At step 3 chat prints `Attached to
  PlayerFrame.` At step 4 Escape cancels, and the Escape key does not also open the game menu.
- **Pass / Fail:** Pass if only Enter picks and only Escape cancels. Try `/rm pick` in combat as
  well: it must print the gray refusal line.

## C-03: Overlapping displays stack whole (F-003)

- **Setup:** Apply the Advanced preset. Turn on the border and background for the All nameplates
  container.
- **Steps:**
  1. Pull a pack of 5 or more mobs so the plates overlap.
  2. Move the mouseover cursor display across the Target screen display.
- **Expected:** At each overlap, one display draws entirely over the other. No fill, border or
  number from the lower display shows through the upper one.
- **Pass / Fail:** Pass if there are no interleaved layers.

## C-04: Renderer strata (F-013)

- **Steps:** `/rm set container.anchor.strata HIGH`, then `/reload`.
- **Expected:** The display draws at HIGH. Open Esc > Options: Blizzard's settings panel shares HIGH
  and the game menu still covers the display.
- **Pass / Fail:** Pass if the display never covers a DIALOG-tier frame.

## C-05: Band-set delete reassigns through the registry (F-006)

- **Steps:**
  1. On the Band sets page, duplicate the default set.
  2. Give a container the duplicate as its Band set.
  3. Delete the duplicate and confirm.
- **Expected:** The container now shows the default set on the Containers page (with no `/reload`),
  and its display recolors.
- **Pass / Fail:** Pass if the panel and the display agree straight away.

## C-06: Spell chips follow the character (F-004)

- **Steps:**
  1. On the Mage, make a Focus container with spell chips on.
  2. Log the Warrior in on the same `Default` profile.
  3. Focus a target dummy.
- **Expected:** The Warrior's chips are Warrior spells (the Retail or Forever seeds), and they light
  up within range.
- **Pass / Fail:** Fail if the Mage's icons appear on the Warrior.

## C-07: Perf capture on the hot path (F-005)

- **Steps:** Follow the standard's two-arm protocol: `/rm perf` for the workflow, clean arm first,
  then suspend as the second arm, with no `/reload` between the arms. Keep the Advanced preset up in
  a dense pack fight. Record the capture with `/dev-copilot:wow-perf-analysis` as a
  `docs/perf-analysis/<YYYYMMDD-HHMMSS>/` bundle.
- **Expected:** Bucket figures for `ticker.tick`, `range.get` and `container.render`. Read the
  buckets, not the frame-time delta. This is also the first in-client evidence for 24 units at
  20 Hz through LibRangeCheck.
- **Pass / Fail:** Pass if the bundle is committed and its `ANALYSIS.md` is written.

## C-08: Localized chat lines (F-007)

- **Steps:** Set `/rm set skin.source eui` with EllesmereUI loaded, `/reload`, then
  `/rm set skin.source ka0s`.
- **Expected:** The reload-request line prints unchanged in enUS. This confirms the key resolves.
- **Pass / Fail:** Pass if the line is identical to today's text.

## C-09: `/rm delete` asks first (F-008)

- **Steps:** `/rm delete 1`, press No, then `/rm delete 1` again and press Yes.
- **Expected:** After No, nothing is deleted. After Yes, chat prints
  `Deleted container '<name>'.` and the display goes.
- **Pass / Fail:** Pass if nothing is deleted without the popup.

## C-10: Clamp cleared on detach (F-009)

- **Steps:**
  1. Make a New container (it starts on screen).
  2. Set Attach to: Nameplate.
  3. Strafe so the target's plate sits partly off the left screen edge.
- **Expected:** The display stays on the plate and goes partly off screen with it.
- **Pass / Fail:** Fail if the display stops at the screen edge, away from its plate.

## C-11 to C-13: Cleanup (F-010, F-011, F-012)

- **Steps:** Pull a pack, kill it, and let the plates vanish. On Retail, learn or unlearn a talent.
- **Expected:** No Lua error. The All nameplates instances go with their plates. Ranges keep
  updating after the talent change.

## Regression suite

1. `/reload` is clean, and login on a fresh character shows the preset picker and then the skin
   picker.
2. ADDON_LOADED, PLAYER_LOGIN and PLAYER_ENTERING_WORLD raise no errors on either client.
3. Enter and leave combat with every preset applied: the ticker rate changes (10 to 20 Hz), Test and
   Sim mode end on combat, and no `ADDON_ACTION_BLOCKED` appears.
4. `/rm disable`: every display hides. `/rm config` and the bare `/rm` still open the panel.
   `/rm enable` brings everything back.
5. Switch profile from the Profiles page: the displays rebuild from the new profile.
6. Open every settings page and toggle each option at least once.

## Taint

- In combat, target and clear target while a container is attached to `TargetFrame`. Expect no
  "Interface action failed because of an AddOn".
- `/rm config` in combat is refused with a gray line. Esc > Options > AddOns > Range Master opens
  out of combat.

## Cross-addon (in client)

Load the whole roster. Type each addon's root slash command and confirm it reaches its own addon,
`/rm` and `/rangemaster` included. Open Settings > AddOns and confirm each addon appears once, and
that each multi-page addon's pages appear once each.

## Sign-off

| ID | Tested? | Pass/Fail | Notes |
|---|---|---|---|
| C-01 | | | |
| C-02 | | | |
| C-03 | | | |
| C-04 | | | |
| C-05 | | | |
| C-06 | | | |
| C-07 | | | |
| C-08 | | | |
| C-09 | | | |
| C-10 | | | |
| C-11 | | | |
| C-12 | | | |
| C-13 | | | |
