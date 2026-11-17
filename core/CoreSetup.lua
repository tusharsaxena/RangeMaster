local addonName, NS = ...
-- core/CoreSetup.lua — the LibKa0s-Core-1.0 seam: the secret-safe stringifier, the class-color
-- resolver, the shared window skin, the close-button factory and the [RM]-prefixed chat printer.
--
-- None of that is this addon's code. What is ours is which tag the lines carry and what happens when
-- the library is not there. LOAD-BEARING POSITION: after core/Namespace.lua (NS.PREFIX) and before
-- everything that prints or takes NS.Print as a load-time upvalue.
NS.Util = NS.Util or {}
local Util = NS.Util

-- The one cause clause every seam uses to explain the same absence, so a degraded install says the
-- same thing about WHY and a different thing about WHAT in each place. Set here, first of the seams.
NS.LIBKA0S_MISSING = NS.L["The LibKa0s library is missing from this installation of Range Master (expected in libs/LibKa0s)"]

local lib = LibStub and LibStub("LibKa0s-Core-1.0", true)

if not lib then
    -- Degrade, never error. Settings files do `local print = NS.Print` at load, so a nil printer
    -- would take the settings UI with it and a no-op one would make /rm answer nothing. These are
    -- short working fallbacks, and "not installed" is said ONCE, on the first line printed.
    NS.SECRET = "<secret>"

    local function probeConcat(v) return table.concat({ v }) end
    function NS.IsConcatSafe(v)
        return (pcall(probeConcat, v))
    end

    function NS.SafeToString(v)
        if v == nil then return "nil" end
        if type(v) == "boolean" then return tostring(v) end
        if NS.IsConcatSafe(v) then return tostring(v) end
        return NS.SECRET
    end

    -- A unit's class color, or nil when the class does not resolve (an NPC, no such unit).
    function NS.ClassColor(unit)
        local ok, _, token = pcall(UnitClass, unit or "player")
        local c = (ok and type(token) == "string" and type(RAID_CLASS_COLORS) == "table")
            and RAID_CLASS_COLORS[token] or nil
        if type(c) ~= "table" or type(c.r) ~= "number" then return nil end
        return c.r, c.g, c.b
    end

    -- The class-color resolver (options-ui-§17): the stored alpha survives the mode, an
    -- unresolvable class falls through to the stored swatch, and the swatch is read under both.
    function NS.ResolveColor(stored, on, unit)
        if type(stored) ~= "table" then stored = {} end
        local r, g, b, a = stored.r or 1, stored.g or 1, stored.b or 1, stored.a or 1
        if not on then return r, g, b, a end
        local cr, cg, cb = NS.ClassColor(unit)
        if cr == nil then return r, g, b, a end
        return cr, cg, cb, a
    end

    -- The chrome degrades to NOTHING rather than to a hand-copied backdrop: Core.SKIN's values ARE the
    -- contract (standalone-windows). SKIN is an empty table so a window may index it unguarded, and
    -- MakeCloseButton answers nil exactly as Core's own does where CreateFrame is unavailable.
    NS.SKIN            = {}
    NS.ApplySkin       = function() end
    NS.MakeCloseButton = function() return nil end

    local announced = false
    function NS.Print(...)
        local parts = { NS.PREFIX }
        for i = 1, select("#", ...) do parts[i + 1] = NS.SafeToString((select(i, ...))) end
        if not DEFAULT_CHAT_FRAME then return end
        if not announced then
            announced = true
            DEFAULT_CHAT_FRAME:AddMessage(NS.SafeToString(NS.PREFIX) .. " " ..
                NS.L["%s; running on reduced built-in fallbacks."]:format(NS.LIBKA0S_MISSING))
        end
        DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " "))
    end
    Util.print = NS.Print

    -- The formatting half: every argument is stringified secret-safe BEFORE format sees it, and a
    -- format the stringified parts cannot satisfy still lands, as the parts printed plainly.
    function NS.Printf(fmt, ...)
        local n = select("#", ...)
        local safeFmt = NS.SafeToString(fmt)
        if n == 0 then return NS.Print(safeFmt) end
        local parts = {}
        for i = 1, n do parts[i] = NS.SafeToString((select(i, ...))) end
        local ok, out = pcall(string.format, safeFmt, unpack(parts, 1, n))
        if ok then NS.Print(out) else NS.Print(safeFmt, unpack(parts, 1, n)) end
    end
    Util.printf = NS.Printf

    -- The event-registration helpers as ONE-RUNG bodies (events-frames-taint-§1): a plain pcall and
    -- no IsEventValid front gate; a refused name is appended to `rejected` once.
    local function noteRejected(rejected, event)
        if type(rejected) ~= "table" then return end
        for i = 1, #rejected do
            if rejected[i] == event then return end
        end
        rejected[#rejected + 1] = event
    end

    function NS.SafeRegisterEvent(target, event, handler, rejected)
        local ok = pcall(target.RegisterEvent, target, event, handler)
        if not ok then noteRejected(rejected, event) end
        return ok
    end

    function NS.SafeRegisterUnitEvent(frame, event, rejected, u1, u2)
        local ok = pcall(frame.RegisterUnitEvent, frame, event, u1, u2)
        if not ok then noteRejected(rejected, event) end
        return ok
    end

    function NS.SafeRegisterEvents(target, events, handler, rejected)
        local n = 0
        for _, event in ipairs(type(events) == "table" and events or {}) do
            if NS.SafeRegisterEvent(target, event, handler, rejected) then n = n + 1 end
        end
        return n
    end

    return
end

NS.IsConcatSafe = lib.IsConcatSafe
NS.SafeToString = lib.SafeToString
NS.SECRET = lib.SECRET

-- The one way this addon registers a game event (events-frames-taint-§1): an unknown name costs only
-- itself and lands in NS.State.rejectedEvents, which every caller passes as `rejected`.
NS.SafeRegisterEvent     = lib.SafeRegisterEvent
NS.SafeRegisterUnitEvent = lib.SafeRegisterUnitEvent
NS.SafeRegisterEvents    = lib.SafeRegisterEvents

-- ONE class-color resolver for the collection (options-ui-§17), and the class lookup on its own.
NS.ResolveColor = lib.ResolveColor
NS.ClassColor = lib.ClassColor

-- The shared window edge (standalone-windows). ApplySkin is wrapped to hand the skin owner, the
-- folder name (skinning-§1), so a caller paints through this addon's skin.
NS.SKIN      = lib.SKIN
NS.ApplySkin = function(frame, keys)
    return lib.ApplySkin(frame, keys, addonName)
end

-- WRAPPED, TO SAY WHO IS ASKING — and this wrapper is a MUST (standalone-windows, anti-patterns
-- #64/#65). Core draws the catalog's `close` mark only when told which addon FOLDER to build the path
-- from, and a vendored library cannot work that out. EVERY close control goes through here:
--
--   grep -rn 'MakeCloseButton(' --include='*.lua' | grep -v '/libs/'
--
-- must return this definition and calls to NS.MakeCloseButton, and nothing else.
NS.MakeCloseButton = function(parent, onClick)
    return lib.MakeCloseButton(parent, onClick, addonName)
end

-- The prefix goes in as a FUNCTION: the printer is built once at load, and the function form keeps a
-- later change to NS.PREFIX from being frozen out.
local printer = lib:New({ prefix = function() return NS.PREFIX end })

-- NS.Print and NS.Util.print MUST be the SAME function object (architecture-§2, anti-pattern #36).
-- AceAddon:NewAddon(NS, …, "AceConsole-3.0") stamps AceConsole's :Print over NS.Print, and
-- core/RangeMaster.lua reclaims it by repointing NS.Print at NS.Util.print. The same for Printf.
NS.Print = printer.Print
Util.print = NS.Print
NS.Printf = printer.Format
Util.printf = NS.Printf
