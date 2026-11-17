local _, NS = ...
-- core/Data.lua — the settings read seam (NS.GetSetting), the minimap row's inverted storage and the
-- cached LibSharedMedia reference.
--
-- There is no setter here: every write goes through NS.SetByPath (settings/Schema.lua,
-- architecture-§5).

-- AceDB instance, set by core/Database.lua at init.
NS.db = nil

-- Cached LibSharedMedia reference.
local LSM

--- LibSharedMedia-3.0, or nil when it is absent (a soft optional; every reader has a fallback).
function NS.GetLSM()
    if LSM then return LSM end
    if LibStub then
        LSM = LibStub("LibSharedMedia-3.0", true)
    end
    return LSM
end

--- Drop the cached reference, so a late-loading LibSharedMedia is picked up on the next read.
function NS.ClearLSMCache()
    LSM = nil
end

-- ── the minimap button's one boolean (launcher-§3) ───────────────────────────────────────
--
-- C.MINIMAP_PATH, `global.minimap.shown`, is the one path whose stored value is neither in the
-- profile nor session state. The path reads in the row's sense (SHOWN); the value is LibDBIcon's own
-- `hide` key in the GLOBAL store, which LibDBIcon writes too. So the row carries these as its own
-- get/set (stamped by settings/General.lua) and nothing is ever stored at `global.minimap.shown`
-- (anti-pattern #81). Not `sessionOnly`: the value IS stored, and a sessionOnly row would be reset by
-- `/rm resetall`, which must not reach an installation-scoped button.
local function minimapTable()
    local g = NS.db and NS.db.global
    return type(g) == "table" and g.minimap or nil
end

--- The minimap row's `get`: inverts LibDBIcon's `hide`. An absent table reads as shown.
function NS.MinimapShown()
    local t = minimapTable()
    return not (t and t.hide)
end

--- The minimap row's `set`: the other half of the inversion, plus the button itself, so the button
--- follows the checkbox at once. Writing the store here as well keeps a build with no launcher still
--- storing what the player chose.
function NS.SetMinimapShown(value)
    local g = NS.db and NS.db.global
    if type(g) == "table" then
        g.minimap = g.minimap or {}
        g.minimap.hide = not value
    end
    if NS.Launcher then NS.Launcher:SetShown(value and true or false) end
end

--- One setting's value: the schema runtime's read, with the shipped defaults behind it, for the one
--- moment the runtime has nowhere to read (before OnInitialize has built the db).
--- @param path string  a profile path ("locked") or a `global.`-prefixed one
function NS.GetSetting(path)
    local S = NS.SchemaRuntime
    if S then
        local v = S.Get(path)
        if v ~= nil then return v end
    end
    local d = NS.defaults
    if not (d and NS.ResolvePath and type(path) == "string") then return nil end
    local global = path:match("^global%.(.+)$")
    if global then return NS.ResolvePath(d.global, global) end
    return NS.ResolvePath(d.profile, path)
end
