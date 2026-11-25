-- tests/test_settings_bandsets.lua — the Band sets page (settings/BandSets.lua): the `bandSet.<field>`
-- paths, the band editor's writers (modules/BandSets.lua SetField, SetBand, AddBand, RemoveBand) and
-- the delete's re-selection. The v0.1.0 plan, Task 8; design spec section 5.6.

local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local E = dofile("tests/settings_env.lua")
local B, CM = NS.BandSets, NS.CM

--- The editor item labeled `label` in `items`, or nil.
local function itemLabeled(items, label)
  for _, item in ipairs(items) do
    if item.label == label then return item end
  end
end

local function slash(line) return E.capture(function() NS.Slash:OnSlash(line) end) end

--- The id of the stored band set named `name`.
local function setNamed(name)
  for _, id in ipairs(B.List()) do
    if B.Get(id).name == name then return id end
  end
end

test("bandsets: test_bandset_paths_get_set — /rm set bandSet.matchBy changes the selected band set", function()
  E.with(function()
    local first, second = B.List()[1], B.List()[2]
    NS.SelectBandSet(second)
    slash("set bandSet.matchBy min")
    assertEqual(B.Get(second).matchBy, "min", "the selected set moved")
    assertEqual(B.Get(first).matchBy, "max", "the default set did not")
    assertTrue(E.said(slash("get bandSet.matchBy"), "min"))
    slash("set bandSet.unknown.label ??")
    assertEqual(B.Get(second).unknown.label, "??")
    slash("set bandSet.name Raid healing")
    assertEqual(B.Get(second).name, "Raid healing", "the name goes through Rename")
    NS.SelectBandSet(nil)
    assertTrue(E.said(slash("get bandSet.matchBy"), "max"), "no selection reads the default set")
  end)
end)

