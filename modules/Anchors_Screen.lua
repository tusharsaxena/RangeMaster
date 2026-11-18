local _, NS = ...
-- modules/Anchors_Screen.lua — the `screen` anchor (design spec 5.4): free on screen, at the stored
-- point on UIParent, dragged by LibKa0s-Widgets-1.0's drag strip while the displays are unlocked.
--
--   NS.Anchors.Screen.Place(inst, c)    the stored point on UIParent (also the frame anchor's
--                                       placement while its frame is missing)
--   NS.Anchors.Screen.DragStop(inst)    save where a drag left the frame (NS.CM.SetPosition)
--
-- THE POSITION IS THE REGISTRY'S. A drag ends in StopMovingOrSizing, then the frame's first point is
-- read back (the client re-anchors a moved frame to the screen) and written through the container
-- registry's own writer, NS.CM.SetPosition, rounded to whole pixels; the coalesced apply that follows
-- places the frame from what was stored. A drag cannot start in combat.
--
-- THE STRIP shows on every screen container while `locked` is false (Master controls, `/rm unlock`,
-- the launcher); `RefreshLock` follows the setting. It is built on the first unlock and kept with the
-- pooled frame. Without LibKa0s-Widgets-1.0 the frame itself takes the drag while unlocked.

local Anchors = NS.Anchors
local Screen = {}
Anchors.Screen = Screen

local LAYERS = NS.Constants.LAYERS
local L = NS.L
local KW = LibStub and LibStub("LibKa0s-Widgets-1.0", true)

local members = {}   -- [inst] = true: every instance placed on screen

local function unlocked()
    return NS.GetSetting("locked") == false
end

function Screen.Place(inst, c)
    local a, root = c.anchor, inst.frame
    root:ClearAllPoints()
    root:SetPoint(Anchors.Point(a.point), UIParent, Anchors.Point(a.relPoint), Anchors.Offset(a.x),
        Anchors.Offset(a.y))
end

local function round(v) return math.floor(v + 0.5) end

function Screen.DragStop(inst)
    if not inst.id then return end
    local point, _, relPoint, x, y = inst.frame:GetPoint(1)
    if not Anchors.POINTS[point] or type(x) ~= "number" or type(y) ~= "number" then return end
    if NS.Compat.IsSecret(x) or NS.Compat.IsSecret(y) then return end
    NS.CM.SetPosition(inst.id, point, Anchors.Point(relPoint, point), round(x), round(y))
end

local function canDrag() return not InCombatLockdown() end

local function tooltip()
    return { title = L["Range display"], body = { L["Drag to move. Lock the displays to hide this strip."] } }
end

--- The strip, or (without the widget library) the frame itself as the drag target.
local function buildHandle(inst)
    if not (KW and KW.DragHandle) then return nil end
    local h = KW.DragHandle(inst.frame, {
        owner = NS.name, label = "", moveFrame = inst.frame, helpIcon = NS.Icon("info"),
        canDrag = canDrag, onDragStop = function() Screen.DragStop(inst) end, tooltip = tooltip(),
        level = LAYERS.LEVEL.HANDLE, ignoreParentAlpha = true,
    })
    if not h then return nil end
    h:ClearAllPoints()
    h:SetPoint("BOTTOM", inst.frame, "TOP", 0, 2)
    return h
end

local function dragFrameItself(inst, on)
    local root = inst.frame
    root:EnableMouse(on)
    if not on then return end
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function() if canDrag() then root:StartMoving() end end)
    root:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        Screen.DragStop(inst)
    end)
end

--- Show the strip while unlocked, hide it otherwise.
local function showHandle(inst, on)
    if on and not inst.dragHandle then
        inst.dragHandle = buildHandle(inst) or false
        -- A preview strip built before the handle stacks beyond it from now on (modules/Container.lua).
        if inst.dragHandle and inst.DockStrips then inst:DockStrips() end
    end
    local h = inst.dragHandle
    if not h then return dragFrameItself(inst, on) end
    if on then
        h:SetLabel(inst.container and inst.container.name or "")
        if h.ApplyWidth then h:ApplyWidth() end
        h:Show()
    else
        h:Hide()
    end
end

function Screen.Apply(inst, c)
    members[inst] = true
    inst:SetAnchorHidden(false)
    Screen.Place(inst, c)
    inst.frame:SetMovable(true)
    inst.frame:SetClampedToScreen(true)
    showHandle(inst, unlocked())
end

function Screen.Detach(inst)
    members[inst] = nil
    if inst.dragHandle ~= nil then showHandle(inst, false) end
    inst.frame:SetMovable(false)
    -- The clamp is the screen anchor's: a container on a plate, a frame or the cursor is not pinned.
    inst.frame:SetClampedToScreen(false)
end

function Screen.RefreshLock()
    local on = unlocked()
    for inst in pairs(members) do showHandle(inst, on) end
end

function Screen.__reset()
    for inst in pairs(members) do members[inst] = nil end
end

Anchors.Register("screen", Screen)
