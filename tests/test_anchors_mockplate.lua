-- tests/test_anchors_mockplate.lua — the preview nameplate (modules/Anchors_Mockplate.lua): unlocked
-- out of combat, a container that sits on a nameplate is drawn beside a stand-in plate, placed as its
-- `nameplate` point and offsets would place it on a real one, and it still drags from its screen point.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse

local H = dofile("tests/anchors_env.lua")
local installPaint = dofile("tests/_kit/mock_paint.lua")
local Mock = NS.Anchors.Mockplate

local function unlock(on) NS.SetByPath("locked", not on) end

--- The last SetPoint `frame` and `other` (the stand-in) each receive while `fn` runs.
local function placed(root, plate, fn)
  local plateCalls
  local rootCalls = H.points(root, function() plateCalls = H.points(plate, fn) end)
  return rootCalls[#rootCalls] or {}, plateCalls[#plateCalls] or {}
end

local function reapply(inst, id) return function() NS.Anchors.Apply(inst, NS.CM.Get(id)) end end

test("mockplate: test_unlock_draws_preview_plate — an own-plate container sits beside a stand-in plate while unlocked", function()
  -- red under: an unlock that parks a nameplate container on the bare screen anchor, with no plate.
  H.with(function()
    local id, inst = H.container("target", { anchor = { mode = "nameplate", x = 30, y = -40 } })
    assertEqual(inst.anchorMode, "nameplate", "locked: on its unit's own plate")
    assertEqual(Mock.__plate(inst), nil, "no stand-in built yet")
    unlock(true)
    assertEqual(inst.anchorMode, "mockplate", "unlocked: beside the stand-in")
    local p = Mock.__plate(inst)
    assertTrue(p ~= nil and p:IsShown(), "the stand-in shows")
    local root, at = placed(inst.frame, p, reapply(inst, id))
    assertTrue(root[2] == M.UIParent and root[4] == 30 and root[5] == -40, "the root waits at its screen point")
    -- The default nameplate anchor: the container's TOP at the plate's BOTTOM, 2 under it. The
    -- stand-in hangs off the root by the inverse: its BOTTOM at the root's TOP, 2 over it.
    assertEqual(at[1] .. " " .. at[3], "BOTTOM TOP", "the plate's relPoint on the root's point")
    assertTrue(at[2] == inst.frame and at[4] == 0 and at[5] == 2, "offset by the inverse of the nameplate's")
    assertTrue(p.nameText:find(NS.L["Target"], 1, true) ~= nil, "named for whose plate it stands for")
    local h = inst.dragHandle
    assertTrue(h ~= nil and h:IsShown(), "it wears the drag strip")
    assertTrue(h.__label:find("|cff", 1, true) == nil, "not muted: it drags")
    -- A drag moves where it waits (the stand-in follows the root), and keeps it a nameplate container.
    rawset(inst.frame, "GetPoint", function() return "CENTER", M.UIParent, "CENTER", 5, 6 end)
    h:__fire("OnDragStart")
    h:__fire("OnDragStop")
    rawset(inst.frame, "GetPoint", nil)
    NS.CM.FlushPending()
    local a = NS.CM.Get(id).anchor
    assertEqual(a.mode .. " " .. a.x .. " " .. a.y, "nameplate 5 6", "the wait point moved, the mode kept")
    unlock(false)
    assertEqual(inst.anchorMode, "nameplate", "locked: back on its own plate")
    assertFalse(p:IsShown(), "and the stand-in hides")
  end)
end)

test("mockplate: test_preview_plate_follows_settings — a nameplate point or offset written while unlocked re-places it", function()
  H.with(function()
    local id, inst = H.container("target", { anchor = { mode = "nameplate" } })
    unlock(true)
    NS.CM.SetField(id, "nameplate.point", "BOTTOM")
    NS.CM.SetField(id, "nameplate.relPoint", "TOP")
    NS.CM.SetField(id, "nameplate.x", 7)
    NS.CM.SetField(id, "nameplate.y", 9)
    NS.CM.FlushPending()
    local _, at = placed(inst.frame, Mock.__plate(inst), reapply(inst, id))
    assertEqual(at[1] .. " " .. at[3] .. " " .. at[4] .. " " .. at[5], "TOP BOTTOM -7 -9",
      "the container over the plate now: the plate under it")
    unlock(false)
  end)
end)

test("mockplate: test_strip_clears_preview_plate — the drag strip is lifted over a plate above the container", function()
  -- red under: a strip left on the root's top edge, over the stand-in.
  H.with(function()
    local id, inst = H.container("target", { anchor = { mode = "nameplate" } })
    unlock(true)
    inst.width, inst.height = 40, 20
    local c = NS.CM.Get(id)
    local left, bottom, right, top = Mock.Rect(inst, c)
    assertEqual(left .. " " .. bottom .. " " .. right .. " " .. top, "-40 22 80 34",
      "the plate's box from the stored points alone, nothing measured")
    inst.handleLift = 0
    local calls = H.points(inst.dragHandle, function() Mock.Relaid(inst) end)
    assertEqual(inst.handleLift, 28, "over the plate and its name line")
    local h = calls[#calls] or {}
    assertEqual(h[1] .. " " .. h[3] .. " " .. h[5], "BOTTOM TOP 30", "the strip sits that much higher")
    -- A container over the plate leaves its strip on its own top edge.
    NS.CM.SetField(id, "nameplate.point", "BOTTOM")
    NS.CM.SetField(id, "nameplate.relPoint", "TOP")
    NS.CM.FlushPending()
    inst.width, inst.height = 40, 20
    Mock.Relaid(inst)
    assertEqual(inst.handleLift, 0, "nothing above it to clear")
    unlock(false)
    assertEqual(inst.handleLift, 0, "the lift goes with the stand-in")
  end)
end)

test("mockplate: test_nameplates_stand_in — an All nameplates container's stand-in sits beside a stand-in plate", function()
  H.with(function()
    local id = NS.CM.Create("nameplates", { anchor = { mode = "nameplate" } })
    NS.CM.FlushPending()
    unlock(true)
    local inst = NS.Container.Get(id)
    assertTrue(inst ~= nil, "unlocked: the stand-in instance")
    assertEqual(inst.anchorMode, "mockplate")
    assertEqual(Mock.__plate(inst).nameText, NS.L["Nameplate (any enemy)"])
    unlock(false)
  end)
end)

test("mockplate: test_combat_ends_preview_plate — combat puts the container back on its plate", function()
  H.with(function()
    local _, inst = H.container("target", { anchor = { mode = "nameplate" } })
    unlock(true)
    local p = Mock.__plate(inst)
    NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
    assertEqual(inst.anchorMode, "nameplate", "combat: on its own plate")
    assertFalse(p:IsShown(), "the stand-in hides")
    NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
    assertEqual(inst.anchorMode, "mockplate", "combat over: beside it again")
    assertTrue(p:IsShown())
    unlock(false)
  end)
end)

test("mockplate: test_preview_plate_keeps_stock_look — the stand-in keeps a nameplate's look under every skin", function()
  -- red under: the stand-in reading bar.bg, bar.border and sem.bad and repainting on OnLooksChanged
  -- (skinning-§9 Preview stand-ins, owner ruling U-24 of 2026-11-20).
  local restorePaint = installPaint(M)
  local S = NS.Skin
  local realColor = S.Color
  local ok, err = pcall(H.with, function()
    S.Color = function() return 0.3, 0.6, 0.9, 1 end
    local _, inst = H.container("target", { anchor = { mode = "nameplate" } })
    unlock(true)
    local p = Mock.__plate(inst)
    M.LibStub("LibKa0s-Skin-1.0"):__NotifyLooks("RangeMaster")
    NS.CM.FlushPending()
    local function same(got, want, what)
      for i = 1, 4 do assertEqual(got and got[i], want[i], what .. " component " .. i) end
    end
    same(M.__paint(p.bg).color, { 0.05, 0.05, 0.05, 0.85 }, "the plate's ground")
    same(M.__paint(p.fill).color, { 0.78, 0.16, 0.16, 1 }, "an enemy plate's health")
    same(M.__paint(p.edges[1]).color, { 0, 0, 0, 1 }, "the plate's edge")
    local name = M.__paint(p.name)
    assertEqual(name.font, nil, "the name line keeps the client's font object")
    assertEqual(name.textColor, nil, "and its color")
    unlock(false)
  end)
  S.Color = realColor
  restorePaint()
  if not ok then error(err, 0) end
end)
