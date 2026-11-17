local addonName, NS = ...
-- core/PerfSetup.lua — the LibKa0s-Perf-1.0 seam (performance).
--
-- The probe, its record schema and the clickable step panel are the library's and shared across every
-- Ka0s addon. What is ours: which hot paths get buckets, where the output goes, and the latch the
-- suspended arm takes its `perf` hold on (core/LifecycleSetup.lua's NS.lifecycle, the same latch the
-- player's switch holds, so there is one teardown path and not two).
--
-- LOAD-BEARING POSITION: built at FILE LOAD, after core/LifecycleSetup.lua (the descriptor's
-- `lifecycle`, without which Perf raises at New) and before any file taking `local Perf = NS.Perf`
-- as a load-time upvalue (core/RangeMaster.lua).

local lib = LibStub and LibStub("LibKa0s-Perf-1.0", true)
if not lib then
    -- A missing vendored lib must degrade, not error at load: the addon's own function is unaffected
    -- by the absence of a diagnostics harness. The stub therefore has to cover EVERY member the
    -- addon calls, not just the bracket idiom (`on`/`Note`) and the show-decision ladder
    -- (`suspended`) — `/rm perf` is registered unconditionally, so OnCommand has to answer too, and
    -- an honest "it is not installed" beats a Lua error in exactly the install this branch exists
    -- for.
    NS.Perf = {
        on        = false,
        suspended = false,
        Note      = function() end,
        OnCommand = function()
            return { NS.L["%s, so performance measurement is unavailable."]:format(NS.LIBKA0S_MISSING) }
        end,
    }
    return
end

NS.Perf = lib:New({
    name    = addonName,
    -- THE FOLDER NAME, a different question from the one above even though this addon
    -- answers both with the same string. `name` seeds the panel's frame globals;
    -- `addonName` is what LibKa0s-Core builds a texture path from, so the panel's own
    -- close control draws this collection's `close` mark rather than a multiplication
    -- sign. PerfPanel minor 4 reads `d.addonName or d.name`, so this addon would fall
    -- through to the right answer by luck; it is passed EXPLICITLY because a host where
    -- the two strings diverge would hand the library a path into nowhere, which draws
    -- nothing and raises nothing.
    addonName = addonName,
    title   = "Range Master",
    slash   = "/rm",
    version = NS.version,
    sv      = "RangeMasterPerfDB",

    -- Ordered for the report, and the nesting is DECLARED rather than left as prose (performance-§3).
    buckets = {
        -- core/RangeMaster.lua's combat edge (PLAYER_REGEN_DISABLED / _ENABLED): ends the preview
        -- modes and re-arms the range ticker at the edge's rate.
        { key = "combatEdge" },
        -- modules/Ticker.lua's tick: a fresh memo and one read of every watched unit, 10 or 20 times
        -- a second while a watched unit exists. The addon's steady-state cost.
        { key = "ticker.tick" },
        -- modules/Range.lua's query on a memo miss: LibRangeCheck's GetRange (and on Forever the
        -- ladder walk). Not declared `within` ticker.tick: an event's forced refresh runs it
        -- outside any tick, so the containment is not a fact about every call.
        { key = "range.get" },
    },

    -- THE LATCH, AND THE ONLY ROUTE THIS PROBE HAS TO MAKING THE ADDON INERT (Perf 12): the suspended
    -- arm takes the `perf` hold on core/LifecycleSetup.lua's latch, whose StandDown and StandUp the
    -- `disabled` hold reaches too (anti-pattern #85). `P.suspended` is a VIEW of the latch, so a Resume
    -- releases the `perf` hold and nothing else: an addon disabled mid-capture stays down.
    lifecycle = NS.lifecycle,

    -- Perf output is not gated on the debug flag: a run is explicit user action.
    log = function(line)
        if NS.DebugLog and NS.DebugLog.Add then
            NS.DebugLog:Add("Perf", line)
        else
            NS.Print(line)
        end
    end,

    print = function(line) NS.Print(line) end,

    showLog = function()
        if NS.DebugLog and NS.DebugLog.Show and not NS.DebugLog:IsShown() then
            NS.DebugLog:Show()
        end
    end,

    -- NO `decorate`: the library's panel draws its own close control from `addonName`, so it matches
    -- the debug console with nothing wired here (performance-§4, anti-pattern #65).
})
