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
      -- red under: a redraw that never shows the strip.
      local strip = inst.strips and inst.strips.test
      assertTrue(strip and strip:IsShown(), name .. " carries the test strip")
      assertEqual(strip.kind, "test", name .. "'s strip is the amber Test mode flavor")
    end
    -- red under: no screen-point fallback (present() placing nothing while the anchor is missing).
    for _, name in ipairs({ "frame", "ownPlate" }) do
      local a, inst = NS.CM.Get(ids[name]).anchor, drawn(ids[name])
      local calls = H.points(inst.frame, function() inst:Rerender() end)
      assertEqual(#calls, 1, name .. " is placed once a draw")
      local point, rel, relPoint, x, y = unpack(calls[1])
      assertEqual(point, NS.Anchors.Point(a.point), name .. " sits at its stored point")
      assertTrue(rel == M.UIParent, name .. " is placed on UIParent while its own anchor is missing")
      assertEqual(relPoint, NS.Anchors.Point(a.relPoint), name .. "'s relative point")
      assertEqual(x, NS.Anchors.Offset(a.x), name .. "'s x")
      assertEqual(y, NS.Anchors.Offset(a.y), name .. "'s y")
    end
    assertEqual(drawn(disabled), nil, "a disabled container shows nothing")
    assertEqual(NS.Preview.Kind(), "test")
    NS.SetTestMode(false, "test")
    assertEqual(NS.Preview.Kind(), nil)
    assertEqual(drawn(ids.plates), nil, "the nameplates stand-in goes with the mode")
    for name, id in pairs(ids) do
      local inst = drawn(id)
      assertFalse(inst ~= nil and inst.frame:IsShown(), name .. " is hidden again")
      if inst then
        assertTrue(inst.strips and inst.strips.test, name .. " kept its strip")
        assertFalse(inst.strips.test:IsShown(), name .. "'s strip is hidden")
      end
    end
    assertFalse(NS.Range.HasSource(), "the live range is back")
  end)
  off()
end)

test("modes: test_unlock_shows_all — unlocked shows every container out of combat, the absent ones on the placeholder", function()
  off()
  withEnv(function()
    M.__unitExists.target = true
    M.__unitExists.focus, M.__unitExists.mouseover, M.__unitExists.pet = false, false, false
    local ids = {
      target = NS.CM.Create("target"),
      focus  = NS.CM.Create("focus"),
      cursor = NS.CM.Create("mouseover", { anchor = { mode = "cursor" } }),
      frame  = NS.CM.Create("pet", { anchor = { mode = "frame", frame = { provider = "custom", name = "NoSuchFrame" } } }),
      plates = NS.CM.Create("nameplates", { anchor = { mode = "nameplate" } }),
    }
    NS.CM.FlushPending()
    for _, name in ipairs({ "focus", "cursor", "frame" }) do
      local inst = drawn(ids[name])
      assertFalse(inst ~= nil and inst.frame:IsShown(), name .. " is hidden while locked: no unit")
    end
    local function shownAll(why)
      for name, id in pairs(ids) do
        local inst = drawn(id)
        assertTrue(inst ~= nil and inst.frame:IsShown(), name .. " shows " .. why)
      end
    end
    NS.SetByPath("locked", false)
    -- red under: unlock moving only the drag strips (focus, mouseover and the plates stay hidden).
    shownAll("while unlocked")
    local focus = drawn(ids.focus)
    assertEqual(focus.state, "none", "an absent unit keeps its own state")
    assertEqual(focus.elements.number.fs:GetText(), "20" .. EN .. "25", "and draws the placeholder")
    assertFalse(focus.strips and focus.strips.test and focus.strips.test:IsShown(), "no preview strip")
    assertFalse(NS.IsTestMode(), "unlock is not Test mode")

    NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
    assertFalse(drawn(ids.focus).frame:IsShown(), "combat puts each container back on its own rules")
    assertTrue(drawn(ids.target).frame:IsShown(), "a unit that is there still shows")
    assertEqual(drawn(ids.plates), nil, "and parks the nameplates stand-in")
    NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
    shownAll("again once combat ends")

    NS.SetByPath("locked", true)
    for _, name in ipairs({ "focus", "cursor", "frame" }) do
      assertFalse(drawn(ids[name]).frame:IsShown(), name .. " hides again once locked")
    end
    assertEqual(drawn(ids.plates), nil, "the stand-in goes with the unlock")
  end)
  M.__unitExists.target = false
  NS.SetByPath("locked", true)
  off()
end)

