local _, NS = ...
-- locales/enUS.lua — the canonical locale (localization-§1). Loads FIRST in the TOC, ahead of
-- core/, so it bootstraps NS.L for every file after it.
--
-- The metatable returns the KEY on a miss, so a string routed before this file lists it still renders
-- in English, and a partial translation degrades one string at a time rather than to nil. Keys ARE
-- the English source strings (localization-§2); a translation copies this file, gates it with
-- GetLocale() and changes only the right-hand sides.
--
-- GENERATED KEY SET: every `L["…"]` subscript in the addon's own source, grouped by the file that
-- first reads it, in TOC order. tests/test_locale.lua fails on a subscript missing here and on a key
-- nothing uses.

NS.L = setmetatable(NS.L or {}, { __index = function(_, k) return k end })
local L = NS.L

-- core/CoreSetup.lua
L["The LibKa0s library is missing from this installation of Range Master (expected in libs/LibKa0s)"] = "The LibKa0s library is missing from this installation of Range Master (expected in libs/LibKa0s)"
L["%s; running on reduced built-in fallbacks."] = "%s; running on reduced built-in fallbacks."

-- core/SkinSetup.lua
L["%s is unavailable: the LibKa0s library did not load."] = "%s is unavailable: the LibKa0s library did not load."

-- core/PerfSetup.lua
L["%s, so performance measurement is unavailable."] = "%s, so performance measurement is unavailable."

-- core/Database.lua
L["Settings upgrade stopped at v%s -> v%s; saved settings were left as they were."] = "Settings upgrade stopped at v%s -> v%s; saved settings were left as they were."

-- core/DebugLogSetup.lua
L["%s, so the debug console window is unavailable."] = "%s, so the debug console window is unavailable."
L["Debug logging on."] = "Debug logging on."
L["Debug logging off."] = "Debug logging off."
L["Diagnostic report written to the debug console: %d lines. Use Copy to share it."] = "Diagnostic report written to the debug console: %d lines. Use Copy to share it."

-- core/LauncherSetup.lua
L["%s, so the minimap button is unavailable."] = "%s, so the minimap button is unavailable."

-- core/RangeMaster.lua
L["Cannot start a preview mode during combat."] = "Cannot start a preview mode during combat."
L["Cannot start a preview mode while Range Master is stood down."] = "Cannot start a preview mode while Range Master is stood down."

-- defaults/BandSetPresets.lua
L["Melee / Ranged"] = "Melee / Ranged"
L["MELEE"] = "MELEE"
L["CLOSE"] = "CLOSE"
L["MID"] = "MID"
L["LONG"] = "LONG"
L["OOR"] = "OOR"
L["Caster 40"] = "Caster 40"
L["Healer"] = "Healer"
L["NEAR"] = "NEAR"
L["FAR"] = "FAR"
L["Hunter"] = "Hunter"
L["DEAD"] = "DEAD"
L["AUTO"] = "AUTO"
L["RANGED"] = "RANGED"

-- modules/BandSets.lua
L["New band set"] = "New band set"
L["%s copy"] = "%s copy"

-- modules/ContainerManager.lua
L["Target"] = "Target"
L["Focus"] = "Focus"
L["Pet"] = "Pet"
L["Mouseover"] = "Mouseover"
L["Nameplates"] = "Nameplates"
L["Container"] = "Container"

-- modules/Presets.lua
L["Target plate"] = "Target plate"
L["Simple"] = "Simple"
L["Intermediate"] = "Intermediate"
L["Advanced"] = "Advanced"
L["Target, Focus, Pet, Mouseover: free on screen"] = "Target, Focus, Pet, Mouseover: free on screen"
L["Number + frame colored by band"] = "Number + frame colored by band"
L["One band set (class default)"] = "One band set (class default)"
L["No sounds, always visible when the unit exists"] = "No sounds, always visible when the unit exists"
L["Target / Focus / Pet attached to their unit frames"] = "Target / Focus / Pet attached to their unit frames"
L["Mouseover follows the cursor"] = "Mouseover follows the cursor"
L["Number + text label + dot"] = "Number + text label + dot"
L["Hostile vs friendly band sets"] = "Hostile vs friendly band sets"
L["Hidden while there is no unit"] = "Hidden while there is no unit"
L["Everything in Intermediate"] = "Everything in Intermediate"
L["Target on its own nameplate + dot on all hostile plates"] = "Target on its own nameplate + dot on all hostile plates"
L["Focus with spell-range chips (class spells)"] = "Focus with spell-range chips (class spells)"
L["Band-change sound (out-of-range warning)"] = "Band-change sound (out-of-range warning)"
L["Visibility rules: nameplates in combat only, hostile only"] = "Visibility rules: nameplates in combat only, hostile only"

-- modules/Elements_Number.lua
L["%s yd"] = "%s yd"

