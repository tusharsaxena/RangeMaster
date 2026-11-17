local _, NS = ...
-- modules/Range.lua — the range engine (design spec 5.1): one question, "how far is this unit",
-- answered as an honest bracket or as unknown, never as a guess.
--
--   NS.Range.Get(unit)                 -> state, minYd, maxYd
--       state "none"     the unit does not exist (minYd, maxYd nil)
--             "unknown"  it exists and nothing could bound it: no checker answered, the estimator
--                        raised, or an answer was a secret value (minYd, maxYd nil)
--             "known"    minYd is a number (0 at the closest rung), maxYd a number or nil for
--                        open-ended ("40+")
--   NS.Range.InSpellRange(id, unit)    -> true | false | nil (nil: not known, no unit, no answer)
--   NS.Range.BeginTick()               clear the per-tick memo
--   NS.Range.Rebuild()                 rebuild the ladder and the known-spell cache, 0.5 s after
--                                      the last call (SPELLS_CHANGED comes in bursts)
--
-- THE ESTIMATOR is LibRangeCheck-3.0's GetRange(unit, true), called inside pcall with both answers
-- passed through NS.Compat.IsSecret before anything compares them. It already restricts a friendly
-- unit in combat to its spell-only checker lists. On WoW Forever, when it answers nothing for a
-- unit that exists, the Compat ladder is walked instead (NS.Compat.RangeLadder: items at the three
-- reliable yards, the two interact distances, known seed spells); in combat on a unit the player
-- cannot attack that walk asks the spell rungs only, because the client refuses item and interact
-- checks there.
--
-- THE MEMO is keyed by unit token (nameplateN included), never by GUID: a GUID can be a secret on
-- 12.x and a secret is not a legal table key. N containers on one unit cost one query per tick.
-- Each token's entry is one reused table, so a tick allocates nothing once every token is seen.

NS.Range = NS.Range or {}
local Range = NS.Range
local Compat = NS.Compat

-- The perf probe, a load-time upvalue (performance-§2).
local Perf = NS.Perf

-- Resolved once at file load (library-stack-§4): the TOC's lib block loads it long before this file.
-- Absent (a partial install, the degraded harness), every existing unit reads unknown.
local LRC = LibStub and LibStub("LibRangeCheck-3.0", true)

local REBUILD_DELAY = 0.5

local tickId = 0
local memo = {}            -- [unit] = { tick, state, minYd, maxYd }
local ladder               -- NS.Compat.RangeLadder(), built on first use and on Rebuild
local known = {}           -- [spellID] = boolean, wiped on Rebuild
local rebuildTimer

-- ---------------------------------------------------------------------------
-- The Forever ladder walk
-- ---------------------------------------------------------------------------

local CHECK = {
    item     = function(e, unit) return Compat.ItemInRange(e.id, unit) end,
    interact = function(e, unit) return Compat.InteractInRange(e.id, unit) end,
    spell    = function(e, unit) return Compat.SpellInRange(e.id, unit) end,
}

local function currentLadder()
    if not ladder then ladder = Compat.RangeLadder() end
    return ladder
end

--- Item and interact checks are refused on a unit the player cannot attack while in combat; a
--- secret or missing "can attack" answer is read as cannot, the side that never asks a blocked
--- check.
local function spellsOnly(unit)
    return InCombatLockdown() and Compat.CanAttack(unit) ~= true
end

--- Walk the sorted ladder from its shortest rung. The first rung answering "in range" is the max;
--- every rung of a shorter yard that answered "out" raises the min. A yard with no answer bounds
--- nothing. Answers minYd, maxYd (maxYd nil past the last answering rung), or nil when no rung
--- answered at all.
local function walkLadder(unit)
    local restricted = spellsOnly(unit)
    local lo, curYd, curOut, answered = 0, nil, false, false
    for _, e in ipairs(currentLadder()) do
        if not restricted or e.kind == "spell" then
            if e.yd ~= curYd then
                if curOut then lo = curYd end
                curYd, curOut = e.yd, false
            end
            local r = CHECK[e.kind](e, unit)
            if r == true then return lo, e.yd end
            if r == false then curOut, answered = true, true end
        end
    end
    if not answered then return nil end
    if curOut then lo = curYd end
    return lo, nil
end

-- ---------------------------------------------------------------------------
-- The query
-- ---------------------------------------------------------------------------

--- LibRangeCheck's answer, guarded: minYd, maxYd, or nil, nil for none; false for "unusable"
--- (raised or secret), which no fallback may paper over.
local function estimator(unit)
    if not LRC then return nil, nil end
    local ok, lo, hi = pcall(LRC.GetRange, LRC, unit, true)
    if not ok or Compat.IsSecret(lo) or Compat.IsSecret(hi) then return false end
    return lo, hi
end

local function bracket(lo, hi)
    if type(lo) ~= "number" and type(hi) ~= "number" then return "unknown" end
    return "known", type(lo) == "number" and lo or 0, type(hi) == "number" and hi or nil
end

local function query(unit)
    if not UnitExists(unit) then return "none" end
    local lo, hi = estimator(unit)
    if lo == false then return "unknown" end
    if lo == nil and hi == nil and Compat.IsForever() then lo, hi = walkLadder(unit) end
    return bracket(lo, hi)
end

-- ---------------------------------------------------------------------------
-- The public reads
-- ---------------------------------------------------------------------------

--- The unit's range bracket, memoized for the current tick. See the file header for the states.
--- @param unit string a unit token
--- @return string state, number|nil minYd, number|nil maxYd
function Range.Get(unit)
    local m = memo[unit]
    if m and m[1] == tickId then return m[2], m[3], m[4] end
    local t0 = Perf.on and debugprofilestop()
    local state, lo, hi = query(unit)
    if t0 then Perf.Note("range.get", debugprofilestop() - t0) end
    if not m then
        m = {}
        memo[unit] = m
    end
    m[1], m[2], m[3], m[4] = tickId, state, lo, hi
    return state, lo, hi
end

--- Whether `unit` is within the spell's range: true, false, or nil when the player does not know
--- the spell, the unit does not exist, or the client gave no usable answer.
--- @return boolean|nil
function Range.InSpellRange(spellID, unit)
    if type(spellID) ~= "number" or not UnitExists(unit) then return nil end
    local k = known[spellID]
    if k == nil then
        k = Compat.IsSpellKnown(spellID)
        known[spellID] = k
    end
    if not k then return nil end
    return Compat.SpellInRange(spellID, unit)
end

--- Start a new tick: every memo entry from the last one goes stale. Nothing is freed.
function Range.BeginTick()
    tickId = tickId + 1
end

--- The rebuild itself: the ladder and the known-spell cache are taken again from the client.
local function rebuildNow()
    rebuildTimer = nil
    ladder = Compat.RangeLadder()
    for id in pairs(known) do known[id] = nil end
    Range.BeginTick()
end
-- Suite seam: tests/test_range.lua rebuilds synchronously around a swapped spell API.
Range.__rebuildNow = rebuildNow

--- Rebuild the ladder and the known-spell cache, REBUILD_DELAY after the last call.
function Range.Rebuild()
    if rebuildTimer then rebuildTimer:Cancel() end
    rebuildTimer = C_Timer.NewTimer(REBUILD_DELAY, rebuildNow)
end

--- Cancel a pending rebuild (the stand-down: no timer survives it, slash-commands-§7).
function Range.CancelRebuild()
    if rebuildTimer then rebuildTimer:Cancel() end
    rebuildTimer = nil
end
