-- tests/test_range.lua — the range engine (modules/Range.lua) and the per-client ladder behind it
-- (core/Compat.lua's RangeLadder, defaults/SpellSeeds.lua). The v0.1.0 plan, Task 2; design spec
-- section 5.1.
--
-- LibRangeCheck-3.0 is the real vendored library, loaded by tests/run.lua; each case replaces its
-- GetRange method for the case's length, so the wrapper is measured against the answers the library
-- can give (a bracket, an open-ended bracket, nothing, a secret, an error), never against a stand-in
-- of the wrapper itself. Unit existence is the kit's M.__unitExists, read at call time.

local T = _G.RM_TEST
local NS, M = T.NS, T.mocks
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local Loader = dofile("tests/_kit/loader.lua")
local profile = Loader.MockClient.current()
local LRC = M.LibStub("LibRangeCheck-3.0", true)

--- Whether a timer handle is no longer armed: absent from the kit's live set, M.__timers().
local function stopped(handle)
  for _, t in ipairs(M.__timers()) do if t == handle then return false end end
  return true
end


--- Run `body` with LRC:GetRange answering `fn(unit)`, counting the calls; restores the library's
--- own method, the units and combat whether or not `body` raised. Answers the call count.
local function withRange(fn, units, body)
  local realGet, calls = LRC.GetRange, 0
  local realUnits = M.__unitExists
  local exists = { player = true }
  for unit, on in pairs(units or {}) do exists[unit] = on end
  M.__unitExists = exists
  LRC.GetRange = function(_, unit, ...)
    calls = calls + 1
    return fn(unit, ...)
  end
  NS.Range.BeginTick()
  local ok, err = pcall(body, function() return calls end)
  LRC.GetRange = realGet
  M.__unitExists = realUnits
  M.InCombatLockdown = function() return false end
  NS.Range.BeginTick()
  if not ok then error(err, 0) end
  return calls
end

local function answers(a, b) return function() return a, b end end

test("range: test_known_bracket — a 20 to 25 yd answer reads known 20, 25", function()
  withRange(answers(20, 25), { target = true }, function()
    local state, lo, hi = NS.Range.Get("target")
    assertEqual(state, "known")
    assertEqual(lo, 20)
    assertEqual(hi, 25)
  end)
end)

test("range: the library is asked with no cache of its own (maxCacheAge 0)", function()
  -- LibRangeCheck keeps an answer 0.1 s by default, keyed by the unit TOKEN when the GUID is a
  -- secret: a target swap inside that window would hand back the previous target's bracket.
  local shape
  withRange(function(unit, checkVisible, noItems, maxCacheAge)
    shape = { unit, checkVisible, noItems, maxCacheAge }
    return 20, 25
  end, { target = true }, function()
    NS.Range.Get("target")
  end)
  assertEqual(shape[1], "target")
  assertEqual(shape[2], true, "checkVisible")
  assertNil(shape[3], "noItems is left to the library")
  assertEqual(shape[4], 0, "maxCacheAge 0: the library always queries again")
end)

test("range: test_open_ended — a min with no max reads known and open-ended", function()
  withRange(answers(40, nil), { target = true }, function()
    local state, lo, hi = NS.Range.Get("target")
    assertEqual(state, "known")
    assertEqual(lo, 40)
    assertNil(hi, "past the last checker there is no max")
  end)
end)

test("range: test_secret_is_unknown — a secret bound reads unknown, never out of range", function()
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    for _, pair in ipairs({ { T.secret(20), 25 }, { 20, T.secret(25) } }) do
      withRange(answers(pair[1], pair[2]), { target = true }, function()
        local state, lo, hi = NS.Range.Get("target")
        assertEqual(state, "unknown", "a secret is unknown")
        assertNil(lo, "no min handed on")
        assertNil(hi, "no max handed on")
      end)
    end
  end)
  restore()
  if not ok then error(err, 0) end
end)

test("range: test_error_is_unknown — the library raising reads unknown, and nothing escapes", function()
  withRange(function() error("boom") end, { target = true }, function()
    local ok, state = pcall(NS.Range.Get, "target")
    assertTrue(ok, "Range.Get raised: " .. tostring(state))
    assertEqual(state, "unknown")
  end)
end)

test("range: test_no_unit_is_none — a unit that does not exist reads none, and is never queried", function()
  local calls = withRange(answers(20, 25), { target = false }, function()
    local state, lo, hi = NS.Range.Get("target")
    assertEqual(state, "none")
    assertNil(lo)
    assertNil(hi)
  end)
  assertEqual(calls, 0, "a missing unit costs no range query")
end)

test("range: test_memo_one_query_per_tick — three reads of one unit in a tick are one query", function()
  local calls = withRange(answers(20, 25), { target = true }, function(count)
    NS.Range.Get("target")
    NS.Range.Get("target")
    NS.Range.Get("target")
    assertEqual(count(), 1, "one query for three reads inside a tick")
    NS.Range.BeginTick()
    NS.Range.Get("target")
    assertEqual(count(), 2, "a new tick queries again")
  end)
  assertEqual(calls, 2)
end)

test("range: test_range_unit_vanishes — a unit gone after BeginTick reads none, no error", function()
  withRange(answers(20, 25), { target = true }, function()
    assertEqual((NS.Range.Get("target")), "known", "precondition: the unit exists")
    M.__unitExists.target = false
    assertEqual((NS.Range.Get("target")), "known", "inside the same tick the memo answers")
    NS.Range.BeginTick()
    local ok, state = pcall(NS.Range.Get, "target")
    assertTrue(ok, "a vanished unit raised: " .. tostring(state))
    assertEqual(state, "none")
  end)
end)

test("range: the memo is keyed by unit token, nameplate tokens included", function()
  local seen = {}
  withRange(function(unit)
    seen[#seen + 1] = unit
    return unit == "nameplate3" and 5 or 30, unit == "nameplate3" and 8 or 35
  end, { target = true, nameplate3 = true }, function()
    local _, lo = NS.Range.Get("nameplate3")
    local _, lo2 = NS.Range.Get("target")
    assertEqual(lo, 5, "nameplate3 has its own entry")
    assertEqual(lo2, 30, "target has its own entry")
    NS.Range.Get("nameplate3")
  end)
  assertEqual(#seen, 2, "one query per token")
end)

--- Swap the spell APIs for the case's length. `usable(id)` answers C_Spell.IsSpellUsable (every
--- spell usable when omitted).
local function withSpells(known, inRange, body, usable)
  local realBook, realSpell = M.C_SpellBook.IsSpellKnown, M.C_Spell.IsSpellInRange
  local realUsable = M.C_Spell.IsSpellUsable
  local asked = 0
  M.C_SpellBook.IsSpellKnown = function(id) return known[id] == true end
  M.C_Spell.IsSpellInRange = function(id, unit)
    asked = asked + 1
    return inRange(id, unit)
  end
  M.C_Spell.IsSpellUsable = usable or function() return true, false end
  NS.Range.__rebuildNow()
  local ok, err = pcall(body, function() return asked end)
  M.C_SpellBook.IsSpellKnown, M.C_Spell.IsSpellInRange = realBook, realSpell
  M.C_Spell.IsSpellUsable = realUsable
  NS.Range.__rebuildNow()
  if not ok then error(err, 0) end
end

test("range: test_spell_unknown_spell_nil — a spell the player does not know answers nil", function()
  M.__unitExists.target = true
  withSpells({ [133] = true }, function() return true end, function(asked)
    assertNil(NS.Range.InSpellRange(116, "target"), "an unknown spell is not asked")
    assertEqual(asked(), 0, "and the range API is never called for it")
    assertEqual(NS.Range.InSpellRange(133, "target"), true, "a known spell in range")
  end)
  withSpells({ [133] = true }, function() return false end, function()
    assertEqual(NS.Range.InSpellRange(133, "target"), false, "a known spell out of range")
  end)
  M.__unitExists.target = false
end)

test("range: a known spell that is unusable right now is not trusted (research lesson 9)", function()
  -- Wrath in Cat Form: known, unusable in the form, and the client can report it in range from
  -- anywhere. Usability is asked per call, never cached, so a form change needs no rebuild.
  local usableNow = false
  M.__unitExists.target = true
  withSpells({ [5176] = true }, function() return true end, function(asked)
    assertNil(NS.Range.InSpellRange(5176, "target"), "unusable: no answer")
    assertEqual(asked(), 0, "and the range API is not asked")
    usableNow = true
    NS.Range.BeginTick()   -- an answer holds for its tick (the spell memo, dynamic-bands plan D3)
    assertEqual(NS.Range.InSpellRange(5176, "target"), true, "usable again, trusted again")
  end, function() return usableNow, false end)
  withSpells({ [5176] = true }, function() return false end, function()
    assertEqual(NS.Range.InSpellRange(5176, "target"), false, "short of power is still usable")
  end, function() return false, true end)
  M.__unitExists.target = false
end)

test("range: a secret or raising usability answer is not trusted", function()
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    M.__unitExists.target = true
    withSpells({ [133] = true }, function() return true end, function()
      assertNil(NS.Range.InSpellRange(133, "target"), "a secret usability is nil")
    end, function() return T.secret(true), false end)
    withSpells({ [133] = true }, function() return true end, function()
      assertNil(NS.Range.InSpellRange(133, "target"), "a raising usability is nil")
    end, function() error("boom") end)
  end)
  restore()
  M.__unitExists.target = false
  if not ok then error(err, 0) end
end)

