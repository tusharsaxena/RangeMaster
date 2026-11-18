-- tests/test_bandsets.lua — the shared band sets (modules/BandSets.lua) and their presets
-- (defaults/BandSetPresets.lua). The v0.1.0 plan, Task 3; design spec section 5.2.
--
-- Every case runs on a FRESH profile: the db is swapped for a bare { profile, global } pair, the
-- load pass (NS.Database.PrepareProfile) seeds it exactly as a first login would, and the real db is
-- put back whether or not the case raised. Nothing here reaches the player's stored profile.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local B = NS.BandSets
local P = NS.BandSetPresets

--- Run `body(profile)` on a freshly prepared profile; restores the real db and any stubbed global.
local function withFreshProfile(body, classToken)
  local savedDb, savedClass = NS.db, M.__context.classToken
  local savedFriend = M.UnitIsFriend
  if classToken then M.__context.classToken = classToken end
  local p = {}
  NS.db = { profile = p, global = savedDb.global }
  local ok, err = pcall(function()
    NS.Database.PrepareProfile(p)
    body(p)
  end)
  NS.db = savedDb
  M.__context.classToken = savedClass
  M.UnitIsFriend = savedFriend
  if not ok then error(err, 0) end
end

--- The index of the band labeled `label` in set `id`.
local function bandIndex(id, label)
  for i, b in ipairs(B.Get(id).bands) do
    if b.label == label then return i end
  end
end

--- A preset's band labels, joined, for a compact shape assertion.
local function labels(bands)
  local out = {}
  for i, b in ipairs(bands) do out[i] = b.label end
  return table.concat(out, ",")
end

--- Count BANDSETS_CHANGED sends while `fn` runs.
local function countChanged(fn)
  local target, n = NS.NewBusTarget(), 0
  target:RegisterMessage(NS.MSG.BANDSETS_CHANGED, function() n = n + 1 end)
  local ok, err = pcall(fn)
  target:UnregisterMessage(NS.MSG.BANDSETS_CHANGED)
  if not ok then error(err, 0) end
  return n
end

-- ---------------------------------------------------------------------------
-- Resolve
-- ---------------------------------------------------------------------------

test("bandsets: test_resolve_by_max — (20, 25) in Melee / Ranged lands in MID 20-30", function()
  withFreshProfile(function()
    local id = B.Create("m", "melee_ranged")
    assertEqual(B.Resolve(id, "known", 20, 25), bandIndex(id, "MID"))
    -- The max is the bound that decides: at most 20 yd is CLOSE (5-20), not MID.
    assertEqual(B.Resolve(id, "known", 15, 20), bandIndex(id, "CLOSE"), "a max on an edge is the nearer band")
    assertEqual(B.Resolve(id, "known", 0, 5), bandIndex(id, "MELEE"))
  end)
end)

test("bandsets: test_resolve_by_min — matchBy min reads the near bound", function()
  withFreshProfile(function()
    local id = B.Create("m", "melee_ranged")
    B.Get(id).matchBy = "min"
    assertEqual(B.Resolve(id, "known", 18, 22), bandIndex(id, "CLOSE"), "min 18 is CLOSE")
    assertEqual(B.Resolve(id, "known", 20, 25), bandIndex(id, "MID"), "at least 20 yd is MID")
    B.Get(id).matchBy = "max"
    assertEqual(B.Resolve(id, "known", 18, 22), bandIndex(id, "MID"), "the same bracket by max is MID")
  end)
end)

