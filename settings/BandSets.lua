local _, NS = ...
-- settings/BandSets.lua — the Band sets page: the shared band sets every container colors by.
--
--     band   [Band set v picker ]                 [ New band set ]
--     strip  [ General ][ Bands ]
--     General  [Name] [Match band by] / -- Unknown range -- [Unknown label] [Unknown color]
--              Used by: Target, Pet            [Duplicate band set] [Delete band set…]
--     Bands    -- Band 1: 0–5 yd MELEE (Spell: Melee) --
--                  [Defined by] [Role] / [Spell IDs] [Fallback (yards)] /
--                  Now: Raptor Strike (2973), melee range   (the read-out; a spell band only)
--                  [Label] [Frame color] / [Text color] [Dot color] / [Sound on enter] [Remove band]
--              -- Band 2: 5–8 yd DEAD (Dead zone) --  [Defined by] [Fallback (yards)] / [Label] ...
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
-- A BAND'S RULE (dynamic-bands plan D5): Defined by picks Yards (no rule), Spell, Dead zone or Beyond
-- the last spell band, written through NS.BandSets.SetBandRule. A spell band also takes a role and an
-- optional list of spell IDs in place of the class's anchors, and shows a read-out of the anchor in
-- use (NS.Range.AnchorFor) with the range the client reports, or the yards it falls back to when none
-- is learned. On a band with a rule the edge slider is its Fallback (yards). ANCHORS_CHANGED redraws
-- the page with BANDSETS_CHANGED, so the read-out follows a talent, form or level change.
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

--- A band's far edge, as a slider between its start and the next band's far edge. On a band with a
--- rule the yards are its fallback (used while its spell cannot answer), and the label says so.
local function edgeItem(id, i, b, nextBand)
    local max = nextBand.to and (nextBand.to - 1) or math.max(100, b.from + 50)
    local fallback = type(b.rule) == "table"
    return {
        type = "number", label = fallback and L["Fallback (yards)"] or L["Up to (yards)"],
        min = b.from + 1, max = max, step = 1,
        tooltip = fallback
            and L["Where this band ends while its rule cannot decide (a spell not learned, unusable or with no answer), and for its label. The next band starts here."]
            or L["Where this band ends. The next band starts here."],
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

-- ── the band's rule (dynamic-bands plan D5) ──────────────────────────────────────────────────

local DEFINED_BY = { yards = L["Yards"], spell = L["Spell"], gap = L["Dead zone"],
    beyond = L["Beyond the last spell band"] }
local DEFINED_BY_SORT = { "yards", "spell", "gap", "beyond" }
local ROLES = { melee = L["Melee"], ranged = L["Ranged"], friendly = L["Friendly"] }
local ROLES_SORT = { "melee", "ranged", "friendly" }

--- The band's rule type as Defined by reads it: "yards" for none, or for one Resolve cannot read (an
--- unknown type, a spell rule whose role is not one of the three).
local function ruleType(b)
    local r = b.rule
    if type(r) ~= "table" or r.type == "yards" or not DEFINED_BY[r.type] then return "yards" end
    if r.type == "spell" and not ROLES[r.role] then return "yards" end
    return r.type
end

--- A band's span in yards, "0–5" or "40+".
local function spanText(b)
    return b.to and ("%d\226\128\147%d"):format(b.from, b.to) or ("%d+"):format(b.from)
end

--- The spell band's read-out: the anchor in use and the range the client reports for it, or the
--- fallback yards when nothing is learned. Nil for a band that is not a spell band.
local function readout(b)
    if ruleType(b) ~= "spell" then return nil end
    local a = NS.Range.AnchorFor(b.rule.role, b.rule.spells)
    if not a then return L["Not learned: using %s yd"]:format(spanText(b)) end
    local name = a.name and L["%s (%d)"]:format(a.name, a.id) or L["spell %d"]:format(a.id)
    local range
    if type(a.maxRange) ~= "number" then
        range = L["range not reported"]
    elseif a.maxRange <= 0 then
        range = L["melee range"]
    else
        range = L["%s yd"]:format(("%d\226\128\147%d"):format(a.minRange or 0, a.maxRange))
    end
    return L["Now: %s, %s"]:format(name, range)
end
NS.__bandReadout = readout

--- Write band `i`'s Defined by: a spell band keeps its role and list, and a new one takes melee in
--- the first band and ranged elsewhere. Yards clears the rule; the band's yards never move.
local function setDefinedBy(id, i, v)
    local b = NS.BandSets.Get(id).bands[i]
    if v == "yards" then return NS.BandSets.SetBandRule(id, i, nil) end
    if v ~= "spell" then return NS.BandSets.SetBandRule(id, i, { type = v }) end
    if ruleType(b) == "spell" then return true end
    return NS.BandSets.SetBandRule(id, i, { type = "spell", role = i == 1 and "melee" or "ranged" })
