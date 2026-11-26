local _, NS = ...
-- defaults/BandSetPresets.lua — the preset band sets (design spec 5.2; RangeMaster#20). Data only: a
-- preset is COPIED into the profile by modules/BandSets.lua (Create with a preset key, and the
-- first-run seed), never handed out by reference.
--
--   NS.BandSetPresets[key] = { name, matchBy, bands = { { from, to, label, frameColor, textColor,
--                              indicatorColor, rule? }, ... } }
--   NS.BandSetPresets.ORDER          the generic keys the first-run seed adds after the class default
--   NS.BandSetPresets.CLASS_KEYS     every class preset key this client has, in class order
--   NS.BandSetPresets.BY_CLIENT      [classFile] = <CLASS>_BY_CLIENT (both clients' lists, for tests)
--   NS.BandSetPresets.DefaultFor(classFile, specID?) -> key   the class default the seed puts first
--   NS.BandSetPresets.SpecDependent(classFile) -> boolean     its default needs the spec to be read
--
-- THE GENERIC PRESETS are Melee / Ranged, Caster 40 and Healer, plus the Hunter set, which the seed has
-- always added. Healer is the friendly override (a container's bandSetFriendly): no class's default.
--
-- A PRESET PER CLASS, PER CLIENT (clients-§5: two lists, picked once). Each class has its own
-- `<CLASS>_BY_CLIENT = { forever = {...}, retail = {...} }`, and `NS.BandSetPresets.<class>` (the
-- lowercase class token) is the one NS.Compat.ClientKey() picks at load (core/Compat.lua loads before
-- this file). A class WoW Forever does not have (Death Knight, Monk, Demon Hunter, Evoker) has a
-- Retail list only, so on Forever its key is nil and Create refuses it. The bands sit at the class's
-- real range tiers, read off each client's DB2 (SpellMisc -> SpellRange) by SF-RM-01's seed contract
-- (docs/validate-seeds.md; the bundles under docs/seed-research/2026-11-25-*): melee, each distinct
-- tier of the class's key abilities, its longest hostile reach, then OOR. A tier is there only where
-- the class has a real ability at that distinct range, and no preset has more than five bands.
--
-- WoW Forever's Auto Shot has the vanilla dead zone, so the hunter's set is 0-5 MELEE, 5-8 DEAD, 8-35
-- RANGE (AUTO until the owner's rename, 2026-11-24), 35+ OOR; Retail's hunter has none, so its set is
-- 0-5 MELEE, 5-40 RANGED, 40+ OOR. The warrior's and the rogue's 5-8 yd CLOSE is a yard band, not a
-- dead zone: the band is there because Charge and Throw start at 8, and a rogue without a thrown
-- weapon has no ranged spell with a min range for the dead zone's test to ask.
--
-- EVERY PRESET CARRIES BAND RULES (schema v2, plan 2026-11-19-dynamic-bands D4): a band asks its
-- role's anchor spell (`spell(role)`), is the dead zone (`gap`) or lies past the last spell band
-- (`beyond`); its yards are the fallback. A rule names a role, never a spell. The roles are melee,
-- ranged, friendly and the tier roles `tierN` (core/Constants.lua TIER_ROLES): the class's spells that
-- reach N yd, so the Forever paladin's 5-10 JUDGE band asks Judgment, then Hammer of Justice, and a
-- class with no list for that tier reads the band's yards. A caster's first band stays a yard band: no
-- baseline melee spell to ask. The generic presets are the shape step 2 of core/Database.lua's ladder
-- gives a stored v1 set (modules/BandSets.lua's ConvertSet), apart from the caster set, which is
-- CLOSE, CAST, OOR. A tier role is new with the class presets: stored sets are never rewritten to
-- carry one, so no ladder step adds it.
--
-- Colors come from the design ramp, nearest band first (core/Constants.lua's BAND_RAMP), each band its
-- own tables; a caster's too-close band is orange, as Caster 40's, and the last band is always red.
-- Labels are localized at load; once copied into a profile they are the player's text.

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

--- A preset: its name, matchBy "max", and its bands.
local function preset(name, bands)
    return { name = name, matchBy = "max", bands = bands }
end

local Presets = {}

Presets.melee_ranged = preset(L["Melee / Ranged"], {
    band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 20, L["CLOSE"], LIME),
    band(20, 30, L["MID"], YELLOW), band(30, 40, L["LONG"], ORANGE, spell("ranged")),
    band(40, nil, L["OOR"], RED, beyond()),
})

-- A caster: too close is a warning (yards: no melee spell to ask), CAST is wherever the ranged anchor
-- reaches (40 yd as its fallback), past it is out of range.
Presets.caster40 = preset(L["Caster 40"], {
    band(0, 8, L["CLOSE"], ORANGE), band(8, 40, L["CAST"], GREEN, spell("ranged")),
    band(40, nil, L["OOR"], RED, beyond()),
})

-- For friendly units (a container's bandSetFriendly): inside 30, then wherever the friendly anchor
-- reaches (40 yd as its fallback), then out of range.
Presets.healer = preset(L["Healer"], {
    band(0, 30, L["NEAR"], GREEN), band(30, 40, L["FAR"], YELLOW, spell("friendly")),
    band(40, nil, L["OOR"], RED, beyond()),
})

-- ---------------------------------------------------------------------------
-- The class presets, one list per client. Each comment names the tier anchors the bands ask
-- (defaults/SpellSeeds.lua) and the DB2 reach they were read at.
-- ---------------------------------------------------------------------------

-- Forever: Charge 100 and Intercept 20252 are 8-25, Throw and the Shoot spells 8-30. Retail: Charge
-- 100 8-25, Heroic Throw 57755 8-30 and Taunt 355 0-30.
local WARRIOR_BY_CLIENT = {
    forever = preset(L["Warrior"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 8, L["CLOSE"], LIME),
        band(8, 25, L["CHARGE"], YELLOW, spell("tier25")), band(25, 30, L["RANGE"], ORANGE, spell("ranged")),
        band(30, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Warrior"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 8, L["CLOSE"], LIME),
        band(8, 25, L["CHARGE"], YELLOW, spell("tier25")), band(25, 30, L["RANGE"], ORANGE, spell("ranged")),
        band(30, nil, L["OOR"], RED, beyond()),
    }),
}

-- Forever: Judgment 20271 and Hammer of Justice 853 are 0-10 (the owner, 2026-11-25), Exorcism and
-- Hammer of Wrath 0-30. Retail: Hammer of Justice 853 0-10, Judgment 20271 and Avenger's Shield 0-30.
local PALADIN_BY_CLIENT = {
    forever = preset(L["Paladin"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 10, L["JUDGE"], LIME, spell("tier10")),
        band(10, 30, L["RANGE"], YELLOW, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Paladin"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 10, L["HAMMER"], LIME, spell("tier10")),
        band(10, 30, L["RANGE"], YELLOW, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
}

-- Unchanged by RangeMaster#20 (the owner's rulings: Wing Clip is the Forever melee anchor, band 3 is
-- RANGE).
local HUNTER_BY_CLIENT = {
    forever = preset(L["Hunter"], {
        band(0, 5, L["MELEE"], YELLOW, spell("melee")), band(5, 8, L["DEAD"], ORANGE, gap()),
        band(8, 35, L["RANGE"], GREEN, spell("ranged")), band(35, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Hunter"], {
        band(0, 5, L["MELEE"], LIME, spell("melee")), band(5, 40, L["RANGED"], GREEN, spell("ranged")),
        band(40, nil, L["OOR"], RED, beyond()),
    }),
}

-- Forever: Throw and the Shoot spells are 8-30. Retail: Shadowstep 36554 0-25, Poisoned Knife and
-- Shuriken Toss 0-30 (Outlaw's Pistol Shot 0-20).
local ROGUE_BY_CLIENT = {
    forever = preset(L["Rogue"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 8, L["CLOSE"], LIME),
        band(8, 30, L["RANGE"], YELLOW, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Rogue"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 25, L["STEP"], LIME, spell("tier25")),
        band(25, 30, L["RANGE"], YELLOW, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
}

-- Forever: Smite, Mind Blast and Shadow Word: Pain are 0-30. Retail: 0-40.
local PRIEST_BY_CLIENT = {
    forever = preset(L["Priest"], {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 30, L["CAST"], GREEN, spell("ranged")),
        band(30, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Priest"], {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 40, L["CAST"], GREEN, spell("ranged")),
        band(40, nil, L["OOR"], RED, beyond()),
    }),
}

-- Retail only: Mind Freeze 47528 is 0-15, Death Coil, Howling Blast and Death Grip 0-30.
local DEATHKNIGHT_BY_CLIENT = {
    retail = preset(L["Death Knight"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 15, L["FREEZE"], LIME, spell("tier15")),
        band(15, 30, L["RANGE"], YELLOW, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
}

-- Forever: Earth Shock 8042, Flame Shock 8050 and Frost Shock 8056 are 0-20, Lightning Bolt 0-30.
-- Retail: Wind Shear 57994 is 0-30, Lightning Bolt and Flame Shock 0-40.
local SHAMAN_BY_CLIENT = {
    forever = preset(L["Shaman"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 20, L["SHOCK"], LIME, spell("tier20")),
        band(20, 30, L["CAST"], YELLOW, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Shaman"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 30, L["SHEAR"], LIME, spell("tier30")),
        band(30, 40, L["CAST"], YELLOW, spell("ranged")), band(40, nil, L["OOR"], RED, beyond()),
    }),
}

-- Forever: Fire Blast 2136 is 0-20, Frostbolt 116 0-30, Fireball 133 0-35. Retail: 0-40.
local MAGE_BY_CLIENT = {
    forever = preset(L["Mage"], {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 20, L["BLAST"], GREEN, spell("tier20")),
        band(20, 30, L["CAST"], LIME, spell("tier30")), band(30, 35, L["LONG"], YELLOW, spell("ranged")),
        band(35, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Mage"], {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 40, L["CAST"], GREEN, spell("ranged")),
        band(40, nil, L["OOR"], RED, beyond()),
    }),
}

-- Forever: Drain Life 689 and Fear 5782 are 0-20, Shadow Bolt and Corruption 0-30. Retail: 0-40.
local WARLOCK_BY_CLIENT = {
    forever = preset(L["Warlock"], {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 20, L["DRAIN"], GREEN, spell("tier20")),
        band(20, 30, L["CAST"], LIME, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Warlock"], {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 40, L["CAST"], GREEN, spell("ranged")),
        band(40, nil, L["OOR"], RED, beyond()),
    }),
}

-- Retail only: Crackling Jade Lightning 117952 is 0-40.
local MONK_BY_CLIENT = {
    retail = preset(L["Monk"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 40, L["RANGE"], LIME, spell("ranged")),
        band(40, nil, L["OOR"], RED, beyond()),
    }),
}

-- Forever: Wrath, Moonfire and Entangling Roots are 0-30. Retail: Skull Bash 106839 is 0-13 (cat and
-- bear), Wrath and Moonfire 0-40.
local DRUID_BY_CLIENT = {
    forever = preset(L["Druid"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 30, L["RANGE"], LIME, spell("ranged")),
        band(30, nil, L["OOR"], RED, beyond()),
    }),
    retail = preset(L["Druid"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 13, L["BASH"], LIME, spell("tier13")),
        band(13, 40, L["RANGE"], YELLOW, spell("ranged")), band(40, nil, L["OOR"], RED, beyond()),
    }),
}

-- Retail only: Felblade 232893 is 0-15, Throw Glaive and Torment 0-30. Devourer keeps its spec
-- override (SPEC_DEFAULT).
local DEMONHUNTER_BY_CLIENT = {
    retail = preset(L["Demon Hunter"], {
        band(0, 5, L["MELEE"], GREEN, spell("melee")), band(5, 15, L["BLADE"], LIME, spell("tier15")),
        band(15, 30, L["RANGE"], YELLOW, spell("ranged")), band(30, nil, L["OOR"], RED, beyond()),
    }),
}

-- Retail only: Azure Strike, Living Flame and Disintegrate are 0-25.
local EVOKER_BY_CLIENT = {
    retail = preset(L["Evoker"], {
        band(0, 8, L["CLOSE"], ORANGE), band(8, 25, L["CAST"], GREEN, spell("ranged")),
        band(25, nil, L["OOR"], RED, beyond()),
    }),
}

-- The class presets in class order (ChrClasses ID), each keyed by its class file.
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
    "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }
local BY_CLIENT = {
    WARRIOR = WARRIOR_BY_CLIENT, PALADIN = PALADIN_BY_CLIENT, HUNTER = HUNTER_BY_CLIENT,
    ROGUE = ROGUE_BY_CLIENT, PRIEST = PRIEST_BY_CLIENT, DEATHKNIGHT = DEATHKNIGHT_BY_CLIENT,
    SHAMAN = SHAMAN_BY_CLIENT, MAGE = MAGE_BY_CLIENT, WARLOCK = WARLOCK_BY_CLIENT, MONK = MONK_BY_CLIENT,
    DRUID = DRUID_BY_CLIENT, DEMONHUNTER = DEMONHUNTER_BY_CLIENT, EVOKER = EVOKER_BY_CLIENT,
}
Presets.BY_CLIENT = BY_CLIENT
Presets.HUNTER_BY_CLIENT = HUNTER_BY_CLIENT

-- The client's own list of each class, picked once. Any client but Forever reads Retail's.
local CLIENT = NS.Compat.ClientKey() == "forever" and "forever" or "retail"
local CLASS_DEFAULT = {}
Presets.CLASS_KEYS = {}
for _, classFile in ipairs(CLASS_ORDER) do
    local own = BY_CLIENT[classFile][CLIENT]
    if own then
        local key = classFile:lower()
        Presets[key] = own
        CLASS_DEFAULT[classFile] = key
        Presets.CLASS_KEYS[#Presets.CLASS_KEYS + 1] = key
    end
end

--- The generic preset keys, in the order the first-run seed adds them after the class default.
Presets.ORDER = { "melee_ranged", "caster40", "healer", "hunter" }

-- A spec that plays unlike its class: Devourer, the Demon Hunter's 25 yd Intellect spec (the owner,
-- 2026-11-19), reads as a caster.
local SPEC_DEFAULT = { [1480] = "caster40" }
-- The classes one of those specs belongs to.
local SPEC_CLASS = { DEMONHUNTER = true }

--- The preset key the first-run seed makes the default for `classFile` (and `specID`, when known):
--- the spec's override, else the class's own preset on this client, else Melee / Ranged (a class
--- not listed, or unreadable).
--- @return string
function Presets.DefaultFor(classFile, specID)
    return SPEC_DEFAULT[specID or 0] or CLASS_DEFAULT[classFile] or "melee_ranged"
end

--- Whether `classFile`'s default can depend on its spec on this client (a class with a spec override
--- and a preset of its own here): until the spec is read, its default is not known yet
--- (modules/BandSetChoice.lua defers the character's assignment; R4-RM-01).
--- @return boolean
function Presets.SpecDependent(classFile)
    return SPEC_CLASS[classFile] == true and CLASS_DEFAULT[classFile] ~= nil
end

NS.BandSetPresets = Presets
