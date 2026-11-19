local _, NS = ...
-- core/Compat.lua — root of the compat family, the sole home of every version-variant client call
-- (compat). Family: core/Compat.lua (this file only).
--
-- It routes three things from LibKa0s-Compat-1.0: the client questions (IsForever, IsRetail,
-- ClientKey, ForClient; clients-§3), the secret-value guards (IsSecret, CanAccess, IsSafeKey;
-- events-frames-taint-§8) and the spell-info reader (GetSpellInfo). It owns the range engine's client
-- reads (IsEventValid, IsSpellKnown, SpellInRange, ItemInRange, InteractInRange, CanAttack), the
-- band rules' anchor reads (CurrentSpellID and AnchorInRange, built on those, and ShapeshiftFormID),
-- the two unit reads the band sets make (IsFriend, PlayerClass), each pcall-wrapped and secret-checked,
-- the anchors' frame reads (NamePlateForUnit, PlateToken, NamePlates, GetMouseFocus), each
-- forbidden-checked, and the per-client range ladder (RangeLadder). No other file of
-- this addon reads a WOW_PROJECT_* global or decides the client from an interface number. Every
-- shim, what it wraps and who calls it: docs/compat-layer.md.
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

-- ---------------------------------------------------------------------------
-- Spell info (LibKa0s-Compat-1.0)
-- ---------------------------------------------------------------------------
-- `name, iconID, castTime, minRange, maxRange, spellID`, or a single nil. Library absent: the
-- major's documented no-rung answer, nil, so a ladder built without it simply has no spell rungs.

Compat.GetSpellInfo = CompatLib and CompatLib.GetSpellInfo or function() return nil end

-- ---------------------------------------------------------------------------
-- The range reads (design spec 5.1; docs/compat-layer.md)
-- ---------------------------------------------------------------------------
-- Every client range read the addon makes outside LibRangeCheck-3.0 lands here. Each one is called
-- inside pcall, and its answer is passed through IsSecret BEFORE it is compared or tested: a raise,
-- a secret or a value that is neither a boolean nor 1/0 all answer nil, "no answer", which the range
-- engine reads as unknown and never as out of range (events-frames-taint-§8).

--- Normalize one guarded range answer: true, false, or nil for no answer.
local function rangeAnswer(ok, v)
    if not ok or Compat.IsSecret(v) then return nil end
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return nil
end

--- Whether the client knows the event `name`, asked before a registration that a client may not
--- carry (PLAYER_FOCUS_CHANGED on Forever). A client with no C_EventUtils answers true and leaves
--- the refusal to NS.SafeRegisterEvent.
--- @return boolean
function Compat.IsEventValid(name)
    if C_EventUtils and C_EventUtils.IsEventValid then
        local ok, v = pcall(C_EventUtils.IsEventValid, name)
        if ok and not Compat.IsSecret(v) then return v and true or false end
    end
    return true
end

--- Whether the player knows the spell `id`. Only a known spell is ever range-checked: an unlearned
--- one can report "in range" from anywhere (research, lesson 9). Knowing is half of that rule; the
--- other half, usable right now, is IsSpellUsable below.
--- @return boolean
function Compat.IsSpellKnown(id)
    if type(id) ~= "number" or not (C_SpellBook and C_SpellBook.IsSpellKnown) then return false end
    return rangeAnswer(pcall(C_SpellBook.IsSpellKnown, id)) == true
end

--- Whether the spell `id` is usable right now, the second half of research lesson 9: a known spell
--- that is unusable in the current form or stance can report "in range" from anywhere. Short of
--- power still counts as usable (the range answer stays true; only the cast is refused). A raise,
--- a secret or a missing API answers false, so the caller never trusts a range it cannot vouch
--- for. Asked per call and never cached: a shapeshift fires no SPELLS_CHANGED.
--- @return boolean
function Compat.IsSpellUsable(id)
    if type(id) ~= "number" or not (C_Spell and C_Spell.IsSpellUsable) then return false end
    local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, id)
    if not ok or Compat.IsSecret(usable) or Compat.IsSecret(noPower) then return false end
    return usable == true or noPower == true
end

--- Whether `unit` is within the spell `id`'s range: true, false, or nil (not applicable, no unit,
--- a raise or a secret).
--- @return boolean|nil
function Compat.SpellInRange(id, unit)
    if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    return rangeAnswer(pcall(C_Spell.IsSpellInRange, id, unit))
end

-- ---------------------------------------------------------------------------
-- The anchor reads (dynamic-bands plan D1; docs/compat-layer.md)
-- ---------------------------------------------------------------------------
-- A band's spell rule asks its role's anchor spell "in range?". The anchor is resolved once per
-- rebuild (CurrentSpellID: the learned rank, then a known override) and asked per tick
-- (AnchorInRange). Both are built on the shims above, so no client call is wrapped twice.

--- A plain positive spell ID, or nil (a secret, a non-number, 0 or less).
local function plainId(v)
    if Compat.IsSecret(v) or type(v) ~= "number" or v <= 0 then return nil end
    return v
