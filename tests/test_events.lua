-- tests/test_events.lua — every event registration survives an unknown name (events-frames-taint-§1).
--
-- The client RAISES `Attempt to register unknown event "<NAME>"` on a name it does not know, and a
-- block of bare RegisterEvent calls loses every line after the one that raised. One event retired by
-- a patch would take the whole enable path down with it. So every registration the addon makes goes
-- through LibKa0s-Core's SafeRegister helpers (published as NS.SafeRegisterEvent /
-- NS.SafeRegisterUnitEvent by core/CoreSetup.lua), and every refused name lands once in the session
-- list NS.State.rejectedEvents, which the [Init] summary and the diagnostics report read back.
--
-- The kit's __badEvents is read at call time on every path: the AceEvent registry, a raw frame's
-- RegisterEvent and RegisterUnitEvent, and C_EventUtils.IsEventValid.
--
-- CLEANUP IS NOT OPTIONAL. This suite runs on the SHARED environment immediately before
-- test_disabled, which compares registration sets, so every case puts back the full registration set
-- and leaves __badEvents and the rejected list empty.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local LIFECYCLE = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

--- Is `event` live on `target` as `kind`, optionally for `unit`?
local function registered(target, kind, event, unit)
  for _, r in ipairs(M.__registrations()) do
    if r.target == target and r.kind == kind and r.event == event
        and (unit == nil or r.unit == unit) then
      return true
    end
  end
  return false
end

local function countOf(list, name)
  local n = 0
  for _, v in ipairs(list) do if v == name then n = n + 1 end end
  return n
end

--- Drop the addon's lifecycle registrations so the next registration is the event's first on the
--- addon object, which is where the client (and the kit's AceEvent registry) raises.
local function dropLifecycle()
  for _, e in ipairs(LIFECYCLE) do NS.addon:UnregisterEvent(e) end
end

--- Put everything back: no bad names, an empty rejected list, the full registration set.
local function restore()
  M.__badEvents = {}
  local list = NS.State.rejectedEvents
  for i = #list, 1, -1 do list[i] = nil end
  NS.addon:RegisterLifecycleEvents()
end

--- Run `fn`, then restore whether or not it raised, then re-raise.
local function guarded(fn)
  local ok, err = pcall(fn)
  restore()
  if not ok then error(err, 0) end
end

test("events: the session rejected list exists and starts empty", function()
  assertEqual(type(NS.State.rejectedEvents), "table", "NS.State.rejectedEvents is the session list")
  assertEqual(#NS.State.rejectedEvents, 0, "nothing rejected in a clean session")
end)

test("events: one unknown lifecycle name costs only itself, and is listed once", function()
  -- red under: a bare self:RegisterEvent in RegisterLifecycleEvents (the first name raises and
  -- the two after it are never registered).
  guarded(function()
    dropLifecycle()
    M.__badEvents = { PLAYER_ENTERING_WORLD = true }
    local ok, err = pcall(NS.addon.RegisterLifecycleEvents, NS.addon)
    assertTrue(ok, "RegisterLifecycleEvents raised on one unknown name: " .. tostring(err))
    assertTrue(registered(NS.addon, "event", "PLAYER_REGEN_DISABLED"),
      "PLAYER_REGEN_DISABLED is still registered after the name before it was refused")
    assertTrue(registered(NS.addon, "event", "PLAYER_REGEN_ENABLED"),
      "PLAYER_REGEN_ENABLED is still registered after the name before it was refused")
    assertFalse(registered(NS.addon, "event", "PLAYER_ENTERING_WORLD"),
      "the refused name is not registered")
    assertEqual(countOf(NS.State.rejectedEvents, "PLAYER_ENTERING_WORLD"), 1)

    -- A disable/enable cycle runs the same block again; the list must not grow.
    NS.addon:RegisterLifecycleEvents()
    assertEqual(countOf(NS.State.rejectedEvents, "PLAYER_ENTERING_WORLD"), 1,
      "a second pass does not list the same name twice")
  end)
end)

test("events: the registered set is exactly the one lifecycle list", function()
  -- red under: an event registered outside NS.__lifecycleEvents, which the stand-down would miss.
  guarded(function()
    local want = {}
    for _, pair in ipairs(NS.__lifecycleEvents) do want[pair[1]] = true end
    for _, r in ipairs(M.__registrations()) do
      if r.target == NS.addon and r.kind == "event" then
        assertTrue(want[r.event], r.event .. " is registered but not in NS.__lifecycleEvents")
      end
    end
  end)
end)
