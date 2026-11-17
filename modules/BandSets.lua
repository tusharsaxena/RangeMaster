local _, NS = ...
-- modules/BandSets.lua — the shared band sets (design spec 5.2, 5.3): the ONE runtime writer of the
-- band-set registry (profile.bandSets, bandSetOrder, nextBandSetId; architecture-§5) and the sole
-- sender of NS.MSG.BANDSETS_CHANGED.
--
--   NS.BandSets.Create(name, bandsOrPresetKey?) -> id     a preset key, a bands array, or nil (Melee / Ranged)
--   NS.BandSets.Delete(id, reassignTo?) -> boolean        never the last set
--   NS.BandSets.Duplicate(id) -> id, Rename(id, name) -> boolean
--   NS.BandSets.List() -> { id, ... }, Get(id) -> set, DefaultId() -> id, Normalize(id) -> boolean
--   NS.BandSets.Resolve(setId, state, minYd, maxYd) -> bandIndex | "unknown" | nil (state "none")
--   NS.BandSets.ForUnit(container, unit) -> setId
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
-- Duplicate and Normalize normalize on write; core/Database.lua's load pass normalizes every stored set.
--
-- Two of the registry's helpers are the load pass's too (architecture-§5): the seed routine (Seed)
-- and the per-set repair (NormalizeSet), both called from core/Database.lua's PrepareProfile.

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

--- The band a bracket falls in. `state` is NS.Range.Get's: "none" answers nil, "unknown" (or a set
--- with nothing to read) answers "unknown", "known" answers the band's index. matchBy "max" picks by
--- the far bound (an open-ended bracket reads as infinitely far) and a band holds (from, to]; "min"
--- picks by the near bound and a band holds [from, to). A set id that does not exist reads the default.
--- @return number|string|nil
function BandSets.Resolve(setId, state, minYd, maxYd)
    if state == "none" then return nil end
    local set = BandSets.Get(setId) or BandSets.Get(BandSets.DefaultId())
    if state ~= "known" or not set or #set.bands == 0 then return "unknown" end
    local byMin = set.matchBy == "min"
    local v
    if byMin then v = minYd or 0 else v = maxYd or HUGE end
    if type(v) ~= "number" then return "unknown" end
    local bands = set.bands
    for i = 1, #bands do
        local to = bands[i].to
        if to == nil or v < to or (not byMin and v == to) then return i end
    end
    return #bands
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
    local id = insert(p, set)
    announce()
    return id
end

--- Duplicate set `id` (deep-copied) right after it. Answers the new id, or nil.
function BandSets.Duplicate(id)
    local p = profile()
    local src = p and p.bandSets and p.bandSets[id]
    if not src then return nil end
    local set = BandSets.NormalizeSet(copy(src))
    set.name = L["%s copy"]:format(src.name)
    local newId = insert(p, set, id)
    announce()
    return newId
end

--- Rename set `id`. Refuses a blank name or an unknown id.
function BandSets.Rename(id, name)
    local set = BandSets.Get(id)
    name = cleanName(name)
    if not (set and name) then return false end
    set.name = name
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

--- Point every container reference to `id` at `target`. The friendly override follows only a set the
--- caller named; otherwise it falls away, and the container uses its own set for every reaction.
local function reassign(p, id, target, named)
    for _, c in pairs(p.containers or {}) do
        if type(c) == "table" then
            if c.bandSet == id then c.bandSet = target end
            if c.bandSetFriendly == id then c.bandSetFriendly = named and target or nil end
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
    reassign(p, id, named and reassignTo or defaultIdOf(p), named)
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

--- Put snapshot `snap` back: the sets, their order and the id counter replaced by copies, ids kept
--- (a container names its set by id), every set normalized. Refuses a snapshot with no set in it,
--- because the registry is never left empty.
function BandSets.RestoreSnapshot(snap)
    local p = profile()
    if type(p) ~= "table" or type(snap) ~= "table" or not defaultIdOf(snap) then return false end
    for _, field in ipairs(SNAPSHOT_FIELDS) do p[field] = copy(snap[field]) end
    for _, set in pairs(p.bandSets) do BandSets.NormalizeSet(set) end
    announce()
    return true
end
