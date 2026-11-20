local _, NS = ...
-- modules/Anchors_Mockplate.lua — the `mockplate` anchor: while the displays are unlocked out of
-- combat (NS.Container.Unlocked), a container that sits on a nameplate (an own-plate `nameplate`
-- container, or a `nameplates` container's stand-in) is drawn beside a stand-in nameplate, placed
-- exactly as its `nameplate` point and offsets would place it on a real one, so the player sees how
-- it attaches and can tune it live. modules/Anchors.lua picks the mode; locking or combat puts each
-- back on its own.
--
--   NS.Anchors.Mockplate.PLATE      { width, height }: the stand-in's size (a default enemy plate's
--                                   health bar)
--   NS.Anchors.Mockplate.Rect(inst, c) -> left, bottom, right, top   the stand-in's box in the
--                                   root's own units, measured from its BOTTOMLEFT (no frame is read)
--
-- THE CONTAINER IS STILL ON THE SCREEN ANCHOR. The root sits at its stored screen point, as a screen
-- container does (modules/Anchors_Screen.lua's Place and drag), and the stand-in is hung off the root
-- by the inverse of the nameplate anchor: where the container's `nameplate.point` would be pinned to
-- the plate's `nameplate.relPoint` at (x, y), the plate's relPoint is pinned to the root's point at
-- (-x, -y). Both read the same, and the root's drag strip still drags it: the stand-in follows. The
-- stand-in is the root's child, so it shares the root's scale, alpha and visibility, and it is never
-- a real nameplate: nothing here is restricted, and nothing is measured.
--
-- THE DRAG STRIP CLEARS IT. The strip sits on the root's top edge; a stand-in above the container
-- (the default: the container under the plate) would sit under it, so the strip is lifted over the
-- stand-in's top (NS.Anchors.Screen.SetLift), worked out from the stored points and the root's laid-out
-- size, never read back from a frame.

local Anchors = NS.Anchors
local Mock = {}
Anchors.Mockplate = Mock

local L = NS.L
local LAYERS = NS.Constants.LAYERS

local PLATE_W, PLATE_H = 120, 12
local FILL = 0.7          -- how much of the stand-in's bar is "health"
local NAME_GAP = 2        -- the name line over the bar
local NAME_H = 12         -- the name line's height, for the strip's lift
Mock.PLATE = { width = PLATE_W, height = PLATE_H }

local plates = {}   -- [inst] = the stand-in frame, kept with the pooled instance
local shown = {}    -- [inst] = true: the instances on the stand-in now

--- The x (or y) of `point` within a box `size` wide (or tall), from its left (or bottom) edge.
local function along(point, size, low, high)
    if point:find(low, 1, true) then return 0 end
    if point:find(high, 1, true) then return size end
    return size / 2
end

--- The stand-in's box in the root's units, from the root's BOTTOMLEFT: left, bottom, right, top.
function Mock.Rect(inst, c)
    local np = c.nameplate or {}
    local point = Anchors.Point(np.point, "TOP")
    local relPoint = Anchors.Point(np.relPoint, "BOTTOM")
    local w, h = tonumber(inst.width) or 0, tonumber(inst.height) or 0
    -- The root's pinned point, and the plate's relPoint placed at it less the offsets.
    local ax = along(point, w, "LEFT", "RIGHT") - Anchors.Offset(np.x)
    local ay = along(point, h, "BOTTOM", "TOP") - Anchors.Offset(np.y)
    local left = ax - along(relPoint, PLATE_W, "LEFT", "RIGHT")
    local bottom = ay - along(relPoint, PLATE_H, "BOTTOM", "TOP")
    return left, bottom, left + PLATE_W, bottom + PLATE_H
end

--- The stand-in's look: an enemy nameplate's, under every skin (skinning-§9 Preview stand-ins, owner
--- ruling U-24 of 2026-11-20). It imitates a client nameplate, which no skin reaches, so a skinned
--- copy would mislead the player tuning offsets against it: its ground, edge, health fill and name
--- line (the client's GameFontHighlightSmall) stay as they are, and only the container beside it
--- follows the skin. Painted once, at build; no skin switch repaints it.
local function paint(p)
    p.bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)
    p.fill:SetColorTexture(0.78, 0.16, 0.16, 1)
    NS.Style.PaintEdges(p.edges, 0, 0, 0, 1)
end

local function build(inst)
    local root = inst.frame
    local p = CreateFrame("Frame", nil, root)
    p:SetSize(PLATE_W, PLATE_H)
    p:EnableMouse(false)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints(p)
    p.fill = p:CreateTexture(nil, "ARTWORK")
    p.fill:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    p.fill:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
    p.fill:SetWidth(PLATE_W * FILL)
    p.edges = NS.Style.NewEdges(p, "OVERLAY")
    NS.Style.LayEdges(p, p.edges, 1)
    p.name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.name:SetPoint("BOTTOM", p, "TOP", 0, NAME_GAP)
    paint(p)
    p:Hide()
    plates[inst] = p
    return p
end

--- What the stand-in's name line says: whose plate it stands for (the Unit row's own label).
local function nameFor(c)
    if c.unit == "nameplates" then return L["Nameplate (any enemy)"] end
    if c.unit == "nameplatesExceptTarget" then return L["Nameplate (any enemy but the target)"] end
    local units = NS.ContainerValues and NS.ContainerValues.UNITS
    return L["Nameplate (%s)"]:format(tostring(units and units[c.unit] or c.unit))
end

--- Hang the stand-in off the root by the inverse of the nameplate anchor, and lift the strip over it.
local function place(inst, c)
    local p = plates[inst] or build(inst)
    local np = c.nameplate or {}
    p:ClearAllPoints()
    p:SetPoint(Anchors.Point(np.relPoint, "BOTTOM"), inst.frame, Anchors.Point(np.point, "TOP"),
        -Anchors.Offset(np.x), -Anchors.Offset(np.y))
    local okLevel, level = pcall(inst.frame.GetFrameLevel, inst.frame)
    if okLevel and type(level) == "number" then p:SetFrameLevel(level + LAYERS.LEVEL.FILL) end
    p.nameText = nameFor(c)
    p.name:SetText(p.nameText)
    p:Show()
    local _, _, _, top = Mock.Rect(inst, c)
    local h = tonumber(inst.height) or 0
    Anchors.Screen.SetLift(inst, math.max(0, top + NAME_GAP + NAME_H - h))
end

function Mock.Apply(inst, c)
    Anchors.Screen.Apply(inst, c)
    shown[inst] = true
    place(inst, c)
end

--- The root was laid out again (its size moved): the strip's lift follows.
function Mock.Relaid(inst)
    if shown[inst] and inst.container then place(inst, inst.container) end
end

function Mock.Detach(inst)
    shown[inst] = nil
    Anchors.Screen.Detach(inst)
    Anchors.Screen.SetLift(inst, 0)
    local p = plates[inst]
    if p then p:Hide() end
end

-- Suite seam: the stand-in an instance wears (nil before its first unlock).
function Mock.__plate(inst) return plates[inst] end

function Mock.__reset()
    for inst in pairs(shown) do shown[inst] = nil end
end

Anchors.Register("mockplate", Mock)
