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
-- ON THE PLATE, OR ON ITS CAST BAR. `nameplate.attachTo` picks what the container is pinned to, in
-- both modes, at the same `nameplate` point and offsets: "plate" (the default), "castbar" (always
-- the plate's cast bar) or "castbarWhenCasting" (the cast bar while the plate's unit casts or
-- channels, else the plate). The cast bar is NS.FrameProviders.PlateCastBar's (EllesmereUI's for
-- that token, else the client's own), and with none (or one refusing the anchor) the container stays
-- on the plate. `inst.anchorPlate` is
-- always the plate, so a removed plate is still told apart by its frame; `inst.anchorPart` is what
-- the root is pinned to. The part is asked again on every placing, the one-frame re-check after ADDED
-- included, so EllesmereUI building its plate after this addon heard ADDED moves the container onto
-- its cast bar a frame later. A hidden cast bar keeps its place, so nothing moves between casts.
--
-- WHILE CASTING IS EVENT-DRIVEN, never polled. The UNIT_SPELLCAST_* events (core/RangeMaster.lua,
-- each ifValid) reach Plates.CastChanged for a tracked plate token only: a start marks the token
-- casting, any other kind asks NS.Compat.IsCasting again (a channel can follow a cast), and the
-- "castbarWhenCasting" instances on that plate, per-plate and own-plate, are placed again. A token no
-- event has spoken for (a plate shown mid-cast) asks NS.Compat.IsCasting, and where the client has no
-- cast read (WoW Forever has no UnitCastingInfo), whether the cast bar is shown. Our frames are no
-- secure frames, so this re-anchors in combat as the rest of this file does.
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
local casting = {}    -- [token] = boolean: the last cast event's word on the plate's unit
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
    inst.anchorPlate, inst.anchorPart = nil, nil
    inst:RefreshStrips()
end

local CAST_PARTS = { castbar = true, castbarWhenCasting = true }

--- Whether `bar` is shown, read under pcall; a secret or a raise reads as not shown.
local function barShown(bar)
    local ok, v = pcall(bar.IsShown, bar)
    return ok and v == true
end

--- Whether the unit behind plate `token` casts now: the last cast event's word, else the client's
--- cast read, else whether its cast bar `bar` is shown.
local function castingOn(token, bar)
    local known = token and casting[token]
    if known ~= nil then return known end
    local asked = token and NS.Compat.IsCasting(token)
    if asked ~= nil then return asked end
    return barShown(bar)
end

--- What container `c` pins `inst` to on `plate`: its cast bar when the container asks for it (and,
--- for "castbarWhenCasting", while its unit casts) and the plate has one, else the plate.
local function partOf(inst, c, plate)
    local np = c.nameplate
    local mode = np and np.attachTo
    if not CAST_PARTS[mode] then return plate end
    local token = inst.plateToken or NS.Compat.PlateToken(plate)
    local bar = NS.FrameProviders.PlateCastBar(plate, token)
    if not bar then return plate end
    if mode == "castbarWhenCasting" and not castingOn(token, bar) then return plate end
    return bar
end

--- The root pinned to `target` at the nameplate point; answers whether the client took it.
local function pin(root, np, target)
    root:ClearAllPoints()
    return (pcall(root.SetPoint, root, Anchors.Point(np.point, "TOP"), target,
        Anchors.Point(np.relPoint, "BOTTOM"), Anchors.Offset(np.x), Anchors.Offset(np.y)))
end

--- Anchor `inst` on `plate` (or its cast bar) at container `c`'s nameplate point, unless it already
--- sits there. A cast bar refusing the anchor leaves it on the plate. Answers whether it sits on the
--- plate.
local function attach(inst, c, plate)
    local part = partOf(inst, c, plate)
    if inst.anchorPlate == plate and inst.anchorPart == part then return true end
    local np, root = c.nameplate or {}, inst.frame
    local ok = pin(root, np, part)
    if not ok and part ~= plate then
        part = plate
        ok = pin(root, np, plate)
    end
    if not ok then
        root:ClearAllPoints()
        inst.anchorPlate, inst.anchorPart = nil, nil
        inst:RefreshStrips()
        return false
    end
    inst.anchorPlate, inst.anchorPart = plate, part
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
    casting[token] = nil
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

local function whileCasting(c)
    return c ~= nil and c.nameplate ~= nil and c.nameplate.attachTo == "castbarWhenCasting"
end

--- A cast started (`started`) or moved on the unit behind `token` (core/RangeMaster.lua's
--- UNIT_SPELLCAST_* handler): its word is kept, and every "castbarWhenCasting" instance on that
--- plate, per-plate and own-plate, is placed again. Anything but a tracked plate token returns at once.
function Plates.CastChanged(token, started)
    local plate = type(token) == "string" and tokens[token]
    if not plate or NS.IsStoodDown() then return end
    if started then
        casting[token] = true
    else
        casting[token] = NS.Compat.IsCasting(token) == true
    end
    for _, id in ipairs(NS.CM.List()) do
        local c = NS.CM.Get(id)
        if isPlates(c) and whileCasting(c) then
            local inst = NS.Container.GetPlate(id, token)
            if inst then placeOn(inst, c, plate) end
        end
    end
    for inst in pairs(own) do
        if inst.anchorPlate == plate and whileCasting(inst.container) then placeOwn(inst) end
    end
end

function Plates.StandDown()
    for token in pairs(casting) do casting[token] = nil end
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
