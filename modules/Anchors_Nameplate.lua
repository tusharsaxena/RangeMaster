local _, NS = ...
-- modules/Anchors_Nameplate.lua — the nameplate anchors (design spec 5.4) and the plate registry.
--
--   NS.Plates.Get(unit) -> plate|nil         the plate behind a token (a tracked plate token, else
--                                            the client's answer for "target", "focus", ...)
--   NS.Plates.ForEachHostile(fn(token, plate), includeFriendly?)   every tracked hostile plate (every
--                                            tracked plate with includeFriendly)
--   NS.Plates.Added(token), Removed(token)   NAME_PLATE_UNIT_ADDED / _REMOVED (core/RangeMaster.lua)
--   NS.Plates.SyncAll()                      every `nameplates` container's per-plate instances, from
--                                            the renderer's Sync (modules/Container.lua)
--   NS.Plates.StandDown(), StandUp()         the latch's edges (core/LifecycleSetup.lua)
--
-- TWO MODES register here. `nameplate`: a target, focus or mouseover container on its unit's own
-- plate, at its `nameplate` point and offsets (a pet has no plate in practice, so its container is
-- hidden). `plates`: a `nameplates` container's per-plate instance, one per tracked plate that is
-- hostile (UnitCanAttack, NS.Compat.CanAttack) or, with `nameplate.includeFriendly`, any plate. A
-- `nameplatesExceptTarget` container is a `nameplates` one that skips the target's plate (found by
-- its frame, below), so it never overlaps a container on the target's own plate; a retarget asks
-- every plate's eligibility again.
--
-- A PLATE IS IDENTIFIED BY ITS FRAME, never through UnitIsUnit (which may answer a secret). An
-- own-plate instance remembers the plate frame it sits on; when NAME_PLATE_UNIT_REMOVED names a
-- token, the plate behind that token is compared with it. While that event dispatches the client
-- still answers the dying plate for "target", so a fresh lookup would put the container straight
-- back on it: the frame comparison hides it now, and a re-check one frame later looks again.
--
-- ONE FRAME LATER, AGAIN. NAME_PLATE_UNIT_ADDED can fire before the client has populated the plate
-- (WoW Forever; RangeLens.lua's OnPlateAdded re-runs a frame later for the same reason, EllesmereUI's
-- plates included), so every ADDED is followed by a re-check of that token on the next frame: the
-- plate is read again, its instances placed on it and its eligibility asked again. The re-check runs
-- on both clients: it is cheap, and a client-specific branch would sit outside the Compat layer.
--
-- FORBIDDEN PLATES ARE NEVER TOUCHED. Every plate comes through NS.Compat.NamePlateForUnit or
-- NS.Compat.NamePlates, which answer nil for a forbidden one (a friendly plate in an instance), so a
-- forbidden plate gets no instance and no own-plate container sits on it.
--
-- PLATES COME AND GO IN COMBAT, and these frames are this addon's own, anchored to a nameplate (no
-- secure frame), so both modes place in combat; the renderer builds or parks a plate instance there
-- too. A stood-down addon tracks nothing and arms no re-check; the stand-up rescans the plates shown.

NS.Plates = NS.Plates or {}
local Plates = NS.Plates
local Anchors = NS.Anchors

local tokens = {}     -- [token] = plate frame: the tracked, not forbidden plates
local rechecks = {}   -- [token] = timer handle: the one-frame re-check after ADDED
local ownRecheck      -- the timer re-placing own-plate containers a frame after a REMOVED
local own = {}        -- [inst] = true: the own-plate instances
local plateInsts = {} -- [inst] = true: the per-plate instances

-- ---------------------------------------------------------------------------
-- Placing
-- ---------------------------------------------------------------------------

--- Off its plate: the root's points cleared while they still name one, so `inst.anchorPlate` stays
--- true to them, and its preview strips re-placed.
local function unpin(inst)
    if inst.anchorPlate == nil then return end
    inst.frame:ClearAllPoints()
    inst.anchorPlate = nil
    inst:RefreshStrips()
end

--- Anchor `inst` on `plate` at container `c`'s nameplate point, unless it already sits there.
--- Answers whether it sits on the plate.
local function attach(inst, c, plate)
    if inst.anchorPlate == plate then return true end
    local np, root = c.nameplate or {}, inst.frame
    root:ClearAllPoints()
    local ok = pcall(root.SetPoint, root, Anchors.Point(np.point, "TOP"), plate,
        Anchors.Point(np.relPoint, "BOTTOM"), Anchors.Offset(np.x), Anchors.Offset(np.y))
    if not ok then
        root:ClearAllPoints()
        inst.anchorPlate = nil
        inst:RefreshStrips()
        return false
    end
    inst.anchorPlate = plate
    inst:RefreshStrips()
    return true
end

--- On `plate`, shown; with no plate (or one refusing the anchor), hidden.
local function placeOn(inst, c, plate)
    if plate and attach(inst, c, plate) then return inst:SetAnchorHidden(false) end
    unpin(inst)
    inst:SetAnchorHidden(true)
end

local function placeOwn(inst)
    local c = inst.container
    if not c then return end
    placeOn(inst, c, Plates.Get(c.unit))
end

local function refreshOwn(unit)
    for inst in pairs(own) do
        if unit == nil or (inst.container and inst.container.unit == unit) then placeOwn(inst) end
    end
end

local Own = {}

function Own.Apply(inst, c)
    own[inst] = true
    unpin(inst)                 -- a re-apply re-places: the offsets may have changed
    placeOn(inst, c, Plates.Get(c.unit))
end