end

--- The ID to ask for the spell `id` now: the rank the spellbook holds under its name (a Forever
--- seed is rank 1; LibRangeCheck-3.0's findSpellIdx also asks by name), then that spell's override
--- when the player knows the override (a hero-talent swap). nil when the client has no such spell
--- (or no spell-info reader); the ID itself when the name lookup answers nothing. The name is the
--- client's own localized one, never a hard-coded string. Asked at rebuild, never per tick.
--- @return number|nil
function Compat.CurrentSpellID(id)
    if type(id) ~= "number" then return nil end
    local name = Compat.GetSpellInfo(id)
    if name == nil or Compat.IsSecret(name) then return nil end
    local cur = plainId(select(6, Compat.GetSpellInfo(name))) or id
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, ov = pcall(C_Spell.GetOverrideSpell, cur)
        ov = ok and plainId(ov) or nil
        if ov and ov ~= cur and Compat.IsSpellKnown(ov) then cur = ov end
    end
    return cur
end

--- Whether `unit` is within the anchor spell `id`'s range: true, false, or nil when the anchor
--- cannot vouch (not known, not usable right now, not applicable, a raise or a secret). A nil is
--- never read as false: the band falls back to its yards (dynamic-bands plan, the owner's rulings).
--- `id` is the rebuild's CurrentSpellID answer.
--- @return boolean|nil
function Compat.AnchorInRange(id, unit)
    if not Compat.IsSpellKnown(id) or not Compat.IsSpellUsable(id) then return nil end
    return Compat.SpellInRange(id, unit)
end

--- The player's shapeshift form ID (GetShapeshiftFormID: 1 Cat, 5 Bear, ...), or nil when the
--- player is in no form, the client will not say, or the answer is a secret. Read by the anchor
--- resolver (modules/Range.lua), which keys a druid's melee anchor by form.
--- @return number|nil
function Compat.ShapeshiftFormID()
    if not GetShapeshiftFormID then return nil end
    local ok, v = pcall(GetShapeshiftFormID)
    if not ok then return nil end
    return plainId(v)
end

--- Whether `unit` is within the item `id`'s use range: true, false, or nil. The client refuses
--- this on a unit the player cannot attack while in combat; the caller skips it there.
--- @return boolean|nil
function Compat.ItemInRange(id, unit)
    if not (C_Item and C_Item.IsItemInRange) then return nil end
    return rangeAnswer(pcall(C_Item.IsItemInRange, id, unit))
end

--- Whether `unit` is within interact distance `index` (3 duel, 4 follow): true, false, or nil.
--- Protected on a friendly unit in combat; the caller skips it there.
--- @return boolean|nil
function Compat.InteractInRange(index, unit)
    if not CheckInteractDistance then return nil end
    return rangeAnswer(pcall(CheckInteractDistance, unit, index))
end

--- Whether the player can attack `unit`: true, false, or nil when the client will not say.
--- @return boolean|nil
function Compat.CanAttack(unit)
    if not UnitCanAttack then return nil end
    return rangeAnswer(pcall(UnitCanAttack, "player", unit))
end

--- Whether `unit` is friendly to the player: true, false, or nil when the client will not say (a
--- raise or a secret). A band set's friendly override (modules/BandSets.lua's ForUnit) applies only
--- on a true, so an unreadable reaction keeps the container on its own set.
--- @return boolean|nil
function Compat.IsFriend(unit)
    if not UnitIsFriend then return nil end
    return rangeAnswer(pcall(UnitIsFriend, "player", unit))
end

-- ---------------------------------------------------------------------------
-- The frame reads the anchors make (design spec 5.4; docs/compat-layer.md)
-- ---------------------------------------------------------------------------
-- A nameplate can be FORBIDDEN (a friendly plate in an instance on 12.x): any method call on one
-- raises, so the plate reads below ask IsForbidden first, under pcall, and hand a forbidden plate
-- back as nil. The caller never touches a plate these did not vouch for.

--- Whether `f` is a forbidden frame. A raise or a secret answer counts as forbidden, the side that
--- never calls a method on it.
local function forbidden(f)
    if type(f) ~= "table" then return true end
    if type(f.IsForbidden) ~= "function" then return false end
    local ok, v = pcall(f.IsForbidden, f)
    if not ok or Compat.IsSecret(v) then return true end
    return v == true
end

--- The nameplate frame of `unit` ("target", "nameplate3", ...), or nil: no plate, a forbidden
--- plate, a raise, or a client with no C_NamePlate.
--- @return table|nil
function Compat.NamePlateForUnit(unit)
    if type(unit) ~= "string" or not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or forbidden(plate) then return nil end
    return plate
end

--- The unit token a nameplate frame serves ("nameplate3"), or nil when it will not say.
--- @return string|nil
function Compat.PlateToken(plate)
    if forbidden(plate) then return nil end
    local ok, token = pcall(function() return plate.namePlateUnitToken end)
    if not ok or type(token) ~= "string" or not Compat.IsSafeKey(token) then return nil end
    return token
end

--- Every visible, not forbidden nameplate, as a new array of { token = string, plate = frame }.
--- The stand-up's rescan: a stood-down addon heard no NAME_PLATE_UNIT_ADDED for the plates shown.
--- @return table
function Compat.NamePlates()
    local out = {}
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return out end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return out end
    for _, plate in ipairs(plates) do
        local token = Compat.PlateToken(plate)
        if token then out[#out + 1] = { token = token, plate = plate } end
    end
    return out
end

--- The topmost frame under the cursor, or nil (the frame picker). GetMouseFoci, which answers every
--- frame under the cursor, topmost first; both clients the TOC admits carry it.
--- @return table|nil
function Compat.GetMouseFocus()
    if not GetMouseFoci then return nil end
    local ok, foci = pcall(GetMouseFoci)
    if not ok or type(foci) ~= "table" then return nil end
    return foci[1]
end

-- ---------------------------------------------------------------------------
-- The per-client range ladder (clients-§5)
-- ---------------------------------------------------------------------------
-- Forever is a mainline-family client on a vanilla world. Its item range checks are reliable only
-- at 20, 30 and 35 yd (AppelSwingsForever Bands.lua, each ID verified on Forever 1.60.1 and listed
-- in LibRangeCheck-3.0's Era harm table at the same yard), and its two interact distances are the
-- vanilla duel (10 yd) and follow (28 yd) distances, shortened for the two large-hitbox races by
-- the offsets LibRangeCheck-3.0 measured (its InteractLists). Retail's ladder is spells only:
-- LibRangeCheck already owns that client's item and interact tables.

local FOREVER_ITEMS = {
    { yd = 20, ids = { 10645, 1191, 4388 } },          -- Gnomish Death Ray, Bag of Marbles, Discombobulator Ray
    { yd = 30, ids = { 835, 2091, 7734, 17202 } },     -- Large Rope Net, Magic Dust, Six Demon Bag, Snowball
    { yd = 35, ids = { 18904, 1399, 1402 } },          -- Zorbin's Ultra-Shrinker, Magic Candle, Brimstone
}
local FOREVER_INTERACT = { { index = 3, yd = 10 }, { index = 4, yd = 28 } }
local INTERACT_RACE_OFFSET = {
    Tauren  = { [3] = -2, [4] = -3 },
    Scourge = { [3] = -1, [4] = -1 },
}

local function playerRace()
    if not UnitRace then return nil end
    local ok, _, raceFile = pcall(UnitRace, "player")
    if not ok or Compat.IsSecret(raceFile) then return nil end
    return raceFile
end

local function playerClass()
    if not UnitClass then return nil end
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or Compat.IsSecret(classFile) then return nil end
    return classFile
end

--- The player's class token ("HUNTER", "MAGE", ...), or nil when the client will not say. Read by
--- the band-set seed (modules/BandSets.lua) to pick the class default.
--- @return string|nil
function Compat.PlayerClass() return playerClass() end

local function addForeverRungs(out)
    for _, group in ipairs(FOREVER_ITEMS) do
        for _, id in ipairs(group.ids) do out[#out + 1] = { kind = "item", id = id, yd = group.yd } end
    end
    local offset = INTERACT_RACE_OFFSET[playerRace() or ""] or {}
    for _, rung in ipairs(FOREVER_INTERACT) do
        out[#out + 1] = { kind = "interact", id = rung.index, yd = rung.yd + (offset[rung.index] or 0) }
    end
end

--- One seed spell as a rung, or nil: known, with a max range above 0 and no min range.
local function spellRung(id)
    if not Compat.IsSpellKnown(id) then return nil end
    local name, _, _, minRange, maxRange = Compat.GetSpellInfo(id)
    if not name or Compat.IsSecret(minRange) or Compat.IsSecret(maxRange) then return nil end
    if type(maxRange) ~= "number" or maxRange <= 0 or (tonumber(minRange) or 0) > 0 then return nil end
    return { kind = "spell", id = id, yd = math.floor(maxRange) }
end

local function addSpellRungs(out, client)
    local byClass = NS.SpellSeeds and NS.SpellSeeds[client]
    local seed = byClass and byClass[playerClass() or ""]
    for _, id in ipairs(seed and seed.ladder or {}) do
        out[#out + 1] = spellRung(id)
    end
end

local function byYard(a, b)
    if a.yd ~= b.yd then return a.yd < b.yd end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.id < b.id
end

--- The range ladder for this client and the player's class and race, sorted by yd ascending:
--- `{ { kind = "item"|"interact"|"spell", id = number, yd = number }, ... }`. A fresh table on each
--- call; modules/Range.lua builds it on the first Forever walk and again after a SPELLS_CHANGED
--- rebuild dropped it, never per tick (Retail, which has no ladder fallback, never builds one).
--- @return table
function Compat.RangeLadder()
    local out = {}
    local client = Compat.ClientKey() or "retail"
    if client == "forever" then addForeverRungs(out) end
    addSpellRungs(out, client)
    table.sort(out, byYard)
    return out
end
