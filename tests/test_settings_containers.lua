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
  containers = "General", containers_display = "Display", containers_indicator = "Indicator",
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
    assertEqual(rail, "General,Display,Indicator,Visibility,Sounds", "a target container lists all five")
    assertEqual(ctx.activeSection, "containers_sounds", "and the page is on Sounds")
    NS.SelectContainer(plates)
    NS.__renderContainersPage(ctx)
    rail = table.concat(E.railLabels(ctx), ",")
    assertEqual(rail, "General,Display,Indicator,Visibility", "a nameplates container lists no Sounds")
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
    assertTrue(labels["Preview"], "and the band preview")
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
