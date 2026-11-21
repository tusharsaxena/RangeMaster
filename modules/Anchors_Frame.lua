local _, NS = ...
-- modules/Anchors_Frame.lua — the `frame` anchor (design spec 5.4): a container on a unit frame from
-- one of three providers (modules/FrameProviders.lua), at the point stored in `anchor.frame` (its
-- own, above the frame by default: never the screen point, so neither a drag nor a new container's
-- screen stagger carries onto the unit frame).
--
--   NS.Anchors.Frame.UsesCursor(c) -> boolean   a mouseover container with no named frame of its
--                                    own follows the cursor (modules/Anchors.lua picks the mode)
--   NS.Anchors.Frame.Retry(why)      look for every missing frame again (ADDON_LOADED,
--                                    PLAYER_ENTERING_WORLD, core/RangeMaster.lua)
--
-- A MISSING FRAME HIDES THE CONTAINER, never raises. The instance is placed at its stored screen
-- point (so it never keeps an anchor to a frame that is gone), hidden through SetAnchorHidden, and
-- one debug line names the frame; the line is not repeated while the same frame stays missing. Each
-- Retry looks again, and the container shows on its frame once the frame exists (EllesmereUI spawns
-- its frames at PLAYER_LOGIN, an addon that loads later fires ADDON_LOADED). A frame that refuses
-- the anchor (SetPoint raises) is treated as missing.
--
-- NO ANCHOR WRITE IN COMBAT. A unit frame is a secure frame, and this addon never anchors to one
-- under combat lockdown (design spec 3): an Apply or a Retry that lands in combat is held, one debug
-- line, and runs on PLAYER_REGEN_ENABLED (FlushDeferred, from core/RangeMaster.lua's leave edge).
-- The frame is never re-parented: it stays this addon's own child of UIParent.

local Anchors = NS.Anchors
local Frame = {}
Anchors.Frame = Frame

local waiting = {}    -- [inst] = true: its frame was missing
local deferred = {}   -- [inst] = true: an anchor write combat held

local function cfgOf(c)
    return c.anchor.frame or {}
end

function Frame.UsesCursor(c)
    if c.unit ~= "mouseover" then return false end
    local f = cfgOf(c)
    return not (f.provider == "custom" and NS.FrameProviders.NameFor("custom", c.unit, f.name))
end

local function defer(inst)
    if deferred[inst] then return end
    deferred[inst] = true
    NS.Debug("Anchor", "container %s: anchoring held until combat ends", tostring(inst.id))
end

--- The frame is missing (or refused the anchor): on its screen point, hidden, one line per frame.
local function missing(inst, c, why)
    local f = cfgOf(c)
    Anchors.Screen.Place(inst, c)
    inst.anchorTarget = nil
    inst:SetAnchorHidden(true)
    waiting[inst] = true
    local key = tostring(f.provider) .. ":" .. tostring(f.name) .. ":" .. tostring(c.unit)
    if inst.missingKey == key then return end
    inst.missingKey = key
    NS.Debug("Anchor", "container %s: %s frame %s %s; hidden until it appears", tostring(inst.id),
        tostring(f.provider), tostring(NS.FrameProviders.NameFor(f.provider, c.unit, f.name) or c.unit), why)
end

function Frame.Apply(inst, c)
    if InCombatLockdown() then return defer(inst) end
    deferred[inst] = nil
    local f = cfgOf(c)
    local target = NS.FrameProviders.Resolve(f.provider, c.unit, f.name)
    if not target then return missing(inst, c, "not found") end
    local root = inst.frame
    root:ClearAllPoints()
    local ok = pcall(root.SetPoint, root, Anchors.Point(f.point, "BOTTOM"), target, Anchors.Point(f.relPoint, "TOP"),
        Anchors.Offset(f.x), Anchors.Offset(f.y))
    if not ok then
        root:ClearAllPoints()
        return missing(inst, c, "refused the anchor")
    end
    waiting[inst], inst.missingKey, inst.anchorTarget = nil, nil, target
    inst:SetAnchorHidden(false)
end

function Frame.Detach(inst)
    waiting[inst], deferred[inst] = nil, nil
    inst.anchorTarget, inst.missingKey = nil, nil
end

local pass = {}

--- Every waiting instance whose frame now exists is anchored (held in combat).
function Frame.Retry(why)
    local n = 0
    for inst in pairs(waiting) do
        local c = inst.container
        local f = c and cfgOf(c)
        if f and NS.FrameProviders.Resolve(f.provider, c.unit, f.name) then
            n = n + 1
            pass[n] = inst
        end
    end
    for i = 1, n do
        local inst = pass[i]
        pass[i] = nil
        NS.Debug("Anchor", "container %s: frame found (%s)", tostring(inst.id), tostring(why))
        Frame.Apply(inst, inst.container)
    end
end

--- The leave edge: every anchor write combat held runs now.
function Frame.FlushDeferred()
    local n = 0
    for inst in pairs(deferred) do
        n = n + 1
        pass[n] = inst
    end
    for i = 1, n do
        local inst = pass[i]
        pass[i] = nil
        if deferred[inst] and inst.container then Anchors.Apply(inst, inst.container) end
    end
end

function Frame.StandDown()
    for inst in pairs(waiting) do waiting[inst] = nil end
    for inst in pairs(deferred) do deferred[inst] = nil end
end
Frame.__reset = Frame.StandDown

Anchors.Register("frame", Frame)
