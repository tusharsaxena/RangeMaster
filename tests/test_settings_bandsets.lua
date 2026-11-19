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
    for _, label in ipairs({ "Name", "Match band by", "Unknown label", "Unknown color", "Duplicate band set" }) do
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
