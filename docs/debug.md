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

What the addon logs, one gated line each: every settings write at the seam (`[Set] path = value`),
each preview-mode change and refusal (`[Mode]`), the combat edge (`[Combat]`), the world entry
(`[World]`), each profile event (`[Profile]` / `[Set]`), each refused event once (`[Events]`) and
each migration step (`[Migrate]`). The library writes its own lines through the same sink: the
dispatcher's refusals (`[Cmd]`), the options combat lock (`[Cfg]`), the launcher's registration
(`[Launcher]`, held until logging is on) and every stand-down and stand-up edge (`[Lifecycle]`).

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