test("bandsets: test_resolve_open_ended — (40, nil) is out of range under either matchBy", function()
  withFreshProfile(function()
    local id = B.Create("m", "melee_ranged")
    local oor = bandIndex(id, "OOR")
    assertEqual(oor, #B.Get(id).bands, "OOR is the last band")
    assertEqual(B.Resolve(id, "known", 40, nil), oor)
    B.Get(id).matchBy = "min"
    assertEqual(B.Resolve(id, "known", 40, nil), oor)
  end)
end)

test("bandsets: test_resolve_unknown — unknown state reads the unknown band", function()
  withFreshProfile(function()
    local id = B.Create("m", "melee_ranged")
    assertEqual(B.Resolve(id, "unknown"), "unknown")
    assertEqual(B.Get(id).unknown.label, "?", "the unknown label defaults to ?")
    assertEqual(B.Resolve(99999, "known", 20, 25), B.Resolve(B.DefaultId(), "known", 20, 25),
      "a set id that does not exist resolves against the default set")
  end)
end)

test("bandsets: test_resolve_none_nil — no unit resolves to nil", function()
  withFreshProfile(function()
    local id = B.Create("m", "melee_ranged")
    assertNil(B.Resolve(id, "none"))
    assertNil(B.Resolve(id, "none", 20, 25))
  end)
end)

-- ---------------------------------------------------------------------------
-- Normalize
-- ---------------------------------------------------------------------------

--- Assert set `id` is sorted, contiguous from 0 and open-ended, and Resolve is total over 0..100.
local function assertWellFormed(id)
  local bands = B.Get(id).bands
  assertTrue(#bands >= 1, "at least one band")
  assertEqual(bands[1].from, 0, "the first band starts at 0")
  for i = 2, #bands do
    assertEqual(bands[i].from, bands[i - 1].to, "band " .. i .. " starts where band " .. (i - 1) .. " ends")
    assertTrue(bands[i].from > bands[i - 1].from, "band " .. i .. " has width")
  end
  assertNil(bands[#bands].to, "the last band is open-ended")
  for yd = 0, 100 do
    for _, by in ipairs({ "max", "min" }) do
      B.Get(id).matchBy = by
      local r = B.Resolve(id, "known", yd, yd)
      assertEqual(type(r), "number", ("Resolve(%d) by %s gave %s"):format(yd, by, tostring(r)))
    end
  end
  B.Get(id).matchBy = "max"
end

test("bandsets: test_bandset_normalize — overlaps, gaps and order are repaired", function()
  withFreshProfile(function()
    local id = B.Create("n", {
      { from = 0, to = 5, label = "A" }, { from = 3, to = 20, label = "B" },
      { from = 30, label = "D" }, { from = 20, to = 30, label = "C" },
    })
    assertEqual(labels(B.Get(id).bands), "A,B,C,D", "sorted by edge")
    assertWellFormed(id)
    assertEqual(B.Get(id).bands[2].from, 5, "the overlap is cut at the band before")
  end)
end)

test("bandsets: normalize swaps a reversed band, closes a gap and drops a swallowed one", function()
  withFreshProfile(function()
    local id = B.Create("n", {
      { from = 10, to = 2, label = "R" },        -- reversed: 2-10
      { from = 15, to = 25, label = "G" },       -- gap 10-15 closed: 10-open
      { from = 4, to = 6, label = "S" },         -- inside 1-10 after the chain: dropped
      { from = 40, to = 40, label = "Z" },       -- zero width: dropped
      { from = -5, to = 1, label = "N" },        -- negative from: clamped to 0
    })
    assertEqual(labels(B.Get(id).bands), "N,R,G", "reversed swapped, swallowed and zero-width dropped")
    assertWellFormed(id)
    assertEqual(B.Get(id).bands[2].from, 1)
    assertEqual(B.Get(id).bands[2].to, 10)
  end)
end)

test("bandsets: normalize gives an open-ended band in the middle the next band's edge", function()
  withFreshProfile(function()
    local id = B.Create("n", { { from = 0, to = 5, label = "A" }, { from = 5, label = "B" },
      { from = 30, to = 40, label = "C" } })
    assertEqual(labels(B.Get(id).bands), "A,B,C")
    assertEqual(B.Get(id).bands[2].to, 30, "B ends where C starts")
    assertWellFormed(id)
  end)
end)

test("bandsets: normalize turns an empty set into one band over everything", function()
  withFreshProfile(function()
    local id = B.Create("n", {})
    assertEqual(#B.Get(id).bands, 1)
    assertWellFormed(id)
    B.Get(id).bands = { "junk", { from = "x", to = {} } }
    B.Normalize(id)
    assertWellFormed(id)
  end)
end)

test("bandsets: normalize fills a band's colors and repairs matchBy and the unknown band", function()
  withFreshProfile(function()
    local id = B.Create("n", { { from = 0, label = "A" } })
    local set = B.Get(id)
    set.matchBy, set.unknown = "nearest", nil
    set.bands[1].frameColor = nil
    B.Normalize(id)
    assertEqual(set.matchBy, "max", "an unknown matchBy reads max")
    assertEqual(set.unknown.label, "?")
    assertEqual(type(set.bands[1].frameColor), "table", "a missing color is filled")
    assertEqual(type(set.bands[1].textColor.r), "number")
  end)
end)

-- ---------------------------------------------------------------------------
-- CRUD
-- ---------------------------------------------------------------------------

test("bandsets: Create, Rename, Duplicate and List keep the order and announce each change", function()
  withFreshProfile(function()
    local before = #B.List()
    local id, dup
    local n = countChanged(function()
      id = B.Create("Mine", "healer")
      assertTrue(B.Rename(id, "Renamed"))
      dup = B.Duplicate(id)
    end)
    assertEqual(n, 3, "one BANDSETS_CHANGED per change")
    assertEqual(#B.List(), before + 2)
    assertEqual(B.Get(id).name, "Renamed")
    assertTrue(B.Get(dup) ~= B.Get(id), "a duplicate is its own table")
    assertTrue(B.Get(dup).bands ~= B.Get(id).bands, "deep-copied")
    assertEqual(labels(B.Get(dup).bands), labels(B.Get(id).bands))
    assertFalse(B.Rename(id, "   "), "a blank name is refused")
    assertFalse(B.Rename(424242, "x"), "an unknown id is refused")
    assertNil(B.Create("x", "no_such_preset"), "an unknown preset key creates nothing")
  end)
end)

test("bandsets: names stay unique: Create, Duplicate and Rename suffix a taken name, in any case", function()
  withFreshProfile(function()
    local caster
    for _, id in ipairs(B.List()) do
      if B.Get(id).name == "Caster 40" then caster = id end
    end
    assertTrue(caster ~= nil, "the seed holds Caster 40")
    local d1, d2 = B.Duplicate(caster), B.Duplicate(caster)
    assertEqual(B.Get(d1).name, "Caster 40 copy")
    assertEqual(B.Get(d2).name, "Caster 40 copy 2", "a second copy is numbered, never a second 'Caster 40 copy'")
    local n1, n2 = B.Create("New band set", "melee_ranged"), B.Create("new BAND set", "melee_ranged")
    assertEqual(B.Get(n1).name, "New band set")
    assertEqual(B.Get(n2).name, "new BAND set 2", "a name that differs only in case is taken")
    assertTrue(B.Rename(d1, "caster 40"))
    assertEqual(B.Get(d1).name, "caster 40 2", "a rename onto a taken name gets a suffix")
    assertTrue(B.Rename(caster, "Caster 40"), "renaming to its own name is not a clash")
    assertEqual(B.Get(caster).name, "Caster 40")
  end)
end)

test("bandsets: test_bandset_delete_reassigns — containers on a deleted set move to the default", function()
  withFreshProfile(function(p)
    local b = B.Create("B", "healer")
    p.containers[1] = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
    p.containers[2] = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
    p.containers[3] = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
    p.containers[1].bandSet, p.containers[2].bandSet = b, b
    p.containers[3].bandSet, p.containers[3].bandSetFriendly = B.DefaultId(), b
    p.containerOrder = { 1, 2, 3 }
    local n = countChanged(function() assertTrue(B.Delete(b)) end)
    assertEqual(n, 1)
    assertNil(B.Get(b), "the set is gone")
    assertEqual(p.containers[1].bandSet, B.DefaultId())
    assertEqual(p.containers[2].bandSet, B.DefaultId())
    assertNil(p.containers[3].bandSetFriendly, "a friendly override on the deleted set falls away")
    -- and each one still resolves a band
    assertEqual(type(B.Resolve(B.ForUnit(p.containers[1], "target"), "known", 20, 25)), "number")
  end)
end)

test("bandsets: Delete honors reassignTo, refuses the last set and an unknown id", function()
  withFreshProfile(function(p)
    local a, b = B.Create("A", "healer"), B.Create("B", "caster40")
    p.containers[1] = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
    p.containers[1].bandSet, p.containers[1].bandSetFriendly = a, a
    p.containerOrder = { 1 }
    assertTrue(B.Delete(a, b))
    assertEqual(p.containers[1].bandSet, b, "moved to the named set")
    assertEqual(p.containers[1].bandSetFriendly, b, "the override follows the named set")
    assertFalse(B.Delete(777777), "an unknown id is refused")
    for _, id in ipairs(B.List()) do
      if #B.List() > 1 then B.Delete(id) end
    end
    local last = B.List()[1]
    assertFalse(B.Delete(last), "the last set is never deleted")
    assertEqual(B.DefaultId(), last)
  end)
end)

test("bandsets: Delete moves the containers through the container registry's writer (NS.CM.SetField)", function()
  -- red under: a reassign that writes c.bandSet directly (architecture-§5, one runtime writer per
  -- registry): the writer's apply request is the witness.
  withFreshProfile(function(p)
    local a, b = B.Create("A", "healer"), B.Create("B", "caster40")
    p.containers[1] = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
    p.containers[1].bandSet, p.containers[1].bandSetFriendly = a, a
    p.containerOrder = { 1 }
    NS.CM.__reset()
    local calls, real = {}, NS.CM.SetField
    NS.CM.SetField = function(id, field, value)
      calls[#calls + 1] = field
      return real(id, field, value)
    end
    local ok, err = pcall(B.Delete, a, b)
    NS.CM.SetField = real
    if not ok then error(err, 0) end
    assertEqual(table.concat(calls, ","), "bandSet,bandSetFriendly", "both references went through the writer")
    assertEqual(p.containers[1].bandSet, b)
    assertTrue(NS.CM.__pending(), "and the writer asked for an apply")
    NS.CM.__reset()
  end)
end)

test("bandsets: deleting the default set makes the next one the default", function()
  withFreshProfile(function()
    local first, second = B.List()[1], B.List()[2]
    assertEqual(B.DefaultId(), first)
    assertTrue(B.Delete(first))
    assertEqual(B.DefaultId(), second)
  end)
end)

-- ---------------------------------------------------------------------------
-- ForUnit
-- ---------------------------------------------------------------------------

test("bandsets: test_for_unit_friendly_override — a friendly unit reads bandSetFriendly when set", function()
  withFreshProfile(function()
    local hostile, friendly = B.Create("H", "melee_ranged"), B.Create("F", "healer")
    local c = NS.Database.DeepCopy(NS.CONTAINER_TEMPLATE)
    c.bandSet = hostile
    local isFriend = false
    M.UnitIsFriend = function() return isFriend end
    assertEqual(B.ForUnit(c, "target"), hostile, "no override: bandSet for every reaction")
    isFriend = true
    assertEqual(B.ForUnit(c, "target"), hostile, "bandSetFriendly nil falls back to bandSet")
    c.bandSetFriendly = friendly
    assertEqual(B.ForUnit(c, "target"), friendly, "friendly + override")
    isFriend = false
    assertEqual(B.ForUnit(c, "target"), hostile, "hostile ignores the override")
    M.UnitIsFriend = function() error("boom") end
    assertEqual(B.ForUnit(c, "target"), hostile, "a raise reads as not friendly")
    c.bandSet, c.bandSetFriendly = 31337, 31338
    isFriend = true
    M.UnitIsFriend = function() return isFriend end
    assertEqual(B.ForUnit(c, "target"), B.DefaultId(), "dangling ids fall back to the default set")
  end)
end)

-- ---------------------------------------------------------------------------
-- Presets
-- ---------------------------------------------------------------------------

test("bandsets: test_hunter_preset_per_client — Forever has the 5-8 dead zone, Retail does not", function()
  local byClient = P.HUNTER_BY_CLIENT
  assertEqual(labels(byClient.forever.bands), "MELEE,DEAD,AUTO,OOR")
  assertEqual(byClient.forever.bands[2].from, 5)
  assertEqual(byClient.forever.bands[2].to, 8)
  assertEqual(byClient.forever.bands[3].to, 35)
  assertEqual(labels(byClient.retail.bands), "MELEE,RANGED,OOR")
  for _, b in ipairs(byClient.retail.bands) do assertTrue(b.label ~= "DEAD", "retail has no dead zone") end
  assertEqual(byClient.retail.bands[2].to, 40)
  assertTrue(P.hunter == byClient[NS.Compat.ClientKey()], "the hunter preset is the running client's")
end)

test("bandsets: the four presets have the spec's shape, every one well formed", function()
  assertEqual(labels(P.melee_ranged.bands), "MELEE,CLOSE,MID,LONG,OOR")
  assertEqual(labels(P.healer.bands), "NEAR,FAR,OOR")
  assertEqual(P.healer.bands[1].to, 30)
  withFreshProfile(function()
    for _, key in ipairs(P.ORDER) do
      local preset = P[key]
      assertEqual(type(preset.name), "string", key)
      assertEqual(preset.matchBy, "max", key)
      assertWellFormed(B.Create(preset.name, key))
    end
  end)
end)

test("bandsets: DefaultFor picks a class's preset, and an unknown class gets Melee / Ranged", function()
  assertEqual(P.DefaultFor("HUNTER"), "hunter")
  assertEqual(P.DefaultFor("MAGE"), "caster40")
  assertEqual(P.DefaultFor("WARRIOR"), "melee_ranged")
  assertEqual(P.DefaultFor(nil), "melee_ranged")
  assertEqual(P.DefaultFor("NOT_A_CLASS"), "melee_ranged")
end)

test("bandsets: SetBandSound writes one band's sound, announces, and refuses a bad set or band", function()
  withFreshProfile(function()
    local id = B.DefaultId()
    local last = #B.Get(id).bands
    assertEqual(countChanged(function()
      assertTrue(B.SetBandSound(id, last, "Mine"))
    end), 1, "one BANDSETS_CHANGED")
    assertEqual(B.Get(id).bands[last].sound, "Mine")
    assertTrue(B.SetBandSound(id, last, nil), "nil clears it")
    assertNil(B.Get(id).bands[last].sound)
    assertEqual(countChanged(function()
      assertFalse(B.SetBandSound(999, 1, "Mine"), "an unknown set")
      assertFalse(B.SetBandSound(id, last + 1, "Mine"), "a band the set does not have")
      assertFalse(B.SetBandSound(id, 1, 42), "a sound that is not a string")
    end), 0, "a refusal announces nothing")
  end)
end)

test("bandsets: a restore never rewinds the id counter, so a later Create mints an id never used", function()
  withFreshProfile(function()
    local snap = B.Snapshot()
    local used = { [B.Create("A")] = true, [B.Create("B")] = true }
    assertTrue(B.RestoreSnapshot(snap))
    assertFalse(used[B.Create("C")] == true)
  end)
end)
