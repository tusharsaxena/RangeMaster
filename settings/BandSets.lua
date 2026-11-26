local _, NS = ...
-- settings/BandSets.lua — the Band sets page: the shared band sets every container colors by.
--
--     header [Band set v picker      ] [New…] [Duplicate] [Copy bands from…] [Delete…]
--            From the Paladin preset · modified (band 2 label)     [Restore Paladin preset…]
--     strip  [ General ][ Bands ]
--     General  [Name] [Match band by] / -- Unknown range -- [Unknown label] [Unknown color]
--              Used by: Target, Pet
--     Bands    +------------------+  -- Band 1: 0–5 yd MELEE (Spell: Melee) --
--              | # 1 MELEE · 0–5 yd |  [Defined by] [Role] / [Spell IDs] [Fallback (yards)] /
--              | # 2 DEAD · 5–8 yd  |  Now: Raptor Strike (2973), melee range   (a spell band only)
--              | # 3 CAST · 8–40 yd |  [Label] [Frame color] / [Text color] [Dot color] /
--              | # 4 OOR · 40+ yd   |  [Sound on enter]
--              +------------------+
--              [Add band] [Remove band]
--              Sounds play on entering a band, ...   (the note, dim)
--
-- THE BAND SET MANAGER (RangeMaster#21: docs/superpowers/specs/2026-11-25-band-set-manager-design.md,
-- the owner's six asks and the approved mockup; docs/settings-panel.md describes the page as built).
--
-- THE HEADER is O.PageHeader's block, not O.PageBanner: the picker and four
-- page-wide acts are more than the banner's three, and the origin line sits under them. Its acts
-- apply to the set whole, so they sit above the strip (options-ui-§14) and none is under General.
-- Delete is disabled on the last set. The block is one AceGUI SimpleGroup with a Flow layout,
-- parented to the header's frame by hand (QuickComms' band, settings/Groups.lua: the shape known to
-- draw), and the last render's block is released only after this render's is built.
--
-- THE PICKER IS GROUPED: "Your band sets" (the default first, "(default)"; a set that differs from
-- its preset, "modified"), "Shipped presets · Classes" (every class preset this client has, in its
-- class color, yours tagged "your class") and "Shipped presets · General" (each in a color of its own,
-- none a class's: NS.Constants.PRESET_COLORS, R5-RM-03). The group names are
-- disabled rows (AceGUI's SetItemDisabled), so only a set or a preset can be chosen, and each draws
-- larger, flush left, on a band of the heading color (R5-RM-01, dressHeaders). A preset's key
-- in the list is "preset:<key>"; choosing one VIEWS it (NS.ViewPreset, settings/Schema.lua).
--
-- THE ORIGIN LINE: a set made from a preset (`set.origin`, modules/BandSets.lua) says so, and
-- what differs when it does, beside Restore <Preset> preset…, enabled only while it differs. A
-- preset VIEWED shows instead that it is read-only, with Use this preset… (the New dialog, prefilled)
-- and Copy into a set of mine… (Copy bands from, the preset as the source). While a preset is viewed
-- both tabs show its values with every control disabled, Duplicate, Copy bands from and Delete are
-- disabled, and `/rm set bandSet.*` is refused. The three dialogs (New…, Copy bands from…, Restore
-- <Preset> preset…) and the Undo after a copy or a restore are settings/BandSetDialogs.lua's
-- (NS.ShowNewBandSetDialog, NS.ShowCopyBandsDialog, NS.ShowRestoreBandSetDialog, NS.UndoBandSets);
-- this file reaches them at click time and hands them its preset names through NS.BandSetsPage.
--
-- THE BANDS TAB IS A SIDE-TAB GROUP (O.SideTabs, the library's rail look inside the content): one
-- entry per band, "<place> <label> · <span> yd" led by a chip of its frame color (#), and beside it
-- only the selected band's heading and controls. The rail is the second level under the page's one
-- strip (options-ui-§13: one tab divided by like subjects, in the scroll; no third level). The band
-- selected is session state, NS.State.selectedBand = { set, index }, never persisted: it survives a
-- redraw, Add band selects the new band, Remove band its neighbor (the next, else the one before),
-- an index the set no longer has clamps to the last band, and another band set opens on band 1. An
-- edge cannot re-sort the bands from here (its slider stops short of both neighbors), so an edge
-- change keeps the band selected by its place. Add band and Remove band share one row under the rail
-- (RangeMaster#21: side by side), Remove band acting on the selected band and disabled while the set
-- has one band; neither is among the band's own controls.
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
-- the last spell band, written through NS.BandSets.SetBandRule. A spell band also takes a role (melee,
-- ranged, friendly or a class's range tier, "10 yd tier": core/Constants.lua TIER_ROLES) and an
-- optional list of spell IDs in place of the class's anchors, and shows a read-out of the anchor in
-- use (NS.Range.AnchorFor) with the range the client reports, or the yards it falls back to when none
-- is learned. On a band with a rule the edge slider is its Fallback (yards). ANCHORS_CHANGED redraws
-- the page with BANDSETS_CHANGED, so the read-out follows a talent, form or level change.
--
-- THE BAND COLORS ARE A PALETTE (options-ui-§17): each identifies a band, not a player, so none takes
-- a class-color companion. Class color is the container's own Color from (the Containers page).
--
-- Both choices, and the Bands tab's rows being out of `/rm set`'s reach, are recorded as decided in the
-- design spec (5.6, "As built") and docs/ARCHITECTURE.md's Known Limitations, as are the band set
-- manager's limits (an origin guessed by name, no sync to a changed preset, the Undo a verb).

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

--- The Used by line for set `id`: the containers on it for this character, then how many other
--- characters pick it on this profile (BSC-REV: a delete clears their picks too), or nil when none.
local function usedBy(id)
    local Choice, names = NS.BandSetChoice, {}
    for _, cid in ipairs(NS.CM.List()) do
        local c = NS.CM.Get(cid)
        if Choice.Hostile(cid, c) == id or Choice.Friendly(cid, c) == id then names[#names + 1] = c.name end
    end
    local others = Choice.OthersUsing(id)
    if others > 0 then names[#names + 1] = L["%d other character(s)"]:format(others) end
    if #names == 0 then return nil end
    return L["Used by: %s"]:format(table.concat(names, ", "))
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
    H.TextRow(ctx, names or L["No container uses this band set."],
        { fontObject = "GameFontDisableSmall" })
end

-- ---------------------------------------------------------------------------
-- The Bands tab: the host editor
-- ---------------------------------------------------------------------------

-- ── the set the page shows: one of the player's, or a preset viewed read-only ──────────────────

-- A viewed preset's id on this page: a string no stored set has (stored ids are numbers), so a
-- writer handed it (NS.BandSets.SetBand and the rest) finds no set and refuses.
local VIEW_PREFIX = "preset:"
local viewCache   -- { key, set }: the viewed preset, built once per key (a preset never changes)

--- The preset being viewed, as a set, and its page id; nil while one of the player's sets is shown.
local function viewedSet()
    local key = NS.ViewedPreset()
    if not key then
        viewCache = nil
        return nil
    end
    if not (viewCache and viewCache.key == key) then viewCache = { key = key, set = NS.BandSets.PresetSet(key) } end
    return viewCache.set, VIEW_PREFIX .. key
end

--- The set page id `id` names: a stored set by number, the viewed preset by its string.
local function setOf(id)
    if type(id) ~= "string" then return NS.BandSets.Get(id) end
    local set, viewId = viewedSet()
    if viewId == id then return set end
    return nil
end

--- The set the page shows, and its page id: the viewed preset, else the selected set.
local function shownSet()
    local set, id = viewedSet()
    if set then return set, id end
    return NS.SelectedBandSet()
end

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
        get = function() return setOf(id).bands[i].to end,
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
        get = function() return setOf(id).bands[i][field] end,
        set = function(v) NS.BandSets.SetBand(id, i, field, v) end,
    }
end

-- ── the band selected (session state; see the header) ────────────────────────────────────────

--- Select band `index` of set `id` on the Bands tab.
local function selectBand(id, index)
    NS.State.selectedBand = { set = id, index = index }
end

--- The band of `set` (id `id`) the Bands tab shows: the one selected while it is this set's and the
--- set still has it, clamped to the last band, and band 1 for a set just switched to.
local function selectedBand(id, set)
    local sel = NS.State.selectedBand
    if not (type(sel) == "table" and sel.set == id and type(sel.index) == "number") then
        selectBand(id, 1)
        return 1
    end
    local n = #set.bands
    local index = math.max(1, math.min(sel.index, n))
    if index ~= sel.index then selectBand(id, index) end
    return index
end

--- Remove band `i` of set `id`; its neighbor takes the selection (the band after it, which now has
--- its place, else the one before it).
local function removeBand(id, i)
    if not NS.BandSets.RemoveBand(id, i) then return print(L["A band set keeps at least one band."]) end
    selectBand(id, math.min(i, #setOf(id).bands))
end

--- Add a band to set `id` and select it.
local function addBand(id)
    local index = NS.BandSets.AddBand(id)
    if index then selectBand(id, index) end
end

-- ── the band's rule (dynamic-bands plan D5) ──────────────────────────────────────────────────

local DEFINED_BY = { yards = L["Yards"], spell = L["Spell"], gap = L["Dead zone"],
    beyond = L["Beyond the last spell band"] }
local DEFINED_BY_SORT = { "yards", "spell", "gap", "beyond" }
local ROLES = { melee = L["Melee"], ranged = L["Ranged"], friendly = L["Friendly"] }
local ROLES_SORT = { "melee", "ranged", "friendly" }
-- Then the tier roles (RangeMaster#20), nearest first: "10 yd tier" is the class's 10 yd spells.
for _, role in ipairs(NS.Constants.TIER_ROLES) do
    ROLES[role] = L["%d yd tier"]:format(NS.Constants.TIER_YARDS[role])
    ROLES_SORT[#ROLES_SORT + 1] = role
end

--- The band's rule type as Defined by reads it: "yards" for none, or for one Resolve cannot read (an
--- unknown type, a spell rule whose role is not one of ROLES).
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
    local b = setOf(id).bands[i]
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
        get = function() return ruleType(setOf(id).bands[i]) end,
        set = function(v) setDefinedBy(id, i, v) end,
    }
end

local function roleItem(id, i)
    return {
        type = "string", values = ROLES, sorting = ROLES_SORT, label = L["Role"],
        tooltip = L["Which of your class's spells this band asks: a melee strike, a ranged attack, a spell cast on friends, or a range tier, the class's spells that reach that far (a paladin's 10 yd tier is Hammer of Justice). A class with no spell for the tier uses the band's yards."],
        get = function() return setOf(id).bands[i].rule.role end,
        set = function(v)
            local r = setOf(id).bands[i].rule
            NS.BandSets.SetBandRule(id, i, { type = "spell", role = v, spells = r.spells })
        end,
    }
end

local function spellIdsItem(id, i)
    return {
        type = "string", dialogControl = "EditBox", maxLetters = 80, label = L["Spell IDs"],
        tooltip = L["Spells this band asks in place of your class's, by ID, separated by commas; the first one you know is used. Empty: your class's spells for the role. Press Enter to apply."],
        get = function()
            local spells = setOf(id).bands[i].rule.spells
            if type(spells) ~= "table" then return "" end
            local parts = {}
            for k, v in ipairs(spells) do parts[k] = tostring(v) end
            return table.concat(parts, ", ")
        end,
        set = function(v)
            local ids = parseIds(v)
            if ids == false then return print(L["Spell IDs are whole numbers, separated by commas."]) end
            local r = setOf(id).bands[i].rule
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
          get = function() return setOf(id).bands[i].label end,
          set = function(v) NS.BandSets.SetBand(id, i, "label", v) end },
        colorItem(id, i, "frameColor", L["Frame color"], L["The border and background color in this band, while Color from is Band color."]),
        colorItem(id, i, "textColor", L["Text color"], L["The number and label color in this band, while Color from is Band color."]),
        colorItem(id, i, "indicatorColor", L["Dot color"], L["The dot and spell chip color in this band, while Color from is Band color."]),
        { type = "string", dialogControl = "Ka0sMedia_Sound", values = SOUNDS, label = L["Sound on enter"],
          tooltip = L["Played when the unit enters this band, on containers with Play band sounds on."],
          get = function() return setOf(id).bands[i].sound or "" end,
          set = function(v) NS.BandSets.SetBandSound(id, i, v ~= "" and v or nil) end },
    }
end

--- One band's controls, two to a line: Defined by first, then (a spell band) its role, its spell
--- override and the read-out, then the yards, the label, the colors and the sound.
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

-- ── the rail ─────────────────────────────────────────────────────────────────────────────────

-- Wide enough for "12 OUT OF RANGE · 40+ yd" (a label holds 12 letters) beside its chip.
local RAIL_WIDTH = 170
local CHIP = "|TInterface\\Buttons\\WHITE8X8:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t "

--- A chip of color `c` ({ r, g, b }), as a texture escape: it keeps the entry's own gold and white,
--- so the selection still reads the way every rail's does.
local function chip(c)
    if type(c) ~= "table" then return "" end
    local function byte(v) return math.floor(math.max(0, math.min(1, tonumber(v) or 1)) * 255 + 0.5) end
    return CHIP:format(byte(c.r), byte(c.g), byte(c.b))
end

--- Band `i`'s rail entry: "1 MELEE · 0–5 yd", led by its frame color, and its heading as the tooltip.
local function railEntry(i, b)
    local text = b.label ~= "" and L["%d %s \194\183 %s yd"]:format(i, b.label, spanText(b))
        or L["%d \194\183 %s yd"]:format(i, spanText(b))
    return { key = i, label = chip(b.frameColor) .. text, tooltip = bandHeading(i, b) }
end

local railButtons   -- the entries the last draw made (a test seam)

local function renderBands(ctx)
    local set, id = shownSet()
    if not set then return H.TextRow(ctx, L["No band set exists yet."]) end
    local entries = {}
    for i, b in ipairs(set.bands) do entries[i] = railEntry(i, b) end
    railButtons = H.SideTabs(ctx, {
        entries = entries, value = selectedBand(id, set), width = RAIL_WIDTH,
        onSelect = function(i) selectBand(id, i) end,
        render = function(c, i)
            local b = setOf(id).bands[i]
            H.Section(c, bandHeading(i, b))
            H.RenderGrid(c, bandItems(id, setOf(id), i))
        end,
    })
    local pair = H.InlineButtonPair(ctx, {
        text = L["Add band"], tooltip = L["Split a new band off the front of the open-ended last band, and select it."],
        onClick = function() addBand(id) end,
    }, {
        text = L["Remove band"], tooltip = L["Remove the selected band. The band after it starts where it did. A band set keeps at least one band."],
        onClick = function() removeBand(id, selectedBand(id, setOf(id))) end,
    })
    -- Remove band is disabled while the set has one band (a viewed preset's page is drawn disabled whole).
    local remove = pair and pair.children and pair.children[2]
    if remove and #set.bands <= 1 then remove:SetDisabled(true) end
    H.TextRow(ctx, L["Sounds play on entering a band, after it has held for 0.2 seconds, at most once a second, and never on the first band after the unit changes."],
        { fontObject = "GameFontDisableSmall" })
end

-- ---------------------------------------------------------------------------
-- The header: the picker, the acts, the origin line
-- ---------------------------------------------------------------------------

local HEADER_KEY = "header:"

--- A preset's display name ("Paladin"), or its key when it has none.
local function presetName(key)
    local p = NS.BandSetPresets[key]
    return type(p) == "table" and p.name or tostring(key)
end

--- `text` in color r, g, b (0-1) as an escape, or plain when the color is not three numbers.
local function colored(text, r, g, b)
    if not (type(r) == "number" and type(g) == "number" and type(b) == "number") then return text end
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return ("|cff%02x%02x%02x%s|r"):format(byte(r), byte(g), byte(b), text)
end

--- A class preset's name in its class color (RAID_CLASS_COLORS), or plain when the client has none.
local function classColored(key, text)
    local c = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS[key:upper()] or nil
    if type(c) ~= "table" then return text end
    return colored(text, c.r, c.g, c.b)
end

--- The player's own class preset key ("paladin"), or nil.
local function yourClassKey()
    local classFile = NS.Compat.PlayerClass()
    return type(classFile) == "string" and classFile:lower() or nil
end

--- Add one disabled group row and answer its key.
local function addHeader(list, order, headers, name, text)
    local key = HEADER_KEY .. name
    list[key], order[#order + 1] = colored(text, NS.Skin.Color("text.heading")), key
    headers[#headers + 1] = key
end

-- A group row's look in the open list (R5-RM-01; the owner, round 5: "Make the category headers more
-- obvious (larger font, background color, etc)"): its text HEADER_GROW points larger than a set's,
-- flush left where a set's check sits, on a band of the heading color at HEADER_BAND_ALPHA. AceGUI
-- pools the pull-out's items for every dropdown in the client, so the dress is undone on the item's
-- next release (its own OnRelease, chained once, as LibKa0s's Skin:OnRelease chains a widget's).
local HEADER_GROW, HEADER_BAND_ALPHA = 3, 0.22
local HEADER_TEXT_X, STOCK_TEXT_X = 6, 18   -- AceGUI's ItemBase lays the text 18 px in, past the check

--- Put pull-out item `item` back as AceGUI made it: its font, its inset, its band hidden.
local function undressHeader(item)
    local st = rawget(item, "rmHeader")
    if not st then return end
    item.rmHeader = nil
    if st.font[1] then item.text:SetFont(st.font[1], st.font[2], st.font[3]) end
    item.text:SetPoint("TOPLEFT", item.frame, "TOPLEFT", STOCK_TEXT_X, 0)
    if st.band then st.band:Hide() end
end

--- Dress pull-out item `item` as a group row, and chain its undress onto its next release.
local function dressHeader(item, r, g, b)
    if rawget(item, "rmHeader") then return end
    local frame, fs = item.frame, item.text
    local path, size, flags = fs:GetFont()
    local band = frame.rmHeaderBand
    if not band then
        band = frame:CreateTexture(nil, "BACKGROUND")
        band:SetAllPoints()
        frame.rmHeaderBand = band
    end
    band:SetColorTexture(r, g, b, HEADER_BAND_ALPHA)
    band:Show()
    item.rmHeader = { font = { path, size, flags }, band = band }
    if path and type(size) == "number" then fs:SetFont(path, size + HEADER_GROW, flags) end
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", HEADER_TEXT_X, 0)
    local had = rawget(item, "OnRelease")
    item.OnRelease = function(self, ...)
        rawset(self, "OnRelease", had)
        -- AceGUI:Release calls OnRelease raw: a failed undress must never keep the pooled item from
        -- its own release, which every other addon's dropdown relies on (R5-REV).
        local ok, err = pcall(undressHeader, self)
        if not ok then print(tostring(err)) end
        local orig = self.OnRelease
        if type(orig) == "function" then return orig(self, ...) end
    end
end

--- Dress the group rows of dropdown `dd`'s pull-out (its items exist once SetList has run). Answers
--- how many it dressed; none without a pull-out (the test kit's Dropdown has none).
local function dressHeaders(dd)
    local po = type(dd) == "table" and dd.pullout
    if not (type(po) == "table" and type(po.IterateItems) == "function") then return 0 end
    local r, g, b = NS.Skin.Color("text.heading")
    if type(r) ~= "number" then r, g, b = 1, 0.82, 0 end
    local n = 0
    for _, item in po:IterateItems() do
        local ud = type(item) == "table" and item.userdata
        local v = type(ud) == "table" and ud.value
        if type(v) == "string" and v:find(HEADER_KEY, 1, true) == 1 then
            dressHeader(item, r, g, b)
            n = n + 1
        end
    end
    return n
end
NS.__dressBandSetHeaders = dressHeaders

--- Whether preset key `origin` is a class's, on either client (BY_CLIENT), so a Retail class's set
--- opened on WoW Forever still counts; classColored leaves it plain where the client has no color.
local function fromClass(origin)
    return type(origin) == "string" and NS.BandSetPresets.BY_CLIENT[origin:upper()] ~= nil
end

--- The player's sets into `list` and `order`, all but `except`, in order: this character's default
--- (its class set, else the first that is no other class's; modules/BandSetChoice.lua, spec C5, C10), "(default)"; a
--- set that differs from its preset, "modified". A set made from a class preset reads in that class's
--- color, renamed or modified (its `origin`; R5-RM-02, the owner, round 5: "Color code your band sets
--- which are spawned from a class reset by that class color"); any other set stays plain. Answers how
--- many it added.
local function addOwnSets(list, order, except)
    local n = 0
    local default = NS.BandSetChoice.CharacterDefaultId()
    for _, id in ipairs(NS.BandSets.List()) do
        if id ~= except then
            local set = NS.BandSets.Get(id)
            local text = set.name
            if fromClass(set.origin) then text = classColored(set.origin, text) end
            if id == default then text = L["%s (default)"]:format(text) end
            if NS.BandSets.IsModified(id) then text = L["%s \194\183 modified"]:format(text) end
            list[id], order[#order + 1], n = text, id, n + 1
        end
    end
    return n
end

--- A general preset's name in its own color (NS.Constants.PRESET_COLORS, R5-RM-03), or plain.
local function generalColored(key, text)
    local hex = NS.Constants.PRESET_COLORS[key]
    if not hex then return text end
    local c = NS.Constants.HexColor(hex)
    return colored(text, c.r, c.g, c.b)
end

--- Every shipped preset into `list` and `order` as "preset:<key>", under two group rows: the class
--- presets in their class colors, yours tagged "your class", then the general ones, each in its own
--- color.
local function addPresets(list, order, headers)
    local keys, mine = NS.BandSets.PresetKeys(), yourClassKey()
    addHeader(list, order, headers, "classes", L["Shipped presets \194\183 Classes"])
    for _, key in ipairs(keys.classes) do
        local text = classColored(key, presetName(key))
        if key == mine then text = L["%s (your class)"]:format(text) end
        list[VIEW_PREFIX .. key], order[#order + 1] = text, VIEW_PREFIX .. key
    end
    addHeader(list, order, headers, "general", L["Shipped presets \194\183 General"])
    for _, key in ipairs(keys.general) do
        list[VIEW_PREFIX .. key], order[#order + 1] = generalColored(key, presetName(key)), VIEW_PREFIX .. key
    end
end

--- The picker's entries: three groups, each led by a disabled row. Answers the list, its order and
--- the group rows' keys.
local function pickerEntries()
    local list, order, headers = {}, {}, {}
    addHeader(list, order, headers, "mine", L["Your band sets"])
    addOwnSets(list, order)
    addPresets(list, order, headers)
    return list, order, headers
end
NS.__bandSetPickerEntries = pickerEntries

--- A picker choice: one of the player's sets is selected (ending a view), a preset is viewed, and a
--- group row (never choosable in the client) changes nothing.
local function choose(v)
    if type(v) == "number" then return NS.ShowBandSet(v) end
    local key = type(v) == "string" and v:match("^" .. VIEW_PREFIX .. "(.+)$")
    if key and NS.ViewPreset(key) then NS.RequestPanelRefresh() end
end
NS.__chooseBandSet = choose

-- What each Diff field reads as in the origin line's summary.
local DIFF_WORDS = {
    to = L["edge"], label = L["label"], rule = L["rule"], frameColor = L["frame color"],
    textColor = L["text color"], indicatorColor = L["dot color"], matchBy = L["match rule"],
    ["unknown.label"] = L["unknown label"], ["unknown.color"] = L["unknown color"], bands = L["band count"],
}

--- The origin line's short summary of `diff`: the first two differences, then how many more.
local function diffSummary(diff)
    local parts = {}
    for i = 1, math.min(2, #diff) do
        local e = diff[i]
        local word = DIFF_WORDS[e.field] or tostring(e.field)
        parts[i] = e.band and L["band %d %s"]:format(e.band, word) or word
    end
    local text = table.concat(parts, ", ")
    if #diff > 2 then text = L["%s and %d more"]:format(text, #diff - 2) end
    return text
end

--- Make stored set `id` this character's band set on the active profile ("Use for this character",
--- R4-RM-01: every container without its own pick follows it). Answers whether it was stored.
function NS.UseBandSetForCharacter(id)
    local set = NS.BandSets.Get(id)
    if not (set and NS.BandSetChoice.Assign(id)) then return false end
    printf(L["'%s' is now this character's band set on this profile."], set.name)
    NS.RequestPanelRefresh()
    return true
end

--- The origin line's character act for stored set `id`: "Use for this character", or, on the set
--- already assigned, a disabled "This character's band set". Nil without a character store.
local function characterAct(id)
    if not (id and NS.BandSetChoice.HasStore()) then return nil end
    local assigned = NS.BandSetChoice.Assigned() == id
    return {
        text = assigned and L["This character's band set"] or L["Use for this character"], disabled = assigned,
        tooltip = L["Make this the band set this character uses on this profile. Every container without a band set of its own, or on the band set this character used until now, follows it; other characters keep theirs."],
        onClick = function() NS.UseBandSetForCharacter(id) end,
    }
end

--- The line a set with no preset shows beside its character act: which set this character uses.
local function characterText(id)
    local own = NS.BandSetChoice.CharacterDefaultId()
    if own == id then return L["This character uses this band set."] end
    local set = own and NS.BandSets.Get(own)
    return L["This character uses %s."]:format(set and set.name or "?")
end

--- The origin line for the page's subject: { text, acts = { { text, tooltip, onClick, disabled } } },
--- or nil for a set with no preset on this client and no character act. A stored set's line ends with
--- its character act (R4-RM-01).
local function originLine()
    local viewed = NS.ViewedPreset()
    if viewed then
        return { text = L["A shipped preset: read-only. Make it yours to use it on a container or to edit it."], acts = {
            { text = L["Use this preset\226\128\166"],
              tooltip = L["Make a band set of your own from this preset, to use on a container or to edit."],
              onClick = function() NS.ShowNewBandSetDialog({ preset = viewed, name = presetName(viewed) }) end },
            { text = L["Copy into a set of mine\226\128\166"],
              tooltip = L["Replace the bands of one of your band sets with this preset's. Asks which set first."],
              onClick = function() NS.ShowCopyBandsDialog({ from = { preset = viewed } }) end },
        } }
    end
    local set, id = NS.SelectedBandSet()
    local diff = id and NS.BandSets.Diff(id)
    local mine = characterAct(id)
    if not diff then
        return mine and { text = characterText(id), acts = { mine } } or nil
    end
    local name = presetName(set.origin)
    local text = #diff > 0 and L["From the %s preset \194\183 modified (%s)"]:format(name, diffSummary(diff))
        or L["From the %s preset"]:format(name)
    return { text = text, acts = { {
        text = L["Restore %s preset\226\128\166"]:format(name), disabled = #diff == 0,
        tooltip = L["Put this set's bands, match rule and unknown label and color back to its preset. Shows what changes first."],
        onClick = function() NS.ShowRestoreBandSetDialog(id) end,
    }, mine } }
end
NS.__bandSetOriginLine = originLine

--- A band rule as Defined by and the heading read it: "Yards", "Spell: Ranged", "Dead zone", ...
local function ruleText(rule)
    local kind = ruleType({ rule = rule })
    if kind == "spell" then return L["Spell: %s"]:format(ROLES[rule.role]) end
    return DEFINED_BY[kind]
end

-- What settings/BandSetDialogs.lua reads from this page, so the dialogs name presets, color classes
-- and word a difference exactly as the picker and the origin line do.
NS.BandSetsPage = {
    PresetName = presetName, ClassColored = classColored, YourClassKey = yourClassKey, Colored = colored,
    DiffWords = DIFF_WORDS, RuleText = ruleText, Match = MATCH, HeaderKey = HEADER_KEY, ViewPrefix = VIEW_PREFIX,
    AddHeader = addHeader, AddOwnSets = addOwnSets, AddPresets = addPresets, DressHeaders = dressHeaders,
}

local function doCopyBands()
    local _, id = NS.SelectedBandSet()
    if id then NS.ShowCopyBandsDialog({ into = id }) end
end

--- The header's four acts. While a preset is viewed only New… is enabled; Delete is disabled on the
--- last set.
local function headerActs()
    local viewing = NS.ViewedPreset() ~= nil
    return {
        { text = L["New\226\128\166"], onClick = function() NS.ShowNewBandSetDialog({}) end,
          tooltip = L["Make a new band set: from a shipped preset, a copy of one of yours, or blank."] },
        { text = L["Duplicate"], onClick = doDuplicate, disabled = viewing,
          tooltip = L["Make a copy of this band set to edit."] },
        { text = L["Copy bands from\226\128\166"], onClick = doCopyBands, disabled = viewing,
          tooltip = L["Replace this set's bands with another set's or a preset's. Its name and the containers using it stay. Asks first."] },
        { text = L["Delete\226\128\166"], onClick = doDelete, disabled = viewing or #NS.BandSets.List() <= 1,
          tooltip = L["Delete this band set. The containers using it move to the default band set. Asks first."] },
    }
end

-- The header's one row (the picker and the acts' shares) and, under it, the origin line's.
local HEADER_H, ORIGIN_H = 44, 32
local PICKER_W, ACT_W = 0.35, 0.16
-- The origin line's shares by how many acts it has: its text, then each act.
local ORIGIN_W = { { text = 0.68, act = 0.3 }, { text = 0.58, act = 0.2 } }

local function refused(kind, subject)
    local check = H.__combatRefused
    return check ~= nil and check(kind, subject) == true
end

--- A header button for `act`, `width` of the row: pcall'd and refused in combat as a banner's is.
local function headerButton(act, width)
    local btn = NS.AceGUI:Create("Button")
    btn:SetText(act.text)
    btn:SetRelativeWidth(width)
    btn:SetDisabled(act.disabled and true or false)
    btn:SetCallback("OnClick", function()
        if refused("banner action", act.text) then return end
        local ok, err = pcall(act.onClick)
        if not ok then print(tostring(err)) end
    end)
    H.AttachTooltip(btn, act.text, act.tooltip)
    return btn
end

local function headerPicker(value)
    local dd = NS.AceGUI:Create("Dropdown")
    local list, order, headers = pickerEntries()
    dd:SetLabel(L["Band set"])
    dd:SetList(list, order)
    for _, key in ipairs(headers) do
        if dd.SetItemDisabled then dd:SetItemDisabled(key, true) end
    end
    dressHeaders(dd)
    dd:SetValue(value)
    dd:SetRelativeWidth(PICKER_W)
    dd:SetCallback("OnValueChanged", function(_, _, v)
        -- A change of subject is a structural redraw: refused in combat, as PageBanner's is.
        if refused("banner select", v) or v == value then return dd:SetValue(value) end
        local ok, err = pcall(choose, v)
        if not ok then print(tostring(err)) end
        if not ok or (type(v) == "string" and v:find(HEADER_KEY, 1, true) == 1) then dd:SetValue(value) end
    end)
    H.AttachTooltip(dd, L["Band set"], L["Which band set this page edits, or a shipped preset to look at. Band sets are shared: every container on one changes with it."])
    return dd
end

--- The origin line's widgets into `block`: its text, then its acts.
local function addOrigin(band, block, line)
    local widths = ORIGIN_W[#line.acts] or ORIGIN_W[1]
    local text = NS.AceGUI:Create("Label")
    text:SetText(line.text)
    text:SetRelativeWidth(widths.text)
    H.LabelFont(text, "GameFontHighlightSmall")
    block:AddChild(text)
    band.origin, band.originActs = text, {}
    for i, act in ipairs(line.acts) do
        local btn = headerButton(act, widths.act)
        block:AddChild(btn)
        band.originActs[i] = btn
    end
end

-- The Flow layout reads the block's content width, which only SetWidth changes, so the header's
-- width is passed on at the build and again from the frame's OnSizeChanged (the first page opened is
-- drawn before the canvas has laid itself out).
local function fitHeader(ctx, block, frame)
    local function fit(width)
        if type(width) ~= "number" or width <= 0 or block.rmLaidOutAt == width then return end
        block.rmLaidOutAt = width
        block:SetWidth(width)
        block:DoLayout()
    end
    fit(frame.GetWidth and frame:GetWidth())
    if frame.SetScript then
        frame:SetScript("OnSizeChanged", function(_, width)
            if ctx.rmHeader and ctx.rmHeader.block == block then fit(width) end
        end)
    end
end

local function buildHeader(ctx, frame, value, line)
    local block = NS.AceGUI:Create("SimpleGroup")
    if not (block and block.frame) then return end
    block:SetLayout("Flow")
    block.frame:SetParent(frame)
    block.frame:ClearAllPoints()
    block.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    block.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    block.frame:Show()
    local band = { block = block, picker = headerPicker(value), acts = {} }
    block:AddChild(band.picker)
    for i, act in ipairs(headerActs()) do
        band.acts[i] = headerButton(act, ACT_W)
        block:AddChild(band.acts[i])
    end
    if line then addOrigin(band, block, line) end
    ctx.rmHeader = band
    fitHeader(ctx, block, frame)
end

--- Draw the header (O.PageHeader), then release the last render's block: released first, AceGUI's
--- pool could hand its widgets straight back to this render while one is still on the stack.
local function drawHeader(ctx, value)
    local old, line = ctx.rmHeader, originLine()
    ctx.rmHeader = nil
    H.PageHeader(ctx, { height = line and (HEADER_H + ORIGIN_H) or HEADER_H, build = function(_, frame)
        buildHeader(ctx, frame, value, line)
    end })
    if old and old.block and NS.AceGUI then NS.AceGUI:Release(old.block) end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

--- A viewed preset's General rows: the page's own, path-less, reading the preset and writing nothing
--- (every control is drawn disabled; settings/Schema.lua refuses a `bandSet.*` write as well).
local function presetRows(rows, set)
    local out = {}
    for i, row in ipairs(rows or {}) do
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        local field = tostring(row.path):match("^bandSet%.(.+)$") or ""
        copy.path, copy.validate, copy.onChange = nil, nil, nil
        copy.get = function()
            local v = set
            for part in field:gmatch("[^%.]+") do v = type(v) == "table" and v[part] or nil end
            return v
        end
        copy.set = function() end
        out[i] = copy
    end
    return out
end

local render

local BANDS_TAB = { key = BANDS, label = BANDS, tooltip = L["Each band's rule, edge, label, colors and sound."],
                    render = function(ctx) renderBands(ctx) end }

local OPTS = { tabs = { BANDS_TAB }, rerender = function(ctx) render(ctx) end }

-- A viewed preset: both tabs are host-drawn from the preset, and the page is drawn disabled.
local VIEW_OPTS = {
    tabs = { { key = GENERAL, render = function(ctx, rows)
                 H.RenderRows(ctx, presetRows(rows, (viewedSet())), nil, nil, { noHeadings = true })
             end }, BANDS_TAB },
    disabledFor = function() return true end,
    rerender = function(ctx) render(ctx) end,
}

function render(ctx)
    H.ClearScroll(ctx)
    local scroll = H.EnsureScroll(ctx)
    local _, viewId = viewedSet()
    local _, id = NS.SelectedBandSet()
    drawHeader(ctx, viewId or id)
    if viewId then
        H.RenderTabbedSchema(ctx, PAGE, nil, nil, VIEW_OPTS)
    else
        H.RenderTabbedSchema(ctx, PAGE, { [GENERAL] = afterGeneral }, nil, OPTS)
    end
    if scroll and scroll.DoLayout then scroll:DoLayout() end
end
NS.__renderBandSetsPage = function(ctx) return render(ctx) end
NS.__bandSetHeader = function(ctx) return ctx and ctx.rmHeader end
NS.__bandItems = bandItems
NS.__bandRail = function() return railButtons end
NS.__selectBand, NS.__selectedBand = selectBand, selectedBand
NS.__removeBand = removeBand

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
        defaultsTooltip = L["Restore the selected band set's match rule and unknown label and color to their defaults. Its name and its bands are kept: to put a preset's bands back, use Restore preset under the picker."],
    })
    ctx.panel.defaultsOnClick = function()
        if NS.ViewedPreset() then
            return print(L["A shipped preset is being viewed, and it is read-only: choose one of your band sets first (/rm bands lists them)."])
        end
        H.RestoreDefaults(PAGE, ctx)
    end
    H.SetRenderer(ctx, render)
    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, L["Band sets"])
end

NS.RegisterOptionsPage(PAGE, L["Band sets"], build)