test("range: InSpellRange answers nil for a secret, an error or a missing unit", function()
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    M.__unitExists.target = true
    withSpells({ [133] = true }, function() return T.secret(true) end, function()
      assertNil(NS.Range.InSpellRange(133, "target"), "a secret answer is nil")
    end)
    withSpells({ [133] = true }, function() error("boom") end, function()
      assertNil(NS.Range.InSpellRange(133, "target"), "a raising API is nil")
    end)
    M.__unitExists.target = false
    withSpells({ [133] = true }, function() return true end, function(asked)
      assertNil(NS.Range.InSpellRange(133, "target"), "no unit, no answer")
      assertEqual(asked(), 0)
    end)
  end)
  restore()
  M.__unitExists.target = false
  if not ok then error(err, 0) end
end)

-- ── the per-client ladder ────────────────────────────────────────────────────────────────────

local FOREVER_YARDS = { [20] = true, [30] = true, [35] = true, [28] = true, [10] = true }

-- The item and interact rungs are held to the reliable yards; a spell rung sits at its own max
-- range (the spell-rung cases below), so the subset holds for those two kinds only.
test("range: test_forever_ladder — Forever's ladder holds only the reliable yards", function()
  local ladder = NS.Compat.RangeLadder()
  assertEqual(type(ladder), "table", "RangeLadder answers a list")
  local kinds = {}
  for i, e in ipairs(ladder) do
    assertTrue(e.kind == "item" or e.kind == "interact" or e.kind == "spell", "entry kind " .. i)
    assertEqual(type(e.id), "number", "entry id " .. i)
    assertEqual(type(e.yd), "number", "entry yd " .. i)
    if i > 1 then assertTrue(ladder[i - 1].yd <= e.yd, "sorted by yd ascending") end
    kinds[e.kind] = (kinds[e.kind] or 0) + 1
    if profile == "forever" and e.kind ~= "spell" then
      assertTrue(FOREVER_YARDS[e.yd], ("Forever entry %s:%d at %d yd is not a reliable yard")
        :format(e.kind, e.id, e.yd))
    end
  end
  if profile == "forever" then
    assertTrue((kinds.item or 0) > 0, "Forever carries the 20/30/35 yd items")
    assertEqual(kinds.interact, 2, "and the two interact distances")
  else
    assertNil(kinds.item, "Retail leaves items to LibRangeCheck")
    assertNil(kinds.interact, "and interact distances too")
  end
end)

test("range: the interact rungs are race-adjusted", function()
  if profile ~= "forever" then return end
  local realRace = M.UnitRace
  M.UnitRace = function() return "Tauren", "Tauren" end
  local ladder = NS.Compat.RangeLadder()
  M.UnitRace = realRace
  local yds = {}
  for _, e in ipairs(ladder) do if e.kind == "interact" then yds[e.id] = e.yd end end
  assertEqual(yds[3], 8, "a Tauren's duel distance is shorter")
  assertEqual(yds[4], 25, "and so is the follow distance")
end)

--- Run `body` with the player knowing `known` and C_Spell.GetSpellInfo answering `info[id]`
--- ({ minRange, maxRange }); the ladder is rebuilt around the swap and after it.
local function withSpellInfo(known, info, body)
  local realBook, realInfo = M.C_SpellBook.IsSpellKnown, M.C_Spell.GetSpellInfo
  M.C_SpellBook.IsSpellKnown = function(id) return known[id] == true end
  M.C_Spell.GetSpellInfo = function(id)
    local r = info[id]
    if r then return { name = "spell" .. id, iconID = 1, castTime = 0, minRange = r[1], maxRange = r[2], spellID = id } end
  end
  NS.Range.__rebuildNow()
  local ok, err = pcall(body)
  M.C_SpellBook.IsSpellKnown, M.C_Spell.GetSpellInfo = realBook, realInfo
  NS.Range.__rebuildNow()
  if not ok then error(err, 0) end
end

local function spellRungs()
  local out = {}
  for _, e in ipairs(NS.Compat.RangeLadder()) do
    if e.kind == "spell" then out[#out + 1] = e.id .. "@" .. e.yd end
  end
  return table.concat(out, ",")
end

test("range: a known seed spell is a rung at its own max range; unknown, min-range and secret are not", function()
  -- The kit's player is a MAGE: the seeds are 133, 116, 2136 on Forever and 116, 118 on Retail.
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    local seeds = NS.SpellSeeds[profile].MAGE.ladder
    local a, b = seeds[1], seeds[2]
    withSpellInfo({ [a] = true, [b] = true }, { [a] = { 0, 40 }, [b] = { 5, 30 } }, function()
      assertEqual(spellRungs(), a .. "@40", "known with no min range; the min-range one is dropped")
    end)
    withSpellInfo({ [b] = true }, { [a] = { 0, 40 }, [b] = { 0, 30 } }, function()
      assertEqual(spellRungs(), b .. "@30", "an unknown seed is no rung")
    end)
    withSpellInfo({ [a] = true }, { [a] = { 0, T.secret(40) } }, function()
      assertEqual(spellRungs(), "", "a secret max range is no rung")
    end)
    withSpellInfo({ [a] = true }, { [a] = { 0, 0 } }, function()
      assertEqual(spellRungs(), "", "a max range of 0 is no rung")
    end)
  end)
  restore()
  if not ok then error(err, 0) end
end)

--- Answer item and interact checks as a unit at `distance` yards would.
local function atDistance(distance, body)
  local realItem, realInteract = M.C_Item.IsItemInRange, M.CheckInteractDistance
  local touched = 0
  local ladder = {}
  for _, e in ipairs(NS.Compat.RangeLadder()) do ladder[e.kind .. e.id] = e.yd end
  M.C_Item.IsItemInRange = function(id)
    touched = touched + 1
    return distance <= ladder["item" .. id]
  end
  M.CheckInteractDistance = function(_, index)
    touched = touched + 1
    return distance <= ladder["interact" .. index]
  end
  NS.Range.__rebuildNow()
  local ok, err = pcall(body, function() return touched end)
  M.C_Item.IsItemInRange, M.CheckInteractDistance = realItem, realInteract
  NS.Range.__rebuildNow()
  if not ok then error(err, 0) end
end

test("range: on Forever an empty library answer falls back to the ladder", function()
  atDistance(25, function()
    withRange(answers(nil, nil), { target = true }, function()
      local state, lo, hi = NS.Range.Get("target")
      if profile == "forever" then
        assertEqual(state, "known", "the ladder answered")
        assertEqual(lo, 20, "beyond the 20 yd items")
        assertEqual(hi, 28, "inside the follow distance")
      else
        assertEqual(state, "unknown", "Retail has no ladder fallback: no answer is unknown")
      end
    end)
  end)
end)

