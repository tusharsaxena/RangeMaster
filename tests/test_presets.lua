-- tests/test_presets.lua — the container presets (modules/Presets.lua): Simple, Intermediate (Range
-- Text), Intermediate (Range Numbers), Advanced and Expert, applied through the container registry's
-- writer (NS.CM), with a one-level Undo. The v0.1.0 plan, Task 4; design spec section 5.2 ("Container
-- presets"); the five-preset plan of 2026-11-19, M4.
--
-- Every case runs on a FRESH profile with the apply queue and the Undo slot emptied before and after;
-- the real db, the class and the friendly read are put back whether or not the case raised.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local CM, Presets, B = NS.CM, NS.Presets, NS.BandSets

local function withFreshProfile(body, classToken)
  local savedDb, savedClass = NS.db, M.__context.classToken
  if classToken then M.__context.classToken = classToken end
  local p = {}
  NS.db = { profile = p, global = savedDb.global }
  CM.__reset()
  Presets.__reset()
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(p)
    body(p)
  end)
  NS.Container.__reset()   -- instances a flush built here would leave their units watched
  CM.__reset()
  Presets.__reset()
  NS.db = savedDb
  M.__context.classToken = savedClass
  if not ok then error(err, 0) end
end

--- The containers in order, as a list of tables.
local function containers()
  local out = {}
  for i, id in ipairs(CM.List()) do out[i] = CM.Get(id) end
  return out
end

--- The containers on `unit` anchored by `mode` (mode nil: any).
local function find(unit, mode)
  for _, c in ipairs(containers()) do
    if c.unit == unit and (mode == nil or c.anchor.mode == mode) then return c end
  end
end

