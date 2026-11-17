-- tests/wow_mock.lua — Ka0s Range Master's WoW-API mock: the shared base (tests/_kit/mock_base.lua)
-- plus the few APIs this addon reads that the base does not answer the way a suite needs.
--
-- Returns a builder, so each environment gets a fresh, isolated mock. Everything universal — frames,
-- timers, the Settings canvas API, LibStub, the Ace fakes, the capture-context lookups — lives in the
-- kit and is documented there. Only what is genuinely this addon's belongs here: a base that stubbed
-- every addon's APIs would hide a missing stub behind a neighbor's. What LibRangeCheck-3.0 reads at
-- LOAD is answered here, so tests/run.lua loads the vendored library as the TOC does; the answers its
-- range queries need (spellbook contents, unit existence per token) join with the range engine (the
-- v0.1.0 plan, Task 2).

local base = dofile("tests/_kit/mock_base.lua")

return function()
  local M = base()

  -- The client's default face, read by core/SkinSetup.lua's degraded HudFont.
  M.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

  -- The class-color table core/CoreSetup.lua's library-absent resolver reads, as LibKa0s-Core does.
  M.RAID_CLASS_COLORS = {
    MAGE    = { r = 0.25, g = 0.78, b = 0.92 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
  }

  -- LibRangeCheck-3.0's load-time reads (libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua:75-131 and its
  -- activate()): the spellbook bank enum and API, the hands slot, and the interact-distance check.
  -- An empty spellbook: the library builds its checker lists from its interact defaults alone.
  if type(M.Enum) ~= "table" then M.Enum = {} end
  M.Enum.SpellBookSpellBank = M.Enum.SpellBookSpellBank or { Player = 0, Pet = 1 }
  M.C_SpellBook = M.C_SpellBook or {
    GetSpellBookItemName      = function() return nil end,
    GetSpellBookItemInfo      = function() return nil end,
    GetNumSpellBookSkillLines = function() return 0 end,
    GetSpellBookSkillLineInfo = function() return nil end,
  }
  M.C_PaperDollInfo = M.C_PaperDollInfo or { GetInventorySlotInfo = function() return 10 end }
  M.CheckInteractDistance = M.CheckInteractDistance or function() return false end
  -- C_Timer.NewTicker, which the kit's C_Timer does not carry (LibRangeCheck arms a 5 s cache
  -- ticker at load). Built on the kit's NewTimer, so it queues, cancels and reports in M.__timers()
  -- exactly as that handle does; it does not re-arm, which no suite yet needs.
  M.C_Timer.NewTicker = M.C_Timer.NewTicker or function(delay, fn, iterations)
    local t = M.C_Timer.NewTimer(delay, fn)
    t.iterations = iterations
    return t
  end

  return M
end
