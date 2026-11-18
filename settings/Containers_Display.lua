local _, NS = ...
-- settings/Containers_Display.lua — the Containers page's Display entry: how the selected container is
-- laid out and framed, and its number and text.
--
--     [ Layout ][ Frame ][ Number ][ Text ]
--
--     Layout   [Direction] [Spacing (px)] / [Padding (px)] / [Container scale] [Container opacity]
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

-- The border's style: "" is Solid (modules/Style.lua), offered first.
for _, row in ipairs(rows) do
    if row.path == "container.frame.border.texture" then
        row.values, row.emptyAs = V.MediaValues("border", "Solid", L["Solid"]), "Solid"
    end
end

NS.RegisterSchemaRows(NS.StampSelectionRows(V.ColorModeCompanion(rows)))

NS.RegisterContainerSection(PAGE, L["Display"], {
    tooltip = L["How this container is laid out and framed, and its number and text."],
})
