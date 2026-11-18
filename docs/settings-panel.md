# Settings panel — Ka0s Range Master

Settings → AddOns → **Ka0s Range Master**, built by `LibKa0s-Options-1.0` from the schema
(`settings/OptionsSetup.lua`). The category registers eagerly at load; each page's body builds on its
first show (options-ui-§5). Every page but the landing page and Profiles is a tab strip
(options-ui-§13). Opening the panel in combat is refused with a gray line, and a page shown in combat
by the sidebar is covered by the library's lock (options-ui-§2).

| Page | Covers |
|---|---|
| Ka0s Range Master (landing) | The logo, the TOC Notes line and the slash command list (`settings/About.lua`) |
| General | Master controls and the skin (`settings/General.lua`) |
| Profiles | AceDB profiles: switch, copy, delete, reset (`settings/Profiles.lua`) |

The Containers, Band sets and Presets pages arrive in plan Task 8 (design spec section 5.6).

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
| Lock frame | `locked` | locked displays cannot be dragged; unlocked, every screen container shows its drag strip (`NS.Anchors.RefreshLock`) |
| Debug console | `state.debugConsole` | session-only; shows or hides the console window |
| Minimap button | `global.minimap.shown` | stored in the global store under LibDBIcon's `hide`, inverted; survives every reset (launcher-§3) |
| Test mode | `state.testMode` | session-only; placeholders on every display; refused in combat and ended by it (`NS.SetTestMode`) |
| Sim mode | `state.sim` | session-only; the launcher's pair, `NS.IsSimMode` / `NS.ToggleSimMode`, same as `/rm sim` |
| Reset position (button) | — | `NS.ResetPositions`, the same handler as `/rm resetposition`: every screen container back at its new-container point |
| Reset all settings (button) | — | confirms, then `NS.Helpers.RestoreAllDefaults`, the same as `/rm resetall` |

The header **Defaults** button restores every General row on this profile except the minimap row.

### Skin

The library's `O.AppearanceTab` (skinning-§3), drawn over the `skin.*` skip-render rows: source, skin,
the Scope's Ignore settings panel and Ignore fonts, the Font and Texture overrides and the Font outline.
A pick lands through `NS.WriteSkinChoice` and the write seam.

## The launcher

One LibDataBroker launcher object registered with LibDBIcon (`core/LauncherSetup.lua`), labeled
`Ka0s Range Master`, with the 128 logo. Left-click opens the settings; right-click opens the menu:
**Enabled**, **Locked**, **Test mode**, **Sim mode**, each the matching slash verb's own handler, and
the library's *Open skin selector*. While disabled, every entry but Enabled is grayed. There is no
Show window entry and no key binding: the addon has no primary window.
