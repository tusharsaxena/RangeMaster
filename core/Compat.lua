local _, NS = ...
-- core/Compat.lua — root of the compat family, the sole home of every version-variant client call
-- (compat). Family: core/Compat.lua (this file only).
--
-- Today it routes two things from LibKa0s-Compat-1.0: the client questions (IsForever, IsRetail,
-- ClientKey, ForClient; clients-§3) and the secret-value guards (IsSecret, CanAccess, IsSafeKey;
-- events-frames-taint-§8). No other file of this addon reads a WOW_PROJECT_* global or decides the
-- client from an interface number. The range ladder and the range API wrappers arrive here in a
-- later change; docs/ARCHITECTURE.md → Documentation map records when docs/compat-layer.md is owed.
NS.Compat = NS.Compat or {}
local Compat = NS.Compat

local CompatLib = LibStub and LibStub("LibKa0s-Compat-1.0", true)

-- ---------------------------------------------------------------------------
-- The client (clients-§3)
-- ---------------------------------------------------------------------------
-- Without the library the stand-in answers Retail, so a partial install keeps every feature that
-- serves Retail instead of gating them all off as an unknown client. A Compat-only absence can only
-- come from a partial copy (library-stack-§7); the whole-payload absence is announced once by
-- core/CoreSetup.lua.

local CLIENT_TOKENS = { retail = true, forever = true, both = true }

local function unknownClient(token)
    error('ForClient: unknown client "' .. tostring(token) .. '"', 3)
end

--- The stand-in ForClient: the library's rule over a client that is always Retail. An unknown token
--- raises before any match, as the library's does.
local function forClientRetail(clients)
    if clients == nil or clients == "both" then return true end
    if type(clients) ~= "table" then unknownClient(clients) end
    local hit = false
    for _, token in ipairs(clients) do
        if not CLIENT_TOKENS[token] then unknownClient(token) end
        hit = hit or token == "both" or token == "retail"
    end
    return hit
end

--- Whether this is a WoW Forever client.
--- @return boolean
function Compat.IsForever()
    if CompatLib then return CompatLib.IsForever() end
    return false
end

--- Whether this is a Retail client (the mainline project and not Forever).
--- @return boolean
function Compat.IsRetail()
    if CompatLib then return CompatLib.IsRetail() end
    return true
end

--- The client's key: "retail", "forever", or nil when the library knows neither.
--- @return string|nil
function Compat.ClientKey()
    if CompatLib then return CompatLib.ClientKey() end
    return "retail"
end

--- Whether a `clients` declaration (nil, "both", or an array of "retail" / "forever" / "both")
--- includes this client; nil serves both (clients-§4). An unknown token raises on every client.
--- @param clients table|string|nil
--- @return boolean
function Compat.ForClient(clients)
    if CompatLib then return CompatLib.ForClient(clients) end
    return forClientRetail(clients)
end

-- ---------------------------------------------------------------------------
-- The secret-value guards (events-frames-taint-§8)
-- ---------------------------------------------------------------------------
-- The library, or the same one-rung body. DELIBERATE DUPLICATION, as LibKa0s
-- docs/api/Compat/version-4-docs.md, "Degradation" requires of a guard: "the library is absent" is
-- not "the client has no secrets system", and a stub answering IsSecret -> false on a 12.x client
-- would send a secret into a comparison on exactly the path the stub exists to survive.

Compat.IsSecret = CompatLib and CompatLib.IsSecret or function(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

Compat.CanAccess = CompatLib and CompatLib.CanAccess or function(v)
    if canaccessvalue then return canaccessvalue(v) and true or false end
    return not (issecretvalue ~= nil and issecretvalue(v))
end

Compat.IsSafeKey = CompatLib and CompatLib.IsSafeKey or function(v)
    if issecretvalue ~= nil and issecretvalue(v) then return false end
    return v ~= nil
end
