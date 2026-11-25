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

--- A preset's rules, one word a band: yards, melee, ranged, friendly, gap or beyond.
local function rules(bands)
  local out = {}
  for i, b in ipairs(bands) do
    local r = b.rule
    out[i] = r == nil and "yards" or (r.type == "spell" and r.role or r.type)
  end
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
  assertEqual(labels(byClient.forever.bands), "MELEE,DEAD,RANGE,OOR", "band 3 is RANGE (the owner, 2026-11-24)")
  assertEqual(byClient.forever.bands[2].from, 5)
  assertEqual(byClient.forever.bands[2].to, 8)
  assertEqual(byClient.forever.bands[3].to, 35)
  assertEqual(labels(byClient.retail.bands), "MELEE,RANGED,OOR")
  for _, b in ipairs(byClient.retail.bands) do assertTrue(b.label ~= "DEAD", "retail has no dead zone") end
  assertEqual(byClient.retail.bands[2].to, 40)
  assertTrue(P.hunter == byClient[NS.Compat.ClientKey()], "the hunter preset is the running client's")
  -- The rules (plan 2026-11-19-dynamic-bands, D4); the yards above are each band's fallback.
  assertEqual(rules(byClient.forever.bands), "melee,gap,ranged,beyond", "MELEE, DEAD, RANGE, OOR")
  assertEqual(rules(byClient.retail.bands), "melee,ranged,beyond", "MELEE, RANGED, OOR")
end)

test("bandsets: the four presets have the spec's shape, every one well formed", function()
  assertEqual(labels(P.melee_ranged.bands), "MELEE,CLOSE,MID,LONG,OOR")
  assertEqual(rules(P.melee_ranged.bands), "melee,yards,yards,ranged,beyond")
  assertEqual(labels(P.caster40.bands), "CLOSE,CAST,OOR", "a caster: a yard first band, CAST, OOR")
  assertEqual(rules(P.caster40.bands), "yards,ranged,beyond")
  assertEqual(P.caster40.bands[1].to, 8)
  assertEqual(P.caster40.bands[2].to, 40)
  assertEqual(labels(P.healer.bands), "NEAR,FAR,OOR")
  assertEqual(rules(P.healer.bands), "yards,friendly,beyond")
  assertEqual(P.healer.bands[1].to, 30)
  withFreshProfile(function()
    for _, key in ipairs(P.ORDER) do
      local preset = P[key]
      assertEqual(type(preset.name), "string", key)
      assertEqual(preset.matchBy, "max", key)
      local id = B.Create(preset.name, key)
      assertWellFormed(id)
      assertEqual(rules(B.Get(id).bands), rules(preset.bands), key .. ": the stored copy carries the rules")
      for i, b in ipairs(B.Get(id).bands) do
        assertTrue(b.rule == nil or b.rule ~= preset.bands[i].rule, key .. ": a rule is copied, never shared")
      end
    end
  end)
end)

