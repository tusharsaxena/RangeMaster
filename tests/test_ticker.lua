-- tests/test_ticker.lua — the one shared range ticker (modules/Ticker.lua): its adaptive rate, its
-- watch list, RANGE_UPDATED only on change, and the stand-down. The v0.1.0 plan, Task 2; design
-- spec section 5.1.
--
-- The ticker is a real C_Timer.NewTicker on the kit's timer queue (tests/wow_mock.lua re-arms it
-- after each fire, as the client does). A case drives one tick through the handle's own callback,
-- never through M.__fireTimers, so no other suite's queued timer runs here.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local LRC = M.LibStub("LibRangeCheck-3.0", true)

--- Whether a timer handle is no longer armed: absent from the kit's live set, M.__timers().
local function stopped(handle)
  for _, t in ipairs(M.__timers()) do if t == handle then return false end end
  return true
end

local Ticker = NS.Ticker

--- The shared fixture: LRC:GetRange answers `range[unit]` (a {min, max} pair), the named units
--- exist, RANGE_UPDATED is recorded. Everything is put back, every watch dropped and the ticker
--- stopped, whether or not `body` raised.
local function fixture(units, body)
  local range, heard = {}, {}
  local realGet, realUnits = LRC.GetRange, M.__unitExists
  local exists = { player = true }
  for _, unit in ipairs(units) do exists[unit] = true; range[unit] = { 20, 25 } end
  M.__unitExists = exists
  LRC.GetRange = function(_, unit)
    local r = range[unit]
    if r then return r[1], r[2] end
  end
  local probe = NS.NewBusTarget()
  probe:RegisterMessage(NS.MSG.RANGE_UPDATED, function(_, unit, state, lo, hi)
    heard[#heard + 1] = ("%s=%s:%s-%s"):format(unit, state, tostring(lo), tostring(hi))
  end)
  local ok, err = pcall(body, range, heard)
  probe:UnregisterAllMessages()
  for _, unit in ipairs(units) do
    while Ticker.IsWatched(unit) do Ticker.Unwatch(unit) end
  end
  LRC.GetRange, M.__unitExists = realGet, realUnits
  M.InCombatLockdown = function() return false end
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  if not ok then error(err, 0) end
end

--- One tick, through the live ticker handle.
local function tick()
  local h = Ticker.__handle()
  assertTrue(h ~= nil, "the ticker is running")
  h.fn()
end

local function queued(handle)
  for _, t in ipairs(M.__timers) do if t == handle then return true end end
  return false
end

test("ticker: test_rate_idle_10hz — out of combat one ticker runs at 10 Hz and re-arms", function()
  fixture({ "target" }, function()
    assertFalse(Ticker.IsRunning(), "nothing watched, nothing running")
    Ticker.Watch("target")
    assertTrue(Ticker.IsRunning(), "a watched live unit starts the ticker")
    assertEqual(Ticker.Interval(), 0.1, "10 Hz")
    local h = Ticker.__handle()
    assertEqual(h.delay, 0.1, "the C_Timer ticker itself runs at 0.1 s")
    h.fn()
    assertTrue(queued(h), "the ticker re-arms after firing")
    Ticker.Watch("target")
    assertTrue(Ticker.__handle() == h, "a second watch does not start a second ticker")
  end)
end)

test("ticker: test_rate_combat_20hz — combat restarts the one ticker at 20 Hz, and back", function()
  fixture({ "target" }, function()
    Ticker.Watch("target")
    local idle = Ticker.__handle()
    NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
    assertEqual(Ticker.Interval(), 0.05, "20 Hz in combat")
    local fight = Ticker.__handle()
    assertTrue(stopped(idle), "the idle ticker was canceled, not left beside the new one")
    assertEqual(fight.delay, 0.05)
    NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
    assertEqual(Ticker.Interval(), 0.1, "back to 10 Hz")
    assertTrue(stopped(fight), "the combat ticker was canceled")
  end)
end)

test("ticker: test_stops_when_nothing_watched — the last unwatch cancels the ticker", function()
  fixture({ "target", "focus" }, function()
    Ticker.Watch("target")
    Ticker.Watch("focus")
    Ticker.Watch("target")
    local h = Ticker.__handle()
    Ticker.Unwatch("target")
    assertTrue(Ticker.IsRunning(), "target is still watched once, and focus")
    Ticker.Unwatch("target")
    Ticker.Unwatch("focus")
    assertFalse(Ticker.IsRunning(), "nothing watched")
    assertTrue(stopped(h), "the handle was canceled")
    assertNil(Ticker.Interval(), "a stopped ticker has no rate")
  end)
end)

test("ticker: it also stops when every watched unit is gone, and an event restarts it", function()
  fixture({ "target" }, function()
    Ticker.Watch("target")
    M.__unitExists.target = false
    tick()
    assertFalse(Ticker.IsRunning(), "no live unit, so no ticker")
    M.__unitExists.target = true
    M.__fireEvent("PLAYER_TARGET_CHANGED")
    assertTrue(Ticker.IsRunning(), "PLAYER_TARGET_CHANGED brought it back")
  end)
end)

test("ticker: test_update_only_on_change — RANGE_UPDATED fires on a change and never on a repeat", function()
  fixture({ "target" }, function(range, heard)
    Ticker.Watch("target")
    assertEqual(table.concat(heard, ","), "target=known:20-25", "the first read is announced")
    tick()
    tick()
    assertEqual(#heard, 1, "two identical ticks send nothing")
    range.target = { 40, nil }
    tick()
    assertEqual(heard[2], "target=known:40-nil", "a change is sent with its payload")
    tick()
    assertEqual(#heard, 2, "and not again")
  end)
end)

test("ticker: test_mouseover_revalidated_each_tick — mouseover leaving with no event reads none", function()
  fixture({ "mouseover", "target" }, function(_, heard)
    Ticker.Watch("mouseover")
    Ticker.Watch("target")
    M.__unitExists.mouseover = false   -- the client fires no event when the mouseover clears
    tick()
    assertEqual(heard[#heard], "mouseover=none:nil-nil", "the next tick saw it gone")
    assertTrue(Ticker.IsRunning(), "target is still live")
  end)
end)

test("ticker: N watches of one unit cost one range query per tick", function()
  fixture({ "target" }, function()
    local real, calls = LRC.GetRange, 0
    LRC.GetRange = function(...) calls = calls + 1; return real(...) end
    for _ = 1, 5 do Ticker.Watch("target") end
    calls = 0
    tick()
    LRC.GetRange = real
    assertEqual(calls, 1, "one query for five watches")
  end)
end)

test("ticker: the unit events refresh their unit; UNIT_PET only for the player", function()
  fixture({ "pet", "mouseover", "nameplate2" }, function(range, heard)
    Ticker.Watch("pet")
    Ticker.Watch("mouseover")
    Ticker.Watch("nameplate2")
    range.pet, range.mouseover, range.nameplate2 = { 5, 8 }, { 8, 10 }, { 30, 35 }
    M.__fireEvent("UNIT_PET", "party1")
    assertEqual(#heard, 3, "another unit's pet changes nothing")
    M.__fireEvent("UNIT_PET", "player")
    M.__fireEvent("UPDATE_MOUSEOVER_UNIT")
    M.__fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")
    assertEqual(table.concat(heard, ",", 4),
      "pet=known:5-8,mouseover=known:8-10,nameplate2=known:30-35", "each event refreshed its unit")
  end)
end)

test("ticker: PLAYER_FOCUS_CHANGED registers only where the client knows it", function()
  local entry
  for _, pair in ipairs(NS.__lifecycleEvents) do
    if pair[1] == "PLAYER_FOCUS_CHANGED" then entry = pair end
  end
  assertTrue(entry ~= nil and entry.ifValid == true, "the focus event is gated on IsEventValid")
  local realBad = M.__badEvents
  NS.addon:UnregisterEvent("PLAYER_FOCUS_CHANGED")
  M.__badEvents = { PLAYER_FOCUS_CHANGED = true }
  NS.addon:RegisterLifecycleEvents()
  local rejected = 0
  for _, name in ipairs(NS.State.rejectedEvents) do
    if name == "PLAYER_FOCUS_CHANGED" then rejected = rejected + 1 end
  end
  assertEqual(rejected, 0, "an invalid focus event is skipped, never attempted and rejected")
  assertNil(NS.addon.__events and NS.addon.__events.PLAYER_FOCUS_CHANGED, "and not registered")
  M.__badEvents = realBad
  NS.addon:RegisterLifecycleEvents()
  assertTrue(NS.addon.__events.PLAYER_FOCUS_CHANGED ~= nil, "a valid one registers")
end)

test("ticker: a stand-down cancels the ticker and a stand-up rebuilds it from the watch list", function()
  fixture({ "target" }, function(_, heard)
    Ticker.Watch("target")
    local h = Ticker.__handle()
    NS.SetByPath("enabled", false)
    assertFalse(Ticker.IsRunning(), "stood down")
    assertTrue(stopped(h), "the handle was canceled")
    Ticker.Watch("target")
    assertFalse(Ticker.IsRunning(), "a watch while stood down starts nothing")
    NS.SetByPath("enabled", true)
    assertTrue(Ticker.IsRunning(), "the stand-up restarted it")
    assertEqual(heard[#heard], "target=known:20-25", "and re-announced the current range")
  end)
end)