end

--- The spell IDs in `text` ("3044, 14281"), nil for none, or false when a part is not a whole ID.
local function parseIds(text)
    local ids = {}
    for part in tostring(text or ""):gmatch("[^,%s]+") do
        local n = tonumber(part)
        if not n or n < 1 or n % 1 ~= 0 then return false end
        ids[#ids + 1] = n
    end
    if #ids == 0 then return nil end
    return ids
end

local function definedByItem(id, i)
    return {
        type = "string", values = DEFINED_BY, sorting = DEFINED_BY_SORT, label = L["Defined by"],
        tooltip = L["What puts the unit in this band. Yards: its range reading. Spell: a spell of the role saying the unit is in range, which follows talents, gear and auras. Dead zone: too close for the ranged spell and too far for melee. Beyond the last spell band: every spell band's spell says out of range."],
        get = function() return ruleType(NS.BandSets.Get(id).bands[i]) end,
        set = function(v) setDefinedBy(id, i, v) end,
    }
end

local function roleItem(id, i)
    return {
        type = "string", values = ROLES, sorting = ROLES_SORT, label = L["Role"],
        tooltip = L["Which of your class's spells this band asks: a melee strike, a ranged attack, or a spell cast on friends."],
        get = function() return NS.BandSets.Get(id).bands[i].rule.role end,
        set = function(v)
            local r = NS.BandSets.Get(id).bands[i].rule
            NS.BandSets.SetBandRule(id, i, { type = "spell", role = v, spells = r.spells })
        end,
    }
end

local function spellIdsItem(id, i)
    return {
        type = "string", dialogControl = "EditBox", maxLetters = 80, label = L["Spell IDs"],
        tooltip = L["Spells this band asks in place of your class's, by ID, separated by commas; the first one you know is used. Empty: your class's spells for the role. Press Enter to apply."],
        get = function()
            local spells = NS.BandSets.Get(id).bands[i].rule.spells
            if type(spells) ~= "table" then return "" end
            local parts = {}
            for k, v in ipairs(spells) do parts[k] = tostring(v) end
            return table.concat(parts, ", ")
        end,
        set = function(v)
            local ids = parseIds(v)
            if ids == false then return print(L["Spell IDs are whole numbers, separated by commas."]) end
            local r = NS.BandSets.Get(id).bands[i].rule
            NS.BandSets.SetBandRule(id, i, { type = "spell", role = r.role, spells = ids })
        end,
    }
end

--- The read-out, dim on a line of its own (a note row: no path, no value).
local function readoutItem(b)
    return { type = "note", text = readout(b) or "" }
end

--- The controls every band has after its yards.
local function bandTail(id, i)
    return {
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

--- One band's controls, two to a line: Defined by first, then (a spell band) its role, its spell
--- override and the read-out, then the yards, the label, the colors, the sound and Remove.
local function bandItems(id, set, i)
    local b, nextBand = set.bands[i], set.bands[i + 1]
    local items = { definedByItem(id, i) }
    local spell = ruleType(b) == "spell"
    if spell then
        items[#items + 1] = roleItem(id, i)
        items[#items + 1] = spellIdsItem(id, i)
    end
    items[#items + 1] = nextBand and edgeItem(id, i, b, nextBand) or openEndItem()
    if spell then items[#items + 1] = readoutItem(b) end
    for _, item in ipairs(bandTail(id, i)) do items[#items + 1] = item end
    return items
end

--- One band's heading text: its place, its span, its label and, on a band with a rule, the rule.
local function bandHeading(i, b)
    local text = L["Band %d: %s yd %s"]:format(i, spanText(b), b.label)
    local kind = ruleType(b)
    if kind == "yards" then return text end
    local rule = kind == "spell" and L["Spell: %s"]:format(ROLES[b.rule.role] or tostring(b.rule.role))
        or DEFINED_BY[kind]
    return L["%s (%s)"]:format(text, rule)
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
    tabs = { { key = BANDS, label = BANDS, tooltip = L["Each band's rule, edge, label, colors and sound."],
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
-- A rebuild that moved an anchor (ANCHORS_CHANGED, modules/Range.lua) redraws them too: a spell
-- band's read-out names the anchor in use and the range the client reports for it.
if target then
    target:RegisterMessage(NS.MSG.BANDSETS_CHANGED, function() NS.RequestPanelRefresh() end)
    target:RegisterMessage(NS.MSG.ANCHORS_CHANGED, function() NS.RequestPanelRefresh() end)
end

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
