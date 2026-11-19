local _, NS = ...
-- modules/BandSets.lua — the shared band sets (design spec 5.2, 5.3): the ONE runtime writer of the
-- band-set registry (profile.bandSets, bandSetOrder, nextBandSetId; architecture-§5) and the sole
-- sender of NS.MSG.BANDSETS_CHANGED.
--
--   NS.BandSets.Create(name, bandsOrPresetKey?) -> id     a preset key, a bands array, or nil (Melee / Ranged)
--   NS.BandSets.Delete(id, reassignTo?) -> boolean        never the last set
--   NS.BandSets.Duplicate(id) -> id, Rename(id, name) -> boolean
--   NS.BandSets.UniqueName(base, exceptId?) -> name   every writer's name: unique, case-blind
--   NS.BandSets.List() -> { id, ... }, Get(id) -> set, DefaultId() -> id, Normalize(id) -> boolean
--   NS.BandSets.SetBandSound(id, bandIndex, sound?) -> boolean   one band's LSM sound key (nil clears)
--   NS.BandSets.SetField(id, field, value) -> boolean    matchBy, unknown.label, unknown.color
--   NS.BandSets.SetBand(id, bandIndex, field, value) -> boolean   to, label, frameColor, textColor, indicatorColor
--   NS.BandSets.SetBandRule(id, bandIndex, rule?) -> boolean   one band's rule (nil: a yard band)
--   NS.BandSets.AddBand(id) -> index, RemoveBand(id, bandIndex) -> boolean
--   NS.BandSets.Resolve(setId, state, minYd, maxYd, unit?) -> bandIndex | "unknown" | nil (state "none")
--   NS.BandSets.ForUnit(container, unit) -> setId
--   NS.BandSets.ConvertSet(set, friendly?) -> set       the v1 -> v2 step's band rules (core/Database.lua)
--   NS.BandSets.Snapshot() -> snap, RestoreSnapshot(snap) -> boolean   the registry whole, for an Undo
--
-- THE DEFAULT SET IS THE FIRST ONE IN bandSetOrder. The first-run seed puts the class default there
-- (defaults/BandSetPresets.lua's DefaultFor), so a fresh container lands on it; deleting it makes the
-- next set the default. A container whose set no longer exists reads the default (ForUnit), and the
-- load pass and Delete both rewrite such a reference, so no container is ever left without bands.
--
-- EVERY STORED SET IS NORMALIZED: bands sorted by edge, contiguous from 0 (band n's `from` is band
-- n-1's `to`), the last one open-ended, none of zero width, at least one. That is what makes Resolve
-- total over [0, infinity) whatever the editor or a hand-edited SavedVariables file handed in. Create,
-- Duplicate, Normalize and RestoreSnapshot normalize on write; core/Database.lua's load pass normalizes
-- every stored set. SetBandSound and SetBandRule touch no edge, so they have nothing to normalize; SetBand, AddBand
-- and RemoveBand, which can, normalize after the write.
--
-- A BAND MAY CARRY A RULE (dynamic-bands plan): `band.rule = { type = "spell", role, spells? }`,
-- `{ type = "gap" }` or `{ type = "beyond" }`; its yards stay, as the band's fallback. Resolve, given
-- the unit, walks the bands in order and takes the first that holds:
--   a yard band (no rule, or one it cannot read) holds when the bracket falls in its yards;
--   spell(role) holds on its anchor's true (NS.Range.RoleInRange); on a nil it is a yard band;
--   gap holds when the ranged anchor says false, the melee anchor does not say true and a shorter
--     check confirms the unit is near (NS.Range.Near);
--   beyond holds when every spell band's anchor said false and no gap holds.
-- When none holds, the band the yards pick is taken unless that band's own anchor contradicts it
-- (a spell band whose anchor said false, a gap band while an anchor says true): then, as with no
-- bracket, the answer is "unknown", never out of range. A set with no rule reads its yards alone
-- and asks no spell.
--
-- Two of the registry's helpers are the load pass's too (architecture-§5): the seed routine (Seed)
-- and the per-set repair (NormalizeSet), both called from core/Database.lua's PrepareProfile. A third,
-- ConvertSet, is the v1 -> v2 migration step's (core/Database.lua): it gives each band of a stored set
-- the rule its yards suggest.

NS.BandSets = NS.BandSets or {}
local BandSets = NS.BandSets

local L = NS.L
local HUGE = math.huge

local function profile()
    return NS.db and NS.db.profile
end

local function copy(v) return NS.Database.DeepCopy(v) end

local function announce()
    NS.bus:SendMessage(NS.MSG.BANDSETS_CHANGED)
end

-- ---------------------------------------------------------------------------
-- Normalizing
-- ---------------------------------------------------------------------------

--- A usable yard: a finite number, or nil.
local function yard(v)
    if type(v) ~= "number" or v ~= v or v == HUGE or v == -HUGE then return nil end
    return v
end

--- One stored band, repaired: edges read as yards (a reversed pair swapped, `from` clamped to 0), the
--- template's fields filled. Answers nil for an entry that is not a band or has no width.
local function sanitizeBand(b, index)
    if type(b) ~= "table" then return nil end
    local from, to = yard(b.from) or 0, yard(b.to)
    if to and to < from then from, to = to, from end
    if from < 0 then from = 0 end
    if to and to <= from then return nil end
    local out = copy(b)
    NS.Database.Backfill(out, NS.BAND_TEMPLATE, true)
    out.from, out.to = from, to
    if type(out.label) ~= "string" then out.label = tostring(out.label or "") end
    if type(out.sound) ~= "string" then out.sound = nil end
    out._pos = index
    return out
end

--- Sort order: by `from`, then by `to` (open-ended last), then by input position, so equal edges keep
--- the order the player gave them.
local function byEdge(a, b)
    if a.from ~= b.from then return a.from < b.from end
    local at, bt = a.to or HUGE, b.to or HUGE
    if at ~= bt then return at < bt end
    return a._pos < b._pos
end

--- Chain the sorted bands: each starts where the kept one before it ends (the first at 0), an
--- open-ended band that is not last ends where the next one starts, a band left with no width is
--- dropped, and the last kept band is open-ended.
local function chain(sorted)
    local out = {}
    for i, b in ipairs(sorted) do
        local nextBand = sorted[i + 1]
        if b.to == nil and nextBand then b.to = nextBand.from end
        b.from = out[#out] and out[#out].to or 0
        if b.to == nil or b.to > b.from then out[#out + 1] = b end
    end
    if #out == 0 then out[1] = copy(NS.BAND_TEMPLATE) end
    out[#out].to = nil
    for _, b in ipairs(out) do b._pos = nil end
    return out
end

--- A normalized copy of `bands` (any input; see the file header for the guarantee).
--- @return table
function BandSets.NormalizeBands(bands)
    local sorted = {}
    for i, b in ipairs(type(bands) == "table" and bands or {}) do
        sorted[#sorted + 1] = sanitizeBand(b, i)
    end
    table.sort(sorted, byEdge)
    return chain(sorted)
end

--- Repair one stored set in place: the template filled, matchBy and the unknown band made readable,
--- the bands normalized. The load pass and every writer below call it.
function BandSets.NormalizeSet(set)
    NS.Database.Backfill(set, NS.BANDSET_TEMPLATE, true)
    if set.matchBy ~= "max" and set.matchBy ~= "min" then set.matchBy = "max" end
    if type(set.name) ~= "string" then set.name = tostring(set.name) end
    if type(set.unknown.label) ~= "string" then set.unknown.label = NS.Constants.UNKNOWN_LABEL end
    set.bands = BandSets.NormalizeBands(set.bands)
    return set
end

--- The rule schema v2 gives band `i` of a normalized set from its yards (ConvertSet), or nil (yards).
--- `ranged` is the index of the outermost band whose far edge is 20 to 45 yd: only that one asks the
--- ranged anchor, because the first band that holds wins and a nearer one would take every true.
local function suggestedRule(bands, i, ranged, friendly)
    local b = bands[i]
    if i == #bands and b.to == nil then return { type = "beyond" } end
    if i == 1 and b.to and b.to <= 5 then return { type = "spell", role = "melee" } end
    if i > 1 and b.from == 5 and b.to == 8 and bands[i + 1] then return { type = "gap" } end
    if i == ranged then return { type = "spell", role = friendly and "friendly" or "ranged" } end
    return nil
end

--- Convert one stored set to rule bands, in place (core/Database.lua's step to v2; the plan's D4):
--- the last, open-ended band is `beyond`; a first band ending at 5 yd or less is `spell(melee)`; a
--- 5 to 8 yd band with a band after it is `gap`; the outermost band whose far edge is 20 to 45 yd is
--- `spell(ranged)`, or `spell(friendly)` when `friendly` (a set used only as a friendly override, or
--- named Healer); any other band stays a yard band. The set is normalized first; no yard moves. A
--- band that already carries a rule table keeps it, so a second run changes nothing.
function BandSets.ConvertSet(set, friendly)
    BandSets.NormalizeSet(set)
    local bands, ranged = set.bands, nil
    for i = 1, #bands do
        local to = bands[i].to
        if to and to >= 20 and to <= 45 then ranged = i end
    end
    for i = 1, #bands do
        if type(bands[i].rule) ~= "table" then bands[i].rule = suggestedRule(bands, i, ranged, friendly) end
    end
    return set
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- The first stored id in `p.bandSetOrder` that names a set, or nil.
local function defaultIdOf(p)
    if not (p and p.bandSetOrder and p.bandSets) then return nil end
    for _, id in ipairs(p.bandSetOrder) do
        if p.bandSets[id] then return id end
    end
    return nil
end

--- The default band set's id: the first in the order.
function BandSets.DefaultId()
    return defaultIdOf(profile())
end

--- The stored set `id` (the live table), or nil.
function BandSets.Get(id)
    local p = profile()
    return p and p.bandSets and p.bandSets[id]
end

--- The set ids in order, as a new array.
function BandSets.List()
    local p, out = profile(), {}
    for i, id in ipairs(p and p.bandSetOrder or {}) do out[i] = id end
    return out
end

--- The band the yards pick for a known bracket, or nil. matchBy "max" picks by the far bound (an
--- open-ended bracket reads as infinitely far) and a band holds (from, to]; "min" picks by the near
--- bound and a band holds [from, to).
local function yardPick(set, minYd, maxYd)
    local byMin = set.matchBy == "min"
    local v
    if byMin then v = minYd or 0 else v = maxYd or HUGE end
    if type(v) ~= "number" then return nil end
    local bands = set.bands
    for i = 1, #bands do
        local to = bands[i].to
        if to == nil or v < to or (not byMin and v == to) then return i end
    end
    return #bands
end

local RULE_TYPES = { spell = true, gap = true, beyond = true }

--- The band's rule when it is one Resolve can read, else nil (a yard band).
local function ruleOf(band)
    local r = band.rule
    if type(r) ~= "table" or not RULE_TYPES[r.type] then return nil end
    if r.type == "spell" and type(r.role) ~= "string" then return nil end
    return r
end

local function hasRule(bands)
    for i = 1, #bands do
        if ruleOf(bands[i]) then return true end
    end
    return false
end

-- One Resolve's reading, reused (Resolve never re-enters): each spell band's answer, NONE for nil.
local NONE = {}
local answers = {}
local cur = { bands = nil, unit = nil, state = nil, maxYd = nil, gap = nil }

local function answerOf(i, rule)
    local v = answers[i]
    if v == nil then
        v = NS.Range.RoleInRange(rule.role, cur.unit, rule.spells)
        if v == nil then v = NONE end
        answers[i] = v
    end
    if v == NONE then return nil end
    return v
end

--- The dead zone's test, asked once a Resolve.
local function gapHolds()
    if cur.gap == nil then
        local R, unit = NS.Range, cur.unit
        cur.gap = R.RoleInRange("ranged", unit) == false and R.RoleInRange("melee", unit) ~= true
            and R.Near(unit, cur.state, cur.maxYd) == true
    end
    return cur.gap
end

local function beyondHolds()
    local bands, any = cur.bands, false
    for i = 1, #bands do
        local r = ruleOf(bands[i])
        if r and r.type == "spell" then
            if answerOf(i, r) ~= false then return false end
            any = true
        elseif r and r.type == "gap" and gapHolds() then
            return false
        end
    end
    return any
end

--- Whether band `i`'s own rule says the unit is not in it, so its yards may not be taken.
local function contradicts(i)
    local r = ruleOf(cur.bands[i])
    if not r then return false end
    if r.type == "spell" then return answerOf(i, r) == false end
    if r.type == "gap" then
        local R = NS.Range
        return R.RoleInRange("ranged", cur.unit) == true or R.RoleInRange("melee", cur.unit) == true
    end
    return false
end

--- Whether band `i` holds (see A BAND MAY CARRY A RULE in the header); `pick` is the yards' band.
local function holds(i, pick)
    local r = ruleOf(cur.bands[i])
    if r and r.type == "spell" then
        local v = answerOf(i, r)
        if v ~= nil then return v end
    elseif r and r.type == "gap" then
        return gapHolds()
    elseif r then
        return beyondHolds()
    end
    return pick == i
end

local function resolveRules(bands, pick, state, maxYd, unit)
    for i = 1, #bands do answers[i] = nil end
    cur.bands, cur.unit, cur.state, cur.maxYd, cur.gap = bands, unit, state, maxYd, nil
    local out = "unknown"
    for i = 1, #bands do
        if holds(i, pick) then
            out = i
            break
        end
    end
    if out == "unknown" and pick and not contradicts(pick) then out = pick end
    cur.bands, cur.unit = nil, nil
    return out
end

--- The band a bracket falls in. `state` is NS.Range.Get's: "none" answers nil, "unknown" (or a set
--- with nothing to read) answers "unknown", "known" answers the band's index (yardPick). A set
--- with band rules is read through them for `unit` first (see the header). A set id that does not
--- exist reads the default.
--- @param unit string|nil the unit token the bracket is for; without one every rule is no answer
--- @return number|string|nil
function BandSets.Resolve(setId, state, minYd, maxYd, unit)
    if state == "none" then return nil end
    local set = BandSets.Get(setId) or BandSets.Get(BandSets.DefaultId())
    if not set or #set.bands == 0 then return "unknown" end
    local pick = state == "known" and yardPick(set, minYd, maxYd) or nil
    if not hasRule(set.bands) then return pick or "unknown" end
    return resolveRules(set.bands, pick, state, maxYd, unit)
end

--- The set a container uses for `unit`: its friendly override when one is set, exists and the client
--- says the unit is friendly; else its own set when that exists; else the default.
function BandSets.ForUnit(container, unit)
    local p = profile()
    local sets = p and p.bandSets or {}
    local friendly = container.bandSetFriendly
    if friendly ~= nil and sets[friendly] and NS.Compat.IsFriend(unit) == true then return friendly end
    if container.bandSet ~= nil and sets[container.bandSet] then return container.bandSet end
    return BandSets.DefaultId()
end

-- ---------------------------------------------------------------------------
-- Writing (the registry's one runtime writer)
-- ---------------------------------------------------------------------------

--- Mint the next id and store `set` under it, after `afterId` in the order when given, else last.
local function insert(p, set, afterId)
    local id = p.nextBandSetId or 1
    p.nextBandSetId = id + 1
    p.bandSets[id] = set
    local pos = #p.bandSetOrder + 1
    for i, other in ipairs(p.bandSetOrder) do
        if other == afterId then pos = i + 1 end
    end
    table.insert(p.bandSetOrder, pos, id)
    return id
end

--- A trimmed non-empty name, or nil.
local function cleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return name
end

--- A name no other set uses: `base`, else `base 2`, `base 3`, ... Names that differ only in case are
--- taken, because `/rm bands <name>` matches without case (as NS.CM.UniqueName for containers).
--- `exceptId`'s own name is free (a rename to itself).
function BandSets.UniqueName(base, exceptId)
    base = cleanName(base) or L["New band set"]
    local taken, p = {}, profile()
    for id, set in pairs(p and p.bandSets or {}) do
        if id ~= exceptId and type(set.name) == "string" then taken[set.name:lower()] = true end
    end
    if not taken[base:lower()] then return base end
    local n = 2
    while taken[("%s %d"):format(base, n):lower()] do n = n + 1 end
    return ("%s %d"):format(base, n)
end

--- A new set from a preset key, a bands array, or nothing (Melee / Ranged). Nil for an unknown key.
local function build(name, arg)
    local set = copy(NS.BANDSET_TEMPLATE)
    local preset = NS.BandSetPresets[arg == nil and "melee_ranged" or arg]
    if type(arg) == "table" then
        set.bands = copy(arg)
    elseif type(preset) == "table" and preset.bands then
        set.bands, set.matchBy = copy(preset.bands), preset.matchBy
    else
        return nil
    end
    set.name = cleanName(name) or (type(arg) ~= "table" and preset.name) or L["New band set"]
    return BandSets.NormalizeSet(set)
end

--- Create a set. Answers its id, or nil for an unknown preset key or before the db exists.
function BandSets.Create(name, bandsOrPresetKey)
    local p = profile()
    if not (p and p.bandSets) then return nil end
    local set = build(name, bandsOrPresetKey)
    if not set then return nil end
    set.name = BandSets.UniqueName(set.name)
    local id = insert(p, set)
    announce()
    return id
end

--- Duplicate set `id` (deep-copied) right after it, named "<name> copy" (made unique). Answers the
--- new id, or nil.
function BandSets.Duplicate(id)
    local p = profile()
    local src = p and p.bandSets and p.bandSets[id]
    if not src then return nil end
    local set = BandSets.NormalizeSet(copy(src))
    set.name = BandSets.UniqueName(L["%s copy"]:format(src.name))
    local newId = insert(p, set, id)
    announce()
    return newId
end

--- Rename set `id` (trimmed, made unique against the others). Refuses a blank name or an unknown id.
function BandSets.Rename(id, name)
    local set = BandSets.Get(id)
    name = cleanName(name)
    if not (set and name) then return false end
    set.name = BandSets.UniqueName(name, id)
    announce()
    return true
end

--- Re-normalize set `id` after an edit to its bands.
function BandSets.Normalize(id)
    local set = BandSets.Get(id)
    if not set then return false end
    BandSets.NormalizeSet(set)
    announce()
    return true
end

--- Put LSM sound key `sound` on band `bandIndex` of set `id` (nil clears it). Refuses an unknown set,
--- a band the set does not have and a sound that is neither a string nor nil.
function BandSets.SetBandSound(id, bandIndex, sound)
    local set = BandSets.Get(id)
    local band = set and set.bands[bandIndex]
    if not band or (sound ~= nil and type(sound) ~= "string") then return false end
    band.sound = sound
    announce()
    return true
end

--- The set fields SetField writes, and the check each value passes. The name is Rename's.
local SET_FIELDS = {
    matchBy = function(v) return v == "max" or v == "min" end,
    ["unknown.label"] = function(v) return type(v) == "string" end,
    ["unknown.color"] = function(v) return type(v) == "table" end,
}

--- Store one field of set `id` (the settings pages' and `/rm set bandSet.<field>`'s writer).
--- Refuses an unknown set, a field not in SET_FIELDS and a value its check rejects.
function BandSets.SetField(id, field, value)
    local set = BandSets.Get(id)
    local check = SET_FIELDS[field]
    if not (set and check and check(value)) then return false end
    if field == "matchBy" then
        set.matchBy = value
    else
        set.unknown[field:match("^unknown%.(.+)$")] = copy(value)
    end
    announce()
    return true
end

--- The band fields SetBand writes besides `to`, and the type each holds.
local BAND_FIELDS = { label = "string", frameColor = "table", textColor = "table", indicatorColor = "table" }

--- Whether `to` is a usable far edge for band `i` of `bands`: past the band's own start and short of
--- the next band's far edge, so no band is left without width. The last band is always open-ended.
local function edgeFits(bands, i, to)
    local b, nextBand = bands[i], bands[i + 1]
    if not (nextBand and yard(to)) or to <= b.from then return false end
    return nextBand.to == nil or to < nextBand.to
end

--- Store one field of band `bandIndex` of set `id`: its far edge `to` (the next band starts there),
--- its label, or one of its three colors. Refuses an unknown set or band, an unknown field, a value of
--- the wrong type and an edge that would leave a band without width.
function BandSets.SetBand(id, bandIndex, field, value)
    local set = BandSets.Get(id)
    local band = set and set.bands[bandIndex]
    if not band then return false end
    if field == "to" then
        if not edgeFits(set.bands, bandIndex, value) then return false end
        band.to = value
        BandSets.NormalizeSet(set)
    elseif BAND_FIELDS[field] and type(value) == BAND_FIELDS[field] then
        band[field] = copy(value)
    else
        return false
    end
    announce()
    return true
end

--- The roles a spell rule names (defaults/SpellSeeds.lua's anchor lists).
local ROLES = { melee = true, ranged = true, friendly = true }

--- A spell override list SetBandRule takes: nil, or a non-empty array of whole spell IDs from 1.
local function spellList(v)
    if v == nil then return true end
    if type(v) ~= "table" or #v == 0 then return false end
    for _, id in ipairs(v) do
        if type(id) ~= "number" or id < 1 or id % 1 ~= 0 then return false end
    end
    return true
end

--- Whether `rule` is one SetBandRule stores: nil (a yard band), gap, beyond, or spell(role, spells?).
local function ruleFits(rule)
    if rule == nil then return true end
    if type(rule) ~= "table" or not RULE_TYPES[rule.type] then return false end
    if rule.type ~= "spell" then return true end
    return ROLES[rule.role] == true and spellList(rule.spells)
end

--- Store band `bandIndex`'s rule in set `id` (the Band sets page's Defined by, role and spell
--- override): nil makes it a yard band, `{ type = "gap" }` a dead zone, `{ type = "beyond" }` the band
--- past the last spell band, `{ type = "spell", role, spells? }` a spell band. The stored rule is a
--- fresh copy holding only those fields, so a band's own `spells` list is never the caller's table
--- (modules/Range.lua caches a band's list by table until the next rebuild). The yards never move.
--- Refuses an unknown set or band and a rule ruleFits rejects.
function BandSets.SetBandRule(id, bandIndex, rule)
    local set = BandSets.Get(id)
    local band = set and set.bands[bandIndex]
    if not (band and ruleFits(rule)) then return false end
    if rule == nil then
        band.rule = nil
    elseif rule.type == "spell" then
        band.rule = { type = "spell", role = rule.role, spells = rule.spells and copy(rule.spells) or nil }
    else
        band.rule = { type = rule.type }
    end
    announce()
    return true
end

--- How wide a band AddBand splits off the open-ended last one, in yards.
local NEW_BAND_WIDTH = 5

--- Add a band to set `id`, split off the front of its open-ended last band, colored by its place on
--- the ramp. Answers the new band's index, or nil.
function BandSets.AddBand(id)
    local set = BandSets.Get(id)
    if not set then return nil end
    local bands = set.bands
    local last = bands[#bands]
    local band = copy(NS.BAND_TEMPLATE)
    local ramp = NS.Constants.BAND_RAMP
    local hex = ramp[math.min(#bands, #ramp)]
    band.from, band.to = last.from, last.from + NEW_BAND_WIDTH
    band.frameColor = NS.Constants.HexColor(hex)
    band.textColor, band.indicatorColor = copy(band.frameColor), copy(band.frameColor)
    last.from = band.to
    table.insert(bands, #bands, band)
    BandSets.NormalizeSet(set)
    announce()
    return #set.bands - 1
end

--- Remove band `bandIndex` of set `id`; the band after it starts where the removed one did. Refuses
--- the last band left.
function BandSets.RemoveBand(id, bandIndex)
    local set = BandSets.Get(id)
    if not (set and set.bands[bandIndex]) or #set.bands <= 1 then return false end
    table.remove(set.bands, bandIndex)
    BandSets.NormalizeSet(set)
    announce()
    return true
end

--- Point every container reference to `id` at `target`. The friendly override follows only a set the
--- caller named; otherwise it falls away, and the container uses its own set for every reaction.
--- Through the container registry's one writer, NS.CM.SetField (architecture-§5), whose type check
--- passes: `id` is already gone and `target` is a survivor. Its apply request coalesces.
local function reassign(id, target, named)
    local CM = NS.CM
    for _, cid in ipairs(CM.List()) do
        local c = CM.Get(cid)
        if type(c) == "table" then
            if c.bandSet == id then CM.SetField(cid, "bandSet", target) end
            if c.bandSetFriendly == id then CM.SetField(cid, "bandSetFriendly", named and target or nil) end
        end
    end
end

--- Delete set `id`; the containers on it move to `reassignTo` when that names another set, else to
--- the default. Refuses an unknown id and the last set.
function BandSets.Delete(id, reassignTo)
    local p = profile()
    if not (p and p.bandSets and p.bandSets[id]) or #p.bandSetOrder <= 1 then return false end
    p.bandSets[id] = nil
    for i = #p.bandSetOrder, 1, -1 do
        if p.bandSetOrder[i] == id then table.remove(p.bandSetOrder, i) end
    end
    local named = reassignTo ~= nil and reassignTo ~= id and p.bandSets[reassignTo] ~= nil
    reassign(id, named and reassignTo or defaultIdOf(p), named)
    announce()
    return true
end

--- The seed routine (the load pass calls it on a profile with no band set): the four presets, the
--- player's class default first, so it is the default set. Announces nothing: no reader is up yet.
--- @return number  how many sets were seeded
function BandSets.Seed(p)
    if defaultIdOf(p) then return 0 end
    local first = NS.BandSetPresets.DefaultFor(NS.Compat.PlayerClass())
    local n = 0
    local keys = { first }
    for _, key in ipairs(NS.BandSetPresets.ORDER) do
        if key ~= first then keys[#keys + 1] = key end
    end
    for _, key in ipairs(keys) do
        insert(p, build(nil, key))
        n = n + 1
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Snapshot (a preset's one-level Undo, modules/Presets.lua through NS.CM.Snapshot)
-- ---------------------------------------------------------------------------

local SNAPSHOT_FIELDS = { "bandSets", "bandSetOrder", "nextBandSetId" }

--- A deep copy of the band-set registry, in the shape RestoreSnapshot takes. Nil with no profile.
function BandSets.Snapshot()
    local p = profile()
    if type(p) ~= "table" then return nil end
    local snap = {}
    for _, field in ipairs(SNAPSHOT_FIELDS) do snap[field] = copy(p[field]) end
    return snap
end

--- Put snapshot `snap` back: the sets and their order replaced by copies, ids kept (a container
--- names its set by id), every set normalized. The id counter is never rewound (the higher of its own
--- and the snapshot's), so an id is never reused. Refuses a snapshot with no set in it, because the
--- registry is never left empty.
function BandSets.RestoreSnapshot(snap)
    local p = profile()
    if type(p) ~= "table" or type(snap) ~= "table" or not defaultIdOf(snap) then return false end
    local counter = math.max(tonumber(p.nextBandSetId) or 1, tonumber(snap.nextBandSetId) or 1)
    for _, field in ipairs(SNAPSHOT_FIELDS) do p[field] = copy(snap[field]) end
    p.nextBandSetId = counter
    for _, set in pairs(p.bandSets) do BandSets.NormalizeSet(set) end
    announce()
    return true
end
