local _, NS = ...
-- modules/Anchors_Screen.lua — the `screen` anchor (design spec 5.4): free on screen, at the stored
-- point on UIParent, dragged by LibKa0s-Widgets-1.0's drag strip while the displays are unlocked.
--
--   NS.Anchors.Screen.Place(inst, c)    the stored point on UIParent (also the frame anchor's
--                                       placement while its frame is missing)
--   NS.Anchors.Screen.DragStop(inst)    save where a drag left the frame (NS.CM.SetPosition)
--   NS.Anchors.Screen.Track(inst), Untrack(inst)   a container instance (never a per-plate one) is
--                                       placed or parked: its drag strip follows (modules/Anchors.lua)
--   NS.Anchors.Screen.Tagged(inst) -> boolean   its drag strip shows, carrying the preview's tag:
--                                       the display's preview marker (modules/Container.lua)
--   NS.Anchors.Screen.SetLift(inst, px) the strip sits `px` higher over the root's top edge, clear
--                                       of a stand-in nameplate (modules/Anchors_Mockplate.lua)
--
-- THE POSITION IS THE REGISTRY'S. A drag ends in StopMovingOrSizing, then the frame's first point is
-- read back (the client re-anchors a moved frame to the screen) and written through the container
-- registry's own writer, NS.CM.SetPosition, rounded to whole pixels; the coalesced apply that follows
-- places the frame from what was stored. A drag cannot start in combat.
--
-- THE STRIP (AuraMaster's drag strip: the display's name, a settings mark, a close mark that
-- disables the display, the help mark) shows while `locked` is false (Master controls, `/rm unlock`,
-- the launcher) on every screen container, in combat too, and, while every container shows unlocked
-- out of combat (NS.Container.Unlocked), on every other container as well (never a per-plate
-- instance: a `nameplates` container wears it on its stand-in). Only a container on the screen
-- anchor drags; one held at its screen point while unlocked (a cursor or own-plate container,
-- modules/Anchors.lua) is on it, and a drag moves where it waits. One on a unit frame shows its name
-- muted and does not drag: it follows its frame. In Test mode the label ends in the TEST tag, in
-- Sim mode in the SIM tag, and while it shows so tagged the strip is the display's preview marker:
-- the renderer hides the TestStrip (preview-mode, *Where the strip sits*, the tagged drag handle,
-- v2.114.0), and puts it back the moment the strip hides.
-- `RefreshLock` follows the setting and the modes. The strip is built on its first show and kept
-- with the pooled frame. Without LibKa0s-Widgets-1.0 a screen frame itself takes the drag.

local Anchors = NS.Anchors
local Screen = {}
Anchors.Screen = Screen

local LAYERS = NS.Constants.LAYERS
local L = NS.L
local KW = LibStub and LibStub("LibKa0s-Widgets-1.0", true)

local members = {}   -- [inst] = true: every instance placed on screen
local tracked = {}   -- [inst] = true: every container instance that may wear the strip

local function unlocked()
    return NS.GetSetting("locked") == false
end

--- Whether `inst` drags: placed on the screen anchor (beside a stand-in nameplate too).
local function draggable(inst) return inst.anchorMode == "screen" or inst.anchorMode == "mockplate" end

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

local function canDrag(inst) return draggable(inst) and not InCombatLockdown() end

--- `text` in the skin's color token `token` (else r, g, b), as a chat escape.
local function tinted(text, token, r, g, b)
    local cr, cg, cb = NS.Skin.Color(token)
    if type(cr) ~= "number" then cr, cg, cb = r, g, b end
    return string.format("|cff%02x%02x%02x%s|r", math.floor(cr * 255 + 0.5), math.floor(cg * 255 + 0.5),
        math.floor(cb * 255 + 0.5), text)
end

--- The preview's tag ending the label: TEST in Test mode, SIM in Sim mode, else nil.
local function tag()
    if NS.IsSimMode and NS.IsSimMode() then return tinted(L["SIM"], "sem.info", 0.3, 0.8, 1) end
    if NS.IsTestMode and NS.IsTestMode() then return tinted(L["TEST"], "sem.warn", 1, 0.65, 0) end
    return nil
end

--- The strip's label: the display's name, muted while it does not drag, and the preview's tag.
local function label(inst)
    local c = inst.container
    local name = c and c.name or ""
    if not draggable(inst) then name = tinted(name, "text.muted", 0.6, 0.6, 0.6) end
    local t = tag()
    if t then name = name .. "  " .. t end
    return name
end

local MODE_LINE = {
    cursor    = L["Follows the cursor once the displays are locked. Drag to choose where it waits while unlocked."],
    nameplate = L["Sits on a nameplate once the displays are locked, where it sits on the preview nameplate now. Drag to move both; set how it attaches in its settings."],
    frame     = L["Sits on its unit frame, so it cannot be dragged. Set its offsets in its settings."],
}

--- What the strip does for this display, read on every hover.
local function howTo(inst)
    local c = inst.container
    local mode = c and c.anchor and c.anchor.mode
    if mode == "frame" and NS.Anchors.Frame.UsesCursor(c) then mode = "cursor" end
    if inst.anchorMode == "frame" then mode = "frame" end
    if inst.anchorMode == "mockplate" then mode = "nameplate" end
    return MODE_LINE[mode] or L["Drag to move. Lock the displays to hide this strip."]