test("bandsets: SetBand moves an edge and the next band follows; an edge that would leave no width is refused", function()
  E.with(function()
    local id = setNamed("Melee / Ranged") or B.Create(nil, "melee_ranged")
    local bands = B.Get(id).bands
    assertEqual(bands[1].to, 5)
    assertTrue(B.SetBand(id, 1, "to", 8))
    bands = B.Get(id).bands
    assertEqual(bands[1].to, 8)
    assertEqual(bands[2].from, 8, "the next band starts at the moved edge")
    assertFalse(B.SetBand(id, 1, "to", bands[2].to), "an edge on the next band's far edge is refused")
    assertFalse(B.SetBand(id, 1, "to", 0), "and one before the band's start")
    assertFalse(B.SetBand(id, #bands, "to", 99), "the last band stays open-ended")
    assertTrue(B.SetBand(id, 2, "label", "NEAR"))
    assertEqual(B.Get(id).bands[2].label, "NEAR")
    assertFalse(B.SetBand(id, 2, "label", 5), "a label of the wrong type is refused")
    assertFalse(B.SetBand(id, 2, "sound", "x"), "a sound goes through SetBandSound")
  end)
end)

test("bandsets: AddBand splits the open-ended band, RemoveBand closes the gap, and the last band stays", function()
  E.with(function()
    local id = B.Create("Two", { { from = 0, to = 10, label = "A" }, { from = 10, label = "B" } })
    local index = B.AddBand(id)
    local bands = B.Get(id).bands
    assertEqual(#bands, 3)
    assertEqual(index, 2, "the new band sits before the open-ended one")
    assertEqual(bands[2].from, 10)
    assertEqual(bands[2].to, 15)
    assertEqual(bands[3].from, 15)
    assertNil(bands[3].to, "the last band is still open-ended")
    assertTrue(B.RemoveBand(id, 1))
    bands = B.Get(id).bands
    assertEqual(bands[1].from, 0, "the gap closes: the next band starts at 0")
    assertTrue(B.RemoveBand(id, 1))
    assertFalse(B.RemoveBand(id, 1), "a set keeps one band")
    assertNil(B.Get(id).bands[1].to)
  end)
end)

test("bandsets: SetField refuses what is not a band-set field, and the name is Rename's", function()
  E.with(function()
    local id = B.DefaultId()
    assertFalse(B.SetField(id, "matchBy", "middle"))
    assertFalse(B.SetField(id, "name", "X"), "the name is Rename's")
    assertFalse(B.SetField(id, "bands", {}), "the bands are the band writers'")
    assertTrue(B.SetField(id, "unknown.color", { r = 1, g = 0, b = 0, a = 1 }))
    assertEqual(B.Get(id).unknown.color.r, 1)
  end)
end)

test("bandsets: deleting the selected band set selects its neighbor and moves its containers to the default", function()
  E.with(function()
    local ids = B.List()
    local doomed = ids[2]
    local c = CM.Create("target", { bandSet = doomed })
    assertEqual(CM.Get(c).bandSet, doomed)
    NS.SelectBandSet(doomed)
    assertTrue(NS.DeleteBandSet(doomed) ~= nil)
    local _, selected = NS.SelectedBandSet()
    assertEqual(selected, ids[3], "the next set takes the selection")
    assertEqual(CM.Get(c).bandSet, B.DefaultId(), "its container moved to the default set")
    for _, id in ipairs(B.List()) do
      if id ~= B.DefaultId() then NS.DeleteBandSet(id) end
    end
    assertNil(NS.DeleteBandSet(B.DefaultId()), "the last set is never deleted")
  end)
end)

test("bandsets: the Band sets page draws General and Bands, and the editor's controls reach the writers", function()
  E.with(function()
    local ctx = E.page("bandsets", "Band sets")
    assertTrue(ctx ~= nil, "the Band sets page rendered")
    ctx.activeTab = "General"
    NS.__renderBandSetsPage(ctx)
    local labels = E.labels(ctx)
    for _, label in ipairs({ "Name", "Match band by", "Unknown label", "Unknown color" }) do
      assertTrue(labels[label], "General shows " .. label)
    end
    ctx.activeTab = "Bands"
    NS.__renderBandSetsPage(ctx)
    labels = E.labels(ctx)
    for _, label in ipairs({ "Up to (yards)", "Label", "Frame color", "Text color", "Dot color",
        "Sound on enter", "Add band" }) do
      assertTrue(labels[label], "Bands shows " .. label)
    end
    local set, id = NS.SelectedBandSet()
    -- Red under the Bands tab still drawing the band ribbon over the list (plan M8).
    assertNil(NS.BandRibbon and labels[NS.BandRibbon(set)] or nil, "and no band ribbon over the list")
    local items = NS.__bandItems(id, set, 1)
    local was = set.bands[1].to
    local edge = itemLabeled(items, "Up to (yards)") or itemLabeled(items, "Fallback (yards)")
    edge.set(was + 1)
    assertEqual(B.Get(id).bands[1].to, was + 1, "the edge control writes through SetBand")
    assertEqual(B.Get(id).bands[2].from, was + 1, "and the next band follows it")
    itemLabeled(items, "Sound on enter").set("")
    assertNil(B.Get(id).bands[1].sound, "None clears the band's sound")
  end)
end)

-- ── the band rule controls (dynamic-bands plan D5) ───────────────────────────────────────────

--- A selected set of a yard band, a spell(ranged) band and an open-ended beyond band.
local function ruleSet()
  local id = B.Create("Rules", {
    { from = 0, to = 5, label = "NEAR" },
    { from = 5, to = 40, label = "CAST", rule = { type = "spell", role = "ranged" } },
    { from = 40, label = "OOR", rule = { type = "beyond" } },
  })
  NS.SelectBandSet(id)
  return id
end

--- Run `body` with NS.Range.AnchorFor answering `fn(role, spells)`.
local function withAnchorFor(fn, body)
  local real = NS.Range.AnchorFor
  NS.Range.AnchorFor = fn
  local ok, err = pcall(body)
  NS.Range.AnchorFor = real
  if not ok then error(err, 0) end
end

test("bandsets: Defined by writes the band's rule, and a spell band gets a role from its place", function()
  -- red under: a band editor with no Defined by control (plan D5).
  E.with(function()
    local id = ruleSet()
    local function items(i) return NS.__bandItems(id, B.Get(id), i) end
    local definedBy = itemLabeled(items(1), "Defined by")
    assertTrue(definedBy ~= nil, "every band has Defined by")
    assertEqual(definedBy.get(), "yards", "a band with no rule reads Yards")
    assertEqual(itemLabeled(items(2), "Defined by").get(), "spell")
    assertEqual(itemLabeled(items(3), "Defined by").get(), "beyond")
    definedBy.set("spell")
    local rule = B.Get(id).bands[1].rule
    assertEqual(rule and rule.type, "spell", "Spell writes a spell rule")
    assertEqual(rule and rule.role, "melee", "the first band's role is melee")
    definedBy.set("gap")
    assertEqual(B.Get(id).bands[1].rule.type, "gap", "Dead zone writes a gap rule")
    definedBy.set("yards")
    assertNil(B.Get(id).bands[1].rule, "Yards clears the rule")
    itemLabeled(items(3), "Defined by").set("spell")
    assertEqual(B.Get(id).bands[3].rule.role, "ranged", "a later band's role is ranged")
    assertEqual(B.Get(id).bands[2].from, 5, "no control moves a band's yards")
    assertEqual(B.Get(id).bands[2].to, 40)
  end)
end)

test("bandsets: a spell band's Role and Spell IDs write its rule; a bad list is refused", function()
  E.with(function()
    local id = ruleSet()
    local function items() return NS.__bandItems(id, B.Get(id), 2) end
    assertNil(itemLabeled(NS.__bandItems(id, B.Get(id), 1), "Role"), "a yard band has no Role")
    assertNil(itemLabeled(NS.__bandItems(id, B.Get(id), 3), "Spell IDs"), "nor does beyond have Spell IDs")
    local role = itemLabeled(items(), "Role")
    assertEqual(role.get(), "ranged")
    role.set("friendly")
    assertEqual(B.Get(id).bands[2].rule.role, "friendly", "Role writes the rule's role")
    local ids = itemLabeled(items(), "Spell IDs")
    assertEqual(ids.get(), "", "no override reads empty")
    ids.set(" 3044, 14281 ")
    assertEqual(B.Get(id).bands[2].rule.spells[1], 3044, "the IDs, in order")
    assertEqual(B.Get(id).bands[2].rule.spells[2], 14281)
    assertEqual(B.Get(id).bands[2].rule.role, "friendly", "the role is kept")
    assertEqual(itemLabeled(items(), "Spell IDs").get(), "3044, 14281")
    itemLabeled(items(), "Role").set("ranged")
    assertEqual(#B.Get(id).bands[2].rule.spells, 2, "a role change keeps the override")
    local out = E.capture(function() itemLabeled(items(), "Spell IDs").set("3044, Arcane Shot") end)
    assertTrue(E.said(out, "Spell IDs are whole numbers"), "a list that is not IDs is refused aloud")
    assertEqual(#B.Get(id).bands[2].rule.spells, 2, "and the stored list is kept")
    itemLabeled(items(), "Spell IDs").set("")
    assertNil(B.Get(id).bands[2].rule.spells, "empty: the class's anchors for the role")
  end)
end)

test("bandsets: the read-out names the anchor in use and its reported range, or the fallback yards", function()
  E.with(function()
    local id = ruleSet()
    local band = B.Get(id).bands[2]
    local asked
    withAnchorFor(function(role, spells)
      asked = { role = role, spells = spells }
      return { id = 3044, name = "Arcane Shot", minRange = 8, maxRange = 41 }
    end, function()
      assertEqual(NS.__bandReadout(band), "Now: Arcane Shot (3044), 8\226\128\14741 yd")
      assertEqual(asked.role, "ranged", "it asks the band's role")
    end)
    B.SetBandRule(id, 2, { type = "spell", role = "ranged", spells = { 3044 } })
    band = B.Get(id).bands[2]
    withAnchorFor(function(_, spells)
      asked = spells
      return { id = 2973, name = "Raptor Strike", minRange = 0, maxRange = 0 }
    end, function()
      assertEqual(NS.__bandReadout(band), "Now: Raptor Strike (2973), melee range")
      assertEqual(asked and asked[1], 3044, "and passes the band's own list")
    end)
    withAnchorFor(function() return { id = 3044 } end, function()
      assertEqual(NS.__bandReadout(band), "Now: spell 3044, range not reported")
    end)
    withAnchorFor(function() return nil end, function()
      assertEqual(NS.__bandReadout(band), "Not learned: using 5\226\128\14740 yd")
      assertEqual(NS.__bandReadout(B.Get(id).bands[3]), nil, "a beyond band has no read-out")
      assertEqual(NS.__bandReadout(B.Get(id).bands[1]), nil, "nor does a yard band")
    end)
  end)
end)

test("bandsets: the Bands tab draws the rule controls, Fallback on rule bands, and the rule in each heading", function()
  E.with(function()
    ruleSet()
    local ctx = E.page("bandsets", "Band sets")
    ctx.activeTab = "Bands"
    withAnchorFor(function() return nil end, function() NS.__renderBandSetsPage(ctx) end)
    local labels = E.labels(ctx)
    assertTrue(labels["Defined by"] and labels["Up to (yards)"], "Bands shows the yard band's controls")
    NS.__selectBand(select(2, NS.SelectedBandSet()), 2)
    withAnchorFor(function() return nil end, function() NS.__renderBandSetsPage(ctx) end)
    labels = E.labels(ctx)
    for _, label in ipairs({ "Defined by", "Role", "Spell IDs", "Fallback (yards)",
        "Not learned: using 5\226\128\14740 yd" }) do
      assertTrue(labels[label], "Bands shows " .. label)
    end
    NS.__selectBand(select(2, NS.SelectedBandSet()), 1)
    withAnchorFor(function() return nil end, function() NS.__renderBandSetsPage(ctx) end)
    labels = E.labels(ctx)
    assertTrue(labels["Band 1: 0\226\128\1475 yd NEAR"], "a yard band's heading names no rule")
    local function headingsWith(i)
      NS.__selectBand(select(2, NS.SelectedBandSet()), i)
      withAnchorFor(function() return nil end, function() NS.__renderBandSetsPage(ctx) end)
      return E.labels(ctx)
    end
    assertTrue(headingsWith(2)["Band 2: 5\226\128\14740 yd CAST (Spell: Ranged)"], "a spell band's names its role")
    assertTrue(headingsWith(3)["Band 3: 40+ yd OOR (Beyond the last spell band)"], "and beyond is named")
  end)
end)

test("bandsets: a rebuild that moves an anchor redraws the page (the read-out)", function()
  E.with(function()
    local real, n = NS.RequestPanelRefresh, 0
    NS.RequestPanelRefresh = function() n = n + 1 end
    local ok, err = pcall(function() NS.bus:SendMessage(NS.MSG.ANCHORS_CHANGED) end)
    NS.RequestPanelRefresh = real
    if not ok then error(err, 0) end
    assertTrue(n >= 1, "ANCHORS_CHANGED asks for a redraw")
  end)
end)

-- ── the band rail (plan 2026-11-19 bandsets-rail) ───────────────────────────────────────────

--- The Bands tab of the selected set, drawn; answers the ctx and the labels it drew.
local function drawBands(ctx)
  ctx = ctx or E.page("bandsets", "Band sets")
  ctx.activeTab = "Bands"
  withAnchorFor(function() return nil end, function() NS.__renderBandSetsPage(ctx) end)
  return ctx, E.labels(ctx)
end

--- The rail's entry texts as drawn, the color chip stripped.
local function railTexts()
  local out = {}
  for i, b in ipairs(NS.__bandRail() or {}) do
    out[i] = (tostring(b.__ka0sNavText):gsub("^|T.-|t ", ""))
  end
  return out
end

--- The drawn widget whose text is `text` in `ctx`'s scroll, or nil.
local function widgetWithText(ctx, text)
  local function walk(w)
    for _, child in ipairs(w.children or {}) do
      if child.text == text then return child end
      local hit = walk(child)
      if hit then return hit end
    end
  end
  return walk(ctx.scroll)
end

test("bandsets: the Bands tab lists every band on a rail and draws only the selected band", function()
  -- red under: the long list, every band's controls under its own heading (the layout before the rail).
  E.with(function()
    ruleSet()
    local _, labels = drawBands()
    local texts = railTexts()
    assertEqual(#texts, 3, "one rail entry per band")
    assertEqual(texts[1], "1 NEAR \194\183 0\226\128\1475 yd")
    assertEqual(texts[2], "2 CAST \194\183 5\226\128\14740 yd")
    assertEqual(texts[3], "3 OOR \194\183 40+ yd")
    assertTrue(tostring(NS.__bandRail()[1].__ka0sNavText):find("|T", 1, true) ~= nil,
      "an entry leads with its band's color chip")
    assertTrue(labels["Band 1: 0\226\128\1475 yd NEAR"], "band 1 is selected first")
    assertNil(labels["Band 2: 5\226\128\14740 yd CAST (Spell: Ranged)"], "and the others are not drawn")
    assertNil(labels["Role"], "nor their controls (band 1 is a yard band)")
    assertTrue(labels["Add band"], "Add band sits under the rail")
    assertTrue(labels["Remove band"], "the selected band keeps Remove band")
  end)
end)

test("bandsets: a rail click selects its band, and the selection survives a redraw", function()
  E.with(function()
    ruleSet()
    local ctx = drawBands()
    NS.__bandRail()[2]:__fire("OnClick")
    local _, labels = drawBands(ctx)
    assertTrue(labels["Band 2: 5\226\128\14740 yd CAST (Spell: Ranged)"], "the click shows band 2")
    assertNil(labels["Band 1: 0\226\128\1475 yd NEAR"], "and only band 2")
    assertTrue(labels["Role"], "with its spell controls")
    _, labels = drawBands(ctx)
    assertTrue(labels["Band 2: 5\226\128\14740 yd CAST (Spell: Ranged)"], "a redraw keeps the selection")
  end)
end)

test("bandsets: removing a band selects its neighbor, and Add band selects the new band", function()
  E.with(function()
    local id = B.Create("Four", { { from = 0, to = 5, label = "A" }, { from = 5, to = 10, label = "B" },
      { from = 10, to = 20, label = "C" }, { from = 20, label = "D" } })
    NS.SelectBandSet(id)
    local ctx = drawBands()
    NS.__selectBand(id, 2)
    NS.__removeBand(id, 2)
    assertEqual(NS.__selectedBand(id, B.Get(id)), 2, "the band after it takes the selection")
    assertEqual(B.Get(id).bands[2].label, "C")
    NS.__selectBand(id, 3)
    NS.__removeBand(id, 3)
    assertEqual(NS.__selectedBand(id, B.Get(id)), 2, "removing the last band selects the one before it")
    local _, labels = drawBands(ctx)
    assertTrue(labels["Band 2: 5+ yd C"], "and the page draws it")
    widgetWithText(ctx, "Add band"):__fire("OnClick")
    assertEqual(#B.Get(id).bands, 3)
    assertEqual(NS.__selectedBand(id, B.Get(id)), 2, "the new band, split off the open-ended last one, is selected")
    assertEqual(B.Get(id).bands[2].from, 5, "it is the new band")
    assertEqual(B.Get(id).bands[2].to, 10)
  end)
end)

test("bandsets: an edge change keeps the selected band, and a band the set lost is clamped", function()
  E.with(function()
    local id = ruleSet()
    local ctx = drawBands()
    NS.__selectBand(id, 2)
    itemLabeled(NS.__bandItems(id, B.Get(id), 2), "Fallback (yards)").set(30)
    assertEqual(NS.__selectedBand(id, B.Get(id)), 2, "the band keeps the selection")
    drawBands(ctx)
    assertEqual(railTexts()[2], "2 CAST \194\183 5\226\128\14730 yd", "its entry follows the edge")
    assertEqual(railTexts()[3], "3 OOR \194\183 30+ yd", "and so does the next band's")
    NS.__selectBand(id, 3)
    B.RemoveBand(id, 3)
    assertEqual(NS.__selectedBand(id, B.Get(id)), 2, "a band gone from under the selection clamps to the last")
  end)
end)

test("bandsets: switching band set resets the band selection to band 1", function()
  E.with(function()
    local id = ruleSet()
    local other = B.DefaultId()
    NS.__selectBand(id, 3)
    NS.ShowBandSet(other)
    assertEqual(NS.__selectedBand(other, B.Get(other)), 1, "another set opens on band 1")
    NS.ShowBandSet(id)
    assertEqual(NS.__selectedBand(id, B.Get(id)), 1, "and so does coming back")
  end)
end)

-- ── the header, the grouped picker, the origin line and the preset view (RangeMaster#21, BS-02) ──

local ELLIPSIS = "\226\128\166"

--- The Band sets page drawn on tab `tab` (General when nil); answers the ctx, its labels and header.
local function drawPage(tab)
  local ctx = E.page("bandsets", "Band sets")
  ctx.activeTab = tab or "General"
  withAnchorFor(function() return nil end, function() NS.__renderBandSetsPage(ctx) end)
  return ctx, E.labels(ctx), NS.__bandSetHeader(ctx)
end

--- The texts of the header's acts, in order.
local function actTexts(hdr)
  local out = {}
  for i, w in ipairs(hdr.acts) do out[i] = w.text end
  return out
end

--- Run `body` with NS[name] replaced by a recorder; answers the calls' first arguments.
local function spying(name, body)
  local real, calls = NS[name], {}
  NS[name] = function(arg) calls[#calls + 1] = arg end
  local ok, err = pcall(body)
  NS[name] = real
  if not ok then error(err, 0) end
  return calls
end

--- Every control drawn in `ctx`'s scroll that a player can change, with whether it is disabled.
local CONTROL = { EditBox = true, Dropdown = true, CheckBox = true, Slider = true, ColorPicker = true,
  Button = true, Ka0sMedia_Sound = true }
local function controls(ctx)
  local out = {}
  local function walk(w)
    for _, child in ipairs(w.children or {}) do
      if CONTROL[child.type] then out[#out + 1] = child end
      walk(child)
    end
  end
  walk(ctx.scroll)
  return out
end

test("bandsets: the header holds the picker and New, Duplicate, Copy bands from and Delete; General has none", function()
  -- red under: the picker and New band set in the banner, Duplicate and Delete under General.
  E.with(function()
    local _, labels, hdr = drawPage()
    assertTrue(hdr ~= nil, "the page draws its header")
    assertEqual(hdr.picker.labelText, "Band set")
    local texts = actTexts(hdr)
    assertEqual(#texts, 4)
    assertEqual(texts[1], "New" .. ELLIPSIS)
    assertEqual(texts[2], "Duplicate")
    assertEqual(texts[3], "Copy bands from" .. ELLIPSIS)
    assertEqual(texts[4], "Delete" .. ELLIPSIS)
    for _, w in ipairs(hdr.acts) do assertFalse(w.disabled, w.text .. " is enabled on one of your sets") end
    assertNil(labels["Duplicate band set"], "General no longer carries Duplicate")
    assertNil(labels["Delete band set" .. ELLIPSIS], "nor Delete")
    assertNil(labels["Duplicate"], "nor the header's")
    for _, id in ipairs(B.List()) do
      if id ~= B.DefaultId() then NS.DeleteBandSet(id) end
    end
    hdr = NS.__bandSetHeader((drawPage()))
    assertTrue(hdr.acts[4].disabled, "Delete is disabled on the last set")
    assertFalse(hdr.acts[2].disabled, "Duplicate is not")
  end)
end)

test("bandsets: the header's acts reach Duplicate, Delete and the dialogs' call sites", function()
  E.with(function()
    local _, id = NS.SelectedBandSet()
    local _, _, hdr = drawPage()
    local n = #B.List()
    hdr.acts[2]:__fire("OnClick")
    assertEqual(#B.List(), n + 1, "Duplicate makes a copy")
    assertTrue(select(2, NS.SelectedBandSet()) ~= id, "and selects it")
    local copies = spying("ShowCopyBandsDialog", function() select(3, drawPage()).acts[3]:__fire("OnClick") end)
    assertEqual(#copies, 1, "Copy bands from opens its dialog")
    assertEqual(copies[1].into, select(2, NS.SelectedBandSet()), "into the set shown")
    local news = spying("ShowNewBandSetDialog", function() select(3, drawPage()).acts[1]:__fire("OnClick") end)
    assertEqual(#news, 1, "New opens its dialog")
    local shown = E.spyPopups()
    select(3, drawPage()).acts[4]:__fire("OnClick")
    assertEqual(shown[1] and shown[1].which, "RANGEMASTER_DELETE_BANDSET", "Delete asks first")
  end)
end)

test("bandsets: the picker lists your sets, then the class presets, then the general ones, under group rows", function()
  -- red under: a picker of the player's sets alone.
  E.with(function()
    local list, order, headers = NS.__bandSetPickerEntries()
    local keys = B.PresetKeys()
    assertEqual(#keys.classes, NS.Compat.ClientKey() == "forever" and 9 or 13, "every class preset this client has")
    assertEqual(#headers, 3, "three group rows")
    assertEqual(order[1], headers[1], "Your band sets leads")
    assertTrue(list[headers[1]]:find("Your band sets", 1, true) ~= nil)
    local ids = B.List()
    for i, id in ipairs(ids) do assertEqual(order[i + 1], id, "your sets in order, under it") end
    assertTrue(list[ids[1]]:find("(default)", 1, true) ~= nil, "the default set is tagged")
    assertNil(list[ids[2]]:find("(default)", 1, true), "and only the default")
    local at = #ids + 2
    assertEqual(order[at], headers[2])
    assertTrue(list[headers[2]]:find("Shipped presets \194\183 Classes", 1, true) ~= nil)
    for i, key in ipairs(keys.classes) do assertEqual(order[at + i], "preset:" .. key, "the classes in class order") end
    at = at + #keys.classes + 1
    assertEqual(order[at], headers[3])
    assertTrue(list[headers[3]]:find("Shipped presets \194\183 General", 1, true) ~= nil)
    for i, key in ipairs(keys.general) do assertEqual(order[at + i], "preset:" .. key, "then the general presets") end
    assertEqual(#order, at + #keys.general, "and nothing else")
    local mage = list["preset:mage"]
    assertTrue(mage:find("(your class)", 1, true) ~= nil, "your class is tagged")
    assertTrue(mage:find("|cff", 1, true) == 1, "in its class color")
    assertNil(list["preset:priest"]:find("(your class)", 1, true), "and only yours")
    assertNil(list["preset:melee_ranged"]:find("|cff", 1, true), "a general preset takes no class color")
  end)
end)

test("bandsets: a group row picks nothing, a preset is viewed, and one of your sets ends the view", function()
  E.with(function()
    local _, id = NS.SelectedBandSet()
    NS.__chooseBandSet("header:mine")
    assertNil(NS.ViewedPreset(), "a group row views nothing")
    assertEqual(select(2, NS.SelectedBandSet()), id, "and keeps the selection")
    NS.__chooseBandSet("preset:caster40")
    assertEqual(NS.ViewedPreset(), "caster40", "a preset is viewed")
    assertEqual(select(2, NS.SelectedBandSet()), id, "the selection stays, for /rm get")
    local _, _, hdr = drawPage()
    assertEqual(hdr.picker.value, "preset:caster40", "the picker shows the preset")
    NS.__chooseBandSet(id)
    assertNil(NS.ViewedPreset(), "choosing your own set (the same one) ends the view")
    assertFalse(NS.ViewPreset("BY_CLIENT"), "a module field is no preset")
    assertFalse(NS.ViewPreset("nope"))
  end)
end)

test("bandsets: a modified set is tagged, and the origin line names its preset, the change and Restore", function()
  -- red under: no origin line and no modified tag.
  E.with(function()
    local set, id = NS.SelectedBandSet()
    assertEqual(set.origin, "mage", "the seeded default is the class preset")
    local _, _, hdr = drawPage()
    assertEqual(hdr.origin and hdr.origin.text, "From the Mage preset")
    assertEqual(hdr.originActs[1].text, "Restore Mage preset" .. ELLIPSIS)
    assertTrue(hdr.originActs[1].disabled, "Restore is disabled while the set matches its preset")
    assertNil(NS.__bandSetPickerEntries()[id]:find("modified", 1, true))
    B.SetBand(id, 1, "label", "XX")
    _, _, hdr = drawPage()
    assertEqual(hdr.origin.text, "From the Mage preset \194\183 modified (band 1 label)")
    assertFalse(hdr.originActs[1].disabled, "a modified set can be restored")
    assertTrue(NS.__bandSetPickerEntries()[id]:find("modified", 1, true) ~= nil, "the picker tags it")
    local restores = spying("ShowRestoreBandSetDialog", function() hdr.originActs[1]:__fire("OnClick") end)
    assertEqual(restores[1], id, "Restore opens its dialog for the set")
    B.SetField(id, "matchBy", "min")
    B.SetBand(id, 2, "label", "YY")
    assertEqual(NS.__bandSetOriginLine().text,
      "From the Mage preset \194\183 modified (match rule, band 1 label and 1 more)", "two, then how many more")
    local blank = B.Create("Blank", { { from = 0, label = "ANY" } })
    NS.SelectBandSet(blank)
    _, _, hdr = drawPage()
    assertNil(hdr.origin, "a set with no preset has no origin line")
  end)
end)

test("bandsets: a viewed preset draws read-only: every control disabled, New alone enabled", function()
  -- red under: a preset with no view, or a view whose controls still write.
  E.with(function()
    local before = B.Snapshot()
    NS.__chooseBandSet("preset:melee_ranged")
    local ctx, labels, hdr = drawPage()
    assertFalse(hdr.acts[1].disabled, "New stays enabled")
    for i = 2, 4 do assertTrue(hdr.acts[i].disabled, hdr.acts[i].text .. " is disabled") end
    assertEqual(hdr.origin.text, "A shipped preset: read-only. Make it yours to use it on a container or to edit it.")
    assertEqual(hdr.originActs[1].text, "Use this preset" .. ELLIPSIS)
    assertEqual(hdr.originActs[2].text, "Copy into a set of mine" .. ELLIPSIS)
    for _, label in ipairs({ "Name", "Match band by", "Unknown label", "Unknown color" }) do
      assertTrue(labels[label], "General shows the preset's " .. label)
    end
    assertNil(labels["No container uses this band set."], "and no Used by line: a preset is on no container")
    local general = controls(ctx)
    assertTrue(#general >= 4, "General draws its controls")
    for _, w in ipairs(general) do assertTrue(w.disabled, tostring(w.labelText or w.text) .. " is disabled") end
    local name
    for _, w in ipairs(general) do if w.labelText == "Name" then name = w end end
    assertEqual(name and (name.text or name.value), B.PresetSet("melee_ranged").name, "it reads the preset")
    ctx, labels = drawPage("Bands")
    assertTrue(labels["Add band"] and labels["Remove band"], "Bands draws the preset's bands")
    assertEqual(#NS.__bandRail(), #B.PresetSet("melee_ranged").bands, "one rail entry per preset band")
    for _, w in ipairs(controls(ctx)) do assertTrue(w.disabled, tostring(w.labelText or w.text) .. " is disabled") end
    local viewId = "preset:melee_ranged"
    local items = NS.__bandItems(viewId, B.PresetSet("melee_ranged"), 1)
    itemLabeled(items, "Label").set("XX")
    NS.__removeBand(viewId, 1)
    assertEqual(NS.Database.DeepCopy(B.Snapshot()).bandSets[1].bands[1].label, before.bandSets[1].bands[1].label,
      "a write through a preset's control reaches no stored set")
    assertEqual(#B.List(), #before.bandSetOrder)
  end)
end)

test("bandsets: Use this preset and Copy into a set of mine open their dialogs with the preset", function()
  E.with(function()
    NS.__chooseBandSet("preset:healer")
    local _, _, hdr = drawPage()
    local news = spying("ShowNewBandSetDialog", function() hdr.originActs[1]:__fire("OnClick") end)
    assertEqual(news[1] and news[1].preset, "healer", "the New dialog, prefilled with the preset")
    assertEqual(news[1].name, B.PresetSet("healer").name, "and its name")
    local copies = spying("ShowCopyBandsDialog", function() hdr.originActs[2]:__fire("OnClick") end)
    assertEqual(copies[1] and copies[1].from and copies[1].from.preset, "healer", "Copy bands from, the preset its source")
    assertNil(copies[1].into, "the set to copy into is asked")
    local n = #B.List()
    local id = NS.ShowNewBandSetDialog({ preset = "healer", name = B.PresetSet("healer").name })
    assertEqual(#B.List(), n + 1, "until BS-03, New creates the set at once")
    assertEqual(B.Get(id).origin, "healer", "from the preset")
    assertEqual(select(2, NS.SelectedBandSet()), id, "and selects it")
    assertNil(NS.ViewedPreset(), "which ends the view")
  end)
end)

test("bandsets: /rm set bandSet.* and Defaults refuse while a preset is viewed; /rm bands ends the view", function()
  E.with(function()
    local _, id = NS.SelectedBandSet()
    NS.ViewPreset("caster40")
    local out = slash("set bandSet.matchBy min")
    assertTrue(E.said(out, "read-only"), "the write is refused aloud")
    assertEqual(B.Get(id).matchBy, "max", "and the selected set is untouched")
    slash("set bandSet.name Hijacked")
    assertTrue(B.Get(id).name ~= "Hijacked", "a name too")
    local ctx = drawPage()
    out = E.capture(function() ctx.panel.defaultsOnClick() end)
    assertTrue(E.said(out, "read-only"), "Defaults refuses too")
    slash("bands 1")
    assertNil(NS.ViewedPreset(), "/rm bands <n> selects a set and ends the view")
    slash("set bandSet.matchBy min")
    assertEqual(B.Get(B.List()[1]).matchBy, "min", "and writes reach the set again")
  end)
end)

test("bandsets: the Defaults tooltip points to Restore for the bands", function()
  -- red under: the tooltip that sent the player to Delete band set for the bands.
  E.with(function()
    local tip = tostring(drawPage().panel.defaultsTooltip)
    assertTrue(tip:find("its bands are kept", 1, true) ~= nil, "Defaults keeps the bands")
    assertTrue(tip:find("Restore preset", 1, true) ~= nil, "and the tooltip names Restore preset for them")
    assertNil(tip:find("Delete band set", 1, true), "not Delete")
  end)
end)
