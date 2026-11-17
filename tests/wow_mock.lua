-- tests/wow_mock.lua — Ka0s Range Master's WoW-API mock: the shared base (tests/_kit/mock_base.lua)
-- plus the few APIs this addon reads that the base does not answer the way a suite needs.
--
-- Returns a builder, so each environment gets a fresh, isolated mock. Everything universal — frames,
-- timers, the Settings canvas API, LibStub, the Ace fakes, the capture-context lookups — lives in the
-- kit and is documented there. Only what is genuinely this addon's belongs here: a base that stubbed
-- every addon's APIs would hide a missing stub behind a neighbor's. The range APIs (LibRangeCheck's
-- answers, unit existence per token) join with the range engine (the v0.1.0 plan, Task 2).

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

  return M
end
