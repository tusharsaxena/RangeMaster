-- tests/test_anchors_frame.lua — the unit-frame anchor (modules/Anchors_Frame.lua), its providers
-- (modules/FrameProviders.lua: Blizzard, EllesmereUI, a custom global name) and the click-to-pick
-- picker (modules/FramePicker.lua). A missing frame hides the container with one debug line and is
-- looked for again on ADDON_LOADED; an anchor write that lands in combat waits for the leave edge;
-- mouseover, which has no unit frame, follows the cursor. The v0.1.0 plan, Task 6; design spec 5.4.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local H = dofile("tests/anchors_env.lua")

--- Run `fn` with the global `name` set to `frame`, then put the old value back.
local function withGlobal(name, frame, fn)
  local old = rawget(_G, name)
  rawset(_G, name, frame)
  local ok, err = pcall(fn)
  rawset(_G, name, old)
  if not ok then error(err, 0) end
end

local function onFrame(provider, name)
  return { anchor = { mode = "frame", frame = { provider = provider, name = name or "", point = "BOTTOM",
                                                relPoint = "TOP", x = 0, y = 4 } } }
end

-- ---------------------------------------------------------------------------
-- The providers
-- ---------------------------------------------------------------------------

test("frames: the providers name Blizzard's and EllesmereUI's frames per unit, and nothing for mouseover", function()
  local P = NS.FrameProviders
  assertEqual(P.NameFor("blizzard", "target"), "TargetFrame")
  assertEqual(P.NameFor("blizzard", "focus"), "FocusFrame")
  assertEqual(P.NameFor("blizzard", "pet"), "PetFrame")
  assertNil(P.NameFor("blizzard", "mouseover"), "mouseover has no unit frame")
  assertEqual(P.NameFor("ellesmere", "target"), "EllesmereUIUnitFrames_Target")
  assertEqual(P.NameFor("ellesmere", "focus"), "EllesmereUIUnitFrames_Focus")
  assertEqual(P.NameFor("ellesmere", "pet"), "EllesmereUIUnitFrames_Pet")
  assertNil(P.NameFor("ellesmere", "mouseover"))
  assertEqual(P.NameFor("custom", "mouseover", "  MyFrame "), "MyFrame", "a custom name serves any unit")
  assertNil(P.NameFor("custom", "target", ""), "a blank custom name is no frame")
  assertNil(P.NameFor("elvui", "target"), "only the three providers")
end)

test("frames: Resolve answers the live global frame, and nil for a missing, forbidden or non-frame one", function()
  local P = NS.FrameProviders
  local f = H.frame("RMTestFrame")
  withGlobal("RMTestFrame", f, function()
    assertTrue(P.Resolve("custom", "target", "RMTestFrame") == f)
  end)
  assertNil(P.Resolve("custom", "target", "RMTestFrame"), "gone")
  withGlobal("RMTestFrame", H.frame("RMTestFrame", true), function()
    assertNil(P.Resolve("custom", "target", "RMTestFrame"), "forbidden")
  end)
  withGlobal("RMTestFrame", "a string", function()
    assertNil(P.Resolve("custom", "target", "RMTestFrame"), "not a frame")
  end)
end)

-- ---------------------------------------------------------------------------
-- Anchoring
-- ---------------------------------------------------------------------------

test("frames: test_frame_blizzard_target — a target container anchors to TargetFrame", function()
  H.with(function()
    local tf = H.frame("TargetFrame")
    withGlobal("TargetFrame", tf, function()
      local id, inst = H.container("target", onFrame("blizzard"))
      assertEqual(inst.anchorMode, "frame")
      assertTrue(inst.anchorTarget == tf, "anchored to TargetFrame")
      assertTrue(inst.frame:IsShown(), "and drawn")
      local calls = H.points(inst.frame, function() NS.Anchors.Apply(inst, NS.CM.Get(id)) end)
      local p = calls[1]
      assertTrue(p[2] == tf, "relative to the unit frame")
      assertEqual(p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], "BOTTOM TOP 0 4", "at the stored point")
    end)
  end)
end)

