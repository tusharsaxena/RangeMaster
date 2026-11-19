local _, NS = ...
-- core/Database.lua — AceDB, the profile backfill and the schemaVersion migration runner
-- (savedvariables-§1). Called from core/RangeMaster.lua's OnInitialize and headlessly by the harness.
--
-- NOTHING HERE TOUCHES A FRAME. The defaults tree is defaults/Profile.lua's NS.defaults.

NS.Database = NS.Database or {}
local Database = NS.Database

--- Recursive copy. A table default is never handed out by reference.
function Database.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Database.DeepCopy(x) end
    return out
end

--- Fill every key `template` has and `dst` lacks, recursively. Tested with `== nil`, never `or`, so a
--- stored `false`, `0` or empty string is the player's choice and survives (savedvariables-§5).
---
--- An ARRAY in the template (a non-empty sequence, like a container's `elements.order`) is filled
--- whole when missing and never index by index: filling slot 3 of a stored two-name list with the
--- template's third name would duplicate an entry. A MAP the player fills (a spell list, the bands) is
--- empty in the template, so there is nothing to fill into it.
---
--- `repair`, for the load pass only: a stored value that is not a table where the template holds a
--- section (a hand-edited `visibility = "junk"`) is replaced by the template's section.
--- @return number  how many leaves were filled or repaired
function Database.Backfill(dst, template, repair)
    local filled = 0
    for k, tv in pairs(template) do
        local dv = dst[k]
        if dv == nil then
            dst[k] = Database.DeepCopy(tv)
            filled = filled + 1
        elseif type(tv) == "table" then
            if type(dv) ~= "table" then
                if repair then
                    dst[k] = Database.DeepCopy(tv)
                    filled = filled + 1
                end
            elseif #tv == 0 then
                filled = filled + Database.Backfill(dv, tv, repair)
            end
        end
    end
    return filled
end

-- ---------------------------------------------------------------------------
-- The registries' load pass (architecture-§5, savedvariables-§1)
-- ---------------------------------------------------------------------------
-- Two structural registries live in the profile: the containers (profile.containers, containerOrder,
-- nextContainerId; runtime writer modules/ContainerManager.lua, Task 4) and the band sets
-- (profile.bandSets, bandSetOrder, nextBandSetId; runtime writer modules/BandSets.lua), plus the
-- first-run sentinel profile.seeded (the container preset picker; runtime writer NS.CM.MarkSeeded,
-- which modules/Presets.lua's MarkPickerSeen calls). PrepareProfile is their
-- load pass: reached only from RunMigrations (InitDB and the AceDB profile callbacks), it repairs and
-- seeds and never applies a player's choice.

--- `t[k]` as a table, replacing anything else.
local function tableAt(t, k)
    if type(t[k]) ~= "table" then t[k] = {} end
    return t[k]
end

--- Re-key a registry's members by positive integer id: a numeric string key ("3") is moved to its
--- number, any other key or a member that is not a table is dropped. Keys are collected first,
--- because adding a key while `pairs` walks the table is not allowed.
local function rekey(members)
    local moves = {}
    for k, v in pairs(members) do
        local id = tonumber(k)
        if type(v) ~= "table" or not id or id < 1 or id % 1 ~= 0 then
            moves[#moves + 1] = { k }
        elseif id ~= k then
            moves[#moves + 1] = { k, id, v }
        end
    end
    for _, m in ipairs(moves) do
        members[m[1]] = nil
        if m[2] and members[m[2]] == nil then members[m[2]] = m[3] end
    end
end

--- Rebuild an order array to hold exactly the stored ids: dangling and duplicate ids dropped, orphans
--- appended in id order. Answers the new array and the highest id stored.
local function rebuildOrder(members, order)
    local seen, out, maxId = {}, {}, 0
    for _, id in ipairs(order) do
        id = tonumber(id)
        if id and members[id] and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    local orphans = {}
    for id in pairs(members) do
        if id > maxId then maxId = id end
        if not seen[id] then orphans[#orphans + 1] = id end
    end
    table.sort(orphans)
    for _, id in ipairs(orphans) do out[#out + 1] = id end
    return out, maxId
end

--- One registry: members re-keyed and backfilled from `template` (with repair), the order rebuilt,
--- the counter bumped past the highest stored id.
local function prepareRegistry(p, key, orderKey, counterKey, template)
    local members = tableAt(p, key)
    rekey(members)
    for _, m in pairs(members) do Database.Backfill(m, template, true) end
    local maxId
    p[orderKey], maxId = rebuildOrder(members, tableAt(p, orderKey))
    if type(p[counterKey]) ~= "number" or p[counterKey] <= maxId then p[counterKey] = maxId + 1 end
end

--- A container's `elements.order`: each known element once, unknown names dropped, any name a later
--- build added appended in the template's order.
local function repairElementOrder(c)
    local known, seen, out = {}, {}, {}
    for _, name in ipairs(NS.CONTAINER_TEMPLATE.elements.order) do known[name] = true end
    for _, name in ipairs(c.elements.order) do
        if known[name] and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    for _, name in ipairs(NS.CONTAINER_TEMPLATE.elements.order) do
        if not seen[name] then out[#out + 1] = name end
    end
    c.elements.order = out
end

--- The band sets: seeded on a profile with none, each normalized; then every container reference
--- that names no set is pointed at the default (a dangling friendly override falls away).
local function prepareBandSets(p)
    local BandSets = NS.BandSets
    if not BandSets then return end
    BandSets.Seed(p)
    for _, set in pairs(p.bandSets) do BandSets.NormalizeSet(set) end
    local default = p.bandSetOrder[1]
    for _, c in pairs(p.containers) do
        if c.bandSet == nil or not p.bandSets[c.bandSet] then c.bandSet = default end
        if c.bandSetFriendly ~= nil and not p.bandSets[c.bandSetFriendly] then c.bandSetFriendly = nil end
    end
end

--- Put a profile's registries into a shape every reader can trust. Idempotent: a second call changes
--- nothing.
function Database.PrepareProfile(p)
    if type(p) ~= "table" then return end
    prepareRegistry(p, "containers", "containerOrder", "nextContainerId", NS.CONTAINER_TEMPLATE)
    prepareRegistry(p, "bandSets", "bandSetOrder", "nextBandSetId", NS.BANDSET_TEMPLATE)
    for _, c in pairs(p.containers) do repairElementOrder(c) end
    if p.seeded == nil then p.seeded = false end
    prepareBandSets(p)
end

function NS:InitDB()
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if AceDB then
        NS.db = AceDB:New("RangeMasterDB", NS.defaults, true)
        if NS.db.RegisterCallback then
            -- A profile switch, copy or reset re-reads the latch and refreshes the panel; each is
            -- traced by its own handler, in the event's words (debug-logging-§10).
            NS.db.RegisterCallback(NS, "OnProfileChanged", function() NS.OnProfileChanged() end)
            NS.db.RegisterCallback(NS, "OnProfileCopied", function(_, _, source) NS.OnProfileCopied(source) end)
            NS.db.RegisterCallback(NS, "OnProfileReset", function() NS.OnProfileReset() end)
            -- Before a switch and before SavedVariables are written: a preset preview goes back.
            NS.db.RegisterCallback(NS, "OnProfileShutdown", function() NS.OnProfileShutdown() end)
            NS.db.RegisterCallback(NS, "OnDatabaseShutdown", function() NS.OnProfileShutdown() end)
        end
    end
    -- Soft fallback when AceDB is absent: a db-shaped table over the raw SavedVariables global, so the
    -- addon still loads and still answers its CLI (savedvariables-§1).
    if not NS.db then
        RangeMasterDB = RangeMasterDB or {}
        RangeMasterDB.profile = RangeMasterDB.profile or {}
        RangeMasterDB.global = RangeMasterDB.global or {}
        Database.Backfill(RangeMasterDB.profile, NS.defaults.profile)
        Database.Backfill(RangeMasterDB.global, NS.defaults.global)
        NS.db = { profile = RangeMasterDB.profile, global = RangeMasterDB.global }
    end
    NS:RunMigrations()
end

-- The migration ladder. Each step is idempotent against a fresh default profile; the runner owns the
-- stamp and advances it only past a step that returned without raising. The declared default stays 0
-- (AceDB strips a stored value equal to it at logout, so 0 is safe); a fresh install climbs every step
-- at once against a profile with no container, which changes nothing.

--- Every stored profile once: AceDB's db.profiles (the raw SavedVariables' table), the kit's db.sv
--- view of the same, and the active profile (the only one the soft fallback has).
local function eachProfile(db, fn)
    local seen = {}
    local function visit(p)
        if type(p) == "table" and not seen[p] then
            seen[p] = true
            fn(p)
        end
    end
    local function visitAll(list)
        if type(list) == "table" then
            for _, p in pairs(list) do visit(p) end
        end
    end
    visitAll(db.profiles)
    visitAll(type(db.sv) == "table" and db.sv.profiles)
    visit(db.profile)
end

--- v0 -> v1, the frame defaults: a new container's border is drawn at 25% and its dot is matte. A
--- container already stored keeps its look: full border opacity and the plain dot, where unset.
local function keepStoredLook(db)
    eachProfile(db, function(p)
        if type(p.containers) ~= "table" then return end
        for _, c in pairs(p.containers) do
            local border = type(c) == "table" and type(c.frame) == "table" and c.frame.border
            if type(border) == "table" and border.alpha == nil then border.alpha = 1 end
            local ind = type(c) == "table" and type(c.elements) == "table" and c.elements.indicator
            if type(ind) == "table" and ind.style == nil then ind.style = "plain" end
        end
    end)
end

local SCHEMA_STEPS = {
    { to = 1, apply = keepStoredLook },
}

--- The runner's target: the highest step's `to`, or 0 with no step.
NS.SCHEMA_VERSION = SCHEMA_STEPS[#SCHEMA_STEPS] and SCHEMA_STEPS[#SCHEMA_STEPS].to or 0
-- Suite seam: tests/test_database.lua drives the runner with steps of its own.
NS.__migrationSteps = SCHEMA_STEPS

--- Climb the ladder from `g.schemaVersion`. A step that raises stops the climb with the stamp where it
--- was, prints one line, and the next load retries from that step. Answers true when every step ran.
local function climbLadder(g)
    for _, step in ipairs(SCHEMA_STEPS) do
        if g.schemaVersion < step.to then
            local from = g.schemaVersion
            local ok, err = pcall(step.apply, NS.db)
            if not ok then
                NS.Debug("Migrate", "v%s -> v%s failed: %s", from, step.to, tostring(err))
                NS.Printf(NS.L["Settings upgrade stopped at v%s -> v%s; saved settings were left as they were."],
                    from, step.to)
                return false
            end
            NS.Debug("Migrate", "v%s -> v%s", from, step.to)
            g.schemaVersion = step.to
        end
    end
    return true
end

--- Run the ladder, then backfill the active profile from the defaults and run the registries' load
--- pass (PrepareProfile), before anything reads it.
function NS:RunMigrations()
    local g = NS.db and NS.db.global
    if not g then return end
    g.schemaVersion = g.schemaVersion or 0
    climbLadder(g)
    if type(NS.db.profile) == "table" then
        Database.Backfill(NS.db.profile, NS.defaults.profile)
        Database.PrepareProfile(NS.db.profile)
    end
end
