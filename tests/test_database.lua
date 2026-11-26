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

test("database: the ladder holds six steps, v0 -> v1 (the frame defaults), v1 -> v2 (band rules), v2 -> v3 (own looks), v3 -> v4 (band set origins), v4 -> v5 (per-character band sets) and v5 -> v6 (the band set assigned to each character), and a fresh install is stamped 6", function()
  -- Red under the v0.1.0 ladder, which was empty with a target of 0, and under the three-step ladder.
  assertEqual(#NS.__migrationSteps, 6, "six steps")
  assertEqual(NS.__migrationSteps[1].to, 1, "the first step climbs to v1")
  assertEqual(NS.__migrationSteps[2].to, 2, "the second step climbs to v2")
  assertEqual(NS.__migrationSteps[3].to, 3, "the third step climbs to v3")
  assertEqual(NS.__migrationSteps[4].to, 4, "the fourth step climbs to v4")
  assertEqual(NS.__migrationSteps[5].to, 5, "the fifth step climbs to v5 (tests/test_bandset_choice.lua)")
  assertEqual(NS.__migrationSteps[6].to, 6, "the sixth step climbs to v6 (R4-RM-01, tests/test_bandset_choice.lua)")
  assertEqual(NS.SCHEMA_VERSION, 6, "the runner's target is the highest step's `to`")
  assertEqual(NS.db.global.schemaVersion, 6, "a fresh install is stamped at the target")
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
  local real, real2 = steps[1], steps[2]
  steps[1] = { to = 1, apply = function() ran[#ran + 1] = 1 end }
  steps[2] = { to = 2, apply = function() ran[#ran + 1] = 2 end }
  local g = NS.db.global
  g.schemaVersion = 0
  local ok, err = pcall(NS.RunMigrations, NS)
  local stamp = g.schemaVersion
  NS:RunMigrations()
  steps[1], steps[2] = real, real2
  g.schemaVersion = NS.SCHEMA_VERSION
  assertTrue(ok, tostring(err))
  assertEqual(table.concat(ran, ","), "1,2", "each step ran once, in order")
  assertEqual(stamp, 6, "the stamp advanced past each step")
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

test("database: test_first_run_seeds_presets — a fresh profile gets the class's own set first, then the four", function()
  local p = {}
  withProfile(p, function()
    D.PrepareProfile(p)
    assertEqual(#p.bandSetOrder, 5, "the Mage set and the four generic sets seeded (RangeMaster#20)")
    assertEqual(p.nextBandSetId, 6)
    assertEqual(p.seeded, false, "the first-run container picker has not run")
    assertEqual(NS.BandSets.Get(NS.BandSets.DefaultId()).name, NS.BandSetPresets.mage.name,
      "a Mage's default is the Mage set")
    -- idempotent: a second pass seeds nothing more
    D.PrepareProfile(p)
    assertEqual(#p.bandSetOrder, 5)
  end, "MAGE")
  local pal = {}
  withProfile(pal, function()
    D.PrepareProfile(pal)
    local first = NS.BandSets.Get(NS.BandSets.DefaultId())
    assertEqual(first.name, NS.BandSetPresets.paladin.name, "a Paladin's default is the Paladin set")
    local roles = {}
    for _, b in ipairs(first.bands) do roles[#roles + 1] = b.rule and (b.rule.role or b.rule.type) or "yards" end
    assertEqual(table.concat(roles, ","), "melee,tier10,ranged,beyond", "its 5-10 band asks the 10 yd tier")
  end, "PALADIN")
  local h = {}
  withProfile(h, function()
    D.PrepareProfile(h)
    assertEqual(NS.BandSets.Get(NS.BandSets.DefaultId()).name, NS.BandSetPresets.hunter.name,
      "a Hunter's default is the Hunter set")
    assertEqual(#h.bandSetOrder, 4, "the Hunter set is the class's own: four sets, no duplicate")
    local seen = {}
    for _, id in ipairs(h.bandSetOrder) do seen[NS.BandSets.Get(id).name] = true end
    for _, key in ipairs(NS.BandSetPresets.ORDER) do
      assertTrue(seen[NS.BandSetPresets[key].name], key .. " seeded")
    end
  end, "HUNTER")
end)

test("database: a Devourer's seed keeps its caster default and still gets the Demon Hunter set", function()
  local realSpec = NS.Compat.PlayerSpecID
  NS.Compat.PlayerSpecID = function() return 1480 end
  local ok, err = pcall(function()
    local p = {}
    withProfile(p, function()
      D.PrepareProfile(p)
      local names = {}
      for _, id in ipairs(p.bandSetOrder) do names[#names + 1] = NS.BandSets.Get(id).name end
      assertEqual(names[1], NS.BandSetPresets.caster40.name, "the spec override stays the default")
      if NS.BandSetPresets.demonhunter then
        -- red under: the override took first place and the class's own preset was never seeded.
        assertEqual(names[2], NS.BandSetPresets.demonhunter.name, "the Demon Hunter set follows it")
        assertEqual(#p.bandSetOrder, 5, "caster40, demonhunter, then the three other generic sets")
        assertEqual(p.nextBandSetId, 6)
      else
        -- a client with no Demon Hunter preset (WoW Forever): the four generic sets alone.
        assertEqual(#p.bandSetOrder, 4, "no class preset on this client: the four generic sets")
        assertEqual(p.nextBandSetId, 5)
      end
    end, "DEMONHUNTER")
  end)
  NS.Compat.PlayerSpecID = realSpec
  assertTrue(ok, tostring(err))
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
    assertEqual(db.global.schemaVersion, NS.SCHEMA_VERSION, "stamped at the target")
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
  assertEqual(db.global.schemaVersion, NS.SCHEMA_VERSION)
  assertEqual(p.containers[1].frame.border.alpha, 1, "migrated")
  assertEqual(p.containers[2].frame.border.alpha, 0.25, "a container stored after the stamp gets the default")
  assertEqual(p.containers[2].elements.indicator.style, "matte", "and the matte dot")
  local fresh = {}
  migrate({ profile = fresh })
  assertNil(fresh.containers and next(fresh.containers), "a fresh profile has no container to migrate")
end)

test("database: step 1 through the real InitDB, against a stored v0 RangeMasterDB with two profiles", function()
  -- red under: InitDB (or a profile callback) backfilling or preparing the active profile before
  -- the ladder runs (the old containers would then load at 25% and matte, and the step skip them),
  -- and under a step that skips a hand-edited container missing its frame or elements section.
  local v0 = oldContainer()
  v0.frame.background.enabled = false
  local partial = { unit = "focus", frame = { background = { enabled = true } } }
  local inactive = oldContainer()
  local savedDb, savedSV = NS.db, _G.RangeMasterDB
  _G.RangeMasterDB = {
    profiles = {
      Default = { containers = { [1] = v0, [2] = partial }, containerOrder = { 1, 2 }, nextContainerId = 3 },
      Raid = { containers = { [7] = inactive }, containerOrder = { 7 }, nextContainerId = 8 },
    },
    global = {},
  }
  local sv = _G.RangeMasterDB
  local ok, err = pcall(function()
    NS:InitDB()
    assertEqual(sv.global.schemaVersion, NS.SCHEMA_VERSION, "the stamp is written into the SavedVariables' global")
    local p = NS.db.profile
    assertTrue(p.containers[1] == v0, "the active profile is the stored one")
    assertEqual(v0.frame.border.alpha, 1, "a stored container keeps a full border")
    assertEqual(v0.elements.indicator.style, "plain", "and its plain dot")
    assertFalse(v0.frame.background.enabled, "and no background")
    assertEqual(partial.frame.border.alpha, 1, "a container with no border section keeps a full border")
    assertEqual(partial.elements.indicator.style, "plain", "and with no elements section, the plain dot")
    assertTrue(partial.frame.background.enabled, "its own background is kept")
    assertEqual(inactive.frame.border.alpha, 1, "a profile not in use is migrated as it is stored")
    assertEqual(inactive.elements.indicator.style, "plain")
    NS:RunMigrations()
    assertEqual(sv.global.schemaVersion, NS.SCHEMA_VERSION, "a second load climbs nothing")
  end)
  NS.db, _G.RangeMasterDB = savedDb, savedSV
  NS.CM.__reset()
  if not ok then error(err, 0) end
end)

test("database: a new container's frame defaults are a 25% border and a background", function()
  -- Red under the v0.1.0 template: no border opacity, the background off.
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  assertEqual(c.frame.border.alpha, 0.25, "border opacity 25%")
  assertTrue(c.frame.border.enabled, "border on")
  assertTrue(c.frame.background.enabled, "background on")
end)

-- ---------------------------------------------------------------------------
-- Migration step 2: band rules (plan 2026-11-19-dynamic-bands, D4). Every stored band set, custom ones
-- included, in every profile, gets the rule its yards suggest; the yards stay, as the fallback.
-- ---------------------------------------------------------------------------

--- A band set as v1 stored it: no band carries a rule. `spec` is { { from, to, label }, ... }.
local function v1Set(name, spec)
  local bands = {}
  for i, b in ipairs(spec) do bands[i] = { from = b[1], to = b[2], label = b[3] } end
  return { name = name, matchBy = "max", bands = bands }
end

--- A set's rules, one word a band: yards, melee, ranged, friendly, gap or beyond.
local function rulesOf(set)
  local out = {}
  for i, b in ipairs(set.bands) do
    local r = b.rule
    out[i] = r == nil and "yards" or (r.type == "spell" and r.role or r.type)
  end
  return table.concat(out, ",")
end

--- A set's yards, "from-to" a band ("+" for open-ended).
local function yardsOf(set)
  local out = {}
  for i, b in ipairs(set.bands) do out[i] = b.from .. "-" .. (b.to or "+") end
  return table.concat(out, ",")
end

local function step2()
  for _, step in ipairs(NS.__migrationSteps) do
    if step.to == 2 then return step end
  end
end

local V1_FOREVER_HUNTER = { { 0, 5, "MELEE" }, { 5, 8, "DEAD" }, { 8, 35, "AUTO" }, { 35, nil, "OOR" } }
local V1_RETAIL_HUNTER = { { 0, 5, "MELEE" }, { 5, 40, "RANGED" }, { 40, nil, "OOR" } }
local V1_MELEE_RANGED = { { 0, 5, "MELEE" }, { 5, 20, "CLOSE" }, { 20, 30, "MID" }, { 30, 40, "LONG" },
  { 40, nil, "OOR" } }
local V1_CASTER40 = { { 0, 8, "CLOSE" }, { 8, 30, "MID" }, { 30, 40, "LONG" }, { 40, nil, "OOR" } }
local V1_HEALER = { { 0, 30, "NEAR" }, { 30, 40, "FAR" }, { 40, nil, "OOR" } }

test("database: step 2 turns each v1 preset shape into rule bands and keeps its yards", function()
  -- Red under the one-step ladder: there is no step 2, and no stored band carries a rule.
  local step = step2()
  assertTrue(step ~= nil, "a step climbs to v2")
  local p = {
    bandSets = {
      [1] = v1Set("Hunter", V1_FOREVER_HUNTER), [2] = v1Set("Hunter 2", V1_RETAIL_HUNTER),
      [3] = v1Set("Melee / Ranged", V1_MELEE_RANGED), [4] = v1Set("Caster 40", V1_CASTER40),
      [5] = v1Set("Healer", V1_HEALER),
    },
    bandSetOrder = { 1, 2, 3, 4, 5 }, nextBandSetId = 6, containers = {},
  }
  step.apply({ profile = p })
  local s = p.bandSets
  assertEqual(rulesOf(s[1]), "melee,gap,ranged,beyond", "Forever Hunter: MELEE, DEAD, AUTO, OOR")
  assertEqual(rulesOf(s[2]), "melee,ranged,beyond", "Retail Hunter: MELEE, RANGED, OOR")
  assertEqual(rulesOf(s[3]), "melee,yards,yards,ranged,beyond",
    "Melee / Ranged: only the outermost 20 to 45 yd band asks the ranged anchor")
  assertEqual(rulesOf(s[4]), "yards,yards,ranged,beyond", "Caster 40: its first band (0-8) stays yards")
  assertEqual(rulesOf(s[5]), "yards,friendly,beyond", "a set named Healer asks the friendly anchor")
  assertEqual(yardsOf(s[1]), "0-5,5-8,8-35,35-+", "the yards are untouched: they are the fallback")
  assertEqual(yardsOf(s[3]), "0-5,5-20,20-30,30-40,40-+")
  assertNil(s[1].bands[3].rule.spells, "a converted rule names the role, not a spell")
  assertEqual(s[1].bands[3].label, "AUTO", "the label is kept")

  -- The owner's case through the converted set: a 35-40 bracket with the ranged anchor in range is AUTO.
  local savedDb, realRole = NS.db, NS.Range.RoleInRange
  NS.db = { profile = p, global = savedDb.global }
  NS.Range.RoleInRange = function(role) if role == "ranged" then return true end return false end
  local ok, got = pcall(NS.BandSets.Resolve, 1, "known", 35, 40, "target")
  NS.db, NS.Range.RoleInRange = savedDb, realRole
  assertTrue(ok, tostring(got))
  assertEqual(got, 3, "AUTO, not OOR")
end)

test("database: step 2 converts a custom set, and reads a friendly-only set as friendly, in every profile", function()
  local step = step2()
  local custom = v1Set("Mine", { { 0, 3, "A" }, { 3, 12, "B" }, { 12, 25, "C" }, { 25, 60, "D" }, { 60, nil, "E" } })
  local heals, mixed = v1Set("Heals", V1_HEALER), v1Set("Mixed", V1_HEALER)
  local raid = {
    bandSets = { [1] = custom, [2] = heals, [3] = mixed }, bandSetOrder = { 1, 2, 3 },
    containers = {
      [1] = { bandSet = 1, bandSetFriendly = 2 },
      [2] = { bandSet = 3, bandSetFriendly = 3 },
    },
  }
  local unordered = v1Set("Loose", { { 30, 10, "X" }, { 0, 4, "Y" }, { 30, nil, "Z" } })
  local active = { bandSets = { [9] = unordered }, bandSetOrder = { 9 } }
  step.apply({ profile = active, profiles = { Raid = raid, Junk = "junk", Bare = {} } })
  assertEqual(rulesOf(custom), "melee,yards,ranged,yards,beyond",
    "a custom set: a first band within 5 yd is melee, the 20 to 45 yd band ranged, the last beyond")
  assertEqual(yardsOf(custom), "0-3,3-12,12-25,25-60,60-+")
  assertEqual(rulesOf(heals), "yards,friendly,beyond", "a set used only as a friendly override is friendly")
  assertEqual(rulesOf(mixed), "yards,ranged,beyond", "a set some container also uses as its own is ranged")
  assertEqual(yardsOf(unordered), "0-4,4-30,30-+", "a hand-edited set is normalized before it is read")
  assertEqual(rulesOf(unordered), "melee,ranged,beyond")
end)

test("database: step 2 is idempotent and keeps a rule a band already carries", function()
  local step = step2()
  local set = v1Set("Kept", { { 0, 5, "A" }, { 5, 30, "B" }, { 30, nil, "C" } })
  set.bands[2].rule = { type = "spell", role = "friendly", spells = { 2061 } }
  set.bands[1].rule = "junk"
  local p = { bandSets = { [1] = set }, bandSetOrder = { 1 } }
  local db = { profile = p }
  step.apply(db)
  local once, onceYards = rulesOf(set), yardsOf(set)
  local spells = set.bands[2].rule.spells
  step.apply(db)
  assertEqual(once, "melee,friendly,beyond", "a rule already stored is kept; a junk one is replaced")
  assertEqual(rulesOf(set), once, "a second run changes no rule")
  assertEqual(yardsOf(set), onceYards, "nor any yard")
  assertEqual(#set.bands[2].rule.spells, 1, "the band's own spell list survives")
  assertEqual(set.bands[2].rule.spells[1], 2061)
  assertEqual(spells[1], 2061)
end)

test("database: step 2 runs on a profile with no usable order and a container with no set (review D6)", function()
  -- red under: a default-set key read as nil ("table index is nil"), which stops the climb at v1.
  local step = step2()
  local set = v1Set("Loose", V1_RETAIL_HUNTER)
  local p = { bandSets = { [1] = set }, containers = { [1] = {} } }
  local ok, err = pcall(step.apply, { profile = p })
  assertTrue(ok, tostring(err))
  assertEqual(rulesOf(set), "melee,ranged,beyond", "the set is still converted")
  local stale = v1Set("Stale", V1_RETAIL_HUNTER)
  ok, err = pcall(step.apply, { profile = { bandSets = { [2] = stale }, bandSetOrder = { 7 }, containers = { {} } } })
  assertTrue(ok, tostring(err))
  assertEqual(rulesOf(stale), "melee,ranged,beyond", "an order naming no stored set: converted too")
end)

test("database: step 2 on a fresh profile changes nothing, and the load pass then seeds rule presets", function()
  local p = {}
  step2().apply({ profile = p })
  assertNil(p.bandSets, "the step makes no band set")
  withProfile(p, function()
    D.PrepareProfile(p)
    for _, id in ipairs(p.bandSetOrder) do
      local set = p.bandSets[id]
      assertEqual(set.bands[#set.bands].rule and set.bands[#set.bands].rule.type, "beyond",
        set.name .. ": its last band is beyond")
    end
  end, "HUNTER")
end)

test("database: test_backfill_plate_part_and_level — a container stored before Attach to part and Frame level reads the plate and Auto", function()
  -- No migration: the load pass fills both from the template, so a stored container draws as before.
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  c.nameplate.attachTo = nil
  c.anchor.level = nil
  c.nameplate.y = -7
  local p = { containers = { [1] = c }, containerOrder = { 1 } }
  withProfile(p, function()
    D.PrepareProfile(p)
  end)
  assertEqual(c.nameplate.attachTo, "plate", "on the plate, as before")
  assertEqual(c.anchor.level, 0, "Auto, as before")
  assertEqual(c.nameplate.y, -7, "a stored value is kept")
end)

-- ── the owner's own looks (2026-11-23, over R-2; step 3 undoes the retired skin step) ─────────

local function eachCompanion(c, fn)
  for _, part in ipairs({ c.label, c.elements.number, c.elements.text }) do
    fn(part, "colorFromSkin"); fn(part, "shadowFromSkin")
  end
  fn(c.elements.indicator, "colorFromSkin")
  fn(c.frame.border, "textureFromSkin"); fn(c.frame.border, "colorFromSkin")
  fn(c.frame.background, "colorFromSkin")
end

--- A container as the retired step left it: every companion on, the Font flags From skin.
local function movedContainer()
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  eachCompanion(c, function(part, key) part[key] = true end)
  for _, part in ipairs({ c.label, c.elements.number, c.elements.text }) do part.outline = "@skin" end
  return c
end

local function step3()
  for _, s in ipairs(NS.__migrationSteps) do if s.to == 3 then return s end end
end

test("database: a new container keeps its own looks, in the template and on the rows", function()
  local T3 = NS.CONTAINER_TEMPLATE
  -- red under: a follow-the-skin sweep flipping one (SD-SK-RM, 2026-11-20): white captions went gold
  eachCompanion(T3, function(part, key) assertEqual(part[key], false, key) end)
  for _, part in ipairs({ T3.label, T3.elements.number, T3.elements.text }) do
    assertEqual(part.outline, "OUTLINE", "Font flags")
  end
  local n = 0
  for _, row in ipairs(NS.Schema) do
    local rel = type(row.path) == "string" and row.path:match("^container%.(.+)$")
    if rel and (rel:find("FromSkin$") or rel:find("%.outline$")) then
      local v = T3
      for seg in rel:gmatch("[^%.]+") do if type(v) == "table" then v = v[seg] end end
      assertEqual(row.default, v, row.path .. " row default agrees")
      n = n + 1
    end
  end
  assertTrue(n >= 11, "the rows were found: " .. n)
end)

test("database: the Ka0s preset is frameless under a skin with a border of its own", function()
  local Skin = T.mocks.LibStub("LibKa0s-Skin-1.0")
  local skinWas, savedDb = NS.db.profile.skin.skin, NS.db
  local p = {}
  NS.db = { profile = p, global = savedDb.global }
  NS.CM.__reset()
  NS.Presets.__reset()
  local ok, err = pcall(function()
    D.PrepareProfile(p)
    for _, skin in ipairs({ "azeroth", "contrast", "wow", "midnight" }) do
      Skin:SetChoice("RangeMaster", "ka0s", skin)
      NS.Presets.Apply("ka0s")
      for _, c in pairs(p.containers) do
        local b = c.frame.border
        local _, show = NS.Skin.BarBorder(b.texture, b.enabled, b.size, b.textureFromSkin == true)
        -- red under: textureFromSkin defaulting on, so a real style drew over "Show border" off
        assertTrue(not show, skin .. ": " .. tostring(c.name) .. " drew a border")
      end
    end
  end)
  NS.Container.__reset()
  NS.CM.__reset()
  NS.Presets.__reset()
  NS.db = savedDb
  Skin:SetChoice("RangeMaster", "ka0s", skinWas)
  if not ok then error(err, 0) end
end)

test("database: step 3 takes back what the retired skin step wrote, in every profile it reached", function()
  local active, parked, untouched = movedContainer(), movedContainer(), movedContainer()
  local picked = movedContainer()
  picked.label.color = { r = 0.2, g = 0.4, b = 0.6, a = 1 }
  local a = { skin = { defaultsFollowSkin = true }, containers = { [1] = active, [2] = picked } }
  local b = { skin = { defaultsFollowSkin = true }, containers = { [1] = parked } }
  local c = { skin = {}, containers = { [1] = untouched } }
  local step = step3()
  assertTrue(step ~= nil, "a step 3")
  step.apply({ profile = a, sv = { profiles = { A = a, B = b, C = c } } })
  for _, moved in ipairs({ active, parked }) do
    -- red under: no restore, or one over the active profile alone
    eachCompanion(moved, function(part, key) assertEqual(part[key], false, key) end)
    assertEqual(moved.label.outline, "OUTLINE")
  end
  assertNil(a.skin.defaultsFollowSkin, "the record cleared")
  assertNil(b.skin.defaultsFollowSkin, "the record cleared")
  assertEqual(picked.label.colorFromSkin, true, "on beside a picked color was never the step's write")
  eachCompanion(untouched, function(part, key) assertEqual(part[key], true, "no record, untouched: " .. key) end)
end)

test("database: the load moves nothing onto the skin", function()
  local saved = NS.db
  local c = D.DeepCopy(NS.CONTAINER_TEMPLATE)
  eachCompanion(c, function(part, key) part[key] = nil end)
  local p = { containers = { [1] = c }, containerOrder = { 1 } }
  NS.db = { profile = p, global = saved.global }
  local ok, err = pcall(NS.RunMigrations, NS)
  NS.db = saved
  assertTrue(ok, tostring(err))
  -- red under: FollowSkinDefaults from RunMigrations, or a backfill of true
  eachCompanion(c, function(part, key) assertEqual(part[key], false, key) end)
  assertNil(p.skin and p.skin.defaultsFollowSkin, "no record")
end)

-- ---------------------------------------------------------------------------
-- Migration step 4: band set origins (RangeMaster#21). A set stored before a set remembered its
-- preset gets `origin` when its name is exactly one preset's localized name on this client.
-- ---------------------------------------------------------------------------

local function step4()
  for _, s in ipairs(NS.__migrationSteps) do if s.to == 4 then return s end end
end

--- A stored set as v3 kept it: a name and bands, no origin.
local function v3Set(name)
  return { name = name, matchBy = "max", bands = { { from = 0, label = "X" } } }
end

test("database: step 4 back-fills origin by a unique, case-blind preset name match, in every profile", function()
  -- Red under the three-step ladder: no stored set carries an origin.
  local BP = NS.BandSetPresets
  local step = step4()
  assertTrue(step ~= nil, "a step climbs to v4")
  local a = { bandSets = {
    [1] = v3Set(BP.paladin.name:lower()), [2] = v3Set("  " .. BP.melee_ranged.name .. " "),
    [3] = v3Set(BP.caster40.name:upper()), [4] = v3Set(BP.hunter.name), [5] = v3Set("My set"),
    [6] = v3Set(BP.paladin.name .. " copy"), [7] = v3Set(NS.L["Death Knight"]),
    [8] = "junk",
  } }
  local kept = v3Set(BP.paladin.name)
  kept.origin = "caster40"
  a.bandSets[9] = kept
  local b = { bandSets = { [1] = v3Set(BP.healer.name) } }
  local c = { containers = {} }
  step.apply({ profile = a, sv = { profiles = { A = a, B = b, C = c } } })
  local s = a.bandSets
  assertEqual(s[1].origin, "paladin", "a name in another case")
  assertEqual(s[2].origin, "melee_ranged", "a name with stray spaces")
  assertEqual(s[3].origin, "caster40")
  assertEqual(s[4].origin, "hunter", "the Hunter preset, listed once")
  assertNil(s[5].origin, "a name of the player's own")
  assertNil(s[6].origin, "a duplicate's name is not the preset's")
  if NS.Compat.ClientKey() == "forever" then
    assertNil(s[7].origin, "a class this client has no preset for")
  else
    assertEqual(s[7].origin, "deathknight")
  end
  assertEqual(kept.origin, "caster40", "an origin already stored is kept")
  assertEqual(b.bandSets[1].origin, "healer", "a profile not in use is migrated too")
  assertNil(c.bandSets, "a profile with no band set is left alone")
  step.apply({ profile = a })
  assertEqual(s[1].origin, "paladin", "a second run changes nothing")
end)

test("database: step 4 leaves a name two presets share alone", function()
  local BP = NS.BandSetPresets
  local healerName = BP.healer.name
  BP.healer.name = BP.caster40.name
  local p = { bandSets = { [1] = v3Set(BP.caster40.name), [2] = v3Set(BP.paladin.name) } }
  local ok, err = pcall(step4().apply, { profile = p })
  BP.healer.name = healerName
  assertTrue(ok, tostring(err))
  assertNil(p.bandSets[1].origin, "two presets match: no origin is a guess")
  assertEqual(p.bandSets[2].origin, "paladin", "a unique match still lands")
end)

test("database: step 4 through the runner from v3, then a fresh profile's seed carries its origins", function()
  local p = { bandSets = { [1] = v3Set(NS.BandSetPresets.caster40.name) }, bandSetOrder = { 1 }, nextBandSetId = 2 }
  migrate({ profile = p, global = { schemaVersion = 3 } }, function(db)
    assertEqual(db.global.schemaVersion, 6, "stamped at v6, the ladder's top")
  end)
  assertEqual(p.bandSets[1].origin, "caster40", "the climb from v3 runs step 4")
  local fresh = {}
  migrate({ profile = fresh })
  assertTrue(#fresh.bandSetOrder > 0, "the load pass seeded the presets")
  for _, id in ipairs(fresh.bandSetOrder) do
    assertTrue(type(fresh.bandSets[id].origin) == "string", fresh.bandSets[id].name .. " was seeded with its origin")
  end
end)