end

local function nameOf(inst)
    return function() return inst.container and inst.container.name or L["Range display"] end
end

--- The settings mark: the Containers page on this display.
local function openSettings(inst)
    if not inst.id then return end
    if NS.ShowContainer then NS.ShowContainer(inst.id) end
    if NS.OpenOptionsPanel then NS.OpenOptionsPanel("containers") end
end

--- The close mark: this display disabled (its settings kept), said in chat.
local function disable(inst)
    local id, c = inst.id, inst.container
    if not (id and c) then return end
    if NS.CM.SetField(id, "enabled", false) then
        NS.Printf(L["%s disabled. Turn it back on with Enable on the Containers page."], c.name or "")
    end
end

--- The strip, or (without the widget library) nil: a screen frame then takes the drag itself.
local function buildHandle(inst)
    if not (KW and KW.DragHandle) then return nil end
    local h = KW.DragHandle(inst.frame, {
        owner = NS.name, label = "", moveFrame = inst.frame, helpIcon = NS.Icon("info"),
        canDrag = function() return canDrag(inst) end, onDragStop = function() Screen.DragStop(inst) end,
        tooltip = { title = nameOf(inst), body = { function() return howTo(inst) end } },
        settings = function() openSettings(inst) end, settingsIcon = NS.Icon("settings"),
        settingsTooltip = { title = nameOf(inst), body = { L["Click to open this display's settings."] } },
        onClose = function() disable(inst) end, closeIcon = NS.Icon("close"),
        closeTooltip = { title = nameOf(inst),
            body = { L["Click to disable this display. Its settings are kept; turn Enable back on for it on the Containers page to bring it back."] } },
        onRightClick = function() openSettings(inst) end,
        level = LAYERS.LEVEL.HANDLE, ignoreParentAlpha = true,
    })
    if not h then return nil end
    h:ClearAllPoints()
    h:SetPoint("BOTTOM", inst.frame, "TOP", 0, 2 + (inst.handleLift or 0))
    return h
end

function Screen.SetLift(inst, px)
    px = math.floor((tonumber(px) or 0) + 0.5)
    if (inst.handleLift or 0) == px then return end
    inst.handleLift = px
    local h = inst.dragHandle
    if not h then return end
    h:ClearAllPoints()
    h:SetPoint("BOTTOM", inst.frame, "TOP", 0, 2 + px)
    if h:IsShown() and inst.strips then
        for _, s in pairs(inst.strips) do
            if s and s.Place then pcall(s.Place, s) end
        end
    end
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

--- Whether `inst` wears the strip now (THE STRIP, above).
local function wantsHandle(inst)
    if not (tracked[inst] and unlocked()) then return false end
    return draggable(inst) or NS.Container.Unlocked()
end

--- Show the strip while `on`, hide it otherwise.
local function showHandle(inst, on)
    if on and not inst.dragHandle then
        inst.dragHandle = buildHandle(inst) or false
        -- A preview strip built before the handle stacks beyond it from now on (modules/Container.lua).
        if inst.dragHandle and inst.DockStrips then inst:DockStrips() end
    end
    local h = inst.dragHandle
    if not h then return dragFrameItself(inst, on and draggable(inst)) end
    if on then
        h:SetLabel(label(inst))
        if h.ApplyWidth then h:ApplyWidth() end
        h:Show()
    else
        h:Hide()
    end
    -- The preview's TestStrip follows: hidden while this strip is the marker (THE STRIP, above).
    if inst.RefreshStrips then inst:RefreshStrips() end
end

function Screen.Tagged(inst)
    local h = inst.dragHandle
    return h and h:IsShown() == true and tag() ~= nil or false
end

function Screen.Apply(inst, c)
    members[inst] = true
    inst:SetAnchorHidden(false)
    Screen.Place(inst, c)
    inst.frame:SetMovable(true)
    inst.frame:SetClampedToScreen(true)
end

function Screen.Detach(inst)
    members[inst] = nil
    if inst.dragHandle == nil then dragFrameItself(inst, false) end
    inst.frame:SetMovable(false)
    -- The clamp is the screen anchor's: a container on a plate, a frame or the cursor is not pinned.
    inst.frame:SetClampedToScreen(false)
end

--- A container instance placed (any mode): its strip follows. A per-plate instance wears none.
function Screen.Track(inst)
    if inst.plateToken then return end
    tracked[inst] = true
    local on = wantsHandle(inst)
    if on or inst.dragHandle then showHandle(inst, on) end
end

--- A container instance parked: its strip goes.
function Screen.Untrack(inst)
    tracked[inst] = nil
    if inst.dragHandle then showHandle(inst, false) end
end

function Screen.RefreshLock()
    for inst in pairs(tracked) do
        local on = wantsHandle(inst)
        if on or inst.dragHandle then showHandle(inst, on) end
    end
end

-- Suite seam (tests/test_anchors_screen.lua): the strip's two marks as its buttons call them.
function Screen.__marks(inst)
    return { settings = function() openSettings(inst) end, close = function() disable(inst) end }
end

function Screen.__reset()
    for inst in pairs(members) do members[inst] = nil end
    for inst in pairs(tracked) do tracked[inst] = nil end
end

Anchors.Register("screen", Screen)
