local _, NS = ...
-- modules/Ticker.lua — the ONE range ticker for the whole addon (design spec 5.1), and the sole
-- sender of NS.MSG.RANGE_UPDATED.
--
--   NS.Ticker.Watch(unit)      count one more consumer of `unit` (a container, a nameplate instance)
--   NS.Ticker.Unwatch(unit)    count one fewer; the last one drops the unit
--   NS.Ticker.Refresh(unit?)   re-read `unit` now (every watched unit when nil), outside the cadence
--   NS.Ticker.Changed(unit)    a different unit now sits behind `unit` (a retarget, a reaction change):
--                              re-read it and send its triple even when it did not move
--   NS.Ticker.OnSteady(fn)     fn(unit) after every read of a watched unit whose triple did not
--                              move, so no RANGE_UPDATED went out (the renderer re-asks its spell
--                              chips there: a spell's edge can fall inside one bracket)
--   NS.Ticker.Removed(unit)    the unit is gone now: send "none" without asking the client, which
--                              still resolves a plate's token while NAME_PLATE_UNIT_REMOVED dispatches
--
-- Each tick starts a new Range memo and reads every watched unit once, however many consumers
-- watch it, so the cost scales with units and never with containers. RANGE_UPDATED goes out with
-- (unit, state, minYd, maxYd) only when that unit's triple changed since the last send.
--
-- THE RATE ADAPTS. 10 Hz out of combat, 20 Hz in it: one C_Timer.NewTicker, canceled and re-armed
-- at the new interval on the combat edge (core/RangeMaster.lua's OnCombatChanged calls SetCombat).
-- It STOPS when no watched unit exists (nothing to measure) and starts again on the event that
-- brings one back (core/RangeMaster.lua routes the unit events here as Refresh). Mouseover has no
-- "cleared" event, so while the ticker runs every tick re-reads it through UnitExists, which is
-- how a mouseover that left turns into "none".
--
-- THE STAND-DOWN (slash-commands-§7) cancels the ticker and forgets what was last sent; the watch
-- counts stay, because they belong to the consumers. The stand-up re-reads every watched unit, so
-- each consumer hears its unit's current range again.

NS.Ticker = NS.Ticker or {}
local Ticker = NS.Ticker

local Perf = NS.Perf

local RATE_IDLE, RATE_COMBAT = 0.1, 0.05

local watched = {}    -- [unit] = consumer count
local last = {}       -- [unit] = { state, minYd, maxYd } as last sent
local pass = {}       -- the units of the pass in flight, reused: a RANGE_UPDATED receiver may
                      -- Watch a new unit mid-pass, and a pairs() walk must not see a key added
local steady = {}     -- the OnSteady listeners, in registration order
local handle, interval
local inCombat = false

-- ---------------------------------------------------------------------------
-- One unit, one pass
-- ---------------------------------------------------------------------------

--- Send RANGE_UPDATED for `unit` if this triple differs from the last one sent; otherwise tell the
--- OnSteady listeners the unit was read and did not move. Answers whether the unit exists.
local function publish(unit, state, lo, hi)
    local l = last[unit]
    if not l then
        l = {}
        last[unit] = l
    end
    if l[1] ~= state or l[2] ~= lo or l[3] ~= hi then
        l[1], l[2], l[3] = state, lo, hi
        NS.bus:SendMessage(NS.MSG.RANGE_UPDATED, unit, state, lo, hi)
    else
        for i = 1, #steady do steady[i](unit) end
    end
    return state ~= "none"
end

--- Read `unit` and publish its triple.
local function evaluate(unit)
    return publish(unit, NS.Range.Get(unit))
end

--- Read every watched unit once, over a snapshot of the watch list.
local function evaluateAll()
    local n = 0
    for unit in pairs(watched) do
        n = n + 1
        pass[n] = unit
    end
    for i = 1, n do
        local unit = pass[i]
        pass[i] = nil
        if watched[unit] then evaluate(unit) end
    end
end

local function anyLive()
    for unit in pairs(watched) do
        local l = last[unit]
        if l and l[1] ~= "none" then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- The ticker
-- ---------------------------------------------------------------------------

local function stop()
    if handle then handle:Cancel() end
    handle, interval = nil, nil
end

local reconcile

--- The tick: a fresh memo, every watched unit once, then start-or-stop.
local function tick()
    local t0 = Perf.on and debugprofilestop()
    NS.Range.BeginTick()
    NS.Range.SetPerfParent("ticker.tick")
    evaluateAll()
    NS.Range.SetPerfParent(false)
    reconcile()
    if t0 then Perf.Note("ticker.tick", debugprofilestop() - t0) end
end

local function wantedRate()
    return (inCombat or InCombatLockdown()) and RATE_COMBAT or RATE_IDLE
end

local function start()
    local rate = wantedRate()
    if handle and interval == rate then return end
    stop()
    interval = rate
    handle = C_Timer.NewTicker(rate, tick)
end

--- Run while a watched unit exists and the addon stands up; stop otherwise.
reconcile = function()
    if anyLive() and not NS.IsStoodDown() then start() else stop() end
end

-- ---------------------------------------------------------------------------
-- The public surface
-- ---------------------------------------------------------------------------

--- Re-read `unit` now (or every watched unit when nil), then start or stop the ticker. An
--- unwatched unit is ignored.
function Ticker.Refresh(unit)
    if unit ~= nil and not watched[unit] then return end
    NS.Range.BeginTick()
    if unit ~= nil then evaluate(unit) else evaluateAll() end
    reconcile()
end

--- A different unit now sits behind the token `unit` (PLAYER_TARGET_CHANGED and its kin, a plate
--- token handed to a new plate, UNIT_FACTION): forget the last send, so the re-read goes out even
--- when the bracket did not move and every consumer draws the new unit. An unwatched unit is ignored.
function Ticker.Changed(unit)
    if not watched[unit] then return end
    last[unit] = nil
    Ticker.Refresh(unit)
end

--- Call fn(unit) after each read of a watched unit whose triple did not move.
function Ticker.OnSteady(fn)
    if type(fn) == "function" then steady[#steady + 1] = fn end
end

--- `unit` is gone as of now (a nameplate being removed): its consumers hear "none" at once, and
--- the ticker stops if nothing live is left. An unwatched unit is ignored.
function Ticker.Removed(unit)
    if not watched[unit] or NS.IsStoodDown() then return end
    publish(unit, "none")
    reconcile()
end

function Ticker.Watch(unit)
    if type(unit) ~= "string" then return end
    watched[unit] = (watched[unit] or 0) + 1
    -- Forget the last send, so the new consumer hears the unit's current range at once; the ones
    -- already watching hear the same triple again, which a receiver that repaints only on change
    -- absorbs.
    last[unit] = nil
    if not NS.IsStoodDown() then Ticker.Refresh(unit) end
end

function Ticker.Unwatch(unit)
    local n = watched[unit]
    if not n then return end
    if n > 1 then
        watched[unit] = n - 1
        return
    end
    watched[unit], last[unit] = nil, nil
    reconcile()
end

function Ticker.IsWatched(unit) return watched[unit] ~= nil end

--- Whether the ticker is armed, and at what interval (nil when stopped).
function Ticker.IsRunning() return handle ~= nil end
function Ticker.Interval() return interval end

--- The combat edge: re-arm at the new rate if running.
function Ticker.SetCombat(on)
    inCombat = on and true or false
    if handle then start() end
end

--- The stand-down: nothing armed survives it, and nothing is remembered as sent.
function Ticker.StandDown()
    stop()
    NS.Range.CancelRebuild()
    for unit in pairs(last) do last[unit] = nil end
end

--- The stand-up: every watched unit is read again and announced.
function Ticker.StandUp()
    inCombat = InCombatLockdown() and true or false
    -- Spells learned while stood down: the ladder is taken again before the first read.
    NS.Range.RunOwedRebuild()
    Ticker.Refresh()
end

-- Suite seam: tests/test_ticker.lua drives one tick through the live handle's own callback.
function Ticker.__handle() return handle end
