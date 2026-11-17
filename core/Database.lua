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
--- @return number  how many leaves were filled
function Database.Backfill(dst, template)
    local filled = 0
    for k, tv in pairs(template) do
        local dv = dst[k]
        if dv == nil then
            dst[k] = Database.DeepCopy(tv)
            filled = filled + 1
        elseif type(tv) == "table" and type(dv) == "table" then
            filled = filled + Database.Backfill(dv, tv)
        end
    end
    return filled
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
-- stamp and advances it only past a step that returned without raising. v0.1.0 ships the first data
-- shape, so there is nothing to migrate from yet and the ladder is empty: the stamp stays 0, which is
-- also the declared default (AceDB strips a stored value equal to it at logout, so 0 is safe).
local SCHEMA_STEPS = {}

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

--- Run the ladder, then backfill the active profile from the defaults, before anything reads it.
function NS:RunMigrations()
    local g = NS.db and NS.db.global
    if not g then return end
    g.schemaVersion = g.schemaVersion or 0
    climbLadder(g)
    if type(NS.db.profile) == "table" then Database.Backfill(NS.db.profile, NS.defaults.profile) end
end
