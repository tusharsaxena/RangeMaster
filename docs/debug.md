# Debug — Ka0s Range Master

The debug surfaces beyond the library's default console: the session log and the diagnostics report.

## The debug console

`LibKa0s-DebugLog-1.0`, wired by `core/DebugLogSetup.lua`. `/rm debug` shows or hides the window and
leaves logging alone; `/rm debug on` and `/rm debug off` switch session logging through the one
`SetEnabled` seam; the Master controls **Debug console** row is the window's checkbox. Logging is
session-only (`NS.State.debug`), off at login and after every `/reload`, never saved
(debug-logging-§5), and it runs with the window closed, so a bug can be reproduced first and the log
opened after. When logging turns on, the library writes the `[Init]` line: name, version, schema
stamp and profile, plus the refused events, the stand-down holds and any missing library when there
are some.

What the addon logs, one gated line each:

| Tag | Written by | When |
|---|---|---|
| `[Set]` | `settings/Schema.lua` (the write seam), `core/RangeMaster.lua` | every settings write (`path = value`), and a profile copy or reset |
| `[Profile]` | `core/RangeMaster.lua` | a profile switch |
| `[Mode]` | `core/RangeMaster.lua` | each Test mode or Sim mode change, and each refusal |
| `[Sim]` | `modules/Sim.lua` | the LibKa0s-Sim session's own lines (start, step, stop and its reason) |
| `[Combat]` | `core/RangeMaster.lua` | the combat edge |
| `[World]` | `core/RangeMaster.lua` | the world entry |
| `[Containers]` | `modules/ContainerManager.lua` | a container created, moved, deleted, duplicated or copied onto, a snapshot restored, and an apply held for combat |
| `[Presets]` | `modules/Presets.lua`, `settings/Presets.lua` | a preset applied, an undo (or the slot dropped by a profile change), the first-run picker shown and marked seen |
| `[Position]` | `core/RangeMaster.lua` | Reset position, with how many displays moved |
| `[Anchor]` | `modules/Anchors_Frame.lua`, `modules/FramePicker.lua` | a unit-frame anchor held for combat, a frame missing (the container hidden until it appears) or found, and each frame pick started, refused, picked or canceled |
| `[Bus]` | `core/Bus.lua` | a subscription the stand-up could not restore |
| `[Events]` | `core/RangeMaster.lua` | each event the client refused, once a session |
| `[Migrate]` | `core/Database.lua` | each migration step |

The range engine, the ticker and the renderer log nothing per tick: a line per read at 20 Hz would
bury everything else, and the perf harness (`docs/performance.md`) is how their cost is seen. The library writes its own lines through the same sink: the
dispatcher's refusals (`[Cmd]`), the options combat lock (`[Cfg]`), Add a table row: | `[Launcher]` | `core/LauncherSetup.lua` | a launcher menu entry whose `/rm` verb has no handler | and every stand-down and stand-up edge (`[Lifecycle]`).

## The diagnostics report (debug-logging-§14)

Two forms and no third: `/rm diagnostics` and `/rm debug diagnostics`; the console's orange
**Diagnostics** link runs the same report. No `diag` or `dump` alias.

- **What a run does.** It turns session logging on first when it is off (this addon does not opt
  out), then appends the report to the console, ungated, after whatever the log already holds — it
  never clears. It runs while the addon is disabled. Chat gets one line: `Diagnostic report written
  to the debug console: N lines. Use Copy to share it.`
- **What the library writes.** Both markers, carrying the brand `Ka0s Range Master`; its identity
  header (client build, locale, the debug flag, both combat reads, the running LibKa0s minors, the
  `[Init]` summary); a `pcall` per section, so a raising section costs one line; the cap and its
  `truncated` line.
- **What this addon writes** (`modules/Diagnostics.lua`), in order:

| Section | Lines |
|---|---|
| `state` | schema stamp stored and in code; profile; client key; enabled and stood down; Test mode and Sim mode |
| `lifecycle` | the latch's holds; whether a perf capture is running; whether the bus is live |
| `settings` | every row whose value differs from its default, as `path = value (default)`, and always `enabled`, `visibility`, `alpha`, `scale`, `locked` and `global.minimap.shown` |
| `events` | the events the addon object holds, or that it is stood down |
| `rejected` | the event names this client refused this session |
| `ui` | whether the settings panel is open; the launcher's registration and shown state; any library that did not load |

- **What it does not read or call.** It reads state only: no event, timer, hold, stand-up or write,
  no settings panel open and no Clear. It reads no range, no unit and no other addon's data.
- **Library absent.** Both forms print `/rm diagnostics is unavailable: the LibKa0s library did not
  load.` and write nothing.

To report a bug, the README's `## Reporting a bug` steps are the ones to give a player.
