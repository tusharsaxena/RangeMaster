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
--   NS.BandSetChoice.Assigned() -> setId | nil         this character's assignment (R4-RM-01)
--   NS.BandSetChoice.Assign(setId) -> boolean          "Use for this character" (the one manual writer)
--   NS.BandSetChoice.EnsureAssigned() -> setId | nil   the first-load writer (Prepare, the spec events)
--   NS.BandSetChoice.Forget(setId, target?, assignTo?)   a band set was deleted
--   NS.BandSetChoice.OthersUsing(setId) -> number      other characters on it (Used by)
--   NS.BandSetChoice.CopyContainer(fromId, toId, fields?)   a container copy or duplicate
--   NS.BandSetChoice.CopyProfile(source, dest), ForgetProfile(name)   the AceDB profile events
--   NS.BandSetChoice.Prepare()                         the load pass: prune this character's picks
--   NS.BandSetChoice.Migrate(db)                       schema v5 (core/Database.lua)
--   NS.BandSetChoice.MigrateAssigned(db)               schema v6: the assignment table
--   NS.BandSetChoice.Invalidate()                      drop the class-set cache
--
-- THE STORE: db.char.bandSetChoice[<profile name>][<container id>] = { hostile?, friendly? }.
-- db.char is one table per character, shared by every profile, and container ids repeat across
-- profiles, so the profile's name comes first (spec C1). `hostile` is a set id; `friendly` is a set
-- id, `false` (Same as Band set) or nil (no pick: the profile's own field). Every character's store is
-- also reachable as db.sv.char[<charKey>] (real AceDB-3.0), so a delete or a profile event reaches all
-- of them (spec C4).
--
-- THE ASSIGNMENT (R4-RM-01; the owner, round 4: "the right class specific bandset should be assigned
-- to that character", answered "One per character"): db.char.bandSetAssigned[<profile name>] = setId,
-- a table apart from bandSetChoice, so Prepare's per-container pruning never touches it. It is WRITTEN
-- ONCE, at the character's first load on a profile (EnsureAssigned, from Prepare): the first set whose
-- `origin` is DefaultFor(class, spec), else a new one made from that preset. A class whose default
-- needs its spec (a Devourer, NS.BandSetPresets.SpecDependent) waits while the spec reads nil, and
-- the first PLAYER_ENTERING_WORLD or spell/spec event that can read it writes it. It then never moves
-- by itself, not on a respec, a profile swap or a login: only "Use for this character" (Assign, the
-- Band sets page) and a delete of the set (Forget moves it to the delete's target) change it. A
-- profile copy copies every character's, and a reset or delete forgets them. This reverses spec C3
-- ("nothing is written back") for the hostile set a container with no pick uses.
--
-- THE RESOLUTION (spec section 2, R4-RM-01). Hostile: the character's pick; else its assignment;
-- else, while none is written (a deferred spec), the old chain: this character's class default (the
-- first set whose `origin` is DefaultFor(class, spec), else DefaultFor(class)); else the container's
-- profile field, unless that is another class's preset; else the first set that is not another
-- class's (BSC-REV); else the default set. Friendly: the character's pick (false: the hostile set);
-- else the profile's bandSetFriendly; else the hostile set.
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

--- Call `fn(store)` with each character's store: every one under db.sv.char and the current one,
--- each once.
local function eachStore(fn)
    local db, seen = NS.db, {}
    local function visit(store)
        if type(store) == "table" and not seen[store] then
            seen[store] = true
            fn(store)
        end
    end
    if type(db) ~= "table" then return end
    if type(db.sv) == "table" and type(db.sv.char) == "table" then
        for _, store in pairs(db.sv.char) do visit(store) end
    end
    visit(db.char)
end

--- Call `fn(byProfile)` with each character's bandSetChoice table.
local function eachCharacter(fn)
    eachStore(function(store)
        if type(store.bandSetChoice) == "table" then fn(store.bandSetChoice) end
    end)
end

--- Call `fn(byProfile)` with each character's bandSetAssigned table.
local function eachAssigned(fn)
    eachStore(function(store)
        if type(store.bandSetAssigned) == "table" then fn(store.bandSetAssigned) end
    end)
end

-- ---------------------------------------------------------------------------
-- The class default (cached until the band sets, the spec or the profile change)
-- ---------------------------------------------------------------------------

local cache = { valid = false }

function Choice.Invalidate()
    cache.valid = false
end

--- The class preset keys, as a set (CLASS_KEYS is fixed at load).
local classKeySet

--- Whether preset key `origin` is a class preset other than this character's own (`spec`, `own`).
local function otherClass(origin, spec, own)
    if origin == nil or origin == spec or origin == own then return false end
    if not classKeySet then
        classKeySet = {}
        for _, key in ipairs(NS.BandSetPresets.CLASS_KEYS) do classKeySet[key] = true end
    end
    return classKeySet[origin] == true
end

--- The first set in the order whose origin is `key`, or nil.
local function firstFrom(p, key)
    for _, id in ipairs(p.bandSetOrder or {}) do
        local set = p.bandSets[id]
        if set and set.origin == key then return id end
    end
    return nil
end

--- The first set in the order that is not another class's preset, or nil.
local function firstOwnable(p, spec, own)
    for _, id in ipairs(p.bandSetOrder or {}) do
        local set = p.bandSets[id]
        if set and not otherClass(set.origin, spec, own) then return id end
    end
    return nil
end

--- The preset keys this character's class default is: the spec's, then the class's own.
local function classKeys()
    local P, C = NS.BandSetPresets, NS.Compat
    local class = C.PlayerClass()
    return P.DefaultFor(class, C.PlayerSpecID()), P.DefaultFor(class)
end

--- This character's resolution in the active profile, or nil: `id` its class set, `generic` the first
--- set that is not another class's (BSC-REV: a class with no set of its own never lands on one),
--- `spec` and `own` its preset keys.
local function resolved()
    local p = profile()
    if not (p and type(p.bandSets) == "table") then return nil end
    local stale = (cache.id ~= nil and not p.bandSets[cache.id])
        or (cache.generic ~= nil and not p.bandSets[cache.generic])
    if not cache.valid or stale then
        local spec, own = classKeys()
        cache.spec, cache.own = spec, own
        cache.id = firstFrom(p, spec) or firstFrom(p, own)
        cache.generic = firstOwnable(p, spec, own)
        cache.valid = true
    end
    return cache
end

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

local function defaultId()
    return NS.BandSets.DefaultId()
end

-- ---------------------------------------------------------------------------
-- The assignment (R4-RM-01)
-- ---------------------------------------------------------------------------

--- This character's assignment table (made when `create`), or nil.
local function assignedTable(create)
    if not Choice.HasStore() then return nil end
    return sub(NS.db.char, "bandSetAssigned", create)
end

--- This character's assignment on the active profile, while it names a set; else nil.
function Choice.Assigned()
    local t, name = assignedTable(false), profileName()
    local id = t and name and t[name]
    if id ~= nil and sets()[id] then return id end
    return nil
end

--- Store `setId` as this character's assignment on the active profile ("Use for this character").
--- Refuses without a store or a profile name, and a set id that names no set.
function Choice.Assign(setId)
    local name = profileName()
    if not (name and setId ~= nil and sets()[setId]) then return false end
    local t = assignedTable(true)
    if not t then return false end
    t[name] = setId
    NS.Debug("BandSets", "band set %s assigned to this character on profile %s", tostring(setId), name)
    if NS.CM and NS.CM.RequestApply then NS.CM.RequestApply() end
    return true
end

--- Whether this character's default needs a spec the client cannot read yet (a Devourer at login).
local function specPending()
    local C = NS.Compat
    return C.PlayerSpecID() == nil and NS.BandSetPresets.SpecDependent(C.PlayerClass())
end

--- The first-load writer: when this character has no assignment that names a set on the active
--- profile, assign the first set from its class (or spec) preset, made from the preset when the
--- profile has none. Waits while the spec is pending. Answers the assignment (nil: none yet) and
--- whether this call wrote it.
function Choice.EnsureAssigned()
    local current = Choice.Assigned()
    if current then return current, false end
    local p, name = profile(), profileName()
    if not (Choice.HasStore() and name and p and type(p.bandSets) == "table") or specPending() then
        return nil, false
    end
    local key = classKeys()
    local id = firstFrom(p, key) or NS.BandSets.Create(nil, key)
    if id == nil then return nil, false end
    assignedTable(true)[name] = id
    Choice.Invalidate()
    NS.Debug("BandSets", "first load on profile %s: band set %s assigned (%s)", name, tostring(id), key)
    return id, true
end

--- The set a container with no pick uses (spec section 2, BSC-REV, R4-RM-01): this character's
--- assignment; else its class set; else the container's profile field unless it is another class's
--- set; else the first set that is not another class's; else the default set. Without a store, the
--- profile field, else the default.
function Choice.FallbackId(c)
    local assigned = Choice.Assigned()
    if assigned then return assigned end
    local r = Choice.HasStore() and resolved() or nil
    if r and r.id then return r.id end
    local field = type(c) == "table" and c.bandSet
    local set = field ~= nil and sets()[field]
    if set and not (r and otherClass(set.origin, r.spec, r.own)) then return field end
    return r and r.generic or defaultId()
end

--- This character's default set ("(default)"): the same chain with no container field.
function Choice.CharacterDefaultId()
    return Choice.FallbackId(nil)
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
--- `target` when one is named, else is cleared (that container then falls back, section 2). Every
--- character's assignment on it moves to `assignTo` (the set the delete moved the containers to), so a
--- character's next load never re-creates the preset the player deleted (R4-RM-01).
function Choice.Forget(setId, target, assignTo)
    local name = profileName()
    eachAssigned(function(bsa)
        if name ~= nil and bsa[name] == setId then bsa[name] = assignTo end
    end)
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

--- Whether character store `store` uses set `setId` on profile `name`: its assignment, or a pick on
--- one of the profile's containers.
local function storeUses(store, name, setId)
    local bsa = type(store.bandSetAssigned) == "table" and store.bandSetAssigned
    if bsa and bsa[name] == setId then return true end
    for _, e in pairs(sub(store.bandSetChoice, name, false) or {}) do
        if type(e) == "table" and (e.hostile == setId or e.friendly == setId) then return true end
    end
    return false
end

--- How many other characters (every store under db.sv.char but this one) are assigned set `setId`
--- or pick it on a container of the active profile: the Band sets page's Used by line counts them
--- (BSC-REV, R4-RM-01).
function Choice.OthersUsing(setId)
    local name, n = profileName(), 0
    if name == nil then return 0 end
    local own = Choice.HasStore() and NS.db.char or nil
    eachStore(function(store)
        if store ~= own and storeUses(store, name, setId) then n = n + 1 end
    end)
    return n
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

--- A profile copy: every character's picks and assignment for `source` become its own for `dest`.
function Choice.CopyProfile(source, dest)
    if source == nil or dest == nil or source == dest then return end
    eachCharacter(function(bsc)
        bsc[dest] = type(bsc[source]) == "table" and NS.Database.DeepCopy(bsc[source]) or nil
    end)
    eachAssigned(function(bsa) bsa[dest] = bsa[source] end)
    Choice.Invalidate()
end

--- A profile reset or delete: every character's picks and assignment for profile `name` are forgotten.
function Choice.ForgetProfile(name)
    if name == nil then return end
    eachCharacter(function(bsc) bsc[name] = nil end)
    eachAssigned(function(bsa) bsa[name] = nil end)
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

--- This character's picks for the active profile lose any container or set that no longer exists.
local function prunePicks()
    local p, t = profile(), mine(false)
    if not (t and p and type(p.containers) == "table") then return end
    local drop = {}
    for cid, e in pairs(t) do
        if not p.containers[cid] or not pruneEntry(e, sets()) then drop[#drop + 1] = cid end
    end
    for _, cid in ipairs(drop) do t[cid] = nil end
end

--- The load pass (NS:RunMigrations, after PrepareProfile): the picks are pruned, an assignment that
--- names no set is dropped, and a character with none is assigned (its first load, R4-RM-01).
function Choice.Prepare()
    Choice.Invalidate()
    prunePicks()
    local t, name = assignedTable(false), profileName()
    if t and name and t[name] ~= nil and not sets()[t[name]] then t[name] = nil end
    Choice.EnsureAssigned()
end

-- ---------------------------------------------------------------------------
-- Schema v5 (core/Database.lua): the migrating character keeps its pick (spec C7)
-- ---------------------------------------------------------------------------

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

--- v5 -> v6 (R4-RM-01): the loading character's assignment table. Its entries are written by each
--- character's own first load on each profile (EnsureAssigned): sv.char holds no class, so no step can
--- write another character's. A value that is not a table is replaced.
function Choice.MigrateAssigned(db)
    if type(db) ~= "table" or type(db.char) ~= "table" then return end
    sub(db.char, "bandSetAssigned", true)
end