-- settings/Slash.lua
L["List available commands"] = "List available commands"
L["Open the settings panel"] = "Open the settings panel"
L["Choose a skin: open the skin picker"] = "Choose a skin: open the skin picker"
L["Turn Range Master on"] = "Turn Range Master on"
L["Turn Range Master off \226\128\148 /rm enable turns it back on"] = "Turn Range Master off \226\128\148 /rm enable turns it back on"
L["List every setting and its current value"] = "List every setting and its current value"
L["Print a setting's current value \226\128\148 /rm get path"] = "Print a setting's current value \226\128\148 /rm get path"
L["Set a setting \226\128\148 /rm set path value (try /rm list)"] = "Set a setting \226\128\148 /rm set path value (try /rm list)"
L["Reset one setting to its default \226\128\148 /rm reset path"] = "Reset one setting to its default \226\128\148 /rm reset path"
L["Reset every setting to defaults"] = "Reset every setting to defaults"
L["List profiles, or switch to one: profile <name>"] = "List profiles, or switch to one: profile <name>"
L["Lock every range display in place"] = "Lock every range display in place"
L["Unlock the range displays so they can be dragged"] = "Unlock the range displays so they can be dragged"
L["Move every range display back to its default position"] = "Move every range display back to its default position"
L["Toggle Test mode: placeholder ranges on every display \226\128\148 /rm test [on|off]"] = "Toggle Test mode: placeholder ranges on every display \226\128\148 /rm test [on|off]"
L["Toggle Sim mode: a simulated target walks through your range bands \226\128\148 /rm sim [on|off]"] = "Toggle Sim mode: a simulated target walks through your range bands \226\128\148 /rm sim [on|off]"
L["Toggle the debug console \226\128\148 on/off enable/disable logging"] = "Toggle the debug console \226\128\148 on/off enable/disable logging"
L["Write a diagnostics report to the debug console"] = "Write a diagnostics report to the debug console"
L["Measure performance \226\128\148 try /rm perf for the workflow"] = "Measure performance \226\128\148 try /rm perf for the workflow"
L["Print the addon version"] = "Print the addon version"
L["Range Master enabled"] = "Range Master enabled"
L["Range Master disabled \226\128\148 /rm enable turns it back on"] = "Range Master disabled \226\128\148 /rm enable turns it back on"
L["All settings reset to defaults."] = "All settings reset to defaults."
L["Cannot reset settings \226\128\148 the settings helpers failed to load."] = "Cannot reset settings \226\128\148 the settings helpers failed to load."
L["%s range display position(s) reset"] = "%s range display position(s) reset"
L["Range displays locked"] = "Range displays locked"
L["Range displays unlocked \226\128\148 drag one by its handle"] = "Range displays unlocked \226\128\148 drag one by its handle"
L["Usage: /rm test [on|off]"] = "Usage: /rm test [on|off]"
L["Test mode on \226\128\148 every range display shows placeholder ranges"] = "Test mode on \226\128\148 every range display shows placeholder ranges"
L["Test mode off"] = "Test mode off"
L["Usage: /rm sim [on|off]"] = "Usage: /rm sim [on|off]"
L["Sim mode on \226\128\148 a simulated target walks through your range bands"] = "Sim mode on \226\128\148 a simulated target walks through your range bands"
L["Sim mode off"] = "Sim mode off"
L["v%s \226\128\148 slash commands"] = "v%s \226\128\148 slash commands"
L["Unknown command '%s'"] = "Unknown command '%s'"

-- settings/OptionsSetup.lua
L["%s, so the settings panel is unavailable."] = "%s, so the settings panel is unavailable."

-- settings/About.lua
L["Slash Commands"] = "Slash Commands"

-- settings/General.lua
L["Refused in combat, and entering combat turns it off."] = "Refused in combat, and entering combat turns it off."
L["Skin source"] = "Skin source"
L["Where this addon's look comes from: the Ka0s skin chosen below, or EllesmereUI."] = "Where this addon's look comes from: the Ka0s skin chosen below, or EllesmereUI."
L["Skin"] = "Skin"
L["The Ka0s skin this addon wears. Changes the range displays, the tool windows and the settings pages right away."] = "The Ka0s skin this addon wears. Changes the range displays, the tool windows and the settings pages right away."
L["Ignore settings panel"] = "Ignore settings panel"
L["Keep this addon's settings panel in the game's own look. Its other surfaces still wear the skin."] = "Keep this addon's settings panel in the game's own look. Its other surfaces still wear the skin."
L["Ignore fonts"] = "Ignore fonts"
L["Keep every font in this addon as the game draws it. The skin still colors the text."] = "Keep every font in this addon as the game draws it. The skin still colors the text."
L["Font"] = "Font"
L["The font this addon's text uses, over the skin's own. Empty keeps the skin's."] = "The font this addon's text uses, over the skin's own. Empty keeps the skin's."
L["Texture"] = "Texture"
L["The texture this addon's displays use, over the skin's own. Empty keeps the skin's."] = "The texture this addon's displays use, over the skin's own. Empty keeps the skin's."
L["Font outline"] = "Font outline"
L["Where the skin outlines this addon's text: all of it, its HUD text only, or nowhere."] = "Where the skin outlines this addon's text: all of it, its HUD text only, or nowhere."
L["Skin picker seen"] = "Skin picker seen"
L["Whether the first-run skin picker was closed on this profile."] = "Whether the first-run skin picker was closed on this profile."
L["Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded \226\128\148 your other profiles are not affected."] = "Reset this profile to the addon's defaults? Everything you have configured or added in it is discarded \226\128\148 your other profiles are not affected."
L["Yes"] = "Yes"
L["No"] = "No"
L["Restore every General setting on this profile to its addon default."] = "Restore every General setting on this profile to its addon default."
