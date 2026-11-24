local _, NS = ...
-- defaults/BandSetPresets.lua — the four preset band sets (design spec 5.2). Data only: a preset is
-- COPIED into the profile by modules/BandSets.lua (Create with a preset key, and the first-run seed),
-- never handed out by reference.
--
--   NS.BandSetPresets[key] = { name, matchBy, bands = { { from, to, label, frameColor, textColor,
--                              indicatorColor, rule? }, ... } }   key ∈ NS.BandSetPresets.ORDER
--   NS.BandSetPresets.DefaultFor(classFile) -> key         the class default the seed puts first
--
-- THE HUNTER SET IS PER CLIENT (clients-§5: two lists, picked once). WoW Forever's Auto Shot has the
-- vanilla dead zone, so its set is 0-5 MELEE, 5-8 DEAD, 8-35 RANGE (AUTO until the owner's rename,
-- 2026-11-24), 35+ OOR; Retail's hunter has none,
-- so its set is 0-5 MELEE, 5-40 RANGED, 40+ OOR. Both lists live in HUNTER_BY_CLIENT and `hunter` is
-- the one NS.Compat.ClientKey() picks at load (core/Compat.lua loads before this file).
--
-- EVERY PRESET CARRIES BAND RULES (schema v2, plan 2026-11-19-dynamic-bands D4): a band asks its
-- role's anchor spell (`spell(role)`), is the dead zone (`gap`) or lies past the last spell band
-- (`beyond`); its yards are the fallback. A rule names a role, never a spell, so one set serves every
-- class. A caster's first band stays a yard band: no baseline melee spell to ask. The presets are the
-- shape step 2 of core/Database.lua's ladder gives a stored v1 set (modules/BandSets.lua's
-- ConvertSet), apart from the caster set, which is CLOSE, CAST, OOR.
--
-- Colors come from the design ramp, nearest band first (core/Constants.lua's BAND_RAMP), each band its
-- own tables. Labels are localized at load; once copied into a profile they are the player's text.

local C = NS.Constants
local L = NS.L

local GREEN, LIME, YELLOW, ORANGE, RED = C.BAND_RAMP[1], C.BAND_RAMP[2], C.BAND_RAMP[3], C.BAND_RAMP[4],
    C.BAND_RAMP[5]

--- One band, every color its own table. `to` nil is open-ended; `rule` nil is a yard band.
local function band(from, to, label, hex, rule)
    return { from = from, to = to, label = label, frameColor = C.HexColor(hex), textColor = C.HexColor(hex),
             indicatorColor = C.HexColor(hex), rule = rule }
end

--- The rules, each call its own table.
local function spell(role) return { type = "spell", role = role } end
local function gap() return { type = "gap" } end
local function beyond() return { type = "beyond" } end

local Presets = {}

Presets.melee_ranged = {
    name = L["Melee / Ranged"], matchBy = "max",
    bands = {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 20, L["CLOSE"], LIME),
        band(20, 30, L["MID"], YELLOW), band(30, 40, L["LONG"], ORANGE, spell("ranged")),
        band(40, nil, L["OOR"], RED, beyond()),
    },
}

-- A caster: too close is a warning (yards: no melee spell to ask), CAST is wherever the ranged anchor
-- reaches (40 yd as its fallback), past it is out of range.
Presets.caster40 = {
    name = L["Caster 40"], matchBy = "max",
    bands = {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 40, L["CAST"], GREEN, spell("ranged")),
        band(40, nil, L["OOR"], RED, beyond()),
    },
}

-- For friendly units (a container's bandSetFriendly): inside 30, then wherever the friendly anchor
-- reaches (40 yd as its fallback), then out of range.
Presets.healer = {
    name = L["Healer"], matchBy = "max",
    bands = {
        band(0, 30, L["NEAR"], GREEN), band(30, 40, L["FAR"], YELLOW, spell("friendly")),
        band(40, nil, L["OOR"], RED, beyond()),
    },
}

local HUNTER_BY_CLIENT = {
    forever = {
        name = L["Hunter"], matchBy = "max",
        bands = {
            band(0, 5, L["MELEE"], YELLOW, spell("melee")), band(5, 8, L["DEAD"], ORANGE, gap()),
            band(8, 35, L["RANGE"], GREEN, spell("ranged")), band(35, nil, L["OOR"], RED, beyond()),
        },
    },
    retail = {
        name = L["Hunter"], matchBy = "max",
        bands = {
            band(0, 5, L["MELEE"], LIME, spell("melee")), band(5, 40, L["RANGED"], GREEN, spell("ranged")),
            band(40, nil, L["OOR"], RED, beyond()),
        },
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

-- A spec that plays unlike its class: Devourer, the Demon Hunter's 25 yd Intellect spec (the owner,
-- 2026-11-19), reads as a caster.
local SPEC_DEFAULT = { [1480] = "caster40" }

--- The preset key the first-run seed makes the default for `classFile` (and `specID`, when known).
--- @return string
function Presets.DefaultFor(classFile, specID)
    return SPEC_DEFAULT[specID or 0] or CLASS_DEFAULT[classFile] or "melee_ranged"
end

NS.BandSetPresets = Presets
