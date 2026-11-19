local _, NS = ...
-- modules/Anchors.lua — the anchor dispatcher (design spec 5.4): where a container instance sits.
--
--   NS.Anchors.Apply(inst, container)   place the instance by its container's anchor mode
--   NS.Anchors.Detach(inst)             leave whatever mode it was in (the renderer's park)
--   NS.Anchors.ShownChanged(inst)       the instance was shown or hidden (the cursor follow arms on it)
--   NS.Anchors.UnitChanged(unit)        a different unit sits behind `unit` (core/RangeMaster.lua)
--   NS.Anchors.FlushDeferred()          the leave edge: re-apply every anchor write combat held
--   NS.Anchors.RefreshLock()            the `locked` setting, the unlocked show-all or Test mode
--                                       moved: the drag strips follow
--   NS.Anchors.Refresh(inst)            place `inst` again when the mode it takes now differs (the
--                                       unlocked show-all's edges, modules/Container.lua)
--   NS.Anchors.Register(mode, impl)     a mode file's registration, at file load
--
-- THE MODES, one file each, each registering here at load:
--   screen      modules/Anchors_Screen.lua     the stored point on UIParent; dragged while unlocked
--   frame       modules/Anchors_Frame.lua      on a unit frame (modules/FrameProviders.lua)
--   nameplate   modules/Anchors_Nameplate.lua  on the container's unit's own nameplate
--   plates      modules/Anchors_Nameplate.lua  a `nameplates` container's per-plate instance
--   cursor      modules/Anchors_Cursor.lua     following the cursor
--   mockplate   modules/Anchors_Mockplate.lua  unlocked: a plate container beside a stand-in plate
-- An impl is `{ Apply(inst, c), Detach(inst)?, ShownChanged(inst)?, UnitChanged(unit)? }`.
--
-- WHICH MODE. A per-plate instance is always `plates`, whatever its container's stored mode. A
-- `frame` container whose unit has no frame from its provider (mouseover: neither Blizzard nor
-- EllesmereUI draws one) follows the cursor instead (design spec 5.4). An unknown stored mode is
-- `screen`. Moving from one mode to another detaches the old one first (its drag strip, its follow
-- membership, its wait for a missing frame).
--
-- UNLOCKED, A DISPLAY THAT MOVES WAITS STILL. While every container shows unlocked out of combat
-- (NS.Container.Unlocked), a cursor container (a frame-mode mouseover one included) is placed on the
-- screen anchor instead, at its stored screen point, so it can be found and its drag strip held. An
-- own-plate container and a `nameplates` container's stand-in are placed there too, beside a
-- stand-in nameplate that shows how they attach to a real one (`mockplate`). Locking or combat puts
-- each back on its own mode. Every container
-- instance but a per-plate one wears the drag strip while unlocked (modules/Anchors_Screen.lua).

NS.Anchors = NS.Anchors or {}
local Anchors = NS.Anchors

local modes = {}

function Anchors.Register(mode, impl)
    modes[mode] = impl
end

--- The mode `inst` is placed in under container `c`.
local function modeFor(inst, c)
    if inst.plateToken then return "plates" end
    local m = c.anchor and c.anchor.mode
    if m == "frame" and modes.frame and modes.frame.UsesCursor(c) then m = "cursor" end
    if NS.Container.Unlocked() then
        if m == "cursor" then return "screen" end
        if (m == "nameplate" or c.unit == "nameplates") and modes.mockplate then return "mockplate" end
    end
    if modes[m] then return m end
    return "screen"
end

function Anchors.Apply(inst, c)
    local mode = modeFor(inst, c)
    local impl = modes[mode]
    local prev = inst.anchorImpl
    if prev and prev ~= impl and prev.Detach then prev.Detach(inst) end
    inst.anchorImpl, inst.anchorMode = impl, mode
    impl.Apply(inst, c)
    if modes.screen then modes.screen.Track(inst) end
end

function Anchors.Detach(inst)
    local impl = inst.anchorImpl
    if impl and impl.Detach then impl.Detach(inst) end
    if modes.screen then modes.screen.Untrack(inst) end
    inst.anchorImpl, inst.anchorMode = nil, nil
end

function Anchors.Refresh(inst)
    local c = inst.container
    if c and modeFor(inst, c) ~= inst.anchorMode then Anchors.Apply(inst, c) end
end

function Anchors.ShownChanged(inst)
    local impl = inst.anchorImpl
    if impl and impl.ShownChanged then impl.ShownChanged(inst) end
end

--- Every mode that follows a unit token hears it (the own-plate containers re-anchor, a plate
--- token's eligibility is asked again).
function Anchors.UnitChanged(unit)
    for _, impl in pairs(modes) do
        if impl.UnitChanged then impl.UnitChanged(unit) end
    end
end

function Anchors.FlushDeferred()
    for _, impl in pairs(modes) do
        if impl.FlushDeferred then impl.FlushDeferred() end
    end
end

function Anchors.RefreshLock()
    local screen = modes.screen
    if screen and screen.RefreshLock then screen.RefreshLock() end
end

--- The stand-down: every mode's own waits and timers go (the renderer's park detached each instance).
function Anchors.StandDown()
    for _, impl in pairs(modes) do
        if impl.StandDown then impl.StandDown() end
    end
end

-- ---------------------------------------------------------------------------
-- Shared by the mode files
-- ---------------------------------------------------------------------------

--- The anchor points SetPoint accepts; anything else stored reads as `fallback`.
local POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}
Anchors.POINTS = POINTS

function Anchors.Point(v, fallback)
    if type(v) == "string" and POINTS[v] then return v end
    return fallback or "CENTER"
end

--- A stored offset as a number (0 for anything else).
function Anchors.Offset(v)
    return tonumber(v) or 0
end

-- Suite seam (tests/anchors_env.lua): every mode's sets dropped between cases.
function Anchors.__reset()
    for _, impl in pairs(modes) do
        if impl.__reset then impl.__reset() end
    end
end
