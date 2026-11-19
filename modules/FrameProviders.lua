local _, NS = ...
-- modules/FrameProviders.lua — which unit frame a `frame` container sits on (design spec 5.4).
--
--   NS.FrameProviders.NameFor(provider, unit, customName) -> globalName|nil
--   NS.FrameProviders.Resolve(provider, unit, customName) -> frame|nil
--   NS.FrameProviders.Lookup(globalName) -> frame|nil
--
-- THREE PROVIDERS, and only three (the v0.1.0 plan's Global Constraints):
--   blizzard   TargetFrame, FocusFrame, PetFrame
--   ellesmere  EllesmereUIUnitFrames_Target, _Focus, _Pet: the names EllesmereUIUnitFrames spawns its
--              frames under (EUI_UnitFrames_Init.lua's SpawnUnitFrame calls), the same in its Retail
--              9.8.6 and WoW Forever 9.8.8 builds (docs/compat-layer.md). It spawns a unit's frame only
--              when that unit's source is EllesmereUI, at PLAYER_LOGIN; this file reads the global
--              and never EllesmereUIDB.
--   custom     the global frame name the player typed or picked (modules/FramePicker.lua)
-- Mouseover has no frame from either addon, so NameFor answers nil for it and the frame anchor
-- follows the cursor instead (modules/Anchors_Frame.lua). A custom name serves any unit.
--
-- A frame is looked up when asked, never cached: a missing one (an addon off, a typo, a frame not
-- spawned yet) answers nil and the anchor asks again on ADDON_LOADED and PLAYER_ENTERING_WORLD. A
-- forbidden frame, or a global that is not a frame, answers nil too.
--
--   NS.FrameProviders.PlateCastBar(plate, token?) -> frame|nil   the cast bar on a nameplate
--
-- THE CAST BAR ON A NAMEPLATE (a nameplate container's "Attach to part", modules/Anchors_Nameplate.lua)
-- comes from two providers, asked in this order:
--   ellesmere  EllesmereUINameplates' own plate for the token, `EllesmereNameplates_NS.plates[token]`
--              (the global its EllesmereUINameplates.lua publishes; EUI_Nameplates_Events.lua fills
--              the map at NAME_PLATE_UNIT_ADDED and clears it at _REMOVED), and its `cast` StatusBar
--              (EUI_Nameplates_PlatePool.lua). Taken only while that plate says it sits on this
--              Blizzard plate (`.nameplate`, set by its SetUnit), so a stale map entry is never used.
--              The same in its Retail 9.8.6 and WoW Forever 9.9 builds (docs/compat-layer.md).
--   blizzard   the client's own plate's `UnitFrame.castBar` (CompactUnitFrame's key on both
--              clients; EllesmereUINameplates' own fallback reads the same), else `UnitFrame.CastBar`.
-- Nil when neither has one: the caller stays on the plate. Every read is a table index under pcall,
-- and a forbidden frame, or a value that is not a frame, answers nil, as Lookup's do. A hidden cast
-- bar is still answered: it keeps its place, so a container on it does not move between casts.

NS.FrameProviders = NS.FrameProviders or {}
local P = NS.FrameProviders

P.NAMES = {
    blizzard  = { target = "TargetFrame", focus = "FocusFrame", pet = "PetFrame" },
    ellesmere = { target = "EllesmereUIUnitFrames_Target", focus = "EllesmereUIUnitFrames_Focus",
                  pet = "EllesmereUIUnitFrames_Pet" },
}

local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:match("^%s*(.-)%s*$"))
end

function P.NameFor(provider, unit, customName)
    if provider == "custom" then
        local name = trim(customName)
        return name ~= "" and name or nil
    end
    local names = P.NAMES[provider]
    return names and names[unit] or nil
end

local function index(t, k) return t[k] end

--- `t[k]` under pcall, or nil.
local function field(t, k)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(index, t, k)
    if ok then return v end
    return nil
end

--- `f` when it is a frame that is not forbidden, else nil. Its reads are pcall'd, so a table whose
--- index raises answers nil.
local function usable(f)
    if type(f) ~= "table" or type(field(f, "SetPoint")) ~= "function" then return nil end
    local isForbidden = field(f, "IsForbidden")
    if type(isForbidden) == "function" then
        local ok, v = pcall(isForbidden, f)
        if not ok or v == true or NS.Compat.IsSecret(v) then return nil end
    end
    return f
end

--- The global frame `name`, or nil for a missing, forbidden or non-frame global.
function P.Lookup(name)
    if type(name) ~= "string" then return nil end
    return usable(_G[name])
end

function P.Resolve(provider, unit, customName)
    return P.Lookup(P.NameFor(provider, unit, customName))
end

-- ---------------------------------------------------------------------------
-- The cast bar on a nameplate
-- ---------------------------------------------------------------------------

P.ELLESMERE_PLATES = "EllesmereNameplates_NS"
P.CAST_BAR_KEYS = { "castBar", "CastBar" }

--- EllesmereUINameplates' cast bar on `plate`: its map entry for `token` while that entry sits on
--- `plate`, else the entry whose host is `plate` (the owner's WoW Forever probe, 2026-11-20, found no
--- entry under the plate's token; the frame comparison needs no token at all).
local function ellesmereCast(plate, token)
    local map = field(field(_G, P.ELLESMERE_PLATES), "plates")
    if type(map) ~= "table" then return nil end
    local own = type(token) == "string" and field(map, token) or nil
    if type(own) ~= "table" or field(own, "nameplate") ~= plate then
        own = nil
        local ok = pcall(function()
            for _, entry in pairs(map) do
                if type(entry) == "table" and entry.nameplate == plate then
                    own = entry
                    return
                end
            end
        end)
        if not ok then own = nil end
    end
    if type(own) ~= "table" then return nil end
    return usable(field(own, "cast"))
end

--- The client's own plate's cast bar.
local function blizzardCast(plate)
    local uf = usable(field(plate, "UnitFrame"))
    if not uf then return nil end
    for _, key in ipairs(P.CAST_BAR_KEYS) do
        local bar = usable(field(uf, key))
        if bar then return bar end
    end
    return nil
end

--- The cast bar on nameplate `plate` (one NS.Compat answered, so not forbidden), for the plate token
--- `token` (read off the plate when not given): EllesmereUI's, else the client's own, else nil.
function P.PlateCastBar(plate, token)
    if not usable(plate) then return nil end
    token = token or NS.Compat.PlateToken(plate)
    return ellesmereCast(plate, token) or blizzardCast(plate)
end
