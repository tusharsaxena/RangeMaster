# Slash dispatch — Ka0s Range Master

`/rm` and `/rangemaster` (`settings/Slash.lua`), dispatched by `LibKa0s-Slash-1.0` over the ordered
`NS.COMMANDS` table. The dispatcher, the help renderer, the formatters and the type-aware value parser
are the library's; the verb table and the host verbs are this addon's. A bare `/rm` opens the
settings panel in either state; `/rm options` is an alias of `config`.

| Verb | Arguments | Live while disabled | What it does |
|---|---|---|---|
| `help` | — | yes | prints the command list |
| `config` | — | yes | opens the settings panel (refused in combat by the library) |
| `skin` | — | no | opens the skin picker (`NS.RunSkinVerb`, skinning-§3) |
| `enable` | — | yes | writes `enabled = true` through the seam, re-reads the latch, echoes `enabled = true` |
| `disable` | — | yes | writes `enabled = false`; the addon stands down |
| `list` | — | yes | every setting and its value, grouped by page |
| `get` | path | yes | one setting's value |
| `set` | path value | yes | writes through `NS.SetByPath`; echoes the stored value |
| `reset` | path | yes | one setting back to its default |
| `resetall` | — | yes | every setting back to defaults (a profile reset) |
| `profile` | [name] | yes | lists profiles, or switches to an existing one |
| `lock` / `unlock` | — | no | writes `locked` and echoes it |
| `resetposition` | — | no | `NS.ResetPositions`: every screen container back at its new-container point; echoes how many moved |
| `containers` | — | no | lists the containers as `n. Name (unit, anchor)`, the selected one marked `*` |
| `select` | number or name | no | selects a container (a name matches in any case); `container.*` paths then mean it |
| `new` | [unit] | no | creates a container (`target` when bare; `focus`, `pet`, `mouseover`, `nameplates`) and selects it; an unknown unit prints the usage line |
| `delete` | number or name | no | deletes a container and selects its neighbor |
| `pick` | — | no | starts the click-to-pick overlay for the selected container; a pick attaches it to that frame by name (refused in combat by the picker) |
| `bands` | [number or name] | no | bare: lists the band sets, the selected one marked, and the selected set's ribbon; with an argument selects one (`bandSet.*` paths then mean it) |
| `preset` | `simple`, `intermediate`, `advanced` or `undo` | no | applies a preset behind the same confirm as the Presets tab (none on an empty profile); `undo` puts back what the last one replaced |
| `test` | [on\|off] | no | toggles or sets Test mode (`NS.SetTestMode`); refused in combat |
| `sim` | [on\|off], or a simulator verb | no | bare, `on` or `off` toggles or sets Sim mode (`NS.SetSimMode`), refused in combat; any other word is LibKa0s-Sim's own verb (`status`, `step`, `pause`, `resume`, `restart`, `stop`, `panel`, `start sweep`; `NS.Sim.RunVerb`), its answer printed in chat |
| `debug` | [on\|off\|diagnostics] | yes | bare: toggles the console window; on/off: session logging; diagnostics: the report |
| `diagnostics` | — | yes | writes the diagnostics report to the console (debug-logging-§14) |
| `perf` | [step] | yes | the perf harness's verb; bare prints the workflow (performance-§4) |
| `version` | — | yes | prints the version |

**Disabled.** The live set is the library's `LIVE_VERBS` plus `diagnostics` and `profile`. Every other
verb answers one line, the library's `DisabledLine()`: `Ka0s Range Master is disabled — enable it with
/rm enable`, and writes nothing (slash-commands-§7). Each refusal the dispatcher decides writes one
`[Cmd]` line to the console; no host verb repeats it.

**Perf-suspended.** Under a performance capture's `perf` hold alone the stored `enabled` path is on,
so the library's gate lets a feature verb through; each feature verb is wrapped once
(`settings/Slash.lua`) to answer `NS.RefusalLine()` on one line, `Not available during a performance
capture.`, and do nothing else. It never names `/rm enable`, which would change nothing. Under both
holds the disabled line wins (slash-commands-§7, *Which refusal, by hold*).

**Library absent.** The stub answers every verb: the host verbs keep working, the schema verbs print
`/rm <verb> is unavailable: the LibKa0s library did not load.`, and the help rows print plainly.

**Selection-relative paths.** `get`, `set` and `reset` take `container.<field>` and `bandSet.<field>`
paths (`/rm set container.unit focus`), which mean the selected container or band set
(`docs/schema.md`). With no container, a `container.` write is refused with a line naming `/rm new`.
