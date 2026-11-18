local _, NS = ...
-- modules/Anchors_Cursor.lua — the `cursor` anchor (design spec 5.4): the container follows the
-- cursor, offset by its stored x and y.
--
-- ONE OnUpdate FOR EVERY CURSOR CONTAINER (the v0.1.0 plan's Global Constraints): a single driver
-- frame, its OnUpdate set only while at least one cursor container is SHOWN and cleared the moment
-- the last one hides (a mouseover that left, a target gone), so a cursor container costs nothing per
-- frame while it draws nothing. The renderer tells the anchors each show and hide
-- (NS.Anchors.ShownChanged), and a container shown is placed at once, so it never flashes at its
-- last spot.
--
-- THE POSITION is GetCursorPosition() over UIParent's effective scale (the cursor in UIParent's
-- units), plus the stored offset, over the container's own scale (SetPoint reads offsets in the
-- frame's units), as a point on UIParent's BOTTOMLEFT. Bucket `cursor.follow` brackets the pass.
-- The frames are this addon's own and anchored to UIParent, so the follow runs in combat too.

local Anchors = NS.Anchors
local Cursor = {}
Anchors.Cursor = Cursor

local Perf = NS.Perf

local members = {}   -- [inst] = true
local driver
local armed = false

local function uiScale()
    local s = tonumber(UIParent:GetEffectiveScale())
    if not s or s <= 0 then return 1 end
    return s
end

local function place(inst, x, y, s)
    local a, root = inst.container.anchor, inst.frame
    local k = inst.appliedScale or 1
    if k <= 0 then k = 1 end
    root:ClearAllPoints()
    root:SetPoint(Anchors.Point(a.point), UIParent, "BOTTOMLEFT", (x / s + Anchors.Offset(a.x)) / k,
        (y / s + Anchors.Offset(a.y)) / k)
end

local function cursorAt()
    local x, y = GetCursorPosition()
    return tonumber(x) or 0, tonumber(y) or 0
end

local function follow()
    local t0 = Perf.on and debugprofilestop()
    local x, y = cursorAt()
    local s = uiScale()
    for inst in pairs(members) do
        if inst.shown and inst.container then place(inst, x, y, s) end
    end
    if t0 then Perf.Note("cursor.follow", debugprofilestop() - t0) end
end

local function anyShown()
    for inst in pairs(members) do
        if inst.shown then return true end
    end
    return false
end

--- Arm the driver while a member is shown and the addon stands up; disarm it otherwise.
local function reconcile()
    local want = anyShown() and not NS.IsStoodDown()
    if want == armed then return end
    armed = want
    if want then
        if not driver then driver = CreateFrame("Frame", nil, UIParent) end
        driver:SetScript("OnUpdate", follow)
        driver:Show()
    else
        driver:SetScript("OnUpdate", nil)
        driver:Hide()
    end
end

local function placeNow(inst)
    if not (inst.shown and inst.container) then return end
    local x, y = cursorAt()
    place(inst, x, y, uiScale())
end

function Cursor.Apply(inst, c)
    members[inst] = true
    inst:SetAnchorHidden(false)
    if c then placeNow(inst) end
    reconcile()
end

function Cursor.ShownChanged(inst)
    if not members[inst] then return end
    placeNow(inst)
    reconcile()
end

function Cursor.Detach(inst)
    members[inst] = nil
    reconcile()
end

function Cursor.StandDown()
    reconcile()
end

function Cursor.__reset()
    for inst in pairs(members) do members[inst] = nil end
    reconcile()
end

-- Suite seams (tests/test_anchors_cursor.lua, tests/test_perf.lua, tests/perf.lua).
function Cursor.__driver() return driver end
function Cursor.__has(inst) return members[inst] == true end

Anchors.Register("cursor", Cursor)
