local _, NS = ...
-- settings/Containers.lua — the Containers page: which range containers exist, and what each one is.
--
--     band   [Container v picker ]                [ New container ]     <- above the rail and the strip
--     rail   | General    |  [ General ][ Position ]                     <- the selected entry's tabs
--            | Display    |  [Name]               [Enable this container]
--            | Visibility |  -- What it tracks --
--            | Sounds     |  [Unit]               [Band set]
--                            [Friendly band set]
--                            [Duplicate container] [Delete container…]
--                            -- Copy settings from --  [Source v] [Copy onto this container]
--
-- ONE PAGE, A RAIL OF FOUR ENTRIES (options-ui-§13, §14; design spec 5.6). The band carries the page's
-- only picker and its create act (O.PageBanner with `action`); the rail chooses which part of the
-- selected container is shown, never which container. Each rail entry is a page key of its own
-- (`containers`, `containers_display`, ...) whose rows carry it, so the header's Defaults restores
-- the entry on screen, every tab of it (options-ui-§13). This file holds the General entry's rows and
-- acts and draws the page; settings/Containers_<Entry>.lua holds each other entry's rows and
-- registers it through NS.RegisterContainerSection.
--
-- THE SOUNDS ENTRY IS NOT OFFERED FOR A `nameplates` CONTAINER (design spec 5.5): twenty plates
-- would chain-fire, so the per-plate instances never play one (modules/Sounds.lua) and the rail does
-- not list a section that does nothing. The rail heals to General when the selection moves to one.
--
-- EVERY ROW IS SELECTION-RELATIVE: `container.<field>`, stamped by NS.StampSelectionRows
-- (settings/Schema.lua), so `/rm get|set container.unit` reads and writes the container the banner
-- shows, through NS.CM.SetField, and the panel and the CLI take one route.

local L = NS.L
local H = NS.Helpers
local print = NS.Print
local printf = NS.Printf

local PAGE = "containers"
local GENERAL = L["General"]
local POSITION = L["Position"]

-- ---------------------------------------------------------------------------
-- The value lists every Containers entry shares (published for the entry files)
-- ---------------------------------------------------------------------------

local V = {}
NS.ContainerValues = V

V.UNITS = {
    target = L["Target"], focus = L["Focus"], pet = L["Pet"], mouseover = L["Mouseover"],
    nameplates = L["All nameplates"],
}
V.UNITS_SORT = { "target", "focus", "pet", "mouseover", "nameplates" }
-- The units with one frame of their own; `nameplates` has an instance per plate instead.
V.SINGLE_UNITS = { "target", "focus", "pet", "mouseover" }

V.MODES = { screen = L["Free on screen"], frame = L["Unit frame"], nameplate = L["Nameplate"],
    cursor = L["Cursor"] }
V.MODES_SORT = { "screen", "frame", "nameplate", "cursor" }

V.PROVIDERS = { blizzard = L["Blizzard"], ellesmere = L["EllesmereUI"], custom = L["Custom frame (by name)"] }
V.PROVIDERS_SORT = { "blizzard", "ellesmere", "custom" }

V.POINTS = {
    TOPLEFT = L["Top left"], TOP = L["Top"], TOPRIGHT = L["Top right"], LEFT = L["Left"],
    CENTER = L["Center"], RIGHT = L["Right"], BOTTOMLEFT = L["Bottom left"], BOTTOM = L["Bottom"],
    BOTTOMRIGHT = L["Bottom right"],
}
V.POINTS_SORT = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM",
    "BOTTOMRIGHT" }

-- Player-chosen strata (frame-layering-§1): BACKGROUND to HIGH.
V.STRATA = { BACKGROUND = "BACKGROUND", LOW = "LOW", MEDIUM = "MEDIUM", HIGH = "HIGH" }
V.STRATA_SORT = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" }

-- The color-mode companion (options-ui-§17: a color-mode dropdown whose value set includes `class`).
V.COLOR_MODES = { band = L["Band color"], fixed = L["Fixed color"], class = L["Class color"] }
V.COLOR_MODES_SORT = { "band", "fixed", "class" }

