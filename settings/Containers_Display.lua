local _, NS = ...
-- settings/Containers_Display.lua — the Containers page's Display entry: how the selected container is
-- laid out and framed, the elements it draws (its number, text, dot and spell chips), and its caption.
--
--     [ Layout ][ Frame ][ Number ][ Text ][ Label ][ Dot ][ Spell chips ]
--
--     Layout   [Direction] [Spacing (px)] / [Padding (px)] / [Container scale] [Container opacity]
--              [Size] / [Width (px)] [Height (px)]  (grayed while Size fits the content)
--              -- Element order --  a drag list, one row per element: handle, on/off tick, name; the
--              elements turned on first and only they drag
--     Frame    -- Border --      the composed border block (options-ui-§16), Show border first, then
--                                [Border opacity] as the block's extra
--              -- Background --  [Show background], the background swatch and its color mode,
--                                [Band tint opacity]
--     Number   [Show number] [Format]  -- Font --  the composed Font block
--     Text     [Show text label] [Uppercase]  -- Font --  the composed Font block
--     Label    [Show label] [Label text] / [Position] [Align] / [Gap (px)]  -- Font --  the composed
--              Font block (Align is drawn only for Top and Bottom)
--     Dot      [Show dot] [Shape] / [Size (px)] / [Dot color] [Color from]
--              -- Style --  a tile per style, each drawn in the stored shape (grayed while the
--                           shape is Bar or Spell icon, which take no style)
--     Spell chips  [Show spell chips] [Style] / [Size (px)]
--
-- The dot is the `indicator` element: its paths (`container.elements.indicator.*`) and its name on
-- the CLI keep that word, so stored settings and /rm set reach it as before; the panel calls it Dot.
-- Which spells the chips show is the logged-in character's class seeds for this client until a list
-- is stored (NS.CM.SpellChips, modules/ContainerManager.lua).
--
-- The Label tab is the CAPTION naming the display (`container.label.*`, modules/Container.lua): no
-- element, so it is not in the element order. Its Label text row is an EditBox that applies on Enter;
-- left empty, the caption reads the container's name (the General tab's Name row), and follows a rename.
--
-- THE BLOCKS ARE COMPOSED (options-ui-§16, anti-pattern #73): H.FontGroup and H.BorderGroup emit the
-- canonical rows and their order; `keys` maps each canonical leaf onto the field the container
-- already stores, so the composer never changes what is stored. The `Use class color` companion each
-- emits becomes this addon's three-value color mode (band / fixed / class), which options-ui-§17
-- names as the richer form of the same companion (NS.ContainerValues.ColorModeCompanion).
--
-- THE ELEMENT ORDER IS DRAGGED (options-ui-§18): its order is the setting, so the Layout tab draws it
-- as LibKa0s-Widgets' ReorderList, one row per element, and a drop writes the new order through the
-- row `container.elements.order`. That row is skipRender (the list is its surface) and reads and
-- takes the order as names, comma-separated, so `/rm set container.elements.order number,text` works:
-- the names given go first, in that order, and the rest keep theirs. The stored value is an array,
-- which NS.CM.SetField accepts only as an arrangement of the four elements (NS.CM.IsElementOrder).
-- The list's controller is canceled at the top of every Containers render, before the scroll is
-- cleared (NS.CancelElementOrder, called by settings/Containers.lua), because its handles and row
-- boxes sit on frames the clear hands back to AceGUI's pool.
--
-- THE DOT'S STYLE IS PICKED FROM TILES, the same way: the row `container.elements.indicator.style`
-- is skipRender (the tiles are its surface, drawn after its `Style` subgroup's heading) and stays a
-- dropdown row in the schema, so `/rm set container.elements.indicator.style gem` works. Each tile
-- is the stored shape's art in that style, tinted as the dot would draw in the first band, and a
-- click writes through the row. Bar and Spell icon take no style: the row is disabledIf them, and
-- the tiles gray and take no click. Their slot's own OnRelease takes them off it, and they carry a
-- refresher of their own, so a Shape or color write repaints them (the tile section, below).

local L = NS.L
local H = NS.Helpers
local V = NS.ContainerValues

local PAGE = "containers_display"
local LAYOUT, FRAME, NUMBER, TEXT, LABEL = L["Layout"], L["Frame"], L["Number"], L["Text"], L["Label"]
local DOT, SPELLS, S_STYLE = L["Dot"], L["Spell chips"], L["Style"]

local UNIT_CLASS = { source = "unit" }

local DIRECTIONS = { row = L["Row (side by side)"], column = L["Column (stacked)"] }
local DIRECTIONS_SORT = { "row", "column" }

local SIZINGS = { fit = L["Fit its content"], fixed = L["Fixed size"] }
local SIZINGS_SORT = { "fit", "fixed" }

--- Whether the selected container's size is its own content's (the width and height then gray).
local function fitsContent()
    local c = NS.SelectedContainer()
    return not (c and c.layout.sizing == "fixed")
end

local FORMATS = {
    range = L["Range (20\226\128\14725)"], max = L["Farthest (25)"], min = L["Nearest (20)"],
    under = L["Under (<25)"], approx = L["About (~22)"], suffix = L["With yards (25 yd)"],
}
local FORMATS_SORT = { "range", "max", "min", "under", "approx", "suffix" }

local MASTER_SCALE = L["Multiplied by Master scale on the General page > Master controls."]
local MASTER_OPACITY = L["Multiplied by Master opacity on the General page > Master controls."]

local rows = {
    { path = "container.layout.direction", page = PAGE, group = LAYOUT, order = 10, type = "string",
      values = DIRECTIONS, sorting = DIRECTIONS_SORT, label = L["Direction"],
      desc = L["Whether the elements sit side by side or stacked."] },
    { path = "container.layout.spacing", page = PAGE, group = LAYOUT, order = 20, type = "number",
      min = 0, max = 40, step = 1, label = L["Spacing (px)"], desc = L["The gap between two elements, in pixels."] },
    { path = "container.layout.padding", page = PAGE, group = LAYOUT, order = 30, type = "number",
      min = 0, max = 40, step = 1, label = L["Padding (px)"],
      desc = L["The space between the elements and the container's edge, in pixels."] },
    { path = "container.layout.scale", page = PAGE, group = LAYOUT, order = 40, type = "number",
      min = 0.5, max = 3, step = 0.05, label = L["Container scale"],
      desc = L["The size of this container."] .. " " .. MASTER_SCALE },
    { path = "container.layout.alpha", page = PAGE, group = LAYOUT, order = 50, type = "number",
      min = 0, max = 1, step = 0.05, isPercent = true, label = L["Container opacity"],
      desc = L["How opaque this container is."] .. " " .. MASTER_OPACITY },
    { path = "container.layout.sizing", page = PAGE, group = LAYOUT, order = 52, type = "string",
      startsLine = true, values = SIZINGS, sorting = SIZINGS_SORT, label = L["Size"],
      desc = L["Fit its content: the container grows and shrinks with what it shows, so a longer number or label widens it. Fixed size: it keeps the width and height below, the elements centered in it."] },
    { path = "container.layout.width", page = PAGE, group = LAYOUT, order = 54, type = "number",
      startsLine = true, min = 10, max = 600, step = 1, label = L["Width (px)"], disabledIf = function() return fitsContent() end,
      desc = L["The container's width while Size is Fixed size."] },
    { path = "container.layout.height", page = PAGE, group = LAYOUT, order = 56, type = "number",
      min = 10, max = 300, step = 1, label = L["Height (px)"], disabledIf = function() return fitsContent() end,
      desc = L["The container's height while Size is Fixed size."] },
}

--- Append `list` to `rows`.
local function add(list)
    for _, row in ipairs(list) do rows[#rows + 1] = row end
end

-- ── Frame ───────────────────────────────────────────────────────────────────────────────────

add(H.BorderGroup({
    prefix = "container.frame.border.", page = PAGE, group = FRAME, subgroup = L["Border"], order = 10,
    show = true, classColor = UNIT_CLASS,
    keys = { borderShow = "enabled", borderStyle = "texture", borderSize = "size", borderColor = "color",
             useClassColorBorder = "colorMode" },
    extra = {
        { path = "container.frame.border.alpha", type = "number", startsLine = true, min = 0, max = 1,
          step = 0.05, isPercent = true, label = L["Border opacity"],
          desc = L["How opaque the border is, multiplying its color's own opacity in every color mode."] },
    },
}))
add({
    { path = "container.frame.background.enabled", page = PAGE, group = FRAME, subgroup = L["Background"],
      order = 100, type = "bool", startsLine = true, label = L["Show background"],
      desc = L["Fill the container behind its elements."] },
})
add(H.ColorPair({
    prefix = "container.frame.background.", page = PAGE, group = FRAME, subgroup = L["Background"],
    order = 110, key = "color", companionKey = "colorMode", label = L["Background color"],
    classColor = UNIT_CLASS,
}))
add({
    { path = "container.frame.background.bandAlpha", page = PAGE, group = FRAME, subgroup = L["Background"],
      order = 130, type = "number", min = 0, max = 1, step = 0.05, isPercent = true,
      label = L["Band tint opacity"],
      desc = L["How strongly the band color tints the background while Color from is Band color."] },
})

-- ── Number and Text ─────────────────────────────────────────────────────────────────────────

local FONT_KEYS = { font = "font", fontSize = "size", fontColor = "color", useClassColorFont = "colorMode",
    fontFlags = "outline", fontShadow = "shadow" }

--- One element's Font block, its face offered with the skin's own first.
local function fontBlock(prefix, group, order)
    local block = H.FontGroup({
        prefix = prefix, page = PAGE, group = group, subgroup = L["Font"], order = order,
        classColor = UNIT_CLASS, keys = FONT_KEYS,
    })
    for _, row in ipairs(block) do
        if row.path == prefix .. "font" then
            row.values, row.emptyAs = V.MediaValues("font", "Skin", L["Skin's font"]), "Skin"
        end
    end
    return block
end

add({
    { path = "container.elements.number.enabled", page = PAGE, group = NUMBER, order = 10, type = "bool",
      startsLine = true, label = L["Show number"], desc = L["Draw the distance as a number."] },
    { path = "container.elements.number.format", page = PAGE, group = NUMBER, order = 20, type = "string",
      values = FORMATS, sorting = FORMATS_SORT, label = L["Format"],
      desc = L["How the distance reads. An open-ended reading shows as 40+ in every format, and an unknown one as its band set's unknown label."] },
})
add(fontBlock("container.elements.number.", NUMBER, 100))
add({
    { path = "container.elements.text.enabled", page = PAGE, group = TEXT, order = 10, type = "bool",
      startsLine = true, label = L["Show text label"], desc = L["Draw the current band's label (MELEE, LONG, ...)."] },
    { path = "container.elements.text.upper", page = PAGE, group = TEXT, order = 20, type = "bool",
      label = L["Uppercase"], desc = L["Draw the band's label in capitals."] },
})
add(fontBlock("container.elements.text.", TEXT, 100))

-- ── Label ───────────────────────────────────────────────────────────────────────────────────

-- The plain sides are inside the container (what the first Label tab stored); "outside*" sit beyond its
-- border (modules/Container.lua's CaptionSide).
local CAPTION_SIDES = {
    top = L["Inside top"], outsideTop = L["Outside top"], bottom = L["Inside bottom"],
    outsideBottom = L["Outside bottom"], left = L["Inside left"], outsideLeft = L["Outside left"],
    right = L["Inside right"], outsideRight = L["Outside right"],
}
local CAPTION_SIDES_SORT = { "top", "outsideTop", "bottom", "outsideBottom", "left", "outsideLeft", "right",
    "outsideRight" }
local CAPTION_ALIGNS = { left = L["Left"], center = L["Center"], right = L["Right"] }
local CAPTION_ALIGNS_SORT = { "left", "center", "right" }

add({
    { path = "container.label.enabled", page = PAGE, group = LABEL, order = 10, type = "bool",
      startsLine = true, label = L["Show label"], desc = L["Draw a caption naming this container."] },
    { path = "container.label.text", page = PAGE, group = LABEL, order = 20, type = "string",
      dialogControl = "EditBox", maxLetters = 40, label = L["Label text"],
      desc = L["What the caption reads. Leave it empty to show the container's name. Press Enter to apply."],
      validate = function(v) return type(v) == "string" end },
    { path = "container.label.position", page = PAGE, group = LABEL, order = 30, type = "string",
      startsLine = true, values = CAPTION_SIDES, sorting = CAPTION_SIDES_SORT, label = L["Position"],
      desc = L["Where the caption sits: inside the container, beside the elements and within its border, or outside it, beyond the border."] },
    { path = "container.label.align", page = PAGE, group = LABEL, order = 40, type = "string",
      values = CAPTION_ALIGNS, sorting = CAPTION_ALIGNS_SORT, label = L["Align"],
      shownWhen = { path = "container.label.position", equals = { "top", "bottom", "outsideTop", "outsideBottom" } },
      desc = L["Where the caption sits along the container's top or bottom."] },
    { path = "container.label.gap", page = PAGE, group = LABEL, order = 50, type = "number",
      startsLine = true, min = 0, max = 40, step = 1, label = L["Gap (px)"],
      desc = L["The space between the caption and the elements (inside) or the container's edge (outside), in pixels."] },
})
add(fontBlock("container.label.", LABEL, 100))

-- ── Dot and Spell chips ─────────────────────────────────────────────────────────────────────

local SHAPES = {
    dot = L["Dot"], ring = L["Ring"], square = L["Square"], diamond = L["Diamond"], triangle = L["Triangle"],
    hexagon = L["Hexagon"], star = L["Star"], bar = L["Bar (fills toward the band's far edge)"], icon = L["Spell icon"],
}
local SHAPES_SORT = { "dot", "ring", "square", "diamond", "triangle", "hexagon", "star", "bar", "icon" }

-- The finishes modules/Elements_Indicator.lua draws (<shape>_<style>.tga); matte is the default.
local STYLES = { plain = L["Plain"], matte = L["Matte"], glossy = L["Glossy"], glowing = L["Glowing"],
    neon = L["Neon"], gem = L["Gem"] }
local STYLES_SORT = { "plain", "matte", "glossy", "glowing", "neon", "gem" }
-- The shapes that are not art, and so take no style.
local UNSTYLED = { bar = true, icon = true }

local CHIP_STYLES = { chip = L["Chip (colored edge)"], icon = L["Icon only"] }
local CHIP_STYLES_SORT = { "chip", "icon" }

--- Whether the selected container's dot takes no style (its shape is Bar or Spell icon).
local function noStyle()
    local c = NS.SelectedContainer()
    return c ~= nil and UNSTYLED[c.elements.indicator.shape] == true
end

add({
    { path = "container.elements.indicator.enabled", page = PAGE, group = DOT, order = 10, type = "bool",
      label = L["Show dot"], desc = L["Draw a shape colored by the current band."] },
    { path = "container.elements.indicator.shape", page = PAGE, group = DOT, order = 20, type = "string",
      values = SHAPES, sorting = SHAPES_SORT, label = L["Shape"],
      desc = L["The dot's shape. Spell icon shows the first spell chip's icon."] },
    { path = "container.elements.indicator.size", page = PAGE, group = DOT, order = 30, type = "number",
      min = 4, max = 64, step = 1, startsLine = true, label = L["Size (px)"],
      desc = L["The dot's width and height, in pixels."] },
})
add(H.ColorPair({
    prefix = "container.elements.indicator.", page = PAGE, group = DOT, order = 40, key = "color",
    companionKey = "colorMode", label = L["Dot color"], classColor = UNIT_CLASS,
}))
local styleRow = {
    path = "container.elements.indicator.style", page = PAGE, group = DOT, subgroup = S_STYLE, order = 100,
    type = "string", skipRender = true, values = STYLES, sorting = STYLES_SORT, label = S_STYLE,
    disabledIf = function() return noStyle() end,
    desc = L["The dot's finish. Bar and Spell icon take no style."],
}
add({ styleRow })
add({
    { path = "container.elements.spells.enabled", page = PAGE, group = SPELLS, order = 10, type = "bool",
      label = L["Show spell chips"],
      desc = L["Draw a chip per class spell, its edge lit while the unit is in that spell's range."] },
    { path = "container.elements.spells.style", page = PAGE, group = SPELLS, order = 20, type = "string",
      values = CHIP_STYLES, sorting = CHIP_STYLES_SORT, label = L["Style"],
      desc = L["A chip with a colored edge, or the icon alone, dimmed while out of range."] },
    { path = "container.elements.spells.size", page = PAGE, group = SPELLS, order = 30, type = "number",
      min = 10, max = 48, step = 1, label = L["Size (px)"], desc = L["Each chip's width and height, in pixels."] },
})

-- ── Element order ───────────────────────────────────────────────────────────────────────────

local ELEMENT_NAMES = {
    indicator = L["Dot"], number = L["Number"], text = L["Text label"], spells = L["Spell chips"],
}
local ORDER_PATH = "container.elements.order"
local ORDER_LABEL = L["Element order"]

--- `v` (element names, comma- or space-separated) as a whole order: the names given first, in that
--- order, then the rest in `current`'s. Nil for an empty list, a name that is no element, or a name
--- given twice.
local function parseOrder(v, current)
    if type(v) ~= "string" then return nil end
    local out, seen = {}, {}
    for name in v:lower():gmatch("[^,%s]+") do
        if not ELEMENT_NAMES[name] or seen[name] then return nil end
        seen[name] = true
        out[#out + 1] = name
    end
    if #out == 0 then return nil end
    for _, name in ipairs(current) do
        if not seen[name] then out[#out + 1] = name end
    end
    return out
end

--- The selected container's order, or the template's while there is none.
local function currentOrder()
    local c = NS.SelectedContainer()
    return (c and c.elements.order) or NS.CONTAINER_TEMPLATE.elements.order
end

local orderRow = {
    path = ORDER_PATH, page = PAGE, group = LAYOUT, order = 60, type = "string", skipRender = true,
    -- Free text on the CLI (the parser leaves an EditBox row unconstrained; validate is the check),
    -- and a stored array read as names (`listAsText`, which tests/test_schema.lua reads).
    dialogControl = "EditBox", listAsText = true, label = ORDER_LABEL,
    desc = L["The order the elements are drawn in, along the direction. Drag a row on the Layout tab, or name them: number,text puts those first."],
    validate = function(v)
        if parseOrder(v, currentOrder()) then return true end
        return false, L["Name the elements to put first, comma-separated: indicator, number, text, spells."]
    end,
}
add({ orderRow })

-- The border's style: "" is Solid (modules/Style.lua), offered first.
for _, row in ipairs(rows) do
    if row.path == "container.frame.border.texture" then
        row.values, row.emptyAs = V.MediaValues("border", "Solid", L["Solid"]), "Solid"
    end
end

NS.StampSelectionRows(V.ColorModeCompanion(rows))
-- The order row reads and takes names, not the stored array: its get, set and default are its own,
-- and its set still hands the array to the registry's writer (stamped above for its validate).
orderRow.default = table.concat(NS.CONTAINER_TEMPLATE.elements.order, ",")
orderRow.get = function()
    local c = NS.SelectedContainer()
    return c and table.concat(c.elements.order, ",") or nil
end
orderRow.set = function(v)
    local c, id = NS.SelectedContainer()
    local order = c and parseOrder(v, c.elements.order)
    if order then NS.CM.SetField(id, "elements.order", order) end
end
NS.RegisterSchemaRows(rows)

-- ── the drag list ───────────────────────────────────────────────────────────────────────────
--
-- THE ROWS ARE MultiMeters' Columns rows (settings/ColumnBlocks.lua there): the library's handle
-- in the gutter at the far left (the `segment` mark), a tick or a cross that turns the element on
-- or off, and the element's name at the right, in the accent while it is on and grayed while off.
-- THE TWO GROUPS: the elements turned on come first, in the order they are drawn, and only they
-- drag (the library's `boundary` keeps a drag inside them); the ones turned off sit dimmed below,
-- with no handle. The tick is what moves an element between the groups: turned on it joins the
-- end of the drawn ones, turned off it heads the others. Every move and every toggle writes the
-- whole order as the list shows it, so the stored order always reads the drawn ones first.

local ROW_H = 30
local ROW_STRIDE = ROW_H + 4   -- top of a row to the next one's: the library's drop arithmetic
local GLYPH_X = 42             -- the tick's left edge, past the handle's gutter
local HANDLE_ICON = "segment"
-- The client's art, the tick wears while the skin gives the settings panel back (NS.Skin.Mark's stock).
local ON_TEX, OFF_TEX = "Interface\\RaidFrame\\ReadyCheck-Ready", "Interface\\RaidFrame\\ReadyCheck-NotReady"
local PANEL_TEXT = { panel = true }

local rowPool, rowAttic = {}, nil

local function widgets()
    local W = LibStub and LibStub("LibKa0s-Widgets-1.0", true)
    return (W and W.ReorderList) and W or nil
end

local function attic()
    if not rowAttic then
        rowAttic = CreateFrame("Frame", nil, UIParent)
        rowAttic:Hide()
    end
    return rowAttic
end

--- Stop the last render's drag, give its handles and boxes back, and take this file's rows off the
--- AceGUI frames they sat on. Called before the Containers page clears its scroll.
function NS.CancelElementOrder(ctx)
    if not ctx then return end
    if ctx.rmOrderList then
        ctx.rmOrderList:Cancel()
        ctx.rmOrderList = nil
    end
    for i = #(ctx.rmOrderRows or {}), 1, -1 do
        local row = ctx.rmOrderRows[i]
        ctx.rmOrderRows[i] = nil
        row.rmName = nil
        row:Hide()
        row:ClearAllPoints()
        row:SetParent(attic())
        rowPool[#rowPool + 1] = row
    end
end

--- Whether element `name` of the selected container is turned on.
local function isOn(name)
    local c = NS.SelectedContainer()
    local el = c and c.elements[name]
    return el ~= nil and el.enabled == true
end

--- The list as it shows: the elements turned on in their order, then the ones turned off in theirs.
--- Answers the names and how many are on.
local function shownOrder()
    local on, off = {}, {}
    for _, name in ipairs(currentOrder()) do
        if isOn(name) then on[#on + 1] = name else off[#off + 1] = name end
    end
    for _, name in ipairs(off) do on[#on + 1] = name end
    return on, #on - #off
end

--- Store `order` (an array of names) through the order row, and redraw the page.
local function writeOrder(order)
    NS.SetByPath(ORDER_PATH, table.concat(order, ","))
    NS.RequestPanelRefresh()
end

--- Move the shown row at `from` to `to`: one write through the order row.
local function moveElement(from, to)
    local order = shownOrder()
    if not (order[from] and order[to]) then return end
    table.insert(order, to, table.remove(order, from))
    writeOrder(order)
end

--- Turn element `name` on or off (its own row, so the Number and Text tabs agree), and move it to
--- the end of the drawn ones or the head of the others.
local function toggleElement(name)
    local turnOn = not isOn(name)
    NS.SetByPath("container.elements." .. name .. ".enabled", turnOn)
    local order, n = shownOrder()
    for i, other in ipairs(order) do
        if other == name then table.remove(order, i) break end
    end
    -- `shownOrder` already sorted it by its new state; place it at the seam of the two groups.
    table.insert(order, turnOn and n or n + 1, name)
    writeOrder(order)
end

--- The tick's tooltip: what a click will do, placed beside the window as the handle's is.
local function glyphTip(glyph)
    local row = glyph.rmRow
    if not (GameTooltip and row and row.rmName) then return end
    local Tip = LibStub and LibStub("LibKa0s-Tooltip-1.0", true)
    if Tip and Tip.Own then Tip.Own(GameTooltip, glyph) else GameTooltip:SetOwner(glyph, "ANCHOR_NONE") end
    local r, g, b = NS.Skin.Color("gtip.value")
    if type(r) ~= "number" then r, g, b = HIGHLIGHT_FONT_COLOR:GetRGB() end
    GameTooltip:AddLine(isOn(row.rmName) and L["Click to turn this element off"] or L["Click to turn this element on"],
        r, g, b)
    GameTooltip:Show()
    if not (Tip and Tip.PlaceBeside and Tip.PlaceBeside(GameTooltip, glyph)) then
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOM", glyph, "TOP", 0, (Tip and Tip.TIP_GAP) or 2)
    end
end

--- A row frame, from the free list or newly built, filling `parent`'s top.
local function acquireRow(parent)
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ROW_H)
        local glyph = CreateFrame("Button", nil, row)
        glyph:SetSize(18, 18)
        glyph:SetPoint("LEFT", row, "LEFT", GLYPH_X, 0)
        glyph:EnableMouse(true)
        -- The name is read off the row at click time: a pooled row is re-pointed every render.
        glyph.rmRow = row
        glyph:SetScript("OnClick", function(self)
            local name = self.rmRow.rmName
            if name then toggleElement(name) end
        end)
        glyph:SetScript("OnEnter", glyphTip)
        glyph:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row.rmGlyph = glyph
        row.rmLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.rmLabel:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        row.rmLabel:SetJustifyH("RIGHT")
    end
    row:SetParent(parent)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    row:Show()
    return row
end

--- The tick or the cross on `row`: the Ka0s mark in the skin's good or bad color, the client's art
--- while the skin gives the settings panel back.
local function paintGlyph(row, on)
    local glyph = row.rmGlyph
    local stock = on and ON_TEX or OFF_TEX
    glyph:SetNormalTexture(stock)
    local tex = glyph.GetNormalTexture and glyph:GetNormalTexture()
    if tex and NS.Skin and NS.Skin.Mark then
        NS.Skin.Mark(tex, { art = NS.Icon(on and "confirm" or "close"), token = on and "sem.good" or "sem.bad",
            panel = true, stock = function(t) t:SetTexture(stock) end })
    end
end

local function newList(boundary)
    local W = widgets()
    if not W then return nil end
    return W.ReorderList({
        stride = ROW_STRIDE, boundary = boundary, onMove = moveElement, owner = NS.name,
        handleIcon = NS.Icon(HANDLE_ICON), handleTooltip = L["Drag to reorder"],
    })
end

--- One element's row: an AceGUI slot the scroll lays out, holding a raw frame the list drags.
local function drawRow(ctx, scroll, list, name)
    local slot = NS.AceGUI:Create("SimpleGroup")
    slot:SetLayout(nil)
    slot:SetFullWidth(true)
    slot:SetHeight(ROW_STRIDE)
    scroll:AddChild(slot)
    local row = acquireRow(slot.frame or slot.content)
    local on = isOn(name)
    row.rmName = name
    paintGlyph(row, on)
    local text = ELEMENT_NAMES[name]
    row.rmLabel:SetText(text)
    if NS.Skin and NS.Skin.Text then NS.Skin.Text(row.rmLabel, on and "accent" or "disabled", PANEL_TEXT) end
    ctx.rmOrderRows[#ctx.rmOrderRows + 1] = row
    if list then
        list:AddRow(row, { draggable = on, dimmed = not on, ghostText = text, height = ROW_H,
            ghostIcon = NS.Icon(on and "confirm" or "close") })
    end
end

--- The Layout tab's foot: the element order as a drag list.
local function renderOrder(ctx)
    local c = NS.SelectedContainer()
    local scroll = H.EnsureScroll(ctx)
    if not (c and scroll and NS.AceGUI) then return end
    H.Section(ctx, ORDER_LABEL)
    H.TextRow(ctx, L["Drag an element by its handle to change where it is drawn. Click the tick or the cross to turn an element on or off."],
        { fontObject = "GameFontDisableSmall" })
    local order, boundary = shownOrder()
    local list = newList(boundary)
    ctx.rmOrderList, ctx.rmOrderRows = list, {}
    for _, name in ipairs(order) do drawRow(ctx, scroll, list, name) end
    if list then list:Finish(scroll.content or scroll.frame) end
end

-- ── the style tiles ─────────────────────────────────────────────────────────────────────────
--
-- One Button per style on an AceGUI slot under the Style heading: the art (the stored shape in that
-- style, the dot's when the shape is Bar or Spell icon), its name below, the stored one edged in the
-- accent. A click is one write through the style row, then a redraw. Pooled as the order rows are.
--
-- THE TILES ARE HAND-BUILT, so they bring their own refresher (options-ui-§11): any write the page
-- makes (the Shape dropdown, the Dot color swatch, Color from) re-reads the container and repaints
-- the six tiles in place. Only a change between a styled shape and Bar or Spell icon changes the
-- tab's layout (the note above the tiles comes or goes), and that one asks for a structural redraw.
-- THE SLOT'S OWN "OnRelease" PARKS THEM (options-ui-§19): the slot is a SimpleGroup this file
-- creates, so whatever releases it (this page's clear, another page's, a parent's ReleaseChildren)
-- takes the tiles off it first; NS.ReleaseStyleTiles before the clear is belt-and-braces.

local TILE_W, TILE_H, TILE_GAP, TILE_ART = 64, 66, 8, 40
-- The tile's four 1px edges: the two corners each spans, and whether it is a row (height) or a column.
local EDGES = {
    { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
}

local tilePool = {}

--- Take `tile` off its slot, onto the attic, and back into the free list. Once per acquisition: the
--- renderer's park and the slot's OnRelease may both reach it.
local function parkTile(tile)
    if tile.rmParked then return end
    tile.rmParked = true
    tile.rmStyle, tile.rmOff, tile.rmPicked, tile.rmArtPath, tile.rmSlot = nil, nil, nil, nil, nil
    tile:Hide()
    tile:ClearAllPoints()
    tile:SetParent(attic())
    tilePool[#tilePool + 1] = tile
end

--- Give the last render's tiles back. Called before the Containers page clears its scroll.
function NS.ReleaseStyleTiles(ctx)
    if not ctx then return end
    for i = #(ctx.rmStyleTiles or {}), 1, -1 do
        parkTile(ctx.rmStyleTiles[i])
        ctx.rmStyleTiles[i] = nil
    end
end

--- A skin color token's r, g, b, or the fallback while the skin does not answer one.
local function skinRGB(token, r, g, b)
    if not (NS.Skin and NS.Skin.Color) then return r, g, b end
    local sr, sg, sb = NS.Skin.Color(token)
    if type(sr) == "number" then return sr, sg, sb end
    return r, g, b
end

--- The color the dot draws in its first band: the swatch in fixed or class mode, else the band's.
local function tileTint(c)
    local el = c.elements.indicator
    local col = el.color
    if el.colorMode == "band" then
        local set = NS.BandSets and NS.BandSets.Get and NS.BandSets.Get(c.bandSet or NS.BandSets.DefaultId())
        local band = set and set.bands and set.bands[1]
        col = (band and band.indicatorColor) or col
    end
    if type(col) ~= "table" then return 1, 1, 1 end
    return col.r or 1, col.g or 1, col.b or 1
end

--- A tile, from the free list or newly built, on `parent`.
local function acquireTile(parent)
    local tile = table.remove(tilePool)
    if tile then tile.rmParked = nil end
    if not tile then
        tile = CreateFrame("Button", nil, parent)
        tile:SetSize(TILE_W, TILE_H)
        tile.rmBg = tile:CreateTexture(nil, "BACKGROUND")
        tile.rmBg:SetAllPoints(tile)
        tile.rmEdges = {}
        for _, spec in ipairs(EDGES) do
            local edge = tile:CreateTexture(nil, "BORDER")
            edge:SetPoint(spec[1], tile, spec[1], 0, 0)
            edge:SetPoint(spec[2], tile, spec[2], 0, 0)
            if spec[3] then edge:SetHeight(1) else edge:SetWidth(1) end
            tile.rmEdges[#tile.rmEdges + 1] = edge
        end
        tile.rmArt = tile:CreateTexture(nil, "ARTWORK")
        tile.rmArt:SetSize(TILE_ART, TILE_ART)
        tile.rmArt:SetPoint("TOP", tile, "TOP", 0, -5)
        tile.rmLabel = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tile.rmLabel:SetPoint("BOTTOM", tile, "BOTTOM", 0, 5)
        -- The style is read off the tile at click time: a pooled tile is re-pointed every render.
        tile:SetScript("OnClick", function(self)
            if self.rmStyle and not noStyle() then
                NS.SetByPath(styleRow.path, self.rmStyle)
                NS.RequestPanelRefresh()
            end
        end)
    end
    tile:SetParent(parent)
    tile:ClearAllPoints()
    tile:Show()
    return tile
end

--- Paint `tile` as style `key` of shape `shape`: picked (edged in the accent) or not, grayed or not.
local function paintTile(tile, key, shape, picked, off, r, g, b)
    -- The art's path and the gray state are kept on the tile too: what a test (and /dump) reads back.
    tile.rmStyle, tile.rmOff, tile.rmPicked = key, off, picked
    tile.rmArtPath = NS.Constants.INDICATOR_PATH .. shape .. "_" .. key
    tile.rmArt:SetTexture(tile.rmArtPath)
    tile.rmArt:SetVertexColor(r, g, b)
    tile.rmLabel:SetText(STYLES[key])
    local br, bg, bb = skinRGB("input.bg", 0.08, 0.07, 0.06)
    tile.rmBg:SetColorTexture(br, bg, bb, 0.9)
    local er, eg, eb = skinRGB(picked and "text.accent" or "input.border", picked and 1 or 0.25,
        picked and 0.82 or 0.22, picked and 0 or 0.16)
    for _, edge in ipairs(tile.rmEdges) do edge:SetColorTexture(er, eg, eb, 1) end
    if NS.Skin and NS.Skin.Text then
        NS.Skin.Text(tile.rmLabel, off and "disabled" or (picked and "accent" or "body"), PANEL_TEXT)
    end
    tile:SetAlpha(off and 0.4 or 1)
    tile:EnableMouse(not off)
end

--- Paint every tile of `ctx`'s last render from the selected container as it is stored now.
local function paintTiles(ctx, c)
    local el, off = c.elements.indicator, noStyle()
    local shape = (SHAPES[el.shape] and not UNSTYLED[el.shape]) and el.shape or "dot"
    local stored = STYLES[el.style] and el.style or "matte"
    local r, g, b = tileTint(c)
    for i, tile in ipairs(ctx.rmStyleTiles) do
        local key = STYLES_SORT[i]
        paintTile(tile, key, shape, key == stored, off, r, g, b)
    end
end

--- The tiles' refresher: a repaint in place, or a structural redraw when the shape moved between a
--- styled one and Bar or Spell icon (the note above the tiles comes or goes).
local function tilesRefresher(ctx)
    return function()
        local c = NS.SelectedContainer()
        if not (c and ctx.rmStyleTiles and #ctx.rmStyleTiles > 0) then return end
        if noStyle() ~= ctx.rmStyleOff then
            NS.RequestPanelRefresh()
            return
        end
        paintTiles(ctx, c)
    end
end

--- The Dot tab's Style subgroup: a tile per style, after the heading the flow drew for the row.
local function renderStyleTiles(ctx, group)
    if group ~= DOT then return end
    local c = NS.SelectedContainer()
    local scroll = H.EnsureScroll(ctx)
    if not (c and scroll and NS.AceGUI) then return end
    local off = noStyle()
    if off then
        H.TextRow(ctx, L["Bar and Spell icon take no style. Pick a shape to choose its finish."],
            { fontObject = "GameFontDisableSmall" })
    end
    local slot = NS.AceGUI:Create("SimpleGroup")
    slot:SetLayout(nil)
    slot:SetFullWidth(true)
    slot:SetHeight(TILE_H + 8)
    scroll:AddChild(slot)
    local parent = slot.frame or slot.content
    local mine = {}
    -- The one OnRelease this slot gets: it parks the tiles still on it (options-ui-§19), and the
    -- page forgets them, so its refresher paints nothing that is no longer on screen.
    slot:SetCallback("OnRelease", function()
        for _, tile in ipairs(mine) do
            if tile.rmSlot == slot then parkTile(tile) end
        end
        if ctx.rmStyleTiles and ctx.rmStyleTiles[1] == mine[1] then ctx.rmStyleTiles = {} end
    end)
    ctx.rmStyleTiles, ctx.rmStyleOff = ctx.rmStyleTiles or {}, off
    for i = 1, #STYLES_SORT do
        local tile = acquireTile(parent)
        tile.rmSlot = slot
        tile:SetPoint("TOPLEFT", parent, "TOPLEFT", (i - 1) * (TILE_W + TILE_GAP), -4)
        mine[#mine + 1] = tile
        ctx.rmStyleTiles[#ctx.rmStyleTiles + 1] = tile
    end
    paintTiles(ctx, c)
    if ctx.refreshers then ctx.refreshers[#ctx.refreshers + 1] = tilesRefresher(ctx) end
end

NS.RegisterContainerSection(PAGE, L["Display"], {
    tooltip = L["How this container is laid out and framed, the elements it draws (its number, text, dot and spell chips), and its caption."],
    afterGroup = { [LAYOUT] = renderOrder },
    afterSubgroup = { [S_STYLE] = renderStyleTiles },
})
