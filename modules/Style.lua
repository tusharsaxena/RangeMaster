local _, NS = ...
-- modules/Style.lua — how a range container is drawn (design spec 5.3): the color a setting reads
-- as, the HUD face, the edge strips, the frame levels, and the measured width of a string. The
-- renderer (modules/Container.lua) and the four element files call it; nothing here holds state.
--
--   NS.Style.Color(mode, stored, ctx, field) -> r, g, b, a
--       mode "band"  the current band's `field` (frameColor, textColor or indicatorColor), or the
--                    set's unknown gray while the range is unknown or there is no unit
--            "fixed" the stored swatch
--            "class" the TRACKED unit's class color (ctx.unit), the stored swatch's alpha kept
--                    (options-ui-§17: a range container describes its unit, so the class is the
--                    unit's; through NS.ResolveColor, so an NPC or a class the client has not answered
--                    for falls through to the swatch). The renderer repaints on a unit change
--                    (modules/Container.lua, UnitChanged), so the color follows a retarget.
--   NS.Style.Font(fs, cfg) -> size      the element's face through the skin's S.HudFont, and its shadow
--   NS.Style.TextWidth(fs, text, size)  the drawn width, or an estimate where the client gives none
--   NS.Style.NewEdges(frame, layer) -> strips, LayEdges(frame, strips, size), PaintEdges(strips, ...)
--   NS.Style.Stack(child, root, offset) the child's level as an offset over the root's (frame-layering-§5)
--
-- THE FACE IS THE SKIN'S unless the element names one. An element's `font` "" draws the skin's HUD
-- face at the skin's HUD size (S.HudFontSize scales the stored size), and any other value is a
-- LibSharedMedia key drawn at the stored size. Every element's face goes through S.HudFont, the one
-- way a HUD string gets its face, so the renderer's restyle on the skin's OnLooksChanged reaches it.
--
-- A SOLID EDGE IS FOUR STRIPS OF OUR OWN, never a backdrop: a strip hangs between two corners with a
-- plain thickness, so drawing it reads no size. A LibSharedMedia edge is drawn by Blizzard's
-- BackdropTemplateMixin on a host frame of its own, and that mixin DOES read the host's size
-- (SetBackdrop and OnBackdropSizeChanged work out the edge pieces' tiling from GetWidth, GetHeight
-- and the effective scale). So the host carries the template's own OnSizeChanged wiring, and every
-- later size the renderer's layout gives the root re-tiles the edge. The host is this addon's frame,
-- sized from the plain numbers Instance:Layout computes, so the size the mixin reads is not secret.

NS.Style = NS.Style or {}
local Style = NS.Style

local C = NS.Constants
local Compat = NS.Compat

-- ---------------------------------------------------------------------------
-- Colors
-- ---------------------------------------------------------------------------

--- r, g, b, a for the setting (`mode`, `stored`) under the render context `ctx` (modules/Container.lua:
--- ctx.row is the current band's table or nil, ctx.set the band set, ctx.unit the tracked unit).
function Style.Color(mode, stored, ctx, field)
    if mode == "fixed" then return NS.ResolveColor(stored, false) end
    if mode == "class" then return NS.ResolveColor(stored, true, ctx.unit) end
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

--- Give `fs` the element's face, size, outline and shadow (the Font block's six rows, options-ui-§16).
--- Answers the size it draws at.
function Style.Font(fs, cfg)
    local S = NS.Skin
    local own = type(cfg.font) == "string" and cfg.font ~= ""
    local size = S.HudFontSize(cfg.size, not own)
    S.HudFont(fs, { face = own and fontPath(cfg.font) or nil, size = size, flags = cfg.outline })
    -- The client's own shadow color (black) is kept: only the offset turns it on or off.
    if cfg.shadow then
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
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
--- mixed in, and the template's OnSizeChanged wiring with it, so a size that moves after the
--- SetBackdrop (the layout sizes the root after the border is laid) re-tiles the edge pieces.
local function backdropHost(holder)
    if holder.backdrop then return holder.backdrop end
    local host = CreateFrame("Frame", nil, holder.frame)
    if BackdropTemplateMixin and Mixin then
        Mixin(host, BackdropTemplateMixin)
        if host.OnBackdropSizeChanged then host:SetScript("OnSizeChanged", host.OnBackdropSizeChanged) end
    end
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