test("frames: an EllesmereUI container anchors to EllesmereUI's frame for its unit", function()
  H.with(function()
    local ef = H.frame("EllesmereUIUnitFrames_Focus")
    M.__unitExists.focus = true
    withGlobal("EllesmereUIUnitFrames_Focus", ef, function()
      local _, inst = H.container("focus", onFrame("ellesmere"))
      assertTrue(inst.anchorTarget == ef)
    end)
  end)
end)

--- The SetPoint a fresh Apply of container `id` makes, as "point relPoint x y" plus its relative frame.
local function appliedPoint(id, inst)
  local calls = H.points(inst.frame, function() NS.Anchors.Apply(inst, NS.CM.Get(id)) end)
  local p = calls[#calls]
  return p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5], p[2]
end

test("frames: a new frame container sits on its frame at the frame default point, whatever its id", function()
  H.with(function()
    local tf = H.frame("TargetFrame")
    withGlobal("TargetFrame", tf, function()
      for _ = 1, 3 do H.container("focus") end
      local id, inst = H.container("target", { anchor = { mode = "frame", frame = { provider = "blizzard" } } })
      local at, rel = appliedPoint(id, inst)
      assertTrue(rel == tf)
      assertEqual(at, "BOTTOM TOP 0 2", "above the unit frame, not the screen stagger of its id")
    end)
  end)
end)

test("frames: a screen position does not carry onto the unit frame when the mode changes", function()
  H.with(function()
    local tf = H.frame("TargetFrame")
    withGlobal("TargetFrame", tf, function()
      local id, inst = H.container("target")
      NS.CM.SetPosition(id, "TOPLEFT", "BOTTOMLEFT", 100, 200)
      NS.CM.FlushPending()
      NS.CM.Get(id).anchor.mode = "frame"
      NS.CM.RequestApply()
      NS.CM.FlushPending()
      assertEqual(inst.anchorMode, "frame")
      assertEqual((appliedPoint(id, inst)), "BOTTOM TOP 0 2", "the frame point is its own")
      NS.CM.Get(id).anchor.mode = "screen"
      NS.CM.RequestApply()
      NS.CM.FlushPending()
      local a = NS.CM.Get(id).anchor
      assertEqual(a.point .. " " .. a.relPoint .. " " .. a.x .. " " .. a.y, "TOPLEFT BOTTOMLEFT 100 200",
        "and the screen point is kept for the way back")
    end)
  end)
end)

test("frames: test_frame_missing_then_loaded — hidden with one debug line, anchored on ADDON_LOADED", function()
  H.with(function()
    local inst
    local lines = H.debugLines(function()
      local _
      _, inst = H.container("target", onFrame("custom", "RMTestLateFrame"))
      NS.CM.RequestApply()
      NS.CM.FlushPending()
      M.__fireEvent("ADDON_LOADED", "SomeOtherAddon")
    end)
    local missing = 0
    for _, l in ipairs(lines) do
      if l:find("RMTestLateFrame", 1, true) then missing = missing + 1 end
    end
    assertEqual(missing, 1, "one line, however many applies and retries:\n  " .. table.concat(lines, "\n  "))
    assertFalse(inst.frame:IsShown(), "hidden while its frame is missing")
    assertNil(inst.anchorTarget)
    local late = H.frame("RMTestLateFrame")
    withGlobal("RMTestLateFrame", late, function()
      M.__fireEvent("ADDON_LOADED", "LateAddon")
      assertTrue(inst.anchorTarget == late, "found on ADDON_LOADED")
      assertTrue(inst.frame:IsShown(), "and drawn")
    end)
  end)
end)

test("frames: a frame that appears by PLAYER_ENTERING_WORLD is found there too", function()
  H.with(function()
    local _, inst = H.container("target", onFrame("custom", "RMTestLateFrame"))
    local late = H.frame("RMTestLateFrame")
    withGlobal("RMTestLateFrame", late, function()
      M.__fireEvent("PLAYER_ENTERING_WORLD", false, true)
      assertTrue(inst.anchorTarget == late)
    end)
  end)
end)