test("range: the ladder walk is open-ended past its last rung", function()
  if profile ~= "forever" then return end
  atDistance(50, function()
    withRange(answers(nil, nil), { target = true }, function()
      local state, lo, hi = NS.Range.Get("target")
      assertEqual(state, "known")
      assertEqual(lo, 35)
      assertNil(hi)
    end)
  end)
end)

test("range: the Forever walk trusts a spell rung only while the spell is usable", function()
  if profile ~= "forever" then return end
  local realUsable, realInRange = M.C_Spell.IsSpellUsable, M.C_Spell.IsSpellInRange
  local usableNow = true
  M.C_Spell.IsSpellUsable = function() return usableNow, false end
  M.C_Spell.IsSpellInRange = function() return true end    -- what an unusable spell may report
  local ok, err = pcall(function()
    withSpellInfo({ [133] = true }, { [133] = { 0, 40 } }, function()
      atDistance(50, function()
        withRange(answers(nil, nil), { target = true }, function()
          local state, lo, hi = NS.Range.Get("target")
          assertEqual(state, "known")
          assertEqual(lo, 35, "past every item")
          assertEqual(hi, 40, "inside the usable spell rung")
          usableNow = false
          NS.Range.BeginTick()
          state, lo, hi = NS.Range.Get("target")
          assertEqual(state, "known")
          assertEqual(lo, 35)
          assertNil(hi, "an unusable spell rung bounds nothing")
        end)
      end)
    end)
  end)
  M.C_Spell.IsSpellUsable, M.C_Spell.IsSpellInRange = realUsable, realInRange
  if not ok then error(err, 0) end
end)

test("range: friendly in combat, the ladder asks spells only (items and interact are blocked)", function()
  local realAttack = M.UnitCanAttack
  M.UnitCanAttack = function() return false end
  atDistance(25, function(touched)
    withRange(answers(nil, nil), { target = true }, function()
      M.InCombatLockdown = function() return true end
      local state = NS.Range.Get("target")
      assertEqual(state, "unknown", "no spell rung, so no answer")
      assertEqual(touched(), 0, "no item or interact check was made on a friendly unit in combat")
    end)
  end)
  M.UnitCanAttack = realAttack
end)

