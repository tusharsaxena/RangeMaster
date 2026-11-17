-- tests/test_modes.lua — Test mode and Sim mode (preview-mode, options-ui-§15): session state with one
-- writer each (core/RangeMaster.lua), reached by the Master controls checkboxes, the launcher menu,
-- `/rm test` and `/rm sim`, refused in combat and ended by it, announced on MODE_CHANGED, and never
-- persisted. What each mode draws arrives with the renderer (the v0.1.0 plan, Task 7).

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function off()
  NS.EndModes("test reset")
  M.InCombatLockdown = function() return false end
end

--- Run `fn` with InCombatLockdown answering true.
local function inCombat(fn)
  M.InCombatLockdown = function() return true end
  local ok, err = pcall(fn)
  M.InCombatLockdown = function() return false end
  if not ok then error(err, 0) end
end

--- Count MODE_CHANGED messages and their payloads while `fn` runs.
local function heard(fn)
  local got = {}
  local probe = NS.NewBusTarget()
  probe:RegisterMessage(NS.MSG.MODE_CHANGED, function(_, mode, on)
    got[#got + 1] = mode .. "=" .. tostring(on)
  end)
  fn()
  probe:UnregisterAllMessages()
  return got
end

test("modes: each writer sets its mode, announces once on a change, and a repeat is silent", function()
  off()
  local got = heard(function()
    assertTrue(NS.SetTestMode(true, "test"), "the start was accepted")
    assertTrue(NS.SetTestMode(true, "test"), "a repeat answers true")
    assertTrue(NS.SetSimMode(true, "test"), "Sim mode too")
    NS.SetTestMode(false, "test")
  end)
  assertEqual(table.concat(got, ","), "test=true,sim=true,test=false", "one message per change")
  assertTrue(NS.IsSimMode(), "Sim mode is still on")
  off()
end)

test("modes: a start is refused in combat with one gray line, and nothing changes", function()
  -- red under: a setMode with no combat gate.
  off()
  M.__resetPrinted()
  inCombat(function()
    assertFalse(NS.SetTestMode(true, "test"), "Test mode refused")
    assertFalse(NS.SetSimMode(true, "test"), "Sim mode refused")
  end)
  assertFalse(NS.IsTestMode() or NS.IsSimMode(), "neither mode started")
  local printed = M.__printed()
  assertEqual(#printed, 2, "one line per refusal: " .. table.concat(printed, " / "))
  assertTrue(printed[1]:find("|cff808080", 1, true) ~= nil, "the refusal is gray: " .. printed[1])
end)

test("modes: entering combat ends both modes", function()
  off()
  NS.SetTestMode(true, "test")
  NS.SetSimMode(true, "test")
  NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
  assertFalse(NS.IsTestMode(), "combat ended Test mode")
  assertFalse(NS.IsSimMode(), "combat ended Sim mode")
  NS.SetTestMode(true, "test")
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  assertTrue(NS.IsTestMode(), "leaving combat ends nothing")
  off()
end)

test("modes: neither mode is ever written to SavedVariables", function()
  off()
  M.__resetSvWrites()
  NS.SetTestMode(true, "test")
  NS.SetSimMode(true, "test")
  off()
  assertEqual(#M.__svWrites(), 0, "a preview mode wrote SavedVariables")
end)

test("modes: /rm test and /rm sim toggle, take on and off, and refuse another word", function()
  off()
  NS.Slash:OnSlash("test")
  assertTrue(NS.IsTestMode(), "a bare /rm test turns it on")
  NS.Slash:OnSlash("test")
  assertFalse(NS.IsTestMode(), "and off again")
  NS.Slash:OnSlash("sim on")
  assertTrue(NS.IsSimMode(), "/rm sim on")
  NS.Slash:OnSlash("sim on")
  assertTrue(NS.IsSimMode(), "on is a set, not a toggle")
  NS.Slash:OnSlash("sim off")
  assertFalse(NS.IsSimMode(), "/rm sim off")
  M.__resetPrinted()
  NS.Slash:OnSlash("test maybe")
  assertFalse(NS.IsTestMode(), "an unknown word changes nothing")
  assertTrue((M.__printed()[1] or ""):find("Usage: /rm test", 1, true) ~= nil, "and prints the usage")
  off()
end)

test("modes: the Master controls carry Test mode, then Sim mode, as session rows on the one writer", function()
  off()
  local testAt, simAt
  for i, row in ipairs(NS.Schema) do
    if row.path == "state.testMode" then testAt = i end
    if row.path == "state.sim" then simAt = i end
  end
  assertTrue(testAt ~= nil and simAt ~= nil, "both rows are composed")
  assertEqual(simAt, testAt + 1, "Sim mode sits straight after Test mode (options-ui-§15)")
  assertTrue(NS.Schema[testAt].sessionOnly, "Test mode is session-only")
  NS.SetByPath("state.testMode", true)
  assertTrue(NS.IsTestMode(), "the checkbox reaches NS.SetTestMode")
  assertTrue(NS.GetSetting("state.testMode"), "and reads the mode back")
  NS.SetByPath("state.sim", true)
  assertTrue(NS.IsSimMode(), "the Sim mode box reaches the sim toggle")
  off()
end)

local function launcherObject()
  if not M.LibStub("LibDataBroker-1.1", true) then
    local ldb = M.LibStub:NewLibrary("LibDataBroker-1.1", 4)
    ldb.objects = {}
    function ldb:NewDataObject(name, tbl)
      if self.objects[name] then return nil end
      self.objects[name] = tbl
      return tbl
    end
    function ldb:GetDataObjectByName(name) return self.objects[name] end
    local icons = M.LibStub:NewLibrary("LibDBIcon-1.0", 45)
    icons.Register = function() end
    icons.Show     = function() end
    icons.Hide     = function() end
  end
  NS.Launcher:Register()
  return NS.Launcher:Object()
end

test("modes: the launcher menu is Enabled, Locked, Test mode, Sim mode, each the verb's handler", function()
  -- launcher-§2: the entries the roster row records, and each toggle the slash verb's own handler.
  off()
  local object = launcherObject()
  local Menu = dofile("tests/mock_menu.lua")(M)
  Menu.install()
  local ok, err = pcall(function()
    object.OnClick(object, "RightButton")
    local menu = assert(Menu.last, "the right click opened no menu")
    assertEqual(table.concat(menu:Texts(), " / "), "Enabled / Locked / Test mode / Sim mode")
    local real, calls = NS.Slash.ToggleTestMode, 0
    NS.Slash.ToggleTestMode = function() calls = calls + 1; return real() end
    menu:Click("Test mode")
    NS.Slash.ToggleTestMode = real
    assertEqual(calls, 1, "the Test mode entry runs `/rm test`'s handler")
    assertTrue(NS.IsTestMode(), "and the mode is on")
    object.OnClick(object, "RightButton")
    assertTrue(Menu.last:Checked("Test mode"), "the entry reads the mode on the next open")
    Menu.last:Click("Sim mode")
    assertTrue(NS.IsSimMode(), "the Sim mode entry starts the sim")
  end)
  Menu.remove()
  off()
  assertTrue(ok, tostring(err))
end)
