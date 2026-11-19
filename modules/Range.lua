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
--   NS.Range.Anchor(role)              -> { id, name, minRange, maxRange } | nil: the anchor spell a
--                                         band rule of `role` ("melee", "ranged", "friendly") asks,
--                                         as the last rebuild resolved it (see THE ANCHORS below)
--   NS.Range.BeginTick()               clear the per-tick memo
--   NS.Range.SetPerfParent(key|false)  the bucket the reads that follow run inside (performance-§3):
--                                      modules/Ticker.lua names "ticker.tick" for its tick, false after
--   NS.Range.Rebuild()                 rebuild the ladder, the known-spell cache and the anchors,
--                                      0.5 s after the last call (SPELLS_CHANGED comes in bursts);
--                                      while stood down it arms nothing and the rebuild is owed
--   NS.Range.RunOwedRebuild()          the stand-up's step (modules/Ticker.lua): an owed rebuild, now
--   NS.Range.SetSource(src|nil)        the preview modes' fake range (modules/Preview.lua is its one
--                                      caller): while set, every read answers src.Get(unit) and
--                                      src.InSpell(spellID, unit) instead of the client
--   NS.Range.HasSource()               whether a fake range is set
--
-- THE ESTIMATOR is LibRangeCheck-3.0's GetRange(unit, true, nil, 0), called inside pcall with both
-- answers passed through NS.Compat.IsSecret before anything compares them. The 0 is maxCacheAge: the
-- library otherwise keeps an answer 0.1 s, keyed by the unit TOKEN whenever the GUID is a secret, so a
-- target swap or a recycled nameplateN inside that window would read back the previous unit's bracket,
-- and a 20 Hz ticker would see fresh data only every other tick. This file's memo is the only cache. It already restricts a friendly
-- unit in combat to its spell-only checker lists. On WoW Forever, when it answers nothing for a
-- unit that exists, the Compat ladder is walked instead (NS.Compat.RangeLadder: items at the three
-- reliable yards, the two interact distances, known seed spells); in combat on a unit the player
-- cannot attack that walk asks the spell rungs only, because the client refuses item and interact
-- checks there.
--
-- A SPELL is trusted only while it is known AND usable (research lesson 9): a spell unusable in the
-- current form or stance can report "in range" from anywhere. Knowing is cached until the next
-- Rebuild; usability is asked on every check, because a shapeshift fires no SPELLS_CHANGED.
--
-- THE MEMO is keyed by unit token (nameplateN included), never by GUID: a GUID can be a secret on
-- 12.x and a secret is not a legal table key. N containers on one unit cost one query per tick.
-- Each token's entry is one reused table, so a tick allocates nothing once every token is seen.
--
-- THE ANCHORS (dynamic-bands plan D2). A band rule names a ROLE; the class's ordered anchor lists
-- (defaults/SpellSeeds.lua) name the spells. Each rebuild takes, per role, the first seed the player
-- knows once NS.Compat.CurrentSpellID has resolved it to the learned rank and a known override (a
-- Forever seed is rank 1, and the rank-1 ID may not read as known once a higher rank is learned),
-- with the name and the min and max range the client reports for that ID, a secret read as none.
-- A role the class has no list for, or none of whose seeds is known, is unresolved (nil), and its
-- band falls back to its yards. A druid's melee list is keyed by form: every form's anchor is
-- resolved at rebuild and the one in use is picked on each read from the current form, so a shift
-- never asks the old form's strike while the debounce runs. A rebuild sends ANCHORS_CHANGED only
-- when an anchor, its reported range or the form's pick moved.
--
-- THE FAKE SOURCE. Test mode and Sim mode draw through the real render path (design spec 5.5): the
-- ticker, the memo, RANGE_UPDATED and the renderer are the live ones, and only the answer comes from
-- a table the preview owns. It answers for any token, so a container with no unit draws too. Setting
-- or clearing it starts a new tick, so no memo entry from the other source is read back.

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
local ladder               -- NS.Compat.RangeLadder(), built on the first Forever walk; Rebuild drops it
local rebuilds = 0         -- how many rebuilds ran (a suite seam's count)
local known = {}           -- [spellID] = boolean, wiped on Rebuild
local rebuildTimer
local rebuildOwed = false  -- a rebuild asked for or canceled while stood down: the stand-up runs it
local perfParent = false   -- the observed parent handed to Perf.Note("range.get")
local source               -- the preview's fake range, or nil (live)
local anchors = {}         -- [role] = anchor, or { forms = { [formKey] = anchor } }; nil unresolved
local anchorsResolved = false
local anchorSig = ""       -- the last resolve's signature: a rebuild announces only a move

-- ---------------------------------------------------------------------------
-- The Forever ladder walk
-- ---------------------------------------------------------------------------

local CHECK = {
    item     = function(e, unit) return Compat.ItemInRange(e.id, unit) end,
    interact = function(e, unit) return Compat.InteractInRange(e.id, unit) end,
    -- An unusable spell rung answers nothing: its "in range" is not evidence (research lesson 9).
    spell    = function(e, unit)
        if not Compat.IsSpellUsable(e.id) then return nil end
        return Compat.SpellInRange(e.id, unit)
    end,
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
    local ok, lo, hi = pcall(LRC.GetRange, LRC, unit, true, nil, 0)
    if not ok or Compat.IsSecret(lo) or Compat.IsSecret(hi) then return false end
    return lo, hi
end

local function bracket(lo, hi)
    if type(lo) ~= "number" and type(hi) ~= "number" then return "unknown" end
    return "known", type(lo) == "number" and lo or 0, type(hi) == "number" and hi or nil
end

local function query(unit)
    if source then return source.Get(unit) end
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
    if t0 then Perf.Note("range.get", debugprofilestop() - t0, perfParent) end
    if not m then
        m = {}
        memo[unit] = m
    end
    m[1], m[2], m[3], m[4] = tickId, state, lo, hi
    return state, lo, hi
end

--- Whether `unit` is within the spell's range: true, false, or nil when the player does not know
--- the spell, cannot use it right now, the unit does not exist, or the client gave no usable answer.
--- @return boolean|nil
function Range.InSpellRange(spellID, unit)
    if type(spellID) ~= "number" then return nil end
    if source then return source.InSpell(spellID, unit) end
    if not UnitExists(unit) then return nil end
    local k = known[spellID]
    if k == nil then
        k = Compat.IsSpellKnown(spellID)
        known[spellID] = k
    end
    if not k or not Compat.IsSpellUsable(spellID) then return nil end
    return Compat.SpellInRange(spellID, unit)
end

-- ---------------------------------------------------------------------------
-- The anchors (dynamic-bands plan D2)
-- ---------------------------------------------------------------------------

local ROLES = { "melee", "ranged", "friendly" }

-- GetShapeshiftFormID's answer to the key a form-keyed anchor list uses (defaults/SpellSeeds.lua,
-- druid melee): 1 Cat Form, 5 Bear Form, 8 Dire Bear Form where a client tells the two apart.
local FORM_KEY = { [1] = "cat", [5] = "bear", [8] = "bear" }

local function plainRange(v)
    if Compat.IsSecret(v) or type(v) ~= "number" then return nil end
    return v
end

--- The first seed in `list` the player knows, as its current rank and override, or nil.
local function firstKnown(list)
    for _, seed in ipairs(list) do
        local id = Compat.CurrentSpellID(seed)
        if id and Compat.IsSpellKnown(id) then
            local name, _, _, minRange, maxRange = Compat.GetSpellInfo(id)
            if Compat.IsSecret(name) or type(name) ~= "string" then name = nil end
            return { id = id, name = name, minRange = plainRange(minRange), maxRange = plainRange(maxRange) }
        end
    end
    return nil
end

--- One role's resolution: an anchor, a form map of anchors, or nil.
local function resolveRole(list)
    if type(list) ~= "table" then return nil end
    if #list > 0 then return firstKnown(list) end
    local forms = {}
    for key, ids in pairs(list) do
        if type(key) == "string" and type(ids) == "table" then forms[key] = firstKnown(ids) end
    end
    return { forms = forms }
end

--- The anchor of a resolved slot in use right now: a form map picks by the current form.
local function inUse(slot)
    if slot and slot.forms then
        local key = FORM_KEY[Compat.ShapeshiftFormID() or 0]
        return key and slot.forms[key] or nil
    end
    return slot
end

local function sigOf(a)
    if not a then return "-" end
    return tostring(a.id) .. ":" .. tostring(a.minRange) .. ":" .. tostring(a.maxRange)
end

--- Everything a band reads of the anchors, as one string: each role's anchor (each form's, for a
--- form map) and the one in use.
local function signature()
    local parts = {}
    for _, role in ipairs(ROLES) do
        local slot = anchors[role]
        if slot and slot.forms then
            local keys = {}
            for key in pairs(slot.forms) do keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do parts[#parts + 1] = role .. "." .. key .. "=" .. sigOf(slot.forms[key]) end
        end
        parts[#parts + 1] = role .. "=" .. sigOf(inUse(slot))
    end
    return table.concat(parts, ";")
end

--- Resolve every role from this client's seed for the player's class. Answers whether anything a
--- band reads moved since the last resolve.
local function resolveAnchors()
    local byClass = NS.SpellSeeds and NS.SpellSeeds[Compat.ClientKey() or "retail"]
    local seed = byClass and byClass[Compat.PlayerClass() or ""]
    local lists = seed and seed.anchors or {}
    for _, role in ipairs(ROLES) do anchors[role] = resolveRole(lists[role]) end
    anchorsResolved = true
    local sig = signature()
    local moved = sig ~= anchorSig
    anchorSig = sig
    return moved
end

--- The anchor spell a band rule of `role` asks, as the last rebuild resolved it:
--- `{ id, name, minRange, maxRange }` (name and the ranges nil when the client will not say), or nil
--- when the role is unresolved. A druid's melee anchor follows the current form. Resolved on the
--- first read when no rebuild has run yet. The table is the resolver's own: read it, never write it.
--- @param role string "melee" | "ranged" | "friendly"
--- @return table|nil
function Range.Anchor(role)
    if not anchorsResolved then resolveAnchors() end
    return inUse(anchors[role])
end

--- Start a new tick: every memo entry from the last one goes stale. Nothing is freed.
function Range.BeginTick()
    tickId = tickId + 1
end

--- Set (or, with nil, clear) the fake range every read answers from. A new tick starts at once.
--- @param src table|nil  { Get = fn(unit) -> state, minYd, maxYd, InSpell = fn(spellID, unit) -> bool|nil }
function Range.SetSource(src)
    source = src
    tickId = tickId + 1
end

function Range.HasSource()
    return source ~= nil
end

--- Name the perf bucket the reads that follow run inside, or false for none: what range.get records
--- as its OBSERVED parent (performance-§3), so a capture shows it nested in ticker.tick on a tick and
--- at top level on an event's forced refresh, rather than a reader summing the two.
--- @param key string|false
function Range.SetPerfParent(key)
    perfParent = key or false
end

--- The bucket the reads now running sit inside, or false: what a reader nested the same way (the
--- renderer's container.render, modules/Container.lua) records as its observed parent.
--- @return string|false
function Range.PerfParent()
    return perfParent
end

--- The rebuild itself: the known-spell cache is taken again from the client, and the ladder is
--- dropped, to be built again on the first Forever walk (currentLadder). Retail never walks one, so
--- it never builds one. The anchors are resolved again, and ANCHORS_CHANGED goes out when they moved.
local function rebuildNow()
    rebuildTimer = nil
    rebuildOwed = false
    ladder = nil
    for id in pairs(known) do known[id] = nil end
    local moved = resolveAnchors()
    Range.BeginTick()
    rebuilds = rebuilds + 1
    if moved and NS.bus then NS.bus:SendMessage(NS.MSG.ANCHORS_CHANGED) end
end
-- Suite seams: tests/test_range.lua rebuilds synchronously around a swapped spell API, and counts
-- the rebuilds that ran (the ladder build is lazy, so it is no witness of one).
Range.__rebuildNow = rebuildNow
function Range.__rebuildCount() return rebuilds end

--- Rebuild the ladder and the known-spell cache, REBUILD_DELAY after the last call. A stood-down
--- addon arms nothing (slash-commands-§7): the rebuild is owed, and the stand-up runs it.
function Range.Rebuild()
    if NS.IsStoodDown and NS.IsStoodDown() then
        Range.CancelRebuild()
        rebuildOwed = true
        return
    end
    if rebuildTimer then rebuildTimer:Cancel() end
    rebuildTimer = C_Timer.NewTimer(REBUILD_DELAY, rebuildNow)
end

--- Cancel a pending rebuild (the stand-down: no timer survives it, slash-commands-§7). A rebuild
--- that was pending stays owed.
function Range.CancelRebuild()
    if rebuildTimer then
        rebuildTimer:Cancel()
        rebuildOwed = true
    end
    rebuildTimer = nil
end

--- Run an owed rebuild now (the stand-up, modules/Ticker.lua): synchronous, no timer.
function Range.RunOwedRebuild()
    if rebuildOwed then rebuildNow() end
end