test("modes: test_test_strip_on_late_instances — a container or plate that appears during Test mode wears the strip", function()
  -- red under: an Acquire or AcquirePlate that never shows the running preview's strip.
  off()
  withEnv(function()
    H.container("target")
    assertTrue(NS.SetTestMode(true, "test"))
    local id, inst = H.container("focus")
    assertTrue(inst ~= nil and inst.frame:IsShown(), "the new container shows its placeholder")
    local strip = inst.strips and inst.strips.test
    assertTrue(strip and strip:IsShown(), "and carries the test strip")
    -- A pooled frame coming back (park hid its strip) wears it again.
    NS.CM.Delete(id)
    NS.CM.FlushPending()
    local _, again = H.container("pet")
    assertTrue(again.frame == inst.frame, "the deleted container's frame came back from the pool")
    assertTrue(again.strips and again.strips.test and again.strips.test:IsShown(), "a reused frame wears it again")
    -- A plate added while the preview runs.
    local plates = NS.CM.Create("nameplates", { anchor = { mode = "nameplate" } })
    NS.CM.FlushPending()
    H.plate("nameplate1", true)
    H.added("nameplate1")
    local plate = NS.Container.GetPlate(plates, "nameplate1")
    assertTrue(plate ~= nil, "the plate has an instance")
    assertTrue(plate.strips and plate.strips.test and plate.strips.test:IsShown(), "and it wears the strip")
    NS.SetTestMode(false, "test")
    assertFalse(again.strips.test:IsShown() or plate.strips.test:IsShown(), "the strips go with the mode")
  end)
  off()
end)

test("modes: test_strip_clears_drag_handle — a strip built while locked docks beyond the handle an unlock builds", function()
  -- red under: a strip whose `clear` was captured (as nil) before the drag handle existed.
  off()
  withEnv(function()
    local _, inst = H.container("target")
    assertTrue(NS.SetTestMode(true, "test"))
    local strip = inst.strips.test
    assertTrue(inst.dragHandle == nil, "locked: no handle yet")
    NS.SetByPath("locked", false)
    local h = inst.dragHandle
    assertTrue(h and h:IsShown(), "the unlock built and showed the handle")
    -- Geometry: the display's top at 500 (the strip host lies over it), the handle 20 above it.
    for f, top in pairs({ [inst.stripHost] = 500, [h] = 520 }) do
      rawset(f, "GetTop", function() return top end)
      rawset(f, "GetBottom", function() return top - 18 end)
      rawset(f, "GetEffectiveScale", function() return 1 end)
    end
    rawset(strip, "GetEffectiveScale", function() return 1 end)
    local calls = H.points(strip, function() strip:Place() end)
    local point, rel, relPoint, _, y = unpack(calls[1])
    assertEqual(point, "BOTTOMLEFT")
    assertTrue(rel == inst.stripHost and relPoint == "TOPLEFT", "on the display's top edge (its host)")
    assertEqual(y, 20, "stacked beyond the handle, never over it")
    NS.SetByPath("locked", true)
  end)
  off()
end)

--- Run `fn` with every frame made in it recording what it is anchored on (`__anchoredOn`).
local function recordingAnchors(fn)
  local real = M.CreateFrame
  M.CreateFrame = function(...)
    local f = real(...)
    rawset(f, "__anchoredOn", {})
    rawset(f, "SetPoint", function(self, _, rel)
      if type(rel) == "table" then table.insert(rawget(self, "__anchoredOn"), rel) end
    end)
    rawset(f, "ClearAllPoints", function(self) rawset(self, "__anchoredOn", {}) end)
    rawset(f, "SetAllPoints", function(self, rel) rawset(self, "__anchoredOn", { rel or self:GetParent() }) end)
    return f
  end
  local ok, err = pcall(fn)
  M.CreateFrame = real
  if not ok then error(err, 0) end
end

--- Whether `f`'s anchors reach `target`, through every frame it is anchored on.
local function reaches(f, target, seen)
  if f == target then return true end
  seen = seen or {}
  if type(f) ~= "table" or seen[f] then return false end
  seen[f] = true
  for _, rel in ipairs(rawget(f, "__anchoredOn") or {}) do
    if reaches(rel, target, seen) then return true end
  end
  return false
