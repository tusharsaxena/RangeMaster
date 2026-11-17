-- tests/test_presets.lua — the container presets (modules/Presets.lua): Simple, Intermediate and
-- Advanced, applied through the container registry's writer (NS.CM), with a one-level Undo. The
-- v0.1.0 plan, Task 4; design spec section 5.2 ("Container presets").
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

test("presets: test_simple_four_free_containers — target, focus, pet, mouseover free on screen", function()
  withFreshProfile(function()
    CM.Create("nameplates")
    Presets.Apply("simple")
    local list = containers()
    assertEqual(#list, 4, "the profile's containers are replaced")
    local units = {}
    for i, c in ipairs(list) do units[i] = c.unit end
    assertEqual(table.concat(units, ","), "target,focus,pet,mouseover")
    local spots = {}
    for _, c in ipairs(list) do
      assertEqual(c.anchor.mode, "screen", c.name)
      assertEqual(enabledElements(c), "number", c.name .. ": only the number")
      assertTrue(c.frame.border.enabled, c.name .. ": a border")
      assertEqual(c.frame.border.colorMode, "band", c.name .. ": colored by band")
      assertEqual(c.bandSet, B.DefaultId(), c.name .. ": the class default set")
      assertNil(c.bandSetFriendly)
      assertFalse(c.sounds.enabled)
      local spot = c.anchor.x .. "," .. c.anchor.y
      assertNil(spots[spot], c.name .. " is not stacked on another")
      spots[spot] = true
    end
    assertEqual(list[1].name, "Target")
    assertEqual(list[4].name, "Mouseover")
  end)
end)

test("presets: test_intermediate_shape — unit frames, cursor mouseover, friendly sets, hidden with no unit", function()
  withFreshProfile(function()
    Presets.Apply("intermediate")
    local list = containers()
    assertEqual(#list, 4)
    local healer = setNamed("Healer")
    assertTrue(healer ~= nil, "the Healer set exists")
    for _, unit in ipairs({ "target", "focus", "pet" }) do
      local c = find(unit)
      assertEqual(c.anchor.mode, "frame", unit)
      assertEqual(c.anchor.frame.provider, "blizzard", unit)
    end
    assertEqual(find("mouseover").anchor.mode, "cursor")
    for _, c in ipairs(list) do
      assertEqual(enabledElements(c), "indicator,number,text", c.name)
      assertEqual(c.elements.indicator.shape, "dot", c.name)
      assertTrue(c.visibility.hideNoUnit, c.name)
      assertEqual(c.bandSet, B.DefaultId(), c.name)
    end
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do
      assertEqual(find(unit).bandSetFriendly, healer, unit .. " reads the Healer set on a friendly unit")
    end
    assertNil(find("pet").bandSetFriendly, "a pet is always friendly: one set")
  end)
end)

test("presets: Intermediate creates the Healer set when the profile has none, and reuses one it has", function()
  withFreshProfile(function()
    local healer = setNamed("Healer")
    B.Delete(healer)
    assertNil(setNamed("Healer"))
    Presets.Apply("intermediate")
    local made = setNamed("Healer")
    assertTrue(made ~= nil, "created")
    local n = #B.List()
    Presets.Apply("intermediate")
    assertEqual(#B.List(), n, "a second apply reuses it")
    assertEqual(find("target").bandSetFriendly, made)
  end)
end)

test("presets: test_advanced_shape — six containers with plates, spell chips, a sound and rules", function()
  withFreshProfile(function()
    Presets.Apply("advanced")
    local list = containers()
    assertEqual(#list, 6)
    -- Intermediate's four, the focus with its spell chips
    assertEqual(find("target", "frame").anchor.frame.provider, "blizzard")
    assertEqual(find("pet", "frame").anchor.frame.provider, "blizzard")
    assertEqual(find("mouseover", "cursor").unit, "mouseover")
    local focus = find("focus", "frame")
    assertTrue(focus.elements.spells.enabled, "focus shows spell chips")
    local seeds = NS.SpellSeeds[NS.Compat.ClientKey()][NS.Compat.PlayerClass()]
    assertEqual(#focus.elements.spells.list, #seeds.chips, "seeded with the class's chips")
    assertEqual(focus.elements.spells.list[1], seeds.chips[1])
    -- the target's own nameplate: diamond + number
    local plate = find("target", "nameplate")
    assertEqual(enabledElements(plate), "indicator,number")
    assertEqual(plate.elements.indicator.shape, "diamond")
    -- every hostile nameplate: dot + the short number
    local all = find("nameplates")
    assertEqual(all.anchor.mode, "nameplate")
    assertEqual(enabledElements(all), "indicator,number")
    assertEqual(all.elements.indicator.shape, "dot")
    assertEqual(all.elements.number.format, "max")
    assertEqual(all.visibility.reaction, "hostile")
    assertFalse(all.nameplate.includeFriendly)
    assertFalse(all.sounds.enabled, "never a sound on every plate")
    -- the OOR sound on the target
    local target = find("target", "frame")
    assertTrue(target.sounds.enabled, "the target sounds")
    local bands = B.Get(target.bandSet).bands
    assertEqual(bands[#bands].sound, Presets.OOR_SOUND, "on its set's out-of-range band")
    -- the visibility rules
    assertEqual(plate.visibility.combat, "in")
    assertEqual(all.visibility.combat, "in")
  end)
end)

test("presets: Advanced keeps a sound the player already put on the out-of-range band", function()
  withFreshProfile(function()
    local bands = B.Get(B.DefaultId()).bands
    bands[#bands].sound = "Mine"
    Presets.Apply("advanced")
    assertEqual(bands[#bands].sound, "Mine")
  end)
end)

test("presets: test_preset_undo_restores — Undo puts back the containers and band sets from before", function()
  withFreshProfile(function(p)
    local mine = CM.Create("focus", { name = "Mine" })
    B.Delete(setNamed("Healer"))
    local setsBefore = #B.List()
    local before = Presets.Apply("advanced")
    assertEqual(type(before), "table", "Apply answers the snapshot taken before it")
    assertEqual(before.containerOrder[1], mine)
    assertEqual(#containers(), 6)
    assertTrue(Presets.CanUndo())
    assertTrue(Presets.Undo())
    assertEqual(#p.containerOrder, 1)
    assertEqual(p.containerOrder[1], mine)
    assertEqual(CM.Get(mine).name, "Mine")
    assertEqual(#B.List(), setsBefore, "the Healer set Intermediate's half created is gone again")
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
    assertNil(Presets.Apply("expert"))
    assertEqual(#containers(), 4)
    assertTrue(Presets.CanUndo())
  end)
end)

test("presets: Describe answers each preset's name, container count and bullet items", function()
  for key, count in pairs({ simple = 4, intermediate = 4, advanced = 6 }) do
    local d = Presets.Describe(key)
    assertEqual(type(d.name), "string", key)
    assertEqual(d.count, count, key)
    assertTrue(#d.items >= 3, key .. " has items")
  end
  assertEqual(Presets.Describe("simple").name, "Simple")
  assertNil(Presets.Describe("expert"))
  assertEqual(table.concat(Presets.ORDER, ","), "simple,intermediate,advanced")
end)

test("presets: an apply announces CONTAINERS_CHANGED once, on the next frame", function()
  withFreshProfile(function()
    local target, n = NS.NewBusTarget(), 0
    target:RegisterMessage(NS.MSG.CONTAINERS_CHANGED, function() n = n + 1 end)
    CM.Create("target")
    Presets.Apply("advanced")
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

test("presets: Advanced puts the OOR sound on through the band-set writer, which announces it", function()
  withFreshProfile(function()
    local target, n = NS.NewBusTarget(), 0
    target:RegisterMessage(NS.MSG.BANDSETS_CHANGED, function() n = n + 1 end)
    local saved = B.SetBandSound
    local calls = 0
    B.SetBandSound = function(...) calls = calls + 1 return saved(...) end
    local ok, err = pcall(Presets.Apply, "advanced")
    B.SetBandSound = saved
    target:UnregisterMessage(NS.MSG.BANDSETS_CHANGED)
    if not ok then error(err, 0) end
    assertEqual(calls, 1, "one write, through NS.BandSets.SetBandSound")
    assertTrue(n >= 1, "the band-set change is announced")
    local bands = B.Get(B.DefaultId()).bands
    assertEqual(bands[#bands].sound, Presets.OOR_SOUND)
  end)
end)
