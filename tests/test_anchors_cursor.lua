-- tests/test_anchors_cursor.lua — the cursor anchor (modules/Anchors_Cursor.lua): every cursor
-- container follows through ONE shared OnUpdate, armed only while one of them is shown, placed at
-- GetCursorPosition() over UIParent's effective scale plus the stored offset. The v0.1.0 plan,
-- Task 6; design spec 5.4.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local H = dofile("tests/anchors_env.lua")
local Cursor = NS.Anchors.Cursor

local function cursorOpts(x, y) return { anchor = { mode = "cursor", x = x or 0, y = y or 0 } } end

test("cursor: test_cursor_single_onupdate — three cursor containers, one OnUpdate script", function()
  H.with(function()
    local insts = {}
    for i = 1, 3 do
      local _, inst = H.container("target", cursorOpts(0, i * 10))
      insts[i] = inst
    end
    local armed = H.onUpdates()
    assertEqual(#armed, 1, "one shared OnUpdate for every cursor container")
    assertTrue(armed[1] == Cursor.__driver(), "and it is the follow's driver")
    for _, inst in ipairs(insts) do
      assertTrue(inst.frame:GetScript("OnUpdate") == nil, "no container runs its own")
    end
  end)
end)

test("cursor: the follow places each shown container at the cursor over UIParent's scale, plus its offset", function()
  H.with(function()
    local _, inst = H.container("target", cursorOpts(10, -20))
    M.__cursor[1], M.__cursor[2] = 400, 300
    rawset(M.UIParent, "GetEffectiveScale", function() return 2 end)
    local calls = H.points(inst.frame, function() Cursor.__driver():__fire("OnUpdate", 0.016) end)
    rawset(M.UIParent, "GetEffectiveScale", nil)
    local p = calls[#calls]
    assertTrue(p[2] == M.UIParent)
    assertEqual(p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], "CENTER BOTTOMLEFT 210 130",
      "(400 / 2 + 10, 300 / 2 - 20)")
  end)
end)

test("cursor: a container drawn at another scale is placed in its own units", function()
  H.with(function()
    local _, inst = H.container("target", { anchor = { mode = "cursor" }, layout = { scale = 2 } })
    M.__cursor[1], M.__cursor[2] = 400, 300
    local calls = H.points(inst.frame, function() Cursor.__driver():__fire("OnUpdate", 0.016) end)
    assertEqual(calls[#calls][4] .. " " .. calls[#calls][5], "200 150")
  end)
end)

test("cursor: the follow runs only while a cursor container is shown", function()
  H.with(function()
    local _, inst = H.container("target", cursorOpts())
    assertEqual(#H.onUpdates(), 1, "shown: armed")
    M.__unitExists.target = false
    NS.Ticker.Changed("target")
    assertFalse(inst.frame:IsShown(), "no target: hidden")
    assertEqual(#H.onUpdates(), 0, "hidden: no OnUpdate left armed")
    M.__unitExists.target = true
    NS.Ticker.Changed("target")
    assertTrue(inst.frame:IsShown())
    assertEqual(#H.onUpdates(), 1, "shown again: armed again")
  end)
end)

test("cursor: a container leaving the cursor mode, or deleted, drops out of the follow", function()
  H.with(function()
    local a, ia = H.container("target", cursorOpts())
    local b = H.container("target", cursorOpts())
    NS.CM.Get(a).anchor.mode = "screen"
    NS.CM.Delete(b)
    NS.CM.FlushPending()
    assertFalse(Cursor.__has(ia), "a screen container is not followed")
    assertEqual(#H.onUpdates(), 0, "nothing left to follow")
  end)
end)

test("cursor: the stand-down leaves the follow disarmed, and the stand-up arms it again", function()
  H.with(function()
    H.container("target", cursorOpts())
    NS.SetByPath("enabled", false)
    NS.SyncEnabledHold()
    assertEqual(#H.onUpdates(), 0)
    NS.SetByPath("enabled", true)
    NS.SyncEnabledHold()
    NS.CM.FlushPending()
    assertEqual(#H.onUpdates(), 1)
  end)
end)
