local _, NS = ...
-- settings/Containers_Indicator.lua — the Containers page's Indicator entry: the selected container's
-- shape indicator and its spell-range chips.
--
--     [ Indicator ][ Spell chips ]
--
--     Indicator    [Show indicator] [Shape] / [Size (px)] / [Indicator color] [Color from]
--     Spell chips  [Show spell chips] [Style] / [Size (px)]
--
-- The indicator's swatch and its color mode are composed (H.ColorPair; options-ui-§17), the companion
-- turned into the three-value color mode (NS.ContainerValues.ColorModeCompanion). Which spells the
-- chips show is seeded per client and class when a container is made (modules/ContainerManager.lua).

local L = NS.L
local H = NS.Helpers
local V = NS.ContainerValues

local PAGE = "containers_indicator"
local INDICATOR, SPELLS = L["Indicator"], L["Spell chips"]

local SHAPES = {
    dot = L["Dot"], ring = L["Ring"], square = L["Square"], diamond = L["Diamond"], triangle = L["Triangle"],
    bar = L["Bar (fills toward the band's far edge)"], icon = L["Spell icon"],
}
local SHAPES_SORT = { "dot", "ring", "square", "diamond", "triangle", "bar", "icon" }

local CHIP_STYLES = { chip = L["Chip (colored edge)"], icon = L["Icon only"] }
local CHIP_STYLES_SORT = { "chip", "icon" }

local rows = {
    { path = "container.elements.indicator.enabled", page = PAGE, group = INDICATOR, order = 10,
      type = "bool", label = L["Show indicator"], desc = L["Draw a shape colored by the current band."] },
    { path = "container.elements.indicator.shape", page = PAGE, group = INDICATOR, order = 20,
      type = "string", values = SHAPES, sorting = SHAPES_SORT, label = L["Shape"],
      desc = L["The indicator's shape. Spell icon shows the first spell chip's icon."] },
    { path = "container.elements.indicator.size", page = PAGE, group = INDICATOR, order = 30,
      type = "number", min = 4, max = 64, step = 1, startsLine = true, label = L["Size (px)"],
      desc = L["The indicator's width and height, in pixels."] },
}
for _, row in ipairs(H.ColorPair({
    prefix = "container.elements.indicator.", page = PAGE, group = INDICATOR, order = 40, key = "color",
    companionKey = "colorMode", label = L["Indicator color"], classColor = { source = "unit" },
})) do rows[#rows + 1] = row end

local SPELL_ROWS = {
    { path = "container.elements.spells.enabled", page = PAGE, group = SPELLS, order = 10, type = "bool",
      label = L["Show spell chips"],
      desc = L["Draw a chip per class spell, its edge lit while the unit is in that spell's range."] },
    { path = "container.elements.spells.style", page = PAGE, group = SPELLS, order = 20, type = "string",
      values = CHIP_STYLES, sorting = CHIP_STYLES_SORT, label = L["Style"],
      desc = L["A chip with a colored edge, or the icon alone, dimmed while out of range."] },
    { path = "container.elements.spells.size", page = PAGE, group = SPELLS, order = 30, type = "number",
      min = 10, max = 48, step = 1, label = L["Size (px)"], desc = L["Each chip's width and height, in pixels."] },
}
for _, row in ipairs(SPELL_ROWS) do rows[#rows + 1] = row end

NS.RegisterSchemaRows(NS.StampSelectionRows(V.ColorModeCompanion(rows)))

NS.RegisterContainerSection(PAGE, L["Indicator"], {
    tooltip = L["The shape indicator and the spell-range chips."],
})
