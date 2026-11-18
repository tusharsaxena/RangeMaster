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

--- The global frame `name`, or nil for a missing, forbidden or non-frame global.
function P.Lookup(name)
    if type(name) ~= "string" then return nil end
    local f = _G[name]
    if type(f) ~= "table" or type(f.SetPoint) ~= "function" then return nil end
    if type(f.IsForbidden) == "function" then
        local ok, v = pcall(f.IsForbidden, f)
        if not ok or v == true or NS.Compat.IsSecret(v) then return nil end
    end
    return f
end

function P.Resolve(provider, unit, customName)
    return P.Lookup(P.NameFor(provider, unit, customName))
end