--- The band sets as dropdown values, id -> name, led by `noneLabel` under 0 (the row's `nilAs`).
local function bandSetValues(noneLabel)
    return function()
        local out = { [0] = noneLabel }
        for _, id in ipairs(NS.BandSets.List()) do out[id] = NS.BandSets.Get(id).name end
        return out
    end
end

--- The same ids in the registry's order, 0 first.
local function bandSetSort()
    local out = { 0 }
    for _, id in ipairs(NS.BandSets.List()) do out[#out + 1] = id end
    return out
end

--- The rows a composer emitted with its `Use class color` companion turned into the color-mode
--- dropdown this addon stores (`colorMode`, one of band / fixed / class). The companion keeps its
--- place right of the swatch and its classColorSource declaration (options-ui-§17).
function V.ColorModeCompanion(rows)
    for _, row in ipairs(rows) do
        if type(row.path) == "string" and row.path:match("%.colorMode$") then
            row.type, row.values, row.sorting = "string", V.COLOR_MODES, V.COLOR_MODES_SORT
            row.label = L["Color from"]
            row.tooltip = L["Where the color comes from: the current band's, the swatch beside this, or the tracked unit's class (the swatch's opacity always applies)."]
        end
    end
    return rows
end

--- A media picker's values with the stored "" offered first as `key` (the row's `emptyAs`), labeled
--- `blank`: the skin's font, a Solid border (modules/Style.lua reads "" so). A function, as the
--- composers' own `values` is (options-ui-§16).
function V.MediaValues(kind, key, blank)
    local lsm = H.LSMValues(kind)
    return function()
        local out = { [key] = blank }
        for k, v in pairs(lsm() or {}) do out[k] = v end
        return out
    end
end

-- ---------------------------------------------------------------------------
-- The rail's entries
-- ---------------------------------------------------------------------------

local sections, sectionOrder = {}, {}

--- Register one rail entry of the Containers page.
--- @param key string    the entry's page key: the `page` its rows carry
--- @param label string  the entry's label
--- @param spec table    { tooltip, hiddenFor = function(container) -> boolean, afterGroup,
---                      afterSubgroup, tabs = { host tab, ... } }
function NS.RegisterContainerSection(key, label, spec)
    spec = spec or {}
    if not sections[key] then sectionOrder[#sectionOrder + 1] = key end
    sections[key] = { key = key, label = label, spec = spec }
end

--- The entries the rail lists for container `c`, in registration order.
local function railSections(c)
    local out = {}
    for _, key in ipairs(sectionOrder) do
        local s = sections[key]
        local hidden = c and type(s.spec.hiddenFor) == "function" and s.spec.hiddenFor(c)
        if not hidden then out[#out + 1] = s end
    end
    return out
end
NS.__containerRail = railSections

-- ---------------------------------------------------------------------------
-- The General entry's rows
-- ---------------------------------------------------------------------------

local S_TRACKS = L["What it tracks"]

local ROWS = {
    { path = "container.name", page = PAGE, group = GENERAL, order = 10, type = "string",
      dialogControl = "EditBox", maxLetters = 40, label = L["Name"],
      desc = L["What this container is called in the picker and in /rm containers. Press Enter to apply."],
      validate = function(v) return type(v) == "string" and v:match("%S") ~= nil end,
      onChange = function() NS.RequestPanelRefresh() end },
    { path = "container.enabled", page = PAGE, group = GENERAL, order = 20, type = "bool",
      label = L["Enable this container"],
      desc = L["Draw this container. A disabled container keeps its settings."] },
    { path = "container.unit", page = PAGE, group = GENERAL, subgroup = S_TRACKS, order = 30,
      type = "string", values = V.UNITS, sorting = V.UNITS_SORT, label = L["Unit"],
      desc = L["Whose range this container shows. All nameplates draws one copy on every hostile nameplate."],
      onChange = function() NS.RequestPanelRefresh() end },
    { path = "container.bandSet", page = PAGE, group = GENERAL, subgroup = S_TRACKS, order = 40,
      type = "number", min = 0, max = 1000000, nilAs = 0, default = 0,
      values = bandSetValues(L["Default band set"]), sorting = bandSetSort, label = L["Band set"],
      desc = L["The bands this container colors by. Band sets are shared and edited on the Band sets page."] },
    { path = "container.bandSetFriendly", page = PAGE, group = GENERAL, subgroup = S_TRACKS, order = 50,
      type = "number", min = 0, max = 1000000, nilAs = 0, default = 0,
      values = bandSetValues(L["Same as Band set"]), sorting = bandSetSort, label = L["Friendly band set"],
      desc = L["The bands used while the unit is friendly, for healing ranges. Same as Band set uses one set for every unit."] },
}

-- ── the Position tab ────────────────────────────────────────────────────────────────────────
--
-- Read the way AuraMaster's Position and growth tab reads: each mode's subsection opens with the two
-- anchor points side by side, what it attaches to on the left ("Unit frame anchor point", "Nameplate
-- anchor point", "Screen anchor point") and "This container anchor point" on the right, then its X
-- and Y side by side. Only the chosen mode's subsection is drawn (`shownWhen`); every row stays in
-- the schema, so `/rm set` and the resets reach each one. Frame strata applies in every mode (the
-- root's strata, modules/Container.lua), so it sits under Attach to, not in one mode's subsection.

local S_ANCHOR = L["Anchor"]
local S_FRAME = L["On the unit frame"]
local S_SCREEN = L["On screen"]
local S_CURSOR = L["At the cursor"]
local S_PLATE = L["On the nameplate"]

local function whenMode(mode) return { path = "container.anchor.mode", equals = mode } end

--- A point dropdown row; `startsLine` opens a new line (the first of a pair).
local function pointRow(path, order, subgroup, shown, label, desc, startsLine)
    return { path = path, page = PAGE, group = POSITION, subgroup = subgroup, order = order,
        type = "string", values = V.POINTS, sorting = V.POINTS_SORT, shownWhen = shown,
        startsLine = startsLine, label = label, desc = desc }
end

--- An offset slider row; `startsLine` opens a new line (the X of an X and Y pair).
local function offsetRow(path, order, subgroup, shown, label, desc, startsLine)
    return { path = path, page = PAGE, group = POSITION, subgroup = subgroup, order = order,
        type = "number", min = -500, max = 500, step = 1, shownWhen = shown, startsLine = startsLine,
        label = label, desc = desc }
end

local THIS_POINT = L["This container anchor point"]
local MY_POINT = L["The point of this container that is pinned to the anchor point beside it."]
local X_NUDGE = L["Horizontal offset from the attachment point, in pixels."]
local Y_NUDGE = L["Vertical offset from the attachment point, in pixels."]
local ON_PLATE = { any = { whenMode("nameplate"), { path = "container.unit", equals = "nameplates" } } }

local POSITION_ROWS = {
    { path = "container.anchor.mode", page = PAGE, group = POSITION, subgroup = S_ANCHOR, order = 10,
      type = "string", values = V.MODES, sorting = V.MODES_SORT,
      shownWhen = { path = "container.unit", equals = V.SINGLE_UNITS }, label = L["Attach to"],
      desc = L["Where this container sits: free on screen (drag it while unlocked), on its unit's frame, on its unit's nameplate, or following the cursor."] },
    { path = "container.anchor.frame.provider", page = PAGE, group = POSITION, subgroup = S_FRAME,
      order = 20, type = "string", values = V.PROVIDERS, sorting = V.PROVIDERS_SORT,
      shownWhen = whenMode("frame"), label = L["Unit frames from"],
      desc = L["Whose unit frame to attach to. Custom frame takes a frame's name: type it, or use Pick on screen."] },
    { path = "container.anchor.frame.name", page = PAGE, group = POSITION, subgroup = S_FRAME, order = 30,
      type = "string", dialogControl = "EditBox", maxLetters = 80,
      shownWhen = { path = "container.anchor.frame.provider", equals = "custom" }, label = L["Frame name"],
      desc = L["The global name of the frame to attach to. Needs Unit frames from set to Custom frame (by name)."] },
    pointRow("container.anchor.frame.relPoint", 40, S_FRAME, whenMode("frame"), L["Unit frame anchor point"],
        L["The point of the unit frame this container is attached to."], true),
    pointRow("container.anchor.frame.point", 50, S_FRAME, whenMode("frame"), THIS_POINT, MY_POINT),
    offsetRow("container.anchor.frame.x", 60, S_FRAME, whenMode("frame"), L["X offset"], X_NUDGE, true),
    offsetRow("container.anchor.frame.y", 70, S_FRAME, whenMode("frame"), L["Y offset"], Y_NUDGE),
    pointRow("container.anchor.relPoint", 80, S_SCREEN, whenMode("screen"), L["Screen anchor point"],
        L["The point of the screen X position and Y position are measured from."], true),
    pointRow("container.anchor.point", 90, S_SCREEN, whenMode("screen"), THIS_POINT,
        L["The point of this container placed at the position measured from the screen anchor point. Dragging it while unlocked sets these for you."]),
    { path = "container.anchor.x", page = PAGE, group = POSITION, subgroup = S_SCREEN, order = 100,
      type = "number", min = -2000, max = 2000, step = 1, shownWhen = whenMode("screen"), startsLine = true,
      label = L["X position"], desc = L["Horizontal position, in pixels, measured from the screen anchor point. Dragging it while unlocked sets this too."] },
    { path = "container.anchor.y", page = PAGE, group = POSITION, subgroup = S_SCREEN, order = 110,
      type = "number", min = -2000, max = 2000, step = 1, shownWhen = whenMode("screen"),
      label = L["Y position"], desc = L["Vertical position, in pixels, measured from the screen anchor point. Dragging it while unlocked sets this too."] },
    { path = "container.anchor.strata", page = PAGE, group = POSITION, subgroup = S_ANCHOR, order = 15,
      type = "string", values = V.STRATA, sorting = V.STRATA_SORT,
      label = L["Frame strata"], tooltip = H.StrataTooltip(V.STRATA) },
    pointRow("container.anchor.cursor.point", 130, S_CURSOR, whenMode("cursor"), THIS_POINT,
        L["The point of this container that follows the cursor."], true),
    offsetRow("container.anchor.cursor.x", 140, S_CURSOR, whenMode("cursor"), L["X offset"],
        L["Horizontal offset from the cursor, in pixels."], true),
    offsetRow("container.anchor.cursor.y", 150, S_CURSOR, whenMode("cursor"), L["Y offset"],
        L["Vertical offset from the cursor, in pixels."]),
    pointRow("container.nameplate.relPoint", 160, S_PLATE, ON_PLATE, L["Nameplate anchor point"],
        L["The point of the nameplate this container is attached to. While unlocked, a preview nameplate shows where it sits."], true),
    pointRow("container.nameplate.point", 170, S_PLATE, ON_PLATE, THIS_POINT, MY_POINT),
    offsetRow("container.nameplate.x", 180, S_PLATE, ON_PLATE, L["X offset"], X_NUDGE, true),
    offsetRow("container.nameplate.y", 190, S_PLATE, ON_PLATE, L["Y offset"], Y_NUDGE),
    { path = "container.nameplate.includeFriendly", page = PAGE, group = POSITION, subgroup = S_PLATE,
      order = 200, type = "bool", shownWhen = { path = "container.unit", equals = "nameplates" },
      label = L["Friendly nameplates too"],
      desc = L["Draw this container on friendly nameplates as well as hostile ones."] },
}

for _, row in ipairs(POSITION_ROWS) do ROWS[#ROWS + 1] = row end
NS.RegisterSchemaRows(NS.StampSelectionRows(ROWS))

-- ---------------------------------------------------------------------------
-- The acts on the selected container (the General tab's foot, options-ui-§14)
-- ---------------------------------------------------------------------------

--- The Containers page's ctx, once built: the page every act below re-renders.
local pageCtx

-- A structural refresh, coalesced to the next frame: a dropdown's own callback must not release the
-- widget it runs in, and a burst of writes (a preset, a delete) redraws once.
local refreshTimer
function NS.RequestPanelRefresh()
    if refreshTimer then return end
    refreshTimer = C_Timer.NewTimer(0, function()
        refreshTimer = nil
        if NS.RefreshOptionsPanel then NS.RefreshOptionsPanel() end
    end)
end

--- Select container `id` and redraw every page: the banner's, `/rm select`'s and a create's one
--- route. Answers whether it was selected.
function NS.ShowContainer(id)
    if not NS.SelectContainer(id) then return false end
    NS.RequestPanelRefresh()
    return true
end

--- Delete container `id` and select its neighbor in the order (the next, else the one before), so a
--- delete never leaves the banner on a container that is gone. Answers the deleted name, or nil.
function NS.DeleteContainer(id)
    local c = NS.CM.Get(id)
    if not c then return nil end
    local ids, index = NS.CM.List(), nil
    for i, other in ipairs(ids) do if other == id then index = i end end
    local name = c.name
    local _, selected = NS.SelectedContainer()
    NS.CM.Delete(id)
    if selected == id then NS.SelectContainer(NS.NeighborAfterDelete(ids, index)) end
    NS.RequestPanelRefresh()
    return name
end

--- A new container on `unit`, selected, with the page on its General entry.
function NS.NewContainer(unit)
    local id = NS.CM.Create(unit)
    if not id then return nil end
    if pageCtx then pageCtx.activeSection = PAGE end
    NS.ShowContainer(id)
    return id
end

local function doNew() NS.NewContainer("target") end

local function doDuplicate()
    local _, id = NS.SelectedContainer()
    local newId = id and NS.CM.Duplicate(id)
    if newId then NS.ShowContainer(newId) end
end

StaticPopupDialogs["RANGEMASTER_DELETE_CONTAINER"] = {
    text         = L["Delete the container '%s'? Its settings are discarded."],
    button1      = L["Yes"],
    button2      = L["No"],
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    OnAccept     = function(_, data)
        local name = data and NS.DeleteContainer(data)
        if name then printf(L["Deleted container '%s'."], name) end
    end,
}

--- Ask before deleting container `id`: the panel's Delete and `/rm delete` (settings/Slash.lua) share
--- this one confirmation, whose OnAccept deletes and prints the line.
function NS.ConfirmDeleteContainer(id)
    local c = id and NS.CM.Get(id)
    if not c then return end
    local popup = StaticPopup_Show("RANGEMASTER_DELETE_CONTAINER", tostring(c.name))
    if popup then popup.data = id end
end

local function doDelete()
    local _, id = NS.SelectedContainer()
    NS.ConfirmDeleteContainer(id)
end

-- The copy control's choice. Page state, not a setting: it means nothing outside an open panel.
local copySource

local function sourceCell(_, parent, rel)
    local _, selected = NS.SelectedContainer()
    local list, order = {}, {}
    for _, id in ipairs(NS.CM.List()) do
        if id ~= selected then
            list[id] = NS.CM.Get(id).name
            order[#order + 1] = id
        end
    end
    if not list[copySource] then copySource = order[1] end
    local dd = NS.AceGUI:Create("Dropdown")
    dd:SetLabel(L["Source container"])
    dd:SetList(list, order)
    dd:SetValue(copySource)
    dd:SetRelativeWidth(rel or 0.5)
    dd:SetCallback("OnValueChanged", function(_, _, v) copySource = v end)
    parent:AddChild(dd)
    return dd
end

local function doCopy()
    local _, selected = NS.SelectedContainer()
    if not (copySource and selected) then return end
    if NS.CM.CopySettings(copySource, selected) then
        printf(L["Copied settings from '%s'."], NS.CM.Get(copySource).name)
        NS.RequestPanelRefresh()
    end
end

local function renderCopy(ctx)
    H.Section(ctx, L["Copy settings from"])
    H.RenderGrid(ctx, { { make = sourceCell } })
    H.InlineButtonPair(ctx, {
        text = L["Copy onto this container"],
        tooltip = L["Replace how the selected container looks and behaves with the source's: its band sets, layout, frame, label, elements, visibility and sounds. Its name, label text, unit and position are never copied."],
        onClick = doCopy,
    }, nil)
end

local function afterGeneral(ctx)
    local c = NS.SelectedContainer()
    if not c then return end
    H.InlineButtonPair(ctx,
        { text = L["Duplicate container"], tooltip = L["Make a copy of this container with every setting."],
          onClick = doDuplicate },
        { text = L["Delete container\226\128\166"], tooltip = L["Delete this container. Asks first."],
          onClick = doDelete })
    if #NS.CM.List() > 1 then renderCopy(ctx) end
end

--- Pick on screen, under the frame rows: the pick-on-screen overlay (modules/FramePicker.lua), whose
--- pick puts the container on that frame by name, through the registry's writer.
function NS.PickFrameForSelected()
    local _, id = NS.SelectedContainer()
    if not id then return print(L["No container exists yet: create one with /rm new."]) end
    return NS.FramePicker.Start(function(name)
        NS.CM.SetField(id, "anchor.mode", "frame")
        NS.CM.SetField(id, "anchor.frame.provider", "custom")
        NS.CM.SetField(id, "anchor.frame.name", name)
        printf(L["Attached to %s."], name)
        NS.RequestPanelRefresh()
    end)
end

local function afterFrameRows(ctx)
    local c = NS.SelectedContainer()
    if not (c and c.anchor.mode == "frame") then return end
    H.InlineButtonPair(ctx, {
        text = L["Pick on screen"],
        tooltip = L["Point at a frame and press Enter to attach this container to it. Escape cancels. Same as /rm pick."],
        onClick = NS.PickFrameForSelected,
    }, nil)
end

NS.RegisterContainerSection(PAGE, GENERAL, {
    tooltip = L["Name this container, choose its unit and band sets, and where it sits."],
    afterGroup = { [GENERAL] = afterGeneral },
    afterSubgroup = { [S_FRAME] = afterFrameRows },
})

-- ---------------------------------------------------------------------------
-- The band ribbon (`/rm bands`' chat line, settings/Slash.lua)
-- ---------------------------------------------------------------------------

--- A stored color as a `|cffRRGGBB` escape.
local function escapeOf(color)
    local r, g, b = NS.ResolveColor(color, false)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end

--- One band as "from–to LABEL" (an open-ended band "from+ LABEL").
local function bandText(b)
    local span = b.to and ("%d\226\128\147%d"):format(b.from, b.to) or ("%d+"):format(b.from)
    if b.label ~= "" then span = span .. " " .. b.label end
    return span
end

--- Set `set`'s bands as one line, each in its frame color, then the unknown label in its gray.
function NS.BandRibbon(set)
    local parts = {}
    for _, b in ipairs(set.bands) do parts[#parts + 1] = escapeOf(b.frameColor) .. bandText(b) .. "|r" end
    parts[#parts + 1] = escapeOf(set.unknown.color) .. set.unknown.label .. "|r"
    return table.concat(parts, "   ")
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

--- The banner's list: every container by name, with its unit.
local function containerList()
    local list, order = {}, {}
    for _, id in ipairs(NS.CM.List()) do
        local c = NS.CM.Get(id)
        list[id] = ("%s  (%s)"):format(c.name, V.UNITS[c.unit] or tostring(c.unit))
        order[#order + 1] = id
    end
    return list, order
end

local BAND = {
    label = L["Container"],
    tooltip = L["Which container every entry and tab of this page edits."],
    action = {
        text = L["New container"],
        tooltip = L["Create a container on the target. Change its unit and look below."],
        onClick = function() doNew() end,
    },
}

local function drawBanner(ctx, id)
    local list, order = containerList()
    H.PageBanner(ctx, {
        label = BAND.label, tooltip = BAND.tooltip, list = list, order = order, value = id,
        onSelect = function(v) if v ~= id then NS.ShowContainer(v) end end,
        action = BAND.action,
    })
end

--- The entry to draw: the one the page holds while the rail still lists it, else the first.
local function settleSection(ctx, list)
    for _, s in ipairs(list) do
        if s.key == ctx.activeSection then return s end
    end
    return list[1]
end

--- With no container there is nothing to edit: each tab of the entry says how to make one.
local function emptyTabs(key)
    local out, seen = {}, {}
    for _, row in ipairs(NS.SchemaForPage(key)) do
        if row.group and not seen[row.group] then
            seen[row.group] = true
            out[#out + 1] = { key = row.group, label = row.group, render = function(c)
                H.TextRow(c, L["No containers yet. Click New container, or type /rm new."])
            end }
        end
    end
    return out
end

local render

--- The rail entry's tabs and hooks, for RenderTabbedSchema.
local function sectionOpts(section, c)
    local spec = section.spec
    local tabs, afterSubgroup = emptyTabs(section.key), nil
    if c then tabs, afterSubgroup = spec.tabs, spec.afterSubgroup end
    return {
        tabs = tabs,
        afterSubgroup = afterSubgroup,
        rerender = function(ctx)
            ctx.sectionTabs[section.key] = ctx.activeTab
            render(ctx)
        end,
    }
end

--- Draw the page: the band, the rail, then the selected entry's strip and tab (the library's draw
--- order: PageBanner, NavRail, TabStrip; options-ui-§13, §14).
function render(ctx)
    ctx.sectionTabs = ctx.sectionTabs or {}
    -- Before the clear, never after (options-ui-§18): the Display entry's drag list and its Dot tab's
    -- style tiles hold frames on AceGUI widgets the clear hands back to the pool.
    if NS.CancelElementOrder then NS.CancelElementOrder(ctx) end
    if NS.ReleaseStyleTiles then NS.ReleaseStyleTiles(ctx) end
    H.ClearScroll(ctx)
    local scroll = H.EnsureScroll(ctx)
    local c, id = NS.SelectedContainer()
    local list = railSections(c)
    local section = settleSection(ctx, list)
    ctx.activeSection = section.key
    ctx.activeTab = ctx.sectionTabs[section.key]
    drawBanner(ctx, id)
    local entries = {}
    for i, s in ipairs(list) do entries[i] = { key = s.key, label = s.label, tooltip = s.spec.tooltip } end
    H.NavRail(ctx, {
        entries = entries,
        value = section.key,
        onSelect = function(key)
            ctx.sectionTabs[ctx.activeSection] = ctx.activeTab
            ctx.activeSection = key
            H.RefreshPanel(ctx, true)
        end,
    })
    H.RenderTabbedSchema(ctx, section.key, c and section.spec.afterGroup or nil, nil, sectionOpts(section, c))
    ctx.sectionTabs[section.key] = ctx.activeTab
    if scroll and scroll.DoLayout then scroll:DoLayout() end
end
NS.__renderContainersPage = function(ctx) return render(ctx) end

local function build(mainCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
    local ctx = H.CreatePanel("RangeMasterContainersPanel", L["Containers"], {
        pageKey         = PAGE,
        defaultsButton  = true,
        defaultsTooltip = L["Restore every tab of the entry selected on the left, for the container in the band, to its defaults."],
    })
    pageCtx = ctx
    ctx.activeSection = PAGE
    -- The entry on screen, read at click time: the button is built once, on the first show.
    ctx.panel.defaultsOnClick = function() H.RestoreDefaults(ctx.activeSection or PAGE, ctx) end
    -- Through SetRenderer, which owns WHEN the page draws and covers it in combat (options-ui-§2).
    H.SetRenderer(ctx, render)
    return Settings.RegisterCanvasLayoutSubcategory(mainCategory, ctx.panel, L["Containers"])
end

NS.RegisterOptionsPage(PAGE, L["Containers"], build)
