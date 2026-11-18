local _, NS = ...
-- settings/Containers_Visibility.lua — the Containers page's Visibility entry: when the selected
-- container shows (modules/Visibility.lua evaluates these on every unit, combat and reaction change).
--
--     [ Visibility ]
--
--     [In combat] [Reaction] / [Hide with no unit] [Out of combat opacity]
--
-- Inside General visibility (the General page > Master controls), which wraps every container.

local L = NS.L

local PAGE = "containers_visibility"
local GROUP = L["Visibility"]

local COMBAT = { any = L["Always"], ["in"] = L["Only in combat"], out = L["Only out of combat"] }
local COMBAT_SORT = { "any", "in", "out" }
local REACTION = { any = L["Any unit"], hostile = L["Hostile only"], friendly = L["Friendly only"] }
local REACTION_SORT = { "any", "hostile", "friendly" }

NS.RegisterSchemaRows(NS.StampSelectionRows({
    { path = "container.visibility.combat", page = PAGE, group = GROUP, order = 10, type = "string",
      values = COMBAT, sorting = COMBAT_SORT, label = L["Show"],
      desc = L["When this container shows. Inside General visibility (the General page > Master controls)."] },
    { path = "container.visibility.reaction", page = PAGE, group = GROUP, order = 20, type = "string",
      values = REACTION, sorting = REACTION_SORT, label = L["Reaction"],
      desc = L["Show this container only for a hostile unit, only for a friendly one, or for any."] },
    { path = "container.visibility.hideNoUnit", page = PAGE, group = GROUP, order = 30, type = "bool",
      label = L["Hide with no unit"],
      desc = L["Hide this container while its unit does not exist, instead of showing the unknown label."] },
    { path = "container.visibility.oocAlpha", page = PAGE, group = GROUP, order = 40, type = "number",
      min = 0, max = 1, step = 0.05, isPercent = true, label = L["Out of combat opacity"],
      desc = L["How opaque this container is out of combat."] .. " "
          .. L["Multiplied by Master opacity on the General page > Master controls."] },
}))

NS.RegisterContainerSection(PAGE, L["Visibility"], {
    tooltip = L["When this container shows: in or out of combat, by the unit's reaction, and with no unit."],
})