function Own.Detach(inst)
    own[inst] = nil
    unpin(inst)
end

function Own.UnitChanged(unit)
    refreshOwn(unit)
end

local Each = {}

function Each.Apply(inst, c)
    plateInsts[inst] = true
    unpin(inst)
    placeOn(inst, c, tokens[inst.plateToken])
end

function Each.Detach(inst)
    plateInsts[inst] = nil
    unpin(inst)
end

-- ---------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------

function Plates.Get(unit)
    if type(unit) ~= "string" then return nil end
    return tokens[unit] or NS.Compat.NamePlateForUnit(unit)
end

local function hostile(token)
    return NS.Compat.CanAttack(token) == true
end

function Plates.ForEachHostile(fn, includeFriendly)
    for token, plate in pairs(tokens) do
        if includeFriendly or hostile(token) then fn(token, plate) end
    end
end

local function isPlates(c)
    return c ~= nil and c.enabled and NS.CM.IsPlates(c.unit)
end

--- Whether the plate behind `token` is the target's: compared by frame, never through UnitIsUnit.
local function isTargetPlate(token)
    local plate = tokens[token]
    return plate ~= nil and plate == NS.Compat.NamePlateForUnit("target")
end

local function wants(c, token)
    if not tokens[token] then return false end
    if c.unit == "nameplatesExceptTarget" and isTargetPlate(token) then return false end
    if c.nameplate and c.nameplate.includeFriendly then return true end
    return hostile(token)
end

--- Container `id`'s instance on `token`: built when wanted and missing, placed when wanted and live
--- (`full` re-applies it from its settings), parked when not wanted.
local function syncOne(id, c, token, full)
    local Container = NS.Container
    if not wants(c, token) then return Container.ReleasePlate(id, token) end
    local inst = Container.GetPlate(id, token)
    if inst and not full then return placeOn(inst, c, tokens[token]) end
    Container.AcquirePlate(id, token)
end

local function syncToken(token, full)
    for _, id in ipairs(NS.CM.List()) do
        local c = NS.CM.Get(id)
        if isPlates(c) then syncOne(id, c, token, full) end
    end
end

--- Every token any `nameplates` container may have an instance on: the tracked ones and the ones an
--- instance still serves.
local seenTokens = {}
local function eachToken(fn)
    for token in pairs(tokens) do seenTokens[token] = true end
    for inst in pairs(plateInsts) do
        if inst.plateToken then seenTokens[inst.plateToken] = true end
    end
    for token in pairs(seenTokens) do
        seenTokens[token] = nil
        fn(token)
    end
end

function Plates.SyncAll()
    if NS.IsStoodDown() then return end
    eachToken(function(token) syncToken(token, true) end)
end

--- Read `token`'s plate again, then its instances and the own-plate containers.
local function refresh(token)
    tokens[token] = NS.Compat.NamePlateForUnit(token)
    syncToken(token, false)
    refreshOwn(nil)
end

local function cancelRecheck(token)
    local t = rechecks[token]
    if t then t:Cancel() end
    rechecks[token] = nil
end

local function scheduleRecheck(token)
    cancelRecheck(token)
    local t
    t = C_Timer.NewTimer(0, function()
        if rechecks[token] ~= t then return end
        rechecks[token] = nil
        refresh(token)
    end)
    t.isPlateRecheck = true
    rechecks[token] = t
end

function Plates.Added(token)
    if type(token) ~= "string" or NS.IsStoodDown() then return end
    refresh(token)
    scheduleRecheck(token)
end

--- Hide every own-plate instance sitting on `plate` now, and look again a frame later.
local function plateGone(plate)
    local any = false
    for inst in pairs(own) do
        if plate ~= nil and inst.anchorPlate == plate then
            unpin(inst)
            inst:SetAnchorHidden(true)
            any = true
        end
    end
    if not any or ownRecheck then return end
    ownRecheck = C_Timer.NewTimer(0, function()
        ownRecheck = nil
        refreshOwn(nil)
    end)
    ownRecheck.isPlateRecheck = true
end

function Plates.Removed(token)
    if type(token) ~= "string" then return end
    cancelRecheck(token)
    local plate = tokens[token] or NS.Compat.NamePlateForUnit(token)
    tokens[token] = nil
    for _, id in ipairs(NS.CM.List()) do NS.Container.ReleasePlate(id, token) end
    plateGone(plate)
end

--- A different unit behind `token` (a reaction change): its eligibility is asked again. A retarget
--- moves which plate a `nameplatesExceptTarget` container skips, so every plate is asked again.
local function tokenChanged(unit)
    if tokens[unit] then return syncToken(unit, false) end
    if unit == "target" and not NS.IsStoodDown() then eachToken(function(token) syncToken(token, false) end) end
end

function Plates.StandDown()
    for token in pairs(rechecks) do cancelRecheck(token) end
    if ownRecheck then ownRecheck:Cancel() end
    ownRecheck = nil
    for token in pairs(tokens) do tokens[token] = nil end
end

--- The stand-up: the plates shown now, which no ADDED will announce again. The registry's apply
--- (NS.CM.StandUp, next) gives them their instances.
function Plates.StandUp()
    for _, entry in ipairs(NS.Compat.NamePlates()) do tokens[entry.token] = entry.plate end
end

function Plates.__reset()
    Plates.StandDown()
    for inst in pairs(own) do own[inst] = nil end
    for inst in pairs(plateInsts) do plateInsts[inst] = nil end
end

Each.UnitChanged = tokenChanged

Anchors.Register("nameplate", Own)
Anchors.Register("plates", Each)
