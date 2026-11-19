-- tests/test_settings_containers.lua — the Containers page (settings/Containers*.lua) and the
-- selection-relative paths under it (settings/Schema.lua): surface parity for every row, the
-- `container.<field>` paths on the CLI, the rail, the acts and the combat refusal. The v0.1.0 plan,
-- Task 8; design spec section 5.6.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local E = dofile("tests/settings_env.lua")
local CM = NS.CM

local CONTAINER_PAGES = {
  containers = "General", containers_display = "Display",
  containers_visibility = "Visibility", containers_sounds = "Sounds",
}

local function slash(line) return E.capture(function() NS.Slash:OnSlash(line) end) end

--- The rows of the new pages, in schema order.
local function rowsOf(pages)
  local out = {}
  for _, row in ipairs(NS.Schema) do
    if pages[row.page] then out[#out + 1] = row end
  end
  return out
end

--- What `/rm set` is handed to store `row`'s current value again (a round trip), or a value for an
--- empty free-text row, which the parser refuses empty.
local function cliValue(row, v)
  if row.type == "color" then return ("%s %s %s %s"):format(v.r, v.g, v.b, v.a or 1) end
  if row.type == "bool" then return v and "true" or "false" end
  if row.type == "string" and v == "" then return "Probe" end
  return tostring(v)
end

--- Spy on the two registries' writers; `counts` gains one per call that reached each.
local function spyWriters(body)
  local counts = { container = 0, bandSet = 0 }
  local B = NS.BandSets
  local saved = { CM.SetField, CM.Rename, B.SetField, B.Rename }
  local function wrap(kind, fn)
    return function(...) counts[kind] = counts[kind] + 1; return fn(...) end
  end
  CM.SetField, CM.Rename = wrap("container", saved[1]), wrap("container", saved[2])
  B.SetField, B.Rename = wrap("bandSet", saved[3]), wrap("bandSet", saved[4])
  local ok, err = pcall(body, counts)
  CM.SetField, CM.Rename, B.SetField, B.Rename = saved[1], saved[2], saved[3], saved[4]
  if not ok then error(err, 0) end
end

test("settings: surface parity — every Containers and Band sets row answers /rm get and /rm set, through its registry's writer", function()
  E.with(function()
    NS.SelectContainer(CM.Create("target"))
    local pages = { bandsets = true }
    for k in pairs(CONTAINER_PAGES) do pages[k] = true end
    local rows = rowsOf(pages)
    assertTrue(#rows > 60, "the pages register their rows (" .. #rows .. ")")
    spyWriters(function(counts)
      for _, row in ipairs(rows) do
        local kind = row.path:match("^(%a+)%.")
        assertTrue(kind == "container" or kind == "bandSet", row.path .. " is selection-relative")
        assertEqual(type(row.get), "function", row.path .. " reads through its own get")
        assertEqual(type(row.set), "function", row.path .. " writes through its own set, never a raw path store")
        local got = slash("get " .. row.path)
        assertTrue(E.said(got, row.path), "/rm get " .. row.path .. " answers: " .. table.concat(got, " | "))
        local before = counts[kind]
        local out = slash("set " .. row.path .. " " .. cliValue(row, NS.GetSetting(row.path)))
        assertEqual(counts[kind], before + 1,
          "/rm set " .. row.path .. " reached the " .. kind .. " writer once: " .. table.concat(out, " | "))
      end
    end)
  end)
end)

--- The labels each page key and tab draws, over every placement, so a row a selector hides under
--- one placement is seen under another.
local function drawnLabels(ctx)
  local seen = {}
  local variants = {
    { unit = "target", mode = "screen" }, { unit = "target", mode = "frame", provider = "custom" },
    { unit = "target", mode = "cursor" }, { unit = "target", mode = "nameplate" },
    { unit = "nameplates", mode = "nameplate" },
  }
  for _, v in ipairs(variants) do
    local id = CM.Create(v.unit)
    CM.SetField(id, "anchor.mode", v.mode)
    if v.provider then CM.SetField(id, "anchor.frame.provider", v.provider) end
    NS.SelectContainer(id)
    for key in pairs(CONTAINER_PAGES) do
      for _, row in ipairs(NS.SchemaForPage(key)) do
        ctx.activeSection, ctx.sectionTabs = key, { [key] = row.group }
        NS.__renderContainersPage(ctx)
        local where = key .. "/" .. row.group
        seen[where] = seen[where] or {}
        for label in pairs(E.labels(ctx)) do seen[where][label] = true end
      end
    end
  end
  return seen
end

test("settings: surface parity — every Containers row is drawn on its rail entry's tab", function()
  E.with(function()
    local ctx = E.page("containers", "Containers")
    assertTrue(ctx ~= nil, "the Containers page rendered")
    local seen = drawnLabels(ctx)
    for key in pairs(CONTAINER_PAGES) do
      for _, row in ipairs(NS.SchemaForPage(key)) do
        local where = key .. "/" .. row.group
        assertTrue(seen[where] and seen[where][row.label],
          row.path .. " (" .. row.label .. ") is drawn on " .. where)
      end
    end
  end)
end)

test("settings: test_container_paths_get_set — /rm set container.unit focus changes the selected container", function()
  E.with(function()
    local a, b = CM.Create("target"), CM.Create("pet")
    NS.SelectContainer(b)
    slash("set container.unit focus")
    assertEqual(CM.Get(b).unit, "focus", "the selected container moved to focus")
    assertEqual(CM.Get(a).unit, "target", "the other one did not")
    assertTrue(E.said(slash("get container.unit"), "focus"), "/rm get reads the selected container")
    NS.SelectContainer(a)
    assertTrue(E.said(slash("get container.unit"), "target"), "and follows the selection")
    slash("set container.elements.number.size 20")
    assertEqual(CM.Get(a).elements.number.size, 20, "a nested field lands on the selected container")
    assertEqual(CM.Get(b).elements.number.size, NS.CONTAINER_TEMPLATE.elements.number.size)
    local out = slash("set container.unit bogus")
    assertEqual(CM.Get(a).unit, "target", "a value outside the list is refused")
    assertTrue(#out > 0, "and the refusal is said")
  end)
end)

test("settings: a band-set reference reads 0 for none, and 0 writes nil back", function()
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    assertEqual(NS.GetSetting("container.bandSetFriendly"), 0, "no friendly set reads as 0")
    local healer = NS.BandSets.Create(nil, "healer")
    assertTrue(NS.SetByPath("container.bandSetFriendly", healer))
    assertEqual(CM.Get(id).bandSetFriendly, healer)
    assertTrue(NS.SetByPath("container.bandSetFriendly", 0))
    assertNil(CM.Get(id).bandSetFriendly, "0 stores nil: the container's own set for every reaction")
    assertTrue(NS.SetByPath("container.bandSet", 0))
    assertEqual(CM.Get(id).bandSet, NS.BandSets.DefaultId(), "0 is the default band set")
  end)
end)

test("settings: with no container, a container. write is refused with how to make one", function()
  E.with(function()
    local ok, err, why = NS.SetByPath("container.unit", "focus")
    assertFalse(ok)
    assertTrue(tostring(why or err):find("/rm new", 1, true) ~= nil, "the refusal names /rm new")
    assertNil(NS.GetSetting("container.unit"), "and nothing reads")
  end)
end)

test("settings: no selection reads the first container, and the selection never outlives its container", function()
  E.with(function()
    local a, b = CM.Create("target"), CM.Create("focus")
    local _, id = NS.SelectedContainer()
    assertEqual(id, a, "nothing selected reads the first")
    assertFalse(NS.SelectContainer(999), "an id that names nothing is refused")
    assertTrue(NS.SelectContainer(b))
    CM.Delete(b)
    _, id = NS.SelectedContainer()
    assertEqual(id, a, "a selection whose container went reads the first")
  end)
end)

test("settings: deleting the selected container selects its neighbor, not the first", function()
  E.with(function()
    local a, b, c = CM.Create("target"), CM.Create("focus"), CM.Create("pet")
    NS.SelectContainer(b)
    assertEqual(NS.DeleteContainer(b), "Focus")
    local _, id = NS.SelectedContainer()
    assertEqual(id, c, "the next one takes the selection")
    NS.DeleteContainer(c)
    _, id = NS.SelectedContainer()
    assertEqual(id, a, "the last one's delete selects the one before it")
    NS.SelectContainer(a)
    local other = CM.Create("pet")
    NS.DeleteContainer(other)
    _, id = NS.SelectedContainer()
    assertEqual(id, a, "deleting another container keeps the selection")
  end)
end)

test("settings: test_sounds_section_hidden_for_nameplates — the rail lists no Sounds for a nameplates container", function()
  E.with(function()
    local ctx = E.page("containers", "Containers")
    local target, plates = CM.Create("target"), CM.Create("nameplates")
    NS.SelectContainer(target)
    ctx.activeSection = "containers_sounds"
    NS.__renderContainersPage(ctx)
    local rail = table.concat(E.railLabels(ctx), ",")
    assertEqual(rail, "General,Display,Visibility,Sounds", "a target container lists all four")
    assertEqual(ctx.activeSection, "containers_sounds", "and the page is on Sounds")
    NS.SelectContainer(plates)
    NS.__renderContainersPage(ctx)
    rail = table.concat(E.railLabels(ctx), ",")
    assertEqual(rail, "General,Display,Visibility", "a nameplates container lists no Sounds")
    assertEqual(ctx.activeSection, "containers", "the page heals to General")
  end)
end)

test("settings: the Containers page draws the banner with New container, and New selects what it made", function()
  E.with(function()
    local ctx = E.page("containers", "Containers")
    NS.__renderContainersPage(ctx)
    local labels = E.labels(ctx)
    assertTrue(labels["No containers yet. Click New container, or type /rm new."],
      "with no container each tab says how to make one")
    local id = NS.NewContainer("focus")
    local _, selected = NS.SelectedContainer()
    assertEqual(selected, id, "a new container is selected")
    assertEqual(ctx.activeSection, "containers", "and the page lands on its General entry")
    NS.__renderContainersPage(ctx)
    labels = E.labels(ctx)
    assertTrue(labels["Duplicate container"] and labels["Delete container\226\128\166"],
      "the General tab carries the acts on the selected container")
    -- Red under the General tab still drawing the band Preview section (plan M8).
    assertNil(labels["Preview"], "and no band preview")
  end)
end)

test("settings: Delete container… confirms first, and the confirm deletes the one it named", function()
  E.with(function()
    local shown = E.spyPopups()
    local a, b = CM.Create("target"), CM.Create("focus")
    NS.SelectContainer(b)
    local ctx = E.page("containers", "Containers")
    NS.__renderContainersPage(ctx)
    local button
    local function find(w)
      for _, child in ipairs(w.children or {}) do
        if child.text == "Delete container\226\128\166" then button = child end
        find(child)
      end
    end
    find(ctx.scroll)
    assertTrue(button ~= nil, "the button is drawn")
    button:__fire("OnClick")
    assertEqual(#shown, 1, "a confirm, not a delete")
    assertTrue(CM.Get(b) ~= nil, "nothing is deleted before the answer")
    shown[1].data = b
    NS.SelectContainer(a)
    E.accept(shown[1])
    assertNil(CM.Get(b), "the answer deletes the container the confirm named")
    assertTrue(CM.Get(a) ~= nil)
  end)
end)

test("settings: the Containers Defaults button restores the entry on screen, for the selected container only", function()
  E.with(function()
    local ctx = E.page("containers", "Containers")
    local a, b = CM.Create("target"), CM.Create("focus")
    CM.SetField(a, "layout.spacing", 30)
    CM.SetField(b, "layout.spacing", 30)
    CM.SetField(a, "visibility.combat", "in")
    NS.SelectContainer(a)
    ctx.activeSection = "containers_display"
    ctx.panel.defaultsOnClick()
    assertEqual(CM.Get(a).layout.spacing, NS.CONTAINER_TEMPLATE.layout.spacing, "the Display entry reset")
    assertEqual(CM.Get(a).visibility.combat, "in", "another entry is not reached")
    assertEqual(CM.Get(b).layout.spacing, 30, "nor another container")
    assertEqual(CM.Get(a).name, "Target", "a container keeps its name")
  end)
end)

test("settings: test_open_in_combat_refused — opening a page in combat is refused with the gray line, and a shown page is covered", function()
  E.with(function()
    M.InCombatLockdown = function() return true end
    local answer
    local out = E.capture(function() answer = NS.OpenOptionsPanel("containers") end)
    assertEqual(answer, false, "the open is refused")
    assertTrue(E.said(out, "cannot open settings during combat"), "with the canonical line")
    local lib = M.LibStub("LibKa0s-Options-1.0")
    for _, name in ipairs({ "Containers", "Band sets" }) do
      local panel = M.__subcategories[name]
      panel:Show()
      E.capture(function() panel:__fire("OnShow") end)
      local page
      for c in pairs(lib.__shownPages) do if c.panel == panel then page = c end end
      assertTrue(page ~= nil and page.__combatCover ~= nil and page.__combatCover:IsShown(),
        name .. " is covered in combat")
      panel:Hide()
      panel:__fire("OnHide")
    end
  end)
end)

test("settings: every rail entry is one page key, and every Containers row names a template field", function()
  for key in pairs(CONTAINER_PAGES) do
    assertTrue(#NS.SchemaForPage(key) > 0, key .. " has rows")
  end
  local errors, _, missing = NS.ValidateSchema()
  assertEqual(errors, 0)
  assertEqual(missing, 0, "every container. and bandSet. path resolves against its template")
end)

test("settings: test_element_order_paths_get_set — /rm get|set container.elements.order reads and moves the selected container's elements", function()
  E.with(function()
    local a, b = CM.Create("target"), CM.Create("pet")
    NS.SelectContainer(a)
    local function order(id) return table.concat(CM.Get(id).elements.order, ",") end
    assertTrue(E.said(slash("get container.elements.order"), "indicator,number,text,spells"),
      "the order reads as the element names, comma-separated")
    slash("set container.elements.order spells,text,number,indicator")
    assertEqual(order(a), "spells,text,number,indicator", "a full list is the new order")
    assertEqual(order(b), "indicator,number,text,spells", "on the selected container only")
    slash("set container.elements.order number")
    assertEqual(order(a), "number,spells,text,indicator", "a shorter list moves those to the front, the rest kept in order")
    local out = slash("set container.elements.order number,bogus")
    assertEqual(order(a), "number,spells,text,indicator", "a name that is no element is refused")
    assertTrue(#out > 0, "and the refusal is said")
    slash("set container.elements.order text,text")
    assertEqual(order(a), "number,spells,text,indicator", "an element named twice is refused")
  end)
end)

--- The Display entry's Layout tab, drawn for the selected container: its ctx.
local function layoutTab()
  local ctx = E.page("containers", "Containers")
  ctx.activeSection, ctx.sectionTabs = "containers_display", { containers_display = "Layout" }
  NS.__renderContainersPage(ctx)
  return ctx
end

test("settings: the Display entry's Layout tab draws the element order as a drag list, and a drop writes through the writer", function()
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    CM.SetField(id, "elements.indicator.enabled", true)
    local ctx = layoutTab()
    local list = ctx.rmOrderList
    assertTrue(list ~= nil, "a LibKa0s-Widgets ReorderList is live for the tab")
    assertEqual(#list.rows, 4, "one row per element, every element (an element turned off is still listed)")
    -- Indicator and number on, text and spells off: the ones on first, and only they drag.
    local order = {}
    for i, row in ipairs(ctx.rmOrderRows) do order[i] = row.rmName end
    assertEqual(table.concat(order, ","), "indicator,number,text,spells", "the elements turned on first")
    assertEqual(list.boundary, 2, "a drag stays among the two turned on")
    local labels = E.labels(ctx)
    assertTrue(labels["Element order"], "the list is headed")
    local writes = 0
    local saved = CM.SetField
    CM.SetField = function(cid, field, v)
      if field == "elements.order" then writes = writes + 1 end
      return saved(cid, field, v)
    end
    local ok, err = pcall(function() list.onMove(1, 2) end)
    CM.SetField = saved
    if not ok then error(err, 0) end
    assertEqual(writes, 1, "the drop is one write, through NS.CM.SetField")
    assertEqual(table.concat(CM.Get(id).elements.order, ","), "number,indicator,text,spells",
      "the dragged element lands where it was dropped")
  end)
end)

test("settings: test_element_tick — the tick turns an element on at the end of the drawn ones, the cross off at the head of the rest", function()
  -- red under: an element list with no on/off control, or a toggle that leaves an element turned
  -- on below the ones turned off (drawn in a place the list does not show).
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    CM.SetField(id, "elements.order", { "text", "indicator", "spells", "number" })
    CM.SetField(id, "elements.indicator.enabled", true)
    local ctx = layoutTab()
    local function rowOf(name)
      for _, row in ipairs(ctx.rmOrderRows) do if row.rmName == name then return row end end
    end
    local shown = {}
    for i, row in ipairs(ctx.rmOrderRows) do shown[i] = row.rmName end
    assertEqual(table.concat(shown, ","), "indicator,number,text,spells", "on first, each group in its stored order")
    rowOf("spells").rmGlyph:__fire("OnClick")
    assertTrue(CM.Get(id).elements.spells.enabled, "the tick turned spell chips on")
    assertEqual(table.concat(CM.Get(id).elements.order, ","), "indicator,number,spells,text",
      "at the end of the drawn ones")
    rowOf("indicator").rmGlyph:__fire("OnClick")
    assertFalse(CM.Get(id).elements.indicator.enabled, "the cross turned the indicator off")
    assertEqual(table.concat(CM.Get(id).elements.order, ","), "number,spells,indicator,text",
      "at the head of the ones turned off")
  end)
end)

test("settings: the element order list is canceled before the next render draws anything (options-ui-§18)", function()
  E.with(function()
    NS.SelectContainer(CM.Create("target"))
    local ctx = layoutTab()
    local first = ctx.rmOrderList
    local cleared = false
    local savedClear = NS.Helpers.ClearScroll
    NS.Helpers.ClearScroll = function(...)
      cleared = true
      assertTrue(first.dead, "the old controller is canceled before the scroll is cleared")
      return savedClear(...)
    end
    local ok, err = pcall(NS.__renderContainersPage, ctx)
    NS.Helpers.ClearScroll = savedClear
    if not ok then error(err, 0) end
    assertTrue(cleared, "the render cleared the scroll")
    assertTrue(ctx.rmOrderList ~= first, "and built a new controller")
    ctx.activeSection, ctx.sectionTabs = "containers", {}
    NS.__renderContainersPage(ctx)
    assertTrue(ctx.rmOrderList == nil, "another tab leaves no live controller")
  end)
end)

test("settings: test_position_rows — each attach mode reads as AuraMaster's: its anchor point, this container's, then X and Y", function()
  -- red under: the old single-word "Anchor point" / "Relative point" rows, this container's point first.
  local L = NS.L
  local byPath = {}
  for _, row in ipairs(NS.Schema) do byPath[row.path] = row end
  local function pair(first, second, firstLabel)
    local a, b = byPath[first], byPath[second]
    assertTrue(a ~= nil and b ~= nil, first .. " and " .. second .. " are rows")
    assertEqual(a.label, firstLabel, first)
    assertTrue(a.startsLine == true and not b.startsLine, first .. " opens the line, " .. second .. " beside it")
    assertTrue(a.order < b.order, first .. " first")
    assertEqual(a.subgroup, b.subgroup, "one subsection")
  end
  local THIS = L["This container anchor point"]
  pair("container.anchor.frame.relPoint", "container.anchor.frame.point", L["Unit frame anchor point"])
  assertEqual(byPath["container.anchor.frame.point"].label, THIS)
  pair("container.anchor.frame.x", "container.anchor.frame.y", L["X offset"])
  pair("container.nameplate.relPoint", "container.nameplate.point", L["Nameplate anchor point"])
  assertEqual(byPath["container.nameplate.point"].label, THIS)
  pair("container.nameplate.x", "container.nameplate.y", L["X offset"])
  pair("container.anchor.relPoint", "container.anchor.point", L["Screen anchor point"])
  pair("container.anchor.x", "container.anchor.y", L["X position"])
  pair("container.anchor.cursor.x", "container.anchor.cursor.y", L["X offset"])
  assertEqual(byPath["container.anchor.cursor.point"].label, THIS)
  local strata = byPath["container.anchor.strata"]
  assertNil(strata.shownWhen, "Frame strata applies in every mode, so every mode draws it")
  assertEqual(strata.subgroup, byPath["container.anchor.mode"].subgroup, "under Attach to")
end)

test("settings: Display > Frame > Border ends with Border opacity, a percent slider after the color pair", function()
  -- Red under the v0.1.0 page, which had no border opacity row.
  local border = {}
  for _, row in ipairs(NS.Schema) do
    if row.page == "containers_display" and row.subgroup == NS.L["Border"] then border[#border + 1] = row end
  end
  table.sort(border, function(a, b) return a.order < b.order end)
  local opacity = border[#border]
  assertEqual(opacity.path, "container.frame.border.alpha", "the last Border row")
  assertEqual(opacity.label, NS.L["Border opacity"])
  assertEqual(opacity.group, NS.L["Frame"])
  assertEqual(border[#border - 1].path, "container.frame.border.colorMode", "right after the color pair")
  assertTrue(opacity.isPercent, "shown as a percent")
  assertEqual(opacity.min, 0); assertEqual(opacity.max, 1); assertEqual(opacity.step, 0.05)
end)

-- ── the Display entry's Dot and Spell chips tabs (plan 2026-11-19, M3) ──────────────────────

--- The rows of the Display entry, by path.
local function displayRows()
  local out = {}
  for _, row in ipairs(NS.SchemaForPage("containers_display")) do out[row.path] = row end
  return out
end

test("settings: test_display_tabs — Display carries Layout, Frame, Number, Text, Label, Dot and Spell chips; the rail has no Indicator", function()
  -- red under: the v0.1.0 rail, whose Indicator entry held the dot and the spell chips.
  local L = NS.L
  local groups, seen = {}, {}
  for _, row in ipairs(NS.SchemaForPage("containers_display")) do
    if not seen[row.group] then seen[row.group] = true; groups[#groups + 1] = row.group end
  end
  assertEqual(table.concat(groups, ","), table.concat({ L["Layout"], L["Frame"], L["Number"], L["Text"],
    L["Label"], L["Dot"], L["Spell chips"] }, ","), "the tabs, in order")
  for _, row in ipairs(NS.Schema) do
    assertTrue(row.page ~= "containers_indicator", tostring(row.path) .. " still names the Indicator entry")
  end
  local rows = displayRows()
  for path, group in pairs({
    ["container.elements.indicator.enabled"] = "Dot", ["container.elements.indicator.shape"] = "Dot",
    ["container.elements.indicator.style"] = "Dot", ["container.elements.indicator.size"] = "Dot",
    ["container.elements.indicator.color"] = "Dot", ["container.elements.indicator.colorMode"] = "Dot",
    ["container.elements.spells.enabled"] = "Spell chips", ["container.elements.spells.style"] = "Spell chips",
    ["container.elements.spells.size"] = "Spell chips",
  }) do
    assertTrue(rows[path] ~= nil, path .. " is on the Display entry")
    assertEqual(rows[path].group, L[group], path .. " on the " .. group .. " tab")
  end
  assertEqual(rows["container.elements.indicator.enabled"].label, L["Show dot"])
  local dot = {}
  for _, row in ipairs(NS.SchemaForPage("containers_display")) do
    if row.group == L["Dot"] then dot[#dot + 1] = row.path:match("indicator%.(%a+)$") end
  end
  assertEqual(table.concat(dot, ","), "enabled,shape,size,color,colorMode,style",
    "Show dot, Shape, Size, the color pair, then the Style tiles")
  E.with(function()
    NS.SelectContainer(CM.Create("target"))
    local ctx = E.page("containers", "Containers")
    NS.__renderContainersPage(ctx)
    assertEqual(table.concat(E.railLabels(ctx), ","), "General,Display,Visibility,Sounds")
  end)
end)

test("settings: test_label_tab — the Label tab's rows, in order: show, text, position, align, gap, the Font block", function()
  -- red under: no container.label rows (the caption reachable only by a raw store).
  local L = NS.L
  local got = {}
  for _, row in ipairs(NS.SchemaForPage("containers_display")) do
    if row.group == L["Label"] then got[#got + 1] = row.path:match("^container%.label%.(.+)$") or row.path end
  end
  assertEqual(table.concat(got, ","), "enabled,text,position,align,gap,font,size,color,colorMode,outline,shadow",
    "every Label row is a container.label field, the Font block's color pair included")
  local rows = displayRows()
  local text = rows["container.label.text"]
  assertEqual(text.dialogControl, "EditBox", "the text is typed, and applies on Enter")
  assertEqual(text.default, "", "empty by default: the container's name")
  assertEqual(table.concat(rows["container.label.position"].sorting, ","), "top,bottom,left,right")
  assertEqual(table.concat(rows["container.label.align"].sorting, ","), "left,center,right")
  -- Red under an Align shownWhen that matches Left / Right, or nothing (the path alone was checked).
  local when = rows["container.label.align"].shownWhen
  assertEqual(when.path, "container.label.position", "Align follows Position")
  local eq = {}
  for i, v in ipairs(type(when.equals) == "table" and when.equals or { when.equals }) do eq[i] = v end
  table.sort(eq)
  assertEqual(table.concat(eq, ","), "bottom,top", "Align is drawn for Top and Bottom only")
  assertEqual(table.concat(rows["container.label.colorMode"].sorting or {}, ","), "band,fixed,class",
    "the color mode is the elements' three")
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    slash("set container.label.enabled true")
    slash("set container.label.position left")
    slash("set container.label.text Healer")
    local c = CM.Get(id)
    assertTrue(c.label.enabled, "/rm set reaches the label")
    assertEqual(c.label.position, "left")
    assertEqual(c.label.text, "Healer")
    slash("reset container.label.text")
    assertEqual(c.label.text, "", "a reset gives the name back")
  end)
end)

test("settings: test_element_order_dot — the element order list calls the indicator Dot", function()
  -- red under: the list naming it Indicator, after its rail entry is gone.
  E.with(function()
    NS.SelectContainer(CM.Create("target"))
    local ctx = layoutTab()
    local label
    for i, row in ipairs(ctx.rmOrderRows) do
      if row.rmName == "indicator" then label = ctx.rmOrderList.rows[i].ghostText end
    end
    assertEqual(label, NS.L["Dot"])
  end)
end)

test("settings: test_dot_style_row — the Style row is a dropdown in the schema, reached by /rm set, disabled for Bar and Spell icon", function()
  -- red under: no container.elements.indicator.style row (the style only reachable by a raw store).
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    local row = displayRows()["container.elements.indicator.style"]
    assertTrue(row ~= nil, "the style row exists")
    assertEqual(table.concat(row.sorting, ","), "plain,matte,glossy,glowing,neon,gem")
    assertEqual(row.default, "matte", "matte is the default")
    assertTrue(row.skipRender, "the tiles are its surface")
    slash("set container.elements.indicator.style gem")
    assertEqual(CM.Get(id).elements.indicator.style, "gem", "/rm set reaches it")
    slash("set container.elements.indicator.style chrome")
    assertEqual(CM.Get(id).elements.indicator.style, "gem", "a style that is none is refused")
    for shape, off in pairs({ dot = false, ring = false, star = false, hexagon = false, bar = true, icon = true }) do
      CM.SetField(id, "elements.indicator.shape", shape)
      assertEqual(row.disabledIf(row), off, shape .. (off and " takes no style" or " takes a style"))
    end
  end)
end)

--- The Display entry's Dot tab, drawn for the selected container: its ctx.
local function dotTab()
  local ctx = E.page("containers", "Containers")
  ctx.activeSection, ctx.sectionTabs = "containers_display", { containers_display = NS.L["Dot"] }
  NS.__renderContainersPage(ctx)
  return ctx
end

test("settings: test_dot_style_tiles — the Dot tab draws a tile per style in the stored shape, and a click writes the style", function()
  -- red under: a Dot tab with no tiles (the style only on the CLI), or tiles drawing the old art.
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    CM.SetField(id, "elements.indicator.shape", "hexagon")
    local ctx = dotTab()
    local labels = E.labels(ctx)
    assertTrue(labels[NS.L["Style"]], "the Style heading is drawn")
    assertTrue(labels[NS.L["Show dot"]] and labels[NS.L["Shape"]], "with the rows above it")
    local tiles = ctx.rmStyleTiles or {}
    assertEqual(#tiles, 6, "one tile per style")
    local keys = {}
    for i, tile in ipairs(tiles) do
      keys[i] = tile.rmStyle
      local art = tostring(tile.rmArtPath)
      assertTrue(art:find("indicators\\hexagon_" .. tile.rmStyle, 1, true) ~= nil,
        tile.rmStyle .. " draws the stored shape in that style: " .. art)
    end
    assertEqual(table.concat(keys, ","), "plain,matte,glossy,glowing,neon,gem")
    tiles[5]:__fire("OnClick")
    assertEqual(CM.Get(id).elements.indicator.style, "neon", "a click writes the style")
  end)
end)

test("settings: test_dot_style_tiles_off — for Bar and Spell icon the tiles gray and take no click", function()
  -- red under: tiles that still write a style the bar and the spell icon never draw.
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    CM.SetField(id, "elements.indicator.shape", "bar")
    local ctx = dotTab()
    assertTrue(E.labels(ctx)[NS.L["Bar and Spell icon take no style. Pick a shape to choose its finish."]],
      "the tab says why")
    local tiles = ctx.rmStyleTiles or {}
    assertEqual(#tiles, 6)
    assertTrue(tiles[1].rmOff and tiles[6].rmOff, "grayed")
    tiles[3]:__fire("OnClick")
    assertEqual(CM.Get(id).elements.indicator.style, "matte", "a click stores nothing")
  end)
end)

test("settings: the style tiles are handed back before the next render clears the scroll", function()
  E.with(function()
    NS.SelectContainer(CM.Create("target"))
    local ctx = dotTab()
    local first = ctx.rmStyleTiles[1]
    local savedClear = NS.Helpers.ClearScroll
    local released
    NS.Helpers.ClearScroll = function(...)
      released = #ctx.rmStyleTiles == 0
      return savedClear(...)
    end
    local ok, err = pcall(NS.__renderContainersPage, ctx)
    NS.Helpers.ClearScroll = savedClear
    if not ok then error(err, 0) end
    assertTrue(released, "the old tiles are released before the clear")
    assertEqual(#ctx.rmStyleTiles, 6, "and the new render drew six")
    -- red under: a release that empties the list but never hands the tiles to the free list (every
    -- render would then build six new Buttons and leak the old ones).
    local reused = false
    for _, tile in ipairs(ctx.rmStyleTiles) do
      if tile == first then reused = true end
    end
    assertTrue(reused, "the next render reuses a released tile")
  end)
end)

--- Run `ctx`'s refreshers, as a write from any of its widgets does (O.RefreshScalars).
local function refresh(ctx)
  for _, fn in ipairs(ctx.refreshers or {}) do pcall(fn) end
end

--- Each tile's art tint as "r,g,b", in tile order: what a repaint by the tiles' refresher hands
--- SetVertexColor (the kit's default texture stub keeps no vertex color, so it is recorded here).
local function tints(ctx)
  local out = {}
  for i, tile in ipairs(ctx.rmStyleTiles) do
    rawset(tile.rmArt, "SetVertexColor", function(_, r, g, b) out[i] = table.concat({ r, g, b }, ",") end)
  end
  refresh(ctx)
  for _, tile in ipairs(ctx.rmStyleTiles) do rawset(tile.rmArt, "SetVertexColor", nil) end
  return out
end

test("settings: test_dot_style_tiles_paint — the stored style is the picked tile, tinted as the dot draws, the dot's art for Bar and Spell icon", function()
  -- red under: every tile (or none) edged as picked, a picked fallback other than matte, a tint from
  -- the wrong band or one that ignores the fixed swatch, and Bar or Spell icon tiles drawing no art.
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    local function picked(ctx)
      local out = {}
      for _, tile in ipairs(ctx.rmStyleTiles) do
        if tile.rmPicked then out[#out + 1] = tile.rmStyle end
      end
      return table.concat(out, ",")
    end
    CM.SetField(id, "elements.indicator.style", "glossy")
    local ctx = dotTab()
    assertEqual(picked(ctx), "glossy", "the stored style alone is picked")
    local c = CM.Get(id)
    c.elements.indicator.style = nil
    ctx = dotTab()
    assertEqual(picked(ctx), "matte", "no stored style picks matte")
    local band1 = NS.BandSets.Get(c.bandSet or NS.BandSets.DefaultId()).bands[1].indicatorColor
    assertEqual(tints(ctx)[2], table.concat({ band1.r, band1.g, band1.b }, ","),
      "band mode: the first band's dot color")
    CM.SetField(id, "elements.indicator.colorMode", "fixed")
    CM.SetField(id, "elements.indicator.color", { r = 0.25, g = 0.5, b = 0.75, a = 1 })
    ctx = dotTab()
    assertEqual(tints(ctx)[4], "0.25,0.5,0.75", "fixed mode: the swatch")
    for _, shape in ipairs({ "bar", "icon" }) do
      CM.SetField(id, "elements.indicator.shape", shape)
      ctx = dotTab()
      for _, tile in ipairs(ctx.rmStyleTiles) do
        assertTrue(tostring(tile.rmArtPath):find("indicators\\dot_" .. tile.rmStyle, 1, true) ~= nil,
          shape .. ": the " .. tile.rmStyle .. " tile draws the dot's art")
      end
    end
  end)
end)

test("settings: test_dot_style_tiles_refresh — a Shape or color write repaints the tiles in place, a move to or from Bar redraws the tab", function()
  -- red under: tiles with no refresher of their own (options-ui-§11): they keep the old shape's art
  -- and the old tint, and stay lit for Bar, until something else re-renders the page.
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    local ctx = dotTab()
    local tiles = ctx.rmStyleTiles
    local savedRefresh, asked = NS.RequestPanelRefresh, 0
    NS.RequestPanelRefresh = function() asked = asked + 1 end
    local ok, err = pcall(function()
      NS.SetByPath("container.elements.indicator.shape", "star")
      refresh(ctx)
      assertTrue(tostring(tiles[1].rmArtPath):find("indicators\\star_plain", 1, true) ~= nil,
        "the tiles draw the new shape: " .. tostring(tiles[1].rmArtPath))
      assertEqual(asked, 0, "a shape that takes a style repaints in place, no redraw")
      NS.SetByPath("container.elements.indicator.colorMode", "fixed")
      NS.SetByPath("container.elements.indicator.color", { r = 0.5, g = 0.25, b = 1, a = 1 })
      assertEqual(tints(ctx)[3], "0.5,0.25,1", "the new tint")
      NS.SetByPath("container.elements.indicator.shape", "bar")
      refresh(ctx)
      assertTrue(asked > 0, "Bar asks for a redraw (the note comes, the tiles gray)")
    end)
    NS.RequestPanelRefresh = savedRefresh
    if not ok then error(err, 0) end
    ctx = dotTab()
    assertTrue(ctx.rmStyleTiles[1].rmOff, "and the redraw grays them")
  end)
end)

test("settings: test_dot_style_tiles_onrelease — a release the page does not see still takes the tiles off their slot", function()
  -- red under: no OnRelease on the tiles' slot (options-ui-§19): a clear the Containers renderer
  -- does not run pools the SimpleGroup with the six Buttons still on it.
  E.with(function()
    NS.SelectContainer(CM.Create("target"))
    local ctx = dotTab()
    local tiles = {}
    for i, tile in ipairs(ctx.rmStyleTiles) do tiles[i] = tile end
    local slot = tiles[1].rmSlot
    assertTrue(slot ~= nil, "the tile knows its slot")
    -- What a parent's ReleaseChildren (or another page's clear) does to the slot in the client.
    NS.AceGUI:Release(slot)
    for _, tile in ipairs(tiles) do
      assertTrue(tile.rmParked, "every tile is parked")
      assertFalse(tile:IsShown(), "and hidden")
    end
    assertEqual(#ctx.rmStyleTiles, 0, "the page forgets them")
    ctx = dotTab()
    assertEqual(#ctx.rmStyleTiles, 6, "the next render draws six again")
  end)
end)

test("settings: test_dot_shape_row — the Shape row offers the seven shapes, Bar and Spell icon, and /rm set takes the new ones", function()
  -- red under: SHAPES or SHAPES_SORT without hexagon or star (the panel could not pick them and
  -- /rm set would refuse them).
  E.with(function()
    local id = CM.Create("target")
    NS.SelectContainer(id)
    local row = displayRows()["container.elements.indicator.shape"]
    assertEqual(table.concat(row.sorting, ","), "dot,ring,square,diamond,triangle,hexagon,star,bar,icon")
    for _, key in ipairs(row.sorting) do
      assertTrue(row.values[key] ~= nil, key .. " has a label")
    end
    for _, shape in ipairs({ "hexagon", "star" }) do
      slash("set container.elements.indicator.shape " .. shape)
      assertEqual(CM.Get(id).elements.indicator.shape, shape, "/rm set takes " .. shape)
    end
    slash("set container.elements.indicator.shape blob")
    assertEqual(CM.Get(id).elements.indicator.shape, "star", "a shape that is none is refused")
  end)
end)