--- The elements enabled on `c`, sorted and joined.
local function enabledElements(c)
  local out = {}
  for _, name in ipairs({ "indicator", "number", "spells", "text" }) do
    if c.elements[name].enabled then out[#out + 1] = name end
  end
  return table.concat(out, ",")
end

--- The id of the stored band set named `name`.
local function setNamed(name)
  for _, id in ipairs(B.List()) do
    if B.Get(id).name == name then return id end
  end
end

--- A preset container's faint frame (plan 2026-11-19 M12): border and background on, the border at 10%
--- and the background's band tint at 10%.
local function assertFaintFrame(c, what)
  assertTrue(c.frame.background.enabled, what .. ": a background")
  assertTrue(c.frame.border.enabled, what .. ": a border")
  assertEqual(c.frame.border.alpha, 0.1, what .. ": the border at 10%")
  assertEqual(c.frame.background.bandAlpha, 0.1, what .. ": the band tint at 10%")
end

--- Assert the four unit containers of `key` are free on screen at their homes, showing `elements`,
--- on the preset's faint frame, the matte dot, and the caption naming it at Outside top.
local function assertFourOnScreen(key, elements)
  local units = {}
  for _, unit in ipairs({ "target", "focus", "pet", "mouseover" }) do
    local c = find(unit, "screen")
    assertTrue(c ~= nil, key .. ": " .. unit .. " free on screen")
    units[#units + 1] = c.unit
    local home = Presets.__home(unit)
    assertEqual(c.anchor.x .. "," .. c.anchor.y, home.x .. "," .. home.y, key .. ": " .. unit .. " at its home")
    assertEqual(enabledElements(c), elements, key .. ": " .. unit .. "'s elements")
    assertFaintFrame(c, key .. ": " .. unit)
    assertEqual(c.frame.border.colorMode, "band", key .. ": colored by band")
    assertTrue(c.label.enabled, key .. ": " .. unit .. " shows its caption")
    assertEqual(c.label.position .. " " .. c.label.align, "outsideTop center", key .. ": outside top, centered")
    assertEqual(c.label.text, "", key .. ": reading the container's name")
    assertEqual(c.elements.indicator.shape, "dot", key)
    assertEqual(c.elements.indicator.style, "matte", key .. ": the matte dot")
    assertEqual(c.bandSet, B.DefaultId(), key .. ": the class default set")
  end
  assertEqual(table.concat(units, ","), "target,focus,pet,mouseover")
end

test("presets: test_six_presets — the picker's six, in order, each with its own elements on the same four homes", function()
  -- red under: the three presets (Simple number-only, Intermediate on unit frames, Advanced), or no
  -- Ka0s preset (the owner's own profile, 2026-11-20).
  assertEqual(table.concat(Presets.ORDER, ","), "simple,text,numbers,advanced,expert,ka0s")
  local want = { simple = "indicator", text = "text", numbers = "number",
    advanced = "indicator,number,text", expert = "indicator,number,spells,text", ka0s = "number,text" }
  for _, key in ipairs(Presets.ORDER) do
    withFreshProfile(function()
      CM.Create("nameplates")
      Presets.Apply(key)
      assertEqual(#containers(), Presets.Describe(key).count, key .. ": the card's count")
      assertFourOnScreen(key, want[key])
    end)
  end
end)

test("presets: test_simple_to_advanced_plain — the four lighter presets hold four containers, no sound, no friendly set", function()
  for _, key in ipairs({ "simple", "text", "numbers", "advanced" }) do
    withFreshProfile(function()
      Presets.Apply(key)
      local list = containers()
      assertEqual(#list, 4, key)
      for _, c in ipairs(list) do
        assertNil(c.bandSetFriendly, key .. ": " .. c.name)
        assertFalse(c.sounds.enabled, key .. ": " .. c.name)
      end
      assertEqual(list[1].name, "Target")
      assertEqual(list[4].name, "Mouseover")
    end)
  end
end)

test("presets: test_expert_shape — six containers: the four with spell chips, both plates, the sound and the Healer set", function()
  -- red under: no Expert preset (Advanced held the extras, on unit frames).
  withFreshProfile(function()
    Presets.Apply("expert")
    local list = containers()
    assertEqual(#list, 6)
    local seeds = NS.SpellSeeds[NS.Compat.ClientKey()][NS.Compat.PlayerClass()]
    for _, unit in ipairs({ "target", "focus", "pet", "mouseover" }) do
      local c = find(unit, "screen")
      assertTrue(c.elements.spells.enabled, unit .. " shows spell chips")
      assertEqual(#NS.CM.SpellChips(c), #seeds.chips, unit .. ": the class's chips")
    end
    local healer = setNamed("Healer")
    assertTrue(healer ~= nil, "the Healer set exists")
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do
      assertEqual(find(unit, "screen").bandSetFriendly, healer, unit .. " reads the Healer set on a friendly unit")
    end
    assertNil(find("pet").bandSetFriendly, "a pet is always friendly: one set")
    -- the target's own nameplate: diamond + number
    local plate = find("target", "nameplate")
    assertEqual(enabledElements(plate), "indicator,number")
    assertEqual(plate.elements.indicator.shape, "diamond")
    assertEqual(plate.name, "Target plate")
    -- every hostile nameplate but the target's (the target plate container sits there; the owner,
    -- 2026-11-19, saw the two overlap): dot + the short number. Red under unit "nameplates".
    local all = find("nameplatesExceptTarget")
    assertEqual(all.anchor.mode, "nameplate")
    assertEqual(enabledElements(all), "indicator,number")
    assertEqual(all.elements.indicator.shape, "dot")
    assertEqual(all.elements.number.format, "max")
    assertEqual(all.visibility.reaction, "hostile")
    assertFalse(all.nameplate.includeFriendly)
    assertFalse(all.sounds.enabled, "never a sound on every plate")
    -- Shown at any time (the owner saw none out of combat, plan 2026-11-19 M12); red under "in".
    assertEqual(plate.visibility.combat, "any")
    assertEqual(all.visibility.combat, "any")
    assertTrue(plate.visibility.hideNoUnit and all.visibility.hideNoUnit, "hidden with no unit")
    assertFaintFrame(plate, "the target plate")
    assertFaintFrame(all, "every hostile plate")
    assertFalse(plate.label.enabled or all.label.enabled, "no caption on a nameplate container")
    -- the OOR sound on the target, and on no other
    local target = find("target", "screen")
    assertTrue(target.sounds.enabled, "the target sounds")
    local bands = B.Get(target.bandSet).bands
    assertEqual(bands[#bands].sound, Presets.OOR_SOUND, "on its set's out-of-range band")
    for _, unit in ipairs({ "focus", "pet", "mouseover" }) do
      assertFalse(find(unit, "screen").sounds.enabled, unit)
    end
  end)
end)

test("presets: Expert creates the Healer set when the profile has none, and reuses one it has", function()
  withFreshProfile(function()
    B.Delete(setNamed("Healer"))
    assertNil(setNamed("Healer"))
    Presets.Apply("expert")
    local made = setNamed("Healer")
    assertTrue(made ~= nil, "created")
    local n = #B.List()
    Presets.Apply("expert")
    assertEqual(#B.List(), n, "a second apply reuses it")
    assertEqual(find("target", "screen").bandSetFriendly, made)
  end)
end)

test("presets: Expert keeps a sound the player already put on the out-of-range band", function()
  withFreshProfile(function()
    local bands = B.Get(B.DefaultId()).bands
    bands[#bands].sound = "Mine"
    Presets.Apply("expert")
    assertEqual(bands[#bands].sound, "Mine")
  end)
end)

test("presets: test_preset_undo_restores — Undo puts back the containers and band sets from before", function()
  withFreshProfile(function(p)
    local mine = CM.Create("focus", { name = "Mine" })
    B.Delete(setNamed("Healer"))
    local setsBefore = #B.List()
    local before = Presets.Apply("expert")
    assertEqual(type(before), "table", "Apply answers the snapshot taken before it")
    assertEqual(before.containerOrder[1], mine)
    assertEqual(#containers(), 6)
    assertTrue(Presets.CanUndo())
    assertTrue(Presets.Undo())
    assertEqual(#p.containerOrder, 1)
    assertEqual(p.containerOrder[1], mine)
    assertEqual(CM.Get(mine).name, "Mine")
    assertEqual(#B.List(), setsBefore, "the Healer set Expert created is gone again")
    local bands = B.Get(B.DefaultId()).bands
    assertNil(bands[#bands].sound, "the OOR sound is gone again")
    assertFalse(Presets.CanUndo(), "one level")
    assertFalse(Presets.Undo())
  end)
end)

test("presets: an unknown key applies nothing and keeps the Undo slot", function()
  withFreshProfile(function()
    CM.Create("target")
    Presets.Apply("simple")
    assertNil(Presets.Apply("bogus"))
    assertEqual(#containers(), 4)
    assertTrue(Presets.CanUndo())
  end)
end)

test("presets: Describe answers each preset's name, container count and bullet items", function()
  local names = { simple = "Simple", text = "Intermediate (Range Text)", numbers = "Intermediate (Range Numbers)",
    advanced = "Advanced", expert = "Expert" }
  for key, count in pairs({ simple = 4, text = 4, numbers = 4, advanced = 4, expert = 6 }) do
    local d = Presets.Describe(key)
    assertEqual(d.name, names[key], key)
    assertEqual(d.count, count, key)
  end
  -- The cards' lines are the only place the player reads what each preset holds; red under a card
  -- copied from another (Simple still listing the range number, Expert missing a line).
  local L = NS.L
  local onScreen, oneSet = L["Target, Focus, Pet, Mouseover: free on screen, each named above it"],
    L["One band set (class default)"]
  local noSounds = L["No sounds; hostile units only (the pet: always)"]
  local want = {
    simple = { onScreen, L["A dot colored by band"], oneSet, noSounds },
    text = { onScreen, L["The band's label as text"], oneSet, noSounds },
    numbers = { onScreen, L["The range number"], oneSet, noSounds },
    advanced = { onScreen, L["Dot + range number + text label"], oneSet, noSounds },
    expert = {
      L["Everything in Advanced, with spell-range chips (class spells)"],
      L["Healer band set for friendly target, focus and mouseover"],
      L["Target on its own nameplate + dot on all hostile plates"],
      L["Band-change sound on target (out-of-range warning)"],
      L["Visibility rules: hostile only, but the friendly-set displays and the pet"],
    },
  }
  for key, items in pairs(want) do
    assertEqual(table.concat(Presets.Describe(key).items, " | "), table.concat(items, " | "), key .. "'s card")
  end
  assertNil(Presets.Describe("intermediate"), "the old keys are gone")
  assertNil(Presets.Describe("bogus"))
end)

test("presets: test_preview_swap_restores — a later pick in the picker drops what Expert's preview added to the band sets", function()
  -- red under: BeginPreview building each pick over the last one (the Healer set and the OOR sound
  -- Expert's preview added outlived it into the preset kept).
  withFreshProfile(function()
    B.Delete(setNamed("Healer"))
    local setsBefore = #B.List()
    assertTrue(Presets.BeginPreview("expert"))
    assertTrue(setNamed("Healer") ~= nil, "Expert's preview made the Healer set")
    assertTrue(Presets.BeginPreview("simple"))
    assertTrue(Presets.EndPreview(true))
    assertEqual(#containers(), 4, "Simple kept")
    assertEqual(#B.List(), setsBefore, "no Healer set the player never chose")
    local bands = B.Get(B.DefaultId()).bands
    assertNil(bands[#bands].sound, "no out-of-range sound the player never chose")
  end)
end)

test("presets: an apply announces CONTAINERS_CHANGED once, on the next frame", function()
  withFreshProfile(function()
    local target, n = NS.NewBusTarget(), 0
    target:RegisterMessage(NS.MSG.CONTAINERS_CHANGED, function() n = n + 1 end)
    CM.Create("target")
    Presets.Apply("expert")
    local t = CM.__flushTimer()
    if t then t.fn() end
    target:UnregisterMessage(NS.MSG.CONTAINERS_CHANGED)
    assertEqual(n, 1)
  end)
end)

test("presets: a profile switch, copy or reset drops the Undo slot, so no other profile is overwritten", function()
  withFreshProfile(function(p)
    Presets.Apply("simple")
    local other = {}
    NS.Database.PrepareProfile(other)
    NS.db.profile = other
    local pet1, pet2 = CM.Create("pet"), CM.Create("pet")
    NS.OnProfileChanged()
    assertFalse(Presets.CanUndo(), "the slot belonged to the profile it was taken on")
    assertFalse(Presets.Undo())
    assertEqual(#CM.List(), 2, "the new profile's containers are untouched")
    assertEqual(CM.Get(pet1).unit, "pet")
    assertEqual(CM.Get(pet2).unit, "pet")
    NS.db.profile = p
    for _, adopt in ipairs({ NS.OnProfileCopied, NS.OnProfileReset }) do
      Presets.Apply("simple")
      adopt()
      assertFalse(Presets.CanUndo())
    end
  end)
end)

test("presets: Expert puts the OOR sound on through the band-set writer, which announces it", function()
  withFreshProfile(function()
    local target, n = NS.NewBusTarget(), 0
    target:RegisterMessage(NS.MSG.BANDSETS_CHANGED, function() n = n + 1 end)
    local saved = B.SetBandSound
    local calls = 0
    B.SetBandSound = function(...) calls = calls + 1 return saved(...) end
    local ok, err = pcall(Presets.Apply, "expert")
    B.SetBandSound = saved
    target:UnregisterMessage(NS.MSG.BANDSETS_CHANGED)
    if not ok then error(err, 0) end
    assertEqual(calls, 1, "one write, through NS.BandSets.SetBandSound")
    assertTrue(n >= 1, "the band-set change is announced")
    local bands = B.Get(B.DefaultId()).bands
    assertEqual(bands[#bands].sound, Presets.OOR_SOUND)
  end)
end)

test("presets: test_preset_homes — each unit has one home on screen, the same in every preset, none shared", function()
  -- red under: per-preset coordinates (Simple's block narrower than two drag strips, Expert's two
  -- nameplate containers on one spot, the mouseover waiting wherever the template put it).
  local seenAt = {}
  for _, key in ipairs(Presets.ORDER) do
    withFreshProfile(function()
      Presets.Apply(key)
      local spots = {}
      for _, c in ipairs(containers()) do
        local spot = c.anchor.x .. "," .. c.anchor.y
        assertTrue(spots[spot] == nil, key .. ": " .. c.name .. " shares " .. spot)
        spots[spot] = true
        local slot = (c.unit == "target" and c.anchor.mode == "nameplate") and "targetPlate"
          or (NS.CM.IsPlates(c.unit) and "nameplates") or c.unit
        local home = Presets.__home(slot)
        assertEqual(spot, home.x .. "," .. home.y, key .. ": " .. c.name .. " at its home")
        assertTrue(seenAt[slot] == nil or seenAt[slot] == spot, c.name .. " moves between presets")
        seenAt[slot] = spot
      end
    end)
  end
  local t, f = Presets.__home("target"), Presets.__home("focus")
  assertTrue(f.x - t.x >= 260, "two drag strips side by side clear each other")
  local pet, plate = Presets.__home("pet"), Presets.__home("targetPlate")
  assertTrue(pet.y - plate.y >= 80, "a row holds a preview nameplate over a nameplate container")
end)

test("presets: test_hostile_only — every preset shows hostile units only, but the pet and the Healer-set displays", function()
  -- red under: presets that show for any reaction (the owner, 2026-11-20).
  for _, key in ipairs({ "simple", "text", "numbers", "advanced" }) do
    withFreshProfile(function()
      Presets.Apply(key)
      for _, c in ipairs(containers()) do
        local want = c.unit == "pet" and "any" or "hostile"
        assertEqual(c.visibility.reaction, want, key .. ": " .. c.name)
      end
    end)
  end
  withFreshProfile(function()
    Presets.Apply("expert")
    for _, c in ipairs(containers()) do
      local want = "hostile"
      if c.unit == "pet" or (c.bandSetFriendly ~= nil and c.anchor.mode == "screen") then want = "any" end
      assertEqual(c.visibility.reaction, want, "expert: " .. c.name)
    end
    assertEqual(find("target", "nameplate").visibility.reaction, "hostile", "the target plate: hostile")
  end)
end)

test("presets: test_plate_containers_cast_bar_flush — every preset container on a nameplate: cast bar while casting, offsets 0", function()
  -- red under: the template's plate part and its y = -2 (the owner, 2026-11-20).
  for _, key in ipairs(Presets.ORDER) do
    withFreshProfile(function()
      Presets.Apply(key)
      for _, c in ipairs(containers()) do
        if c.anchor.mode == "nameplate" or NS.CM.IsPlates(c.unit) then
          assertEqual(c.nameplate.attachTo, "castbarWhenCasting", key .. ": " .. c.name)
          assertEqual(c.nameplate.x, 0, key .. ": " .. c.name .. " x")
          assertEqual(c.nameplate.y, 0, key .. ": " .. c.name .. " y")
        end
      end
    end)
  end
end)

test("presets: test_ka0s_shape — the owner's Ka0s profile: five containers, number + text, hostile only but the pet", function()
  withFreshProfile(function()
    Presets.Apply("ka0s")
    local list = containers()
    assertEqual(#list, 5)
    local healer = setNamed("Healer")
    local key = NS.BandSetPresets.DefaultFor(NS.Compat.PlayerClass(), NS.Compat.PlayerSpecID())
    local own = setNamed(NS.BandSetPresets[key].name)
    for _, c in ipairs(list) do
      local want = c.unit == "pet" and "any" or "hostile"
      assertEqual(c.visibility.reaction, want, c.name .. ": hostile only, but the always-friendly pet")
      assertEqual(c.bandSet, own, c.name .. ": the class's own band set")
    end
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do
      assertEqual(find(unit, "screen").bandSetFriendly, healer, unit .. " reads the Healer set on a friend")
    end
    assertNil(find("pet", "screen").bandSetFriendly)
    for _, c in ipairs(list) do
      assertFalse(c.sounds.enabled, c.name .. ": no sound (only Expert sounds, the owner, 2026-11-20)")
    end
    local plate = find("target", "nameplate")
    assertEqual(plate.name, "Target plate")
    assertEqual(enabledElements(plate), "number", "the number alone: the owner turned its dot off")
    assertEqual(plate.nameplate.attachTo, "castbarWhenCasting")
    assertEqual(plate.nameplate.x .. "," .. plate.nameplate.y, "0,0")
    assertNil(find("nameplatesExceptTarget"), "no every-plate container")
  end)
end)

test("presets: test_ka0s_class_set — Ka0s finds the class's own set by name, whichever set is the default", function()
  -- red under: the profile's default set (a profile whose first set is not the class's).
  withFreshProfile(function()
    local key = NS.BandSetPresets.DefaultFor(NS.Compat.PlayerClass(), NS.Compat.PlayerSpecID())
    local own = setNamed(NS.BandSetPresets[key].name)
    local other = B.Create("Somebody else's", "healer")
    NS.db.profile.bandSetOrder = { other, own }
    Presets.Apply("ka0s")
    assertTrue(B.DefaultId() == other, "the default is another set")
    assertEqual(find("target", "screen").bandSet, own, "yet Ka0s reads the class's own")
  end)
end)