-- The class presets (RangeMaster#20), every class on both clients: labels | rules, band by band. The
-- tiers are DB2's (SF-RM-01's bundles, docs/seed-research/2026-11-25-*), the yards each band's
-- fallback. Pinned whole, so a band moved, added or re-ruled is a red here first.
local CLASS_SHAPES = {
  retail = {
    WARRIOR = "MELEE,CLOSE,CHARGE,RANGE,OOR|melee,yards,tier25,ranged,beyond|5,8,25,30",
    PALADIN = "MELEE,HAMMER,RANGE,OOR|melee,tier10,ranged,beyond|5,10,30",
    HUNTER = "MELEE,RANGED,OOR|melee,ranged,beyond|5,40",
    ROGUE = "MELEE,STEP,RANGE,OOR|melee,tier25,ranged,beyond|5,25,30",
    PRIEST = "CLOSE,CAST,OOR|yards,ranged,beyond|8,40",
    DEATHKNIGHT = "MELEE,FREEZE,RANGE,OOR|melee,tier15,ranged,beyond|5,15,30",
    SHAMAN = "MELEE,SHEAR,CAST,OOR|melee,tier30,ranged,beyond|5,30,40",
    MAGE = "CLOSE,CAST,OOR|yards,ranged,beyond|8,40",
    WARLOCK = "CLOSE,CAST,OOR|yards,ranged,beyond|8,40",
    MONK = "MELEE,RANGE,OOR|melee,ranged,beyond|5,40",
    DRUID = "MELEE,BASH,RANGE,OOR|melee,tier13,ranged,beyond|5,13,40",
    DEMONHUNTER = "MELEE,BLADE,RANGE,OOR|melee,tier15,ranged,beyond|5,15,30",
    EVOKER = "CLOSE,CAST,OOR|yards,ranged,beyond|8,25",
  },
  forever = {
    WARRIOR = "MELEE,CLOSE,CHARGE,RANGE,OOR|melee,yards,tier25,ranged,beyond|5,8,25,30",
    PALADIN = "MELEE,JUDGE,RANGE,OOR|melee,tier10,ranged,beyond|5,10,30",
    HUNTER = "MELEE,DEAD,RANGE,OOR|melee,gap,ranged,beyond|5,8,35",
    ROGUE = "MELEE,CLOSE,RANGE,OOR|melee,yards,ranged,beyond|5,8,30",
    PRIEST = "CLOSE,CAST,OOR|yards,ranged,beyond|8,30",
    SHAMAN = "MELEE,SHOCK,CAST,OOR|melee,tier20,ranged,beyond|5,20,30",
    MAGE = "CLOSE,BLAST,CAST,LONG,OOR|yards,tier20,tier30,ranged,beyond|8,20,30,35",
    WARLOCK = "CLOSE,DRAIN,CAST,OOR|yards,tier20,ranged,beyond|8,20,30",
    DRUID = "MELEE,RANGE,OOR|melee,ranged,beyond|5,30",
  },
}

--- The bands' far edges, the open-ended last one left out.
local function edges(bands)
  local out = {}
  for i = 1, #bands - 1 do out[i] = tostring(bands[i].to) end
  return table.concat(out, ",")
end