test("range: Rebuild is debounced to one rebuild after the last call", function()
  local realNew, handles = M.C_Timer.NewTimer, {}
  M.C_Timer.NewTimer = function(delay, fn)
    local h = realNew(delay, fn)
    handles[#handles + 1] = h
    return h
  end
  local base = NS.Range.__rebuildCount()
  local function built() return NS.Range.__rebuildCount() - base end
  local ok, err = pcall(function()
    NS.Range.Rebuild()
    NS.Range.Rebuild()
    NS.Range.Rebuild()
    assertEqual(#handles, 3, "each call re-arms the debounce")
    assertEqual(handles[3].delay, 0.5, "half a second after the last call")
    assertTrue(stopped(handles[1]) and stopped(handles[2]), "the earlier timers are canceled")
    assertFalse(stopped(handles[3]), "the last one is armed")
    assertEqual(built(), 0, "nothing rebuilt before the timer fires")
    handles[3].fn()
    assertEqual(built(), 1, "one rebuild")
  end)
  M.C_Timer.NewTimer = realNew
  if not ok then error(err, 0) end
end)

test("range: a Rebuild asked while stood down arms nothing and runs at the stand-up", function()
  -- red under: Range.Rebuild arming its timer whatever the latch says (a SPELLS_CHANGED handler
  -- reached on a stood-down addon leaves a timer armed), or Ticker.StandUp not running the owed
  -- rebuild (spells learned while disabled are never seen).
  local realNew, handles = M.C_Timer.NewTimer, {}
  M.C_Timer.NewTimer = function(delay, fn)
    local h = realNew(delay, fn)
    -- The rebuild's debounce only: the stand-up's container apply arms its own zero-delay timer.
    if delay == 0.5 then handles[#handles + 1] = h end
    return h
  end
  local base = NS.Range.__rebuildCount()
  local function built() return NS.Range.__rebuildCount() - base end
  local ok, err = pcall(function()
    NS.SetByPath("enabled", false)
    NS.Range.Rebuild()
    assertEqual(#handles, 0, "a stood-down addon arms no rebuild timer")
    assertEqual(built(), 0, "and rebuilds nothing")
    NS.SetByPath("enabled", true)
    assertEqual(built(), 1, "the stand-up runs the owed rebuild, once")
    assertEqual(#handles, 0, "synchronously, with no timer")
    NS.SetByPath("enabled", false)
    NS.SetByPath("enabled", true)
    assertEqual(built(), 1, "nothing owed, nothing rebuilt")
  end)
  M.C_Timer.NewTimer = realNew
  NS.SetByPath("enabled", true)
  if not ok then error(err, 0) end
end)

test("range: every class seed table is well-formed on both clients", function()
  for _, client in ipairs({ "retail", "forever" }) do
    local byClass = NS.SpellSeeds[client]
    assertEqual(type(byClass), "table", "seeds for " .. client)
    local n = 0
    for classFile, seed in pairs(byClass) do
      n = n + 1
      for _, list in ipairs({ "chips", "ladder" }) do
        assertEqual(type(seed[list]), "table", client .. "." .. classFile .. "." .. list)
        for _, id in ipairs(seed[list]) do
          assertEqual(type(id), "number", client .. "." .. classFile .. "." .. list)
        end
      end
    end
    assertTrue(n >= 9, client .. " seeds every class it has")
  end
  assertNil(NS.SpellSeeds.forever.EVOKER, "Forever is a vanilla world: no Evoker")
end)

--- The IDs of one anchor role: an array, or (druid melee) a map of form key to array, flattened.
local function anchorIds(list, where)
  assertEqual(type(list), "table", where)
  if #list > 0 then return list end
  local out = {}
  for form, ids in pairs(list) do
    assertEqual(type(form), "string", where .. ": a form key")
    assertTrue(type(ids) == "table" and #ids > 0, where .. "." .. tostring(form) .. " is a non-empty list")
    for _, id in ipairs(ids) do out[#out + 1] = id end
  end
  return out
end

test("range: every class has anchors on both clients, a non-empty ranged role, roles from the three", function()
  -- red under: a class seed with no `anchors`, or an empty ranged role (dynamic-bands plan D1).
  local ROLES = { melee = true, ranged = true, friendly = true }
  for _, client in ipairs({ "retail", "forever" }) do
    for classFile, seed in pairs(NS.SpellSeeds[client]) do
      local where = client .. "." .. classFile .. ".anchors"
      assertEqual(type(seed.anchors), "table", where)
      assertTrue(type(seed.anchors.ranged) == "table" and #seed.anchors.ranged > 0, where .. ".ranged")
      for role, list in pairs(seed.anchors) do
        assertTrue(ROLES[role] == true, where .. ": unknown role " .. tostring(role))
        local ids = anchorIds(list, where .. "." .. role)
        assertTrue(#ids > 0, where .. "." .. role .. " is non-empty")
        for _, id in ipairs(ids) do assertEqual(type(id), "number", where .. "." .. role) end
      end
    end
  end
end)

test("range: the anchors carry the critic's corrections", function()
  local function has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
  end
  local fh = NS.SpellSeeds.forever.HUNTER.anchors
  assertEqual(fh.melee[1], 2974, "Forever hunter melee is Wing Clip (the owner, 2026-11-24)")
  assertFalse(has(fh.melee, 2973), "no Raptor Strike: it answers in range at any distance on Forever")
  assertFalse(has(fh.melee, 6603), "no Attack: it has no range requirement on Forever")
  assertFalse(has(fh.melee, 1495), "no Mongoose Bite: it is reactive")
  assertEqual(fh.ranged[1], 75, "Forever hunter ranged starts at Auto Shot")
  local fd = NS.SpellSeeds.forever.DRUID.anchors.melee
  assertEqual(fd.cat[1], 1082, "Forever cat melee: Claw")
  assertEqual(fd.bear[1], 6807, "Forever bear melee: Maul")
  local dh = NS.SpellSeeds.retail.DEMONHUNTER
  assertTrue(has(dh.anchors.melee, 183752), "Disrupt is a melee anchor (0-5 yd in 12.1.5)")
  assertFalse(has(dh.anchors.ranged, 183752), "and not a ranged one")
  assertFalse(has(dh.ladder, 183752), "nor a ladder rung: the stale 20 yd entry is gone")
  for _, client in ipairs({ "retail", "forever" }) do
    for classFile, seed in pairs(NS.SpellSeeds[client]) do
      assertNil(seed.anchors.long, client .. "." .. classFile .. ": no long (Hunter's Mark) role")
    end
  end
end)

test("range: no ladder seed is a min-range spell (seed validation, 2026-11-25)", function()
  -- red under: Throw 2764 (8-30 on wowf 1.60.1.71091) or Heroic Throw 57755 (8-30 on wow
  -- 12.1.5.70961) back in a ladder. spellRung drops a min-range seed, so it was never a rung
  -- (docs/seed-research/2026-11-25-*/RULINGS.md, ladder-min).
  local function has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
  end
  assertFalse(has(NS.SpellSeeds.retail.WARRIOR.ladder, 57755), "retail warrior: no Heroic Throw rung")
  assertTrue(has(NS.SpellSeeds.retail.WARRIOR.ladder, 355), "retail warrior: Taunt (0-30) stays")
  assertEqual(#NS.SpellSeeds.forever.WARRIOR.ladder, 0, "forever warrior: no ladder spell")
  assertEqual(#NS.SpellSeeds.forever.ROGUE.ladder, 0, "forever rogue: no ladder spell")
  assertTrue(has(NS.SpellSeeds.forever.WARRIOR.chips, 2764), "Throw stays a chip")
end)

test("range: a rebuild builds no ladder; only a Forever walk does, on first need", function()
  -- red under: rebuildNow calling NS.Compat.RangeLadder() eagerly (Retail builds a ladder it never
  -- walks: it has no ladder fallback).
  local real, n = NS.Compat.RangeLadder, 0
  NS.Compat.RangeLadder = function(...) n = n + 1; return real(...) end
  local ok, err = pcall(function() NS.Range.__rebuildNow() end)
  NS.Compat.RangeLadder = real
  if not ok then error(err, 0) end
  assertEqual(n, 0, "the rebuild drops the ladder and leaves the build to the first walk")
end)

-- ── the anchor resolver (dynamic-bands plan D2) ──────────────────────────────────────────────

--- Run `body` with this client's seed for the player's class carrying `spec.anchors`, and the spell
--- client answering from `spec`: `known[id]`, `info[idOrName] = { name, spellID, minRange, maxRange }`,
--- `override[id]` and `form` (GetShapeshiftFormID, or a function answering it). A synchronous rebuild
--- runs before `body` and after the restore, raise or not.
local function withAnchors(spec, body)
  local client, class = NS.Compat.ClientKey(), M.__context.classToken
  local seeds = NS.SpellSeeds[client]
  local realSeed = seeds[class]
  local book, spell = M.C_SpellBook, M.C_Spell
  local real = { book.IsSpellKnown, spell.IsSpellUsable, spell.GetSpellInfo, spell.GetOverrideSpell,
    M.GetShapeshiftFormID }
  local known, info, override = spec.known or {}, spec.info or {}, spec.override or {}
  seeds[class] = { chips = {}, ladder = {}, anchors = spec.anchors }
  book.IsSpellKnown = function(id) return known[id] == true end
  spell.IsSpellUsable = function(id) return not (spec.usable and spec.usable[id] == false), false end
  spell.GetSpellInfo = function(id)
    local r = info[id]
    if r then
      return { name = r[1], iconID = 1, castTime = 0, spellID = r[2], minRange = r[3] or 0, maxRange = r[4] or 40 }
    end
  end
  spell.GetOverrideSpell = function(id) return override[id] or id end
  M.GetShapeshiftFormID = function()
    if type(spec.form) == "function" then return spec.form() end
    return spec.form
  end
  NS.Range.__rebuildNow()
  local ok, err = pcall(body, spec)
  seeds[class] = realSeed
  book.IsSpellKnown, spell.IsSpellUsable, spell.GetSpellInfo, spell.GetOverrideSpell, M.GetShapeshiftFormID =
    real[1], real[2], real[3], real[4], real[5]
  NS.Range.__rebuildNow()
  if not ok then error(err, 0) end
end

test("anchors: a role resolves to its first KNOWN anchor, with the client's name and range", function()
  -- red under: a resolver that takes the list's first entry whatever the spellbook says.
  withAnchors({
    anchors = { ranged = { 116, 133, 30451 } },
    known = { [133] = true, [30451] = true },
    info = { [116] = { "Frostbolt", 116 }, [133] = { "Fireball", 133, 0, 35 }, [30451] = { "Arcane Blast", 30451, 0, 30 },
      Fireball = { "Fireball", 133, 0, 35 } },
  }, function()
    local a = NS.Range.Anchor("ranged")
    assertTrue(type(a) == "table", "the ranged role resolved")
    assertEqual(a.id, 133, "the first known anchor, not the list's first")
    assertEqual(a.name, "Fireball", "the client's own name")
    assertEqual(a.minRange, 0, "the reported min range")
    assertEqual(a.maxRange, 35, "the reported max range")
  end)
end)

test("anchors: a rank-1 seed resolves to the learned rank, a role with nothing known is nil", function()
  -- red under: a resolver asking IsSpellKnown of the stored rank-1 ID (critic 10).
  withAnchors({
    anchors = { ranged = { 3044 }, melee = { 2973 } },
    known = { [14281] = true },
    info = { [3044] = { "Arcane Shot", 3044 }, ["Arcane Shot"] = { "Arcane Shot", 14281, 8, 41 },
      [14281] = { "Arcane Shot", 14281, 8, 41 }, [2973] = { "Raptor Strike", 2973 } },
  }, function()
    local a = NS.Range.Anchor("ranged")
    assertEqual(a and a.id, 14281, "the current rank's ID")
    assertEqual(a and a.maxRange, 41, "and its reported range")
    assertNil(NS.Range.Anchor("melee"), "an unlearned role is unresolved")
    assertNil(NS.Range.Anchor("friendly"), "a role the class has no list for is unresolved")
    assertNil(NS.Range.Anchor("nonsense"), "an unknown role is unresolved")
  end)
end)

test("anchors: druid melee follows the form, and has no anchor out of Cat and Bear", function()
  -- red under: a melee role read as one list (the form map's keys taken as anchors), or a form read
  -- only at rebuild (a shift before the debounce fires would ask the old form's strike).
  local form = 1
  withAnchors({
    anchors = { melee = { cat = { 1082 }, bear = { 6807 } }, ranged = { 5176 } },
    known = { [1082] = true, [6807] = true, [5176] = true },
    info = { [1082] = { "Claw", 1082, 0, 5 }, [6807] = { "Maul", 6807, 0, 5 }, [5176] = { "Wrath", 5176 } },
    form = function() return form end,
  }, function()
    assertEqual(NS.Range.Anchor("melee").id, 1082, "Cat Form: Claw")
    form = 5
    assertEqual(NS.Range.Anchor("melee").id, 6807, "Bear Form: Maul")
    form = 0
    assertNil(NS.Range.Anchor("melee"), "caster form: no melee anchor")
    form = nil
    assertNil(NS.Range.Anchor("melee"), "no form answer: no melee anchor")
    assertEqual(NS.Range.Anchor("ranged").id, 5176, "a role without forms ignores the form")
  end)
end)

test("anchors: a secret form or a secret range is no answer", function()
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    withAnchors({
      anchors = { melee = { cat = { 1082 } }, ranged = { 133 } },
      known = { [1082] = true, [133] = true },
      info = { [1082] = { "Claw", 1082 }, [133] = { "Fireball", 133, 0, T.secret(35) } },
      form = function() return T.secret(1) end,
    }, function()
      assertNil(NS.Range.Anchor("melee"), "a secret form keys nothing")
      local a = NS.Range.Anchor("ranged")
      assertEqual(a and a.id, 133, "a secret range still resolves the anchor")
      assertNil(a.maxRange, "but reports no max range")
    end)
  end)
  restore()
  if not ok then error(err, 0) end
end)

--- Count NS.MSG.ANCHORS_CHANGED for the length of `body`.
local function countAnnouncements(body)
  local n = 0
  local target = NS.NewBusTarget()
  target:RegisterMessage(NS.MSG.ANCHORS_CHANGED, function() n = n + 1 end)
  local ok, err = pcall(body, function() return n end)
  target:UnregisterMessage(NS.MSG.ANCHORS_CHANGED)
  if not ok then error(err, 0) end
  return n
end

test("anchors: a rebuild announces only when a resolved anchor or its range moved", function()
  -- red under: a rebuild that announces on every pass (SPELLS_CHANGED storms repaint every display).
  local spec = {
    anchors = { ranged = { 75, 3044 }, melee = { cat = { 1082 } } },
    known = { [75] = true },
    info = { [75] = { "Auto Shot", 75, 8, 35 }, [3044] = { "Arcane Shot", 3044 }, [1082] = { "Claw", 1082, 0, 5 } },
    form = 0,
  }
  withAnchors(spec, function()
    countAnnouncements(function(n)
      NS.Range.__rebuildNow()
      assertEqual(n(), 0, "nothing moved: no announcement")
      spec.info[75] = { "Auto Shot", 75, 8, 41 }
      NS.Range.__rebuildNow()
      assertEqual(n(), 1, "the range moved (a talent): one announcement")
      NS.Range.__rebuildNow()
      assertEqual(n(), 1, "and none again while it stays")
      spec.known[75] = false
      spec.known[3044] = true
      NS.Range.__rebuildNow()
      assertEqual(n(), 2, "the anchor moved: one more")
      spec.known[1082] = true
      NS.Range.__rebuildNow()
      assertEqual(n(), 3, "a form's anchor learned: one more")
      spec.form = 1
      NS.Range.__rebuildNow()
      assertEqual(n(), 4, "a shift changes the anchor in use: one more")
    end)
  end)
end)

test("anchors: a rebuild announces when a band's own spell list resolves to another spell (review D6)", function()
  -- red under: a change test that reads the class's roles alone (the read-out of an override band goes stale).
  local list = { 3044, 19434 }
  local spec = {
    anchors = { ranged = { 75 } },
    known = { [75] = true, [3044] = true },
    info = { [75] = { "Auto Shot", 75, 8, 41 }, [3044] = { "Arcane Shot", 3044, 8, 41 },
      [19434] = { "Aimed Shot", 19434, 8, 41 } },
  }
  withAnchors(spec, function()
    local a = NS.Range.AnchorFor("ranged", list)
    assertEqual(a and a.id, 3044, "the list's first known spell")
    countAnnouncements(function(n)
      NS.Range.__rebuildNow()
      assertEqual(n(), 0, "nothing moved: no announcement")
      spec.known[3044] = false
      spec.known[19434] = true
      NS.Range.__rebuildNow()
      assertEqual(n(), 1, "the list's spell in use moved: one announcement")
      a = NS.Range.AnchorFor("ranged", list)
      assertEqual(a and a.id, 19434)
      spec.known[19434] = false
      NS.Range.__rebuildNow()
      assertEqual(n(), 2, "nothing in the list known any more: one more")
      assertNil(NS.Range.AnchorFor("ranged", list))
      NS.Range.__rebuildNow()
      assertEqual(n(), 2, "and none again while it stays")
    end)
  end)
end)

-- ── the rebuild triggers (dynamic-bands plan D2) ─────────────────────────────────────────────

--- Count NS.Range.Rebuild calls for the length of `body`.
local function countRebuilds(body)
  local real, n = NS.Range.Rebuild, 0
  NS.Range.Rebuild = function() n = n + 1 end
  local ok, err = pcall(body, function() return n end)
  NS.Range.Rebuild = real
  if not ok then error(err, 0) end
end

local function lifecycleEntry(name)
  for _, pair in ipairs(NS.__lifecycleEvents) do
    if pair[1] == name then return pair end
  end
end

local TRIGGERS = { "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
  "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
  "PLAYER_LEVEL_UP", "UPDATE_SHAPESHIFT_FORM", "PLAYER_EQUIPMENT_CHANGED" }

test("anchors: every trigger event is registered ifValid and asks for one rebuild", function()
  -- red under: a trigger missing from LIFECYCLE_EVENTS, registered bare (a client without it would
  -- record a rejection), or whose handler does not reach NS.Range.Rebuild.
  local spells = lifecycleEntry("SPELLS_CHANGED")
  assertTrue(spells ~= nil, "SPELLS_CHANGED stays a trigger")
  countRebuilds(function(n)
    NS.addon[spells[2]](NS.addon, "SPELLS_CHANGED")
    assertEqual(n(), 1, "SPELLS_CHANGED: one rebuild")
  end)
  for _, name in ipairs(TRIGGERS) do
    local entry = lifecycleEntry(name)
    assertTrue(entry ~= nil, name .. " is in the lifecycle list")
    assertTrue(entry.ifValid == true, name .. " is registered only where the client knows it")
    countRebuilds(function(n)
      NS.addon[entry[2]](NS.addon, name, "player")
      assertEqual(n(), 1, name .. ": one rebuild")
    end)
  end
  assertNil(lifecycleEntry("LEARNED_SPELL_IN_TAB"), "no LEARNED_SPELL_IN_TAB: neither client has it")
end)

test("anchors: CVAR_UPDATE rebuilds for ShowAllSpellRanks only, UNIT_PET for the player's pet only", function()
  local cvar = lifecycleEntry("CVAR_UPDATE")
  assertTrue(cvar ~= nil and cvar.ifValid == true, "CVAR_UPDATE is a trigger, ifValid")
  countRebuilds(function(n)
    NS.addon[cvar[2]](NS.addon, "CVAR_UPDATE", "ShowAllSpellRanks", "1")
    assertEqual(n(), 1, "the rank cvar: one rebuild")
    NS.addon[cvar[2]](NS.addon, "CVAR_UPDATE", "Sound_EnableAllSound", "1")
    assertEqual(n(), 1, "any other cvar: none")
  end)
  local pet = lifecycleEntry("UNIT_PET")
  countRebuilds(function(n)
    NS.addon[pet[2]](NS.addon, "UNIT_PET", "player")
    assertEqual(n(), 1, "the player's pet: one rebuild")
    NS.addon[pet[2]](NS.addon, "UNIT_PET", "party1")
    assertEqual(n(), 1, "another player's pet: none")
  end)
end)

test("anchors: LibRangeCheck's CHECKERS_CHANGED rebuilds while up, and is dropped by the stand-down", function()
  -- red under: no subscription, or one the stand-down leaves live (a stood-down addon hears nothing).
  assertTrue(LRC.callbacks ~= nil, "the addon subscribed to the library's callbacks")
  local ok, err = pcall(function()
    countRebuilds(function(n)
      LRC.callbacks:Fire(LRC.CHECKERS_CHANGED)
      assertEqual(n(), 1, "a checker change: one rebuild")
      NS.addon:UnregisterLifecycleEvents()
      LRC.callbacks:Fire(LRC.CHECKERS_CHANGED)
      assertEqual(n(), 1, "unsubscribed with the events")
      NS.addon:RegisterLifecycleEvents()
      NS.addon:RegisterLifecycleEvents()
      LRC.callbacks:Fire(LRC.CHECKERS_CHANGED)
      assertEqual(n(), 2, "back on the stand-up, once however often it runs")
    end)
  end)
  NS.addon:RegisterLifecycleEvents()
  if not ok then error(err, 0) end
end)

-- ── the rule evaluation (dynamic-bands plan D3) ──────────────────────────────────────────────

local B = NS.BandSets

--- The Forever hunter shape as rule bands; the yards are each band's fallback.
local function hunterBands()
  return {
    { from = 0, to = 5, label = "MELEE", rule = { type = "spell", role = "melee" } },
    { from = 5, to = 8, label = "DEAD", rule = { type = "gap" } },
    { from = 8, to = 35, label = "AUTO", rule = { type = "spell", role = "ranged" } },
    { from = 35, label = "OOR", rule = { type = "beyond" } },
  }
end

local HUNTER = {
  anchors = { melee = { 2973 }, ranged = { 75 } },
  known = { [2973] = true, [75] = true },
  info = { [2973] = { "Raptor Strike", 2973, 0, 5 }, [75] = { "Auto Shot", 75, 8, 41 } },
}

--- A spec for withRules: HUNTER's anchors and spellbook with `extra`'s fields laid over them.
local function hunter(extra)
  local spec = {}
  for k, v in pairs(HUNTER) do spec[k] = v end
  for k, v in pairs(extra or {}) do spec[k] = v end
  return spec
end

--- Run `body(setId, asked)` with a band set of `spec.bands` (the hunter shape when omitted) stored,
--- the player's class `spec.class` (HUNTER when omitted), the anchors and spellbook of `spec`
--- (withAnchors), C_Spell.IsSpellInRange answering `spec.inRange[id]` (a function is called), the
--- interact checks answering `spec.interact[index]`, and LibRangeCheck answering `spec.bracket`.
--- `asked()` counts the range API's calls.
local function withRules(spec, body)
  local savedClass = M.__context.classToken
  local spell = M.C_Spell
  local realInRange, realInteract = spell.IsSpellInRange, M.CheckInteractDistance
  local asked = 0
  M.__context.classToken = spec.class or "HUNTER"
  spec.inRange, spec.interact, spec.bracket = spec.inRange or {}, spec.interact or {}, spec.bracket or {}
  spell.IsSpellInRange = function(id)
    asked = asked + 1
    local v = spec.inRange[id]
    if type(v) == "function" then return v() end
    return v
  end
  M.CheckInteractDistance = function(_, index) return spec.interact[index] end
  local setId = B.Create("Rules", spec.bands or hunterBands())
  local ok, err = pcall(withRange, function() return spec.bracket[1], spec.bracket[2] end, { target = true },
    function()
      withAnchors(spec, function() body(setId, function() return asked end) end)
    end)
  B.Delete(setId)
  spell.IsSpellInRange, M.CheckInteractDistance = realInRange, realInteract
  M.__context.classToken = savedClass
  if not ok then error(err, 0) end
end

--- The set's band index for the bracket `spec.bracket` on the target, at a fresh tick.
local function resolve(setId, spec)
  NS.Range.BeginTick()
  local lo, hi = spec.bracket[1], spec.bracket[2]
  local state = (lo or hi) and "known" or "unknown"
  return B.Resolve(setId, state, lo, hi, "target")
end

test("rules: the owner's case: a 35-40 bracket with Auto Shot in range reads AUTO, not OOR", function()
  -- red under: a Resolve that reads the yards alone (40 is past AUTO's 35 yd edge).
  local spec = hunter({ bracket = { 35, 40 }, inRange = { [2973] = false, [75] = true } })
  withRules(spec, function(setId)
    assertEqual(NS.Range.RoleInRange("ranged", "target"), true, "the ranged anchor answers")
    assertEqual(resolve(setId, spec), 3, "AUTO")
    spec.inRange[75] = false
    assertEqual(resolve(setId, spec), 4, "out of every anchor's range: OOR")
    spec.inRange[2973] = true
    assertEqual(resolve(setId, spec), 4,
      "Raptor Strike's true at 35-40 is the Forever quirk (owner, 2026-11-19: MELEE at 45-100): voided, OOR")
    spec.bracket = { 0, 5 }
    assertEqual(resolve(setId, spec), 1, "in melee, close by: MELEE")
  end)
end)

test("rules: the dead zone holds only when a shorter check confirms the target is near", function()
  -- red under: a gap read from the two anchors alone (a target past 41 yd would read DEAD).
  local spec = hunter({ bracket = { 5, 8 }, inRange = { [2973] = false, [75] = false } })
  withRules(spec, function(setId)
    assertEqual(resolve(setId, spec), 2, "the bracket's max at the ranged anchor's min: DEAD")
    spec.bracket = {}
    spec.interact[3] = true
    assertEqual(resolve(setId, spec), 2, "no bracket, the interact distance says near: DEAD")
    spec.interact[3] = false
    assertEqual(resolve(setId, spec), "unknown",
      "no bracket, nothing confirms near: Auto Shot's false may be its 8 yd min, so unknown, never OOR")
    spec.bracket = { 5, 10 }
    assertEqual(resolve(setId, spec), 2,
      "5-10, under Auto Shot's 41 yd reach: its false can only mean too close, DEAD (the owner, 2026-11-24)")
    spec.bracket = { 30, 40 }
    assertEqual(resolve(setId, spec), 4, "a bracket reaching into beyond's yards: OOR")
    spec.bracket = { 5, 10 }
    spec.interact[3], spec.inRange[75] = true, true
    assertEqual(resolve(setId, spec), 3, "the ranged anchor in range is never the dead zone")
  end)
end)

test("rules: every spell out of range reads OOR, short of beyond's yards too (owner, 2026-11-19)", function()
  -- red under: a beyond that gives way to the yards (a Forever caster's 30-yd spell left 30-40 unknown).
  local bands = {
    { from = 0, to = 8, label = "CLOSE" },
    { from = 8, to = 40, label = "CAST", rule = { type = "spell", role = "ranged" } },
    { from = 40, label = "OOR", rule = { type = "beyond" } },
  }
  local spec = { bands = bands, class = "MAGE", anchors = { ranged = { 133 } }, known = { [133] = true },
    info = { [133] = { "Fireball", 133, 0, 35 } }, bracket = { 30, 35 }, inRange = { [133] = false } }
  withRules(spec, function(setId)
    assertEqual(resolve(setId, spec), 3, "Fireball out of range at 30-35: OOR, not unknown")
    spec.inRange[133] = true
    assertEqual(resolve(setId, spec), 2, "Fireball in range: CAST")
    spec.bracket = { 0, 5 }
    assertEqual(resolve(setId, spec), 1, "a nearer yard band still wins in band order")
  end)
end)

test("rules: no melee spell (a Forever paladin) still reads OOR once the ranged spell is out", function()
  -- red under: a beyond that needs every spell band's answer (the unlearned melee band left 30-40 unknown).
  local bands = {
    { from = 0, to = 5, label = "MELEE", rule = { type = "spell", role = "melee" } },
    { from = 5, to = 20, label = "CLOSE" }, { from = 20, to = 30, label = "MID" },
    { from = 30, to = 40, label = "LONG", rule = { type = "spell", role = "ranged" } },
    { from = 40, label = "OOR", rule = { type = "beyond" } },
  }
  local spec = { bands = bands, class = "PALADIN", anchors = { ranged = { 879 } }, known = { [879] = true },
    info = { [879] = { "Exorcism", 879, 0, 30 } }, bracket = { 30, 35 }, inRange = { [879] = false } }
  withRules(spec, function(setId)
    assertNil(NS.Range.RoleInRange("melee", "target"), "no melee anchor: no answer")
    assertEqual(resolve(setId, spec), 5, "the farthest spell band out, the melee band silent: OOR")
    spec.bracket = { 0, 5 }
    spec.inRange[879] = true
    assertEqual(resolve(setId, spec), 1, "close in: MELEE by its yards")
  end)
end)

test("rules: an unlearned anchor falls back to its band's yards, and unknown stays unknown", function()
  -- red under: an unresolved role read as out of range (a fresh level 1 would read OOR everywhere).
  local spec = hunter({ known = { [2973] = true }, bracket = { 20, 25 }, inRange = { [2973] = false, [75] = true } })
  withRules(spec, function(setId)
    assertNil(NS.Range.RoleInRange("ranged", "target"), "no ranged anchor: no answer")
    assertEqual(resolve(setId, spec), 3, "AUTO by its fallback yards")
    spec.bracket = { 35, 40 }
    assertEqual(resolve(setId, spec), 4, "OOR by its fallback yards")
    spec.bracket = {}
    assertEqual(resolve(setId, spec), "unknown", "nothing to decide: unknown, never OOR")
  end)
end)

test("rules: a nil or secret answer is no answer: the yards decide, or unknown", function()
  local restore = T.installSecretValue()
  local ok, err = pcall(function()
    local spec = hunter({ bracket = { 20, 25 }, inRange = { [2973] = false } })
    withRules(spec, function(setId)
      assertEqual(resolve(setId, spec), 3, "a nil answer: AUTO by its yards")
      spec.inRange[75] = function() return T.secret(false) end
      assertNil(NS.Range.RoleInRange("ranged", "target"), "a secret is no answer")
      assertEqual(resolve(setId, spec), 3, "a secret: AUTO by its yards")
      spec.bracket = {}
      assertEqual(resolve(setId, spec), "unknown", "and with no bracket, unknown, never OOR")
    end)
  end)
  restore()
  if not ok then error(err, 0) end
end)

test("rules: yards that contradict a band's own anchor never paint that band", function()
  -- red under: a fallback that paints AUTO while Auto Shot says the target is out of its range.
  local spec = hunter({ known = { [75] = true }, bracket = { 20, 25 }, inRange = { [75] = false } })
  withRules(spec, function(setId)
    assertEqual(resolve(setId, spec), 4, "the yards say AUTO, the farthest anchor says no: the spell wins, OOR")
  end)
end)

test("rules: a melee true is voided, for every class, when the bracket puts the unit 8 yd or more away", function()
  -- red under: no guard (a melee spell can answer true from anywhere), or a hunter exempt from it
  -- (the owner, 2026-11-19: a Forever hunter read MELEE at 41-45 and 45-100).
  local spec = hunter({ class = "WARRIOR", bracket = { 25, 30 }, inRange = { [2973] = true, [75] = true } })
  withRules(spec, function(setId)
    assertNil(NS.Range.RoleInRange("melee", "target"), "a warrior's melee true at 25 yd is voided")
    assertEqual(resolve(setId, spec), 3, "and the next band's anchor decides")
    spec.bracket, spec.inRange[75] = { 0, 5 }, false
    NS.Range.BeginTick()
    assertEqual(NS.Range.RoleInRange("melee", "target"), true, "close by, the true stands")
  end)
  spec = hunter({ bracket = { 45, 100 }, inRange = { [2973] = true } })
  withRules(spec, function()
    assertNil(NS.Range.RoleInRange("melee", "target"), "a hunter's melee true at 45-100 is voided too")
    spec.bracket = { 8, 10 }
    NS.Range.BeginTick()
    assertNil(NS.Range.RoleInRange("melee", "target"), "and at 8-10")
  end)
end)

test("rules: a melee true is voided while a min-range ranged anchor says true, with no bracket", function()
  -- red under: a guard that reads the bracket alone (no bracket: Raptor Strike's quirk read MELEE).
  local spec = hunter({ bracket = {}, inRange = { [2973] = true, [75] = true } })
  withRules(spec, function()
    assertNil(NS.Range.RoleInRange("melee", "target"), "Auto Shot in range means past 8 yd: no melee")
    spec.inRange[75] = false
    NS.Range.BeginTick()
    assertEqual(NS.Range.RoleInRange("melee", "target"), true, "Auto Shot out (too close): the true stands")
  end)
end)

test("rules: a druid's melee band follows the form, and reads its yards out of Cat and Bear", function()
  local form = 1
  local spec = {
    class = "DRUID",
    anchors = { melee = { cat = { 1082 }, bear = { 6807 } }, ranged = { 5176 } },
    known = { [1082] = true, [6807] = true, [5176] = true },
    info = { [1082] = { "Claw", 1082, 0, 5 }, [6807] = { "Maul", 6807, 0, 5 }, [5176] = { "Wrath", 5176, 0, 30 } },
    form = function() return form end,
    bracket = { 0, 5 },
    inRange = { [1082] = true, [6807] = false, [5176] = true },
    bands = {
      { from = 0, to = 5, label = "MELEE", rule = { type = "spell", role = "melee" } },
      { from = 5, to = 30, label = "CAST", rule = { type = "spell", role = "ranged" } },
      { from = 30, label = "OOR", rule = { type = "beyond" } },
    },
  }
  withRules(spec, function(setId)
    assertEqual(resolve(setId, spec), 1, "Cat Form: Claw says in range")
    form = 5
    assertEqual(resolve(setId, spec), 2, "Bear Form: Maul says no, Wrath says yes")
    form = 0
    assertNil(NS.Range.RoleInRange("melee", "target"), "caster form: no melee anchor")
    assertEqual(resolve(setId, spec), 1, "and the melee band reads its yards")
  end)
end)

test("rules: a friendly spell band reads its anchor's answer on a friendly unit (review D6)", function()
  -- red under: a friendly role read through the hostile anchors, or never asked.
  local spec = {
    class = "PRIEST",
    anchors = { friendly = { 2061 } },
    known = { [2061] = true },
    info = { [2061] = { "Flash Heal", 2061, 0, 40 } },
    bracket = { 20, 30 },
    inRange = { [2061] = true },
    bands = {
      { from = 0, to = 30, label = "NEAR" },
      { from = 30, to = 40, label = "FAR", rule = { type = "spell", role = "friendly" } },
      { from = 40, label = "OOR", rule = { type = "beyond" } },
    },
  }
  withRules(spec, function(setId)
    assertEqual(NS.Range.RoleInRange("friendly", "target"), true, "the friendly anchor answers")
    assertEqual(resolve(setId, spec), 1, "NEAR by its yards, first in band order")
    spec.bracket = { 35, 45 }
    assertEqual(resolve(setId, spec), 2, "FAR on the heal's true, past FAR's yards")
    spec.inRange[2061] = false
    assertEqual(resolve(setId, spec), 3, "out of the heal's range: OOR")
  end)
end)

test("rules: a ranged anchor with no min range has no dead zone, so a gap band never holds by rule (review D6)", function()
  -- red under: a Near that confirms near on the bracket alone (every Retail gap band would read DEAD).
  local spec = hunter({
    info = { [2973] = { "Raptor Strike", 2973, 0, 5 }, [75] = { "Auto Shot", 75, 0, 40 } },
    bracket = { 5, 8 }, inRange = { [2973] = false, [75] = false }, interact = { [3] = true },
  })
  withRules(spec, function(setId)
    assertEqual(NS.Range.Near("target", "known", 8), false, "no min range: nothing is near")
    spec.bracket = {}
    assertEqual(resolve(setId, spec), 4, "the interact distance says near, yet no gap holds: beyond")
  end)
end)

test("rules: one range call per spell per unit per tick, shared by the bands and the chips", function()
  -- red under: a band read that asks the client again for a spell a chip asked this tick.
  local spec = hunter({ bracket = { 20, 25 }, inRange = { [2973] = false, [75] = true } })
  withRules(spec, function(setId, asked)
    NS.Range.BeginTick()
    local before = asked()
    assertEqual(NS.Range.InSpellRange(75, "target"), true, "the chip's answer")
    assertEqual(B.Resolve(setId, "known", 20, 25, "target"), 3)
    assertEqual(B.Resolve(setId, "known", 20, 25, "target"), 3)
    assertEqual(asked() - before, 2, "Auto Shot once, Raptor Strike once")
    NS.Range.BeginTick()
    NS.Range.RoleInRange("ranged", "target")
    assertEqual(asked() - before, 3, "a new tick asks again")
    local yards = B.Create("Yards only", { { from = 0, to = 5, label = "NEAR" }, { from = 5, label = "FAR" } })
    NS.Range.BeginTick()
    B.Resolve(yards, "known", 20, 25, "target")
    B.Delete(yards)
    assertEqual(asked() - before, 3, "a set with no rule asks no spell")
  end)
end)

test("rules: a spell band's own list overrides the class's anchors for its role", function()
  local spec = hunter({
    known = { [2973] = true, [75] = true, [3044] = true },
    info = { [2973] = { "Raptor Strike", 2973, 0, 5 }, [75] = { "Auto Shot", 75, 8, 41 },
      [3044] = { "Arcane Shot", 3044, 8, 41 } },
    bracket = { 20, 25 }, inRange = { [2973] = false, [75] = false, [3044] = true },
  })
  spec.bands = hunterBands()
  spec.bands[3].rule.spells = { 3044 }
  withRules(spec, function(setId)
    assertEqual(NS.Range.RoleInRange("ranged", "target", { 3044 }), true, "the override's answer")
    assertEqual(resolve(setId, spec), 3, "AUTO on Arcane Shot, whatever Auto Shot says")
  end)
end)

test("rules: a malformed rule reads as a yard band", function()
  local spec = hunter({ bracket = { 20, 25 }, inRange = { [2973] = false, [75] = false } })
  spec.bands = hunterBands()
  spec.bands[3].rule = { type = "spell", role = 42 }
  spec.bands[4].rule = "beyond"
  withRules(spec, function(setId)
    assertEqual(resolve(setId, spec), 3, "AUTO by its yards")
  end)
end)

test("anchors: AnchorFor names the anchor a band asks, its own list's or the role's (the editor's read-out)", function()
  -- red under: no AnchorFor (the Band sets page's read-out names what RoleInRange would ask).
  withAnchors({
    anchors = { ranged = { 75 } },
    known = { [75] = true, [3044] = true },
    info = { [75] = { "Auto Shot", 75, 8, 41 }, [3044] = { "Arcane Shot", 3044, 8, 41 },
      [2973] = { "Raptor Strike", 2973 } },
  }, function()
    local a = NS.Range.AnchorFor("ranged")
    assertEqual(a and a.id, 75, "no list: the role's anchor")
    a = NS.Range.AnchorFor("ranged", { 2973, 3044 })
    assertEqual(a and a.id, 3044, "a list: its first known spell")
    assertEqual(a and a.name, "Arcane Shot")
    assertNil(NS.Range.AnchorFor("ranged", { 2973 }), "a list with nothing known is unresolved")
    assertNil(NS.Range.AnchorFor("melee"), "and so is a role with nothing known")
  end)
end)

-- ---------------------------------------------------------------------------
-- The cross-validation round (2026-11-19): longest usable anchor, melee reach, min range, yard bands
-- ---------------------------------------------------------------------------

test("anchors: a talented later seed reaching farther is asked first (Shadow Reach Mind Blast over Smite)", function()
  -- red under: the first known seed alone (a Forever shadow priest read OOR from 30 with Mind Blast at 36).
  withAnchors({
    anchors = { ranged = { 585, 8092 } },
    known = { [585] = true, [8092] = true },
    info = { [585] = { "Smite", 585, 0, 30 }, [8092] = { "Mind Blast", 8092, 0, 36 } },
  }, function()
    assertEqual(NS.Range.Anchor("ranged").id, 8092, "the 36 yd Mind Blast")
  end)
end)

test("rules: an unusable anchor passes to the next (Charge in combat, Throw answers)", function()
  -- red under: the first known anchor alone (Charge unusable left the ranged role silent: LONG by yards).
  local bands = {
    { from = 0, to = 5, label = "MELEE", rule = { type = "spell", role = "melee" } },
    { from = 5, to = 30, label = "MID" },
    { from = 30, to = 40, label = "LONG", rule = { type = "spell", role = "ranged" } },
    { from = 40, label = "OOR", rule = { type = "beyond" } },
  }
  local spec = { bands = bands, class = "WARRIOR", anchors = { melee = { 78 }, ranged = { 100, 2764 } },
    known = { [78] = true, [100] = true, [2764] = true },
    info = { [78] = { "Heroic Strike", 78, 0, 5 }, [100] = { "Charge", 100, 8, 30 }, [2764] = { "Throw", 2764, 8, 30 } },
    usable = { [100] = false }, bracket = { 30, 35 }, inRange = { [78] = false, [100] = true, [2764] = false } }
  withRules(spec, function(setId)
    local v, a = NS.Range.RoleInRange("ranged", "target")
    assertEqual(v, false, "Throw's answer")
    assertEqual(a and a.id, 2764, "Throw answered, not the unusable Charge")
    assertEqual(resolve(setId, spec), 4, "every usable spell out: OOR")
  end)
end)

test("anchors: a melee seed reported past 8 yd is no melee anchor (Improved Disrupt)", function()
  withAnchors({
    anchors = { melee = { 183752, 263642 } },
    known = { [183752] = true, [263642] = true },
    info = { [183752] = { "Disrupt", 183752, 0, 10 }, [263642] = { "Fracture", 263642, 0, 5 } },
  }, function()
    assertEqual(NS.Range.Anchor("melee").id, 263642, "Disrupt at 10 yd is skipped: Fracture")
  end)
end)

test("rules: a melee true is voided while a buff's override reaches past 8 yd (Aspect of the Eagle)", function()
  local spec = hunter({ bracket = { 0, 5 }, inRange = { [2973] = true, [75] = false },
    override = { [2973] = 265189 } })
  spec.known = { [2973] = true, [75] = true }
  spec.info = { [2973] = { "Raptor Strike", 2973, 0, 5 }, [75] = { "Auto Shot", 75, 8, 41 },
    [265189] = { "Raptor Strike", 265189, 0, 40 } }
  withRules(spec, function()
    assertNil(NS.Range.RoleInRange("melee", "target"), "the 40 yd override: no melee true")
  end)
end)

test("rules: a min-range anchor's false inside its min is not OOR (a 5-8 bracket, no gap band)", function()
  -- red under: a beyond trusting any false (a Forever rogue's Throw read OOR at 6 yd).
  local bands = {
    { from = 0, to = 5, label = "MELEE", rule = { type = "spell", role = "melee" } },
    { from = 5, to = 30, label = "RANGED", rule = { type = "spell", role = "ranged" } },
    { from = 30, label = "OOR", rule = { type = "beyond" } },
  }
  local spec = { bands = bands, class = "ROGUE", anchors = { melee = { 1752 }, ranged = { 2764 } },
    known = { [1752] = true, [2764] = true },
    info = { [1752] = { "Sinister Strike", 1752, 0, 5 }, [2764] = { "Throw", 2764, 8, 30 } },
    bracket = { 5, 8 }, inRange = { [1752] = false, [2764] = false } }
  withRules(spec, function(setId)
    assertEqual(resolve(setId, spec), "unknown", "inside Throw's 8 yd min: never OOR")
    spec.bracket = { 30, 35 }
    assertEqual(resolve(setId, spec), 3, "past it: OOR")
  end)
end)

test("rules: every spell out of range beats a yard band's yards (owner, 2026-11-19: Evoker healer NEAR)", function()
  -- red under: band order kept for yard bands (a 25-30 yd friend read NEAR with Living Flame out).
  local bands = {
    { from = 0, to = 30, label = "NEAR" },
    { from = 30, to = 40, label = "FAR", rule = { type = "spell", role = "friendly" } },
    { from = 40, label = "OOR", rule = { type = "beyond" } },
  }
  local spec = { bands = bands, class = "EVOKER", anchors = { friendly = { 361469 } }, known = { [361469] = true },
    info = { [361469] = { "Living Flame", 361469, 0, 25 } }, bracket = { 25, 30 }, inRange = { [361469] = false } }
  withRules(spec, function(setId)
    assertEqual(resolve(setId, spec), 3, "Living Flame out at 25-30: OOR, not NEAR")
    spec.inRange[361469] = true
    assertEqual(resolve(setId, spec), 1, "in range: the yards' NEAR")
  end)
end)
