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

test("anchors: test_unlock_parks_cursor — unlocked, a cursor container waits at its screen point with a strip", function()
  -- red under: an unlock that leaves a cursor container following the cursor, with no strip.
  H.with(function()
    local id, inst = H.container("mouseover", { anchor = { mode = "cursor", x = 40, y = -60 } })
    assertEqual(inst.anchorMode, "cursor", "locked: it follows the cursor")
    assertFalse(inst.dragHandle ~= nil and inst.dragHandle:IsShown(), "with no strip")
    local calls = H.points(inst.frame, function() unlock(true) end)
    assertEqual(inst.anchorMode, "screen", "unlocked: on the screen anchor")
    local last = calls[#calls]
    assertTrue(last and last[2] == M.UIParent and last[4] == 40 and last[5] == -60, "at its stored screen point")
    assertFalse(NS.Anchors.Cursor.__has(inst), "out of the cursor follow")
    assertTrue(inst.dragHandle ~= nil and inst.dragHandle:IsShown(), "wearing the strip")
    -- A drag moves where it waits, and leaves it a cursor container.
    rawset(inst.frame, "GetPoint", function() return "CENTER", M.UIParent, "CENTER", 10, 20 end)
    inst.dragHandle:__fire("OnDragStart")
    inst.dragHandle:__fire("OnDragStop")
    rawset(inst.frame, "GetPoint", nil)
    NS.CM.FlushPending()
    local a = NS.CM.Get(id).anchor
    assertEqual(a.mode .. " " .. a.x .. " " .. a.y, "cursor 10 20", "the wait point moved, the mode kept")
    assertEqual(inst.anchorMode, "screen", "still waiting while unlocked")
    -- Combat ends the unlocked show-all: it follows the cursor again.
    NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
    assertEqual(inst.anchorMode, "cursor", "combat: back on the cursor")
    assertFalse(inst.dragHandle:IsShown(), "and the strip is down")
    NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
    assertEqual(inst.anchorMode, "screen", "combat over: waiting again")
    unlock(false)
    assertEqual(inst.anchorMode, "cursor", "locked: on the cursor")
    assertFalse(inst.dragHandle:IsShown(), "with no strip")
  end)
end)

test("anchors: test_unlock_strip_on_every_container — a frame container wears a muted strip it cannot drag by", function()
  -- red under: drag strips only on screen containers.
  H.with(function()
    local tf = H.frame("TargetFrame")
    local had = rawget(_G, "TargetFrame")
    rawset(_G, "TargetFrame", tf)
    local ok, err = pcall(function()
      local id, inst = H.container("target", { anchor = { mode = "frame", frame = { provider = "blizzard", name = "" } } })
      assertEqual(inst.anchorMode, "frame")
      unlock(true)
      assertEqual(inst.anchorMode, "frame", "it stays on its frame")
      local h = inst.dragHandle
      assertTrue(h ~= nil and h:IsShown(), "and wears the strip")
      assertTrue(h.__label:find("|cff", 1, true) ~= nil, "its name muted")
      rawset(inst.frame, "GetPoint", function() return "CENTER", M.UIParent, "CENTER", 99, 99 end)
      h:__fire("OnDragStart")
      h:__fire("OnDragStop")
      rawset(inst.frame, "GetPoint", nil)
      local a = NS.CM.Get(id).anchor
      assertFalse(a.x == 99, "a drag saves nothing")
      -- Test mode tags the label.
      assertTrue(NS.SetTestMode(true, "test"))
      assertTrue(h.__label:find(NS.L["TEST"], 1, true) ~= nil, "Test mode tags it")
      NS.SetTestMode(false, "test")
      assertTrue(h.__label:find(NS.L["TEST"], 1, true) == nil, "and the tag goes with it")
      unlock(false)
      assertFalse(h:IsShown(), "locked: no strip")
    end)
    rawset(_G, "TargetFrame", had)
    if not ok then error(err, 0) end
  end)
end)

test("anchors: test_tagged_handle_is_the_marker — while the tagged drag strip shows, the TestStrip hides", function()
  -- red under: a TestStrip stacked over every unlocked display's TEST-tagged drag strip
  -- (preview-mode, *Where the strip sits*, the tagged drag handle, v2.114.0).
  H.with(function()
    local _, inst = H.container("target")
    assertTrue(NS.SetTestMode(true, "test"))
    local strip = inst.strips and inst.strips.test
    assertTrue(strip and strip:IsShown(), "locked: the TestStrip marks the display")
    unlock(true)
    local h = inst.dragHandle
    assertTrue(h:IsShown() and h.__label:find(NS.L["TEST"], 1, true) ~= nil, "unlocked: the drag strip, tagged")
    assertFalse(strip:IsShown(), "and no TestStrip beside it")
    unlock(false)
    assertTrue(strip:IsShown(), "locked again: the TestStrip is back")
    unlock(true)
    NS.SetTestMode(false, "test")
    assertTrue(h:IsShown() and h.__label:find(NS.L["TEST"], 1, true) == nil, "Test mode off: untagged")
    assertFalse(strip:IsShown(), "and no TestStrip")
    unlock(false)
  end)
  NS.EndModes("test reset")
end)

test("anchors: test_strip_marks — the strip's settings mark opens the display, its close mark disables it", function()
  H.with(function()
    local id, inst = H.container("target")
    unlock(true)
    local opened
    local realOpen = NS.OpenOptionsPanel
    NS.OpenOptionsPanel = function(page) opened = page end
    local ok, err = pcall(function()
      NS.Anchors.Screen.__marks(inst).settings()
      assertEqual(opened, "containers", "the Containers page")
      assertEqual(select(2, NS.SelectedContainer()), id, "on this display")
      NS.Anchors.Screen.__marks(inst).close()
      assertFalse(NS.CM.Get(id).enabled, "the close mark disables it")
    end)
    NS.OpenOptionsPanel = realOpen
    if not ok then error(err, 0) end
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
    unlock(false)
    NS.CM.Get(id).anchor.mode = "cursor"
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    assertEqual(inst.anchorMode, "cursor")
    assertFalse(inst.dragHandle:IsShown(), "the strip went with the screen anchor")
  end)
end)

test("anchors: a container leaving the screen anchor is no longer clamped to the screen", function()
  -- red under: Screen.Detach without SetClampedToScreen(false) (a container moved to a nameplate, a
  -- frame or the cursor stays pinned at the screen's edge).
  local restore = dofile("tests/_kit/mock_layers.lua")(M)
  local ok, err = pcall(H.with, function()
    local id, inst = H.container("target")
    assertTrue(M.__layers(inst.frame).clamped, "on screen: clamped")
    NS.CM.Get(id).anchor.mode = "cursor"
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    assertEqual(inst.anchorMode, "cursor")
    assertFalse(M.__layers(inst.frame).clamped, "at the cursor: the clamp went with the screen anchor")
  end)
  restore()
  if not ok then error(err, 0) end
end)
