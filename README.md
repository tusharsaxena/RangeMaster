# Ka0s Range Master

![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.5_and_Forever_1.60.1-purple)
![License](https://img.shields.io/badge/License-MIT-orange)
![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
![Tests](https://img.shields.io/badge/Tests-630%2F630_passing-green)

Supports Retail and WoW Forever. Range Master lets you build your own range displays for your
target, your focus, your pet, whatever is under your mouse, and every enemy nameplate on screen.

Each display is a container. You pick its unit, then what it shows: the distance as a number, a
word such as "Melee" or "Out of range", a colored dot or shape, and a row of your own spells that
light up when that spell would reach. The distance is split into bands, and every band has its own
color, so a glance tells you whether you can hit the thing in front of you. Band sets are shared, so
one change to your caster bands updates every display that uses them.

A display can sit anywhere on screen, hang off a unit frame (Blizzard's or EllesmereUI's, or any
frame you point at), ride on a nameplate, or follow your cursor.

Version 0.1.0 has not been released yet.

## Screenshots

Screenshots arrive with the first release.

## Usage

The first time you log in, Range Master opens its preset picker. Pick **Simple** (four displays free
on screen), **Intermediate** (on your unit frames and the cursor) or **Advanced** (adds nameplates,
spell chips and a warning sound) from its dropdown and it shows on your screen in test mode right
away; **Apply** keeps it, **Not now** puts your own displays back. Open the picker again any time
with `/rm preset`, or use General → Presets, or type `/rm preset simple`. If you already have displays, applying a
preset asks first, and **Undo last preset** (or `/rm preset undo`) puts them back.

To build one yourself, open the **Containers** page with `/rm` and press New container. Pick its
unit, its band set and where it sits, then what it shows. The **Band sets** page holds the distance
bands every display colors by: where each band ends, its name, its colors and an optional sound. From
chat, `/rm new focus` makes a display, `/rm containers` lists them, and `/rm select 2` picks the one
that `container.` settings change, for example `/rm set container.anchor.mode cursor`.

Displays start locked. Type `/rm unlock` and every display shows, even one whose unit isn't there
(it shows a placeholder range until combat starts) with a handle on top: its name, a gear that opens
its settings and an X that turns it off. Drag a free-on-screen display by its handle. A display that
follows the cursor or sits on a nameplate waits at a fixed spot while unlocked, and dragging it
picks that spot. A display on a unit frame stays on its frame; `/rm lock` locks them again, and `/rm resetposition` brings them all back near the middle. Under
Visibility on the Containers page, a display can show only in combat or only out of it, only for enemies or only for
friends, and hide when it has no unit. To place and style displays without a target, turn on Test
mode, which fills each one with a sample range. Sim mode walks a pretend target in and out of your
bands so you can see every color and hear every sound. Both stop when combat starts and can't be
turned on during it. The minimap button opens the settings, and right-clicking it gives a quick menu
for turning the addon on or off, locking, and the two modes.

`/rm skin` opens the skin picker, which sets how Range Master's windows, settings pages and displays
look. While it is open your displays show sample ranges, and the eye button turns that off and on.
**Apply** keeps your choice; closing the picker without it puts the old look back.

Everything else is under Settings → AddOns → Ka0s Range Master, and `/rm help` (or
`/rangemaster help`) lists every command.

## How it works

- The game lets an addon ask whether a unit is within reach of one of your spells or items, not how
  far away it is. Range Master asks that question for a ladder of spells and items at known
  distances, through the LibRangeCheck library, and turns the answers into a bracket such as "20 to
  25 yards".
- One shared timer does the asking, ten times a second out of combat and twenty times in it, and
  only for units a display is watching. It stops when nothing needs it.
- Each display looks the bracket up in its band set and colors itself by the band it lands in. It
  only redraws when the band or the text changes.
- When the game will not answer, for example because the unit is out of sight or the value is
  hidden from addons, the display shows a gray "?" rather than guessing.

## FAQ

| Question | Answer |
|----------|--------|
| Does it show the exact distance? | No addon can. The game only answers "in range of this spell or not", so Range Master shows the narrowest bracket the answers allow. |
| Does it work on WoW Forever? | Yes, from the same download. Range Master uses each client's own spells and items to measure distance. |
| Can I have a different band set for friends? | Yes. Each display has a Friendly band set, used whenever its unit is friendly. The Intermediate preset sets it to Healer. |
| Will it slow my game down? | It does one small pass ten or twenty times a second, only while a display is watching a unit, and none at all when the addon is turned off. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing shows at all | On General → Master controls, check that **Enable Range Master** is ticked (`/rm enable` ticks it) and that **General visibility** isn't set to *Never*, or to a combat state you're not in. |
| One display never shows | Check its Visibility tab: it may be set to combat only, to one reaction, or to hide when it has no unit. |
| A display meant for a unit frame is missing | The frame it waits for isn't there: EllesmereUI is turned off, that EllesmereUI frame is disabled, or a custom frame name is misspelled. Fix the name on Containers → General → Position, or use **Pick on screen**. |
| I can't drag a display | Type `/rm unlock`. A display on a unit frame follows its frame and can't be dragged (its handle's name is grayed); nothing drags during combat. |
| A display shows a gray "?" | The game isn't giving a range for that unit right now, usually because it is out of sight. It is not the same as out of range. |
| I only see sample ranges | Test mode is on. Type `/rm test off`, or untick **Test mode** under General → Master controls. |
| Test mode or Sim mode will not start | Neither can start during combat. Wait until combat ends and try again. Test mode also waits while Sim mode runs: type `/rm sim off` first. |
| Something looks wrong and I want to report it | Follow [Reporting a bug](#reporting-a-bug) below. |

## Reporting a bug

- Type `/rm debug on` and reproduce the bug.
- Type `/rm diagnostics`.
- If the debug window isn't open, open it with `/rm debug`. Press **Copy**, copy the entire output, and include it with your bug report.

The report is added after the debug trace in the same window, so one copy carries both.

## Issues and feature requests

Bugs, ideas and planned work all go in the GitHub issue tracker:
[https://github.com/tusharsaxena/RangeMaster/issues](https://github.com/tusharsaxena/RangeMaster/issues).
Please file reports there rather than in comments, so nothing gets lost.

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 0.1.0 | Unreleased | - Range displays for your target, focus, pet, mouseover and every enemy nameplate, each showing a range bracket as a number, a band name, a colored shape and your own spells<br>- Shared band sets with their own colors and sounds, and a separate set for friendly units<br>- Displays free on screen, on Blizzard or EllesmereUI unit frames or any frame you click, on nameplates, or at the cursor<br>- Simple, Intermediate and Advanced presets, offered on first run, with Undo<br>- Visibility by combat, reaction and missing unit<br>- Test mode and Sim mode for placing and checking your displays<br>- Works on Retail and WoW Forever |

## Credits

The debug console's close, copy and clear buttons, the skin picker's preview and settings buttons,
and the other marks the shared Ka0s windows draw come from
[Open Iconic](https://github.com/iconic/open-iconic) by Waybury (MIT). Only the icons the addon draws
are shipped, inside the LibKa0s payload, with their license text beside them.
