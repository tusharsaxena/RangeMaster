-- tests/test_modes.lua — Test mode and Sim mode (preview-mode, options-ui-§15): session state with one
-- writer each (core/RangeMaster.lua), reached by the Master controls checkboxes, the launcher menu,
-- `/rm test` and `/rm sim`, refused in combat and ended by it, announced on MODE_CHANGED, and never
-- persisted; and what each mode draws (modules/Preview.lua, modules/Sim.lua; the v0.1.0 plan, Task 7).

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

test("modes: test_refuse_in_combat — a start is refused in combat with one gray line, and nothing changes", function()
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

test("modes: test_combat_ends_modes — entering combat ends both modes", function()
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

test("modes: test_launcher_and_slash_same_handler — the launcher menu is Enabled, Locked, Test mode, Sim mode, each the verb's handler", function()
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

-- ---------------------------------------------------------------------------
-- What the modes draw (modules/Preview.lua, modules/Sim.lua)
-- ---------------------------------------------------------------------------

local H = dofile("tests/anchors_env.lua")
local installPaint = dofile("tests/_kit/mock_paint.lua")

--- H.with under the kit's paint recorder (font strings that keep their text, frames their opacity and
--- scale), with the combat edge put back however the case ends.
local function withEnv(body)
  local restore = installPaint(M)
  local ok, err = pcall(H.with, body)
  restore()
  M.InCombatLockdown = function() return false end
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  if not ok then error(err, 0) end
end
local EN = "\226\128\147"

--- The instance drawing container `id`: its own, or (for a `nameplates` container) its stand-in.
local function drawn(id) return NS.Container.Get(id) end

test("modes: test_test_mode_placeholders_all_containers — every enabled container shows a placeholder", function()
  off()
  withEnv(function()
    M.__unitExists.target = false
    local ids = {
      screen   = NS.CM.Create("target"),
      combat   = NS.CM.Create("focus", { visibility = { combat = "in" } }),
      frame    = NS.CM.Create("pet", { anchor = { mode = "frame", frame = { provider = "custom", name = "NoSuchFrame" } } }),
      ownPlate = NS.CM.Create("target", { anchor = { mode = "nameplate" } }),
      plates   = NS.CM.Create("nameplates", { anchor = { mode = "nameplate" } }),
      cursor   = NS.CM.Create("mouseover", { anchor = { mode = "cursor" } }),
    }
    local disabled = NS.CM.Create("target", { enabled = false })
    NS.CM.FlushPending()
    for name, id in pairs(ids) do
      local inst = drawn(id)
      assertFalse(inst ~= nil and inst.frame:IsShown(), name .. " is hidden before Test mode")
    end
    assertTrue(NS.SetTestMode(true, "test"))
    for name, id in pairs(ids) do
      local inst = drawn(id)
      assertTrue(inst ~= nil, name .. " has an instance in Test mode")
      assertTrue(inst.frame:IsShown(), name .. " shows its placeholder")
      assertEqual(inst.elements.number.fs:GetText(), "20" .. EN .. "25", name .. " reads the placeholder range")
      assertEqual(inst.state, "known", name .. " drew it through the real render path")
      if inst.strips then
        assertTrue(inst.strips.test and inst.strips.test:IsShown(), name .. " carries the test strip")
      end
    end
    assertEqual(drawn(disabled), nil, "a disabled container shows nothing")
    assertEqual(NS.Preview.Kind(), "test")
    NS.SetTestMode(false, "test")
    assertEqual(NS.Preview.Kind(), nil)
    assertEqual(drawn(ids.plates), nil, "the nameplates stand-in goes with the mode")
    for name, id in pairs(ids) do
      local inst = drawn(id)
      assertFalse(inst ~= nil and inst.frame:IsShown(), name .. " is hidden again")
      if inst and inst.strips and inst.strips.test then
        assertFalse(inst.strips.test:IsShown(), name .. "'s strip is hidden")
      end
    end
    assertFalse(NS.Range.HasSource(), "the live range is back")
  end)
  off()
end)

test("modes: Test mode keeps the ticker reading the placeholder while it is on", function()
  off()
  withEnv(function()
    M.__unitExists.target = false
    local id = NS.CM.Create("target")
    NS.CM.FlushPending()
    assertFalse(NS.Ticker.IsRunning(), "no live unit: no ticker")
    NS.SetTestMode(true, "test")
    assertTrue(NS.Ticker.IsRunning(), "the placeholder is live")
    assertEqual(NS.Range.InSpellRange(1, "target"), true, "a chip reads in range")
    NS.SetTestMode(false, "test")
    assertFalse(NS.Ticker.IsRunning(), "and stops with it")
    assertFalse(drawn(id).frame:IsShown())
  end)
  off()
end)

--- Play the running sweep one step at a time, a steady read between steps, half a second apart;
--- answers the target container's band after each step, until the session ends (bounded).
local function sweep(inst)
  local session = NS.Sim.Session()
  local bands = { inst.bandIndex }
  for _ = 1, 60 do
    if not session:IsActive() then break end
    M.__now = M.__now + 0.5
    session:Step()
    M.__now = M.__now + 0.5
    NS.Ticker.Refresh()
    if bands[#bands] ~= inst.bandIndex and session:IsActive() then bands[#bands + 1] = inst.bandIndex end
  end
  return bands
end

test("modes: test_sim_sweeps_bands — Sim mode walks 0 to 50 to 0 yd through every band, with sounds", function()
  off()
  withEnv(function()
    local played, savedPlay, savedNow = 0, M.PlaySoundFile, M.__now
    M.PlaySoundFile = function() played = played + 1 return true end
    local ok, err = pcall(function()
      local setId = NS.BandSets.Create("Sweep", "melee_ranged")
      for i = 1, 5 do NS.BandSets.SetBandSound(setId, i, NS.Presets.OOR_SOUND) end
      local _, inst = H.container("target", { bandSet = setId, sounds = { enabled = true } })
      M.__now = 50
      assertTrue(NS.SetSimMode(true, "test"))
      assertTrue(NS.Sim.IsRunning(), "a LibKa0s-Sim session runs")
      assertEqual(NS.Preview.Kind(), "sim")
      local steps = NS.Sim.Session():Steps()
      assertEqual(steps[1].yd, 0)
      assertEqual(steps[11].yd, 50, "out to 50 yd")
      assertEqual(steps[21].yd, 0, "and back to 0")
      assertEqual(#steps, 22, "21 distances and the end")
      assertEqual(inst.bandIndex, 1, "the first step is in melee")
      M.__now = M.__now + 0.5
      NS.Ticker.Refresh()                -- the ticker's steady read settles melee, silently
      assertEqual(played, 0, "the first band is silent")
      local bands = sweep(inst)
      assertEqual(table.concat(bands, ","), "1,2,3,4,5,4,3,2,1", "every band, out and back")
      assertEqual(played, 8, "a sound on each band entered after the first")
      assertFalse(NS.IsSimMode(), "the sweep ends the mode")
      assertFalse(NS.Range.HasSource())
      assertEqual(inst.elements.number.fs:GetText(), "20" .. EN .. "25", "the live range is drawn again")
    end)
    M.PlaySoundFile, M.__now = savedPlay, savedNow
    if not ok then error(err, 0) end
  end)
  off()
end)

test("modes: the sweep's run plays on its own timers, and Sim mode off stops it", function()
  off()
  withEnv(function()
    local _, inst = H.container("target")
    NS.SetSimMode(true, "test")
    assertEqual(inst.elements.number.fs:GetText(), "0" .. EN .. "1", "the first step drew at once")
    M.__fireTimers()
    assertEqual(NS.Sim.Session():Status().pos, 2, "the next step came on a timer")
    NS.SetSimMode(false, "test")
    assertFalse(NS.Sim.IsRunning(), "the session stopped with the mode")
    assertFalse(NS.Range.HasSource())
  end)
  off()
end)

test("modes: Sim mode wins over Test mode, and Test mode is refused while a sim runs", function()
  off()
  withEnv(function()
    local _, inst = H.container("target")
    NS.SetTestMode(true, "test")
    NS.SetSimMode(true, "test")
    assertEqual(NS.Preview.Kind(), "sim")
    assertEqual(inst.elements.number.fs:GetText(), "0" .. EN .. "1", "the sweep, not the placeholder")
    NS.SetTestMode(false, "test")
    M.__resetPrinted()
    assertFalse(NS.SetTestMode(true, "test"), "Test mode refused while the sim runs")
    assertEqual(#M.__printed(), 1, "with one line")
    NS.SetSimMode(false, "test")
    assertTrue(NS.SetTestMode(true, "test"), "accepted once it ends")
  end)
  off()
end)

test("modes: entering combat stops the sim session and puts the live range back", function()
  off()
  withEnv(function()
    local _, inst = H.container("target")
    NS.SetSimMode(true, "test")
    NS.SetTestMode(false, "test")
    M.InCombatLockdown = function() return true end
    NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
    assertFalse(NS.Sim.IsRunning(), "combat stopped the session")
    assertFalse(NS.IsSimMode())
    assertFalse(NS.Range.HasSource())
    assertEqual(inst.elements.number.fs:GetText(), "20" .. EN .. "25")
    M.InCombatLockdown = function() return false end
    NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  end)
  off()
end)

test("modes: /rm sim passes any other word to the simulator's own verbs", function()
  off()
  withEnv(function()
    H.container("target")
    M.__resetPrinted()
    NS.Slash:OnSlash("sim status")
    assertTrue(#M.__printed() >= 1, "the status line printed in chat")
    NS.Slash:OnSlash("sim start sweep")
    assertTrue(NS.IsSimMode(), "a typed start turns Sim mode on")
    NS.Slash:OnSlash("sim stop")
    assertFalse(NS.IsSimMode(), "a typed stop turns it off")
  end)
  off()
end)

test("modes: the simulator's seam leaves no Compat member unwrapped", function()
  local seam = NS.Sim.Seam()
  assertTrue(seam ~= nil, "the seam exists")
  assertEqual(#seam:Unwrapped(), 0)
end)
