local _, NS = ...
-- settings/BandSets.lua — the Band sets page: the shared band sets every container colors by.
--
--     band   [Band set v picker ]                 [ New band set ]
--     strip  [ General ][ Bands ]
--     General  [Name] [Match band by] / -- Unknown range -- [Unknown label] [Unknown color]
--              Used by: Target, Pet            [Duplicate band set] [Delete band set…]
--     Bands    -- Band 1: 0–5 MELEE --  [Up to (yards)] [Label] / [Frame color] [Text color] /
--                                       [Dot color] [Sound on enter] / [Remove band]
--              ...                      [Add band]
--
-- The General tab's rows are selection-relative, `bandSet.<field>` (settings/Schema.lua), so `/rm
-- get|set bandSet.matchBy` edits the band set the banner shows, through NS.BandSets.SetField. The
-- Bands tab is a host editor (options-ui-§13): a band is one of a list the player grows, which a path
-- cannot name, so its controls are path-less rows whose get and set reach NS.BandSets.SetBand,
-- SetBandSound, AddBand and RemoveBand. Every band-set write announces BANDSETS_CHANGED, and the page
-- redraws on the next frame (NS.RequestPanelRefresh), because moving one edge moves the next band.
--
-- THE BANDS ARE ORDERED BY DISTANCE, NOT BY HAND. modules/BandSets.lua keeps every set sorted by its
-- edges, contiguous from 0 and open-ended, so a band's place in the list is its `Up to` and nothing
-- else: the editor moves a band by moving its edge, and offers no reorder control.
--
-- THE BAND COLORS ARE A PALETTE (options-ui-§17): each identifies a band, not a player, so none takes
-- a class-color companion. Class color is the container's own Color from (the Containers page).
--
-- Both choices, and the Bands tab's rows being out of `/rm set`'s reach, are recorded as decided in the
-- design spec (5.6, "As built") and docs/ARCHITECTURE.md's Known Limitations.

local L = NS.L
local H = NS.Helpers
local print = NS.Print
local printf = NS.Printf

local PAGE = "bandsets"
local GENERAL, BANDS = L["General"], L["Bands"]

local MATCH = { max = L["Upper bound (farthest range)"], min = L["Lower bound (nearest range)"] }
local MATCH_SORT = { "max", "min" }

NS.RegisterSchemaRows(NS.StampSelectionRows({
    { path = "bandSet.name", page = PAGE, group = GENERAL, order = 10, type = "string",
      dialogControl = "EditBox", maxLetters = 40, label = L["Name"],
      desc = L["What this band set is called in the pickers. Press Enter to apply."],
      validate = function(v) return type(v) == "string" and v:match("%S") ~= nil end,
      onChange = function() NS.RequestPanelRefresh() end },
    { path = "bandSet.matchBy", page = PAGE, group = GENERAL, order = 20, type = "string",
      values = MATCH, sorting = MATCH_SORT, label = L["Match band by"],
      desc = L["Which end of a range reading picks the band: the farthest the unit may be, or the nearest."] },
    { path = "bandSet.unknown.label", page = PAGE, group = GENERAL, subgroup = L["Unknown range"], order = 30,
      type = "string", dialogControl = "EditBox", maxLetters = 12, label = L["Unknown label"],
      desc = L["What a container shows while the range cannot be read. An unknown range never counts as out of range."] },
    { path = "bandSet.unknown.color", page = PAGE, group = GENERAL, subgroup = L["Unknown range"], order = 40,
      type = "color", hasAlpha = false, paletteSwatch = true, label = L["Unknown color"],
      desc = L["The color a container takes while the range cannot be read."] },
}))

-- ---------------------------------------------------------------------------
-- The acts on the selected band set
-- ---------------------------------------------------------------------------

--- Select band set `id` and redraw every page.
function NS.ShowBandSet(id)
    if not NS.SelectBandSet(id) then return false end
    NS.RequestPanelRefresh()
    return true
end

--- Delete band set `id`: its containers move to the default set (modules/BandSets.lua), and the
--- selection moves to its neighbor. Answers the deleted name, or nil (an unknown id, the last set).
function NS.DeleteBandSet(id)
    local set = NS.BandSets.Get(id)
    if not set then return nil end
    local ids, index = NS.BandSets.List(), nil
    for i, other in ipairs(ids) do if other == id then index = i end end
    local name = set.name
    local _, selected = NS.SelectedBandSet()
    if not NS.BandSets.Delete(id) then return nil end
    if selected == id then NS.SelectBandSet(NS.NeighborAfterDelete(ids, index)) end
    NS.RequestPanelRefresh()
    return name
end

--- The names of the containers on set `id`, as one string, or nil when none uses it.
local function usedBy(id)
    local names = {}
    for _, cid in ipairs(NS.CM.List()) do
        local c = NS.CM.Get(cid)
        if c.bandSet == id or c.bandSetFriendly == id then names[#names + 1] = c.name end
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

StaticPopupDialogs["RANGEMASTER_DELETE_BANDSET"] = {
    text         = L["Delete the band set '%s'? The containers using it move to the default band set."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function(_, data)
        local name = data and NS.DeleteBandSet(data)
        if name then printf(L["Deleted band set '%s'."], name) end
    end,
}

local function doDelete()
    local set, id = NS.SelectedBandSet()
    if not id then return end
    if #NS.BandSets.List() <= 1 then return print(L["The last band set cannot be deleted."]) end
    local popup = StaticPopup_Show("RANGEMASTER_DELETE_BANDSET", tostring(set.name))
    if popup then popup.data = id end
end

local function doDuplicate()
    local _, id = NS.SelectedBandSet()
    local newId = id and NS.BandSets.Duplicate(id)
    if newId then NS.ShowBandSet(newId) end
end

local function afterGeneral(ctx)
    local _, id = NS.SelectedBandSet()
    if not id then return end
    local names = usedBy(id)
    H.TextRow(ctx, names and L["Used by: %s"]:format(names) or L["No container uses this band set."],
        { fontObject = "GameFontDisableSmall" })
    H.InlineButtonPair(ctx,
        { text = L["Duplicate band set"], tooltip = L["Make a copy of this band set to edit."], onClick = doDuplicate },
        { text = L["Delete band set\226\128\166"],
          tooltip = L["Delete this band set. The containers using it move to the default band set. Asks first."],
          onClick = doDelete })
end

-- ---------------------------------------------------------------------------
-- The Bands tab: the host editor
-- ---------------------------------------------------------------------------

--- The LibSharedMedia sounds, led by None ("" stores no sound).
local function soundValues()
    local lsm = H.LSMValues("sound")
    return function()
        local out = { [""] = L["None"] }
        for k, v in pairs(lsm() or {}) do out[k] = v end
        return out
    end
end
local SOUNDS = soundValues()

--- A band's far edge, as a slider between its start and the next band's far edge.
local function edgeItem(id, i, b, nextBand)
    local max = nextBand.to and (nextBand.to - 1) or math.max(100, b.from + 50)
    return {
        type = "number", label = L["Up to (yards)"], min = b.from + 1, max = max, step = 1,
        tooltip = L["Where this band ends. The next band starts here."],
        get = function() return NS.BandSets.Get(id).bands[i].to end,
        set = function(v) NS.BandSets.SetBand(id, i, "to", v) end,
    }
end

--- The open-ended last band's edge cell: nothing to set.
local function openEndItem()
    return { make = function(_, parent, rel)
        local w = NS.AceGUI:Create("Label")
        w:SetText(L["Up to: no limit (the last band is open-ended)"])
        w:SetRelativeWidth(rel or 0.5)
        parent:AddChild(w)
        return w
    end }
end

local function colorItem(id, i, field, label, tooltip)
    return {
        type = "color", label = label, hasAlpha = false, tooltip = tooltip, paletteSwatch = true,
        get = function() return NS.BandSets.Get(id).bands[i][field] end,
        set = function(v) NS.BandSets.SetBand(id, i, field, v) end,
    }
end

local function removeItem(id, i)
    return { make = function(_, parent, rel)
        local w = NS.AceGUI:Create("Button")
        w:SetText(L["Remove band"])
        w:SetRelativeWidth(rel or 0.5)
        w:SetCallback("OnClick", function()
            if not NS.BandSets.RemoveBand(id, i) then print(L["A band set keeps at least one band."]) end
        end)
        parent:AddChild(w)
        return w
    end }
end

--- One band's controls, two to a line.
local function bandItems(id, set, i)
    local b, nextBand = set.bands[i], set.bands[i + 1]
    return {
        nextBand and edgeItem(id, i, b, nextBand) or openEndItem(),
        { type = "string", dialogControl = "EditBox", maxLetters = 12, label = L["Label"],
          tooltip = L["The band's name, which the text label shows."],
          get = function() return NS.BandSets.Get(id).bands[i].label end,
          set = function(v) NS.BandSets.SetBand(id, i, "label", v) end },
        colorItem(id, i, "frameColor", L["Frame color"], L["The border and background color in this band, while Color from is Band color."]),
        colorItem(id, i, "textColor", L["Text color"], L["The number and label color in this band, while Color from is Band color."]),
        colorItem(id, i, "indicatorColor", L["Dot color"], L["The dot and spell chip color in this band, while Color from is Band color."]),
        { type = "string", dialogControl = "Ka0sMedia_Sound", values = SOUNDS, label = L["Sound on enter"],
          tooltip = L["Played when the unit enters this band, on containers with Play band sounds on."],
          get = function() return NS.BandSets.Get(id).bands[i].sound or "" end,
          set = function(v) NS.BandSets.SetBandSound(id, i, v ~= "" and v or nil) end },
        removeItem(id, i),
    }
end

--- One band's heading text: its place, its span and its label.
local function bandHeading(i, b)
    local span = b.to and ("%d\226\128\147%d"):format(b.from, b.to) or ("%d+"):format(b.from)
    return L["Band %d: %s yd %s"]:format(i, span, b.label)
end

local function renderBands(ctx)
    local set, id = NS.SelectedBandSet()
    if not set then return H.TextRow(ctx, L["No band set exists yet."]) end
    for i, b in ipairs(set.bands) do
        H.Section(ctx, bandHeading(i, b))
        H.RenderGrid(ctx, bandItems(id, set, i))
    end
    H.InlineButtonPair(ctx, {
        text = L["Add band"], tooltip = L["Split a new band off the front of the open-ended last band."],
        onClick = function() NS.BandSets.AddBand(id) end,
    }, nil)
    H.TextRow(ctx, L["Sounds play on entering a band, after it has held for 0.2 seconds, at most once a second, and never on the first band after the unit changes."],
        { fontObject = "GameFontDisableSmall" })
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function bandSetList()
    local list, order = {}, {}
    for _, id in ipairs(NS.BandSets.List()) do
        list[id] = NS.BandSets.Get(id).name
        order[#order + 1] = id
    end
    if order[1] then list[order[1]] = L["%s (default)"]:format(list[order[1]]) end
    return list, order
end

local function doNew()
    local id = NS.BandSets.Create(L["New band set"], "melee_ranged")
    if id then NS.ShowBandSet(id) end
end

local render

local OPTS = {
    tabs = { { key = BANDS, label = BANDS, tooltip = L["Each band's edge, label, colors and sound."],
               render = function(ctx) renderBands(ctx) end } },
    rerender = function(ctx) render(ctx) end,
}

function render(ctx)
    H.ClearScroll(ctx)
    local scroll = H.EnsureScroll(ctx)
    local _, id = NS.SelectedBandSet()
    local list, order = bandSetList()
    H.PageBanner(ctx, {
        label = L["Band set"], list = list, order = order, value = id,
        tooltip = L["Which band set this page edits. Band sets are shared: every container on one changes with it."],
        onSelect = function(v) if v ~= id then NS.ShowBandSet(v) end end,
        action = { text = L["New band set"], tooltip = L["Create a band set from Melee / Ranged, to edit."],
                   onClick = doNew },
    })
    H.RenderTabbedSchema(ctx, PAGE, { [GENERAL] = afterGeneral }, nil, OPTS)
    if scroll and scroll.DoLayout then scroll:DoLayout() end
end
NS.__renderBandSetsPage = function(ctx) return render(ctx) end
NS.__bandItems = bandItems

-- A band-set write from anywhere (this page, a preset, `/rm set bandSet.*`) redraws the pages on the
-- next frame: the band headings and the Containers page's band-set pickers all read it.
local target = NS.NewBusTarget and NS.NewBusTarget()
if target then target:RegisterMessage(NS.MSG.BANDSETS_CHANGED, function() NS.RequestPanelRefresh() end) end

local function build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
    local ctx = H.CreatePanel("RangeMasterBandSetsPanel", L["Band sets"], {
        pageKey         = PAGE,
        defaultsButton  = true,
        defaultsTooltip = L["Restore the selected band set's match rule and unknown label and color to their defaults. Its name and its bands are kept: Delete band set removes it whole."],
    })
    ctx.panel.defaultsOnClick = function() H.RestoreDefaults(PAGE, ctx) end
    H.SetRenderer(ctx, render)
    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, L["Band sets"])
end

NS.RegisterOptionsPage(PAGE, L["Band sets"], build)
