-- tests/test_sim_start_panel.lua — every start of a sweep shows the step panel, pinned (FB2-RM-01 of
-- Ka0sAddonsCommonTasks docs/2026-11-24-FEEDBACK_BATCH, decision D2; LibKa0s-Sim-1.0 minor 5).
--
-- The owner's words, 2026-11-24: "sim mode whether started from a command like /xx sim start
-- <scenario> or from just plain /xx sim should always show the sim stepper window". The library
-- shows the panel at its one choke point, the session's own Start, and Range Master's prepare shows
-- and pins it there too (modules/Sim.lua). This file holds every start path the addon has to that
-- rule, each from a closed panel: `/rm sim`, `/rm sim on`, `/rm sim start sweep`, the Master controls
-- Sim mode box, the launcher's Sim mode entry, the panel's own Start row, and a Restart after the
-- player hid the panel mid-run. "Pinned" is the addon's half: no close mark while the session runs.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertTrue, assertFalse = T.test, T.assertTrue, T.assertFalse

local H = dofile("tests/anchors_env.lua")
local installPaint = dofile("tests/_kit/mock_paint.lua")

local function off()
  NS.EndModes("test reset")
  M.InCombatLockdown = function() return false end
end

local function withEnv(body)
  local restore = installPaint(M)
  local ok, err = pcall(H.with, body)
  restore()
  off()
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  if not ok then error(err, 0) end
end

local PANEL = "RangeMasterSimPanel"

--- The session is idle and its panel closed, as a player finds it before a start.
local function closed()
  off()
  local session = NS.Sim.Session()
  session:HidePanel()
  assertFalse(session:IsActive(), "idle before the start")
  assertFalse(session:IsPanelShown(), "and the panel closed")
  return session
end

--- The sweep runs, its panel is shown, and it carries no close mark.
local function shownAndPinned(session, how)
  assertTrue(session:IsActive(), how .. " started the sweep")
  assertTrue(NS.IsSimMode(), how .. " turned Sim mode on")
  assertTrue(session:IsPanelShown(), how .. " showed the step panel")
  local frame = _G[PANEL]
  assertTrue(type(frame) == "table" and frame:IsShown(), how .. ": the panel frame is up")
  assertFalse(frame.closeButton:IsShown(), how .. ": the panel is pinned, no close mark")
end

--- Each start path from a closed panel.
local function eachPath(name, start)
  test("sim start panel: " .. name .. " shows the step panel, pinned", function()
    withEnv(function()
      H.container("target")
      local session = closed()
      start(session)
      shownAndPinned(session, name)
    end)
  end)
end

eachPath("a bare /rm sim", function() NS.Slash:OnSlash("sim") end)
eachPath("/rm sim on", function() NS.Slash:OnSlash("sim on") end)
eachPath("a typed /rm sim start sweep", function() NS.Slash:OnSlash("sim start sweep") end)
eachPath("the Master controls Sim mode box", function() NS.SetByPath("state.sim", true) end)

eachPath("the launcher's Sim mode entry", function()
  local ldb = M.LibStub("LibDataBroker-1.1", true)
  if not ldb then
    ldb = M.LibStub:NewLibrary("LibDataBroker-1.1", 4)
    ldb.objects = {}
    function ldb:NewDataObject(n, tbl)
      if self.objects[n] then return nil end
      self.objects[n] = tbl
      return tbl
    end
    function ldb:GetDataObjectByName(n) return self.objects[n] end
    local icons = M.LibStub:NewLibrary("LibDBIcon-1.0", 45)
    icons.Register, icons.Show, icons.Hide = function() end, function() end, function() end
  end
  NS.Launcher:Register()
  local object = NS.Launcher:Object()
  local Menu = dofile("tests/mock_menu.lua")(M)
  Menu.install()
  local ok, err = pcall(function()
    object.OnClick(object, "RightButton")
    Menu.last:Click("Sim mode")
  end)
  Menu.remove()
  assertTrue(ok, tostring(err))
end)

eachPath("the panel's own Start row", function(session)
  NS.Slash:OnSlash("sim panel")
  assertTrue(session:IsPanelShown(), "`/rm sim panel` opens the idle panel")
  local frame = _G[PANEL]
  local start = frame.__rowButtons and frame.__rowButtons[1]
  assertTrue(start ~= nil, "the idle panel's first row is Start")
  start:__fire("OnClick")
end)

eachPath("a Restart after the player hid the panel", function(session)
  NS.Slash:OnSlash("sim on")
  session:HidePanel()
  assertFalse(session:IsPanelShown(), "hidden mid-run")
  NS.Slash:OnSlash("sim restart")
end)