test("frames: test_frame_anchor_deferred_in_combat — no anchor write in combat, done on the leave edge", function()
  H.with(function()
    local id, inst = H.container("target", onFrame("custom", "RMTestLateFrame"))
    local late = H.frame("RMTestLateFrame")
    withGlobal("RMTestLateFrame", late, function()
      M.InCombatLockdown = function() return true end
      local calls = H.points(inst.frame, function()
        M.__fireEvent("ADDON_LOADED", "LateAddon")
        NS.Anchors.Apply(inst, NS.CM.Get(id))
      end)
      assertEqual(#calls, 0, "nothing moved in combat")
      assertNil(inst.anchorTarget, "still waiting")
      M.InCombatLockdown = function() return false end
      NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
      assertTrue(inst.anchorTarget == late, "anchored on PLAYER_REGEN_ENABLED")
      assertTrue(inst.frame:IsShown())
    end)
  end)
end)

test("frames: test_mouseover_frame_falls_back_to_cursor — a mouseover container on a unit frame follows the cursor", function()
  H.with(function()
    M.__unitExists.mouseover = true
    local _, inst = H.container("mouseover", onFrame("blizzard"))
    assertEqual(inst.anchorMode, "cursor", "Blizzard has no mouseover frame")
    assertTrue(NS.Anchors.Cursor.__has(inst), "it is in the cursor follow")
    local _, ell = H.container("mouseover", onFrame("ellesmere"))
    assertEqual(ell.anchorMode, "cursor", "nor has EllesmereUI")
  end)
end)

test("frames: a mouseover container on a named custom frame stays on that frame", function()
  H.with(function()
    M.__unitExists.mouseover = true
    local f = H.frame("RMTestFrame")
    withGlobal("RMTestFrame", f, function()
      local _, inst = H.container("mouseover", onFrame("custom", "RMTestFrame"))
      assertEqual(inst.anchorMode, "frame")
      assertTrue(inst.anchorTarget == f)
    end)
  end)
end)

test("frames: a frame that will not take the anchor hides the container instead of raising", function()
  H.with(function()
    local f = H.frame("RMTestFrame")
    withGlobal("RMTestFrame", f, function()
      local id = NS.CM.Create("target", onFrame("custom", "RMTestFrame"))
      local realCreate = M.CreateFrame
      M.CreateFrame = function(...)
        local fr = realCreate(...)
        rawset(fr, "SetPoint", function(_, _, rel) if rel == f then error("anchor family") end end)
        return fr
      end
      local ok = pcall(NS.CM.FlushPending)
      M.CreateFrame = realCreate
      assertTrue(ok, "no error escaped")
      local inst = NS.Container.Get(id)
      assertNil(inst.anchorTarget)
      assertFalse(inst.frame:IsShown())
    end)
  end)
end)

-- ---------------------------------------------------------------------------
-- The picker
-- ---------------------------------------------------------------------------

local FP = NS.FramePicker

test("picker: NamedAncestor walks to the nearest named ancestor, skipping UIParent and forbidden frames", function()
  local named = H.frame("SomeAddonFrame")
  local child = H.frame()
  rawset(child, "GetParent", function() return named end)
  local f, name = FP.NamedAncestor(child)
  assertTrue(f == named)
  assertEqual(name, "SomeAddonFrame")
  assertNil(FP.NamedAncestor(H.frame("UIParent")), "the screen is no anchor")
  assertNil(FP.NamedAncestor(H.frame("RangeMasterAnything")), "nor this addon's own")
  assertNil(FP.NamedAncestor(H.frame("Forbidden", true)), "a forbidden frame ends the walk")
  assertNil(FP.NamedAncestor(nil))
end)

test("picker: Enter on a named frame calls back with its name and ends the pick", function()
  local picked
  local target = H.frame("SomeAddonFrame")
  M.__mouseFoci[1] = target
  assertTrue(FP.Start(function(name) picked = name end))
  local overlay = FP.__overlay()
  overlay:__fire("OnUpdate")             -- the hovered frame is tracked
  overlay:__fire("OnKeyDown", "A")       -- any other key passes through
  assertNil(picked, "only Enter picks")
  overlay:__fire("OnKeyDown", "ENTER")
  M.__mouseFoci[1] = nil
  assertEqual(picked, "SomeAddonFrame")
  assertFalse(FP.IsActive())
  assertNil(overlay:GetScript("OnUpdate"), "its OnUpdate went with it")
end)

test("picker: a mouse press neither picks nor cancels (the click belongs to the game)", function()
  -- red under: an onUpdate that reads IsMouseButtonDown (the click would also reach the frame under
  -- the non-mouse overlay: PlayerFrame targets, an action button casts).
  local canceled, picked = false, nil
  M.__mouseFoci[1] = H.frame("SomeAddonFrame")
  FP.Start(function(n) picked = n end, function() canceled = true end)
  local overlay = FP.__overlay()
  overlay:__fire("OnUpdate")
  M.__mouseDown.LeftButton = true
  overlay:__fire("OnUpdate")
  M.__mouseDown.LeftButton, M.__mouseDown.RightButton = false, true
  overlay:__fire("OnUpdate")
  M.__mouseDown.RightButton, M.__mouseFoci[1] = false, nil
  assertNil(picked, "a left press picks nothing")
  assertFalse(canceled, "a right press cancels nothing")
  assertTrue(FP.IsActive(), "the pick is still running")
  FP.Stop()
end)

test("picker: refused in combat with one gray line, and combat during a pick cancels it", function()
  local realCombat = M.InCombatLockdown
  M.InCombatLockdown = function() return true end
  M.__resetPrinted()
  local started = FP.Start(function() end)
  local printed = #M.__printed()
  M.InCombatLockdown = realCombat
  assertFalse(started, "refused")
  assertFalse(FP.IsActive())
  assertEqual(printed, 1, "one line")
  local canceled = false
  assertTrue(FP.Start(function() end, function() canceled = true end))
  NS.addon:OnCombatChanged("PLAYER_REGEN_DISABLED")
  NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")
  assertFalse(FP.IsActive(), "the combat edge ended it")
  assertTrue(canceled, "as a cancel")
  assertNil(FP.__overlay():GetScript("OnUpdate"))
end)

test("picker: Escape cancels", function()
  local canceled, picked = false, nil
  FP.Start(function(n) picked = n end, function() canceled = true end)
  local overlay = FP.__overlay()
  overlay:__fire("OnUpdate")
  overlay:__fire("OnKeyDown", "ESCAPE")
  assertTrue(canceled)
  assertNil(picked)
  assertFalse(FP.IsActive())
end)

test("frame picker: test_picker_label_skin — the label draws in the skin's accent and the skin's body face", function()
  -- red under: the label's GameFontNormalLarge face, which no skin reached (SD-SK-RM.9).
  local restore = dofile("tests/_kit/mock_paint.lua")(M)
  -- The harness loads no LibSharedMedia, so the skin's face resolves to nothing: a fake answers it,
  -- with this addon's own (caching) NS.GetLSM held off it meanwhile.
  local savedGetLSM = NS.GetLSM
  NS.GetLSM = function() return nil end
  M.__libs["LibSharedMedia-3.0"] = { Fetch = function(_, kind, key)
    if kind == "font" then return "Interface\\AddOns\\RangeMasterTest\\font\\" .. tostring(key) end
  end }
  FP.__drop()
  local ok, err = pcall(function()
    assertTrue(FP.Start(function() end, function() end))
    local label
    for _, r in ipairs({ FP.__overlay():GetRegions() }) do
      if r:GetObjectType() == "FontString" then label = r end
    end
    assertTrue(label ~= nil, "the overlay's label")
    local got = M.__paint(label)
    local ar, ag, ab = NS.Skin.Color("text.accent")
    assertTrue(math.abs(got.textColor[1] - ar) < 1e-6 and math.abs(got.textColor[2] - ag) < 1e-6
      and math.abs(got.textColor[3] - ab) < 1e-6, "in the skin's accent")
    local face = got.fontObject and got.fontObject:GetFont() or (got.font and got.font[1])
    local body = NS.Skin.Token("font.body")
    assertEqual(face, "Interface\\AddOns\\RangeMasterTest\\font\\" .. tostring(body), "in the skin's body face")
    FP.Cancel("escape")
  end)
  FP.__drop()
  M.__libs["LibSharedMedia-3.0"] = nil
  NS.GetLSM = savedGetLSM
  restore()
  if not ok then error(err, 0) end
end)
