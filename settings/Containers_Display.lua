local _, NS = ...
-- settings/Containers_Display.lua — the Containers page's Display entry: how the selected container is
-- laid out and framed, and its number and text.
--
--     [ Layout ][ Frame ][ Number ][ Text ]
--
--     Layout   [Direction] [Spacing (px)] / [Padding (px)] / [Container scale] [Container opacity]
--              [Size] / [Width (px)] [Height (px)]  (grayed while Size fits the content)
--              -- Element order --  a drag list, one row per element: handle, on/off tick, name; the
--              elements turned on first and only they drag
--     Frame    -- Border --      the composed border block (options-ui-§16), Show border first
--              -- Background --  [Show background], the background swatch and its color mode,
--                                [Band tint opacity]
--     Number   [Show number] [Format]  -- Font --  the composed Font block
--     Text     [Show text label] [Uppercase]  -- Font --  the composed Font block
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

local L = NS.L
local H = NS.Helpers
local V = NS.ContainerValues

local PAGE = "containers_display"
local LAYOUT, FRAME, NUMBER, TEXT = L["Layout"], L["Frame"], L["Number"], L["Text"]

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

-- ── Element order ───────────────────────────────────────────────────────────────────────────

local ELEMENT_NAMES = {
    indicator = L["Indicator"], number = L["Number"], text = L["Text label"], spells = L["Spell chips"],
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

NS.RegisterContainerSection(PAGE, L["Display"], {
    tooltip = L["How this container is laid out and framed, and its number and text."],
    afterGroup = { [LAYOUT] = renderOrder },
})
