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
  local realLadder, built = NS.Compat.RangeLadder, 0
  NS.Compat.RangeLadder = function(...) built = built + 1; return realLadder(...) end
  local ok, err = pcall(function()
    NS.Range.Rebuild()
    NS.Range.Rebuild()
    NS.Range.Rebuild()
    assertEqual(#handles, 3, "each call re-arms the debounce")
    assertEqual(handles[3].delay, 0.5, "half a second after the last call")
    assertTrue(stopped(handles[1]) and stopped(handles[2]), "the earlier timers are canceled")
    assertFalse(stopped(handles[3]), "the last one is armed")
    assertEqual(built, 0, "nothing rebuilt before the timer fires")
    handles[3].fn()
    assertEqual(built, 1, "one rebuild")
  end)
  M.C_Timer.NewTimer = realNew
  NS.Compat.RangeLadder = realLadder
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
  local realLadder, built = NS.Compat.RangeLadder, 0
  NS.Compat.RangeLadder = function(...) built = built + 1; return realLadder(...) end
  local ok, err = pcall(function()
    NS.SetByPath("enabled", false)
    NS.Range.Rebuild()
    assertEqual(#handles, 0, "a stood-down addon arms no rebuild timer")
    assertEqual(built, 0, "and rebuilds nothing")
    NS.SetByPath("enabled", true)
    assertEqual(built, 1, "the stand-up runs the owed rebuild, once")
    assertEqual(#handles, 0, "synchronously, with no timer")
    NS.SetByPath("enabled", false)
    NS.SetByPath("enabled", true)
    assertEqual(built, 1, "nothing owed, nothing rebuilt")
  end)
  M.C_Timer.NewTimer = realNew
  NS.Compat.RangeLadder = realLadder
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
