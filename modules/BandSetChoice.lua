local _, NS = ...
-- modules/BandSetChoice.lua — the band set a container uses is the character's own (spec
-- docs/superpowers/specs/2026-11-26-band-set-per-character-design.md; the owner, 2026-11-26: "Band set
-- selection for a single Ace3 profile should be tied to the character you are on"). The one runtime
-- writer of the character store below (architecture-§5).
--
--   NS.BandSetChoice.HasStore() -> boolean            a character scope exists (real AceDB)
--   NS.BandSetChoice.Set(cid, field, setId?) -> boolean   field "bandSet" | "bandSetFriendly"
--   NS.BandSetChoice.Read(cid, c, field) -> handled, value   the Containers page rows' read
--   NS.BandSetChoice.Hostile(cid, c) -> setId          the set container `c` (id `cid`) uses
--   NS.BandSetChoice.Friendly(cid, c) -> setId | nil   its friendly override, nil: the hostile set
--   NS.BandSetChoice.FallbackId(c) -> setId            what a container with no pick uses
--   NS.BandSetChoice.CharacterDefaultId() -> setId     this character's default ("(default)")
--   NS.BandSetChoice.Forget(setId, target?)            a band set was deleted
--   NS.BandSetChoice.CopyContainer(fromId, toId, fields?)   a container copy or duplicate
--   NS.BandSetChoice.CopyProfile(source, dest), ForgetProfile(name)   the AceDB profile events
--   NS.BandSetChoice.Prepare()                         the load pass: prune this character's picks
--   NS.BandSetChoice.Migrate(db)                       schema v5 (core/Database.lua)
--   NS.BandSetChoice.Invalidate()                      drop the class-set cache
--
-- THE STORE: db.char.bandSetChoice[<profile name>][<container id>] = { hostile?, friendly? }.
-- db.char is one table per character, shared by every profile, and container ids repeat across
-- profiles, so the profile's name comes first (spec C1). `hostile` is a set id; `friendly` is a set
-- id, `false` (Same as Band set) or nil (no pick: the profile's own field). Every character's store is
-- also reachable as db.sv.char[<charKey>] (real AceDB-3.0), so a delete or a profile event reaches all
-- of them (spec C4).
--
-- THE RESOLUTION (spec section 2). Hostile: the character's pick; else this character's class
-- default (the first set whose `origin` is DefaultFor(class, spec), else DefaultFor(class)); else the
-- container's profile field; else the default set. Friendly: the character's pick (false: the hostile
-- set); else the profile's bandSetFriendly; else the hostile set. Nothing is written back (spec C3).
--
-- WITHOUT A CHARACTER STORE (the no-AceDB fallback and the test kit's AceDB fake, spec C8) the profile
-- fields are the selection, exactly as before: Read answers unhandled, Set refuses, and the resolution
-- skips the class default.

NS.BandSetChoice = NS.BandSetChoice or {}
local Choice = NS.BandSetChoice

local FIELD = { bandSet = "hostile", bandSetFriendly = "friendly" }

local function profile()
    return NS.db and NS.db.profile
end

local function sets()
    local p = profile()
    return p and type(p.bandSets) == "table" and p.bandSets or {}
end

--- Whether a character scope exists to hold picks.
function Choice.HasStore()
    return NS.db ~= nil and type(NS.db.char) == "table"
end

--- The active profile's name, or nil.
local function profileName(db)
    db = db or NS.db
    if not db then return nil end
    if type(db.keys) == "table" and type(db.keys.profile) == "string" then return db.keys.profile end
    if type(db.GetCurrentProfile) == "function" then return db:GetCurrentProfile() end
    return nil
end

--- `t[k]` as a table, made when `create` and missing; nil otherwise.
local function sub(t, k, create)
    if type(t) ~= "table" or k == nil then return nil end
    local v = t[k]
    if type(v) ~= "table" then
        if not create then return nil end
        v = {}
        t[k] = v
    end
    return v
end

--- This character's picks for the active profile (made when `create`), or nil.
local function mine(create)
    if not Choice.HasStore() then return nil end
    return sub(sub(NS.db.char, "bandSetChoice", create), profileName(), create)
end

--- Call `fn(byProfile)` with each character's bandSetChoice table: every store under db.sv.char and
--- the current one, each once.
local function eachCharacter(fn)
    local db, seen = NS.db, {}
    local function visit(store)
        local bsc = type(store) == "table" and store.bandSetChoice
        if type(bsc) == "table" and not seen[bsc] then
            seen[bsc] = true
            fn(bsc)
        end
    end
    if type(db) ~= "table" then return end
    if type(db.sv) == "table" and type(db.sv.char) == "table" then
        for _, store in pairs(db.sv.char) do visit(store) end
    end
    visit(db.char)
end

-- ---------------------------------------------------------------------------
-- The class default (cached until the band sets, the spec or the profile change)
-- ---------------------------------------------------------------------------

local cache = { valid = false, id = nil }

function Choice.Invalidate()
    cache.valid, cache.id = false, nil
end

--- The first set in the order whose origin is `key`, or nil.
local function firstFrom(p, key)
    for _, id in ipairs(p.bandSetOrder or {}) do
        local set = p.bandSets[id]
        if set and set.origin == key then return id end
    end
    return nil
end

--- The preset keys this character's class default is: the spec's, then the class's own.
local function classKeys()
    local P, C = NS.BandSetPresets, NS.Compat
    local class = C.PlayerClass()
    return P.DefaultFor(class, C.PlayerSpecID()), P.DefaultFor(class)
end

--- This character's class set in the active profile, or nil.
local function classSetId()
    local p = profile()
    if not (p and type(p.bandSets) == "table") then return nil end
    if cache.valid and (cache.id == nil or p.bandSets[cache.id]) then return cache.id end
    local spec, own = classKeys()
    cache.id = firstFrom(p, spec) or firstFrom(p, own)
    cache.valid = true
    return cache.id
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

local function defaultId()
    return NS.BandSets.DefaultId()
end

--- This character's default set: its class set, else the default set. Without a store, the default.
function Choice.CharacterDefaultId()
    return Choice.HasStore() and classSetId() or defaultId()
end

--- The set a container with no pick uses: the class set, else its profile field, else the default.
function Choice.FallbackId(c)
    local own = Choice.HasStore() and classSetId() or nil
    if own then return own end
    local field = type(c) == "table" and c.bandSet
    if field ~= nil and sets()[field] then return field end
    return defaultId()
end

--- This character's entry for container `cid`, or nil.
local function entry(cid)
    local t = cid ~= nil and mine(false)
    local e = t and t[cid]
    return type(e) == "table" and e or nil
end

function Choice.Hostile(cid, c)
    local e = entry(cid)
    local pick = e and e.hostile
    if pick ~= nil and sets()[pick] then return pick end
    return Choice.FallbackId(c)
end

function Choice.Friendly(cid, c)
    local e = entry(cid)
    local pick = e and e.friendly
    if pick == false then return nil end
    if pick ~= nil and sets()[pick] then return pick end
    local field = type(c) == "table" and c.bandSetFriendly
    if field ~= nil and sets()[field] then return field end
    return nil
end

--- The Containers page rows' read of `field` for container `cid`: (true, value) when this character's
--- store answers it, (false) when the profile field does. nil reads as the row's 0.
function Choice.Read(cid, c, field)
    if not (FIELD[field] and Choice.HasStore()) then return false end
    local e = entry(cid)
    if field == "bandSet" then
        local pick = e and e.hostile
        return true, (pick ~= nil and sets()[pick]) and pick or nil
    end
    return true, Choice.Friendly(cid, c)
end

-- ---------------------------------------------------------------------------
-- Writing (the store's one runtime writer)
-- ---------------------------------------------------------------------------

local function isEmpty(e)
    return e.hostile == nil and e.friendly == nil
end

--- Store this character's pick for container `cid`: `field` is "bandSet" (nil clears the pick) or
--- "bandSetFriendly" (nil stores Same as Band set). Refuses without a store, an unknown container or
--- field, and a set id that names no set.
function Choice.Set(cid, field, setId)
    local key = FIELD[field]
    if not (key and Choice.HasStore() and NS.CM.Get(cid)) then return false end
    if setId ~= nil and not sets()[setId] then return false end
    local t = mine(true)
    if not t then return false end
    local e = type(t[cid]) == "table" and t[cid] or {}
    if key == "friendly" and setId == nil then e.friendly = false else e[key] = setId end
    t[cid] = not isEmpty(e) and e or nil
    NS.Debug("BandSets", "%s for container %s on this character: %s", field, cid, tostring(setId))
    NS.CM.RequestApply()
    return true
end

--- Rewrite `e`'s references to `setId` to `target` (nil clears them).
local function repoint(e, setId, target)
    if e.hostile == setId then e.hostile = target end
    if e.friendly == setId then e.friendly = target end
end

--- Band set `setId` was deleted: every character's pick on it, in the active profile, moves to
--- `target` when one is named, else is cleared (that container then falls back, section 2).
function Choice.Forget(setId, target)
    local name = profileName()
    eachCharacter(function(bsc)
        local t = sub(bsc, name, false)
        if not t then return end
        local empty = {}
        for cid, e in pairs(t) do
            if type(e) == "table" then
                repoint(e, setId, target)
                if isEmpty(e) then empty[#empty + 1] = cid end
            end
        end
        for _, cid in ipairs(empty) do t[cid] = nil end
    end)
    Choice.Invalidate()
end

--- Copy every character's pick for container `fromId` onto `toId`: `fields` (default both) as
--- container field names, "bandSet" and "bandSetFriendly".
function Choice.CopyContainer(fromId, toId, fields)
    local name = profileName()
    fields = fields or { "bandSet", "bandSetFriendly" }
    eachCharacter(function(bsc)
        local t = sub(bsc, name, false)
        if not t then return end
        local src, dst = type(t[fromId]) == "table" and t[fromId] or {}, type(t[toId]) == "table" and t[toId] or {}
        for _, field in ipairs(fields) do
            local key = FIELD[field]
            if key then dst[key] = src[key] end
        end
        t[toId] = not isEmpty(dst) and dst or nil
    end)
end

--- A profile copy: every character's picks for `source` become its picks for `dest`.
function Choice.CopyProfile(source, dest)
    if source == nil or dest == nil or source == dest then return end
    eachCharacter(function(bsc)
        bsc[dest] = type(bsc[source]) == "table" and NS.Database.DeepCopy(bsc[source]) or nil
    end)
    Choice.Invalidate()
end

--- A profile reset or delete: every character's picks for profile `name` are forgotten.
function Choice.ForgetProfile(name)
    if name == nil then return end
    eachCharacter(function(bsc) bsc[name] = nil end)
    Choice.Invalidate()
end

--- Whether entry `e` of a stored pick table still means something, repaired in place: a pick that
--- names no set is dropped (a friendly `false` stays).
local function pruneEntry(e, known)
    if type(e) ~= "table" then return false end
    if e.hostile ~= nil and not known[e.hostile] then e.hostile = nil end
    if e.friendly ~= false and e.friendly ~= nil and not known[e.friendly] then e.friendly = nil end
    return not isEmpty(e)
end

--- The load pass (NS:RunMigrations, after PrepareProfile): this character's picks for the active
--- profile lose any container or set that no longer exists.
function Choice.Prepare()
    Choice.Invalidate()
    local p, t = profile(), mine(false)
    if not (t and p and type(p.containers) == "table") then return end
    local drop = {}
    for cid, e in pairs(t) do
        if not p.containers[cid] or not pruneEntry(e, sets()) then drop[#drop + 1] = cid end
    end
    for _, cid in ipairs(drop) do t[cid] = nil end
end

-- ---------------------------------------------------------------------------
-- Schema v5 (core/Database.lua): the migrating character keeps its pick (spec C7)
-- ---------------------------------------------------------------------------

--- Whether preset key `origin` is a class preset other than this character's own.
local function otherClass(origin, spec, own)
    if origin == nil or origin == spec or origin == own then return false end
    for _, key in ipairs(NS.BandSetPresets.CLASS_KEYS) do
        if key == origin then return true end
    end
    return false
end

--- Pin profile `p`'s container fields into `t` (one profile's picks), skipping another class's set.
local function pinProfile(p, t, spec, own)
    local stored = type(p.bandSets) == "table" and p.bandSets or {}
    for cid, c in pairs(type(p.containers) == "table" and p.containers or {}) do
        local set = type(c) == "table" and stored[c.bandSet]
        if type(set) == "table" and not otherClass(set.origin, spec, own) then
            local e = type(t[cid]) == "table" and t[cid] or {}
            if e.hostile == nil then e.hostile = c.bandSet end
            t[cid] = e
        end
    end
end

--- v4 -> v5: for every stored profile, the loading character's picks become the containers' fields.
function Choice.Migrate(db)
    if type(db) ~= "table" or type(db.char) ~= "table" then return end
    local spec, own = classKeys()
    local bsc = sub(db.char, "bandSetChoice", true)
    local seen = {}
    local function visit(name, p)
        if type(name) == "string" and type(p) == "table" and not seen[name] then
            seen[name] = true
            pinProfile(p, sub(bsc, name, true), spec, own)
        end
    end
    local current = profileName(db)
    if current then visit(current, db.profile) end
    for _, list in ipairs({ db.profiles, type(db.sv) == "table" and db.sv.profiles or nil }) do
        if type(list) == "table" then
            for name, p in pairs(list) do visit(name, p) end
        end
    end
    for name, t in pairs(bsc) do
        if type(t) == "table" and next(t) == nil then bsc[name] = nil end
    end
end
