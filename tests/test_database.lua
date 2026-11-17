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

test("database: v0.1.0 ships the first data shape, so the ladder is empty and the target is 0", function()
  assertEqual(#NS.__migrationSteps, 0, "no step to migrate from yet")
  assertEqual(NS.SCHEMA_VERSION, 0, "the runner's target is the highest step's `to`, or 0")
  assertEqual(NS.db.global.schemaVersion, 0, "a fresh install is stamped at the target")
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
  steps[1] = { to = 1, apply = function() ran[#ran + 1] = 1 end }
  steps[2] = { to = 2, apply = function() ran[#ran + 1] = 2 end }
  local g = NS.db.global
  g.schemaVersion = 0
  local ok, err = pcall(NS.RunMigrations, NS)
  local stamp = g.schemaVersion
  NS:RunMigrations()
  steps[1], steps[2] = nil, nil
  g.schemaVersion = 0
  assertTrue(ok, tostring(err))
  assertEqual(table.concat(ran, ","), "1,2", "each step ran once, in order")
  assertEqual(stamp, 2, "the stamp advanced past each step")
end)

test("database: a step that raises leaves the stamp unmoved and says so once in chat", function()
  local steps = NS.__migrationSteps
  steps[1] = { to = 1, apply = function() error("boom") end }
  local g = NS.db.global
  g.schemaVersion = 0
  T.mocks.__resetPrinted()
  local ok = pcall(NS.RunMigrations, NS)
  local printed = T.mocks.__printed()
  steps[1] = nil
  assertTrue(ok, "the runner never raises out of a failed step")
  assertEqual(g.schemaVersion, 0, "the stamp did not move past the failed step")
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
end)
