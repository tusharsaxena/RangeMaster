-- tests/test_disabled.lua — the conformance suite for the disabled state (slash-commands-§7).
--
-- `Disabled` means the addon is NOT RUNNING: every event and bus registration actually unregistered
-- (an early-returning handler does not satisfy this), every timer canceled, both preview modes ended,
-- nothing written from a game event, and all of it through the same latch the perf harness suspends
-- on. The dispatcher, the settings category and AceDB's profile callbacks are setup and stay up, and
-- every reserved verb keeps answering. Each case below is one of the section's ten steps, numbered as
-- the standard numbers them, and each is falsifiable: each negative assertion (steps 3, 6 and 10)
-- names, on its own `-- red under:` line, the mutation that reddens it.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function regKey(r)
  return ("%s|%s|%s|%s"):format(r.kind, tostring(r.event), tostring(r.unit), tostring(r.target))
end

-- What the vendored LibRangeCheck-3.0 arms at its own load (libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua,
-- lib:activate()): its event frame, which also carries its OnUpdate, and its 5 s cache ticker. A
-- library's, not this addon's, and loaded before the addon exists, so the stand-down does not own them
-- and every count below leaves them out. Nothing else is exempt.
local LRC = M.LibStub("LibRangeCheck-3.0", true)
local function libraryOwned(x)
  return LRC ~= nil and x ~= nil and (x == LRC.frame or x == LRC.cacheResetTimer)
end

