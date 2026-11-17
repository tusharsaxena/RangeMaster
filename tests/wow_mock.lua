-- tests/wow_mock.lua — Ka0s Range Master's WoW-API mock: the shared base (tests/_kit/mock_base.lua)
-- plus the few APIs this addon reads that the base does not answer the way a suite needs.
--
-- Returns a builder, so each environment gets a fresh, isolated mock. Everything universal — frames,
-- timers, the Settings canvas API, LibStub, the Ace fakes, the capture-context lookups — lives in the
-- kit and is documented there. Only what is genuinely this addon's belongs here: a base that stubbed
-- every addon's APIs would hide a missing stub behind a neighbor's. What LibRangeCheck-3.0 reads at
-- LOAD is answered here, so tests/run.lua loads the vendored library as the TOC does. The range
-- engine's client reads (core/Compat.lua: the spell, item and interact checks, the player's race,
-- whether a unit is attackable) answer "nothing known" by default; a suite swaps the one it drives.

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
    -- core/Compat.lua's IsSpellKnown: a fresh character knows nothing.
    IsSpellKnown              = function() return false end,
  }
  M.C_PaperDollInfo = M.C_PaperDollInfo or { GetInventorySlotInfo = function() return 10 end }
  M.CheckInteractDistance = M.CheckInteractDistance or function() return false end
  -- The range engine's client reads (core/Compat.lua), each answering "no answer" until a suite
  -- swaps it: a spell or item range check answers nil (not applicable), an interact check false.
  M.C_Spell = M.C_Spell or {}
  M.C_Spell.IsSpellInRange = M.C_Spell.IsSpellInRange or function() return nil end
  M.C_Spell.GetSpellInfo = M.C_Spell.GetSpellInfo or function() return nil end
  -- No usability answer either, so an unswapped spell is never trusted (research lesson 9).
  M.C_Spell.IsSpellUsable = M.C_Spell.IsSpellUsable or function() return nil end
  M.C_Item = M.C_Item or {}
  M.C_Item.IsItemInRange = M.C_Item.IsItemInRange or function() return nil end
  M.UnitRace = M.UnitRace or function() return "Human", "Human", 1 end
  M.UnitCanAttack = M.UnitCanAttack or function() return false end

  -- C_Timer.NewTicker, which the kit's C_Timer does not carry (LibRangeCheck arms a 5 s cache
  -- ticker at load; modules/Ticker.lua is one). Built on the kit's NewTimer, so it queues, cancels
  -- and reports in M.__timers() exactly as that handle does, and it RE-ARMS as the client's does:
  -- after each fire the same handle goes back on the queue until it is canceled or its
  -- `iterations` run out. The callback receives the handle, as the client's does.
  M.C_Timer.NewTicker = M.C_Timer.NewTicker or function(delay, fn, iterations)
    local t, stopped
    local remaining = iterations
    t = M.C_Timer.NewTimer(delay, function()
      fn(t)
      if remaining then remaining = remaining - 1 end
      if not stopped and (remaining == nil or remaining > 0) then
        M.__timers[#M.__timers + 1] = t
      end
    end)
    local cancel = t.Cancel
    t.Cancel = function(...)
      stopped = true
      return cancel(...)
    end
    t.iterations = iterations
    return t
  end

  return M
end