end

test("modes: test_strip_on_a_plate — a display on a nameplate wears a strip nothing measures", function()
  -- red under: the HUD dock's target being the root, which the client cannot measure on a plate
  -- ("Can't measure restricted regions" from the dock's OnShow / OnSizeChanged hooks).
  off()
  withEnv(function() recordingAnchors(function()
    local plate = H.plate("nameplate1", true)
    M.__plates.target = plate
    M.__unitExists.target = true
    local _, inst = H.container("target", { anchor = { mode = "nameplate" } })
    assertTrue(NS.SetTestMode(true, "test"))
    assertTrue(inst.anchorPlate == plate, "the display sits on the target's plate")
    -- The client's rule: a region anchored on a plate cannot be measured.
    local function restrict(f)
      for _, m in ipairs({ "GetTop", "GetBottom", "GetLeft", "GetRight" }) do
        rawset(f, m, function(self)
          if reaches(self, plate) then error("Can't measure restricted regions") end
          return 100
        end)
      end
      rawset(f, "GetEffectiveScale", function() return 1 end)
    end
    restrict(inst.frame)
    restrict(inst.stripHost)
    local strip = inst.strips and inst.strips.test
    assertTrue(strip and strip:IsShown(), "it wears the test strip")
    assertTrue(strip.__dock == nil, "an undocked one")
    assertTrue(reaches(strip, inst.frame), "on the display's top edge")
    assertFalse(reaches(inst.stripHost, plate), "the dock's target is parked off the plate")
    for _, f in ipairs({ inst.frame, inst.stripHost, strip }) do
      for _, script in ipairs({ "OnShow", "OnSizeChanged" }) do
        local ok, err = pcall(f.__fire, f, script)
        assertTrue(ok, script .. " measured a region on the plate: " .. tostring(err))
      end
    end
    for _, s in pairs(inst.stripSets.docked) do
      if s then assertFalse(s:IsShown(), "the docked strip is down while on the plate") end
    end
    -- Off the plate (the target's plate gone, the preview places it on screen): the docked strip.
    M.__plates.target = nil
    H.removed("nameplate1")
    assertTrue(inst.anchorPlate == nil, "off the plate")
    assertTrue(reaches(inst.stripHost, inst.frame), "the host lies over the display again")
    local docked = inst.strips.test
    assertTrue(docked and docked ~= strip and docked.__dock ~= nil, "it wears the docked strip")
    assertTrue(docked:IsShown() and not strip:IsShown(), "and only that one")
    NS.SetTestMode(false, "test")
    assertFalse(docked:IsShown() or strip:IsShown(), "the strips go with the mode")
  end) end)
  M.__unitExists.target = false
  off()
end)

test("modes: test_sim_strip_and_pinned_panel — Sim mode wears the cyan strip, and its step panel cannot be closed", function()
  -- red under: a redraw with no strip, or a panel left with its default close mark.
  off()
  withEnv(function()
    local _, inst = H.container("target")
    assertTrue(NS.SetSimMode(true, "test"))
    local strip = inst.strips and inst.strips.sim
    assertTrue(strip and strip:IsShown(), "the container carries the sim strip")
    assertEqual(strip.kind, "sim", "the cyan Sim mode flavor")
    assertFalse(inst.strips.test and inst.strips.test:IsShown(), "and not the test strip")
    local name = "RangeMasterSimPanel"
    local frame = _G[name]
    assertTrue(type(frame) == "table" and frame:IsShown(), "the step panel shows")
    assertTrue(frame.closeButton ~= nil, "the panel has a close mark to hide")
    assertFalse(frame.closeButton:IsShown(), "with no close mark while the session runs")
    for _, n in ipairs(M.UISpecialFrames) do assertFalse(n == name, "and Escape does not close it") end
    NS.SetSimMode(false, "test")
    assertFalse(strip:IsShown(), "the strip goes with the mode")
    assertTrue(frame.closeButton:IsShown(), "the close mark is back once the session ends")
    local listed = false
    for _, n in ipairs(M.UISpecialFrames) do if n == name then listed = true end end
    assertTrue(listed, "and the panel is on UISpecialFrames again")
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
