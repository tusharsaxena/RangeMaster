-- tests/test_anchors_nameplate.lua — the nameplate anchors (modules/Anchors_Nameplate.lua): the
-- plate registry NS.Plates, a container on its unit's own plate (found by comparing plate frames,
-- never through UnitIsUnit), and the `nameplates` unit, one instance per eligible plate (hostile
-- unless the container includes friendly ones). A plate is re-checked one frame after
-- NAME_PLATE_UNIT_ADDED (WoW Forever populates it late), a forbidden plate is never touched, and a
-- removed plate's instances go back to the pool at once. The v0.1.0 plan, Task 6; design spec 5.4.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local H = dofile("tests/anchors_env.lua")
local Container = NS.Container

local function own(unit, extra)
  local opts = { anchor = { mode = "nameplate" } }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return H.container(unit, opts)
end

local function allPlates(includeFriendly)
  return H.container("nameplates", { nameplate = { includeFriendly = includeFriendly and true or false } })
end

local function platesOf(id)
  local out = {}
  Container.ForEachPlate(function(inst, cid, token)
    if cid == id then out[token] = inst end
  end)
  return out
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- ---------------------------------------------------------------------------
-- A container on its own unit's plate
-- ---------------------------------------------------------------------------

test("plates: test_nameplate_own_plate_follows_target_change — the target container moves to the new target's plate", function()
  H.with(function()
    local a, b = H.plate("nameplate1", true), H.plate("nameplate2", true)
    M.__plates.target = a
    H.added("nameplate1")
    H.added("nameplate2")
    local _, inst = own("target")
    assertEqual(inst.anchorMode, "nameplate")
    assertTrue(inst.anchorPlate == a, "on the target's plate")
    assertTrue(inst.frame:IsShown())
    M.__plates.target = b
    local calls = H.points(inst.frame, function() M.__fireEvent("PLAYER_TARGET_CHANGED") end)
    assertTrue(inst.anchorPlate == b, "followed the retarget")
    assertTrue(calls[#calls][2] == b, "SetPoint relative to the new plate")
    assertEqual(calls[#calls][1] .. " " .. calls[#calls][3], "TOP BOTTOM", "the container's nameplate point")
  end)
end)

test("plates: test_expert_plates_out_of_combat — Expert's plate containers show out of combat", function()
  -- red under: Expert's plate containers stored with visibility.combat = "in" (the owner, out of
  -- combat, saw neither; plan 2026-11-19 M12).
  H.with(function()
    local a = H.plate("nameplate1", true)
    H.plate("nameplate2", true)
    M.__plates.target = a
    H.added("nameplate1")
    H.added("nameplate2")
    NS.Presets.Apply("expert")
    NS.CM.FlushPending()
    local plateInst, eachInst
    for _, id in ipairs(NS.CM.List()) do
      local c = NS.CM.Get(id)
      if c.unit == "target" and c.anchor.mode == "nameplate" then plateInst = Container.Get(id) end
      if NS.CM.IsPlates(c.unit) then
        eachInst = platesOf(id).nameplate2
        assertNil(platesOf(id).nameplate1, "Expert's every-plate container leaves the target's plate to the target one")
      end
    end
    assertTrue(plateInst ~= nil and plateInst.anchorPlate == a, "the target plate container sits on its plate")
    assertFalse(NS.Visibility.InCombat(), "out of combat")
    assertTrue(plateInst.frame:IsShown(), "and shows")
    assertTrue(eachInst ~= nil and eachInst.frame:IsShown(), "the hostile plate's instance shows too")
    NS.Presets.__reset()
  end)
end)

test("plates: a target with no plate hides the container, and its plate coming into view shows it", function()
  H.with(function()
    local _, inst = own("target")
    assertFalse(inst.frame:IsShown(), "no plate: hidden")
    local a = H.plate("nameplate4", true)
    M.__plates.target = a
    H.added("nameplate4")
    assertTrue(inst.anchorPlate == a, "found when the plate came")
    assertTrue(inst.frame:IsShown())
  end)
end)

test("plates: a removed plate is told apart by its frame — another plate going leaves the target where it is", function()
  H.with(function()
    local a = H.plate("nameplate1", true)
    H.plate("nameplate2", true)
    M.__plates.target = a
    H.added("nameplate1")
    H.added("nameplate2")
    local _, inst = own("target")
    H.removed("nameplate2")
    assertTrue(inst.anchorPlate == a, "untouched")
    assertTrue(inst.frame:IsShown())
    -- While REMOVED dispatches, the client still answers the dying plate for "target": the frame
    -- comparison is what hides it now, rather than a lookup that would put it straight back.
    H.removed("nameplate1")
    assertNil(inst.anchorPlate, "the target's own plate went")
    assertFalse(inst.frame:IsShown(), "hidden at once")
    M.__plates.target = nil
    M.__fireTimers()
    assertFalse(inst.frame:IsShown(), "and the next frame's re-check finds none")
  end)
end)

test("plates: a pet container on its own nameplate is hidden (a pet has no plate in practice)", function()
  H.with(function()
    M.__unitExists.pet = true
    local _, inst = own("pet")
    assertFalse(inst.frame:IsShown())
  end)
end)

-- ---------------------------------------------------------------------------
-- The nameplates unit: one instance per plate
-- ---------------------------------------------------------------------------

test("plates: test_nameplates_instance_per_hostile_plate — one instance per hostile plate, each on it", function()
  H.with(function()
    local p1, p3 = H.plate("nameplate1", true), H.plate("nameplate3", true)
    H.plate("nameplate2", false)
    local id = allPlates()
    for _, t in ipairs({ "nameplate1", "nameplate2", "nameplate3" }) do H.added(t) end
    local by = platesOf(id)
    assertEqual(count(by), 2, "the friendly plate has none")
    assertTrue(by.nameplate1.anchorPlate == p1 and by.nameplate3.anchorPlate == p3, "each on its own plate")
    assertEqual(by.nameplate1.unit, "nameplate1", "each watches its own token")
    assertTrue(NS.Ticker.IsWatched("nameplate3"))
    assertFalse(NS.Ticker.IsWatched("nameplate2"))
    assertEqual(by.nameplate1.elements.number.text, "20\226\128\14725", "and renders its range")
    assertNil(Container.Get(id), "the container itself has no single instance")
  end)
end)

test("plates: plates already shown when a nameplates container is created get instances on its apply", function()
  H.with(function()
    H.plate("nameplate1", true)
    H.plate("nameplate2", true)
    H.added("nameplate1")
    H.added("nameplate2")
    local id = allPlates()
    assertEqual(count(platesOf(id)), 2)
  end)
end)

test("plates: test_nameplates_friendly_toggle — includeFriendly gives friendly plates an instance too", function()
  H.with(function()
    H.plate("nameplate1", true)
    H.plate("nameplate2", false)
    H.added("nameplate1")
    H.added("nameplate2")
    local id = allPlates()
    assertEqual(count(platesOf(id)), 1, "hostile only by default")
    NS.CM.Get(id).nameplate.includeFriendly = true
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    assertEqual(count(platesOf(id)), 2, "the friendly plate joins")
    NS.CM.Get(id).nameplate.includeFriendly = false
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    assertEqual(count(platesOf(id)), 1, "and leaves again")
    assertFalse(NS.Ticker.IsWatched("nameplate2"))
  end)
end)

test("plates: a reaction change (UNIT_FACTION) moves a plate in or out", function()
  H.with(function()
    H.plate("nameplate1", false)
    H.added("nameplate1")
    local id = allPlates()
    assertEqual(count(platesOf(id)), 0)
    M.__hostile.nameplate1 = true
    M.__fireEvent("UNIT_FACTION", "nameplate1")
    assertEqual(count(platesOf(id)), 1, "turned hostile")
  end)
end)

test("plates: test_nameplate_recycle — REMOVED releases the plate's instance, and the stale token errs nowhere", function()
  H.with(function()
    H.plate("nameplate1", true)
    H.added("nameplate1")
    local id = allPlates()
    local inst = platesOf(id).nameplate1
    local frame = inst.frame
    H.removed("nameplate1")
    assertEqual(count(platesOf(id)), 0, "released")
    assertFalse(frame:IsShown(), "hidden")
    assertFalse(NS.Ticker.IsWatched("nameplate1"), "its watch went")
    local free = Container.__plateCounts()
    assertEqual(free, 1, "parked for the next plate")
    -- The stale token, everywhere it can still arrive: a pending re-check, a tick, an update.
    M.__fireTimers()
    NS.Ticker.Refresh()
    NS.bus:SendMessage(NS.MSG.RANGE_UPDATED, "nameplate1", "known", 1, 2)
    assertNil(NS.Plates.Get("nameplate1"))
    -- The token handed to a new plate reuses the parked frame.
    local p = H.plate("nameplate1", true)
    H.added("nameplate1")
    local again = platesOf(id).nameplate1
    assertTrue(again.frame == frame, "the same pooled frame")
    assertTrue(again.anchorPlate == p)
  end)
end)

test("plates: a plate not populated at ADDED is picked up by the next frame's re-check", function()
  H.with(function()
    local id = allPlates()
    M.__unitExists.nameplate5, M.__hostile.nameplate5 = true, true
    H.added("nameplate5")                -- the client has no frame for it yet (WoW Forever)
    assertEqual(count(platesOf(id)), 0)
    local p = H.plate("nameplate5", true)
    M.__fireTimers()
    local inst = platesOf(id).nameplate5
    assertTrue(inst ~= nil and inst.anchorPlate == p, "found a frame later")
  end)
end)

test("plates: test_forbidden_plate_skipped — a forbidden plate gets no instance and no anchor", function()
  H.with(function()
    local bad = H.plate("nameplate1", true, true)
    M.__plates.target = bad
    H.added("nameplate1")
    local id = allPlates()
    local _, inst = own("target")
    assertEqual(count(platesOf(id)), 0, "skipped")
    assertNil(NS.Plates.Get("nameplate1"))
    assertNil(inst.anchorPlate, "the target container does not touch it")
    assertFalse(inst.frame:IsShown())
  end)
end)

test("plates: ForEachHostile walks the hostile plates, and every plate with includeFriendly", function()
  H.with(function()
    H.plate("nameplate1", true)
    H.plate("nameplate2", false)
    H.added("nameplate1")
    H.added("nameplate2")
    local seen = {}
    NS.Plates.ForEachHostile(function(token, plate)
      seen[#seen + 1] = token
      assertTrue(plate == M.__plates[token])
    end)
    assertEqual(table.concat(seen, ","), "nameplate1")
    local all = 0
    NS.Plates.ForEachHostile(function() all = all + 1 end, true)
    assertEqual(all, 2)
  end)
end)

test("plates: deleting the nameplates container releases every plate instance", function()
  H.with(function()
    H.plate("nameplate1", true)
    H.added("nameplate1")
    local id = allPlates()
    NS.CM.Delete(id)
    NS.CM.FlushPending()
    assertEqual(count(platesOf(id)), 0)
    assertFalse(NS.Ticker.IsWatched("nameplate1"))
  end)
end)

test("plates: the stand-down releases every plate instance and leaves no re-check armed; the stand-up rescans", function()
  H.with(function()
    H.plate("nameplate1", true)
    H.added("nameplate1")
    local id = allPlates()
    NS.SetByPath("enabled", false)
    NS.SyncEnabledHold()
    assertEqual(count(platesOf(id)), 0, "released")
    for _, t in ipairs(M.__timers()) do
      assertFalse(t.isPlateRecheck == true, "a plate re-check survived the stand-down")
    end
    NS.SetByPath("enabled", true)
    NS.SyncEnabledHold()
    NS.CM.FlushPending()
    assertEqual(count(platesOf(id)), 1, "the plate still shown is found again")
  end)
end)

-- ---------------------------------------------------------------------------
-- All nameplates except the target's (the owner, 2026-11-19: a target-plate container and an every-
-- plate one overlapped on the target's plate)
-- ---------------------------------------------------------------------------

local function allButTarget()
  return H.container("nameplatesExceptTarget", { nameplate = { includeFriendly = false } })
end

test("plates: test_except_target_skips_the_target_plate — no instance on the target's plate, one on every other", function()
  -- red under: no nameplatesExceptTarget unit (CM.Create answers nil).
  H.with(function()
    local a, b = H.plate("nameplate1", true), H.plate("nameplate2", true)
    M.__plates.target = a
    H.added("nameplate1")
    H.added("nameplate2")
    local id = allButTarget()
    assertTrue(id ~= nil, "the unit exists")
    local by = platesOf(id)
    assertNil(by.nameplate1, "none on the target's plate")
    assertTrue(by.nameplate2 ~= nil and by.nameplate2.anchorPlate == b, "one on the other plate")
  end)
end)

test("plates: test_except_target_follows_retarget — a retarget moves the gap to the new target's plate", function()
  H.with(function()
    local a, b = H.plate("nameplate1", true), H.plate("nameplate2", true)
    M.__plates.target = a
    H.added("nameplate1")
    H.added("nameplate2")
    local id = allButTarget()
    M.__plates.target = b
    M.__fireEvent("PLAYER_TARGET_CHANGED")
    local by = platesOf(id)
    assertTrue(by.nameplate1 ~= nil and by.nameplate1.anchorPlate == a, "the old target's plate gets one back")
    assertNil(by.nameplate2, "the new target's plate loses its")
    M.__plates.target = nil
    M.__fireEvent("PLAYER_TARGET_CHANGED")
    assertEqual(count(platesOf(id)), 2, "no target: every hostile plate")
  end)
end)

test("plates: test_except_target_plate_arriving — the target's plate coming into view gets no instance", function()
  H.with(function()
    local id = allButTarget()
    local a = H.plate("nameplate3", true)
    M.__plates.target = a
    H.added("nameplate3")
    M.__fireTimers()
    assertNil(platesOf(id).nameplate3, "the target's plate, though it arrived after the container")
  end)
end)

test("plates: test_all_nameplates_keeps_the_target_plate — plain All nameplates still draws on the target's plate", function()
  H.with(function()
    local a = H.plate("nameplate1", true)
    M.__plates.target = a
    H.added("nameplate1")
    local id = allPlates()
    assertTrue(platesOf(id).nameplate1 ~= nil)
  end)
end)

test("plates: test_except_target_is_a_plates_unit — no sound, no single instance, the plate rows", function()
  H.with(function()
    local id = allButTarget()
    assertTrue(NS.CM.IsPlates("nameplatesExceptTarget") and NS.CM.IsPlates("nameplates"))
    assertFalse(NS.CM.IsPlates("target"))
    assertNil(Container.Get(id), "locked: per-plate instances only")
    assertEqual(NS.ContainerValues.UNITS.nameplatesExceptTarget, "All nameplates except target")
    local sorted = table.concat(NS.ContainerValues.UNITS_SORT, ",")
    assertEqual(sorted, "target,focus,pet,mouseover,nameplates,nameplatesExceptTarget")
  end)
end)
