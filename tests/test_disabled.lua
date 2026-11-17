-- tests/test_disabled.lua — the conformance suite for the disabled state (slash-commands-§7).
--
-- `Disabled` means the addon is NOT RUNNING: every event and bus registration actually unregistered
-- (an early-returning handler does not satisfy this), every timer canceled, both preview modes ended,
-- nothing written from a game event, and all of it through the same latch the perf harness suspends
-- on. The dispatcher, the settings category and AceDB's profile callbacks are setup and stay up, and
-- every reserved verb keeps answering. Each case below is one of the section's ten steps, numbered as
-- the standard numbers them, and each is falsifiable: drop the stand-down's unregister and steps 3, 6
-- and 9 go red.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function regKey(r)
  return ("%s|%s|%s|%s"):format(r.kind, tostring(r.event), tostring(r.unit), tostring(r.target))
end

--- The live registration set (events, unit events, bus messages), as sorted keys.
local function regSet()
  local out = {}
  for i, r in ipairs(M.__registrations()) do out[i] = regKey(r) end
  table.sort(out)
  return out
end

local function joined(list) return table.concat(list, "\n  ") end

--- An enabled, stood-up addon with no timer armed: the baseline every case measures from.
local function bringUp()
  -- The Skin library's one-shot EllesmereUI retry frame waits for PLAYER_LOGIN, which the harness
  -- never fires; released here so it is not counted as this addon's registration.
  local skinLib = M.LibStub("LibKa0s-Skin-1.0", true)
  local retry = skinLib and skinLib.__euiEventFrame
  if retry then retry:__fire("OnEvent", "PLAYER_LOGIN") end
  NS.SetByPath("enabled", true)
  NS.SyncEnabledHold()
  NS.addon:OnEnable()
  NS.EndModes("test baseline")
  return regSet()
end

local function disable() NS.SetByPath("enabled", false) end
local function enable()  NS.SetByPath("enabled", true)  end

test("disabled 1: the enabled addon registers something to stand down from", function()
  local R_on = bringUp()
  local events = {}
  for _, r in ipairs(M.__registrations()) do
    if r.kind == "event" then events[r.event] = true end
  end
  for _, pair in ipairs(NS.__lifecycleEvents) do
    assertTrue(events[pair[1]], "the lifecycle event " .. pair[1] .. " is registered: " .. joined(R_on))
  end
end)

