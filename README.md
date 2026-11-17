# Range Master

![WoW](https://img.shields.io/badge/WoW-Midnight_12.1.5_and_Forever_1.60.1-purple)
![License](https://img.shields.io/badge/License-MIT-orange)
![Standard](https://img.shields.io/badge/Ka0s-WoW_Addon_Standard-yellow)
![Tests](https://img.shields.io/badge/Tests-436%2F436_passing-green)

Supports Retail and WoW Forever. Range Master lets you build your own range displays for your
target, your focus, your pet, whatever is under your mouse, and every enemy nameplate on screen.

Each display is a container. You pick its unit, then what it shows: the distance as a number, a
word such as "Melee" or "Out of range", a colored dot or shape, and a row of your own spells that
light up when that spell would reach. The distance is split into bands, and every band has its own
color, so a glance tells you whether you can hit the thing in front of you. Band sets are shared, so
one change to your caster bands updates every display that uses them.

A display can sit anywhere on screen, hang off a unit frame (Blizzard's or EllesmereUI's, or any
frame you point at), ride on a nameplate, or follow your cursor.

Range Master is in development. Version 0.1.0 is not out yet, and this page describes what it is
being built to do.

## Screenshots

Screenshots arrive with the first release.

## Usage

Type `/rm` to open the settings, or click the minimap button. Right-click the minimap button for a
quick menu: turn the addon on or off, lock the displays, and switch Test mode or Sim mode.

Test mode fills every display with a sample range, so you can place and style it without a target.
Sim mode walks a pretend target in and out of your range bands, so you can watch every color and
sound change in turn. Both stop as soon as you enter combat, and neither can be started in one.

`/rm skin` opens the skin picker, where you choose how Range Master's windows, settings pages and
displays look. `/rm help` lists every command, and `/rm diagnostics` writes a report you can paste
into a bug report.

Everything else is under Settings → AddOns → Ka0s Range Master, and every setting can also be read
and changed from chat: `/rm list` shows them all.

## How it works

- The game lets an addon ask whether a unit is within reach of one of your spells or items, not how
  far away it is. Range Master asks that question for a ladder of spells and items at known
  distances, through the LibRangeCheck library, and turns the answers into a bracket such as "20 to
  25 yards".
- One shared timer does the asking, ten times a second out of combat and twenty times in it, and
  only for units a display is watching. It stops when nothing needs it.
- Each display looks the bracket up in its band set and colors itself by the band it lands in.
- When the game will not answer, for example because the unit is out of sight or the value is
  hidden from addons, the display shows a gray "?" rather than guessing.

## FAQ

**Does it show the exact distance?**
No addon can. The game only answers "in range of this spell or not", so Range Master shows the
narrowest bracket the answers allow.

**Does it work on WoW Forever?**
Yes. Range Master uses each client's own spells and items to measure distance.

**Will it slow my game down?**
It does one small pass ten or twenty times a second, only while a display is watching a unit, and
none at all when the addon is turned off.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Nothing shows at all | On General → Master controls, check that **Enable Range Master** is ticked (`/rm enable` ticks it) and that **General visibility** isn't set to *Never*, or to a combat state you're not in. |
| I only see sample ranges | Test mode is on. Type `/rm test off`, or untick **Test mode** under General → Master controls. |
| Test mode or Sim mode will not start | Neither can start during combat. Wait until combat ends and try again. |
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
| 0.1.0 | Unreleased | - In development: range displays for target, focus, pet, mouseover and nameplates |

## Credits

The debug console's close, copy and clear buttons, the skin picker's preview and settings buttons,
and the other marks the shared Ka0s windows draw come from
[Open Iconic](https://github.com/iconic/open-iconic) by Waybury (MIT). Only the icons the addon draws
are shipped, inside the LibKa0s payload, with their license text beside them.
