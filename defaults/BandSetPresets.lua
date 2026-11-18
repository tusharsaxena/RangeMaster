local _, NS = ...
-- defaults/BandSetPresets.lua — the four preset band sets (design spec 5.2). Data only: a preset is
-- COPIED into the profile by modules/BandSets.lua (Create with a preset key, and the first-run seed),
-- never handed out by reference.
--
--   NS.BandSetPresets[key] = { name, matchBy, bands = { { from, to, label, frameColor, textColor,
--                              indicatorColor }, ... } }   key ∈ NS.BandSetPresets.ORDER
--   NS.BandSetPresets.DefaultFor(classFile) -> key         the class default the seed puts first
--
-- THE HUNTER SET IS PER CLIENT (clients-§5: two lists, picked once). WoW Forever's Auto Shot has the
-- vanilla dead zone, so its set is 0-5 MELEE, 5-8 DEAD, 8-35 AUTO, 35+ OOR; Retail's hunter has none,
-- so its set is 0-5 MELEE, 5-40 RANGED, 40+ OOR. Both lists live in HUNTER_BY_CLIENT and `hunter` is
-- the one NS.Compat.ClientKey() picks at load (core/Compat.lua loads before this file).
--
-- Colors come from the design ramp, nearest band first (core/Constants.lua's BAND_RAMP), each band its
-- own tables. Labels are localized at load; once copied into a profile they are the player's text.

local C = NS.Constants
local L = NS.L

local GREEN, LIME, YELLOW, ORANGE, RED = C.BAND_RAMP[1], C.BAND_RAMP[2], C.BAND_RAMP[3], C.BAND_RAMP[4],
    C.BAND_RAMP[5]

--- One band, every color its own table. `to` nil is open-ended.
local function band(from, to, label, hex)
    return { from = from, to = to, label = label, frameColor = C.HexColor(hex), textColor = C.HexColor(hex),
             indicatorColor = C.HexColor(hex) }
end

local Presets = {}

Presets.melee_ranged = {
    name = L["Melee / Ranged"], matchBy = "max",
    bands = {
        band(0, 5, L["MELEE"], GREEN), band(5, 20, L["CLOSE"], LIME), band(20, 30, L["MID"], YELLOW),
        band(30, 40, L["LONG"], ORANGE), band(40, nil, L["OOR"], RED),
    },
}

-- A 40 yd caster: too close is a warning, the working band is green, the edge of 40 yd is yellow.
Presets.caster40 = {
    name = L["Caster 40"], matchBy = "max",
    bands = {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 30, L["MID"], GREEN), band(30, 40, L["LONG"], YELLOW),
        band(40, nil, L["OOR"], RED),
    },
}

-- For friendly units (a container's bandSetFriendly): inside 30, the 30-40 edge, out of 40.
Presets.healer = {
    name = L["Healer"], matchBy = "max",
    bands = { band(0, 30, L["NEAR"], GREEN), band(30, 40, L["FAR"], YELLOW), band(40, nil, L["OOR"], RED) },
}

local HUNTER_BY_CLIENT = {
    forever = {
        name = L["Hunter"], matchBy = "max",
        bands = {
            band(0, 5, L["MELEE"], YELLOW), band(5, 8, L["DEAD"], ORANGE), band(8, 35, L["AUTO"], GREEN),
            band(35, nil, L["OOR"], RED),
        },
    },
    retail = {
        name = L["Hunter"], matchBy = "max",
        bands = { band(0, 5, L["MELEE"], LIME), band(5, 40, L["RANGED"], GREEN), band(40, nil, L["OOR"], RED) },
    },
}
Presets.HUNTER_BY_CLIENT = HUNTER_BY_CLIENT
Presets.hunter = HUNTER_BY_CLIENT[NS.Compat.ClientKey()] or HUNTER_BY_CLIENT.retail

--- The preset keys, in the order the first-run seed adds them after the class default.
Presets.ORDER = { "melee_ranged", "caster40", "healer", "hunter" }

-- The class default. Class alone cannot tell a healer, and the healer set is a friendly override,
-- so it is no class's default; a class not listed (or unreadable) gets Melee / Ranged.
local CLASS_DEFAULT = {
    HUNTER = "hunter",
    MAGE = "caster40", WARLOCK = "caster40", PRIEST = "caster40", EVOKER = "caster40",
}

--- The preset key the first-run seed makes the default for `classFile`.
--- @return string
function Presets.DefaultFor(classFile)
    return CLASS_DEFAULT[classFile] or "melee_ranged"
end

NS.BandSetPresets = Presets
