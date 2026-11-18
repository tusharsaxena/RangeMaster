local addonName, NS = ...
-- core/LifecycleSetup.lua — the LibKa0s-Lifecycle-1.0 seam: ONE latch, two named holds, and the
-- addon's single way down and single way back up (slash-commands-§7).
--
-- WHY A LATCH AND NOT A BOOLEAN. There are two independent reasons for this addon to be inert: the
-- player unticked "Enable Range Master" (the `disabled` hold), and the perf harness is measuring its
-- suspended arm (the `perf` hold, taken by core/PerfSetup.lua's instance on this same latch). A
-- resume that wrote `false` would stand the addon back up under a player who switched it off; holds
-- cannot fail that way.
--
-- DISABLED IS TOTAL, NOT A DRAW GATE. StandDown UNREGISTERS every event and bus message this addon
-- owns and ends both preview modes; it never gates a handler on a flag. StandUp rebuilds from the
-- settings as they are NOW (performance-§6). The edges themselves are the library's `[Lifecycle]`
-- lines, written through the descriptor's `debug`; this file writes no second line for either.
--
-- LOAD-BEARING POSITION: before core/PerfSetup.lua, which takes NS.lifecycle as its `lifecycle`
-- descriptor field and raises without one; after core/Bus.lua, whose stand-down record it drives.

local lib = LibStub and LibStub("LibKa0s-Lifecycle-1.0", true)

--- Run NS[module][fn]() for each { module, fn } in `steps` whose module and function are loaded.
local function runSteps(steps)
    for _, step in ipairs(steps) do
        local mod = NS[step[1]]
        local f = mod and mod[step[2]]
        if f then f() end
    end
end

-- The feature modules' stand-down, in order (each optional, so a partial load still goes down).
local DOWN_STEPS = {
    -- A frame pick in progress ends with no callback: its overlay's OnUpdate goes.
    { "FramePicker", "Stop" },
    -- The range containers: every instance parked and hidden, its watch dropped, before the ticker.
    { "Container", "StandDown" },
    -- The anchors' waits and timers: the plate registry and its re-checks, the frame waits, the follow.
    { "Plates", "StandDown" },
    { "Anchors", "StandDown" },
    -- The range ticker and the pending spell rebuild: no timer survives a stand-down.
    { "Ticker", "StandDown" },
    -- The container registry's coalescing timer; an owed apply stays owed for the stand-up.
    { "CM", "StandDown" },
}

local UP_STEPS = {
    -- Last, once every receiver is back: each watched unit is read and announced again.
    { "Ticker", "StandUp" },
    -- The nameplates shown now, which no NAME_PLATE_UNIT_ADDED will announce again.
    { "Plates", "StandUp" },
    -- One apply of every container as the settings are now (CONTAINERS_CHANGED on the next frame).
    { "CM", "StandUp" },
}

--- EMPTY -> NON-EMPTY: the addon stops. Every registration it owns goes, not gated.
local function StandDown()
    -- The two preview modes are session state that draws; a stood-down addon draws nothing.
    if NS.EndModes then NS.EndModes("stood down") end
    if NS.HideSkinPicker then NS.HideSkinPicker() end
    local addon = NS.addon
    if addon and addon.UnregisterLifecycleEvents then addon:UnregisterLifecycleEvents() end
    runSteps(DOWN_STEPS)
    if NS.BusStandDown then NS.BusStandDown() end
end

--- NON-EMPTY -> EMPTY: the addon comes back, rebuilt from the current settings.
local function StandUp()
    if NS.BusStandUp then NS.BusStandUp() end
    local addon = NS.addon
    if addon and addon.RegisterLifecycleEvents then addon:RegisterLifecycleEvents() end
    runSteps(UP_STEPS)
end

NS.StandDown, NS.StandUp = StandDown, StandUp

if not lib then
    -- Degrade, never error: a local latch with the library's surface, so the show ladder, the perf
    -- stub and the suites read the same seam on every build. Edge-triggered like the library: a
    -- Reevaluate that agrees with the current state runs no callback.
    local held, down = {}, false
    local function reevaluate()
        local any = next(held) ~= nil
        if any == down then return false end
        down = any
        if any then StandDown() else StandUp() end
        return true
    end
    NS.lifecycle = {
        name       = addonName,
        Hold       = function(_, key) held[key] = true;  return reevaluate() end,
        Release    = function(_, key) held[key] = nil;   return reevaluate() end,
        Set        = function(self, key, on)
            if on then return self:Hold(key) end
            return self:Release(key)
        end,
        IsHeld     = function(_, key) return held[key] == true end,
        IsDown     = function() return down end,
        Holds      = function()
            local out = {}
            for k in pairs(held) do out[#out + 1] = k end
            table.sort(out)
            return out
        end,
        Reevaluate = function() return reevaluate() end,
        PrintHolds = function(self)
            local list = self:Holds()
            NS.Print(addonName .. ":", #list > 0 and table.concat(list, ", ") or "no holds")
            return true
        end,
    }
else
    NS.lifecycle = lib:New({
        name      = addonName,
        standDown = StandDown,
        standUp   = StandUp,
        print     = function(line) NS.Print(line) end,
        -- The gated sink (debug-logging-§4): the library writes each edge's `[Lifecycle]` line.
        debug     = function(tag, message) NS.Debug(tag, "%s", message) end,
    })
end

NS.HOLD_DISABLED = lib and lib.HOLD_DISABLED or "disabled"
NS.HOLD_PERF = lib and lib.HOLD_PERF or "perf"

--- Is the addon inert right now, for ANY reason (the player's switch or a perf capture).
function NS.IsStoodDown()
    return NS.lifecycle:IsDown()
end

--- Is the addon inert because the PLAYER switched it off. Only this hold may print the refusal that
--- names `/rm enable`: a perf capture is not something `/rm enable` fixes.
function NS.IsDisabled()
    return NS.lifecycle:IsHeld(NS.HOLD_DISABLED)
end

--- Is the addon enabled, from the stored path? EXPLICITLY false only: before core/Database.lua
--- builds NS.db the read answers the shipped default. settings/Slash.lua hands this same function to
--- the dispatcher as its `isEnabled`, so the gate and the stand-down read one predicate.
function NS.EnabledStored()
    return NS.GetSetting("enabled") ~= false
end

--- Take or release the `disabled` hold from the stored path. Every surface that can flip it (the
--- Master controls checkbox, `/rm enable`, `/rm disable`, `/rm set enabled`, a profile switch and the
--- load-time read) lands here, so there is one branch rather than six.
function NS.SyncEnabledHold()
    NS.lifecycle:Set(NS.HOLD_DISABLED, not NS.EnabledStored())
end
