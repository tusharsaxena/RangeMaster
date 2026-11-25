-- tests/test_settings_bandset_dialogs.lua — the Band sets page's dialogs and Undo
-- (settings/BandSetDialogs.lua; RangeMaster#21, BS-03): New…, Copy bands from…, Restore <Preset>
-- preset…, `/rm bands undo`, and Add band beside Remove band under the rail (settings/BandSets.lua).

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local E = dofile("tests/settings_env.lua")
local B = NS.BandSets

--- Run `body` on a fresh profile with no dialog up before or after.
local function with(body)
  E.with(function(p)
    NS.HideBandSetDialog()
    local ok, err = pcall(body, p)
    NS.HideBandSetDialog()
    if not ok then error(err, 0) end
  end)
end

local function dialog() return NS.__bandSetDialog() end

local function slash(line) return E.capture(function() NS.Slash:OnSlash(line) end) end

--- The id of the stored band set named `name`.
local function setNamed(name)
  for _, id in ipairs(B.List()) do
    if B.Get(id).name == name then return id end
  end
end

--- Press the dialog's act (Create, Copy, Restore); answers the chat lines it printed.
local function act() return E.capture(function() dialog().w.act:__fire("OnClick") end) end

--- Choose `v` in dropdown `w`, as a click in its list does.
local function pick(w, v) w:__fire("OnValueChanged", v) end

--- A set of four bands with sounds, made from no preset.
local function four()
  local id = B.Create("Four", { { from = 0, to = 5, label = "A", sound = "s1" },
    { from = 5, to = 10, label = "B", sound = "s2" }, { from = 10, to = 20, label = "C" }, { from = 20, label = "D" } })
  return id
end

-- ── the window ───────────────────────────────────────────────────────────────────────────────

test("bandset dialogs: one companion window, modal and on Escape's list, closed by Cancel", function()
  with(function()
    -- The window built afresh under the kit's layer recorder, so its strata can be read back.
    local restore = dofile("tests/_kit/mock_layers.lua")(M)
    dialog().frame = nil
    local ok, d = pcall(NS.ShowNewBandSetDialog, {})
    local layers = ok and d and M.__layers(d.frame)
    restore()
    if not ok then error(d, 0) end
    assertTrue(d ~= nil and d.kind == "new", "New opens its dialog")
    local f = d.frame
    assertTrue(f:IsShown())
    assertEqual(d.title, "New band set")
    assertEqual(layers.strata, NS.Constants.LAYERS.STRATA.MODAL, "modal strata")
    assertTrue(layers.toplevel and layers.clamped, "toplevel and clamped")
    local listed = false
    for _, name in ipairs(M.UISpecialFrames) do
      if name == "RangeMasterBandSetDialog" then listed = true end
    end
    assertTrue(listed, "Escape closes it")
    local hb = f.headerButtons
    if hb then
      assertTrue(hb.companion, "a companion window: the close and no settings mark")
      assertNil(hb.settings)
    end
    local block = d.block
    d.w.cancel:__fire("OnClick")
    assertFalse(f:IsShown(), "Cancel closes it")
    assertTrue(block.__released, "and its body is released")
    assertNil(dialog().kind)
  end)
end)

-- ── New… ─────────────────────────────────────────────────────────────────────────────────────

test("bandset dialogs: New starts from your class's preset, named after it and made unique", function()
  -- red under: the stand-in, which made the set at once with no dialog.
  with(function()
    local n = #B.List()
    local d = NS.ShowNewBandSetDialog({})
    assertEqual(#B.List(), n, "nothing is made until Create")
    assertEqual(d.w.presetList.value, "preset:mage", "the preset list starts on your class")
    assertTrue(d.w.preset.value and not d.w.copy.value and not d.w.blank.value, "A shipped preset is chosen")
    assertEqual(d.w.preset.checkType, "radio")
    assertEqual(d.w.name.text, "Mage 2", "the preset's name, unique beside the seeded Mage set")
    assertFalse(d.w.presetList.disabled)
    assertTrue(d.w.copyList.disabled, "only the chosen start's list is enabled")
    local out = act()
    local id = setNamed("Mage 2")
    assertTrue(id ~= nil, "Create makes the set")
    assertEqual(B.Get(id).origin, "mage", "from the preset")
    assertEqual(select(2, NS.SelectedBandSet()), id, "and selects it")
    assertFalse(d.frame:IsShown(), "the dialog closes")
    assertTrue(E.said(out, "Mage 2"))
  end)
end)

test("bandset dialogs: New's name follows the start until it is typed in", function()
  with(function()
    local d = NS.ShowNewBandSetDialog({})
    pick(d.w.presetList, "preset:healer")
    assertEqual(d.w.name.text, B.UniqueName(B.PresetSet("healer").name), "a preset picked renames it")
    d.w.blank:__fire("OnValueChanged", true)
    assertTrue(d.w.blank.value and not d.w.preset.value, "the radios are one choice")
    assertEqual(d.w.name.text, "New band set")
    assertTrue(d.w.presetList.disabled and d.w.copyList.disabled)
    d.w.name:SetText("Mine")
    d.w.name:__fire("OnTextChanged", "Mine")
    d.w.preset:__fire("OnValueChanged", true)
    assertEqual(d.w.name.text, "Mine", "a typed name stays")
    pick(d.w.presetList, "header:classes")
    assertEqual(d.w.presetList.value, "preset:healer", "a group row picks nothing")
  end)
end)

test("bandset dialogs: New makes a blank set, a copy of one of yours, or the preset Use this preset names", function()
  with(function()
    local d = NS.ShowNewBandSetDialog({})
    d.w.blank:__fire("OnValueChanged", true)
    d.w.name:SetText("Empty")
    act()
    local blank = setNamed("Empty")
    assertEqual(#B.Get(blank).bands, 1, "blank is one band")
    assertNil(B.Get(blank).bands[1].to, "open-ended")
    assertNil(B.Get(blank).origin, "from no preset")

    local src = B.List()[1]
    B.SetBandSound(src, 1, "Ping")
    d = NS.ShowNewBandSetDialog({})
    d.w.copy:__fire("OnValueChanged", true)
    pick(d.w.copyList, src)
    assertEqual(d.w.name.text, "Mage copy", "a copy is named after its set")
    d.w.name:SetText("Mage")
    act()
    local copy = setNamed("Mage 2")
    assertTrue(copy ~= nil, "a taken name gets a number")
    assertEqual(B.Get(copy).origin, "mage", "the copy keeps the set's preset")
    assertEqual(B.Get(copy).bands[1].sound, "Ping", "and its sounds")
    assertEqual(#B.Get(copy).bands, #B.Get(src).bands)

    NS.ViewPreset("healer")
    d = NS.ShowNewBandSetDialog({ preset = "healer", name = B.PresetSet("healer").name })
    assertEqual(d.w.presetList.value, "preset:healer", "Use this preset prefills the preset")
    assertEqual(d.w.name.text, B.UniqueName(B.PresetSet("healer").name), "and its name")
    act()
    local id = select(2, NS.SelectedBandSet())
    assertEqual(B.Get(id).origin, "healer")
    assertNil(NS.ViewedPreset(), "the new set ends the view")
  end)
end)

-- ── Copy bands from… ─────────────────────────────────────────────────────────────────────────

test("bandset dialogs: Copy bands from copies into the current set from your others, then every preset", function()
  with(function()
    local into = four()
    NS.SelectBandSet(into)
    local d = NS.ShowCopyBandsDialog({ into = into })
    assertEqual(d.kind, "copy")
    assertNil(d.w.into, "the current set is the target, not asked")
    local from = d.w.from
    assertEqual(from.order[1], "header:mine", "Your band sets lead the sources")
    for _, v in ipairs(from.order) do assertTrue(v ~= into, "the target is no source") end
    local others, presets = 0, 0
    for _, v in ipairs(from.order) do
      if type(v) == "number" then
        others = others + 1
        assertEqual(presets, 0, "your sets come before the presets")
      elseif tostring(v):find("preset:", 1, true) == 1 then
        presets = presets + 1
      end
    end
    assertEqual(others, #B.List() - 1)
    local keys = B.PresetKeys()
    assertEqual(presets, #keys.classes + #keys.general, "then every preset")
    assertEqual(from.value, B.List()[1], "starting on your first other set")
    assertTrue(d.w.bands.value and d.w.bands.disabled, "Bands is always on")
    assertTrue(d.w.sounds.value, "Sounds on enter starts on")
    assertFalse(d.w.general.value, "Match rule and unknown starts off")
    pick(from, "preset:melee_ranged")
    local n = #B.PresetSet("melee_ranged").bands
    assertEqual(d.w.summary.text, ("Four's 4 bands are replaced by %s's %d. Its name and the containers using it stay.")
      :format(B.PresetSet("melee_ranged").name, n))
    d.w.general:__fire("OnValueChanged", true)
    assertTrue(d.w.summary.text:find("So are its match rule", 1, true) ~= nil, "the summary says what else goes")
    B.SetField(into, "matchBy", "min")
    local out = act()
    assertEqual(#B.Get(into).bands, n, "the bands are the preset's")
    assertEqual(B.Get(into).name, "Four", "the name stays")
    assertEqual(B.Get(into).matchBy, B.PresetSet("melee_ranged").matchBy, "the match rule came too")
    assertEqual(B.Get(into).origin, "melee_ranged")
    assertTrue(E.said(out, "/rm bands undo"), "the chat line offers the Undo")
    assertFalse(d.frame:IsShown())
  end)
end)

test("bandset dialogs: Copy with Sounds on enter off keeps each band's sound by its place", function()
  with(function()
    local into, src = four(), B.Create("Src", { { from = 0, to = 8, label = "X", sound = "other" }, { from = 8, label = "Y" } })
    local d = NS.ShowCopyBandsDialog({ into = into, from = src })
    assertEqual(d.w.from.value, src, "the source asked for")
    d.w.sounds:__fire("OnValueChanged", false)
    act()
    assertEqual(B.Get(into).bands[1].label, "X")
    assertEqual(B.Get(into).bands[1].sound, "s1", "band 1 keeps its own sound")
    assertEqual(B.Get(into).bands[2].sound, "s2")
    assertNil(B.Get(into).origin, "a set with no preset passes on none")
  end)
end)

test("bandset dialogs: Copy into a set of mine asks for the target and keeps the source off it", function()
  with(function()
    local mine = four()
    NS.SelectBandSet(mine)
    NS.ViewPreset("healer")
    local d = NS.ShowCopyBandsDialog({ from = { preset = "healer" } })
    assertTrue(d.w.into ~= nil, "the target is asked")
    assertEqual(d.w.into.value, mine, "starting on the selected set")
    assertEqual(d.w.from.value, "preset:healer", "from the preset viewed")
    local other = B.List()[1]
    pick(d.w.from, other)
    pick(d.w.into, other)
    assertTrue(d.w.from.value ~= other, "a target never copies into itself")
    for _, v in ipairs(d.w.from.order) do assertTrue(v ~= other) end
    assertTrue(d.w.summary.text:find(B.Get(other).name, 1, true) == 1, "the summary follows the target")
    pick(d.w.from, "preset:healer")
    act()
    assertEqual(B.Get(other).origin, "healer", "the chosen target took the preset")
    assertEqual(select(2, NS.SelectedBandSet()), other, "and is selected")
    assertNil(NS.ViewedPreset(), "which ends the view")
  end)
end)

-- ── Restore <Preset> preset… ─────────────────────────────────────────────────────────────────

test("bandset dialogs: Restore lists the differences, eight at most, then restores behind Keep my sounds", function()
  with(function()
    local id = B.List()[1]
    assertEqual(B.Get(id).origin, "mage")
    local before = E.capture(function() assertNil(NS.ShowRestoreBandSetDialog(id)) end)
    assertTrue(E.said(before, "already matches"), "an unmodified set has nothing to restore")
    local was = B.Get(id).bands[1].label
    B.SetBand(id, 1, "label", "HOLY")
    B.SetBandSound(id, 1, "Ping")
    local d = NS.ShowRestoreBandSetDialog(id)
    assertEqual(d.kind, "restore")
    assertEqual(d.title, "Restore Mage preset")
    assertEqual(#d.w.lines, 1)
    assertEqual(d.w.lines[1].text, ("Band 1 label: HOLY -> %s"):format(was))
    assertNil(d.w.more)
    assertTrue(d.w.keep.value, "Keep my sounds starts on")
    local out = act()
    assertEqual(B.Get(id).bands[1].label, was, "the preset's label is back")
    assertEqual(B.Get(id).bands[1].sound, "Ping", "the sound was kept")
    assertFalse(B.IsModified(id))
    assertTrue(E.said(out, "Restored 'Mage' to the Mage preset. /rm bands undo puts it back."))

    for i = 1, #B.Get(id).bands do
      B.SetBand(id, i, "label", "Z" .. i)
      B.SetBand(id, i, "frameColor", { r = 0.1, g = 0.2, b = 0.3 })
      B.SetBand(id, i, "textColor", { r = 0.1, g = 0.2, b = 0.3 })
      B.SetBand(id, i, "indicatorColor", { r = 0.1, g = 0.2, b = 0.3 })
    end
    B.SetField(id, "matchBy", "min")
    B.SetField(id, "unknown.label", "??")
    B.SetBandSound(id, 1, "Ping")
    local diff = B.Diff(id)
    assertTrue(#diff > 8, "a set changed in more than eight ways")
    d = NS.ShowRestoreBandSetDialog(id)
    assertEqual(#d.w.lines, 8, "eight lines")
    assertEqual(d.w.more.text, ("and %d more"):format(#diff - 8), "then how many more")
    assertEqual(d.w.lines[1].text, "Match rule: Lower bound (nearest range) -> Upper bound (farthest range)")
    d.w.keep:__fire("OnValueChanged", false)
    act()
    assertNil(B.Get(id).bands[1].sound, "without Keep my sounds the preset's bands carry none")
  end)
end)

test("bandset dialogs: Restore refuses a set with no preset", function()
  with(function()
    local id = four()
    local out = E.capture(function() assertNil(NS.ShowRestoreBandSetDialog(id)) end)
    assertTrue(E.said(out, "nothing to restore"))
    assertFalse(dialog().frame ~= nil and dialog().frame:IsShown() or false)
  end)
end)

test("bandset dialogs: a difference reads as its band, its field and both sides", function()
  local line = NS.__bandSetDiffLine
  assertEqual(line({ band = 2, field = "to", mine = 12, preset = 10 }), "Band 2 edge: 12 yd -> 10 yd")
  assertEqual(line({ band = 4, field = "to", mine = 30 }), "Band 4 edge: 30 yd -> no limit")
  assertEqual(line({ field = "bands", mine = 5, preset = 4 }), "Band count: 5 -> 4")
  assertEqual(line({ band = 1, field = "rule", mine = { type = "spell", role = "ranged" } }),
    "Band 1 rule: Spell: Ranged -> Yards")
  assertEqual(line({ field = "unknown.label", mine = "", preset = "?" }), "Unknown label: (none) -> ?")
  assertEqual(line({ band = 1, field = "frameColor", mine = { r = 1, g = 0, b = 0 }, preset = { r = 0, g = 1, b = 0 } }),
    "Band 1 frame color: |cffff0000#FF0000|r -> |cff00ff00#00FF00|r")
end)

-- ── Undo ─────────────────────────────────────────────────────────────────────────────────────

test("bandset dialogs: /rm bands undo puts back what a Copy replaced, and only that set", function()
  with(function()
    assertTrue(E.said(slash("bands undo"), "Nothing to undo"), "nothing to undo on a fresh profile")
    local into = four()
    local other = B.List()[1]
    local was = NS.Database.DeepCopy(B.Get(into))
    NS.ShowCopyBandsDialog({ into = into, from = { preset = "caster40" } })
    act()
    assertTrue(#B.Get(into).bands ~= 4 or B.Get(into).bands[1].label ~= "A", "the copy landed")
    B.SetBand(other, 1, "label", "KEEP")
    local made = B.Create("Later", "healer")
    local out = slash("bands undo")
    assertTrue(E.said(out, "Undone: 'Four' is back as it was."))
    local now = B.Get(into)
    assertEqual(#now.bands, 4)
    for i, b in ipairs(was.bands) do
      assertEqual(now.bands[i].label, b.label)
      assertEqual(now.bands[i].sound, b.sound)
    end
    assertNil(now.origin)
    assertEqual(B.Get(other).bands[1].label, "KEEP", "an edit to another set since stays")
    assertTrue(B.Get(made) ~= nil, "and a set made since stays")
    assertEqual(select(2, NS.SelectedBandSet()), into, "the set undone is selected")
    assertTrue(E.said(slash("bands undo"), "Nothing to undo"), "one level")
  end)
end)

test("bandset dialogs: Undo follows a Restore, refuses a deleted set and is forgotten on a profile change", function()
  with(function()
    local id = B.List()[1]
    B.SetBand(id, 1, "label", "HOLY")
    NS.ShowRestoreBandSetDialog(id)
    act()
    assertTrue(NS.CanUndoBandSets())
    assertTrue(NS.UndoBandSets(), "a restore is undone")
    assertEqual(B.Get(id).bands[1].label, "HOLY", "the modified label is back")

    local doomed = four()
    NS.ShowCopyBandsDialog({ into = doomed, from = id })
    act()
    NS.DeleteBandSet(doomed)
    assertTrue(E.said(slash("bands undo"), "deleted"), "a deleted set is not brought back")
    assertTrue(B.Get(doomed) == nil)

    NS.ShowCopyBandsDialog({ into = id, from = { preset = "healer" } })
    act()
    NS.ForgetBandSetUndo()
    assertFalse(NS.CanUndoBandSets(), "a profile change drops the slot")
  end)
end)

test("bandset dialogs: /rm bands lists undo in its help line", function()
  local found
  for _, row in ipairs(NS.COMMANDS) do
    if row[1] == "bands" then found = row[2] end
  end
  assertTrue(found ~= nil and found:find("undo", 1, true) ~= nil, "the help names /rm bands undo")
end)

-- ── Add band and Remove band, side by side ───────────────────────────────────────────────────

--- The Bands tab drawn; answers the ctx and the Add band / Remove band row.
local function bandsRow(ctx)
  ctx = ctx or E.page("bandsets", "Band sets")
  ctx.activeTab = "Bands"
  local real = NS.Range.AnchorFor
  NS.Range.AnchorFor = function() return nil end
  local ok, err = pcall(NS.__renderBandSetsPage, ctx)
  NS.Range.AnchorFor = real
  if not ok then error(err, 0) end
  local row
  local function walk(w)
    for _, c in ipairs(w.children or {}) do
      if c.type == "SimpleGroup" and c.children[1] and c.children[1].text == "Add band" then row = c end
      walk(c)
    end
  end
  walk(ctx.scroll)
  return ctx, row
end

test("bandset dialogs: Add band and Remove band share one row; Remove leaves the band's controls", function()
  -- red under: Remove band inside the band's own controls, Add band alone under the rail.
  with(function()
    local id = four()
    NS.SelectBandSet(id)
    local ctx, row = bandsRow()
    assertTrue(row ~= nil, "Add band's row is drawn")
    assertEqual(row.children[2] and row.children[2].text, "Remove band", "Remove band beside it")
    assertFalse(row.children[2].disabled)
    for _, item in ipairs(NS.__bandItems(id, B.Get(id), 1)) do
      assertTrue(item.label ~= "Remove band", "no Remove band among the band's controls")
    end
    NS.__selectBand(id, 2)
    row = select(2, bandsRow(ctx))
    row.children[2]:__fire("OnClick")
    assertEqual(#B.Get(id).bands, 3, "Remove band removes a band")
    assertEqual(B.Get(id).bands[2].label, "C", "the selected one")
    local blank = B.Create("One", {})
    NS.SelectBandSet(blank)
    row = select(2, bandsRow(ctx))
    assertTrue(row.children[2].disabled, "Remove band is disabled with one band")
  end)
end)