test("bandsets: every class has its own preset per client, at its DB2 range tiers (RangeMaster#20)", function()
  -- red under: a class with no preset on a client it exists on, or a preset whose bands moved.
  local C = NS.Constants
  for client, shapes in pairs(CLASS_SHAPES) do
    local n = 0
    for classFile, want in pairs(shapes) do
      n = n + 1
      local where = client .. "." .. classFile
      local own = P.BY_CLIENT[classFile] and P.BY_CLIENT[classFile][client]
      assertTrue(type(own) == "table", where .. " has a preset")
      assertEqual(labels(own.bands) .. "|" .. rules(own.bands) .. "|" .. edges(own.bands), want, where)
      assertEqual(own.matchBy, "max", where)
      assertTrue(#own.bands >= 3 and #own.bands <= 5, where .. ": three to five bands")
      assertEqual(own.bands[1].from, 0, where .. " starts at 0")
      assertEqual(own.bands[#own.bands].label, "OOR", where .. " ends out of range")
      for i, b in ipairs(own.bands) do
        if i > 1 then assertEqual(b.from, own.bands[i - 1].to, where .. ": band " .. i .. " is contiguous") end
        local role = b.rule and b.rule.type == "spell" and b.rule.role
        if role and C.TIER_YARDS[role] then
          assertEqual(b.to, C.TIER_YARDS[role], where .. ": a " .. role .. " band ends at its tier's yards")
        end
      end
    end
    assertEqual(n, client == "retail" and 13 or 9, client .. ": every class of the client")
  end
  for classFile in pairs(CLASS_SHAPES.retail) do
    if not CLASS_SHAPES.forever[classFile] then
      assertNil(P.BY_CLIENT[classFile].forever, classFile .. " has no WoW Forever list (no such class there)")
    end
  end
end)

test("bandsets: every rule of a class preset names a role its class has anchors for on that client", function()
  -- red under: a band asking a tier the class's seed has no list for (it would always read its yards).
  for client, shapes in pairs(CLASS_SHAPES) do
    for classFile in pairs(shapes) do
      local anchors = NS.SpellSeeds[client][classFile].anchors
      for _, b in ipairs(P.BY_CLIENT[classFile][client].bands) do
        local role = b.rule and b.rule.type == "spell" and b.rule.role
        if role then
          local list = anchors[role]
          assertTrue(type(list) == "table" and next(list) ~= nil,
            client .. "." .. classFile .. ": the " .. b.label .. " band's role " .. role .. " has anchors")
        end
      end
    end
  end
  -- The Forever paladin's 10 yd tier is the owner's case (2026-11-25): the seal-and-judge spell 20271
  -- first, Hammer of Justice 853 after it.
  local tier10 = NS.SpellSeeds.forever.PALADIN.anchors.tier10
  assertEqual(table.concat(tier10, ","), "20271,853")
end)

test("bandsets: the running client's class presets are the ones Create and the seed take", function()
  local client = NS.Compat.ClientKey() == "forever" and "forever" or "retail"
  local keys = {}
  for _, key in ipairs(P.CLASS_KEYS) do keys[key] = true end
  for classFile in pairs(CLASS_SHAPES.retail) do
    local key = classFile:lower()
    local own = P.BY_CLIENT[classFile][client]
    if own then
      assertTrue(P[key] == own, key .. " is this client's list")
      assertTrue(keys[key], key .. " is in CLASS_KEYS")
    else
      assertNil(P[key], key .. ": no preset on a client without the class")
      assertNil(keys[key], key .. " is not in CLASS_KEYS")
    end
  end
  assertEqual(#P.CLASS_KEYS, client == "retail" and 13 or 9)
  withFreshProfile(function()
    for _, key in ipairs(P.CLASS_KEYS) do
      local id = B.Create(nil, key)
      assertTrue(id ~= nil, key .. " creates")
      assertWellFormed(id)
      assertEqual(rules(B.Get(id).bands), rules(P[key].bands), key .. ": the stored copy carries the rules")
      for i, b in ipairs(B.Get(id).bands) do
        assertTrue(b.rule == nil or b.rule ~= P[key].bands[i].rule, key .. ": a rule is copied, never shared")
      end
    end
    if client == "forever" then assertNil(B.Create(nil, "evoker"), "no Evoker preset on WoW Forever") end
  end)
end)

test("bandsets: DefaultFor picks the class's own preset, and an unknown class gets Melee / Ranged", function()
  for _, key in ipairs(P.CLASS_KEYS) do
    assertEqual(P.DefaultFor(key:upper()), key, key:upper() .. "'s default is its own preset")
  end
  assertEqual(P.DefaultFor("HUNTER"), "hunter")
  assertEqual(P.DefaultFor("PALADIN"), "paladin", "the owner's case: a paladin has its own set (RangeMaster#20)")
  assertEqual(P.DefaultFor(nil), "melee_ranged")
  assertEqual(P.DefaultFor("NOT_A_CLASS"), "melee_ranged")
  if NS.Compat.ClientKey() == "forever" then
    assertEqual(P.DefaultFor("EVOKER"), "melee_ranged", "a class the client lacks: Melee / Ranged")
  else
    -- red under: a class-only pick (Devourer, a 25 yd Intellect spec, got Melee / Ranged; owner 2026-11-19).
    assertEqual(P.DefaultFor("DEMONHUNTER", 1480), "caster40", "Devourer reads as a caster")
    assertEqual(P.DefaultFor("DEMONHUNTER", 577), "demonhunter", "Havoc keeps its class's set")
    assertEqual(P.DefaultFor("DEMONHUNTER"), "demonhunter", "no spec answer: the class's set")
  end
  assertEqual(P.DefaultFor("DEMONHUNTER", 1480), "caster40", "the spec override holds on any client")
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

-- ── the band rule writer (dynamic-bands plan D5) ─────────────────────────────────────────────

test("bandsets: SetBandRule writes a band's rule as a copy, nil makes a yard band, and announces", function()
  -- red under: no SetBandRule (the Band sets page's Defined by, role and spell override write here).
  withFreshProfile(function()
    local id = B.Create("Rules", { { from = 0, to = 5, label = "A" }, { from = 5, to = 30, label = "B" },
      { from = 30, label = "C" } })
    local spells = { 3044, 14281 }
    assertEqual(countChanged(function()
      assertTrue(B.SetBandRule(id, 2, { type = "spell", role = "ranged", spells = spells }))
    end), 1, "one BANDSETS_CHANGED")
    local rule = B.Get(id).bands[2].rule
    assertEqual(rule.type, "spell")
    assertEqual(rule.role, "ranged")
    assertEqual(rule.spells[2], 14281)
    assertTrue(rule.spells ~= spells, "the list is a copy, never the caller's table (D3's per-list cache)")
    assertTrue(B.SetBandRule(id, 1, { type = "gap" }))
    assertEqual(B.Get(id).bands[1].rule.type, "gap")
    assertTrue(B.SetBandRule(id, 3, { type = "beyond" }))
    assertEqual(B.Get(id).bands[3].rule.type, "beyond")
    assertTrue(B.SetBandRule(id, 3, nil), "nil: a yard band")
    assertNil(B.Get(id).bands[3].rule)
    assertTrue(B.SetBandRule(id, 2, { type = "spell", role = "melee" }))
    assertNil(B.Get(id).bands[2].rule.spells, "no list: the class's anchors for the role")
    assertEqual(B.Get(id).bands[2].from, 5, "the yards never move")
    assertEqual(B.Get(id).bands[2].to, 30)
  end)
end)

test("bandsets: SetBandRule refuses a bad set, band, type, role or spell list, and announces nothing", function()
  withFreshProfile(function()
    local id = B.DefaultId()
    local before = NS.Database.DeepCopy(B.Get(id).bands[1].rule)
    assertEqual(countChanged(function()
      assertFalse(B.SetBandRule(999, 1, { type = "gap" }), "an unknown set")
      assertFalse(B.SetBandRule(id, 99, { type = "gap" }), "a band the set does not have")
      assertFalse(B.SetBandRule(id, 1, { type = "mark" }), "an unknown type")
      assertFalse(B.SetBandRule(id, 1, "gap"), "a rule that is not a table")
      assertFalse(B.SetBandRule(id, 1, { type = "spell" }), "a spell rule with no role")
      assertFalse(B.SetBandRule(id, 1, { type = "spell", role = "long" }), "a role outside the three")
      assertFalse(B.SetBandRule(id, 1, { type = "spell", role = "melee", spells = {} }), "an empty list")
      assertFalse(B.SetBandRule(id, 1, { type = "spell", role = "melee", spells = { 0 } }), "an ID under 1")
      assertFalse(B.SetBandRule(id, 1, { type = "spell", role = "melee", spells = { 1.5 } }), "a fraction")
      assertFalse(B.SetBandRule(id, 1, { type = "spell", role = "melee", spells = { "x" } }), "not a number")
    end), 0, "a refusal announces nothing")
    local after = B.Get(id).bands[1].rule
    assertEqual(after and after.type, before and before.type, "and leaves the rule as it was")
  end)
end)

-- ---------------------------------------------------------------------------
-- Origins: set.origin, PresetKeys, Diff, IsModified, RestorePreset, CopyFrom (RangeMaster#21)
-- ---------------------------------------------------------------------------

--- Deep equality for a test's comparisons.
local function deepEqual(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

--- A Diff, one "band:field" word an entry ("-" for a set field), joined.
local function diffWords(diff)
  local out = {}
  for i, e in ipairs(diff) do out[i] = (e.band or "-") .. ":" .. e.field end
  return table.concat(out, ",")
end

--- The class preset count per client (the spec: 9 on WoW Forever, 13 on Retail).
local CLASS_COUNT = { forever = 9, retail = 13 }

test("bandsets: a set made from a preset remembers it as origin; Duplicate copies it, a bands array has none", function()
  -- Red before RangeMaster#21: no stored set remembers its preset.
  withFreshProfile(function()
    assertEqual(B.Get(B.Create("P", "paladin")).origin, "paladin", "Create from a preset key")
    assertEqual(B.Get(B.Create("M")).origin, "melee_ranged", "Create with no source copies Melee / Ranged")
    assertNil(B.Get(B.Create("Arr", { { from = 0, to = nil, label = "X" } })).origin, "a bands array has none")
    assertNil(B.Get(B.Create("Blank", {})).origin, "a blank set has none")
    assertNil(B.Create("Bad", "BY_CLIENT"), "a field of the preset module is not a preset key")
    assertNil(B.Create("Bad", "DefaultFor"), "nor is its function")
    local src = B.Create("C", "caster40")
    assertEqual(B.Get(B.Duplicate(src)).origin, "caster40", "Duplicate copies the origin")
    local set = B.Get(src)
    set.origin = 42
    B.NormalizeSet(set)
    assertNil(set.origin, "an origin that is not a key string is dropped on normalize")
  end)
end)

test("bandsets: the first-run seed stores each seeded set's preset as its origin", function()
  withFreshProfile(function()
    local ids = B.List()
    assertEqual(B.Get(ids[1]).origin, P.DefaultFor(NS.Compat.PlayerClass(), NS.Compat.PlayerSpecID()),
      "the default set is the class default")
    for _, id in ipairs(ids) do
      local set = B.Get(id)
      assertTrue(type(set.origin) == "string", set.name .. " has an origin")
      assertEqual(set.name, P[set.origin].name, set.name .. " is its origin's copy")
      assertFalse(B.IsModified(id), set.name .. " is not modified")
    end
  end, "PALADIN")
end)

test("bandsets: PresetKeys lists every class preset, then the generic ones, each once", function()
  local keys = B.PresetKeys()
  assertEqual(#keys.classes, CLASS_COUNT[NS.Compat.ClientKey()], "the client's class preset count")
  assertEqual(table.concat(keys.classes, ","), table.concat(P.CLASS_KEYS, ","), "in class order")
  assertEqual(table.concat(keys.general, ","), "melee_ranged,caster40,healer",
    "the Hunter preset is a class's, so it is listed once, under the classes")
  local seen = {}
  for _, list in ipairs({ keys.classes, keys.general }) do
    for _, key in ipairs(list) do
      assertNil(seen[key], key .. " is listed once")
      seen[key] = true
      assertTrue(type(P[key]) == "table" and type(P[key].bands) == "table", key .. " is a preset")
    end
  end
  keys.classes[1] = "mutated"
  assertEqual(B.PresetKeys().classes[1], P.CLASS_KEYS[1], "each call answers new tables")
  assertEqual(P.CLASS_KEYS[1], "warrior", "CLASS_KEYS itself is untouched")
end)

test("bandsets: Diff answers an empty list for an untouched preset copy and an entry per edited field", function()
  withFreshProfile(function()
    local id = B.Create("Pal", "paladin")
    local diff = B.Diff(id)
    assertEqual(#diff, 0, "a fresh copy matches its preset")
    assertFalse(B.IsModified(id))
    local presetLabel = P.paladin.bands[2].label
    assertTrue(B.SetBand(id, 2, "label", "HOLY"))
    diff = B.Diff(id)
    assertEqual(diffWords(diff), "2:label")
    assertEqual(diff[1].mine, "HOLY")
    assertEqual(diff[1].preset, presetLabel)
    assertTrue(B.IsModified(id))
    assertTrue(B.SetBand(id, 1, "frameColor", { r = 0.1, g = 0.2, b = 0.3, a = 1 }))
    assertTrue(B.SetField(id, "matchBy", "min"))
    assertTrue(B.SetField(id, "unknown.label", "??"))
    assertEqual(diffWords(B.Diff(id)), "-:matchBy,-:unknown.label,1:frameColor,2:label",
      "set fields first, then each band's fields")
    diff = B.Diff(id)
    diff[1].mine = "mutated"
    assertEqual(B.Get(id).matchBy, "min", "an entry holds copies, never the set's own values")
  end)
end)

test("bandsets: Diff reads a band count change as one entry, ignores sounds and a missing alpha", function()
  withFreshProfile(function()
    local id = B.Create("Pal", "paladin")
    local n = #B.Get(id).bands
    assertTrue(B.SetBandSound(id, 1, "Mine"))
    assertEqual(#B.Diff(id), 0, "a sound is the player's layer, not a departure from the preset")
    local c = B.Get(id).bands[1].textColor
    c.a = nil
    assertEqual(#B.Diff(id), 0, "a color with no alpha reads as alpha 1")
    c.r = c.r + 0.001
    assertEqual(#B.Diff(id), 0, "a color picker's float noise is not a change")
    assertTrue(B.RemoveBand(id, n))
    local diff = B.Diff(id)
    assertEqual(diff[1].field, "bands", "the count comes first")
    assertNil(diff[1].band)
    assertEqual(diff[1].mine, n - 1)
    assertEqual(diff[1].preset, n)
    local counted = 0
    for _, e in ipairs(diff) do
      if e.field == "bands" then counted = counted + 1 end
    end
    assertEqual(counted, 1, "a difference in band count is one entry")
  end)
end)

test("bandsets: Diff is nil with no origin or no such preset on this client, and IsModified is false", function()
  withFreshProfile(function()
    local id = B.Create("Arr", { { from = 0, to = 10, label = "A" }, { from = 10, label = "B" } })
    assertNil(B.Diff(id), "no origin")
    assertFalse(B.IsModified(id))
    B.Get(id).origin = "no_such_preset"
    assertNil(B.Diff(id), "an origin this client has no preset for")
    if NS.Compat.ClientKey() == "forever" then
      B.Get(id).origin = "deathknight"
      assertNil(B.Diff(id), "a Retail-only class preset is gone on WoW Forever")
    end
    assertNil(B.Diff(424242), "an unknown id")
    assertFalse(B.IsModified(424242))
  end)
end)

test("bandsets: RestorePreset puts the origin's bands, matchBy and unknown back, keeping name, id and origin", function()
  withFreshProfile(function()
    local id = B.Create("Holy", "paladin")
    assertTrue(B.SetBand(id, 2, "label", "HOLY"))
    B.AddBand(id)
    assertTrue(B.SetField(id, "matchBy", "min"))
    assertTrue(B.SetField(id, "unknown.label", "??"))
    assertTrue(B.SetBandSound(id, 1, "One"))
    local order = table.concat(B.List(), ",")
    local n = countChanged(function() assertTrue(B.RestorePreset(id)) end)
    assertEqual(n, 1, "announces once")
    local set = B.Get(id)
    assertEqual(#B.Diff(id), 0, "matches the preset again")
    assertEqual(set.name, "Holy", "the name stays")
    assertEqual(set.origin, "paladin", "the origin stays")
    assertEqual(table.concat(B.List(), ","), order, "the id and the order stay")
    assertNil(set.bands[1].sound, "without keepSounds the preset's bands carry no sound")
    assertTrue(set.bands ~= P.paladin.bands and set.bands[1] ~= P.paladin.bands[1], "a copy, never the preset")
    assertTrue(set.unknown ~= P.paladin.unknown, "its own unknown band")
  end)
end)

test("bandsets: RestorePreset with keepSounds keeps each band's sound by index", function()
  withFreshProfile(function()
    local id = B.Create("Holy", "paladin")
    local n = #B.Get(id).bands
    for i = 1, n do assertTrue(B.SetBandSound(id, i, "S" .. i)) end
    assertTrue(B.SetBand(id, 1, "label", "X"))
    assertTrue(B.RestorePreset(id, true))
    for i = 1, n do assertEqual(B.Get(id).bands[i].sound, "S" .. i, "same count: band " .. i .. " keeps its sound") end
    -- One band fewer: the preset's last band has no band of mine at its index, so it gets none.
    assertTrue(B.RemoveBand(id, n))
    for i = 1, n - 1 do assertTrue(B.SetBandSound(id, i, "T" .. i)) end
    assertTrue(B.RestorePreset(id, true))
    local bands = B.Get(id).bands
    assertEqual(#bands, n, "the preset's band count is back")
    for i = 1, n - 1 do assertEqual(bands[i].sound, "T" .. i, "band " .. i .. " keeps its index's sound") end
    assertNil(bands[n].sound, "a band with no band of mine at its index has none")
  end)
end)

test("bandsets: RestorePreset refuses an unknown set and one with no origin, and announces nothing", function()
  withFreshProfile(function()
    local id = B.Create("Arr", { { from = 0, label = "A" } })
    assertEqual(countChanged(function()
      assertFalse(B.RestorePreset(id), "no origin")
      assertFalse(B.RestorePreset(424242), "an unknown id")
      B.Get(id).origin = "no_such_preset"
      assertFalse(B.RestorePreset(id), "an origin this client has no preset for")
    end), 0)
    assertEqual(labels(B.Get(id).bands), "A", "the set is untouched")
  end)
end)

test("bandsets: CopyFrom a preset replaces the bands, sets the origin, and takes general fields only when asked", function()
  withFreshProfile(function()
    local id = B.Create("Mine", "melee_ranged")
    assertTrue(B.SetField(id, "matchBy", "min"))
    assertTrue(B.SetField(id, "unknown.label", "??"))
    assertTrue(B.SetBandSound(id, 1, "One"))
    local n = countChanged(function() assertTrue(B.CopyFrom(id, { preset = "caster40" })) end)
    assertEqual(n, 1, "announces once")
    local set = B.Get(id)
    assertEqual(labels(set.bands), labels(P.caster40.bands), "the preset's bands")
    assertTrue(set.bands[1] ~= P.caster40.bands[1], "copied, never referenced")
    assertEqual(set.origin, "caster40", "the origin is now the preset")
    assertEqual(set.name, "Mine", "the name stays")
    assertEqual(set.matchBy, "min", "general off: matchBy stays")
    assertEqual(set.unknown.label, "??", "general off: the unknown band stays")
    assertEqual(set.bands[1].sound, "One", "sounds off: band 1 keeps its sound")
    assertEqual(diffWords(B.Diff(id)), "-:matchBy,-:unknown.label", "the kept general fields read as changes")
    assertTrue(B.CopyFrom(id, { preset = "caster40" }, { sounds = true, general = true }))
    set = B.Get(id)
    assertEqual(set.matchBy, "max", "general on: the preset's matchBy")
    assertEqual(set.unknown.label, NS.Constants.UNKNOWN_LABEL, "general on: the preset's unknown band")
    assertNil(set.bands[1].sound, "sounds on: the preset's (none)")
    assertEqual(#B.Diff(id), 0)
  end)
end)

test("bandsets: CopyFrom one of my sets takes its bands, its sounds when asked, and its origin", function()
  withFreshProfile(function()
    local src = B.Create("Src", "paladin")
    assertTrue(B.SetBand(src, 1, "label", "SRC"))
    assertTrue(B.SetBandSound(src, 1, "SrcSound"))
    assertTrue(B.SetField(src, "matchBy", "min"))
    local dst = B.Create("Dst", "caster40")
    assertTrue(B.SetBandSound(dst, 1, "DstSound"))
    assertTrue(B.CopyFrom(dst, src))
    local set = B.Get(dst)
    assertEqual(labels(set.bands), labels(B.Get(src).bands), "the source's bands")
    assertTrue(set.bands[1] ~= B.Get(src).bands[1], "copied")
    assertEqual(set.bands[1].sound, "DstSound", "sounds off: my own sound by index")
    assertEqual(set.origin, "paladin", "the source set's origin")
    assertEqual(set.matchBy, "max", "general off")
    assertTrue(B.CopyFrom(dst, src, { sounds = true, general = true }))
    assertEqual(B.Get(dst).bands[1].sound, "SrcSound", "sounds on: the source's")
    assertEqual(B.Get(dst).matchBy, "min", "general on: the source's matchBy")
    local bare = B.Create("Bare", { { from = 0, label = "Z" } })
    assertTrue(B.CopyFrom(dst, bare))
    assertNil(B.Get(dst).origin, "a source with no origin leaves none")
    assertEqual(B.Get(dst).name, "Dst", "the name stays")
  end)
end)

test("bandsets: CopyFrom refuses copying into itself, an unknown target, source or preset, and announces nothing", function()
  withFreshProfile(function()
    local id = B.Create("Mine", "paladin")
    local before = labels(B.Get(id).bands)
    assertEqual(countChanged(function()
      assertFalse(B.CopyFrom(id, id), "into itself")
      assertFalse(B.CopyFrom(424242, B.DefaultId()), "an unknown target")
      assertFalse(B.CopyFrom(id, 424242), "an unknown source set")
      assertFalse(B.CopyFrom(id, { preset = "no_such_preset" }), "an unknown preset")
      assertFalse(B.CopyFrom(id, { preset = "ORDER" }), "a field of the preset module")
      assertFalse(B.CopyFrom(id, {}), "a source table naming no preset")
    end), 0)
    assertEqual(labels(B.Get(id).bands), before, "the set is untouched")
    assertEqual(B.Get(id).origin, "paladin")
  end)
end)

test("bandsets: a Snapshot taken before RestorePreset or CopyFrom undoes it whole, origin included", function()
  withFreshProfile(function()
    local id = B.Create("Holy", "paladin")
    assertTrue(B.SetBand(id, 2, "label", "HOLY"))
    assertTrue(B.SetBandSound(id, 1, "One"))
    local before = NS.Database.DeepCopy(B.Get(id))
    local snap = B.Snapshot()
    assertTrue(B.RestorePreset(id))
    assertTrue(B.RestoreSnapshot(snap), "undo the restore")
    assertTrue(deepEqual(B.Get(id), before), "the restore is undone whole")
    snap = B.Snapshot()
    assertTrue(B.CopyFrom(id, { preset = "caster40" }, { sounds = true, general = true }))
    assertEqual(B.Get(id).origin, "caster40")
    assertTrue(B.RestoreSnapshot(snap), "undo the copy")
    assertTrue(deepEqual(B.Get(id), before), "the copy is undone whole")
    assertEqual(B.Get(id).origin, "paladin", "the origin comes back")
    assertTrue(B.IsModified(id), "and so does the modification")
  end)
end)
