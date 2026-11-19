-- tests/test_database.lua — core/Database.lua: AceDB, the profile backfill and the migration runner
-- (savedvariables-§1, savedvariables-§5), and the AceDB profile callbacks in core/RangeMaster.lua.

local T = _G.RM_TEST
local NS = T.NS
local test, assertEqual, assertTrue, assertFalse, assertNil =
  T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertNil

local D = NS.Database

test("database: the account-wide schemaVersion default is 0 (savedvariables-§1)", function()
  -- 0, never the current version: AceDB strips a value equal to its default at logout and backfills
  -- the default onto a legacy account with no stamp.
  assertEqual(NS.defaults.global.schemaVersion, 0)
end)

test("database: the ladder holds one step, v0 -> v1 (the frame defaults), and a fresh install is stamped 1", function()
  -- Red under the v0.1.0 ladder, which was empty with a target of 0.
  assertEqual(#NS.__migrationSteps, 1, "one step")
  assertEqual(NS.__migrationSteps[1].to, 1, "the step climbs to v1")
  assertEqual(NS.SCHEMA_VERSION, 1, "the runner's target is the highest step's `to`")
  assertEqual(NS.db.global.schemaVersion, 1, "a fresh install is stamped at the target")
end)

test("database: RunMigrations is a safe no-op when the DB is absent", function()
  local saved = NS.db
  NS.db = nil
  local ok, err = pcall(NS.RunMigrations, NS)
  NS.db = saved
  assertTrue(ok, "RunMigrations raised with no db: " .. tostring(err))
end)

test("database: the runner climbs every step, stamps each, and is idempotent", function()
  local steps, ran = NS.__migrationSteps, {}
  local real = steps[1]
  steps[1] = { to = 1, apply = function() ran[#ran + 1] = 1 end }
  steps[2] = { to = 2, apply = function() ran[#ran + 1] = 2 end }
  local g = NS.db.global
  g.schemaVersion = 0
  local ok, err = pcall(NS.RunMigrations, NS)
  local stamp = g.schemaVersion
  NS:RunMigrations()
  steps[1], steps[2] = real, nil
  g.schemaVersion = NS.SCHEMA_VERSION
  assertTrue(ok, tostring(err))
  assertEqual(table.concat(ran, ","), "1,2", "each step ran once, in order")
  assertEqual(stamp, 2, "the stamp advanced past each step")
end)

test("database: a step that raises leaves the stamp unmoved and says so once in chat", function()
  local steps = NS.__migrationSteps
  local real = steps[1]
  steps[1] = { to = 1, apply = function() error("boom") end }
  local g = NS.db.global
  g.schemaVersion = 0
  T.mocks.__resetPrinted()
  local ok = pcall(NS.RunMigrations, NS)
  local printed = T.mocks.__printed()
  steps[1] = real
  local stamp = g.schemaVersion
  g.schemaVersion = NS.SCHEMA_VERSION
  assertTrue(ok, "the runner never raises out of a failed step")
  assertEqual(stamp, 0, "the stamp did not move past the failed step")
  assertEqual(#printed, 1, "one chat line: " .. table.concat(printed, " / "))
  assertTrue(printed[1]:find("v0 -> v1", 1, true) ~= nil, "it names the step: " .. printed[1])
end)

test("database: InitDB produced a profile carrying every default key", function()
  for key in pairs(NS.defaults.profile) do
    assertTrue(NS.db.profile[key] ~= nil, "profile is missing " .. key)
  end
end)

test("database: Backfill fills only missing keys, deep-copied, and keeps a stored false", function()
  local template = { a = 1, nested = { b = 2, c = { r = 1 } }, flag = true }
  local dst = { flag = false, nested = { b = 5 } }
  local n = D.Backfill(dst, template)
  assertFalse(dst.flag, "a stored false is the player's choice and survives")
  assertEqual(dst.nested.b, 5, "a stored value is never overwritten")
  assertEqual(dst.a, 1, "a missing key is filled")
  assertTrue(dst.nested.c ~= template.nested.c, "a table default is copied, never shared")
  assertEqual(n, 2, "two leaves filled")
end)

test("database: the session-only state is in no defaults tree", function()
  -- debug-logging-§5 and options-ui-§15: the debug flag and both preview modes reset every /reload.
  for _, key in ipairs({ "debug", "testMode", "simMode", "state" }) do
    assertNil(NS.defaults.profile[key], key .. " must not be persisted")
  end
  assertNil(NS.defaults.global.minimap.shown, "the minimap row's sense is never stored (anti-pattern #81)")
end)

test("database: a profile reset re-reads the latch and traces once", function()
  local db = NS.db
  if not db.ResetProfile then return end
  db.profile.enabled = false
  NS.SyncEnabledHold()
  assertTrue(NS.IsStoodDown(), "precondition: down")
  db:ResetProfile()
  assertFalse(NS.IsStoodDown(), "the reset profile is enabled, and the addon came back up")
  -- The reset profile is fresh, so the first-run picker came up and previews Simple on it; close it
  -- unanswered, so the shared profile carries no preview into the suites after this one.
  NS.HidePresetPicker()
end)

-- ---------------------------------------------------------------------------
-- The registries' load pass (NS.Database.PrepareProfile; the v0.1.0 plan, Task 3)
-- ---------------------------------------------------------------------------

--- Run `body(p)` with the db swapped for a bare { profile = p, global } pair; restores the real one.
local function withProfile(p, body, classToken)
  local savedDb, savedClass = NS.db, T.mocks.__context.classToken
  if classToken then T.mocks.__context.classToken = classToken end
  NS.db = { profile = p, global = savedDb.global }
  local ok, err = pcall(body, p)
  NS.db = savedDb
  T.mocks.__context.classToken = savedClass
  if not ok then error(err, 0) end
end

test("database: test_template_fill_missing_keys — a stored container gains what a later build added", function()
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  c.elements.spells = nil
  c.anchor.frame = nil
  c.elements.number.enabled = false
  c.elements.order = { "number", "text" }
  c.visibility = "junk"
  local p = { containers = { [4] = c, [9] = "junk" }, containerOrder = { 4, 4, 12 } }
  withProfile(p, function()
    D.PrepareProfile(p)
  end)
  assertEqual(type(c.elements.spells), "table", "elements.spells filled on load")
  assertEqual(c.elements.spells.enabled, false)
  assertEqual(type(c.elements.spells.list), "table")
  assertEqual(c.anchor.frame.provider, "blizzard", "a nested section filled")
  assertFalse(c.elements.number.enabled, "a stored false survives")
  assertEqual(table.concat(c.elements.order, ","), "number,text,indicator,spells",
    "an array is never backfilled index by index; the missing names are appended once")
  assertEqual(type(c.visibility), "table", "a section stored as a non-table is repaired")
  assertNil(p.containers[9], "a member that is not a table is dropped")
  assertEqual(table.concat(p.containerOrder, ","), "4", "dangling and duplicate ids dropped")
  assertEqual(p.nextContainerId, 5, "the counter is bumped past the highest stored id")
  assertEqual(c.bandSet, NS.BandSets.DefaultId(), "a container with no band set gets the default")
end)

test("database: the load pass repairs a container whose band set ids name no stored set", function()
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  c.bandSet = 999
  c.bandSetFriendly = 998
  local p = { containers = { [1] = c }, containerOrder = { 1 } }
  withProfile(p, function()
    D.PrepareProfile(p)
    assertNil(p.bandSets[999], "precondition: no set 999 is stored")
    assertEqual(c.bandSet, NS.BandSets.DefaultId(), "a dangling bandSet is pointed at the default")
    assertNil(c.bandSetFriendly, "a dangling bandSetFriendly is cleared")
  end)
end)

test("database: test_first_run_seeds_presets — a fresh profile gets the four sets, class default first", function()
  local p = {}
  withProfile(p, function()
    D.PrepareProfile(p)
    assertEqual(#p.bandSetOrder, 4, "four band sets seeded")
    assertEqual(p.nextBandSetId, 5)
    assertEqual(p.seeded, false, "the first-run container picker has not run")
    assertEqual(NS.BandSets.Get(NS.BandSets.DefaultId()).name, NS.BandSetPresets.caster40.name,
      "a Mage's default is Caster 40")
    -- idempotent: a second pass seeds nothing more
    D.PrepareProfile(p)
    assertEqual(#p.bandSetOrder, 4)
  end, "MAGE")
  local h = {}
  withProfile(h, function()
    D.PrepareProfile(h)
    assertEqual(NS.BandSets.Get(NS.BandSets.DefaultId()).name, NS.BandSetPresets.hunter.name,
      "a Hunter's default is the Hunter set")
    local seen = {}
    for _, id in ipairs(h.bandSetOrder) do seen[NS.BandSets.Get(id).name] = true end
    for _, key in ipairs(NS.BandSetPresets.ORDER) do
      assertTrue(seen[NS.BandSetPresets[key].name], key .. " seeded")
    end
  end, "HUNTER")
end)

test("database: the load pass normalizes a stored band set and repairs its counter and order", function()
  local p = {
    bandSets = { [7] = { name = "Hand-edited", bands = { { from = 30, to = 10, label = "X" } } } },
    bandSetOrder = { 3, 7 }, nextBandSetId = 2,
  }
  withProfile(p, function()
    D.PrepareProfile(p)
  end)
  assertEqual(table.concat(p.bandSetOrder, ","), "7", "no seeding over a stored set; dangling id dropped")
  assertEqual(p.nextBandSetId, 8)
  local set = p.bandSets[7]
  assertEqual(set.matchBy, "max", "the template filled matchBy")
  assertEqual(set.bands[1].from, 0)
  assertNil(set.bands[#set.bands].to)
end)

test("database: the active profile was prepared at load", function()
  local p = NS.db.profile
  assertEqual(type(p.containers), "table")
  assertEqual(type(p.containerOrder), "table")
  assertTrue(#p.bandSetOrder >= 1, "the live profile carries its seeded band sets")
  assertEqual(type(p.nextContainerId), "number")
  assertTrue(p.seeded ~= nil)
end)

-- ---------------------------------------------------------------------------
-- Migration step 1: the frame defaults (border opacity 25%, the matte dot) reach only containers
-- created after it; every container already stored, in every profile, keeps its look.
-- ---------------------------------------------------------------------------

--- A container stored before step 1: no border opacity, no indicator style.
local function oldContainer()
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  c.frame.border.alpha = nil
  c.elements.indicator.style = nil
  return c
end

--- Run the ladder from v0 against `db` (swapped in for NS.db), then restore the real one.
local function migrate(db, body)
  local savedDb = NS.db
  db.global = db.global or { schemaVersion = 0 }
  NS.db = db
  local ok, err = pcall(function()
    NS:RunMigrations()
    if body then body(db) end
  end)
  NS.db = savedDb
  if not ok then error(err, 0) end
end

test("database: step 1 writes border opacity 100% and the plain dot onto every stored container, in every profile", function()
  -- Red under the empty v0.1.0 ladder: nothing writes either field, and the load pass backfills the
  -- new defaults (25%, matte) onto the old containers instead.
  local active, raid = { containers = { [1] = oldContainer() } }, { containers = { [3] = oldContainer() } }
  local kept = oldContainer()
  kept.frame.border.alpha, kept.elements.indicator.style = 0.6, "gem"
  raid.containers[4] = kept
  -- The kit's AceDB shape: every profile under db.sv.profiles, the active one also as db.profile.
  migrate({ profile = active, sv = { profiles = { Default = active, Raid = raid, Junk = "junk" } } }, function(db)
    assertEqual(db.global.schemaVersion, 1, "stamped v1")
  end)
  assertEqual(active.containers[1].frame.border.alpha, 1, "the active profile's container keeps a full border")
  assertEqual(active.containers[1].elements.indicator.style, "plain", "and its plain dot")
  assertEqual(raid.containers[3].frame.border.alpha, 1, "a profile not in use is migrated too")
  assertEqual(raid.containers[3].elements.indicator.style, "plain")
  assertEqual(kept.frame.border.alpha, 0.6, "a value already stored is the player's and survives")
  assertEqual(kept.elements.indicator.style, "gem")

  -- Real AceDB-3.0's shape: db.profiles is the raw SavedVariables' profiles table.
  local other = { containers = { [2] = oldContainer() } }
  migrate({ profile = {}, profiles = { Other = other } })
  assertEqual(other.containers[2].frame.border.alpha, 1, "db.profiles is walked")
  assertEqual(other.containers[2].elements.indicator.style, "plain")

  -- The soft fallback with no AceDB: only the active profile, and junk in it is passed over.
  local bare = { containers = { [1] = oldContainer(), [2] = { frame = "junk" } } }
  migrate({ profile = bare })
  assertEqual(bare.containers[1].frame.border.alpha, 1, "the active profile alone is migrated")
end)

test("database: step 1 runs once, and a container made after it takes the new defaults", function()
  local p = { containers = { [1] = oldContainer() } }
  local db = { profile = p, sv = { profiles = { Default = p } } }
  migrate(db, function()
    p.containers[2] = oldContainer()
    NS:RunMigrations()
  end)
  assertEqual(db.global.schemaVersion, 1)
  assertEqual(p.containers[1].frame.border.alpha, 1, "migrated")
  assertEqual(p.containers[2].frame.border.alpha, 0.25, "a container stored after the stamp gets the default")
  assertEqual(p.containers[2].elements.indicator.style, "matte", "and the matte dot")
  local fresh = {}
  migrate({ profile = fresh })
  assertNil(fresh.containers and next(fresh.containers), "a fresh profile has no container to migrate")
end)

test("database: a new container's frame defaults are a 25% border and a background", function()
  -- Red under the v0.1.0 template: no border opacity, the background off.
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  assertEqual(c.frame.border.alpha, 0.25, "border opacity 25%")
  assertTrue(c.frame.border.enabled, "border on")
  assertTrue(c.frame.background.enabled, "background on")
end)