test("disabled 2: the hold follows the STORED path, read when the addon comes up", function()
  bringUp()
  NS.db.profile.enabled = false        -- a profile saved disabled, read as the load reads it
  NS.addon:OnEnable()
  assertTrue(NS.lifecycle:IsHeld(NS.HOLD_DISABLED), "the load took the disabled hold off the store")
  assertEqual(#regSet(), 0, "and registered nothing:\n  " .. joined(regSet()))
  enable()
  assertFalse(NS.IsStoodDown(), "the enable write released it")
end)

test("disabled 3: writing the enable path leaves NOTHING registered", function()
  bringUp()
  disable()
  local after = regSet()
  assertEqual(#after, 0, "survivors of the stand-down:\n  " .. joined(after))
  enable()
end)

test("disabled 4: no timer, ticker or OnUpdate is left armed, and both preview modes end", function()
  bringUp()
  NS.SetTestMode(true, "test")
  NS.SetSimMode(true, "test")
  disable()
  assertEqual(#M.__timers(), 0, "timers left armed on a stood-down addon: " .. #M.__timers())
  assertFalse(NS.IsTestMode(), "Test mode ended with the stand-down")
  assertFalse(NS.IsSimMode(), "Sim mode ended with the stand-down")
  enable()
end)

test("disabled 5: a preview mode cannot be started while disabled, so nothing can be shown", function()
  bringUp()
  disable()
  M.__resetPrinted()
  assertFalse(NS.SetTestMode(true, "test"), "the Test mode start was refused")
  assertFalse(NS.SetSimMode(true, "test"), "the Sim mode start was refused")
  assertFalse(NS.IsTestMode() or NS.IsSimMode(), "and neither mode is on")
  enable()
end)

test("disabled 6: firing every baseline event writes nothing, says nothing, runs nothing", function()
  local R_on = bringUp()
  local events = {}
  for _, r in ipairs(M.__registrations()) do
    if r.kind == "event" then events[r.event] = true end
  end
  assertTrue(events.PLAYER_REGEN_DISABLED, "the combat-entry event is in the baseline set by name")

  disable()
  M.__resetSvWrites()
  M.__resetPrinted()
  local ran = 0
  for event in pairs(events) do ran = ran + M.__fire(event) end
  assertEqual(ran, 0, "a handler ran off a game event while the addon was disabled")
  assertEqual(#M.__svWrites(), 0, "SavedVariables writes from a game event")
  assertEqual(#M.__printed(), 0, "lines printed: " .. table.concat(M.__printed(), " / "))

  -- The silence above must be the addon's, not the harness's: a frame the client still dispatches
  -- to reaches its handler.
  local probe = M.CreateFrame("Frame")
  local heard = 0
  probe:SetScript("OnEvent", function() heard = heard + 1 end)
  assertTrue(M.__fireUnconditional(probe, "PLAYER_REGEN_DISABLED") >= 1,
    "the harness could not dispatch to an unregistered frame at all")
  assertEqual(heard, 1, "and the probe's handler ran")

  enable()
  assertEqual(table.concat(regSet(), "\n"), table.concat(R_on, "\n"), "and the set comes back")
end)

test("disabled 7: every reserved verb answers, and only a feature verb refuses", function()
  local LIVE = {
    help = true, config = true, version = true, enable = true, disable = true,
    debug = true, perf = true, get = true, set = true, list = true, reset = true, resetall = true,
    diagnostics = true, profile = true,
  }
  local refusal = NS.Slash:DisabledLine()
  local realOpen, opened = NS.OpenOptionsPanel, 0
  NS.OpenOptionsPanel = function() opened = opened + 1 end
  local realDiag = NS.DebugLog.RunDiagnostics
  NS.DebugLog.RunDiagnostics = function() return 0 end

  bringUp()
  for _, entry in ipairs(NS.COMMANDS) do
    local verb = entry[1]
    disable()
    M.__resetPrinted()
    NS.Slash:OnSlash(verb)
    local out = M.__printed()
    if verb == "help" then
      assertTrue(#out > 2, "`/rm help` prints the whole index while disabled: " .. joined(out))
    elseif LIVE[verb] then
      for _, line in ipairs(out) do
        assertFalse(line:find(refusal, 1, true) ~= nil,
          "`/rm " .. verb .. "` must answer normally while disabled: " .. line)
      end
    else
      assertEqual(#out, 1, "`/rm " .. verb .. "` refuses on ONE line: " .. joined(out))
      assertTrue(out[1]:find(refusal, 1, true) ~= nil, "`/rm " .. verb .. "`: " .. out[1])
    end
  end

  disable()
  opened = 0
  NS.Slash:OnSlash("")
  assertEqual(opened, 1, "a bare `/rm` must open the settings panel while disabled")

  NS.OpenOptionsPanel = realOpen
  NS.DebugLog.RunDiagnostics = realDiag
  enable()
end)

test("disabled 7: a refused feature verb reaches no write seam", function()
  bringUp()
  NS.SetByPath("locked", true)
  disable()
  local real, seen = NS.SetByPath, 0
  NS.SetByPath = function(path, value)
    if path == "locked" then seen = seen + 1 end
    return real(path, value)
  end
  NS.Slash:OnSlash("unlock")
  NS.Slash:OnSlash("test")
  NS.SetByPath = real
  assertEqual(seen, 0, "a refused verb reached the write seam")
  assertTrue(NS.GetSetting("locked"), "and the displays are still locked")
  assertFalse(NS.IsTestMode(), "and Test mode did not start")
  enable()
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

test("disabled 8: the left click opens the panel; the menu grays the rest and still re-enables", function()
  local object = launcherObject()
  assertTrue(object ~= nil, "precondition: the launcher object is registered")
  bringUp()
  NS.SetByPath("locked", true)
  disable()
  M.__resetSvWrites()
  M.__resetPrinted()

  local realOpen, opened = NS.OpenOptionsPanel, 0
  NS.OpenOptionsPanel = function() opened = opened + 1 end
  object.OnClick(object, "LeftButton")
  NS.OpenOptionsPanel = realOpen
  assertEqual(opened, 1, "left-click must open the settings panel while disabled")
  assertEqual(#M.__svWrites(), 0, "a disabled addon's left click wrote SavedVariables")

  local Menu = dofile("tests/mock_menu.lua")(M)
  Menu.install()
  local ok, err = pcall(function()
    object.OnClick(object, "RightButton")
    local menu = assert(Menu.last, "the right click opened no menu")
    for _, entry in ipairs({ "Locked", "Test mode", "Sim mode" }) do
      assertFalse(menu:Find(entry).enabled, entry .. " is grayed while disabled")
    end
    menu:Click("Test mode")
    assertFalse(NS.IsTestMode(), "a grayed Test mode started nothing")
    assertEqual(#M.__svWrites(), 0, "a grayed entry wrote SavedVariables")

    object.OnClick(object, "RightButton")
    Menu.last:Click("Enabled")
    assertTrue(NS.GetSetting("enabled") ~= false, "the menu's Enabled re-enabled the addon")
  end)
  Menu.remove()
  enable()
  assertTrue(ok, tostring(err))
end)

test("disabled 9: re-enabling restores the registration set, from the settings as they are NOW", function()
  local R_on = bringUp()
  disable()
  NS.SetByPath("locked", false)       -- a change made while down is what comes back up
  enable()
  assertEqual(table.concat(regSet(), "\n"), table.concat(R_on, "\n"),
    "the set did not come back as it went down")
  assertFalse(NS.GetSetting("locked"), "the setting changed while down is the one in force")
  NS.SetByPath("locked", true)
end)

test("disabled 9: a bus subscription comes back once, and reaches its receiver once", function()
  bringUp()
  local heard = 0
  local probe = NS.NewBusTarget()
  probe:RegisterMessage(NS.MSG.MODE_CHANGED, function() heard = heard + 1 end)
  disable()
  NS.bus:SendMessage(NS.MSG.MODE_CHANGED, "test", false)
  assertEqual(heard, 0, "a stood-down addon's receiver heard a message")
  enable()
  NS.bus:SendMessage(NS.MSG.MODE_CHANGED, "test", false)
  assertEqual(heard, 1, "the stand-up replayed the subscription once")
  probe:UnregisterAllMessages()
end)

test("disabled 10: releasing one hold does not stand up an addon the other still holds down", function()
  local R_on = bringUp()
  local lc = NS.lifecycle
  NS.Perf.Suspend()
  assertTrue(lc:IsHeld("perf"), "the perf hold is taken")
  disable()
  assertEqual(#regSet(), 0, "down under both holds")
  NS.Perf.Resume()
  assertTrue(lc:IsDown(), "and the addon is STILL down: the player disabled it")
  assertEqual(#regSet(), 0, "a released perf hold resurrected a disabled addon")
  enable()
  assertEqual(#regSet(), #R_on, "and the last hold released stands it up")

  disable()
  NS.Perf.Suspend()
  enable()
  assertTrue(lc:IsDown(), "still down: the perf arm is still running")
  assertEqual(#regSet(), 0, "re-enabling mid-capture stood the addon up")
  NS.Perf.Resume()
  assertFalse(lc:IsDown(), "and releasing the last hold brings it back")
  assertEqual(#regSet(), #R_on, "with the set it went down with")
end)

test("disabled 10: the perf hold is session-only and the disabled hold is the stored path", function()
  bringUp()
  M.__resetSvWrites()
  NS.Perf.Suspend()
  assertEqual(#M.__svWrites(), 0, "the perf hold was persisted")
  NS.Perf.Resume()
  disable()
  assertFalse(NS.GetSetting("enabled"), "the disabled hold is read back out of the store")
  assertTrue(NS.lifecycle:IsHeld("disabled"), "and the hold follows it")
  enable()
  assertFalse(NS.lifecycle:IsDown(), "with no hold left, the addon is up")
end)
