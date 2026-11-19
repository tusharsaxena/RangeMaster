std = "lua51"
max_line_length = false
codes = true

-- libs/ holds vendored code, including libs/LibKa0s/ whose upstream is the LibKa0s repo, so it is
-- linted there and not here. tests/_kit/ is the same fact one level down: a byte copy of the
-- library's testkit/, linted in LibKa0s as source. Everything else under tests/ is ours and is
-- linted (lint). Under docs/ only the FROZEN record bundles are excluded.
exclude_files = { "libs/", "tests/_kit/", "docs/audits/", "docs/reviews/", "docs/revendor/",
  "docs/automated-tests/", "_dev/" }

-- NO TOP-LEVEL `ignore` (lint): an entry at the top level reaches every file whatever it names.
-- The `files[...]` stanzas at the foot each name one file and the variable that earns the code, and
-- tests/test_lintconfig.lua keeps a blanket from re-entering.

-- The WoW client API this addon reads. A name nothing reads comes off the list (test_lintconfig).
read_globals = {
  "_G", "LibStub", "CreateFrame", "UIParent", "STANDARD_TEXT_FONT", "C_AddOns",
  "UnitClass", "RAID_CLASS_COLORS",          -- core/CoreSetup.lua's library-absent class resolver
  "InCombatLockdown", "Settings", "SettingsPanel",
  "issecretvalue", "canaccessvalue",         -- core/Compat.lua's guard stand-ins
  "debugprofilestop",                        -- the perf bracket's clock (performance-§2)
  "DEFAULT_CHAT_FRAME", "StaticPopup_Show",
  "StaticPopup_Hide",                        -- settings/Presets.lua: the first-run picker taken down
  -- core/Compat.lua's range reads and the per-client ladder (design spec 5.1)
  "C_Spell", "C_SpellBook", "C_Item", "CheckInteractDistance", "UnitCanAttack", "UnitRace",
  "C_EventUtils",                            -- core/Compat.lua's IsEventValid
  "GetShapeshiftFormID",                     -- core/Compat.lua's ShapeshiftFormID (a druid's melee anchor)
  "UnitExists",                              -- modules/Range.lua: "none" is a unit that does not exist
  "UnitIsFriend",                            -- core/Compat.lua's IsFriend (modules/BandSets.lua's friendly override)
  "C_Timer",                                 -- modules/Ticker.lua's ticker, modules/Range.lua's rebuild debounce
  "BackdropTemplateMixin", "Mixin",           -- modules/Style.lua's media border, on a plain frame
  -- core/Compat.lua's plate and mouse-focus reads, and the anchors' cursor (design spec 5.4)
  "C_NamePlate", "GetMouseFoci", "GetCursorPosition", "IsMouseButtonDown",
  "UnitCastingInfo", "UnitChannelInfo",       -- core/Compat.lua's IsCasting (a plate's "while casting" part)
  -- the band sounds' clock and the client's sound call (modules/Sounds.lua, modules/Container.lua)
  "GetTime", "PlaySoundFile",
  -- settings/Containers_Display.lua: the element list's on/off tick tooltip
  "GameTooltip", "HIGHLIGHT_FONT_COLOR",
}

globals = {
  "RangeMasterDB",       -- the SavedVariables write target
  "RangeMasterPerfDB",   -- the diagnostics capture ring (performance-§5)
  "StaticPopupDialogs",  -- the Reset-all confirmation registers here
  "UISpecialFrames",     -- modules/Sim.lua takes the step panel off Escape's list while a sweep runs
}

-- The harness global is declared HERE rather than in the top-level `read_globals`: no shipped file
-- may reach for the test harness (lint). The SavedVariables tables are named as fields so a suite
-- clearing one says so.
files["tests/"] = {
  globals = { "_G.RM_TEST", "_G.RangeMasterDB", "_G.RangeMasterPerfDB" },
  read_globals = { "arg" },
}

-- AceAddon calls its lifecycle and event handlers as METHODS (addon:OnEnable(), an AceEvent handler
-- registered by name), so they keep the colon where a body never reads `self`. Narrowed to the file.
files["core/RangeMaster.lua"] = {
  ignore = { "212/self" },
}

-- `NS:InitDB` and `NS:RunMigrations` are reached with a colon; the bodies address NS directly
-- because the receiver and the namespace are the same table.
files["core/Database.lua"] = {
  ignore = { "212/self" },
}

-- The degraded `SlashLib.New` mirrors the library's `lib:New(d)`, and `Sl:LandingRows`, `Sl:OnSlash`,
-- `Sl:DisabledLine` and `Sl:Register` mirror the library instance, which the parity gate asserts.
files["settings/Slash.lua"] = {
  ignore = { "212/self" },
}
