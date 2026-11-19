-- tests/test_settings_bandsets.lua — the Band sets page (settings/BandSets.lua): the `bandSet.<field>`
-- paths, the band editor's writers (modules/BandSets.lua SetField, SetBand, AddBand, RemoveBand) and
-- the delete's re-selection. The v0.1.0 plan, Task 8; design spec section 5.6.

local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local E = dofile("tests/settings_env.lua")
local B, CM = NS.BandSets, NS.CM

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
    items[1].set(was + 1)
    assertEqual(B.Get(id).bands[1].to, was + 1, "the edge control writes through SetBand")
    assertEqual(B.Get(id).bands[2].from, was + 1, "and the next band follows it")
    items[6].set("")
    assertNil(B.Get(id).bands[1].sound, "None clears the band's sound")
  end)
end)
