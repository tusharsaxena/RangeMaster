local _, NS = ...
-- modules/Style.lua — how a range container is drawn (design spec 5.3): the color a setting reads
-- as, the HUD face, the edge strips, the frame levels, and the measured width of a string. The
-- renderer (modules/Container.lua) and the four element files call it; nothing here holds state.
--
--   NS.Style.Color(mode, stored, ctx, field) -> r, g, b, a
--       mode "band"  the current band's `field` (frameColor, textColor or indicatorColor), or the
--                    set's unknown gray while the range is unknown or there is no unit
--            "fixed" the stored swatch
--            "class" the PLAYER's class color, the stored swatch's alpha kept (options-ui-§17,
--                    through NS.ResolveColor: an unresolvable class falls through to the swatch)
--   NS.Style.Font(fs, cfg) -> size      the element's face through the skin's S.HudFont
--   NS.Style.TextWidth(fs, text, size)  the drawn width, or an estimate where the client gives none
--   NS.Style.NewEdges(frame, layer) -> strips, LayEdges(frame, strips, size), PaintEdges(strips, ...)
--   NS.Style.Stack(child, root, offset) the child's level as an offset over the root's (frame-layering-§5)
--
-- THE FACE IS THE SKIN'S unless the element names one. An element's `font` "" draws the skin's HUD
-- face at the skin's HUD size (S.HudFontSize scales the stored size), and any other value is a
-- LibSharedMedia key drawn at the stored size. Every element's face goes through S.HudFont, the one
-- way a HUD string gets its face, so the renderer's restyle on the skin's OnLooksChanged reaches it.
--
-- EDGES ARE FOUR STRIPS OF OUR OWN, never a BackdropTemplate's: Blizzard's Backdrop does arithmetic on
-- the frame's size, and a container attached to a unit frame (plan Task 6) can sit under geometry
-- that reads secret. A strip hangs between two corners with a plain thickness, so no size is read.

NS.Style = NS.Style or {}
local Style = NS.Style

local C = NS.Constants
local Compat = NS.Compat

-- ---------------------------------------------------------------------------
-- Colors
-- ---------------------------------------------------------------------------

--- r, g, b, a for the setting (`mode`, `stored`) under the render context `ctx` (modules/Container.lua:
--- ctx.row is the current band's table or nil, ctx.set the band set).
function Style.Color(mode, stored, ctx, field)
    if mode == "fixed" then return NS.ResolveColor(stored, false) end
    if mode == "class" then return NS.ResolveColor(stored, true) end
    local row = ctx.row
    local c = row and row[field]
    if not c then c = ctx.set and ctx.set.unknown and ctx.set.unknown.color end
    return NS.ResolveColor(c or stored, false)
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

--- The path of LibSharedMedia font `key`, or the fallback face.
local function fontPath(key)
    local LSM = NS.GetLSM()
    local path = LSM and LSM:Fetch("font", key, true)
    return path or C.FALLBACK_FONT
end

--- Give `fs` the element's face, size and outline. Answers the size it draws at.
function Style.Font(fs, cfg)
    local S = NS.Skin
    local own = type(cfg.font) == "string" and cfg.font ~= ""
    local size = S.HudFontSize(cfg.size, not own)
    S.HudFont(fs, { face = own and fontPath(cfg.font) or nil, size = size, flags = cfg.outline })
    return size
end

--- The width `text` draws at in `fs`: the client's measure when it is a plain number above 0, else
--- an estimate from the size (a font that has not loaded yet measures 0).
function Style.TextWidth(fs, text, size)
    if text == "" then return 0 end
    local ok, w = pcall(fs.GetStringWidth, fs)
    if ok and type(w) == "number" and not Compat.IsSecret(w) and w > 0 then return math.ceil(w) end
    return math.ceil(#text * size * 0.6)
end

-- ---------------------------------------------------------------------------
-- Edges
-- ---------------------------------------------------------------------------

-- The four strips: the two corners each runs between, and the setter its thickness goes through.
local STRIPS = {
    { "TOPLEFT", "TOPRIGHT", "SetHeight" },
    { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
    { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
}

--- Four strip textures on `frame`, hidden until laid.
function Style.NewEdges(frame, layer)
    local strips = {}
    for i = 1, #STRIPS do
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:Hide()
        strips[i] = t
    end
    return strips
end

--- Lay `strips` on `frame`, `size` thick, inside its edge; a size of 0 or less hides them.
function Style.LayEdges(frame, strips, size)
    for i, t in ipairs(strips) do
        if size <= 0 then
            t:Hide()
        else
            local e = STRIPS[i]
            t:ClearAllPoints()
            t:SetPoint(e[1], frame, e[1], 0, 0)
            t:SetPoint(e[2], frame, e[2], 0, 0)
            t[e[3]](t, size)
            t:Show()
        end
    end
end

function Style.PaintEdges(strips, r, g, b, a)
    for _, t in ipairs(strips) do t:SetColorTexture(r, g, b, a) end
end

--- The edge file LibSharedMedia border `key` names, or nil for Solid (the strips): "" , a key LSM
--- does not know, and the flat white texture all draw as strips.
local function edgeFile(key)
    if type(key) ~= "string" or key == "" then return nil end
    local LSM = NS.GetLSM()
    local path = LSM and LSM:Fetch("border", key, true)
    if type(path) ~= "string" or path:lower() == "interface\\buttons\\white8x8" then return nil end
    return path
end

--- The frame a media border draws on, built on first need: a plain frame with BackdropTemplateMixin
--- mixed in, never the template, so no OnSizeChanged script does arithmetic on a size.
local function backdropHost(holder)
    if holder.backdrop then return holder.backdrop end
    local host = CreateFrame("Frame", nil, holder.frame)
    if BackdropTemplateMixin and Mixin then Mixin(host, BackdropTemplateMixin) end
    host:SetAllPoints(holder.frame)
    holder.backdrop = host
    return host
end

--- Lay a container's border (`holder` = { frame, strips }) from its settings `bd`: off, Solid strips
--- `size` thick, or a LibSharedMedia edge on a backdrop of its own.
function Style.Border(holder, bd)
    local size = bd.enabled and (tonumber(bd.size) or 1) or 0
    local edge = size > 0 and edgeFile(bd.texture)
    if edge then
        Style.LayEdges(holder.frame, holder.strips, 0)
        local host = backdropHost(holder)
        host:SetBackdrop({ edgeFile = edge, edgeSize = size })
        host:Show()
        holder.media = true
        return
    end
    if holder.backdrop then holder.backdrop:Hide() end
    Style.LayEdges(holder.frame, holder.strips, size)
    holder.media = false
end

function Style.PaintBorder(holder, r, g, b, a)
    if holder.media then
        holder.backdrop:SetBackdropBorderColor(r, g, b, a)
    else
        Style.PaintEdges(holder.strips, r, g, b, a)
    end
end

-- ---------------------------------------------------------------------------
-- Levels (frame-layering-§5)
-- ---------------------------------------------------------------------------

--- `frame`'s level as a plain number, 0 where the client will not give one.
local function levelOf(frame)
    local ok, level = pcall(frame.GetFrameLevel, frame)
    if ok and type(level) == "number" and not Compat.IsSecret(level) then return level end
    return 0
end

--- Put `child` at `offset` (a C.LAYERS.LEVEL entry) over `root`'s level.
function Style.Stack(child, root, offset)
    child:SetFrameLevel(levelOf(root) + offset)
end