--- The addon's live registrations, the library's left out.
local function addonRegistrations()
  local out = {}
  for _, r in ipairs(M.__registrations()) do
    if not libraryOwned(r.target) then out[#out + 1] = r end
  end
  return out
end

--- The live registration set (events, unit events, bus messages), as sorted keys.
local function regSet()
  local out = {}
  for i, r in ipairs(addonRegistrations()) do out[i] = regKey(r) end
  table.sort(out)
  return out
end

--- The addon's armed timers, tickers and OnUpdate scripts, the library's left out.
local function addonTimers()
  local out = {}
  for _, t in ipairs(M.__timers()) do
    if not libraryOwned(t) then out[#out + 1] = t end
  end
  return out
end

--- How many of THIS addon's handlers M.__fire reached: the library frame, which the mock counts once
--- per event it is registered for, is taken back out.
local function addonFire(event)
  local lib = 0
  for _, r in ipairs(M.__registrations()) do
    if r.event == event and libraryOwned(r.target) then lib = 1 end
  end
  return M.__fire(event) - lib
end

local function joined(list) return table.concat(list, "\n  ") end

--- Is `f` drawn: shown by its own flag and by every ancestor's. The kit's IsShown answers the
--- frame's own flag; the client's IsVisible walks the parent chain, and a stand-down hides a
--- container's root, not every texture under it.
local function drawn(f)
  local p = f
  while p do
    if not p.__shown then return false end
    p = p.__parent
  end
  return true
end

--- The frames of THIS addon on screen: every range container's root that is drawn. The kit builds
--- every frame shown, the library's and the client's included, so the survey is the addon's own
--- displays rather than M.__shownFrames() whole.
local function addonShown()
  local out = {}
  NS.Container.ForEach(function(inst)
    if inst.frame and drawn(inst.frame) then out[#out + 1] = inst.frame end
  end)
  NS.Container.ForEachPlate(function(inst)
    if inst.frame and drawn(inst.frame) then out[#out + 1] = inst.frame end
  end)
  return out
end

--- How many frames went from hidden to shown since `before` (a M.__shownFrames() list).
local function newlyShown(before)
  local was, n = {}, 0
  for _, f in ipairs(before) do was[f] = true end
  for _, f in ipairs(M.__shownFrames()) do
    if not was[f] then n = n + 1 end
  end
  return n
end

--- Let one frame pass for the zero-delay one-shots queued so far: each runs once and is spent, as
--- the client runs a C_Timer.After(0) on the next frame. Anything a run arms again stays armed.
local function passOneFrame()
  local live, due = {}, {}
  for _, t in ipairs(M.__timers()) do live[t] = true end
  for i = #M.__timers, 1, -1 do
    local t = M.__timers[i]
    if t.delay == 0 and live[t.timer or t] then
      table.remove(M.__timers, i)
      due[#due + 1] = t
    end
  end
  for i = #due, 1, -1 do due[i].fn() end
end

local function assertNoTimers(where)
  assertEqual(#addonTimers(), 0, "a timer armed on a stood-down addon (" .. where .. "): " .. #addonTimers())
end

--- An enabled, stood-up addon: the baseline every case measures from. Answers step 1's three
--- snapshots: the registration set R_on, the armed-timer set T_on and the addon's shown frames F_on.
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
  return regSet(), addonTimers(), addonShown()
end

-- The perf hold's refusal (slash-commands-§7, *Which refusal, by hold*), pinned here because no
-- library constant carries it: the collection's wording, a plain sentence with its period.
local PERF_LINE = "Not available during a performance capture."

local function disable() NS.SetByPath("enabled", false) end
local function enable()  NS.SetByPath("enabled", true)  end

test("disabled 1: the enabled addon registers something to stand down from", function()
  local R_on, T_on, F_on = bringUp()
  assertTrue(#R_on > 0, "R_on is non-empty: an addon registering nothing passes every later step")
  assertEqual(type(T_on), "table", "T_on is taken")
  assertEqual(type(F_on), "table", "F_on is taken")
  local events = {}
  for _, r in ipairs(addonRegistrations()) do
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
  -- red under: drop the addon:UnregisterLifecycleEvents() or the NS.BusStandDown() in
  -- core/LifecycleSetup.lua's StandDown (the lifecycle events, or the bus messages, survive).
  local after = regSet()
  assertEqual(#after, 0, "survivors of the stand-down:\n  " .. joined(after))
  enable()
end)

test("disabled 4: no timer, ticker or OnUpdate is left armed, and both preview modes end", function()
  bringUp()
  NS.SetTestMode(true, "test")
  NS.SetSimMode(true, "test")
  disable()
  assertNoTimers("at the disable")
  assertFalse(NS.IsTestMode(), "Test mode ended with the stand-down")
  assertFalse(NS.IsSimMode(), "Sim mode ended with the stand-down")
  enable()
end)

test("disabled 4: a skin notice owed through combat leaves nothing armed and writes nothing", function()
  -- The one-time skin notice is refused in combat and asked again when combat ends. That wait is a
  -- one-shot PLAYER_REGEN_ENABLED registration the stand-down drops, never a C_Timer poll.
  -- red under: the NOTICE_RETRY C_Timer.After poll back in core/SkinSetup.lua (a timer survives
  -- the stand-down and writes db.global.skinNotice into the disabled addon).
  local picker = M.LibStub("LibKa0s-Options-1.0", true)
  local g = NS.db.global
  local savedNotice, savedClaim = g.skinNotice, picker and picker.__noticeClaimed
  bringUp()
  g.skinNotice = nil
  if picker then picker.__noticeClaimed = nil end
  local realCombat = M.InCombatLockdown
  M.InCombatLockdown = function() return true end
  local ok, err = pcall(function()
    local before, timersBefore = #regSet(), #addonTimers()
    local _, why = NS.MaybeShowSkinNotice()
    assertEqual(why, "combat", "precondition: the notice is owed and refused in combat")
    assertEqual(#regSet(), before + 1, "the owed notice waits on ONE new registration")
    assertEqual(#addonTimers(), timersBefore, "and arms no timer to poll with")
    disable()
    assertNoTimers("with the notice owed")
    assertEqual(#regSet(), 0, "the notice's wait survived the stand-down:\n  " .. joined(regSet()))
    M.InCombatLockdown = function() return false end
    M.__resetSvWrites()
    M.__fireEvent("PLAYER_REGEN_ENABLED")
    M.__fireTimers()
    assertEqual(g.skinNotice, nil, "the stood-down addon recorded the notice")
    assertEqual(#M.__svWrites(), 0, "SavedVariables writes after the combat edge")
  end)
  M.InCombatLockdown = realCombat
  enable()
  NS.HideSkinPicker()
  g.skinNotice = savedNotice
  if picker then picker.__noticeClaimed = savedClaim end
  assertTrue(ok, tostring(err))
end)

test("disabled 5: every frame the enabled addon drew is hidden", function()
  -- A container in Test mode draws without a unit: the baseline has something of ours on screen.
  local id = NS.CM.Create("target")
  NS.CM.FlushPending()
  bringUp()
  NS.SetTestMode(true, "test")
  NS.CM.FlushPending()
  local F_on = addonShown()
  assertTrue(#F_on > 0, "precondition: the baseline draws a range display")
  disable()
  for _, f in ipairs(F_on) do
    assertFalse(drawn(f), "a range display shown at baseline is still drawn")
  end
  assertEqual(#addonShown(), 0, "something of ours is on screen while disabled")
  enable()
  NS.EndModes("test baseline")
  NS.CM.Delete(id)
  NS.CM.FlushPending()
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

test("disabled 6: every baseline event, fired anyway, reaches its handler and writes, prints and shows nothing", function()
  local R_on = bringUp()
  -- R_on as (target, event) pairs: the addon's OWN stood-down targets, captured before the
  -- stand-down removes them from the registry. Bus messages are not game events; step 9 covers them.
  local fires, sawCombat = {}, false
  for _, r in ipairs(addonRegistrations()) do
    if r.kind == "event" or r.kind == "frame" or r.kind == "unit" then
      fires[#fires + 1] = { target = r.target, event = r.event, key = regKey(r) }
      if r.event == "PLAYER_REGEN_DISABLED" then sawCombat = true end
    end
  end
  assertTrue(#fires > 0, "precondition: the baseline registers game events")
  assertTrue(sawCombat, "the combat-entry event is in the baseline set by name")

  disable()
  M.__resetSvWrites()
  M.__resetPrinted()
  local shownBefore = #M.__shownFrames()

  -- The client fires at the live registry only, which is empty now: nothing may run.
  local seen, ran = {}, 0
  for _, f in ipairs(fires) do
    if not seen[f.event] then seen[f.event] = true; ran = ran + addonFire(f.event) end
  end
  assertEqual(ran, 0, "a handler ran off a game event while the addon was disabled")

  -- And the falsification half, PER EVENT: each fire is driven at the target that registered it
  -- and MUST reach a handler, so the silence below is the addon's and not the harness's.
  for _, f in ipairs(fires) do
    assertTrue(M.__fireUnconditional(f.target, f.event) >= 1, f.key .. " reached no handler")
  end
  -- red under: a handler left registered in StandDown (it writes, prints or shows from the fire),
  -- or `locked = true` written on PLAYER_REGEN_DISABLED from a draw-gated handler.
  assertEqual(#M.__svWrites(), 0, "SavedVariables writes from a game event")
  assertEqual(#M.__printed(), 0, "lines printed: " .. table.concat(M.__printed(), " / "))
  assertEqual(#M.__shownFrames(), shownBefore, "a frame was shown by a game event while disabled")
  assertNoTimers("after every baseline event fired")

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
  NS.OpenOptionsPanel = realOpen
  NS.DebugLog.RunDiagnostics = realDiag
  assertEqual(opened, 1, "a bare `/rm` must open the settings panel while disabled")
  -- A live verb keeps answering, so `resetall` may reset the skin and the options library queue its
  -- one-frame panel re-render (the settings panel is setup and stays up); once that frame has
  -- passed, nothing may still be armed.
  passOneFrame()
  assertNoTimers("after every verb was dispatched")
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

test("disabled 7: under the perf hold alone a feature verb answers the capture line, not the enable one", function()
  bringUp()
  NS.SetByPath("locked", true)
  NS.Perf.Suspend()
  local ok, err = pcall(function()
    assertTrue(NS.IsStoodDown() and not NS.IsDisabled(), "precondition: the perf hold alone")
    local refusal = NS.Slash:DisabledLine()
    for _, verb in ipairs({ "unlock", "test", "skin" }) do
      M.__resetPrinted()
      NS.Slash:OnSlash(verb)
      local out = M.__printed()
      assertEqual(#out, 1, "`/rm " .. verb .. "` answers ONE line under the perf hold: " .. joined(out))
      assertTrue(out[1]:find(PERF_LINE, 1, true) ~= nil, "`/rm " .. verb .. "`: " .. tostring(out[1]))
      assertFalse(out[1]:find(refusal, 1, true) ~= nil, "the disabled line under the perf hold alone")
    end
    assertTrue(NS.GetSetting("locked"), "the refused unlock wrote nothing")
    assertFalse(NS.IsTestMode(), "and Test mode did not start")
    -- Both holds: the disabled line wins.
    disable()
    M.__resetPrinted()
    NS.Slash:OnSlash("unlock")
    local out = M.__printed()
    assertEqual(#out, 1, "one line under both holds")
    assertTrue(out[1]:find(refusal, 1, true) ~= nil, "under both holds the disabled line wins")
  end)
  NS.Perf.Resume()
  enable()
  assertTrue(ok, tostring(err))
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
  local shown = M.__shownFrames()
  object.OnClick(object, "LeftButton")
  NS.OpenOptionsPanel = realOpen
  assertEqual(opened, 1, "left-click must open the settings panel while disabled")
  assertEqual(#M.__svWrites(), 0, "a disabled addon's left click wrote SavedVariables")
  assertEqual(newlyShown(shown), 0, "a disabled addon's left click showed a frame")

  local Menu = dofile("tests/mock_menu.lua")(M)
  Menu.install()
  local ok, err = pcall(function()
    local before = M.__shownFrames()
    object.OnClick(object, "RightButton")
    local menu = assert(Menu.last, "the right click opened no menu")
    assertEqual(#M.__svWrites(), 0, "opening the menu wrote SavedVariables")
    assertEqual(newlyShown(before), 0, "opening the menu showed a frame")
    assertTrue(menu:Find("Enabled").enabled, "Enabled is live while disabled")
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

test("disabled 9: a range display made while disabled is the one the stand-up rebuilds", function()
  -- This addon's registration set is static (every container shares the lifecycle events), so the
  -- settings that shape what comes back are the containers: their units are what the ticker
  -- watches, and their instances are what the renderer draws.
  local R_on = bringUp()
  assertFalse(NS.Ticker.IsWatched("focus"), "precondition: nothing watches focus")
  disable()
  local id = NS.CM.Create("focus")
  assertFalse(NS.Ticker.IsWatched("focus"), "a stood-down addon watches nothing")
  enable()
  NS.CM.FlushPending()
  local ok, err = pcall(function()
    assertTrue(NS.Ticker.IsWatched("focus"), "the stand-up watches the display made while down")
    assertTrue(NS.Container.Get(id) ~= nil, "and the renderer built it")
    assertEqual(table.concat(regSet(), "\n"), table.concat(R_on, "\n"), "with the registration set it went down with")
    disable()
    NS.CM.Delete(id)
    enable()
    NS.CM.FlushPending()
    assertFalse(NS.Ticker.IsWatched("focus"), "a display deleted while down does not come back")
    assertEqual(NS.Container.Get(id), nil, "and has no instance")
  end)
  if NS.CM.Get(id) then NS.CM.Delete(id); NS.CM.FlushPending() end
  assertTrue(ok, tostring(err))
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
  -- red under: a Resume (core/PerfSetup.lua) that calls StandUp directly instead of releasing its
  -- hold and re-evaluating the latch (a disabled addon comes back up mid-session).
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
