-- tests/test_anchors_screen.lua — the free-on-screen anchor (modules/Anchors_Screen.lua) and the
-- dispatcher it is the default of (modules/Anchors.lua): a container sits at its stored point on
-- UIParent, shows LibKa0s-Widgets' drag strip while unlocked, and a drag saves its point and offsets
-- through the container registry's own writer. The v0.1.0 plan, Task 6; design spec section 5.4.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local H = dofile("tests/anchors_env.lua")

local function unlock(on) NS.SetByPath("locked", not on) end

test("anchors: a screen container sits at its stored point on UIParent", function()
  H.with(function()
    local id, inst = H.container("target", { anchor = { point = "TOPLEFT", relPoint = "CENTER", x = 12, y = -34 } })
    assertEqual(inst.anchorMode, "screen")
    local calls = H.points(inst.frame, function() NS.Anchors.Apply(inst, NS.CM.Get(id)) end)
    assertEqual(#calls, 1, "one SetPoint")
    local p = calls[1]
    assertEqual(p[1], "TOPLEFT")
    assertTrue(p[2] == M.UIParent, "relative to UIParent")
    assertEqual(p[3] .. " " .. p[4] .. " " .. p[5], "CENTER 12 -34")
  end)
end)

test("anchors: a stored point the client does not know falls back to CENTER", function()
  H.with(function()
    local id, inst = H.container("target", { anchor = { point = "MIDDLE", relPoint = 7 } })
    local calls = H.points(inst.frame, function() NS.Anchors.Apply(inst, NS.CM.Get(id)) end)
    assertEqual(calls[1][1] .. " " .. calls[1][3], "CENTER CENTER")
  end)
end)

test("anchors: a locked screen container shows no drag strip; unlocking shows it, locking hides it", function()
  H.with(function()
    local _, inst = H.container("target")
    assertFalse(inst.dragHandle ~= nil and inst.dragHandle:IsShown(), "locked: no strip")
    unlock(true)
    assertTrue(inst.dragHandle ~= nil and inst.dragHandle:IsShown(), "unlocked: the strip shows")
    unlock(false)
    assertFalse(inst.dragHandle:IsShown(), "locked again: hidden")
  end)
end)

test("anchors: test_screen_drag_saves_point — a drag on the strip saves point and offsets through NS.CM", function()
  H.with(function()
    local id, inst = H.container("target")
    unlock(true)
    local h = inst.dragHandle
    h:__fire("OnDragStart")
    rawset(inst.frame, "GetPoint", function() return "TOPLEFT", M.UIParent, "BOTTOMLEFT", 100.4, 200.6 end)
    h:__fire("OnDragStop")
    rawset(inst.frame, "GetPoint", nil)
    local a = NS.CM.Get(id).anchor
    assertEqual(a.point .. " " .. a.relPoint .. " " .. a.x .. " " .. a.y, "TOPLEFT BOTTOMLEFT 100 201",
      "rounded to whole pixels, stored on the container")
    assertTrue(NS.CM.__pending(), "the writer asked for an apply")
    NS.CM.FlushPending()
    local calls = H.points(inst.frame, function() NS.Anchors.Apply(inst, NS.CM.Get(id)) end)
    assertEqual(calls[1][1] .. " " .. calls[1][4] .. " " .. calls[1][5], "TOPLEFT 100 201", "and placed from it")
    unlock(false)
  end)
end)

test("anchors: a drag is refused in combat, and nothing is saved", function()
  H.with(function()
    local id, inst = H.container("target", { anchor = { x = 5, y = 6 } })
    unlock(true)
    M.InCombatLockdown = function() return true end
    rawset(inst.frame, "GetPoint", function() return "TOPLEFT", M.UIParent, "BOTTOMLEFT", 1, 2 end)
    inst.dragHandle:__fire("OnDragStart")
    inst.dragHandle:__fire("OnDragStop")
    rawset(inst.frame, "GetPoint", nil)
    local a = NS.CM.Get(id).anchor
    assertEqual(a.x .. " " .. a.y, "5 6", "unmoved")
    M.InCombatLockdown = function() return false end
    unlock(false)
  end)
end)

test("anchors: a non-screen container shows no drag strip, unlocked or not", function()
  H.with(function()
    local _, inst = H.container("mouseover", { anchor = { mode = "cursor" } })
    unlock(true)
    assertFalse(inst.dragHandle ~= nil and inst.dragHandle:IsShown(), "a cursor container is not dragged")
    unlock(false)
  end)
end)

test("anchors: Reset position puts every screen container back at its default point", function()
  H.with(function()
    local a = H.container("target", { anchor = { point = "TOPLEFT", x = 300, y = 300 } })
    local b = H.container("focus", { anchor = { x = -40, y = 90 } })
    H.container("mouseover", { anchor = { mode = "cursor", cursor = { x = 9, y = 9 } } })
    assertEqual(NS.ResetPositions(), 2, "the two screen containers")
    local sa, sb = NS.CM.Get(a).anchor, NS.CM.Get(b).anchor
    assertEqual(sa.point .. " " .. sa.relPoint .. " " .. sa.x .. " " .. sa.y, "CENTER CENTER 0 0")
    assertEqual(sb.x .. " " .. sb.y, "0 -30", "staggered by id, as a new container is")
  end)
end)

test("anchors: switching a container's mode detaches the old anchor", function()
  H.with(function()
    local id, inst = H.container("target")
    unlock(true)
    assertTrue(inst.dragHandle:IsShown())
    NS.CM.Get(id).anchor.mode = "cursor"
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    assertEqual(inst.anchorMode, "cursor")
    assertFalse(inst.dragHandle:IsShown(), "the strip went with the screen anchor")
    unlock(false)
  end)
end)
