local _, NS = ...
-- settings/Containers_Display.lua — the Containers page's Display entry: how the selected container is
-- laid out and framed, and its number and text.
--
--     [ Layout ][ Frame ][ Number ][ Text ]
--
--     Layout   [Direction] [Spacing (px)] / [Padding (px)] / [Container scale] [Container opacity]
--              -- Element order --  a drag list, one row per element (an element turned off reads dimmed)
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

local ROW_H = 24
local ROW_STRIDE = ROW_H + 4   -- top of a row to the next one's: the library's drop arithmetic
local LABEL_GAP = 12           -- between the handle's gutter and the element's name
local GUTTER_FALLBACK = 30     -- the library's ROW_BOX.HANDLE_W, for a copy that has none

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
        row:Hide()
        row:ClearAllPoints()
        row:SetParent(attic())
        rowPool[#rowPool + 1] = row
    end
end

--- A row frame, from the free list or newly built, filling `parent`'s top.
local function acquireRow(parent, gutter)
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ROW_H)
        row.rmLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.rmLabel:SetPoint("LEFT", row, "LEFT", gutter + LABEL_GAP, 0)
        row.rmLabel:SetJustifyH("LEFT")
    end
    row:SetParent(parent)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    row:Show()
    return row
end

--- Move the selected container's element at `from` to `to`: one write through the order row.
local function moveElement(from, to)
    local order = {}
    for i, name in ipairs(currentOrder()) do order[i] = name end
    if not (order[from] and order[to]) then return end
    table.insert(order, to, table.remove(order, from))
    NS.SetByPath(ORDER_PATH, table.concat(order, ","))
    NS.RequestPanelRefresh()
end

local function newList()
    local W = widgets()
    if not W then return nil end
    return W.ReorderList({
        stride = ROW_STRIDE, onMove = moveElement, owner = NS.name,
        handleTooltip = L["Drag to reorder"],
    })
end

--- One element's row: an AceGUI slot the scroll lays out, holding a raw frame the list drags.
local function drawRow(ctx, scroll, list, gutter, c, name)
    local slot = NS.AceGUI:Create("SimpleGroup")
    slot:SetLayout(nil)
    slot:SetFullWidth(true)
    slot:SetHeight(ROW_STRIDE)
    scroll:AddChild(slot)
    local row = acquireRow(slot.frame or slot.content, gutter)
    local on = c.elements[name] and c.elements[name].enabled
    local text = on and ELEMENT_NAMES[name] or L["%s (off)"]:format(ELEMENT_NAMES[name])
    row.rmLabel:SetText(text)
    if NS.Skin and NS.Skin.Text then NS.Skin.Text(row.rmLabel, on and "accent" or "disabled", { panel = true }) end
    ctx.rmOrderRows[#ctx.rmOrderRows + 1] = row
    if list then list:AddRow(row, { dimmed = not on, ghostText = text, height = ROW_H }) end
end

--- The Layout tab's foot: the element order as a drag list.
local function renderOrder(ctx)
    local c = NS.SelectedContainer()
    local scroll = H.EnsureScroll(ctx)
    if not (c and scroll and NS.AceGUI) then return end
    H.Section(ctx, ORDER_LABEL)
    H.TextRow(ctx, L["Drag an element by its handle to change where it is drawn. An element turned off keeps its place for when it is turned on."],
        { fontObject = "GameFontDisableSmall" })
    local W, list = widgets(), newList()
    local gutter = (W and W.ROW_BOX and W.ROW_BOX.HANDLE_W) or GUTTER_FALLBACK
    ctx.rmOrderList, ctx.rmOrderRows = list, {}
    for _, name in ipairs(c.elements.order) do drawRow(ctx, scroll, list, gutter, c, name) end
    if list then list:Finish(scroll.content or scroll.frame) end
end

NS.RegisterContainerSection(PAGE, L["Display"], {
    tooltip = L["How this container is laid out and framed, and its number and text."],
    afterGroup = { [LAYOUT] = renderOrder },
})
