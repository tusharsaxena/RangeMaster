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


-- ---------------------------------------------------------------------------
-- Frame strata on a plate, and the cast bar (plan 2026-11-20, plate cast bar)
-- ---------------------------------------------------------------------------

--- Run `body` with the kit's frame-layer recorder installed, so every frame built in it answers its
--- strata and level back.
local function withLayers(body)
  local restore = dofile("tests/_kit/mock_layers.lua")(M)
  local ok, err = pcall(H.with, body)
  restore()
  if not ok then error(err, 0) end
end

--- `inst`'s root strata, and whether any of its layers or element frames carries a strata of its own.
local function strataOf(inst)
  local kept = false
  local frames = { inst.fill, inst.border.frame, inst.overlay }
  for _, el in pairs(inst.elements) do frames[#frames + 1] = el.frame end
  for _, f in ipairs(frames) do
    if rawget(f, "__strata") ~= nil then kept = true end
  end
  return M.__layers(inst.frame).strata, kept
end

test("plates: test_strata_reaches_every_plate_instance — a Frame strata write re-seats the per-plate and own-plate roots, and no child keeps one", function()
  -- The owner's report (2026-11-20): BACKGROUND still drew over EllesmereUI's cast bar. Pins that the
  -- write reaches both nameplate modes and that nothing under a root holds a strata of its own.
  withLayers(function()
    local a = H.plate("nameplate1", true)
    H.plate("nameplate2", true)
    M.__plates.target = a
    H.added("nameplate1")
    H.added("nameplate2")
    local each = allPlates()
    local ownId, ownInst = own("target")
    NS.CM.SetField(each, "anchor.strata", "BACKGROUND")
    NS.CM.SetField(ownId, "anchor.strata", "BACKGROUND")
    NS.CM.FlushPending()
    local insts = platesOf(each)
    assertEqual(count(insts), 2)
    insts.own = ownInst
    for name, inst in pairs(insts) do
      local strata, childOwn = strataOf(inst)
      assertEqual(strata, "BACKGROUND", name .. ": the root takes the write")
      assertFalse(childOwn, name .. ": no layer or element frame keeps a strata of its own")
    end
    -- A plate arriving after the write is built in the stored strata too.
    H.plate("nameplate3", true)
    H.added("nameplate3")
    assertEqual((strataOf(platesOf(each).nameplate3)), "BACKGROUND", "a new plate's instance")
  end)
end)

test("plates: test_strata_write_relays_the_levels — the ladder is laid again after the client resets it on a strata write", function()
  -- red under: applyFrame writing the strata and leaving the levels (the client resets a frame's
  -- level and its children's on a strata write): the fill, border and overlay collapse together.
  withLayers(function()
    H.plate("nameplate1", true)
    H.added("nameplate1")
    local id = allPlates()
    local inst = platesOf(id).nameplate1
    local LV = NS.Constants.LAYERS.LEVEL
    local root = inst.frame
    local frames = { root, inst.fill, inst.border.frame, inst.overlay }
    for _, el in pairs(inst.elements) do frames[#frames + 1] = el.frame end
    local realSet = root.SetFrameStrata
    rawset(root, "SetFrameStrata", function(self, s)
      realSet(self, s)
      for _, f in ipairs(frames) do rawset(f, "__level", nil) end   -- what the client does
    end)
    NS.CM.SetField(id, "anchor.strata", "LOW")
    NS.CM.FlushPending()
    rawset(root, "SetFrameStrata", realSet)
    local base = M.__layers(root).level
    assertEqual(base, M.__layers(M.UIParent).level + inst.slotLevel, "the root back on its own slot")
    assertEqual(M.__layers(inst.fill).level, base + LV.FILL, "fill")
    assertEqual(M.__layers(inst.border.frame).level, base + LV.BORDER, "border")
    assertEqual(M.__layers(inst.overlay).level, base + LV.OVERLAY, "overlay")
    for name, el in pairs(inst.elements) do
      assertEqual(M.__layers(el.frame).level, base + LV.OVERLAY + LV.ELEMENT, name .. " over the overlay")
    end
  end)
end)

test("plates: test_frame_level_orders_within_the_strata — a Frame level puts the root at a fixed place, 1 under every Auto one", function()
  withLayers(function()
    H.plate("nameplate1", true)
    H.added("nameplate1")
    local auto = allPlates()
    local low = allPlates()
    NS.CM.SetField(low, "anchor.level", 1)
    NS.CM.FlushPending()
    local LV = NS.Constants.LAYERS.LEVEL
    local ui = M.__layers(M.UIParent).level
    local autoInst, lowInst = platesOf(auto).nameplate1, platesOf(low).nameplate1
    assertEqual(M.__layers(lowInst.frame).level, ui + LV.FLOOR, "1 is the floor")
    assertTrue(M.__layers(lowInst.frame).level + LV.HANDLE < M.__layers(autoInst.frame).level,
      "a level-1 container's whole band sits under an Auto one")
    assertEqual(M.__layers(lowInst.overlay).level, M.__layers(lowInst.frame).level + LV.OVERLAY, "its ladder follows")
    NS.CM.SetField(low, "anchor.level", LV.SLOTS)
    NS.CM.FlushPending()
    local top = M.__layers(lowInst.frame).level
    assertEqual(top, ui + LV.FLOOR + (LV.SLOTS - 1) * LV.STRIDE, "the highest place")
    assertTrue(top + LV.HANDLE < 10000, "under the client's ceiling")
    NS.CM.SetField(low, "anchor.level", 0)
    NS.CM.FlushPending()
    assertEqual(M.__layers(lowInst.frame).level, ui + lowInst.slotLevel, "0 goes back to its own slot")
    NS.CM.Get(low).anchor.level = 5000          -- hand-edited out of range: Auto
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    assertEqual(M.__layers(lowInst.frame).level, ui + lowInst.slotLevel, "out of range reads as Auto")
  end)
end)

--- The client's own cast bar on `plate` (`UnitFrame.<key>`, castBar by default).
local function blizzardCast(plate, key)
  local uf, bar = H.frame(nil), H.frame(nil)
  plate.UnitFrame = uf
  uf[key or "castBar"] = bar
  return bar
end

--- Run `body(map)` with EllesmereUINameplates' global plate map planted (empty), then removed.
local function withEllesmere(body)
  local old = rawget(_G, "EllesmereNameplates_NS")
  local map = {}
  rawset(_G, "EllesmereNameplates_NS", { plates = map })
  local ok, err = pcall(body, map)
  rawset(_G, "EllesmereNameplates_NS", old)
  if not ok then error(err, 0) end
end

--- EllesmereUI's plate for `token` sitting on `plate`, with its cast bar.
local function ellesmerePlate(map, token, plate)
  local bar = H.frame(nil)
  map[token] = { nameplate = plate, cast = bar }
  return bar
end

local function castOpts(unit)
  local opts = { nameplate = { attachTo = "castbar" } }
  if not NS.CM.IsPlates(unit) then opts.anchor = { mode = "nameplate" } end
  return opts
end

test("plates: test_castbar_provider — EllesmereUI's cast bar first, then the client's castBar or CastBar, else nil", function()
  H.with(function()
    local P = NS.FrameProviders
    local p = H.plate("nameplate1", true)
    assertNil(P.PlateCastBar(p), "no cast bar anywhere")
    assertNil(P.PlateCastBar(nil), "no plate")
    local blizz = blizzardCast(p)
    assertTrue(P.PlateCastBar(p) == blizz, "the client's own UnitFrame.castBar")
    local q = H.plate("nameplate2", true)
    local upper = blizzardCast(q, "CastBar")
    assertTrue(P.PlateCastBar(q) == upper, "UnitFrame.CastBar on a client that names it so")
    withEllesmere(function(map)
      local eui = ellesmerePlate(map, "nameplate1", p)
      assertTrue(P.PlateCastBar(p) == eui, "EllesmereUI's plate for the token wins")
      assertTrue(P.PlateCastBar(p, "nameplate1") == eui, "the token handed in")
      map.nameplate1, map.other = nil, { nameplate = p, cast = eui }
      assertTrue(P.PlateCastBar(p, "nameplate1") == eui,
        "no entry under the token: the entry hosted on this plate (the owner's Forever probe)")
      map.other, map.nameplate1 = nil, { nameplate = q, cast = eui }
      assertTrue(P.PlateCastBar(p) == blizz, "a stale map entry, on another plate, is not used")
      map.nameplate1 = { nameplate = p, cast = H.frame(nil, true) }
      assertTrue(P.PlateCastBar(p) == blizz, "a forbidden cast bar is never answered")
      map.nameplate1 = { nameplate = p, cast = "not a frame" }
      assertTrue(P.PlateCastBar(p) == blizz, "nor a value that is not a frame")
    end)
    p.UnitFrame.castBar = H.frame(nil, true)
    assertNil(P.PlateCastBar(p), "the client's forbidden cast bar: nil")
    local raising = setmetatable({}, { __index = function() error("restricted") end })
    assertNil(P.PlateCastBar(raising), "a plate whose reads raise: nil, nothing escapes")
  end)
end)

test("plates: test_castbar_attach_own_plate — a target container set to Cast bar sits on its plate's cast bar", function()
  H.with(function()
    local a = H.plate("nameplate1", true)
    local bar = blizzardCast(a)
    M.__plates.target = a
    H.added("nameplate1")
    local _, inst = own("target", castOpts("target"))
    assertTrue(inst.anchorPlate == a, "anchorPlate is still the plate (removal compares it)")
    assertTrue(inst.anchorPart == bar, "pinned to the cast bar")
    assertTrue(inst.frame:IsShown())
    local calls = H.points(inst.frame, function()
      NS.CM.Get(inst.id).nameplate.attachTo = "plate"
      NS.CM.RequestApply()
      NS.CM.FlushPending()
    end)
    assertTrue(calls[#calls][2] == a, "Nameplate puts it back on the plate")
    assertTrue(inst.anchorPart == a)
    H.removed("nameplate1")
    assertNil(inst.anchorPlate, "the plate going still hides it")
    assertFalse(inst.frame:IsShown())
  end)
end)

test("plates: test_castbar_attach_every_plate — each per-plate instance sits on its own plate's cast bar, EllesmereUI's where it has one", function()
  H.with(function()
    withEllesmere(function(map)
      local p1, p2 = H.plate("nameplate1", true), H.plate("nameplate2", true)
      local eui = ellesmerePlate(map, "nameplate1", p1)
      local blizz = blizzardCast(p2)
      H.added("nameplate1")
      H.added("nameplate2")
      for _, unit in ipairs({ "nameplates", "nameplatesExceptTarget" }) do
        local id = H.container(unit, castOpts(unit))
        local by = platesOf(id)
        assertTrue(by.nameplate1.anchorPart == eui, unit .. ": EllesmereUI's cast bar")
        assertTrue(by.nameplate2.anchorPart == blizz, unit .. ": the client's own on the other plate")
        assertTrue(by.nameplate1.anchorPlate == p1 and by.nameplate2.anchorPlate == p2, unit .. ": each on its plate")
        NS.CM.Delete(id)
        NS.CM.FlushPending()
      end
    end)
  end)
end)

test("plates: test_castbar_falls_back_to_the_plate — no cast bar, or one refusing the anchor, leaves it on the plate", function()
  H.with(function()
    local p = H.plate("nameplate1", true)
    H.added("nameplate1")
    local id = H.container("nameplates", castOpts("nameplates"))
    local inst = platesOf(id).nameplate1
    assertTrue(inst.anchorPart == p, "no cast bar: on the plate")
    assertTrue(inst.frame:IsShown(), "and shown")
    local bar = blizzardCast(p)
    local realSet = inst.frame.SetPoint
    rawset(inst.frame, "SetPoint", function(self, point, rel, ...)
      if rel == bar then error("refused") end
      return realSet(self, point, rel, ...)
    end)
    NS.CM.RequestApply()
    NS.CM.FlushPending()
    rawset(inst.frame, "SetPoint", nil)
    inst = platesOf(id).nameplate1
    assertTrue(inst.anchorPlate == p and inst.anchorPart == p, "the refusal falls back to the plate")
    assertTrue(inst.frame:IsShown(), "still shown")
  end)
end)

test("plates: test_castbar_found_a_frame_later — EllesmereUI building its plate after ADDED moves the container onto its cast bar on the re-check", function()
  H.with(function()
    withEllesmere(function(map)
      local p = H.plate("nameplate1", true)
      local id = H.container("nameplates", castOpts("nameplates"))
      local a = H.plate("nameplate2", true)
      M.__plates.target = a
      local _, mine = own("target", castOpts("target"))
      H.added("nameplate1")
      H.added("nameplate2")
      assertTrue(platesOf(id).nameplate1.anchorPart == p, "this addon heard ADDED first: on the plate")
      assertTrue(mine.anchorPart == a)
      local eui = ellesmerePlate(map, "nameplate1", p)
      local euiTarget = ellesmerePlate(map, "nameplate2", a)
      M.__fireTimers()
      assertTrue(platesOf(id).nameplate1.anchorPart == eui, "the re-check finds EllesmereUI's cast bar")
      assertTrue(mine.anchorPart == euiTarget, "and the own-plate container's")
    end)
  end)
end)

--- The cast bar as the client drives it: shown (or hidden), then its OnShow (OnHide) script, the
--- order EllesmereUI's Show and Hide call them in.
local function showBar(bar) bar:Show(); bar:__fire("OnShow") end
local function hideBar(bar) bar:Hide(); bar:__fire("OnHide") end

local function partOpts(unit, part)
  local opts = { nameplate = { attachTo = part } }
  if not NS.CM.IsPlates(unit) then opts.anchor = { mode = "nameplate" } end
  return opts
end

test("plates: test_attach_part_three_choices — Nameplate, Cast bar, and Cast bar while casting (the plate between casts)", function()
  H.with(function()
    local p = H.plate("nameplate1", true)
    local bar = blizzardCast(p)
    bar:Hide()
    H.added("nameplate1")
    local plateId = H.container("nameplates", partOpts("nameplates", "plate"))
    local barId = H.container("nameplates", partOpts("nameplates", "castbar"))
    local whenId = H.container("nameplates", partOpts("nameplates", "castbarWhenCasting"))
    assertTrue(platesOf(plateId).nameplate1.anchorPart == p, "Nameplate: on the plate")
    assertTrue(platesOf(barId).nameplate1.anchorPart == bar, "Cast bar: on the bar, casting or not")
    assertTrue(platesOf(whenId).nameplate1.anchorPart == p, "while casting: on the plate between casts")
    local values = NS.ContainerValues.PLATE_PARTS
    assertEqual(table.concat(NS.ContainerValues.PLATE_PARTS_SORT, ","), "plate,castbar,castbarWhenCasting")
    assertEqual(values.castbarWhenCasting, NS.L["Cast bar while casting, else nameplate"])
  end)
end)

test("plates: test_cast_event_before_the_bar — the owner's order: the event first, the bar shown or hidden after", function()
  -- red under: a switch decided at the event (the owner, 2026-11-20, EllesmereUI with Casts In Front
  -- of Nameplates: hidden under the lifted bar during the cast, left on the bar's spot after it).
  H.with(function()
    local p, a = H.plate("nameplate1", true), H.plate("nameplate2", true)
    local bar, abar = blizzardCast(p), blizzardCast(a)
    bar:Hide()
    abar:Hide()
    M.__plates.target = a
    H.added("nameplate1")
    H.added("nameplate2")
    local id = H.container("nameplates", partOpts("nameplates", "castbarWhenCasting"))
    local _, mine = own("target", partOpts("target", "castbarWhenCasting"))
    local each = platesOf(id).nameplate1
    assertTrue(each.anchorPart == p and mine.anchorPart == a, "between casts: on the plates")
    M.__fireEvent("UNIT_SPELLCAST_START", "nameplate1")
    assertTrue(each.anchorPart == p, "the event before the bar shows: still the plate")
    showBar(bar)
    assertTrue(each.anchorPart == bar, "the bar shows: onto it")
    assertTrue(mine.anchorPart == a, "another plate's bar moves nothing else")
    M.__fireEvent("UNIT_SPELLCAST_STOP", "nameplate1")
    assertTrue(each.anchorPart == bar, "the stop before the bar hides: still on it")
    hideBar(bar)
    assertTrue(each.anchorPart == p, "the bar hides: back on the plate")
    assertTrue(each.frame:IsShown(), "shown throughout")
    showBar(abar)
    assertTrue(mine.anchorPart == abar, "the target's own plate: the own-plate container moves too")
    hideBar(abar)
    assertTrue(mine.anchorPart == a, "and back")
  end)
end)

test("plates: test_cast_bar_already_shown — a plate placed mid-cast starts on its shown bar; an event re-reads it", function()
  H.with(function()
    local p = H.plate("nameplate1", true)
    local bar = blizzardCast(p)
    H.added("nameplate1")
    local id = H.container("nameplates", partOpts("nameplates", "castbarWhenCasting"))
    local inst = platesOf(id).nameplate1
    assertTrue(inst.anchorPart == bar, "the bar shown: already casting")
    bar:Hide()
    M.__fireEvent("UNIT_SPELLCAST_INTERRUPTED", "nameplate1")
    assertTrue(inst.anchorPart == p, "an event after the bar hid (no hook heard): the plate")
    M.__fireEvent("UNIT_SPELLCAST_START", "player")
    M.__fireEvent("UNIT_SPELLCAST_START", "nameplate9")
    assertTrue(inst.anchorPart == p, "an untracked token moves nothing")
  end)
end)

test("plates: test_cast_with_no_cast_bar — while casting, a plate with no cast bar keeps the container on the plate", function()
  H.with(function()
    local p = H.plate("nameplate1", true)
    H.added("nameplate1")
    local id = H.container("nameplates", partOpts("nameplates", "castbarWhenCasting"))
    local barId = H.container("nameplates", partOpts("nameplates", "castbar"))
    M.__fireEvent("UNIT_SPELLCAST_START", "nameplate1")
    assertTrue(platesOf(id).nameplate1.anchorPart == p, "while casting: still the plate")
    assertTrue(platesOf(barId).nameplate1.anchorPart == p, "Cast bar: the plate too")
    assertTrue(platesOf(id).nameplate1.frame:IsShown(), "and shown")
  end)
end)

test("plates: test_cast_events_registered_ifvalid — every cast event is in the lifecycle list, ifValid, on one handler", function()
  local want = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP" }
  local byName = {}
  for _, pair in ipairs(NS.__lifecycleEvents) do byName[pair[1]] = pair end
  for _, name in ipairs(want) do
    local pair = byName[name]
    assertTrue(pair ~= nil, name .. " is registered")
    assertTrue(pair.ifValid == true, name .. " is ifValid")
    assertEqual(pair[2], "OnPlateCast", name .. "'s handler")
  end
end)
